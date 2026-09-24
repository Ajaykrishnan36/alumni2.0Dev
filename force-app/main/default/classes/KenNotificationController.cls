public without sharing class KenNotificationController {
  private static final Integer DEFAULT_POLL_SECONDS = 60;

  @TestVisible
  private static Id testCurrentAccountId;

  public class NotificationHeartbeat {
    @AuraEnabled
    public Integer unreadCount;
    @AuraEnabled
    public Boolean hasNew;
    @AuraEnabled
    public Integer pollIntervalSeconds;
  }

  /**
   * Sole heartbeat endpoint for the alumni portal bell. Returns a cheap
   * SELECT COUNT() of unread (non-broadcast) notifications, plus the
   * admin-configured poll interval so the client can adjust its timer without a
   * deploy. One round-trip does both jobs so the client never needs a second call
   * on the polling path:
   *   1. Stamps Account.Last_Active__c for the user.
   *   2. Returns a cheap SELECT COUNT() of unread (non-broadcast) notifications.
   * The stamp used to live on Ken_Alumni_CRM__c and would INSERT a row when none
   * existed, which was one source of duplicate CRM rows. It now updates the Person
   * Account that always exists, so the heartbeat never creates records.
   */
  @AuraEnabled
  public static NotificationHeartbeat fetchNotifications() {
    NotificationHeartbeat result = new NotificationHeartbeat();
    result.unreadCount = 0;
    result.hasNew = false;
    result.pollIntervalSeconds = resolvePollIntervalSeconds();

    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      return result;

    stampLastActive(accountId);

    Integer cnt = [
      SELECT COUNT()
      FROM Ken_Notification__c
      WHERE
        Recipient__c = :accountId
        AND Is_Broadcast__c = FALSE
        AND Is_Read__c = FALSE
    WITH SECURITY_ENFORCED
    ];
    result.unreadCount = cnt;
    result.hasNew = cnt > 0;
    return result;
  }

  /**
   * @description Stamps the heartbeat time on the user's Person Account. Updates
   *              only — the Account is guaranteed to exist for a portal user, so
   *              this path never inserts.
   *
   * @param accountId Person Account of the logged-in user.
   */
  private static void stampLastActive(Id accountId) {
    try {
      if (!Schema.sObjectType.Account.isUpdateable()) {
          throw new KenCrudException('Account is not updateable by the current user.');
      }
      update new Account(Id = accountId, Last_Active__c = System.now());
    } catch (DmlException e) {
      System.debug(
        LoggingLevel.WARN,
        'stampLastActive skipped: ' + e.getMessage()
      );
    }
  }

  /**
   * The portal's AMBIENT refresh cadence - how often a background badge may re-check.
   *
   * Public because the chat's unread badge and its room list ride the same interval: they are
   * the same kind of thing as the notification bell, and three separate cadences for
   * "something might have changed" is three things to tune and get wrong.
   */
  public static Integer resolvePollIntervalSeconds() {
    Ken_Alm_Org_Parameters__c p = Ken_Alm_Org_Parameters__c.getInstance();
    if (p == null || p.Notification_Poll_Interval_Seconds__c == null) {
      return DEFAULT_POLL_SECONDS;
    }
    Integer v = p.Notification_Poll_Interval_Seconds__c.intValue();
    if (v < 10)
      return 10;
    if (v > 3600)
      return 3600;
    return v;
  }

  public class NotificationDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String body;
    @AuraEnabled
    public String imageUrl;
    @AuraEnabled
    public String targetUrl;
    @AuraEnabled
    public Boolean isRead;
    @AuraEnabled
    public Boolean isBroadcast;
    @AuraEnabled
    public Datetime createdDate;
  }

  @AuraEnabled(cacheable=true)
  public static List<NotificationDTO> getNotifications(
    Integer pageSize,
    Integer offsetCount
  ) {
    Id userAcctId = getCurrentUserAccountId();
    if (userAcctId == null) {
      return new List<NotificationDTO>();
    }
    Integer effectivePageSize = (pageSize == null ||
      pageSize <= 0)
      ? 50
      : pageSize;
    Integer effectiveOffset = (offsetCount == null ||
      offsetCount < 0)
      ? 0
      : offsetCount;

    List<Ken_Notification__c> personal = [
      SELECT
        Id,
        Category__c,
        Title__c,
        Body__c,
        Image_Url__c,
        Target_Url__c,
        Is_Read__c,
        Is_Broadcast__c,
        CreatedDate
      FROM Ken_Notification__c
      WHERE Recipient__c = :userAcctId AND Is_Broadcast__c = FALSE
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT :effectivePageSize
      OFFSET :effectiveOffset
    ];

    // Without Audience_Value__c, the only broadcast mode that resolves at read
    // time is 'All'. Role-type / segmentation modes are kept on the picklist for
    // a future cut where the audience filter moves to junction objects.
    List<Ken_Notification__c> broadcasts = [
      SELECT
        Id,
        Category__c,
        Title__c,
        Body__c,
        Image_Url__c,
        Target_Url__c,
        Is_Read__c,
        Is_Broadcast__c,
        Audience_Mode__c,
        CreatedDate
      FROM Ken_Notification__c
      WHERE Is_Broadcast__c = TRUE AND Audience_Mode__c = 'All'
      WITH SECURITY_ENFORCED
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
    if (userAcctId == null)
      return 0;
    return [
      SELECT COUNT()
      FROM Ken_Notification__c
      WHERE
        Recipient__c = :userAcctId
        AND Is_Broadcast__c = FALSE
        AND Is_Read__c = FALSE
    WITH SECURITY_ENFORCED
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
    if (acctId == null)
      return roles;
    for (ConstituentRole cr : [
      SELECT RoleType
      FROM ConstituentRole
      WHERE PersonId = :acctId
    WITH SECURITY_ENFORCED
    ]) {
      if (String.isNotBlank(cr.RoleType)) {
        roles.add(cr.RoleType);
      }
    }
    return roles;
  }

  @AuraEnabled
  public static void markAsRead(List<Id> notificationIds) {
    if (notificationIds == null || notificationIds.isEmpty())
      return;
    Id userAcctId = getCurrentUserAccountId();
    if (userAcctId == null)
      return;
    List<Ken_Notification__c> rows = [
      SELECT Id, Is_Read__c
      FROM Ken_Notification__c
      WHERE
        Id IN :notificationIds
        AND Recipient__c = :userAcctId
        AND Is_Read__c = FALSE
    WITH SECURITY_ENFORCED
    ];
    for (Ken_Notification__c r : rows) {
      r.Is_Read__c = true;
    }
    if (!rows.isEmpty()) {
      if (!Schema.sObjectType.Ken_Notification__c.isUpdateable()) {
          throw new KenCrudException('Ken_Notification__c is not updateable by the current user.');
      }
      update rows;
    }
  }

  @AuraEnabled
  public static Integer markAllAsRead() {
    Id userAcctId = getCurrentUserAccountId();
    if (userAcctId == null)
      return 0;
    List<Ken_Notification__c> rows = [
      SELECT Id
      FROM Ken_Notification__c
      WHERE Recipient__c = :userAcctId AND Is_Read__c = FALSE
      WITH SECURITY_ENFORCED
      LIMIT 200
    ];
    for (Ken_Notification__c r : rows) {
      r.Is_Read__c = true;
    }
    if (!rows.isEmpty()) {
      if (!Schema.sObjectType.Ken_Notification__c.isUpdateable()) {
          throw new KenCrudException('Ken_Notification__c is not updateable by the current user.');
      }
      update rows;
    }
    return rows.size();
  }

  private static List<NotificationDTO> convertRows(
    List<Ken_Notification__c> rows
  ) {
    List<NotificationDTO> out = new List<NotificationDTO>();
    for (Ken_Notification__c r : rows) {
      Boolean isBroadcastRow = r.Is_Broadcast__c == true;
      NotificationDTO d = new NotificationDTO();
      d.id = r.Id;
      d.category = r.Category__c;
      d.title = r.Title__c;
      d.body = r.Body__c;
      d.imageUrl = r.Image_Url__c;
      d.targetUrl = r.Target_Url__c;
      d.isRead = isBroadcastRow ? true : r.Is_Read__c;
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
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (users.isEmpty())
      return null;
    User currentUser = users[0];
    if (currentUser.AccountId != null)
      return currentUser.AccountId;
    if (currentUser.ContactId != null) {
      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :currentUser.ContactId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!contacts.isEmpty() && contacts[0].AccountId != null) {
        return contacts[0].AccountId;
      }
    }
    return null;
  }
}