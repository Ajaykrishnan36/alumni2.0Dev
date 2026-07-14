/**
 * Foundation trigger handler for Ken_Job_Application__c (Jobs v2.0 Phase 2).
 *
 *  - maintainCurrentStage()  (before insert/update): the state machine that keeps the
 *    governed Current_Stage__c (Ken_Job_Stage_Set) in sync, while respecting an explicit
 *    user/admin override.
 *  - calculateRollups()      (after insert/update/delete/undelete): replaces the native
 *    roll-up lost when Job__c was converted from Master-Detail to Lookup, by maintaining
 *    Ken_Job_Master__c.Application_Count__c.
 *
 * Honors KenTriggerHandler.skipTrigger for data-load bypass.
 */
public without sharing class KenJobApplicationTriggerHandler extends KenTriggerHandler {

    // Status__c (existing) → Current_Stage__c (Ken_Job_Stage_Set). Unmapped statuses
    // leave the stage untouched so manual stages (Aptitude/HR/Withdrawn) are preserved.
    private static final Map<String, String> STATUS_TO_STAGE = new Map<String, String>{
        'Applied'      => 'Applied',
        'Submitted'    => 'Applied',
        'Under Review' => 'Screening',
        'Shortlisted'  => 'Screening',
        'Interview'    => 'Interview',
        'Ongoing'      => 'Interview',
        'Offered'      => 'Offer Extended',
        'Approved'     => 'Offer Accepted',
        'Hired'        => 'Offer Accepted',
        'Rejected'     => 'Rejected'
    };

    // Re-entrancy guard for the offer-accepted lockout sweep (the sweep itself issues an
    // update that re-fires after-update on the competing records).
    @TestVisible private static Boolean orchestrating = false;

    // Stages that are already terminal — never re-lock or re-close these.
    private static final Set<String> CLOSED_STAGES = new Set<String>{
        'Offer Accepted', 'Rejected', 'Withdrawn'
    };

    protected override void processBeforeInsert() { maintainCurrentStage(); }
    protected override void processBeforeUpdate() { maintainCurrentStage(); }
    protected override void processAfterInsert()   { calculateRollups(); }
    protected override void processAfterUpdate()   { calculateRollups(); orchestrateAcceptedState(); }
    protected override void processAfterDelete()   { calculateRollups(); }
    protected override void processAfterUndelete() { calculateRollups(); }

    /**
     * OrchestrateAcceptedState — when an application transitions to 'Offer Accepted',
     * atomically lock + withdraw every other still-open application for that same applicant.
     * Wrapped in a Savepoint so a partial failure rolls the whole sweep back.
     */
    @TestVisible
    private void orchestrateAcceptedState() {
        if (orchestrating) return; // ignore the recursive update we trigger below
        Map<Id, Ken_Job_Application__c> oldMap =
            (Map<Id, Ken_Job_Application__c>) Trigger.oldMap;

        Set<Id> applicantIds = new Set<Id>();
        Set<Id> acceptedAppIds = new Set<Id>();
        for (Ken_Job_Application__c app : (List<Ken_Job_Application__c>) Trigger.new) {
            Ken_Job_Application__c prior = (oldMap != null) ? oldMap.get(app.Id) : null;
            Boolean becameAccepted = app.Current_Stage__c == 'Offer Accepted'
                && (prior == null || prior.Current_Stage__c != 'Offer Accepted');
            if (becameAccepted && app.Applicant__c != null) {
                applicantIds.add(app.Applicant__c);
                acceptedAppIds.add(app.Id);
            }
        }
        if (applicantIds.isEmpty()) return;

        Savepoint sp = Database.setSavepoint();
        try {
            List<Ken_Job_Application__c> competitors = [
                SELECT Id, Current_Stage__c, Locked__c, Applicant__c
                FROM Ken_Job_Application__c
                WHERE Applicant__c IN :applicantIds
                  AND Id NOT IN :acceptedAppIds
                  AND Locked__c = false
                  AND Current_Stage__c NOT IN :CLOSED_STAGES
            ];
            for (Ken_Job_Application__c comp : competitors) {
                comp.Locked__c = true;
                comp.Current_Stage__c = 'Withdrawn';
                comp.Closed_Reason__c = 'Auto-closed (offer accepted elsewhere)';
            }
            if (!competitors.isEmpty()) {
                orchestrating = true;
                update competitors;
            }
        } catch (Exception e) {
            Database.rollback(sp);
            throw e; // atomic — surface so the accept itself rolls back too
        } finally {
            orchestrating = false;
        }
    }

    /** State machine — derive Current_Stage__c from Status__c unless explicitly overridden. */
    @TestVisible
    private void maintainCurrentStage() {
        Map<Id, Ken_Job_Application__c> oldMap =
            (Map<Id, Ken_Job_Application__c>) Trigger.oldMap;

        for (Ken_Job_Application__c app : (List<Ken_Job_Application__c>) Trigger.new) {
            Ken_Job_Application__c prior = (oldMap != null) ? oldMap.get(app.Id) : null;

            // If the caller explicitly changed Current_Stage__c in this transaction, respect it.
            Boolean stageSetByUser = prior != null && app.Current_Stage__c != prior.Current_Stage__c;
            if (stageSetByUser) continue;

            String mapped = STATUS_TO_STAGE.get(app.Status__c);
            if (mapped != null) {
                app.Current_Stage__c = mapped;
            } else if (String.isBlank(app.Current_Stage__c)) {
                app.Current_Stage__c = 'Applied'; // safe default for new/unmapped records
            }
        }
    }

    /** Recompute Ken_Job_Master__c.Application_Count__c for every affected job. */
    @TestVisible
    private void calculateRollups() {
        Set<Id> jobIds = new Set<Id>();
        if (Trigger.new != null) {
            for (Ken_Job_Application__c a : (List<Ken_Job_Application__c>) Trigger.new) {
                if (a.Job__c != null) jobIds.add(a.Job__c);
            }
        }
        if (Trigger.old != null) {
            // Captures deletes and any reparenting (Job__c changed).
            for (Ken_Job_Application__c a : (List<Ken_Job_Application__c>) Trigger.old) {
                if (a.Job__c != null) jobIds.add(a.Job__c);
            }
        }
        if (jobIds.isEmpty()) return;

        Map<Id, Integer> countByJob = new Map<Id, Integer>();
        for (Id jid : jobIds) countByJob.put(jid, 0);
        for (AggregateResult ar : [
            SELECT Job__c jid, COUNT(Id) cnt
            FROM Ken_Job_Application__c
            WHERE Job__c IN :jobIds
            GROUP BY Job__c
        ]) {
            countByJob.put((Id) ar.get('jid'), (Integer) ar.get('cnt'));
        }

        List<Ken_Job_Master__c> updates = new List<Ken_Job_Master__c>();
        for (Id jid : countByJob.keySet()) {
            updates.add(new Ken_Job_Master__c(Id = jid, Application_Count__c = countByJob.get(jid)));
        }
        if (!updates.isEmpty()) update updates;
    }
}