@IsTest
private class KenNotificationFactoryTest {

    @IsTest
    static void testApplyMergeReplacesKnownKeysAndStripsUnknown() {
        Map<String, String> data = new Map<String, String>{
            'Sender.Name' => 'Alice',
            'Group.Name'  => 'Movie Buff'
        };

        String tpl = '{!Sender.Name} invited you to join "{!Group.Name}" — {!Unknown.Key}';
        String out = KenNotificationFactory.applyMerge(tpl, data);

        System.assertEquals('Alice invited you to join "Movie Buff" — ', out);
    }

    @IsTest
    static void testApplyMergeNullAndBlank() {
        Map<String, String> data = new Map<String, String>{ 'X' => 'Y' };
        System.assertEquals(null, KenNotificationFactory.applyMerge(null, data));
        System.assertEquals('', KenNotificationFactory.applyMerge('', data));
        System.assertEquals('plain', KenNotificationFactory.applyMerge('plain', data));
    }

    @IsTest
    static void testCreateThrowsForUnknownTemplate() {
        Account a = createAlumniPersonAccount('Factory', 'Recipient', 'factory.recipient@test.com');
        insert a;

        KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(a.Id, null, null);

        Boolean threw = false;
        Test.startTest();
        try {
            KenNotificationFactory.create('Template_That_Does_Not_Exist_xxx', ctx);
        } catch (KenCustomException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Should throw for unknown template developer name');
    }

    @IsTest
    static void testCreateSkipsContextsWithoutRecipient() {
        // Pick an existing template to avoid coupling this test to a specific record.
        // Falls back to no-op when no templates are deployed.
        List<Ken_Notification_Template__mdt> tpls = [
            SELECT DeveloperName FROM Ken_Notification_Template__mdt LIMIT 1
        ];
        if (tpls.isEmpty()) return;

        KenNotificationFactory.Context bad = new KenNotificationFactory.Context();
        // recipientAccountId left null → row should be skipped

        Test.startTest();
        List<Id> ids = KenNotificationFactory.create(
            tpls[0].DeveloperName,
            new List<KenNotificationFactory.Context>{ bad }
        );
        Test.stopTest();

        System.assertEquals(0, ids.size(), 'Contexts without a recipient must be skipped');
    }

    @IsTest
    static void testCreateProducesNotificationFromTemplate() {
        // Uses Mentorship_Request_Received (deployed alongside the factory).
        // If the CMDT record is absent in this org, the test silently passes.
        List<Ken_Notification_Template__mdt> tpls = [
            SELECT DeveloperName, Title_Template__c
            FROM Ken_Notification_Template__mdt
            WHERE DeveloperName = 'Mentorship_Request_Received'
            LIMIT 1
        ];
        if (tpls.isEmpty()) return;

        Account mentor = createAlumniPersonAccount('Factory', 'Mentor', 'factory.mentor@test.com');
        Account mentee = createAlumniPersonAccount('Factory', 'Mentee', 'factory.mentee@test.com');
        insert new List<Account>{ mentor, mentee };

        KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
            mentor.Id, mentee.Id, null
        );

        Test.startTest();
        List<Id> ids = KenNotificationFactory.create(
            'Mentorship_Request_Received',
            new List<KenNotificationFactory.Context>{ ctx }
        );
        Test.stopTest();

        System.assertEquals(1, ids.size(), 'One notification should be created');
        Ken_Notification__c n = [
            SELECT Id, Recipient__c, Title__c, Category__c, Target_Url__c
            FROM Ken_Notification__c WHERE Id = :ids[0] LIMIT 1
        ];
        System.assertEquals(mentor.Id, n.Recipient__c);
        System.assertEquals('Mentorship', n.Category__c);
        System.assert(
            n.Title__c.contains('Factory Mentee'),
            'Sender.Name should be merged into the title; got: ' + n.Title__c
        );
    }

    @IsTest
    static void testSuppressionMapsCategoryToPreferenceLabel() {
        // Pref opts into Groups + Events only. Category values are singular/internal
        // ('Group'), so the factory must map 'Group' -> 'Groups' before checking.
        Ken_Alumni_Preferences__c pref = new Ken_Alumni_Preferences__c(
            Notify_me_for__c = 'Groups;Events'
        );

        System.assertEquals(false,
            KenNotificationFactory.isSuppressedByPreferences(pref, 'Group'),
            'Group must map to the "Groups" preference label and be delivered');
        System.assertEquals(false,
            KenNotificationFactory.isSuppressedByPreferences(pref, 'Event'),
            'Event must map to the "Events" preference label and be delivered');
        System.assertEquals(true,
            KenNotificationFactory.isSuppressedByPreferences(pref, 'Mentorship'),
            'Mentorship is not opted in and must be suppressed');
    }

    @IsTest
    static void testSuppressionDeliversCategoriesWithoutPreferenceToggle() {
        // 'Network' has no Notify_me_for__c option, so it can never be opted out.
        Ken_Alumni_Preferences__c pref = new Ken_Alumni_Preferences__c(
            Notify_me_for__c = 'Groups'
        );
        System.assertEquals(false,
            KenNotificationFactory.isSuppressedByPreferences(pref, 'Network'),
            'Categories with no preference toggle must always be delivered');
    }

    @IsTest
    static void testSuppressionBlankPreferenceDeliversEverything() {
        Ken_Alumni_Preferences__c pref = new Ken_Alumni_Preferences__c(
            Notify_me_for__c = null
        );
        System.assertEquals(false,
            KenNotificationFactory.isSuppressedByPreferences(pref, 'Group'),
            'Blank Notify_me_for__c must deliver every category');
        System.assertEquals(false,
            KenNotificationFactory.isSuppressedByPreferences(null, 'Group'),
            'Null preference record must deliver every category');
    }

    @IsTest
    static void testMarkRelatedAsReadClearsMatchingUnread() {
        Account actor = createAlumniPersonAccount('Clear', 'Actor', 'clear.actor@test.com');
        insert actor;
        // Any record id embedded in the URL works; the actor's own id stands in
        // for a request record id.
        Id fakeRequestId = actor.Id;
        Ken_Notification__c match = new Ken_Notification__c(
            Recipient__c = actor.Id,
            Title__c = 'Request received',
            Category__c = 'Network',
            Target_Url__c = '/network?profileId=' + fakeRequestId,
            Is_Read__c = false,
            Is_Broadcast__c = false
        );
        Ken_Notification__c other = new Ken_Notification__c(
            Recipient__c = actor.Id,
            Title__c = 'Unrelated',
            Category__c = 'Network',
            Target_Url__c = '/network?profileId=001000000000000AAA',
            Is_Read__c = false,
            Is_Broadcast__c = false
        );
        insert new List<Ken_Notification__c>{ match, other };

        Test.startTest();
        KenNotificationFactory.markRelatedAsRead(new Set<Id>{ fakeRequestId }, actor.Id);
        Test.stopTest();

        System.assertEquals(true,
            [SELECT Is_Read__c FROM Ken_Notification__c WHERE Id = :match.Id].Is_Read__c,
            'Notification pointing at the actioned record should be marked read.');
        System.assertEquals(false,
            [SELECT Is_Read__c FROM Ken_Notification__c WHERE Id = :other.Id].Is_Read__c,
            'Unrelated notifications must stay unread.');
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