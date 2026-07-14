/**
 * @description Controller for the V2 Home Dashboard (LWC: ken42AlumniHomeV2).
 *              Resolves current user → Person Account → Ken_Alumni_CRM__c,
 *              determines portal phase, and assembles dashboard state, action
 *              items, quick actions, and the home feed for the phase-based UI.
 *
 *              FLS hardening: every SOQL uses, and each
 *              read is wrapped in try/catch so partial failures degrade
 *              gracefully (empty lists) rather than blanking the home page.
 */
public with sharing class KenHomeController {

    private static final String PHASE_VERIFY  = 'Verify';
    private static final String PHASE_CONNECT = 'Connect';

    // ─────────────────────────────────────────────────────────────────────────
    //   WRAPPERS
    // ─────────────────────────────────────────────────────────────────────────

    public class DashboardStateDTO {
        @AuraEnabled public String phase;
        @AuraEnabled public Integer profileCompleteness;
        @AuraEnabled public String userFirstName;
        @AuraEnabled public String userLastName;
        @AuraEnabled public String batchLabel;
        @AuraEnabled public List<InsightPillDTO> insights;
    }

    public class InsightPillDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String icon;
        @AuraEnabled public String label;
        @AuraEnabled public String detail;
        @AuraEnabled public String targetUrl;
    }

    public class ActionItemDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public String ctaLabel;
        @AuraEnabled public String targetUrl;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public String severity;
        @AuraEnabled public Integer order;
    }

    public class QuickActionDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String icon;
        @AuraEnabled public String targetUrl;
        @AuraEnabled public String accentColor;
    }

    public class FeedItemDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String source;
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String displayTime;
        @AuraEnabled public Datetime occurredAt;
        @AuraEnabled public String targetUrl;
    }

    public class SpotlightDTO {
        @AuraEnabled public String eyebrow;
        @AuraEnabled public String personName;
        @AuraEnabled public String meta;
        @AuraEnabled public String quote;
        @AuraEnabled public String ctaLabel;
        @AuraEnabled public String secondaryCtaLabel;
        @AuraEnabled public String videoChip;
        @AuraEnabled public String videoTitle;
        @AuraEnabled public String videoMeta;
    }

    /**
     * Hero spotlight + video card content. Served from the active
     * Ken_Home_Spotlight__mdt record so admins can swap it each month without a
     * deploy. Falls back to a built-in default when no active record exists, so
     * the home never renders blank.
     */
    @AuraEnabled(cacheable=true)
    public static SpotlightDTO getSpotlight() {
        SpotlightDTO d = new SpotlightDTO();
        // Built-in fallback (used if no active CMDT record is present).
        d.eyebrow = 'MAY 2026 · SPOTLIGHT';
        d.personName = 'Priya Nambiar';
        d.meta = 'Batch 2013 · MCA · Group PM, Atlassian';
        d.quote = '"KU shaped how I think about products. Mentoring this year reminded me what made me curious in the first place."';
        d.ctaLabel = 'Read full story';
        d.secondaryCtaLabel = 'Nominate next month';
        d.videoChip = '▶ WATCH · 4 MIN';
        d.videoTitle = 'Why I came back to mentor.';
        d.videoMeta = 'Priya Nambiar · Batch 2013';
        try {
            List<Ken_Home_Spotlight__mdt> rows = [
                SELECT Eyebrow__c, Person_Name__c, Meta__c, Quote__c, CTA_Label__c,
                       Secondary_CTA_Label__c, Video_Chip__c, Video_Title__c, Video_Meta__c
                FROM Ken_Home_Spotlight__mdt
                WHERE Is_Active__c = true
                ORDER BY Sort_Order__c ASC NULLS LAST
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                Ken_Home_Spotlight__mdt s = rows[0];
                if (String.isNotBlank(s.Eyebrow__c))              d.eyebrow = s.Eyebrow__c;
                if (String.isNotBlank(s.Person_Name__c))          d.personName = s.Person_Name__c;
                if (String.isNotBlank(s.Meta__c))                 d.meta = s.Meta__c;
                if (String.isNotBlank(s.Quote__c))                d.quote = s.Quote__c;
                if (String.isNotBlank(s.CTA_Label__c))            d.ctaLabel = s.CTA_Label__c;
                if (String.isNotBlank(s.Secondary_CTA_Label__c))  d.secondaryCtaLabel = s.Secondary_CTA_Label__c;
                if (String.isNotBlank(s.Video_Chip__c))           d.videoChip = s.Video_Chip__c;
                if (String.isNotBlank(s.Video_Title__c))          d.videoTitle = s.Video_Title__c;
                if (String.isNotBlank(s.Video_Meta__c))           d.videoMeta = s.Video_Meta__c;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'KenHomeController.getSpotlight: ' + ex.getMessage());
        }
        return d;
    }

    // Internal context container — caches per-invocation lookups
    private class UserContext {
        Id userId;
        Id accountId;
        Id contactId;
        Account account;
        Ken_Alumni_CRM__c crm;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   PUBLIC: getUserDashboardState
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static DashboardStateDTO getUserDashboardState() {
        DashboardStateDTO state = new DashboardStateDTO();
        state.phase = PHASE_VERIFY;
        state.profileCompleteness = 0;
        state.userFirstName = '';
        state.userLastName  = '';
        state.batchLabel    = '';
        state.insights      = new List<InsightPillDTO>();

        UserContext ctx = resolveContext();
        if (ctx == null) {
            return state;
        }

        if (ctx.account != null) {
            state.userFirstName = ctx.account.FirstName;
            state.userLastName  = ctx.account.LastName;
        }

        if (ctx.crm != null) {
            String p = ctx.crm.Portal_Phase__c;
            state.phase = (p == PHASE_CONNECT) ? PHASE_CONNECT : PHASE_VERIFY;
            if (!String.isBlank(ctx.crm.Year_of_Graduation__c)) {
                state.batchLabel = 'Batch ' + ctx.crm.Year_of_Graduation__c;
            }
        }

        state.profileCompleteness = computeCompleteness(ctx);
        state.insights = buildInsights(ctx, state);
        return state;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   PUBLIC: getActionItems
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ActionItemDTO> getActionItems(String phase) {
        UserContext ctx = resolveContext();
        String resolvedPhase = (phase == PHASE_CONNECT) ? PHASE_CONNECT : PHASE_VERIFY;

        List<ActionItemDTO> items = (resolvedPhase == PHASE_CONNECT)
            ? buildConnectActionItems(ctx)
            : buildVerifyActionItems(ctx);

        items.sort(new ActionItemComparator());
        if (items.size() > 5) {
            List<ActionItemDTO> trimmed = new List<ActionItemDTO>();
            for (Integer i = 0; i < 5; i++) trimmed.add(items[i]);
            return trimmed;
        }
        return items;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   PUBLIC: getQuickActions
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<QuickActionDTO> getQuickActions(String phase) {
        String resolvedPhase = (phase == PHASE_CONNECT) ? PHASE_CONNECT : PHASE_VERIFY;
        List<QuickActionDTO> result = new List<QuickActionDTO>();

        if (resolvedPhase == PHASE_VERIFY) {
            result.add(qa('verify-profile',  'Complete profile',  '👤', '/my-profile',        '#6d28d9'));
            result.add(qa('verify-batch',    'Find batchmates',   '👥', '/network',           '#4f46e5'));
            result.add(qa('verify-invite',   'Invite classmates', '＋', '/network',           '#be123c'));
            result.add(qa('verify-events',   'Browse events',     '📅', '/events',            '#f59e0b'));
            result.add(qa('verify-groups',   'Discover groups',   '▤',  '/groups',            '#047857'));
            result.add(qa('verify-res',      'View resources',    '📚', '/resources',         '#0369a1'));
        } else {
            result.add(qa('connect-job',     'Post a job',        '💼', '/jobs?view=create',           '#047857'));
            result.add(qa('connect-mentor',  'Offer to mentor',   '💗', '/mentorship?action=become',   '#6d28d9'));
            result.add(qa('connect-event',   'Propose an event',  '📢', '/events?view=propose',        '#f59e0b'));
            result.add(qa('connect-give',    'Make a contribution', '🎁', '/giving',                   '#be123c'));
            result.add(qa('connect-disc',    'Start a discussion','💬', '/groups?action=post',         '#0369a1'));
            result.add(qa('connect-mile',    'Share a milestone', '🏆', '/feed?action=post',           '#3061FF'));
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   PUBLIC: getHomeFeed
    // ─────────────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<FeedItemDTO> getHomeFeed() {
        List<FeedItemDTO> all = new List<FeedItemDTO>();

        // EVENTS
        try {
            for (Ken_Event_Master__c e : [
                SELECT Id, Name, Start_Date__c, Location__c, Event_Type__c, CreatedDate
                FROM Ken_Event_Master__c
                WHERE Is_Active__c = true AND Event_Status__c = 'Approved'
               
                ORDER BY CreatedDate DESC
                LIMIT 5
            ]) {
                FeedItemDTO f = new FeedItemDTO();
                f.id = e.Id;
                f.source = 'EVENT';
                f.title = e.Name;
                f.subtitle = String.isBlank(e.Location__c) ? e.Event_Type__c : e.Location__c;
                f.occurredAt = e.CreatedDate;
                f.displayTime = relativeTime(e.CreatedDate);
                f.targetUrl = '/events?view=detail&id=' + e.Id;
                all.add(f);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'KenHomeController.getHomeFeed events: ' + ex.getMessage());
        }

        // GROUP FEED ITEMS
        try {
            List<Id> groupIds = new List<Id>();
            for (Ken_Group__c g : [SELECT Id FROM Ken_Group__c LIMIT 200]) {
                groupIds.add(g.Id);
            }
            if (!groupIds.isEmpty()) {
                for (FeedItem fi : [
                    SELECT Id, Title, Body, ParentId, CreatedDate
                    FROM FeedItem
                    WHERE ParentId IN :groupIds
                    ORDER BY CreatedDate DESC
                    LIMIT 5
                ]) {
                    FeedItemDTO f = new FeedItemDTO();
                    f.id = fi.Id;
                    f.source = 'GROUP';
                    f.title = String.isBlank(fi.Title)
                        ? (String.isBlank(fi.Body) ? 'Group update' : fi.Body.abbreviate(80))
                        : fi.Title;
                    f.subtitle = 'Group update';
                    f.occurredAt = fi.CreatedDate;
                    f.displayTime = relativeTime(fi.CreatedDate);
                    f.targetUrl = '/groups?view=detail&id=' + fi.ParentId;
                    all.add(f);
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'KenHomeController.getHomeFeed groups: ' + ex.getMessage());
        }

        // Sort merged list by occurredAt DESC
        all.sort(new FeedItemComparator());

        if (all.size() > 5) {
            List<FeedItemDTO> trimmed = new List<FeedItemDTO>();
            for (Integer i = 0; i < 5; i++) trimmed.add(all[i]);
            return trimmed;
        }
        return all;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   HELPERS — resolution
    // ─────────────────────────────────────────────────────────────────────────

    private static UserContext resolveContext() {
        UserContext ctx = new UserContext();
        ctx.userId = UserInfo.getUserId();
        try {
            List<User> users = [
                SELECT Id, AccountId, ContactId
                FROM User
                WHERE Id = :ctx.userId
               
                LIMIT 1
            ];
            if (users.isEmpty() || users[0].AccountId == null) {
                return ctx; // sysadmin / no portal mapping — phase=Verify default
            }
            ctx.accountId = users[0].AccountId;
            ctx.contactId = users[0].ContactId;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'KenHomeController.resolveContext user: ' + ex.getMessage());
            return ctx;
        }

        try {
            List<Account> accs = [
                SELECT Id, FirstName, LastName, PersonContactId, Linkedin_Profile_URL__c
                FROM Account
                WHERE Id = :ctx.accountId
               
                LIMIT 1
            ];
            if (!accs.isEmpty()) {
                ctx.account = accs[0];
                if (ctx.contactId == null) ctx.contactId = accs[0].PersonContactId;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'KenHomeController.resolveContext acc: ' + ex.getMessage());
        }

        try {
            List<Ken_Alumni_CRM__c> crms = [
                SELECT Id, Person_Account__c, Portal_Phase__c, Profile_Photo_URL__c,
                       Current_Company__c, Current_Location__c, Year_of_Graduation__c,
                       Specialization__c, Industry__c, Interests__c, Skills__c,
                       Program__c
                FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c = :ctx.accountId
               
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!crms.isEmpty()) ctx.crm = crms[0];
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'KenHomeController.resolveContext crm: ' + ex.getMessage());
        }
        return ctx;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   HELPERS — completeness, insights
    // ─────────────────────────────────────────────────────────────────────────

    private static Integer computeCompleteness(UserContext ctx) {
        // True, dynamic calculation over 8 weighted fields (each = 12.5%), read
        // from the user's actual Account + Ken_Alumni_CRM__c records:
        //   1. Name (First+Last)            5. City (Current_Location__c)
        //   2. LinkedIn (Account)           6. Graduation Year
        //   3. Photo (Profile_Photo_URL__c) 7. Industry
        //   4. Company (Current_Company__c) 8. Interests
        final Integer TOTAL = 8;
        Integer filled = 0;
        if (ctx.account != null) {
            if (!String.isBlank(ctx.account.FirstName) && !String.isBlank(ctx.account.LastName)) filled++;
            if (!String.isBlank(ctx.account.Linkedin_Profile_URL__c)) filled++;
        }
        if (ctx.crm != null) {
            if (!String.isBlank(ctx.crm.Profile_Photo_URL__c))    filled++;
            if (!String.isBlank(ctx.crm.Current_Company__c))      filled++;
            if (!String.isBlank(ctx.crm.Current_Location__c))     filled++;
            if (!String.isBlank(ctx.crm.Year_of_Graduation__c))   filled++;
            if (!String.isBlank(ctx.crm.Industry__c))             filled++;
            if (!String.isBlank(ctx.crm.Interests__c))            filled++;
        }
        return Math.min(100, (Integer) Math.round((filled * 100.0) / TOTAL));
    }

    private static List<InsightPillDTO> buildInsights(UserContext ctx, DashboardStateDTO state) {
        List<InsightPillDTO> pills = new List<InsightPillDTO>();

        if (state.phase == PHASE_VERIFY) {
            if (!String.isBlank(state.batchLabel)) {
                pills.add(pill('verify-batch', '✓', state.batchLabel + ' record matched', null, null));
            }
            Integer missing = 8 - (Integer) Math.floor((state.profileCompleteness / 100.0) * 8);
            if (missing > 0) {
                pills.add(pill('verify-confirm', '!', missing + ' details need confirmation',
                    null, '/my-profile'));
            }
            pills.add(pill('verify-pct', '👤', state.profileCompleteness + '% profile completion',
                null, '/my-profile'));
        } else {
            // CONNECT
            try {
                Integer openJobs = [
                    SELECT COUNT()
                    FROM Ken_Job_Master__c
                    WHERE Is_Closed__c = false AND Status__c = 'Open'
                   
                ];
                if (openJobs > 0) {
                    pills.add(pill('connect-jobs', '💼', openJobs + ' alumni hiring',
                        null, '/jobs'));
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'insights jobs: ' + ex.getMessage());
            }

            try {
                Date today = Date.today();
                Date weekEnd = today.addDays(7);
                List<Ken_Event_Master__c> evts = [
                    SELECT Id, Name, Start_Date__c
                    FROM Ken_Event_Master__c
                    WHERE Is_Active__c = true
                      AND Event_Status__c = 'Approved'
                      AND Start_Date__c >= :today AND Start_Date__c <= :weekEnd
                   
                    ORDER BY Start_Date__c ASC
                    LIMIT 1
                ];
                if (!evts.isEmpty()) {
                    pills.add(pill('connect-event', '📅', evts[0].Name + ' this week',
                        null, '/events?view=detail&id=' + evts[0].Id));
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'insights events: ' + ex.getMessage());
            }

            if (ctx.accountId != null) {
                try {
                    Integer pending = [
                        SELECT COUNT()
                        FROM Ken_Network_Connection__c
                        WHERE Recipient__c = :ctx.accountId AND Status__c = 'Requested'
                       
                    ];
                    if (pending > 0) {
                        pills.add(pill('connect-req', '👥', pending + ' new requests',
                            null, '/network?tab=requests'));
                    }
                } catch (Exception ex) {
                    System.debug(LoggingLevel.WARN, 'insights req: ' + ex.getMessage());
                }
            }
        }

        if (pills.size() > 3) {
            List<InsightPillDTO> top = new List<InsightPillDTO>();
            for (Integer i = 0; i < 3; i++) top.add(pills[i]);
            return top;
        }
        return pills;
    }

    private static InsightPillDTO pill(String id, String icon, String label, String detail, String targetUrl) {
        InsightPillDTO p = new InsightPillDTO();
        p.id = id; p.icon = icon; p.label = label; p.detail = detail; p.targetUrl = targetUrl;
        return p;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   HELPERS — Verify action items (checklist)
    // ─────────────────────────────────────────────────────────────────────────

    private static List<ActionItemDTO> buildVerifyActionItems(UserContext ctx) {
        List<ActionItemDTO> items = new List<ActionItemDTO>();
        Ken_Alumni_CRM__c crm = (ctx == null) ? null : ctx.crm;
        Account acc = (ctx == null) ? null : ctx.account;

        items.add(action('v-company', 'Add current company',
            'Helps batchmates find you',
            crm != null && !String.isBlank(crm.Current_Company__c),
            'Add', '/my-profile?edit=company', 'high', 1));

        items.add(action('v-linkedin', 'Add LinkedIn URL',
            'Auto-match with classmates',
            acc != null && !String.isBlank(acc.Linkedin_Profile_URL__c),
            'Add', '/my-profile?edit=linkedin', 'high', 2));

        items.add(action('v-city', 'Confirm current city',
            'So we can suggest local meetups',
            crm != null && !String.isBlank(crm.Current_Location__c),
            'Confirm', '/my-profile?edit=city', 'medium', 3));

        items.add(action('v-photo', 'Upload photo',
            'Required for your alumni ID',
            crm != null && !String.isBlank(crm.Profile_Photo_URL__c),
            'Upload', '/my-profile?edit=photo', 'medium', 4));

        items.add(action('v-about', 'Add interests',
            'Powers smart introductions',
            crm != null && !String.isBlank(crm.Interests__c),
            'Add', '/my-profile?tab=about', 'low', 5));

        // Achievements count
        Boolean hasAch = false;
        if (ctx != null && ctx.accountId != null) {
            try {
                Integer cnt = [
                    SELECT COUNT()
                    FROM Ken_Achievement__c
                    WHERE Person_Account__c = :ctx.accountId AND Is_Archived__c = false
                   
                ];
                hasAch = cnt > 0;
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'verify ach: ' + ex.getMessage());
            }
        }
        items.add(action('v-ach', 'Add achievements',
            'Tell your story',
            hasAch, 'Add', '/my-profile?section=achievements', 'low', 6));

        items.add(action('v-grad', 'Set graduation year',
            'Find your batch',
            crm != null && !String.isBlank(crm.Year_of_Graduation__c),
            'Set', '/my-profile', 'medium', 7));

        return items;
    }

    private static ActionItemDTO action(String id, String title, String descText,
            Boolean completed, String cta, String url, String severity, Integer ord) {
        ActionItemDTO a = new ActionItemDTO();
        a.id = id; a.title = title; a.description = descText;
        a.completed = completed; a.ctaLabel = cta; a.targetUrl = url;
        a.severity = severity; a.order = ord;
        return a;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   HELPERS — Connect action items (needs attention)
    // ─────────────────────────────────────────────────────────────────────────

    private static List<ActionItemDTO> buildConnectActionItems(UserContext ctx) {
        List<ActionItemDTO> items = new List<ActionItemDTO>();
        if (ctx == null) return items;

        // Pending connection requests
        if (ctx.accountId != null) {
            try {
                List<Ken_Network_Connection__c> reqs = [
                    SELECT Id, Initiator__c, Initiator__r.Name
                    FROM Ken_Network_Connection__c
                    WHERE Recipient__c = :ctx.accountId AND Status__c = 'Requested'
                   
                    ORDER BY Requested_Date__c DESC NULLS LAST
                    LIMIT 5
                ];
                Integer idx = 0;
                for (Ken_Network_Connection__c r : reqs) {
                    String who = (r.Initiator__r != null && r.Initiator__r.Name != null)
                        ? r.Initiator__r.Name : 'An alumnus';
                    items.add(action('c-net-' + r.Id, 'Connection request from ' + who,
                        'Review and respond',
                        false, 'Review', '/network?tab=requests&id=' + r.Id, 'high', 10 + idx));
                    idx++;
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'connect net: ' + ex.getMessage());
            }
        }

        // Mentorship pending (mentee request awaiting mentor decision — current user as mentor)
        if (ctx.accountId != null) {
            try {
                List<Ken_Mentorship__c> mts = [
                    SELECT Id, Meeting_Title__c, Mentee__r.Name, Mentorship_Status__c
                    FROM Ken_Mentorship__c
                    WHERE Mentor__c = :ctx.accountId
                      AND Mentorship_Status__c IN ('Pending', 'Requested')
                   
                    ORDER BY CreatedDate DESC
                    LIMIT 3
                ];
                Integer idx = 0;
                for (Ken_Mentorship__c m : mts) {
                    String menteeName = (m.Mentee__r != null && m.Mentee__r.Name != null)
                        ? m.Mentee__r.Name : 'a student';
                    items.add(action('c-mt-' + m.Id,
                        'Mentorship request from ' + menteeName,
                        String.isBlank(m.Meeting_Title__c) ? 'Awaiting your response' : m.Meeting_Title__c,
                        false, 'View', '/mentorship?id=' + m.Id, 'medium', 20 + idx));
                    idx++;
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'connect mentor: ' + ex.getMessage());
            }
        }

        // Open Tasks linked to user's Contact
        if (ctx.contactId != null) {
            try {
                List<Task> tasks = [
                    SELECT Id, Subject, ActivityDate, Priority
                    FROM Task
                    WHERE WhoId = :ctx.contactId
                      AND Status != 'Completed'
                      AND IsClosed = false
                   
                    ORDER BY ActivityDate ASC NULLS LAST
                    LIMIT 3
                ];
                Integer idx = 0;
                for (Task t : tasks) {
                    String sev = (t.Priority == 'High') ? 'high' : 'low';
                    String due = (t.ActivityDate == null) ? 'No due date'
                        : 'Due ' + t.ActivityDate.format();
                    items.add(action('c-tk-' + t.Id,
                        String.isBlank(t.Subject) ? 'Open task' : t.Subject,
                        due, false, 'Open', '/tasks?id=' + t.Id, sev, 30 + idx));
                    idx++;
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN, 'connect tasks: ' + ex.getMessage());
            }
        }

        // Survey responses due — surveys active for the user, not yet responded
        try {
            List<Ken_Survey__c> surveys = [
                SELECT Id, Name, End_Date__c
                FROM Ken_Survey__c
                WHERE Is_Active__c = true
                  AND Approval_Status__c = 'Approved'
               
                ORDER BY End_Date__c ASC NULLS LAST
                LIMIT 2
            ];
            Integer idx = 0;
            for (Ken_Survey__c s : surveys) {
                String due = (s.End_Date__c == null) ? 'Response requested'
                    : 'Closes ' + s.End_Date__c.format();
                items.add(action('c-sv-' + s.Id,
                    'Survey: ' + s.Name, due, false,
                    'Respond', '/surveys?id=' + s.Id, 'low', 40 + idx));
                idx++;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'connect survey: ' + ex.getMessage());
        }

        return items;
    }

    private static QuickActionDTO qa(String id, String label, String icon, String url, String accent) {
        QuickActionDTO q = new QuickActionDTO();
        q.id = id; q.label = label; q.icon = icon; q.targetUrl = url; q.accentColor = accent;
        return q;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   HELPERS — formatting
    // ─────────────────────────────────────────────────────────────────────────

    private static String relativeTime(Datetime dt) {
        if (dt == null) return '';
        Long deltaMs = System.now().getTime() - dt.getTime();
        if (deltaMs < 0) deltaMs = 0;
        Long mins = deltaMs / 60000L;
        if (mins < 60) return Math.max(1, mins) + 'm ago';
        Long hrs = mins / 60L;
        if (hrs < 24) return hrs + 'h ago';
        Long days = hrs / 24L;
        if (days < 7) return days + 'd ago';
        Long weeks = days / 7L;
        if (weeks < 5) return weeks + 'w ago';
        Long months = days / 30L;
        if (months < 12) return months + 'mo ago';
        return (days / 365L) + 'y ago';
    }

    // ─────────────────────────────────────────────────────────────────────────
    //   COMPARATORS
    // ─────────────────────────────────────────────────────────────────────────

    private class ActionItemComparator implements System.Comparator<ActionItemDTO> {
        public Integer compare(ActionItemDTO a, ActionItemDTO b) {
            Integer sa = severityScore(a.severity);
            Integer sb = severityScore(b.severity);
            if (sa != sb) return sb - sa; // high first
            Integer oa = (a.order == null) ? 999 : a.order;
            Integer ob = (b.order == null) ? 999 : b.order;
            return oa - ob;
        }
        private Integer severityScore(String s) {
            if (s == 'high') return 3;
            if (s == 'medium') return 2;
            if (s == 'low') return 1;
            return 0;
        }
    }

    private class FeedItemComparator implements System.Comparator<FeedItemDTO> {
        public Integer compare(FeedItemDTO a, FeedItemDTO b) {
            if (a.occurredAt == null && b.occurredAt == null) return 0;
            if (a.occurredAt == null) return 1;
            if (b.occurredAt == null) return -1;
            if (a.occurredAt > b.occurredAt) return -1;
            if (a.occurredAt < b.occurredAt) return 1;
            return 0;
        }
    }
}