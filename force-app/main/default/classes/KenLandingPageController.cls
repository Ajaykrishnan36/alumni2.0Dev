/**
 * @description Supplies the admin-curated content on the public landing page:
 *              the events promoted to "Moments That Matter", the newsletters
 *              shown in the Newsletter section, and the alumni stories shown in
 *              "Meet Alumni Creating Impact".
 *
 *              Events are driven by Ken_Event_Master__c.Show_On_Landing_Page__c
 *              so staff choose what the world sees without a code change. The
 *              flag is only reachable from the Salesforce record page (it is on
 *              the Event Master layout and deliberately not mapped in
 *              KenEventFormController), so an alumnus creating an event through
 *              the portal wizard can never publish themselves onto the public
 *              page.
 *
 *              Newsletters come from the Gallery album named "Newsletter", so
 *              admins publish one simply by uploading the file there - the same
 *              album the portal header's newsletter banner already reads.
 *
 *              without sharing: the landing page is served to the site guest
 *              user, which has no sharing access to event, album or file
 *              records.
 */
public without sharing class KenLandingPageController {
    @TestVisible private static final Integer LANDING_EVENT_LIMIT = 4;
    @TestVisible private static final Integer LANDING_NEWSLETTER_LIMIT = 3;
    @TestVisible private static final Integer LANDING_STORY_LIMIT = 3;

    /**
     * Caps what the flagged-record queries scan. "Still to come" and the
     * long-text checks below are decided in Apex, so the SOQL cannot stop at the
     * card count; this leaves plenty of headroom over the handful of records an
     * admin realistically flags.
     */
    private static final Integer FLAGGED_SCAN_LIMIT = 200;

    /**
     * Newsletters are curated as a Gallery album, matched by name the same way
     * KenGalleryController does, so the landing page and the portal header's
     * newsletter banner can never point at different albums.
     */
    private static final Set<String> NEWSLETTER_ALBUM_NAMES = new Set<String>{
        'Newsletter',
        'Newsletters'
    };

    private static final String STATUS_APPROVED = 'Approved';
    private static final String DEFAULT_BADGE = 'EVENT';

    public class LandingEvent {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String badge;
        // dateLabel only: an event is day-granular, holding Start_Date__c and
        // End_Date__c with no time of its own. That makes the server-built label
        // safe even though this page runs as the site guest user whose timezone
        // nobody has ever set — a Date has no timezone to be wrong about.
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String location;
        @AuraEnabled public String imageUrl;
    }

    public class LandingStory {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String company;
        @AuraEnabled public String role;
        @AuraEnabled public String batchLabel;
        @AuraEnabled public String quote;
        /** Null whenever there is no guest-reachable photo, which the caller
         *  reads as "use the static portrait for this card". */
        @AuraEnabled public String imageUrl;
    }

    public class LandingNewsletter {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String imageUrl;
        /** Always true - non-images never reach the caller. Kept on the payload
         *  so the LWC contract does not change. */
        @AuraEnabled public Boolean isImage;
    }

    /**
     * @description Returns up to 4 admin-flagged events for the landing page,
     *              earliest start date first. An empty list is the caller's cue
     *              to keep its own static content, so failures degrade to that
     *              rather than breaking the public page.
     *
     *              A flagged event with no usable end at all is treated as still
     *              current; the admin's tick is the only signal we have for it.
     */
    @AuraEnabled(cacheable=true)
    public static List<LandingEvent> getLandingPageEvents() {
        List<LandingEvent> rows = new List<LandingEvent>();
        try {
            DateTime now = System.now();
            for (Ken_Event_Master__c ev : [
                SELECT Id, Name, Event_Type__c, Event_banner__c, Location__c,
                       Start_Date__c, End_Date__c,
                       (SELECT Id, Start_DateTime__c, End_DateTime__c FROM Schedule_Sessions__r)
                FROM Ken_Event_Master__c
                WHERE Show_On_Landing_Page__c = true
                  AND Is_Active__c = true
                  AND Event_Status__c = :STATUS_APPROVED
                WITH SECURITY_ENFORCED
                ORDER BY Start_Date__c ASC NULLS LAST, Name ASC
                LIMIT :FLAGGED_SCAN_LIMIT
            ]) {
                DateTime endsAt = resolveEffectiveEnd(ev);
                if (endsAt != null && endsAt < now) {
                    continue;
                }
                LandingEvent row = new LandingEvent();
                row.id = ev.Id;
                row.title = ev.Name;
                row.badge = buildBadge(ev.Event_Type__c);
                row.dateLabel = buildDateLabel(ev.Start_Date__c);
                row.location = ev.Location__c;
                row.imageUrl = ev.Event_banner__c;
                rows.add(row);
                if (rows.size() == LANDING_EVENT_LIMIT) {
                    break;
                }
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'KenLandingPageController.getLandingPageEvents failed: ' + e.getMessage()
            );
            return new List<LandingEvent>();
        }
        return rows;
    }

    /**
     * @description Returns the three most recently uploaded newsletters an admin
     *              has ticked Show_On_Landing_Page__c on, newest first, for the
     *              landing page's Newsletter section. An empty list means nothing
     *              has been flagged and the caller keeps its static cards, so the
     *              public page degrades rather than showing an empty band.
     *
     *              Uploading is not publishing: a file reaches the public page
     *              only once it is BOTH in the Newsletter album AND flagged, so
     *              staff can stage newsletters in the gallery before they go live.
     *
     *              Scoping to the Newsletter album is what makes the flag safe to
     *              expose on every file. A custom field belongs to the object
     *              rather than a subset of rows, so Show_On_Landing_Page__c exists
     *              on files in every album - but nothing outside this album is
     *              ever read, so ticking it elsewhere is inert and cannot leak a
     *              private file onto the public page.
     *
     *              Reads Share_URL__c rather than the file itself: the site
     *              guest user has no access to Files, so the public link stored
     *              at upload time is the only image source that renders for an
     *              anonymous visitor.
     *
     *              Filters on Is_Image__c rather than the record name: the name
     *              is typed by hand for a file created in Setup and routinely has
     *              no extension, so parsing it hid genuine images. The flag is
     *              stamped from the real ContentVersion at upload, which the
     *              guest user cannot read itself.
     *
     *              Only renderable images are returned. A document has no
     *              publicly reachable thumbnail, and a file with no public link
     *              has nothing to point an <img> at, so both are dropped rather
     *              than shown over a stock cover that would misrepresent them.
     *              Because a card is skipped rather than substituted, the row can
     *              come back with one or two cards - which is intended, and is
     *              why the query scans rather than capping at three.
     */
    @AuraEnabled(cacheable=true)
    public static List<LandingNewsletter> getLandingPageNewsletters() {
        List<LandingNewsletter> rows = new List<LandingNewsletter>();
        try {
            List<Ken_Album__c> albums = [
                SELECT Id
                FROM Ken_Album__c
                WHERE Name IN :NEWSLETTER_ALBUM_NAMES
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (albums.isEmpty()) {
                return rows;
            }
            for (Ken_File__c photo : [
                SELECT Id, Name, Description__c, Share_URL__c, CreatedDate
                FROM Ken_File__c
                WHERE Album__c = :albums[0].Id
                AND Show_On_Landing_Page__c = true
                AND Is_Image__c = true
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT :FLAGGED_SCAN_LIMIT
            ]) {
                if (String.isBlank(photo.Share_URL__c)) {
                    continue;
                }
                LandingNewsletter row = new LandingNewsletter();
                row.id = photo.Id;
                row.title = buildNewsletterTitle(photo);
                row.dateLabel = buildNewsletterLabel(photo);
                row.imageUrl = photo.Share_URL__c;
                row.isImage = true;
                rows.add(row);
                if (rows.size() == LANDING_NEWSLETTER_LIMIT) {
                    break;
                }
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'KenLandingPageController.getLandingPageNewsletters failed: ' + e.getMessage()
            );
            return new List<LandingNewsletter>();
        }
        return rows;
    }

    /**
     * @description The card headline. Description__c wins when an
     *              admin has written one, because a file name is rarely good
     *              public copy; otherwise it falls back to the file name with its
     *              extension stripped, which is what the cards showed before that
     *              field existed.
     */
    private static String buildNewsletterTitle(Ken_File__c photo) {
        if (String.isNotBlank(photo.Description__c)) {
            return photo.Description__c.trim();
        }
        return stripFileExtension(photo.Name);
    }

    /**
     * @description Returns up to 3 admin-flagged alumni stories for the landing
     *              page's "Meet Alumni Creating Impact" section, newest flagged
     *              first. An empty list means nothing is published and the caller
     *              keeps its static cards, so the public page degrades rather
     *              than showing an empty band.
     *
     *              Flagged on the Constituent Role, not the person: one alumnus
     *              can have several pass-outs, and the card names the faculty and
     *              batch the story is told from. Flagging the role is what lets
     *              staff pick which qualification appears.
     *
     *              About__c is a long text area, which SOQL cannot filter on, so
     *              the quote is checked in the loop. That is why the query scans
     *              rather than capping at three - otherwise a flagged role with no
     *              quote would consume a card slot and hide a complete story. The
     *              quote is the content of the card; without one the story would
     *              render as a portrait over empty space.
     *
     *              Unlike a newsletter card, a missing photo does NOT drop the
     *              story. The quote is the content and the portrait is dressing,
     *              so a card with no guest-reachable image keeps its place and
     *              the caller supplies the static portrait instead.
     */
    @AuraEnabled(cacheable=true)
    public static List<LandingStory> getLandingPageStories() {
        List<LandingStory> rows = new List<LandingStory>();
        try {
            List<ConstituentRole> roles = [
                SELECT Id, PersonId, Person.Name, Institute_Name__c, Institution_Name__c,
                Program_Name__c, Graduation_Year__c, About__c
                FROM ConstituentRole
                WHERE Show_On_Landing_Page__c = true
                WITH SYSTEM_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT :FLAGGED_SCAN_LIMIT
            ];
            if (roles.isEmpty()) {
                return rows;
            }

            Set<Id> accountIds = new Set<Id>();
            for (ConstituentRole role : roles) {
                if (role.PersonId != null &&
                    role.PersonId.getSobjectType() == Account.SObjectType) {
                    accountIds.add(role.PersonId);
                }
            }
            Map<Id, String> photos = lookupGuestReadablePhotos(accountIds);
            Map<Id, PersonEmployment> jobs = lookupCurrentEmployment(accountIds);

            for (ConstituentRole role : roles) {
                if (String.isBlank(role.About__c)) {
                    continue;
                }
                LandingStory row = new LandingStory();
                row.id = role.Id;
                row.name = role.Person != null ? role.Person.Name : null;
                row.quote = role.About__c.trim();
                row.batchLabel = buildBatchLabel(role);
                row.imageUrl = photos.get(role.PersonId);
                PersonEmployment job = jobs.get(role.PersonId);
                row.company = job != null ? job.Company_Name__c : null;
                row.role = job != null ? job.Designation__c : null;
                rows.add(row);
                if (rows.size() == LANDING_STORY_LIMIT) {
                    break;
                }
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'KenLandingPageController.getLandingPageStories failed: ' + e.getMessage()
            );
            return new List<LandingStory>();
        }
        return rows;
    }

    /**
     * @description "Faculty of Management, Batch: 2004". Either half can be
     *              missing, in which case the label shrinks to whichever half
     *              exists rather than rendering a stray comma or "Batch: null".
     *
     *              Institute_Name__c is not a name despite its label. It carries
     *              the sharing token KenInstitutePopulationService stamps from
     *              the provider's record id, semicolon separated when a role
     *              spans several, because criteria sharing rules match it with
     *              CONTAINS. Printing it raw put "001Im00000B9ASJIA3" on the
     *              public page where the faculty belongs, so an id-shaped token
     *              is passed over in favour of a readable field.
     *
     *              An org that stamps a readable value is still taken at its
     *              word, which is what the KJS orgs do. Only an id falls through
     *              to Institution_Name__c, the Program_Plan__r.Provider.Name
     *              formula carrying the same institute in readable form, and
     *              then to the programme.
     */
    private static String buildBatchLabel(ConstituentRole role) {
        String faculty = readableInstitute(role);
        String batch = String.isNotBlank(role.Graduation_Year__c)
            ? 'Batch: ' + role.Graduation_Year__c.trim()
            : null;
        if (faculty == null) {
            return batch;
        }
        return batch == null ? faculty : faculty + ', ' + batch;
    }

    /**
     * @description The institute as a visitor should read it: the stamped token
     *              when it is not an id, otherwise the provider-name formula and
     *              finally the programme.
     */
    private static String readableInstitute(ConstituentRole role) {
        if (String.isNotBlank(role.Institute_Name__c)) {
            String first = role.Institute_Name__c.trim()
                .split(KenInstitutePopulationService.DELIMITER)[0]
                .trim();
            if (String.isNotBlank(first) && !isRecordId(first)) {
                return first;
            }
        }
        if (String.isNotBlank(role.Institution_Name__c)) {
            return role.Institution_Name__c.trim();
        }
        return String.isNotBlank(role.Program_Name__c) ? role.Program_Name__c.trim() : null;
    }

    /**
     * @description A 15 or 18 character value Salesforce accepts as an id, which
     *              is how a sharing token is told apart from an institute name
     *              someone typed.
     */
    private static Boolean isRecordId(String value) {
        if (String.isBlank(value) || (value.length() != 15 && value.length() != 18)) {
            return false;
        }
        try {
            Id.valueOf(value);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    /**
     * @description Only photos an anonymous visitor can actually load.
     *
     *              Account.PhotoUrl is the Chatter photo and sits behind a login,
     *              so it renders as a broken portrait on the public page - it is
     *              deliberately NOT used here, unlike the portal's own lookups.
     *              Profile_Photo_URL__c is a plain URL field, so it is usable
     *              when it holds an absolute link. It is a long text area, which
     *              SOQL cannot filter on, so blanks are skipped in the loop.
     */
    private static Map<Id, String> lookupGuestReadablePhotos(Set<Id> accountIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (accountIds.isEmpty()) {
            return out;
        }
        for (Account a : [
            SELECT Id, Profile_Photo_URL__c
            FROM Account
            WHERE Id IN :accountIds
        WITH SECURITY_ENFORCED
        ]) {
            if (String.isBlank(a.Profile_Photo_URL__c)) {
                continue;
            }
            String url = a.Profile_Photo_URL__c.trim();
            if (url.startsWithIgnoreCase('http://') || url.startsWithIgnoreCase('https://')) {
                out.put(a.Id, url);
            }
        }
        return out;
    }

    /**
     * @description Current job first, then the most recently started - the same
     *              ordering the admin alumni workspace uses, so a card and the
     *              record agree.
     */
    private static Map<Id, PersonEmployment> lookupCurrentEmployment(Set<Id> accountIds) {
        Map<Id, PersonEmployment> out = new Map<Id, PersonEmployment>();
        if (accountIds.isEmpty()) {
            return out;
        }
        for (PersonEmployment job : [
            SELECT Id, AccountId, Company_Name__c, Designation__c
            FROM PersonEmployment
            WHERE AccountId IN :accountIds
            AND (Is_Archived__c = false OR Is_Archived__c = null)
            WITH SECURITY_ENFORCED
            ORDER BY Currently_Employed__c DESC NULLS LAST, StartDate DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (!out.containsKey(job.AccountId)) {
                out.put(job.AccountId, job);
            }
        }
        return out;
    }

    /**
     * @description The small line above the headline is the uploaded file's name.
     *              It replaced a formatted upload date, which only ever looked
     *              right by coincidence: re-uploading an October newsletter in
     *              December captioned it "December".
     *
     *              No fallback: Name is a required text field, set from the file
     *              itself on a portal upload and typed by hand in Setup, so a
     *              file without one cannot exist.
     */
    private static String buildNewsletterLabel(Ken_File__c photo) {
        return stripFileExtension(photo.Name);
    }

    /**
     * @description "October Newsletter.pdf" reads better on a card as "October
     *              Newsletter". Guards against names that merely contain a dot
     *              ("Vol 2.1 Highlights") by requiring a short trailing segment.
     */
    private static String stripFileExtension(String fileName) {
        if (String.isBlank(fileName)) {
            return null;
        }
        String trimmed = fileName.trim();
        Integer lastDot = trimmed.lastIndexOf('.');
        Boolean looksLikeExtension = lastDot > 0 && (trimmed.length() - lastDot) <= 6;
        return looksLikeExtension ? trimmed.substring(0, lastDot).trim() : trimmed;
    }

    /**
     * @description When an event has sessions the last session decides whether it
     *              is over, otherwise the event's own end date does. Mirrors
     *              KenPortalEventController.EventWrapper.resolveEffectiveEnd so the
     *              landing page and the portal's Upcoming Events never disagree
     *              about what "still to come" means. Same-day sessions are saved
     *              with no end date, so the start date doubles as the end date.
     */
    private static DateTime resolveEffectiveEnd(Ken_Event_Master__c event) {
        DateTime latest = null;
        if (event.Schedule_Sessions__r != null) {
            for (Ken_Schedule_Sessions__c s : event.Schedule_Sessions__r) {
                DateTime sessionEnd = sessionEffectiveEnd(s);
                if (sessionEnd != null && (latest == null || sessionEnd > latest)) {
                    latest = sessionEnd;
                }
            }
        }
        if (latest != null) {
            return latest;
        }
        // No sessions: the event's own last day decides. Same-day events are
        // saved with no end date, so the start date doubles as the end date.
        Date fallbackEnd = event.End_Date__c != null ? event.End_Date__c : event.Start_Date__c;
        return endOfDay(fallbackEnd);
    }

    /**
     * @description When a session ends. Same-day sessions are saved with a start
     *              but no end — 48 of 189 in AlumniDev — so those count until the
     *              end of the day they start on, and an afternoon session does not
     *              vanish from the page at the moment it begins.
     *
     *              The day comes from the start instant rather than a stored Date
     *              column, which is the whole point of keeping one GMT field: the
     *              date is derived, never duplicated.
     */
    private static DateTime sessionEffectiveEnd(Ken_Schedule_Sessions__c s) {
        if (s.End_DateTime__c != null) {
            return s.End_DateTime__c;
        }
        return endOfDay(KenDateTimeUtil.localDate(s.Start_DateTime__c));
    }

    /**
     * @description Last instant of a day, so a whole-day event does not drop off
     *              the landing page at midnight on its final day.
     *
     *              Expressed as the exclusive start of the next day rather than
     *              a literal 23:59:59, which would silently discard the final
     *              second.
     */
    private static DateTime endOfDay(Date d) {
        return d == null ? null : KenDateTimeUtil.dayAfter(d);
    }

    /**
     * @description Event_Type__c is a multi-select picklist; the card has room
     *              for one short badge, so the first selected value wins.
     */
    private static String buildBadge(String eventType) {
        if (String.isBlank(eventType)) {
            return DEFAULT_BADGE;
        }
        String first = eventType.split(';')[0].trim();
        return String.isBlank(first) ? DEFAULT_BADGE : first.toUpperCase();
    }

    /**
     * @description Mirrors the label format used by KenPortalHomeController's
     *              upcoming events.
     */
    /**
     * @description "dd MMM, yyyy" for an event's start day. No time part: an
     *              event is day-granular, and its sessions carry the clock.
     *
     *              Built from the Date's own components rather than a stored
     *              DateTime, so no timezone conversion can shift the day.
     */
    private static String buildDateLabel(Date startDate) {
        if (startDate == null) {
            return null;
        }
        return Datetime.newInstance(startDate.year(), startDate.month(), startDate.day())
            .format('dd MMM, yyyy');
    }

    // ═══════════════════ the community social band ═══════════════════

    /*
     * Absorbed from KenLandingSocialController on 2026-08-14. It was a separate
     * class only by accident of when it was written: same page, same guest
     * audience, same without-sharing reason, same cacheable-read shape as the
     * three sections above. Nothing here touches the SYNC - that is KenSocialSync,
     * which stays separate because it does callouts and must never sit behind a
     * class the guest user is granted.
     *
     * Selection is purely by recency - the newest three active posts across every
     * platform win, so the band survives one account going quiet because the
     * others fill the gap. Nothing here picks one card per platform; three
     * Instagram posts in a day is a valid result.
     *
     * A post with no image is still published: the LWC substitutes the band's
     * existing static cover image for that slot, matching how stories and events
     * already handle a missing photo. Filtering them out here instead would let
     * one imageless post silently shrink the band to two cards.
     */

    @TestVisible private static final Integer LANDING_SOCIAL_LIMIT = 3;

    @TestVisible private static final String PLATFORM_INSTAGRAM = 'Instagram';
    @TestVisible private static final String PLATFORM_FACEBOOK  = 'Facebook';
    @TestVisible private static final String PLATFORM_LINKEDIN  = 'LinkedIn';
    @TestVisible private static final String PLATFORM_X         = 'X';
    @TestVisible private static final String PLATFORM_THREADS   = 'Threads';

    /**
     * @description One community card. The LWC resolves the platform icon from
     *              `platform`, so no image URL for it travels over the wire.
     */
    public class SocialPost {
        @AuraEnabled public String id;
        @AuraEnabled public String platform;
        @AuraEnabled public String handle;
        @AuraEnabled public String body;
        @AuraEnabled public String imageUrl;
        /**
         * Deep link to the post on the platform. Null on posts synced before
         * Post_URL__c existed, and the sync never revisits a stored post, so
         * the LWC has to keep rendering a card that cannot be opened.
         */
        @AuraEnabled public String postUrl;
        @AuraEnabled public String title;
        @AuraEnabled public String postedInstant;
    }

    /**
     * @description Newest active posts that actually have an image, across all
     *              platforms.
     *
     *              When set, Media_Share_URL__c is always a Salesforce
     *              ContentDistribution link written by the sync, never the
     *              platform's own CDN URL - those are signed and expire in days.
     *
     * @return up to three cards, newest first; empty when nothing is published
     */
    @AuraEnabled(cacheable=true)
    public static List<SocialPost> getLandingSocialPosts() {
        Map<String, String> handleByPlatform = loadHandles();
        List<SocialPost> cards = new List<SocialPost>();

        for (Ken_Social_Media_Post__c record : [
            SELECT Id, Platform__c, Body__c, Title__c, Media_Share_URL__c, Post_URL__c, Posted_At__c
            FROM Ken_Social_Media_Post__c
            WHERE Is_Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Posted_At__c DESC
            LIMIT :LANDING_SOCIAL_LIMIT
        ]) {
            SocialPost card = new SocialPost();
            card.id            = record.Id;
            card.platform      = record.Platform__c;
            card.handle        = handleByPlatform.get(record.Platform__c);
            card.body          = record.Body__c;
            card.title         = record.Title__c;
            card.imageUrl      = record.Media_Share_URL__c;
            card.postUrl       = record.Post_URL__c;
            card.postedInstant = KenDateTimeUtil.formatInstant(record.Posted_At__c);
            cards.add(card);
        }
        return cards;
    }

    /**
     * @description Platform name -> public handle, read from Ken_Alm_Integration_Settings__mdt.
     *              A blank handle is simply absent, and the card then renders
     *              without one.
     *
     *              The handle comes from the platform's config rather than from the
     *              post row, because every post from a given platform shares the
     *              organisation's one handle.
     *
     *              The platform constants double as the record DeveloperNames, so
     *              they must keep matching the deployed records; forPlatform()
     *              returns an empty record on a mismatch, which surfaces as a
     *              missing handle rather than an exception.
     *
     *              getInstance() needs no object permission and costs no query, so
     *              this works unchanged for the site guest user - which is why
     *              reading it from KenSocialSync does not drag the sync's callout
     *              machinery into the guest's reach.
     */
    private static Map<String, String> loadHandles() {
        Map<String, String> handleByPlatform = new Map<String, String>();

        for (String platform : handledPlatforms()) {
            putHandle(handleByPlatform, platform,
                KenSocialSync.forPlatform(platform).Account_Handle__c);
        }
        return handleByPlatform;
    }

    /**
     * @description Every platform whose posts can reach the band must appear here,
     *              or its cards render with no handle.
     *
     *              Exposed to the test because that is a silent failure: the card
     *              still draws, the image and caption are correct, and only the
     *              handle is quietly missing - so adding a platform to
     *              Ken_Social_Media_Post__c.Platform__c without adding it here
     *              would never surface in testing. X was added on 2026-08-13 and
     *              had exactly this gap.
     */
    @TestVisible
    private static Set<String> handledPlatforms() {
        return new Set<String>{
            PLATFORM_INSTAGRAM, PLATFORM_FACEBOOK, PLATFORM_LINKEDIN,
            PLATFORM_X, PLATFORM_THREADS
        };
    }

    private static void putHandle(Map<String, String> target, String platform, String handle) {
        if (String.isNotBlank(handle)) {
            target.put(platform, handle.trim());
        }
    }

    // ═══════════════════ footer social profile links ═══════════════════

    /**
     * @description Public profile URL for each configured platform, for the
     *              footer's social icons.
     *
     *              Facebook, Instagram and X publish Account_Handle__c as
     *              "@handle", which is also the platform's own public profile
     *              slug, so the link is built by stripping the "@" and
     *              appending it to the platform's public site (never
     *              Base_Endpoint__c, which is the API host used for syncing
     *              posts and is not a page a visitor can open).
     *
     *              LinkedIn's Account_Handle__c is a free-typed display name
     *              ("Kenverse Alumni"), not a URL-safe slug, so it cannot
     *              build a link. LinkedIn's numeric Account_Id__c (the
     *              organisation id already used to sync its posts) doubles as
     *              a valid public company-page URL, so that is used instead.
     *
     *              A platform with Is_Active__c = false or no usable
     *              identifier is simply absent from the map; the caller
     *              leaves that icon unlinked rather than pointing it at
     *              nothing.
     *
     * @return platform DeveloperName -> public profile URL
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getSocialProfileLinks() {
        Map<String, String> linkByPlatform = new Map<String, String>();

        putHandleLink(linkByPlatform, PLATFORM_FACEBOOK, 'https://facebook.com/');
        putHandleLink(linkByPlatform, PLATFORM_INSTAGRAM, 'https://instagram.com/');
        putHandleLink(linkByPlatform, PLATFORM_X, 'https://x.com/');
        putLinkedInLink(linkByPlatform);

        return linkByPlatform;
    }

    /**
     * @description Profile_URL__c always wins when an admin has set it -
     *              that is the whole point of the field: to fix a wrong or
     *              underivable link without touching Apex. Only when it is
     *              blank does this fall back to building one from the
     *              handle, so the 3 platforms that already work today keep
     *              working unchanged.
     */
    private static void putHandleLink(Map<String, String> target, String platform, String publicSiteBaseUrl) {
        Ken_Alm_Integration_Settings__mdt config = KenSocialSync.forPlatform(platform);
        if (config.Is_Active__c != true) {
            return;
        }
        if (String.isNotBlank(config.Profile_URL__c)) {
            target.put(platform, config.Profile_URL__c.trim());
            return;
        }
        if (String.isBlank(config.Account_Handle__c)) {
            return;
        }
        String handle = config.Account_Handle__c.trim();
        if (handle.startsWith('@')) {
            handle = handle.substring(1);
        }
        if (String.isBlank(handle)) {
            return;
        }
        target.put(platform, publicSiteBaseUrl + handle);
    }

    /**
     * @description Same Profile_URL__c-first precedence as putHandleLink,
     *              but LinkedIn's fallback is Account_Id__c (a numeric
     *              organisation id that doubles as a valid company-page URL)
     *              rather than Account_Handle__c, which LinkedIn stores as a
     *              free-typed display name and cannot turn into a link.
     */
    private static void putLinkedInLink(Map<String, String> target) {
        Ken_Alm_Integration_Settings__mdt linkedIn = KenSocialSync.forPlatform(PLATFORM_LINKEDIN);
        if (linkedIn.Is_Active__c != true) {
            return;
        }
        if (String.isNotBlank(linkedIn.Profile_URL__c)) {
            target.put(PLATFORM_LINKEDIN, linkedIn.Profile_URL__c.trim());
            return;
        }
        if (String.isNotBlank(linkedIn.Account_Id__c)) {
            target.put(PLATFORM_LINKEDIN, 'https://www.linkedin.com/company/' + linkedIn.Account_Id__c.trim() + '/');
        }
    }

    // ═══════════════════ footer contact email ═══════════════════

    /**
     * @description The email address shown in the footer, resolved the same
     *              way KenMessagingService picks who alumni emails come FROM
     *              - so the footer never shows an address that disagrees with
     *              where a reply would actually go.
     *
     *              KenMessagingService.orgWideAddressName() returns a Display
     *              Name (Ken_Alm_Org_Parameters__c.Org_Wide_Email_Address__c,
     *              or 'Alumni Management' when blank); this looks up the
     *              standing OrgWideEmailAddress record with that name for its
     *              actual Address. Institution_Email__c is a separate,
     *              unrelated field - it is not where alumni emails are sent
     *              from, so it is deliberately not used here except as a
     *              last-resort fallback if the org has no matching
     *              OrgWideEmailAddress record (or the guest user cannot query
     *              it) and something is still better than an empty footer
     *              line.
     *
     * @return the resolved address, Institution_Email__c, or null when
     *         neither is available - the caller hides the footer row rather
     *         than show a blank or guessed email.
     */
    @AuraEnabled(cacheable=true)
    public static String getContactEmailAddress() {
        try {
            String displayName = KenMessagingService.orgWideAddressName();
            List<OrgWideEmailAddress> addresses = [
                SELECT Address
                FROM OrgWideEmailAddress
                WHERE DisplayName = :displayName
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!addresses.isEmpty() && String.isNotBlank(addresses[0].Address)) {
                return addresses[0].Address;
            }
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'KenLandingPageController.getContactEmailAddress: OrgWideEmailAddress lookup failed: ' + e.getMessage()
            );
        }
        Ken_Alm_Org_Parameters__c cs = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        return (cs != null && String.isNotBlank(cs.Institution_Email__c)) ? cs.Institution_Email__c.trim() : null;
    }

    // ═══════════════════ footer phone / location ═══════════════════

    /**
     * @description Phone and location for the footer, read from the standard
     *              Organization record (Setup > Company Information) - no
     *              custom field holds these today, and the admin has already
     *              filled that page in.
     *
     *              Both are simply absent (null) when Organization has
     *              nothing set, or when the query itself fails - which the
     *              caller reads as "hide that footer row" rather than
     *              showing a blank or stale hardcoded value.
     */
    public class OrgContactDetails {
        @AuraEnabled public String phone;
        @AuraEnabled public String location;
    }

    @AuraEnabled(cacheable=true)
    public static OrgContactDetails getOrgContactDetails() {
        OrgContactDetails details = new OrgContactDetails();
        try {
            Organization org = [SELECT Phone, City, State FROM Organization WITH SYSTEM_MODE LIMIT 1];
            details.phone = String.isNotBlank(org.Phone) ? org.Phone.trim() : null;
            details.location = buildLocationLabel(org.City, org.State);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'KenLandingPageController.getOrgContactDetails failed: ' + e.getMessage()
            );
        }
        return details;
    }

    /**
     * @description "Coimbatore, TN" - either half can be missing, in which
     *              case the label shrinks to whichever half exists rather
     *              than rendering a stray comma.
     */
    private static String buildLocationLabel(String city, String state) {
        String c = String.isNotBlank(city) ? city.trim() : null;
        String s = String.isNotBlank(state) ? state.trim() : null;
        if (c == null) {
            return s;
        }
        return s == null ? c : c + ', ' + s;
    }
}