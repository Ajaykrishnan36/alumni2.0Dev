/**
 * @description Serves the portal Home dashboard widgets: upcoming approved
 *              events, upcoming alumni birthdays, and a limited feed of
 *              recent posts from the groups the current user has joined.
 *              Albums, businesses, spotlight and the invite link are reused
 *              from their existing controllers directly by the LWCs.
 */
public without sharing class KenPortalHomeController {

    private static final Integer EVENT_LIMIT = 3;
    private static final Integer BIRTHDAY_LIMIT = 4;
    private static final Integer BIRTHDAY_WINDOW_DAYS = 30;
    // Total rows after group and social posts are merged. Each source is queried
    // up to this many, so with 10 social posts a limit of 5 would fill the feed
    // with social alone and drop every group post - which defeats the mingling.
    private static final Integer FEED_LIMIT = 12;

    public class HomeEventRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        // An event is a day-granular container: Start_Date__c / End_Date__c and
        // no time of its own. Times belong to its sessions, which carry real
        // instants. So there is no instant to hand the component here, and none
        // is needed — a Date has no timezone, so formatting it server-side
        // cannot bake one in the way a DateTime would.
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String image;
    }

    public class HomeBirthdayRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String batch;
        @AuraEnabled public String program;
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String dayLabel;
        @AuraEnabled public String photoUrl;
    }


    public class HomeFeedRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String authorName;
        @AuraEnabled public String authorPhotoUrl;
        @AuraEnabled public String groupName;
        @AuraEnabled public String body;
        @AuraEnabled public String bodyText;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Boolean hasImage;
        @AuraEnabled public String platform;
        @AuraEnabled public String postUrl;
        /**
         * The moment the post was published - a group post's CreatedDate, or a
         * social post's Posted_At__c (NEVER the Salesforce created/synced date,
         * which is just when the row landed here). This is the single key the
         * mingled feed is ordered by.
         */
        @AuraEnabled public Datetime postedAt;
    }

    /** Orders the mingled feed newest-first on postedAt. */
    private class FeedSort implements Comparable {
        HomeFeedRow row;
        Datetime postedAt;
        public Integer compareTo(Object other) {
            FeedSort o = (FeedSort) other;
            if (postedAt == o.postedAt) return 0;
            if (postedAt == null) return 1;
            if (o.postedAt == null) return -1;
            return postedAt > o.postedAt ? -1 : 1;
        }
    }

    public class HomeData {
        @AuraEnabled public List<HomeEventRow> events;
        @AuraEnabled public List<HomeBirthdayRow> birthdays;
        @AuraEnabled public List<HomeFeedRow> feed;
    }

    @AuraEnabled(cacheable=true)
    public static HomeData getHomeData() {
        HomeData data = new HomeData();
        data.events = upcomingEvents();
        data.birthdays = upcomingBirthdays();
        data.feed = recentFeed();
        return data;
    }

    private static List<HomeEventRow> upcomingEvents() {
        List<HomeEventRow> rows = new List<HomeEventRow>();
        try {
            for (Ken_Event_Master__c ev : [
                SELECT Id, Name, Start_Date__c, Event_banner__c
                FROM Ken_Event_Master__c
                WHERE Event_Status__c = 'Approved'
                  AND Start_Date__c >= :Date.today()
                WITH SECURITY_ENFORCED
                ORDER BY Start_Date__c ASC
                LIMIT :EVENT_LIMIT
            ]) {
                HomeEventRow row = new HomeEventRow();
                row.id = ev.Id;
                row.title = ev.Name;
                row.dateLabel = buildEventDateLabel(ev.Start_Date__c);
                row.image = ev.Event_banner__c;
                rows.add(row);
            }
        } catch (Exception e) {
            return rows;
        }
        return rows;
    }

    /**
     * @description "dd MMM, yyyy" for an event's start day. No time part: an
     *              event is day-granular, and its sessions carry the clock.
     *
     *              Built from the Date's own components rather than a stored
     *              DateTime, so no timezone conversion can shift the day.
     */
    private static String buildEventDateLabel(Date startDate) {
        if (startDate == null) return null;
        return Datetime.newInstance(startDate.year(), startDate.month(), startDate.day()).format('dd MMM, yyyy');
    }



    /**
     * @description Whole days from today to the next occurrence of a birthday, so
     *              "upcoming" can be bounded by a real window. The previous key was
     *              month * 100 + day, which orders correctly but is NOT a day count,
     *              so nothing could be filtered by it - the card always showed the
     *              nearest four birthdays even when the next one was months away.
     *              A 29 Feb birthday falls back to 1 March in non-leap years.
     */
    private static Integer daysUntilNextBirthday(Date today, Date birthdate) {
        if (birthdate == null) return null;
        Integer m = birthdate.month();
        Integer d = birthdate.day();
        Date next = safeDate(today.year(), m, d);
        if (next == null) return null;
        if (next < today) {
            next = safeDate(today.year() + 1, m, d);
            if (next == null) return null;
        }
        return today.daysBetween(next);
    }

    private static Date safeDate(Integer year, Integer month, Integer day) {
        try {
            return Date.newInstance(year, month, day);
        } catch (Exception e) {
            try {
                return Date.newInstance(year, 3, 1);
            } catch (Exception fallbackFailed) {
                return null;
            }
        }
    }

    private static List<HomeBirthdayRow> upcomingBirthdays() {
        List<HomeBirthdayRow> rows = new List<HomeBirthdayRow>();
        try {
            List<Account> people = [
                SELECT Id, Name, PersonBirthdate, Profile_Photo_URL__c
                FROM Account
                WHERE IsPersonAccount = true AND PersonBirthdate != null
                WITH SECURITY_ENFORCED
                LIMIT 1000
            ];
            if (people.isEmpty()) return rows;

            Date today = Date.today();
            List<BirthdaySort> sortable = new List<BirthdaySort>();
            for (Account a : people) {
                Integer daysAway = daysUntilNextBirthday(today, a.PersonBirthdate);
                if (daysAway == null || daysAway > BIRTHDAY_WINDOW_DAYS) continue;
                BirthdaySort b = new BirthdaySort();
                b.acct = a;
                b.distance = daysAway;
                sortable.add(b);
            }
            if (sortable.isEmpty()) return rows;
            sortable.sort();

            Set<Id> pickedIds = new Set<Id>();
            List<Account> picked = new List<Account>();
            for (BirthdaySort b : sortable) {
                if (picked.size() >= BIRTHDAY_LIMIT) break;
                picked.add(b.acct);
                pickedIds.add(b.acct.Id);
            }

            Map<Id, ConstituentRole> roleByPerson = new Map<Id, ConstituentRole>();
            for (ConstituentRole cr : [
                SELECT PersonId, Graduation_Year__c, Program_Name__c, Program_Plan__r.LearningProgram.Name
                FROM ConstituentRole
                WHERE PersonId IN :pickedIds AND RoleType = 'Alumni'
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
            ]) {
                if (cr.PersonId != null && !roleByPerson.containsKey(cr.PersonId)) {
                    roleByPerson.put(cr.PersonId, cr);
                }
            }

            for (Account a : picked) {
                HomeBirthdayRow row = new HomeBirthdayRow();
                row.id = a.Id;
                row.name = a.Name;
                row.photoUrl = a.Profile_Photo_URL__c;
                Datetime bd = Datetime.newInstance(a.PersonBirthdate.year(), a.PersonBirthdate.month(), a.PersonBirthdate.day());
                row.monthLabel = bd.format('MMM');
                row.dayLabel = bd.format('dd');
                ConstituentRole cr = roleByPerson.get(a.Id);
                if (cr != null) {
                    row.batch = String.isNotBlank(cr.Graduation_Year__c) ? 'Batch ' + cr.Graduation_Year__c : null;
                    row.program = String.isNotBlank(cr.Program_Name__c)
                        ? cr.Program_Name__c
                        : (cr.Program_Plan__r != null && cr.Program_Plan__r.LearningProgram != null
                            ? cr.Program_Plan__r.LearningProgram.Name : null);
                }
                rows.add(row);
            }
        } catch (Exception e) {
            return rows;
        }
        return rows;
    }

    private class BirthdaySort implements Comparable {
        Account acct;
        Integer distance;
        public Integer compareTo(Object other) {
            BirthdaySort o = (BirthdaySort) other;
            return distance - o.distance;
        }
    }

    private static List<HomeFeedRow> recentGroupFeed() {
        List<HomeFeedRow> rows = new List<HomeFeedRow>();
        try {
            Id accountId = currentAccountId();
            if (accountId == null) return rows;

            Map<Id, String> groupNameById = new Map<Id, String>();
            for (Ken_Group_Member__c m : [
                SELECT Group__c, Group__r.Name
                FROM Ken_Group_Member__c
                WHERE Member__c = :accountId
                  AND Status__c IN ('Approved', 'Accepted')
                  AND Group__c != null
                WITH SECURITY_ENFORCED
                LIMIT 200
            ]) {
                groupNameById.put(m.Group__c, m.Group__r.Name);
            }
            if (groupNameById.isEmpty()) return rows;

            Set<Id> groupIds = groupNameById.keySet();
            List<FeedItem> posts = [
                SELECT Id, Body, CreatedDate, CreatedById, ParentId
                FROM FeedItem
                WHERE ParentId IN :groupIds
                  AND Type IN ('TextPost', 'ContentPost', 'LinkPost')
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT :FEED_LIMIT
            ];
            if (posts.isEmpty()) return rows;

            Set<Id> authorUserIds = new Set<Id>();
            for (FeedItem fi : posts) {
                if (fi.CreatedById != null) authorUserIds.add(fi.CreatedById);
            }
            Map<Id, User> userById = new Map<Id, User>([
                SELECT Id, Name, AccountId FROM User WHERE Id IN :authorUserIds
            WITH SYSTEM_MODE
            ]);
            Set<Id> authorAccountIds = new Set<Id>();
            for (User u : userById.values()) {
                if (u.AccountId != null) authorAccountIds.add(u.AccountId);
            }
            Map<Id, Account> authorAcctById = new Map<Id, Account>([
                SELECT Id, Name, Profile_Photo_URL__c FROM Account WHERE Id IN :authorAccountIds
            WITH SECURITY_ENFORCED
            ]);

            Set<Id> feedItemIds = new Set<Id>();
            Map<Id, String> bodyByFeedItem = new Map<Id, String>();
            for (FeedItem fi : posts) {
                feedItemIds.add(fi.Id);
                bodyByFeedItem.put(fi.Id, fi.Body);
            }
            Map<Id, List<KenGroupFeedController.AttachmentDTO>> attachmentsByFeedItem =
                KenGroupFeedService.lookupAttachments(feedItemIds, bodyByFeedItem);

            Map<Id, Id> inlineDocByFeedItem = new Map<Id, Id>();
            Pattern inlineImg = Pattern.compile('(?i)sfdc://(069[a-zA-Z0-9]{12,15})');
            for (FeedItem fi : posts) {
                if (String.isBlank(fi.Body)) continue;
                Matcher m = inlineImg.matcher(fi.Body);
                if (!m.find()) continue;
                try {
                    inlineDocByFeedItem.put(fi.Id, (Id) m.group(1));
                } catch (Exception ignored) {
                    continue;
                }
            }
            Map<Id, String> inlineImageUrls = KenGroupFeedService.lookupInlineImageUrls(
                KenGroupFeedService.extractInlineImageIds(bodyByFeedItem.values()));

            for (FeedItem fi : posts) {
                HomeFeedRow row = new HomeFeedRow();
                row.id = fi.Id;
                row.hasImage = false;
                Id inlineDocId = inlineDocByFeedItem.get(fi.Id);
                String inlineUrl = inlineDocId != null ? inlineImageUrls.get(inlineDocId) : null;
                if (String.isNotBlank(inlineUrl)) {
                    row.imageUrl = inlineUrl;
                    row.hasImage = true;
                }
                if (!row.hasImage) {
                    for (KenGroupFeedController.AttachmentDTO att : attachmentsByFeedItem.get(fi.Id) != null
                            ? attachmentsByFeedItem.get(fi.Id)
                            : new List<KenGroupFeedController.AttachmentDTO>()) {
                        if (att.isImage == true && String.isNotBlank(att.previewUrl)) {
                            row.imageUrl = att.previewUrl;
                            row.hasImage = true;
                            break;
                        }
                    }
                }
                row.groupName = groupNameById.get(fi.ParentId);
                // Rich HTML, not stripped text - the group feed renders formatting and
                // the home feed must match. Inline <img src="sfdc://..."> tags are removed
                // (empty map) because the picture is rendered separately from imageUrl;
                // leaving them would show it twice. Nothing is truncated server-side, so
                // "Show all" can genuinely show all - the old abbreviate(240) capped it.
                row.body = String.isBlank(fi.Body)
                    ? ''
                    : KenGroupFeedService.rewriteInlineImages(fi.Body, new Map<Id, String>());
                row.bodyText = String.isBlank(fi.Body) ? '' : fi.Body.stripHtmlTags();
                row.postedAt = fi.CreatedDate;
                row.dateLabel = fi.CreatedDate != null ? fi.CreatedDate.format('dd MMM yyyy, h:mm a') : null;
                User author = userById.get(fi.CreatedById);
                if (author != null) {
                    Account authorAcct = author.AccountId != null ? authorAcctById.get(author.AccountId) : null;
                    // The Person Account name wins over User.Name because these
                    // communities run with nickname display enabled, which makes
                    // User.Name come back as the auto-generated CommunityNickname
                    // ("User17890150349934689346") instead of the person's real name.
                    // Internal users have no Person Account and are not substituted,
                    // so User.Name remains the correct fallback for them.
                    row.authorName = (authorAcct != null && String.isNotBlank(authorAcct.Name))
                        ? authorAcct.Name
                        : author.Name;
                    if (authorAcct != null) row.authorPhotoUrl = authorAcct.Profile_Photo_URL__c;
                }
                rows.add(row);
            }
        } catch (Exception e) {
            return rows;
        }
        return rows;
    }

    /**
     * @description The home feed is group posts and social posts mingled, newest
     *              first. A social post is ordered by Posted_At__c - when it went
     *              live on the platform - not by when it was synced into Salesforce.
     */
    private static List<HomeFeedRow> recentFeed() {
        List<FeedSort> merged = new List<FeedSort>();
        merged.addAll(groupFeedEntries());
        merged.addAll(socialFeedEntries());
        merged.sort();

        List<HomeFeedRow> rows = new List<HomeFeedRow>();
        for (FeedSort entry : merged) {
            if (rows.size() >= FEED_LIMIT) break;
            rows.add(entry.row);
        }
        return rows;
    }

    private static List<FeedSort> groupFeedEntries() {
        List<FeedSort> entries = new List<FeedSort>();
        for (HomeFeedRow row : recentGroupFeed()) {
            FeedSort entry = new FeedSort();
            entry.row = row;
            entry.postedAt = row.postedAt;
            entries.add(entry);
        }
        return entries;
    }

    /**
     * @description Manually curated / synced social posts. Reads Ken_Alm_Integration_Settings__mdt
     *              directly for the public handle rather than going through
     *              KenSocialSync, so displaying the feed can never touch the
     *              fetch/schedule path.
     */
    private static List<FeedSort> socialFeedEntries() {
        List<FeedSort> entries = new List<FeedSort>();
        try {
            Map<String, String> handleByPlatform = new Map<String, String>();
            for (Ken_Alm_Integration_Settings__mdt cfg : [
                SELECT Service__c, Account_Handle__c FROM Ken_Alm_Integration_Settings__mdt
            WITH SYSTEM_MODE
            ]) {
                if (String.isNotBlank(cfg.Service__c) && String.isNotBlank(cfg.Account_Handle__c)) {
                    handleByPlatform.put(cfg.Service__c, cfg.Account_Handle__c);
                }
            }

            for (Ken_Social_Media_Post__c post : [
                SELECT Id, Platform__c, Title__c, Body__c, Media_Share_URL__c, Post_URL__c, Posted_At__c
                FROM Ken_Social_Media_Post__c
                WHERE Is_Active__c = true AND Posted_At__c != null
                WITH SECURITY_ENFORCED
                ORDER BY Posted_At__c DESC
                LIMIT :FEED_LIMIT
            ]) {
                HomeFeedRow row = new HomeFeedRow();
                row.id = post.Id;
                row.platform = post.Platform__c;
                row.postUrl = post.Post_URL__c;
                row.groupName = post.Platform__c;
                row.authorName = handleByPlatform.containsKey(post.Platform__c)
                    ? handleByPlatform.get(post.Platform__c)
                    : post.Platform__c;
                row.postedAt = post.Posted_At__c;
                row.dateLabel = post.Posted_At__c.format('dd MMM yyyy, h:mm a');
                row.imageUrl = post.Media_Share_URL__c;
                row.hasImage = String.isNotBlank(post.Media_Share_URL__c);

                String plain = joinNonBlank(post.Title__c, post.Body__c);
                row.bodyText = plain;
                row.body = toSafeHtml(plain);

                FeedSort entry = new FeedSort();
                entry.row = row;
                entry.postedAt = post.Posted_At__c;
                entries.add(entry);
            }
        } catch (Exception e) {
            return entries;
        }
        return entries;
    }

    private static String joinNonBlank(String title, String body) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(title)) parts.add(title.trim());
        if (String.isNotBlank(body)) parts.add(body.trim());
        return String.join(parts, '\n\n');
    }

    /**
     * @description A social body is plain text but the feed paints body as HTML, so
     *              it is escaped before newlines become paragraph breaks. Skipping
     *              the escape would let a caption containing "<" break the markup.
     */
    private static String toSafeHtml(String plain) {
        if (String.isBlank(plain)) return '';
        String escaped = plain.escapeHtml4();
        List<String> paragraphs = new List<String>();
        for (String chunk : escaped.split('\n{2,}')) {
            if (String.isBlank(chunk)) continue;
            paragraphs.add('<p>' + chunk.replace('\n', '<br/>') + '</p>');
        }
        return String.join(paragraphs, '');
    }
    @TestVisible
    private static Id testAccountId;

    private static Id currentAccountId() {
        if (Test.isRunningTest() && testAccountId != null) {
            return testAccountId;
        }
        List<User> users = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        return users.isEmpty() ? null : users[0].AccountId;
    }
}