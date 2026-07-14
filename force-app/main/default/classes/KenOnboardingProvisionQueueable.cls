/**
 * @description Provisions the community user + temporary password for a freshly
 *              onboarded alumni, in its OWN transaction. The V2 onboarding finish
 *              (KenAlumniOnboardingService.saveOnboardingV2) performs non-setup DML
 *              (Account / Ken_Alumni_CRM__c / ConstituentRole) and then enqueues
 *              this job, so the User (setup-object) DML happens in a separate
 *              transaction — avoiding MIXED_DML_OPERATION.
 */
public without sharing class KenOnboardingProvisionQueueable implements Queueable {

    private final Map<Id, Id> accountToRole;

    public KenOnboardingProvisionQueueable(Map<Id, Id> accountToRole) {
        this.accountToRole = accountToRole;
    }

    public void execute(QueueableContext ctx) {
        if (accountToRole == null || accountToRole.isEmpty()) {
            return;
        }
        try {
            KenAlumniOnboardingService.processByConstituentRole(accountToRole);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KenOnboardingProvisionQueueable failed: ' + e.getTypeName() + ' :: ' + e.getMessage());
        }
    }
}