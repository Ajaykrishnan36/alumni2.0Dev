/**
 * @description Trigger handler for ConstituentRole events.
 *              Handles registration status changes and initiates alumni onboarding
 *              when the status transitions to 'Onboarding In Progress', and keeps the
 *              stamped institute code in step with the role's program plan.
 * @author
 * @since
 */

public with sharing class KenConstituentRoleTriggerHandler extends KenTriggerHandler {

    public override void processBeforeInsert() {
        KenInstitutePopulationService.stampInstitute(Trigger.new, Trigger.oldMap);
    }

    public override void processBeforeUpdate() {
        KenInstitutePopulationService.stampInstitute(Trigger.new, Trigger.oldMap);
    }

    public override void processAfterInsert() {
        fanOutInstituteChanges();
    }

    public override void processAfterUpdate() {
        handleStatusChange();
        fanOutInstituteChanges();
    }

    /**
     * @description Pushes the new institute code out to the person Account and every related
     *              alumni record, but only for people whose stamped value actually moved.
     */
    @TestVisible
    private static void fanOutInstituteChanges() {

        Map<Id, ConstituentRole> oldMap = (Map<Id, ConstituentRole>) Trigger.oldMap;
        Set<Id> accountIds = new Set<Id>();

        for (ConstituentRole newCr : (List<ConstituentRole>) Trigger.new) {

            if (newCr.PersonId == null) {
                continue;
            }

            ConstituentRole oldCr = oldMap == null ? null : oldMap.get(newCr.Id);

            if (oldCr == null || newCr.Institute_Name__c != oldCr.Institute_Name__c) {
                accountIds.add(newCr.PersonId);
            }
        }

        KenInstitutePopulationService.enqueueFanout(accountIds);
    }

    @TestVisible
    private static void handleStatusChange() {

        // accountId → constituentRoleId for alumni who just became Verified
        Map<Id, Id> provisionAccountToRoleId = new Map<Id, Id>();

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

            if (statusChanged && newCr.Registration_Status__c == 'Onboarding In Progress') {
                provisionAccountToRoleId.put(newCr.PersonId, newCr.Id);
            }
        }

        if (!provisionAccountToRoleId.isEmpty()) {
            KenAlumniOnboardingService.processByConstituentRole(provisionAccountToRoleId);
        }
    }
}