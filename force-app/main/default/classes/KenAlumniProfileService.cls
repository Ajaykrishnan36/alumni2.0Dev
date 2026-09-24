/**
 * @description Resolves the alumni profile facts that used to be stored on
 *              Ken_Alumni_CRM__c from their canonical sources: current employment
 *              comes from PersonEmployment and current location from the Mailing
 *              Ken_Address__c. Every method is bulkified and keyed by Person Account
 *              Id so callers issue one query per page rather than one per row.
 *
 *              Runs without sharing because community users hold no sharing access
 *              to these objects; callers are responsible for scoping the Id set they
 *              pass in.
 */
public without sharing class KenAlumniProfileService {

    /**
     * @description Snapshot of the employment row that counts as an alumnus's
     *              current job.
     */
    public class EmploymentSnapshot {
        @AuraEnabled public String company { get; set; }
        @AuraEnabled public String industry { get; set; }
        @AuraEnabled public String designation { get; set; }
        @AuraEnabled public String location { get; set; }
    }

    /**
     * @description Resolves the current employment for each Person Account. A row
     *              flagged Currently_Employed__c wins; when no row is flagged the
     *              most recent StartDate wins, so alumni whose employment history
     *              has ended still report their last known job. Archived rows are
     *              ignored.
     *
     *              Industry prefers the standard EmploymentIndustry picklist and falls
     *              back to the free-text Industry__c, matching the precedence
     *              KenNetworkController already used. The picklist has no active values
     *              in the client orgs, so in practice the text field is what renders —
     *              it is also the only field able to hold the legacy free-text values
     *              migrated off Ken_Alumni_CRM__c.
     *
     * @param personAccountIds Person Account Ids to resolve. Keep this bounded.
     * @return Map of Person Account Id to its current EmploymentSnapshot. Accounts
     *         with no usable employment row are absent from the map.
     */
    public static Map<Id, EmploymentSnapshot> currentEmployment(Set<Id> personAccountIds) {
        Map<Id, EmploymentSnapshot> result = new Map<Id, EmploymentSnapshot>();
        if (personAccountIds == null || personAccountIds.isEmpty()) {
            return result;
        }

        for (PersonEmployment pe : [
            SELECT AccountId, Company_Name__c, EmploymentIndustry, Industry__c,
                   Designation__c, Location__c
            FROM PersonEmployment
            WHERE AccountId IN :personAccountIds
              AND (Is_Archived__c = false OR Is_Archived__c = null)
            WITH SECURITY_ENFORCED
            ORDER BY Currently_Employed__c DESC, StartDate DESC NULLS LAST
        ]) {
            if (result.containsKey(pe.AccountId)) {
                continue;
            }
            EmploymentSnapshot snap = new EmploymentSnapshot();
            snap.company = pe.Company_Name__c;
            snap.industry = String.isNotBlank(pe.EmploymentIndustry)
                ? pe.EmploymentIndustry
                : pe.Industry__c;
            snap.designation = pe.Designation__c;
            snap.location = pe.Location__c;
            result.put(pe.AccountId, snap);
        }
        return result;
    }

    /**
     * @description Single-record convenience wrapper around currentEmployment.
     *
     * @param personAccountId Person Account to resolve.
     * @return The current EmploymentSnapshot, or null when none exists.
     */
    public static EmploymentSnapshot currentEmployment(Id personAccountId) {
        if (personAccountId == null) {
            return null;
        }
        return currentEmployment(new Set<Id>{ personAccountId }).get(personAccountId);
    }

    /**
     * @description Resolves the display location for each Person Account from its
     *              Mailing Ken_Address__c, formatted as "City, Country" to match the
     *              string Ken_Alumni_CRM__c.Current_Location__c used to hold. Falls
     *              back to whichever of city or country is present.
     *
     * @param personAccountIds Person Account Ids to resolve. Keep this bounded.
     * @return Map of Person Account Id to its formatted location. Accounts with no
     *         Mailing address, or an address carrying neither city nor country, are
     *         absent from the map.
     */
    public static Map<Id, String> currentLocation(Set<Id> personAccountIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (personAccountIds == null || personAccountIds.isEmpty()) {
            return result;
        }

        for (Ken_Address__c addr : [
            SELECT Person_Account__c, City__c, Country__c
            FROM Ken_Address__c
            WHERE Person_Account__c IN :personAccountIds
              AND Address_Type__c = 'Mailing'
            WITH SECURITY_ENFORCED
            ORDER BY LastModifiedDate DESC
        ]) {
            if (result.containsKey(addr.Person_Account__c)) {
                continue;
            }
            String formatted = formatLocation(addr.City__c, addr.Country__c);
            if (String.isNotBlank(formatted)) {
                result.put(addr.Person_Account__c, formatted);
            }
        }
        return result;
    }

    /**
     * @description Single-record convenience wrapper around currentLocation.
     *
     * @param personAccountId Person Account to resolve.
     * @return The formatted location, or null when none exists.
     */
    public static String currentLocation(Id personAccountId) {
        if (personAccountId == null) {
            return null;
        }
        return currentLocation(new Set<Id>{ personAccountId }).get(personAccountId);
    }

    /**
     * @description Joins city and country into the single display string the portal
     *              and Alumni 360 expect.
     *
     * @param city Address city.
     * @param country Address country.
     * @return "City, Country", or whichever part is present, or null when neither is.
     */
    @TestVisible
    private static String formatLocation(String city, String country) {
        Boolean hasCity = String.isNotBlank(city);
        Boolean hasCountry = String.isNotBlank(country);
        if (hasCity && hasCountry) {
            return city.trim() + ', ' + country.trim();
        }
        if (hasCity) {
            return city.trim();
        }
        if (hasCountry) {
            return country.trim();
        }
        return null;
    }
}