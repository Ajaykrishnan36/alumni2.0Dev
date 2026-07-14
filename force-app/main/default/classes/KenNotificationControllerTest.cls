@IsTest
private class KenNotificationControllerTest {

    @TestSetup
    static void setupData() {
        Account recipient = createAlumniPersonAccount('Notif', 'Recipient', 'notif.recipient@test.com');
        Account other     = createAlumniPersonAccount('Notif', 'Other',     'notif.other@test.com');
        insert new List<Account>{ recipient, other };

        insert new List<Ken_Notification__c>{
            new Ken_Notification__c(
                Recipient__c  = recipient.Id,
                Category__c   = 'Network',
                Title__c      = 'Notif Other accepted your connection request',
                Target_Url__c = '/network?profileId=' + other.Id,
                Is_Read__c    = false
            ),
            new Ken_Notification__c(
                Recipient__c = recipient.Id,
                Category__c  = 'System',
                Title__c     = 'Welcome to the alumni portal',
                Is_Read__c   = false
            )
        };
    }

    @IsTest
    static void testGetNotificationsReturnsCurrentUserRows() {
        Account recipient = [SELECT Id FROM Account WHERE Name = 'Notif Recipient' LIMIT 1];

        Test.startTest();
        KenNotificationController.testCurrentAccountId = recipient.Id;
        List<KenNotificationController.NotificationDTO> rows = KenNotificationController.getNotifications(50, 0);
        KenNotificationController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Recipient should see both seeded notifications');
        for (KenNotificationController.NotificationDTO r : rows) {
            System.assertEquals(false, r.isRead, 'Seeded notifications should be unread');
        }
    }

    @IsTest
    static void testGetCurrentAccountIdReturnsNullForSystemUser() {
        Test.startTest();
        Id acctId = KenNotificationController.getCurrentAccountId();
        Test.stopTest();
        System.assertEquals(null, acctId, 'System running user has no Person Account in this test context');
    }

    @IsTest
    static void testFetchNotificationsReturnsUnreadAndStampsLastActive() {
        Account recipient = [SELECT Id FROM Account WHERE Name = 'Notif Recipient' LIMIT 1];

        Test.startTest();
        KenNotificationController.testCurrentAccountId = recipient.Id;
        KenNotificationController.NotificationHeartbeat hb =
            KenNotificationController.fetchNotifications();
        KenNotificationController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertNotEquals(null, hb);
        System.assertEquals(2, hb.unreadCount, 'Both seeded notifications are unread');
        System.assertEquals(true, hb.hasNew);
        System.assertNotEquals(null, hb.pollIntervalSeconds);
        System.assert(hb.pollIntervalSeconds >= 10 && hb.pollIntervalSeconds <= 3600);

        List<Ken_Alumni_CRM__c> crmRows = [
            SELECT Last_Active__c FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :recipient.Id
        ];
        System.assertEquals(1, crmRows.size(), 'A CRM row should exist after fetchNotifications');
        System.assertNotEquals(null, crmRows[0].Last_Active__c);
    }

    @IsTest
    static void testGetUnreadCount() {
        Account recipient = [SELECT Id FROM Account WHERE Name = 'Notif Recipient' LIMIT 1];

        Test.startTest();
        KenNotificationController.testCurrentAccountId = recipient.Id;
        Integer count = KenNotificationController.getUnreadCount();
        KenNotificationController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals(2, count);
    }

    @IsTest
    static void testMarkAsRead() {
        Account recipient = [SELECT Id FROM Account WHERE Name = 'Notif Recipient' LIMIT 1];
        Ken_Notification__c first = [
            SELECT Id FROM Ken_Notification__c
            WHERE Recipient__c = :recipient.Id LIMIT 1
        ];

        Test.startTest();
        KenNotificationController.testCurrentAccountId = recipient.Id;
        KenNotificationController.markAsRead(new List<Id>{ first.Id });
        Integer remaining = KenNotificationController.getUnreadCount();
        KenNotificationController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals(1, remaining);
    }

    @IsTest
    static void testMarkAllAsRead() {
        Account recipient = [SELECT Id FROM Account WHERE Name = 'Notif Recipient' LIMIT 1];

        Test.startTest();
        KenNotificationController.testCurrentAccountId = recipient.Id;
        Integer marked = KenNotificationController.markAllAsRead();
        Integer remaining = KenNotificationController.getUnreadCount();
        KenNotificationController.testCurrentAccountId = null;
        Test.stopTest();

        System.assertEquals(2, marked);
        System.assertEquals(0, remaining);
    }

    private static Account createAlumniPersonAccount(String firstName, String lastName, String email) {
        Id paRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Alumni_Person_Account' LIMIT 1
        ].Id;
        return new Account(
            RecordTypeId = paRtId,
            FirstName    = firstName,
            LastName     = lastName,
            PersonEmail  = email
        );
    }
}