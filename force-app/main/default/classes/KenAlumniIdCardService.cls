/**
 * @description Service called when a ConstituentRole transitions to 'Registered'.
 *              Copies Registration_Number__c from ConstituentRole into the matching
 *              Ken_Alumni_CRM__c record (looked up by ConstituentRole__c) and clears
 *              any stale ID_Card_URL__c so the LWC regenerates the ID card.
 *
 *              Each Ken_Alumni_CRM__c is owned by exactly one ConstituentRole, so this
 *              service uses ConstituentRole Id as the primary lookup key.
 */
public with sharing class KenAlumniIdCardService {

    /**
     * @description Initializes ID card data for alumni whose ConstituentRole just
     *              transitioned to 'Registered'. Copies the Registration_Number__c
     *              from the ConstituentRole into the matching Ken_Alumni_CRM__c record
     *              and clears any stale ID_Card_URL__c.
     *
     * @param constituentRoleToRegNumber  Map of ConstituentRole Id → Registration_Number__c.
     */
    public static void initializeForRegistered(Map<Id, String> constituentRoleToRegNumber) {
        if (constituentRoleToRegNumber == null || constituentRoleToRegNumber.isEmpty()) {
            return;
        }

        List<Ken_Alumni_CRM__c> alumniList = [
            SELECT Id, ConstituentRole__c, Registration_Number__c, ID_Card_URL__c
            FROM Ken_Alumni_CRM__c
            WHERE ConstituentRole__c IN :constituentRoleToRegNumber.keySet()
        ];

        if (alumniList.isEmpty()) {
            return;
        }

        List<Ken_Alumni_CRM__c> toUpdate = new List<Ken_Alumni_CRM__c>();
        for (Ken_Alumni_CRM__c alumni : alumniList) {
            String regNumber = constituentRoleToRegNumber.get(alumni.ConstituentRole__c);
            Boolean needsUpdate = false;

            if (String.isNotBlank(regNumber) && regNumber != alumni.Registration_Number__c) {
                alumni.Registration_Number__c = regNumber;
                needsUpdate = true;
            }

            if (String.isNotBlank(alumni.ID_Card_URL__c)) {
                alumni.ID_Card_URL__c = null;
                needsUpdate = true;
            }

            if (needsUpdate) {
                toUpdate.add(alumni);
            }
        }

        if (!toUpdate.isEmpty() && Schema.sObjectType.Ken_Alumni_CRM__c.isUpdateable()) {
            update toUpdate;
        }
    }
}