/**
 * Epic 2 — Application Tracker & Timeline.
 *
 * Returns the ordered Ken_Job_Application_Step__c records for an application PLUS the
 * authoritative server clock as an epoch (ms). The LWC uses serverNowEpoch to compute its
 * skew from the browser clock so the time-gated "Join Meeting" window cannot be spoofed by
 * changing the local machine time.
 *
 * NOT cacheable on purpose — a cached server timestamp would drift and defeat the gate.
 */
public without sharing class KenJobTrackerController {

    public class StepRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String state;            // completed | active | upcoming | rejected
        @AuraEnabled public Decimal stepOrder;
        @AuraEnabled public String locationMode;     // Online | In-Person
        @AuraEnabled public String meetingLink;
        @AuraEnabled public Long scheduledStartEpoch; // ms, null if unset
        @AuraEnabled public Long scheduledEndEpoch;   // ms, null if unset
    }

    public class TrackerResult {
        @AuraEnabled public List<StepRow> steps = new List<StepRow>();
        @AuraEnabled public Long serverNowEpoch;     // authoritative clock for the gate
    }

    @AuraEnabled
    public static TrackerResult getApplicationSteps(Id applicationId) {
        if (applicationId == null) throw new AuraHandledException('Application id is required.');
        TrackerResult res = new TrackerResult();
        res.serverNowEpoch = System.now().getTime();
        for (Ken_Job_Application_Step__c s : [
            SELECT Id, Step_Label__c, State__c, Step_Order__c, Location_Mode__c,
                   Meeting_Link__c, Scheduled_Start__c, Scheduled_End__c
            FROM Ken_Job_Application_Step__c
            WHERE Application__c = :applicationId
            ORDER BY Step_Order__c ASC NULLS LAST
        ]) {
            StepRow r = new StepRow();
            r.id = s.Id;
            r.label = s.Step_Label__c;
            r.state = s.State__c;
            r.stepOrder = s.Step_Order__c;
            r.locationMode = s.Location_Mode__c;
            r.meetingLink = s.Meeting_Link__c;
            r.scheduledStartEpoch = s.Scheduled_Start__c != null ? s.Scheduled_Start__c.getTime() : null;
            r.scheduledEndEpoch   = s.Scheduled_End__c   != null ? s.Scheduled_End__c.getTime()   : null;
            res.steps.add(r);
        }
        return res;
    }
}