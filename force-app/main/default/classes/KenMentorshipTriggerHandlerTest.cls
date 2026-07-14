@IsTest
private class KenMentorshipTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Account mentor = createAlumniPersonAccount('Mentor', 'One',     'mentor.one@test.com');
        Account mentee = createAlumniPersonAccount('Mentee', 'One',     'mentee.one@test.com');
        insert new List<Account>{ mentor, mentee };
    }

    @IsTest
    static void testTriggerBypass() {
        Account mentor = [SELECT Id FROM Account WHERE Name = 'Mentor One' LIMIT 1];
        Account mentee = [SELECT Id FROM Account WHERE Name = 'Mentee One' LIMIT 1];
        insert new Alumni_Trigger_Settings__c(Mentorship_Trigger__c = true);
        Test.startTest();
        insert new Ken_Mentorship__c(
            RecordTypeId         = connectionRtId(),
            Mentor__c            = mentor.Id,
            Mentee__c            = mentee.Id,
            Mentorship_Status__c = 'Requested'
        );
        Test.stopTest();
        System.assertEquals(0,
            [SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c = :mentor.Id AND Category__c = 'Mentorship'],
            'Trigger bypass flag should suppress the mentor notification.');
    }

    @IsTest
    static void testRequestNotifiesMentor() {
        Account mentor = [SELECT Id FROM Account WHERE Name = 'Mentor One' LIMIT 1];
        Account mentee = [SELECT Id FROM Account WHERE Name = 'Mentee One' LIMIT 1];

        Test.startTest();
        Ken_Mentorship__c m = new Ken_Mentorship__c(
            RecordTypeId         = connectionRtId(),
            Mentor__c            = mentor.Id,
            Mentee__c            = mentee.Id,
            Mentorship_Status__c = 'Requested'
        );
        insert m;
        Test.stopTest();

        List<Ken_Notification__c> notifs = [
            SELECT Id, Recipient__c, Category__c, Target_Url__c
            FROM Ken_Notification__c
            WHERE Recipient__c = :mentor.Id AND Category__c = 'Mentorship'
        ];
        System.assertEquals(1, notifs.size(), 'Mentor should receive one notification');
        System.assertEquals(mentor.Id, notifs[0].Recipient__c, 'Notification should go to the mentor');
        System.assertEquals('Mentorship', notifs[0].Category__c);
        System.assert(notifs[0].Target_Url__c != null && notifs[0].Target_Url__c.contains(String.valueOf(m.Id)),
            'Target URL should contain the mentorship record id');
    }

    @IsTest
    static void testAcceptNotifiesMentee() {
        Account mentor = [SELECT Id FROM Account WHERE Name = 'Mentor One' LIMIT 1];
        Account mentee = [SELECT Id FROM Account WHERE Name = 'Mentee One' LIMIT 1];

        Ken_Mentorship__c m = new Ken_Mentorship__c(
            RecordTypeId         = connectionRtId(),
            Mentor__c            = mentor.Id,
            Mentee__c            = mentee.Id,
            Mentorship_Status__c = 'Requested'
        );
        insert m;

        Test.startTest();
        m.Mentorship_Status__c = 'Accepted';
        update m;
        Test.stopTest();

        List<Ken_Notification__c> menteeNotifs = [
            SELECT Id, Recipient__c, Title__c, Target_Url__c
            FROM Ken_Notification__c
            WHERE Recipient__c = :mentee.Id AND Title__c LIKE '%accepted%'
        ];
        System.assertEquals(1, menteeNotifs.size(), 'Mentee should receive one accepted notification');
        System.assert(menteeNotifs[0].Target_Url__c != null && menteeNotifs[0].Target_Url__c.contains(String.valueOf(m.Id)),
            'Target URL should carry the mentorship record id');
        System.assert(menteeNotifs[0].Title__c.contains('accepted'), 'Title should mention accepted');
    }

    @IsTest
    static void testRejectNotifiesMentee() {
        Account mentor = [SELECT Id FROM Account WHERE Name = 'Mentor One' LIMIT 1];
        Account mentee = [SELECT Id FROM Account WHERE Name = 'Mentee One' LIMIT 1];

        Ken_Mentorship__c m = new Ken_Mentorship__c(
            RecordTypeId         = connectionRtId(),
            Mentor__c            = mentor.Id,
            Mentee__c            = mentee.Id,
            Mentorship_Status__c = 'Requested'
        );
        insert m;

        Test.startTest();
        m.Mentorship_Status__c = 'Rejected';
        update m;
        Test.stopTest();

        List<Ken_Notification__c> menteeNotifs = [
            SELECT Id, Recipient__c, Title__c
            FROM Ken_Notification__c
            WHERE Recipient__c = :mentee.Id AND Title__c LIKE '%declined%'
        ];
        System.assertEquals(1, menteeNotifs.size(), 'Mentee should receive one declined notification');
        System.assert(menteeNotifs[0].Title__c.contains('declined'), 'Title should mention declined');
    }

    @IsTest
    static void testStatusChangeFromAcceptedDoesNotNotify() {
        Account mentor = [SELECT Id FROM Account WHERE Name = 'Mentor One' LIMIT 1];
        Account mentee = [SELECT Id FROM Account WHERE Name = 'Mentee One' LIMIT 1];

        Ken_Mentorship__c m = new Ken_Mentorship__c(
            RecordTypeId         = connectionRtId(),
            Mentor__c            = mentor.Id,
            Mentee__c            = mentee.Id,
            Mentorship_Status__c = 'Accepted'
        );
        insert m;

        delete [
            SELECT Id FROM Ken_Notification__c WHERE Recipient__c IN (:mentor.Id, :mentee.Id)
        ];

        Test.startTest();
        m.Mentorship_Status__c = 'Cancelled';
        update m;
        Test.stopTest();

        Integer count = [
            SELECT COUNT() FROM Ken_Notification__c WHERE Recipient__c IN (:mentor.Id, :mentee.Id)
        ];
        System.assertEquals(0, count, 'No new notification should be created when transitioning out of Accepted');
    }

    private static Id connectionRtId() {
        return [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c'
              AND DeveloperName = 'Connection_Request'
            LIMIT 1
        ].Id;
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