/**
 * @description Trigger handler for ConstituentRole after update events.
 *              Handles registration status changes and initiates alumni onboarding
 *              when the status transitions to 'Verified'.
 * @author
 * @since
 */

public with sharing class KenConstituentRoleTriggerHandler extends KenTriggerHandler {

    public override void processAfterUpdate() {
        handleStatusChange();
    }

    @TestVisible
    private static void handleStatusChange() {

        // accountId → constituentRoleId for alumni who just became Verified
        Map<Id, Id> verifiedAccountToRoleId = new Map<Id, Id>();
        // constituentRoleIds for alumni who just became Registered
        Set<Id> registeredRoleIds           = new Set<Id>();

        Map<Id, ConstituentRole> oldMap = (Map<Id, ConstituentRole>) Trigger.oldMap;

        for (ConstituentRole newCr : (List<ConstituentRole>) Trigger.new) {

            if (newCr.PersonId == null) {
                continue;
            }

            if (String.isBlank(newCr.Registration_Status__c)) {
                continue;
            }

            ConstituentRole oldCr = oldMap != null ? oldMap.get(newCr.Id) : null;
            Boolean statusChanged = (oldCr == null) ? true : newCr.Registration_Status__c != oldCr.Registration_Status__c;

            if (statusChanged && newCr.Registration_Status__c == 'Verified') {
                verifiedAccountToRoleId.put(newCr.PersonId, newCr.Id);
            }

            if (statusChanged && newCr.Registration_Status__c == 'Registered') {
                registeredRoleIds.add(newCr.Id);
            }
        }

        if (!verifiedAccountToRoleId.isEmpty()) {
            KenAlumniOnboardingService.processByConstituentRole(verifiedAccountToRoleId);
        }

        if (!registeredRoleIds.isEmpty()) {
            System.enqueueJob(new KenAlumniIdCardQueueable(registeredRoleIds));
        }
    }
}