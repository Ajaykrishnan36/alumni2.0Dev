public without sharing class KenNotificationFactory {

    private static final Pattern MERGE_PATTERN = Pattern.compile('\\{!([A-Za-z0-9_\\.]+)\\}');

    public class Context {
        public Id recipientAccountId;
        public Id senderAccountId;
        public Id sourceRecordId;   // substitutes the {!Id} placeholder in the template's Target_Url__c
        public Map<String, String> extras;

        public Context() {}

        public Context(Id recipient, Id sender, Id source) {
            this.recipientAccountId = recipient;
            this.senderAccountId    = sender;
            this.sourceRecordId     = source;
        }
    }

    public static Id create(String templateDeveloperName, Context ctx) {
        if (ctx == null) return null;
        List<Id> ids = create(templateDeveloperName, new List<Context>{ ctx });
        return ids.isEmpty() ? null : ids[0];
    }

    /**
     * Insert a single broadcast notification.
     * audienceMode:
     *   - 'Individual'      -> single recipient (use create() instead — kept for completeness)
     *   - 'All'             -> every user sees it
     *   - 'By_Role_Type'    -> user must have a ConstituentRole matching the configured role
     *   - 'By_Segmentation' -> reserved; not implemented in v1 controller
     */
    public static Id createBroadcast(String templateDeveloperName, Context ctx, String audienceMode) {
        if (String.isBlank(audienceMode)) {
            audienceMode = 'All';
        }
        Ken_Notification_Template__mdt tpl = Ken_Notification_Template__mdt.getInstance(templateDeveloperName);
        if (tpl == null) {
            throw new KenCustomException('Notification template not found: ' + templateDeveloperName);
        }
        if (tpl.Active__c != true) {
            System.debug('createBroadcast: template ' + templateDeveloperName + ' is inactive — skipping dispatch');
            return null;
        }
        if (ctx == null) ctx = new Context();

        Set<Id> acctIds = new Set<Id>();
        if (ctx.senderAccountId != null) acctIds.add(ctx.senderAccountId);
        Map<Id, Account> acctById = acctIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([
                SELECT Id, Name, FirstName, LastName, PhotoUrl
                FROM Account WHERE Id IN :acctIds
            ]);
        Map<Id, String> imageByAcct = lookupProfileImages(acctIds);

        Map<String, String> data = buildMergeData(ctx, acctById);
        String title = applyMerge(tpl.Title_Template__c, data);
        if (String.isBlank(title)) {
            throw new KenCustomException('Broadcast title resolved to blank for template ' + templateDeveloperName);
        }

        Ken_Notification__c row = new Ken_Notification__c(
            Recipient__c     = null,
            Is_Broadcast__c  = true,
            Audience_Mode__c = audienceMode,
            Category__c      = tpl.Category__c,
            Title__c         = title,
            Body__c          = applyMerge(tpl.Body_Template__c, data),
            Image_Url__c     = resolveImage(tpl.Image_Source__c, ctx, imageByAcct, tpl.Static_Image_Url__c),
            Target_Url__c    = resolveTargetUrl(tpl.Target_Url__c, ctx),
            Is_Read__c       = false
        );
        insert row;
        return row.Id;
    }

    public static List<Id> create(String templateDeveloperName, List<Context> contexts) {
        List<Id> resultIds = new List<Id>();
        if (contexts == null || contexts.isEmpty()) {
            return resultIds;
        }

        Ken_Notification_Template__mdt tpl = Ken_Notification_Template__mdt.getInstance(templateDeveloperName);
        if (tpl == null) {
            throw new KenCustomException('Notification template not found: ' + templateDeveloperName);
        }
        if (tpl.Active__c != true) {
            System.debug('create: template ' + templateDeveloperName + ' is inactive — skipping dispatch');
            return resultIds;
        }

        Set<Id> acctIds = new Set<Id>();
        for (Context c : contexts) {
            if (c == null || c.recipientAccountId == null) continue;
            acctIds.add(c.recipientAccountId);
            if (c.senderAccountId != null) acctIds.add(c.senderAccountId);
        }

        Map<Id, Account> acctById = acctIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([
                SELECT Id, Name, FirstName, LastName, PhotoUrl
                FROM Account WHERE Id IN :acctIds
            ]);
        Map<Id, String> imageByAcct = lookupProfileImages(acctIds);
        Set<Id> recipientIds = new Set<Id>();
        for (Context c : contexts) {
            if (c != null && c.recipientAccountId != null) recipientIds.add(c.recipientAccountId);
        }
        Map<Id, Ken_Alumni_Preferences__c> prefsByAcct = loadPreferences(recipientIds);

        List<Ken_Notification__c> rows = new List<Ken_Notification__c>();
        for (Context c : contexts) {
            if (c == null || c.recipientAccountId == null) continue;
            if (isSuppressedByPreferences(prefsByAcct.get(c.recipientAccountId), tpl.Category__c)) {
                continue;
            }
            Map<String, String> data = buildMergeData(c, acctById);
            String title = applyMerge(tpl.Title_Template__c, data);
            if (String.isBlank(title)) {
                continue;
            }
            rows.add(new Ken_Notification__c(
                Recipient__c     = c.recipientAccountId,
                Is_Broadcast__c  = false,
                Audience_Mode__c = 'Individual',
                Category__c      = tpl.Category__c,
                Title__c         = title,
                Body__c          = applyMerge(tpl.Body_Template__c, data),
                Image_Url__c     = resolveImage(tpl.Image_Source__c, c, imageByAcct, tpl.Static_Image_Url__c),
                Target_Url__c    = resolveTargetUrl(tpl.Target_Url__c, c),
                Is_Read__c       = false
            ));
        }

        if (rows.isEmpty()) {
            return resultIds;
        }
        insert rows;
        for (Ken_Notification__c n : rows) {
            resultIds.add(n.Id);
        }
        return resultIds;
    }

    /**
     * Marks the recipient's unread notifications that point at the given source
     * records as read — e.g. clears "sent you a connection request" once the
     * request is accepted/rejected. Ken_Notification__c has no related-record
     * field, so rows are matched by the record id embedded in Target_Url__c
     * (every request template merges {!Id} into its URL).
     * Fail-soft: clearing must never break the action that triggered it.
     */
    public static void markRelatedAsRead(Set<Id> sourceRecordIds, Id recipientAccountId) {
        if (sourceRecordIds == null || sourceRecordIds.isEmpty() || recipientAccountId == null) {
            return;
        }
        try {
            List<Ken_Notification__c> toUpdate = new List<Ken_Notification__c>();
            for (Ken_Notification__c n : [
                SELECT Id, Target_Url__c
                FROM Ken_Notification__c
                WHERE Recipient__c = :recipientAccountId
                  AND Is_Read__c = false
                  AND Is_Broadcast__c = false
                  AND Target_Url__c != null
                LIMIT 2000
            ]) {
                for (Id sourceId : sourceRecordIds) {
                    if (n.Target_Url__c.contains(String.valueOf(sourceId))) {
                        n.Is_Read__c = true;
                        toUpdate.add(n);
                        break;
                    }
                }
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'KenNotificationFactory.markRelatedAsRead failed: ' + e.getMessage());
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    private static Map<String, String> buildMergeData(Context c, Map<Id, Account> acctById) {
        Map<String, String> data = new Map<String, String>();
        Account sender    = c.senderAccountId    != null ? acctById.get(c.senderAccountId)    : null;
        Account recipient = c.recipientAccountId != null ? acctById.get(c.recipientAccountId) : null;
        if (sender != null) {
            data.put('Sender.Name',      blankIfNull(sender.Name));
            data.put('Sender.FirstName', blankIfNull(sender.FirstName));
            data.put('Sender.LastName',  blankIfNull(sender.LastName));
        }
        if (recipient != null) {
            data.put('Recipient.Name',      blankIfNull(recipient.Name));
            data.put('Recipient.FirstName', blankIfNull(recipient.FirstName));
            data.put('Recipient.LastName',  blankIfNull(recipient.LastName));
        }
        if (c.extras != null) {
            for (String k : c.extras.keySet()) {
                if (k != null && !k.startsWith('_')) {
                    data.put(k, blankIfNull(c.extras.get(k)));
                }
            }
        }
        return data;
    }

    @TestVisible
    private static String applyMerge(String tpl, Map<String, String> data) {
        if (String.isBlank(tpl)) return tpl;
        Matcher m = MERGE_PATTERN.matcher(tpl);
        String result = '';
        Integer last = 0;
        while (m.find()) {
            result += tpl.substring(last, m.start());
            String key = m.group(1);
            result += data.containsKey(key) ? data.get(key) : '';
            last = m.end();
        }
        result += tpl.substring(last);
        return result;
    }

    private static String resolveImage(String source, Context c, Map<Id, String> images, String staticUrl) {
        if (source == null) return null;
        if (source == 'Sender'      && c.senderAccountId != null)    return images.get(c.senderAccountId);
        if (source == 'Recipient'   && c.recipientAccountId != null) return images.get(c.recipientAccountId);
        if (source == 'Static')                                      return staticUrl;
        if (source == 'From_Extras' && c.extras != null)             return c.extras.get('_imageUrl');
        return null;
    }

    /**
     * Resolves the template's Target_Url__c into the actual URL written on the row:
     *   - If the pattern contains {!Id}, substitutes ctx.sourceRecordId. When the
     *     id is unavailable, the notification ships with no target URL (uninclickable).
     *   - Otherwise the pattern is used verbatim (good for static paths like /help
     *     or full external URLs like https://...).
     * The LWC then decides at click time whether to open externally or navigate
     * within the community based on the http(s):// prefix.
     */
    private static String resolveTargetUrl(String pattern, Context c) {
        if (String.isBlank(pattern)) return null;
        if (!pattern.contains('{!Id}')) return pattern;
        if (c == null || c.sourceRecordId == null) return null;
        return pattern.replace('{!Id}', String.valueOf(c.sourceRecordId));
    }

    private static String blankIfNull(String s) {
        return s == null ? '' : s;
    }

    private static Map<Id, Ken_Alumni_Preferences__c> loadPreferences(Set<Id> acctIds) {
        Map<Id, Ken_Alumni_Preferences__c> out = new Map<Id, Ken_Alumni_Preferences__c>();
        if (acctIds == null || acctIds.isEmpty()) return out;
        for (Ken_Alumni_Preferences__c p : [
            SELECT Id, Person_Account__c, Notify_me_for__c,
                   Mute_Notifications_Start_Time__c, Mute_Notifications_End_Time__c
            FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c IN :acctIds
        ]) {
            if (p.Person_Account__c != null) out.put(p.Person_Account__c, p);
        }
        return out;
    }

    // Ken_Notification__c.Category__c values are singular/internal, but the
    // Notify_me_for__c preference picklist uses different labels. Map a category
    // to its preference value before evaluating the opt-out. A category with no
    // entry here (e.g. 'Network') has no preference toggle and is never suppressed.
    private static final Map<String, String> CATEGORY_TO_PREF = new Map<String, String>{
        'Event'      => 'Events',
        'Group'      => 'Groups',
        'Mentorship' => 'Mentorship requests',
        'Survey'     => 'Survey'
    };

    @TestVisible
    private static Boolean isSuppressedByPreferences(Ken_Alumni_Preferences__c pref, String category) {
        if (pref == null) return false;

        // Category opt-out. Blank Notify_me_for__c = deliver everything,
        // so newly-provisioned alumni still hear from us until they pick.
        if (String.isNotBlank(category) && String.isNotBlank(pref.Notify_me_for__c)
                && CATEGORY_TO_PREF.containsKey(category)) {
            String prefValue = CATEGORY_TO_PREF.get(category);
            Set<String> allowed = new Set<String>();
            for (String v : pref.Notify_me_for__c.split(';')) {
                if (String.isNotBlank(v)) allowed.add(v.trim());
            }
            if (!allowed.isEmpty() && !allowed.contains(prefValue)) {
                return true;
            }
        }

        Time muteStart = pref.Mute_Notifications_Start_Time__c;
        Time muteEnd   = pref.Mute_Notifications_End_Time__c;
        if (muteStart != null && muteEnd != null) {
            Time now = Datetime.now().time();
            Boolean wraps = muteStart > muteEnd; // crosses midnight
            Boolean inWindow = wraps
                ? (now >= muteStart || now < muteEnd)
                : (now >= muteStart && now < muteEnd);
            if (inWindow) return true;
        }
        return false;
    }

    private static Map<Id, String> lookupProfileImages(Set<Id> acctIds) {
        Map<Id, String> out = new Map<Id, String>();
        if (acctIds == null || acctIds.isEmpty()) return out;
        Map<Id, String> crmByAcct = new Map<Id, String>();
        for (Ken_Alumni_CRM__c crm : [
            SELECT Person_Account__c, Profile_Photo_URL__c
            FROM Ken_Alumni_CRM__c
            WHERE Person_Account__c IN :acctIds
        ]) {
            if (String.isNotBlank(crm.Profile_Photo_URL__c)) {
                crmByAcct.put(crm.Person_Account__c, crm.Profile_Photo_URL__c);
            }
        }
        String orgDomain = URL.getOrgDomainUrl().toExternalForm();
        for (Account a : [SELECT Id, PhotoUrl FROM Account WHERE Id IN :acctIds]) {
            if (crmByAcct.containsKey(a.Id)) {
                out.put(a.Id, crmByAcct.get(a.Id));
            } else if (String.isNotBlank(a.PhotoUrl)) {
                out.put(a.Id, orgDomain + a.PhotoUrl);
            }
        }
        return out;
    }
}