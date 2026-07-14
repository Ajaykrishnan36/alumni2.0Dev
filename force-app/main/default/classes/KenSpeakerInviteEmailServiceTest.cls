@isTest
private class KenSpeakerInviteEmailServiceTest {

    private static Ken_Events_Sessions_Enrollment__c buildSpeaker(Boolean sendInvite, String email) {
        Id eventRt = Schema.SObjectType.Ken_Event_Master__c
            .getRecordTypeInfosByDeveloperName().get('Event').getRecordTypeId();
        Ken_Event_Master__c ev = new Ken_Event_Master__c(
            Name = 'Invite Test Event', RecordTypeId = eventRt, Event_Status__c = 'In Review'
        );
        insert ev;
        Ken_Schedule_Sessions__c sess = new Ken_Schedule_Sessions__c(
            Name = 'Invite Test Session', Event_Reference__c = ev.Id
        );
        insert sess;
        Id spkRt = Schema.SObjectType.Ken_Events_Sessions_Enrollment__c
            .getRecordTypeInfosByDeveloperName().get('Speaker_Enrollment').getRecordTypeId();
        Ken_Events_Sessions_Enrollment__c spk = new Ken_Events_Sessions_Enrollment__c(
            RecordTypeId = spkRt,
            Event_Reference__c = ev.Id,
            Schedule_Sessions__c = sess.Id,
            Speaker_Name__c = 'Jane Speaker',
            Speaker_Email__c = email,
            Send_Invite__c = sendInvite,
            Invite_Email_Sent__c = false
        );
        insert spk;
        return spk;
    }

    @isTest
    static void testInviteSentOnEnqueue() {
        Ken_Events_Sessions_Enrollment__c spk = buildSpeaker(true, 'jane@example.com');
        Id eventId = [SELECT Event_Reference__c FROM Ken_Events_Sessions_Enrollment__c WHERE Id = :spk.Id].Event_Reference__c;

        Test.startTest();
        KenSpeakerInviteEmailService.enqueueForEvents(new Set<Id>{ eventId });
        Test.stopTest(); // queueable executes here -> sends + marks

        Ken_Events_Sessions_Enrollment__c reloaded = [
            SELECT Invite_Email_Sent__c FROM Ken_Events_Sessions_Enrollment__c WHERE Id = :spk.Id
        ];
        System.assertEquals(true, reloaded.Invite_Email_Sent__c, 'Invite should be marked sent');
    }

    @isTest
    static void testNotSentWhenFlagOff() {
        Ken_Events_Sessions_Enrollment__c spk = buildSpeaker(false, 'jane@example.com');
        Id eventId = [SELECT Event_Reference__c FROM Ken_Events_Sessions_Enrollment__c WHERE Id = :spk.Id].Event_Reference__c;

        Test.startTest();
        KenSpeakerInviteEmailService.sendInvitesForEvents(new Set<Id>{ eventId });
        Test.stopTest();

        Ken_Events_Sessions_Enrollment__c reloaded = [
            SELECT Invite_Email_Sent__c FROM Ken_Events_Sessions_Enrollment__c WHERE Id = :spk.Id
        ];
        System.assertEquals(false, reloaded.Invite_Email_Sent__c, 'No invite when Send_Invite__c is off');
    }

    @isTest
    static void testBypass() {
        Alumni_Email_Settings__c s = new Alumni_Email_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Bypass_Speaker_Invite_Email__c = true
        );
        insert s;
        Ken_Events_Sessions_Enrollment__c spk = buildSpeaker(true, 'jane@example.com');
        Id eventId = [SELECT Event_Reference__c FROM Ken_Events_Sessions_Enrollment__c WHERE Id = :spk.Id].Event_Reference__c;

        Test.startTest();
        KenSpeakerInviteEmailService.sendInvitesForEvents(new Set<Id>{ eventId });
        Test.stopTest();

        Ken_Events_Sessions_Enrollment__c reloaded = [
            SELECT Invite_Email_Sent__c FROM Ken_Events_Sessions_Enrollment__c WHERE Id = :spk.Id
        ];
        System.assertEquals(false, reloaded.Invite_Email_Sent__c, 'Bypass should skip sending');
    }
}