public without sharing class KenNotificationController {
    private static final Integer DEFAULT_POLL_SECONDS = 60;

    @TestVisible
    private static Id testCurrentAccountId;

    public class NotificationHeartbeat {
        @AuraEnabled public Integer unreadCount;
        @AuraEnabled public Boolean hasNew;
        @AuraEnabled public Integer pollIntervalSeconds;
    }

    /**
     * Sole heartbeat endpoint for the alumni portal bell. One round-trip does both
     * jobs so the client never needs a second SOQL call on the polling path:
     *   1. Stamps Last_Active__c on every Ken_Alumni_CRM__c tied to the user.
     *   2. Returns a cheap SELECT COUNT() of unread (non-broadcast) notifications.
     * Also returns the admin-configured poll interval so the client can adjust its
     * timer without a deploy.
     */
    @AuraEnabled
    public static NotificationHeartbeat fetchNotifications() {
        NotificationHeartbeat result = new NotificationHeartbeat();
        result.unreadCount = 0;
        result.hasNew = false;
        result.pollIntervalSeconds = resolvePollIntervalSeconds();

        Id accountId = getCurrentUserAccountId();
        if (accountId == null) return result;

        stampLastActive(accountId);

        Integer cnt = [
            SELECT COUNT()
            FROM Ken_Notification__c
            WHERE Recipient__c = :accountId
              AND Is_Broadcast__c = false
              AND Is_Read__c = false
        ];
        result.unreadCount = cnt;
        result.hasNew = cnt > 0;
        return result;
    }

    private static void stampLastActive(Id accountId) {
        Datetime nowValue = System.now();
        List<Ken_Alumni_CRM__c> existing = [
            SELECT Id FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :accountId
        ];
        if (!existing.isEmpty()) {
            for (Ken_Alumni_CRM__c rec : existing) {
                rec.Last_Active__c = nowValue;
            }
            update existing;
            return;
        }
        Id constituentRoleId = null;
        List<ConstituentRole> roles = [
            SELECT Id FROM ConstituentRole
            WHERE PersonId = :accountId AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!roles.isEmpty()) {
            constituentRoleId = roles[0].Id;
        }
        insert new Ken_Alumni_CRM__c(
            Person_Account__c  = accountId,
            ConstituentRole__c = constituentRoleId,
            Last_Active__c     = nowValue
        );
    }

    private static Integer resolvePollIntervalSeconds() {
        Alumni_Org_Parameters__c p = Alumni_Org_Parameters__c.getInstance();
        if (p == null || p.Notification_Poll_Interval_Seconds__c == null) {
            return DEFAULT_POLL_SECONDS;
        }
        Integer v = p.Notification_Poll_Interval_Seconds__c.intValue();
        if (v < 10) return 10;
        if (v > 3600) return 3600;
        return v;
    }

    public class NotificationDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String category;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String targetUrl;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public Boolean isBroadcast;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<NotificationDTO> getNotifications(Integer pageSize, Integer offsetCount) {
        Id userAcctId = getCurrentUserAccountId();
        if (userAcctId == null) {
            return new List<NotificationDTO>();
        }
        Integer effectivePageSize = (pageSize == null || pageSize <= 0) ? 50 : pageSize;
        Integer effectiveOffset   = (offsetCount == null || offsetCount < 0) ? 0 : offsetCount;

        List<Ken_Notification__c> personal = [
            SELECT Id, Category__c, Title__c, Body__c, Image_Url__c,
                   Target_Url__c, Is_Read__c, Is_Broadcast__c, CreatedDate
            FROM Ken_Notification__c
            WHERE Recipient__c = :userAcctId
              AND Is_Broadcast__c = false
            ORDER BY CreatedDate DESC
            LIMIT :effectivePageSize
            OFFSET :effectiveOffset
        ];

        // Without Audience_Value__c, the only broadcast mode that resolves at read
        // time is 'All'. Role-type / segmentation modes are kept on the picklist for
        // a future cut where the audience filter moves to junction objects.
        List<Ken_Notification__c> broadcasts = [
            SELECT Id, Category__c, Title__c, Body__c, Image_Url__c,
                   Target_Url__c, Is_Read__c,
                   Is_Broadcast__c, Audience_Mode__c, CreatedDate
            FROM Ken_Notification__c
            WHERE Is_Broadcast__c = true
              AND Audience_Mode__c = 'All'
            ORDER BY CreatedDate DESC
            LIMIT :effectivePageSize
        ];

        return convertRows(mergeDesc(personal, broadcasts, effectivePageSize));
    }

    @AuraEnabled(cacheable=true)
    public static Id getCurrentAccountId() {
        return getCurrentUserAccountId();
    }

    @AuraEnabled(cacheable=true)
    public static Integer getUnreadCount() {
        Id userAcctId = getCurrentUserAccountId();
        if (userAcctId == null) return 0;
        return [
            SELECT COUNT()
            FROM Ken_Notification__c
            WHERE Recipient__c = :userAcctId
              AND Is_Broadcast__c = false
              AND Is_Read__c = false
        ];
    }

    private static List<Ken_Notification__c> mergeDesc(
        List<Ken_Notification__c> a,
        List<Ken_Notification__c> b,
        Integer maxSize
    ) {
        List<Ken_Notification__c> out = new List<Ken_Notification__c>();
        Integer i = 0, j = 0;
        while ((i < a.size() || j < b.size()) && out.size() < maxSize) {
            if (i >= a.size()) {
                out.add(b[j++]);
            } else if (j >= b.size()) {
                out.add(a[i++]);
            } else if (a[i].CreatedDate >= b[j].CreatedDate) {
                out.add(a[i++]);
            } else {
                out.add(b[j++]);
            }
        }
        return out;
    }

    private static Set<String> getUserRoleTypes(Id acctId) {
        Set<String> roles = new Set<String>();
        if (acctId == null) return roles;
        for (ConstituentRole cr : [
            SELECT RoleType FROM ConstituentRole WHERE PersonId = :acctId
        ]) {
            if (String.isNotBlank(cr.RoleType)) {
                roles.add(cr.RoleType);
            }
        }
        return roles;
    }

    @AuraEnabled
    public static void markAsRead(List<Id> notificationIds) {
        if (notificationIds == null || notificationIds.isEmpty()) return;
        Id userAcctId = getCurrentUserAccountId();
        if (userAcctId == null) return;
        List<Ken_Notification__c> rows = [
            SELECT Id, Is_Read__c
            FROM Ken_Notification__c
            WHERE Id IN :notificationIds
              AND Recipient__c = :userAcctId
              AND Is_Read__c = false
        ];
        for (Ken_Notification__c r : rows) {
            r.Is_Read__c = true;
        }
        if (!rows.isEmpty()) {
            update rows;
        }
    }

    @AuraEnabled
    public static Integer markAllAsRead() {
        Id userAcctId = getCurrentUserAccountId();
        if (userAcctId == null) return 0;
        List<Ken_Notification__c> rows = [
            SELECT Id
            FROM Ken_Notification__c
            WHERE Recipient__c = :userAcctId
              AND Is_Read__c = false
            LIMIT 200
        ];
        for (Ken_Notification__c r : rows) {
            r.Is_Read__c = true;
        }
        if (!rows.isEmpty()) {
            update rows;
        }
        return rows.size();
    }

    private static List<NotificationDTO> convertRows(List<Ken_Notification__c> rows) {
        List<NotificationDTO> out = new List<NotificationDTO>();
        for (Ken_Notification__c r : rows) {
            Boolean isBroadcastRow = r.Is_Broadcast__c == true;
            NotificationDTO d = new NotificationDTO();
            d.id          = r.Id;
            d.category    = r.Category__c;
            d.title       = r.Title__c;
            d.body        = r.Body__c;
            d.imageUrl    = r.Image_Url__c;
            d.targetUrl   = r.Target_Url__c;
            d.isRead      = isBroadcastRow ? true : r.Is_Read__c;
            d.isBroadcast = isBroadcastRow;
            d.createdDate = r.CreatedDate;
            out.add(d);
        }
        return out;
    }

    private static Id getCurrentUserAccountId() {
        if (Test.isRunningTest() && testCurrentAccountId != null) {
            return testCurrentAccountId;
        }
        List<User> users = [
            SELECT Id, AccountId, ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (users.isEmpty()) return null;
        User currentUser = users[0];
        if (currentUser.AccountId != null) return currentUser.AccountId;
        if (currentUser.ContactId != null) {
            List<Contact> contacts = [
                SELECT AccountId FROM Contact WHERE Id = :currentUser.ContactId LIMIT 1
            ];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                return contacts[0].AccountId;
            }
        }
        return null;
    }
}