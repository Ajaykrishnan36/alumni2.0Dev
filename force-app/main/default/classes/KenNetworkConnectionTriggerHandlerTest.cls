@isTest
private class KenNetworkConnectionTriggerHandlerTest {

    @testSetup
    static void setupData() {
        Id paRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Alumni_Person_Account' LIMIT 1
        ].Id;
        List<Account> people = new List<Account>{
            new Account(RecordTypeId = paRtId, FirstName = 'Initiator', LastName = 'Test', PersonEmail = 'init@ttest.example'),
            new Account(RecordTypeId = paRtId, FirstName = 'Recipient', LastName = 'Test', PersonEmail = 'recip@ttest.example')
        };
        insert people;
    }

    @isTest
    static void afterInsert_bypass_suppresses_notification() {
        Account initiator = [SELECT Id FROM Account WHERE FirstName = 'Initiator' LIMIT 1];
        Account recipient = [SELECT Id FROM Account WHERE FirstName = 'Recipient' LIMIT 1];
        insert new Alumni_Trigger_Settings__c(Network_Connection_Trigger__c = true);
        Test.startTest();
        insert new Ken_Network_Connection__c(
            Initiator__c = initiator.Id,
            Recipient__c = recipient.Id,
            Status__c    = 'Requested',
            Requested_Date__c = Datetime.now()
        );
        Test.stopTest();
        System.assertEquals(0,
            [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :recipient.Id AND Category__c = 'Network'],
            'Trigger bypass flag should suppress the network notification.');
    }

    @isTest
    static void afterInsert_requested_fires_request_received_notification() {
        Account initiator = [SELECT Id FROM Account WHERE FirstName = 'Initiator' LIMIT 1];
        Account recipient = [SELECT Id FROM Account WHERE FirstName = 'Recipient' LIMIT 1];

        Test.startTest();
        Ken_Network_Connection__c conn = new Ken_Network_Connection__c(
            Initiator__c = initiator.Id,
            Recipient__c = recipient.Id,
            Status__c    = 'Requested',
            Requested_Date__c = Datetime.now()
        );
        insert conn;
        Test.stopTest();

        List<Ken_Notification__c> notifs = [
            SELECT Id, Recipient__c, Category__c, Title__c
            FROM Ken_Notification__c
            WHERE Recipient__c = :recipient.Id
        ];
        System.assertEquals(1, notifs.size(), 'One request-received notification should fire');
        System.assertEquals('Network', notifs[0].Category__c);
    }

    @isTest
    static void afterUpdate_rejected_fires_rejection_notification_to_initiator() {
        Account initiator = [SELECT Id FROM Account WHERE FirstName = 'Initiator' LIMIT 1];
        Account recipient = [SELECT Id FROM Account WHERE FirstName = 'Recipient' LIMIT 1];

        Ken_Network_Connection__c conn = new Ken_Network_Connection__c(
            Initiator__c = initiator.Id,
            Recipient__c = recipient.Id,
            Status__c    = 'Requested',
            Requested_Date__c = Datetime.now()
        );
        insert conn;
        // Clear the request-received notification so the assert below only sees the rejection one.
        delete [SELECT Id FROM Ken_Notification__c];

        Test.startTest();
        conn.Status__c = 'Rejected';
        update conn;
        Test.stopTest();

        List<Ken_Notification__c> notifs = [
            SELECT Id, Recipient__c, Category__c, Title__c
            FROM Ken_Notification__c
            WHERE Recipient__c = :initiator.Id
        ];
        System.assertEquals(1, notifs.size(), 'One rejection notification should fire to the initiator');
        System.assertEquals('Network', notifs[0].Category__c);
    }

    @isTest
    static void status_unchanged_update_fires_no_extra_notification() {
        Account initiator = [SELECT Id FROM Account WHERE FirstName = 'Initiator' LIMIT 1];
        Account recipient = [SELECT Id FROM Account WHERE FirstName = 'Recipient' LIMIT 1];

        Ken_Network_Connection__c conn = new Ken_Network_Connection__c(
            Initiator__c = initiator.Id,
            Recipient__c = recipient.Id,
            Status__c    = 'Requested',
            Requested_Date__c = Datetime.now()
        );
        insert conn;
        delete [SELECT Id FROM Ken_Notification__c];

        Test.startTest();
        conn.Requested_Date__c = Datetime.now().addMinutes(1);
        update conn;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Ken_Notification__c];
        System.assertEquals(0, count, 'Non-status update should produce no notification');
    }
}