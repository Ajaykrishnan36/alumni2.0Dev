/**
 * Epic 4 — verifies OrchestrateAcceptedState plus the dashboard split/actions.
 * Inserts several applications for one contact, accepts one, and asserts the rest are
 * systematically locked + withdrawn, while a different contact's application is untouched.
 */
@isTest
private class KenJobOrchestrationTest {

    private static Ken_Job_Master__c job;

    private static Ken_Job_Application__c app(Id contactId, String status, String cycle) {
        return new Ken_Job_Application__c(
            Job__c = job.Id, Applicant__c = contactId, Applicant_Type__c = 'Alumni',
            Status__c = status, Application_State__c = 'inProgress',
            Placement_Cycle__c = cycle);
    }

    @testSetup
    static void setup() {
        Ken_Job_Master__c j = new Ken_Job_Master__c(
            Company__c = 'Acme', Job_Title__c = 'Engineer', Status__c = 'Live');
        insert j;
    }

    private static void loadJob() {
        job = [SELECT Id FROM Ken_Job_Master__c LIMIT 1];
    }

    @isTest
    static void acceptingOneLocksAllCompetitors() {
        loadJob();
        Contact me = new Contact(LastName = 'Primary Applicant');
        Contact other = new Contact(LastName = 'Other Applicant');
        insert new List<Contact>{ me, other };

        Ken_Job_Application__c a1 = app(me.Id, 'Interview', '2025-26');   // -> Interview
        Ken_Job_Application__c a2 = app(me.Id, 'Shortlisted', '2025-26'); // -> Screening
        Ken_Job_Application__c a3 = app(me.Id, 'Offered', '2025-26');     // -> Offer Extended (the one we accept)
        Ken_Job_Application__c x1 = app(other.Id, 'Interview', '2025-26');// different contact, must NOT lock
        insert new List<Ken_Job_Application__c>{ a1, a2, a3, x1 };

        Test.startTest();
        KenJobDashboardController.acceptOffer(a3.Id); // -> Offer Accepted -> orchestration sweep
        Test.stopTest();

        Map<Id, Ken_Job_Application__c> after = new Map<Id, Ken_Job_Application__c>([
            SELECT Id, Locked__c, Current_Stage__c, Closed_Reason__c, Is_Closed__c
            FROM Ken_Job_Application__c]);

        // Accepted record itself
        System.assertEquals('Offer Accepted', after.get(a3.Id).Current_Stage__c);
        System.assertEquals(false, after.get(a3.Id).Locked__c, 'accepted record stays unlocked');

        // Competitors auto-closed
        for (Id cid : new Set<Id>{ a1.Id, a2.Id }) {
            Ken_Job_Application__c r = after.get(cid);
            System.assertEquals(true, r.Locked__c, 'competitor locked');
            System.assertEquals('Withdrawn', r.Current_Stage__c, 'competitor withdrawn');
            System.assertEquals('Auto-closed (offer accepted elsewhere)', r.Closed_Reason__c);
            System.assertEquals(true, r.Is_Closed__c, 'Is_Closed formula reflects lock');
        }

        // Different applicant unaffected
        Ken_Job_Application__c xr = after.get(x1.Id);
        System.assertEquals(false, xr.Locked__c, 'other contact not locked');
        System.assertEquals('Interview', xr.Current_Stage__c);
    }

    @isTest
    static void dashboardSplitsActiveVsClosedWithActions() {
        loadJob();
        Contact me = new Contact(LastName = 'Dashboard Applicant');
        insert me;

        Ken_Job_Application__c active1 = app(me.Id, 'Interview', '2025-26');
        Ken_Job_Application__c offerExtended = app(me.Id, 'Offered', '2025-26');
        Ken_Job_Application__c rejected = app(me.Id, 'Rejected', '2024-25');
        insert new List<Ken_Job_Application__c>{ active1, offerExtended, rejected };
        // give the offer-extended row a stored offer letter to exercise the download URL
        update new Ken_Job_Application__c(Id = offerExtended.Id,
            Offer_Letter_Content_Version__c = '068000000000001');

        KenJobDashboardController.testContactId = me.Id;

        Test.startTest();
        KenJobDashboardController.DashboardResult res =
            KenJobDashboardController.getMyApplications();
        Test.stopTest();

        System.assertEquals(2, res.active.size(), 'Interview + Offer Extended are active');
        System.assertEquals(1, res.closed.size(), 'Rejected is closed');
        System.assert(res.cycles.contains('2025-26') && res.cycles.contains('2024-25'),
            'distinct cycles surfaced for the filter');

        // verify the per-row action flags
        Boolean sawReviewAccept = false, sawDownload = false;
        for (KenJobDashboardController.AppRow r : res.active) {
            if (r.currentStage == 'Offer Extended') {
                sawReviewAccept = r.showReviewAccept;
                sawDownload = r.offerLetterUrl != null && r.offerLetterUrl.contains('068000000000001');
            }
        }
        System.assert(sawReviewAccept, 'Offer Extended row exposes Review/Accept');
        System.assert(sawDownload, 'offer letter download URL built');
    }

    @isTest
    static void acceptOfferNullThrows() {
        Boolean thrown = false;
        try {
            KenJobDashboardController.acceptOffer(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'null application id should throw');
    }
}