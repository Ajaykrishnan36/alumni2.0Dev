/**
 * Mentorship v2.0 — covers the Epic 3 call-request state machine + Epic 1 matchmaking
 * added to KenMentorshipController (respondToCallRequest / proposeReschedule /
 * acceptReschedule / searchMentors).
 */
@isTest
private class KenMentorshipV2StateMachineTest {

    private static Ken_Mentorship__c makeMentorship() {
        Account mentor = new Account(Name = 'Mentor Acct');
        Account mentee = new Account(Name = 'Mentee Acct');
        insert new List<Account>{ mentor, mentee };
        Ken_Mentorship__c m = new Ken_Mentorship__c(
            Mentor__c = mentor.Id, Mentee__c = mentee.Id,
            Call_Request_Status__c = 'Requested', Mentorship_Status__c = 'Requested');
        insert m;
        return m;
    }

    @isTest
    static void proposeThenAcceptReschedule_online() {
        Ken_Mentorship__c m = makeMentorship();
        Date d = Date.today().addDays(5);

        Test.startTest();
        KenMentorshipController.proposeReschedule(m.Id, d, '10:00', '11:00', 'Online',
            'https://meet.google.com/abc-defg-hij', null);
        Test.stopTest();

        Ken_Mentorship__c afterPropose = [
            SELECT Call_Request_Status__c, Proposed_Meet_Date__c, Proposed_Start_Time__c,
                   Proposed_Meeting_Mode__c, Proposed_Meeting_Link__c, Proposed_Meeting_Location__c
            FROM Ken_Mentorship__c WHERE Id = :m.Id];
        System.assertEquals('Reschedule Proposed', afterPropose.Call_Request_Status__c);
        System.assertEquals(d, afterPropose.Proposed_Meet_Date__c);
        System.assertEquals(Time.newInstance(10, 0, 0, 0), afterPropose.Proposed_Start_Time__c);
        System.assertEquals('Online', afterPropose.Proposed_Meeting_Mode__c);
        System.assertEquals('https://meet.google.com/abc-defg-hij', afterPropose.Proposed_Meeting_Link__c);
        System.assertEquals(null, afterPropose.Proposed_Meeting_Location__c, 'no location for online');

        // accept the proposal -> promoted to live fields, overlay cleared
        KenMentorshipController.acceptReschedule(m.Id);
        Ken_Mentorship__c live = [
            SELECT Call_Request_Status__c, Meet_Date__c, Meet_Start_Time__c, Meeting_Mode__c,
                   Meeting_Link__c, Proposed_Meet_Date__c, Proposed_By__c
            FROM Ken_Mentorship__c WHERE Id = :m.Id];
        System.assertEquals('Scheduled', live.Call_Request_Status__c);
        System.assertEquals(d, live.Meet_Date__c, 'proposed date promoted to live');
        System.assertEquals(Time.newInstance(10, 0, 0, 0), live.Meet_Start_Time__c);
        System.assertEquals('Online', live.Meeting_Mode__c);
        System.assertEquals(null, live.Proposed_Meet_Date__c, 'overlay cleared');
    }

    @isTest
    static void proposeReschedule_inPersonUsesLocation() {
        Ken_Mentorship__c m = makeMentorship();
        KenMentorshipController.proposeReschedule(m.Id, Date.today().addDays(2), '14:00', '15:00',
            'In-person', 'https://ignored', '12 Campus Rd, Bengaluru');
        Ken_Mentorship__c rec = [
            SELECT Proposed_Meeting_Mode__c, Proposed_Meeting_Link__c, Proposed_Meeting_Location__c
            FROM Ken_Mentorship__c WHERE Id = :m.Id];
        System.assertEquals('In-person', rec.Proposed_Meeting_Mode__c);
        System.assertEquals(null, rec.Proposed_Meeting_Link__c, 'link dropped for in-person');
        System.assertEquals('12 Campus Rd, Bengaluru', rec.Proposed_Meeting_Location__c);
    }

    @isTest
    static void searchMentorsFiltersByExpertise() {
        Account a1 = new Account(Name = 'Willing Mentor A');
        Account a2 = new Account(Name = 'Willing Mentor B');
        insert new List<Account>{ a1, a2 };
        insert new List<Ken_Alumni_Preferences__c>{
            new Ken_Alumni_Preferences__c(Person_Account__c = a1.Id, Willing_to_be_a_mentor__c = true,
                Mentorship_Expertise_Areas__c = 'Project Management;Design',
                Mentorship_Preferred_Communication_Modes__c = 'Email'),
            new Ken_Alumni_Preferences__c(Person_Account__c = a2.Id, Willing_to_be_a_mentor__c = true,
                Mentorship_Expertise_Areas__c = 'Development',
                Mentorship_Preferred_Communication_Modes__c = 'Whatsapp'),
            // not willing -> excluded
            new Ken_Alumni_Preferences__c(Person_Account__c = a1.Id, Willing_to_be_a_mentor__c = false)
        };

        Test.startTest();
        List<KenMentorshipController.MentorCard> all = KenMentorshipController.searchMentors('', '');
        List<KenMentorshipController.MentorCard> design = KenMentorshipController.searchMentors('design', '');
        List<KenMentorshipController.MentorCard> wapp = KenMentorshipController.searchMentors('', 'Whatsapp');
        Test.stopTest();

        System.assert(all.size() >= 2, 'both willing mentors returned');
        System.assertEquals(1, design.size(), 'expertise filter narrows to Design');
        System.assertEquals(1, wapp.size(), 'communication filter narrows to WhatsApp');
    }

    @isTest
    static void nullGuardsThrow() {
        Integer thrown = 0;
        try { KenMentorshipController.proposeReschedule(null, Date.today(), '9:00', '10:00', 'Online', 'x', null); } catch (AuraHandledException e) { thrown++; }
        try { KenMentorshipController.acceptReschedule(null); } catch (AuraHandledException e) { thrown++; }
        System.assertEquals(2, thrown, 'all null-id calls throw');
    }
}