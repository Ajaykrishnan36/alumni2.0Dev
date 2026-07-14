/**
 * Epic 4 — Application Dashboard.
 *
 *  - getMyApplications(): splits the running alum's applications into Active vs Closed using
 *    the Is_Closed__c formula, and surfaces the per-row action state the LWC renders
 *    (Review/Accept, Congratulations, or Locked). Also returns the distinct Placement Cycles
 *    for the combobox filter.
 *  - acceptOffer(): flips Current_Stage__c to 'Offer Accepted' — the trigger's
 *    OrchestrateAcceptedState then auto-locks every competing application.
 *
 * `without sharing` so a community alum sees their own pipeline regardless of OWD.
 */
public without sharing class KenJobDashboardController {

    private static final String DOWNLOAD_PREFIX = '/sfc/servlet.shepherd/version/download/';

    public class AppRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;          // Application Number
        @AuraEnabled public String jobTitle;
        @AuraEnabled public String currentStage;
        @AuraEnabled public String placementCycle;
        @AuraEnabled public Boolean isClosed;
        @AuraEnabled public Boolean locked;
        @AuraEnabled public String closedReason;
        @AuraEnabled public String offerLetterUrl; // null if no offer letter stored
        // Pre-computed action flags so the template stays declarative.
        @AuraEnabled public Boolean showReviewAccept;
        @AuraEnabled public Boolean showCongrats;
        @AuraEnabled public Boolean showLocked;
    }

    public class DashboardResult {
        @AuraEnabled public List<AppRow> active = new List<AppRow>();
        @AuraEnabled public List<AppRow> closed = new List<AppRow>();
        @AuraEnabled public List<String> cycles = new List<String>();
    }

    @AuraEnabled(cacheable=true)
    public static DashboardResult getMyApplications() {
        Id c = currentContactId();
        DashboardResult res = new DashboardResult();
        Set<String> cycleSet = new Set<String>();
        for (Ken_Job_Application__c a : [
            SELECT Id, Name, Job__r.Name, Current_Stage__c, Placement_Cycle__c,
                   Is_Closed__c, Locked__c, Closed_Reason__c, Offer_Letter_Content_Version__c
            FROM Ken_Job_Application__c
            WHERE Applicant__c = :c
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            AppRow r = new AppRow();
            r.id = a.Id;
            r.name = a.Name;
            r.jobTitle = a.Job__r != null ? a.Job__r.Name : '';
            r.currentStage = a.Current_Stage__c;
            r.placementCycle = a.Placement_Cycle__c;
            r.isClosed = a.Is_Closed__c;
            r.locked = a.Locked__c;
            r.closedReason = a.Closed_Reason__c;
            r.offerLetterUrl = String.isNotBlank(a.Offer_Letter_Content_Version__c)
                ? DOWNLOAD_PREFIX + a.Offer_Letter_Content_Version__c : null;

            r.showLocked = a.Locked__c == true;
            r.showCongrats = !r.showLocked && a.Current_Stage__c == 'Offer Accepted';
            r.showReviewAccept = !r.showLocked && a.Current_Stage__c == 'Offer Extended';

            if (String.isNotBlank(a.Placement_Cycle__c)) cycleSet.add(a.Placement_Cycle__c);
            if (a.Is_Closed__c) res.closed.add(r); else res.active.add(r);
        }
        List<String> cycles = new List<String>(cycleSet);
        cycles.sort();
        res.cycles = cycles;
        return res;
    }

    @AuraEnabled
    public static void acceptOffer(Id applicationId) {
        if (applicationId == null) throw new AuraHandledException('Application id is required.');
        try {
            update new Ken_Job_Application__c(Id = applicationId, Current_Stage__c = 'Offer Accepted');
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
    }

    @TestVisible private static Id testContactId; // test seam — avoids provisioning a portal user

    private static Id currentContactId() {
        if (Test.isRunningTest() && testContactId != null) return testContactId;
        for (User u : [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]) {
            return u.ContactId;
        }
        return null;
    }
}