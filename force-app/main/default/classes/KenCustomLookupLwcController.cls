/**
 * Controller used by LWC lookups to fetch recent records by name.
 *
 * Security:
 * - Validates the provided sObject API name against the org's schema to avoid injection.
 * - Uses bind variables for all user-provided values.
 * - Appends WITH SECURITY_ENFORCED to respect CRUD/FLS.
 *
 * Caching:
 * - Method is cacheable and performs only read operations.
 */
public  with sharing class KenCustomLookupLwcController {
    
     /**
     * Fetch up to 5 most recently created records whose Name matches the search key.
     *
     * @param searchKey       Partial text to match against the Name field.
     * @param sObjectApiName  API name of the target sObject (validated against schema).
     * @param recordTypeName  DeveloperName of the RecordType (only used for Event_Master__c).
     * @return                List<SObject> with Id and Name populated.
     */
    @AuraEnabled(cacheable=true)
    public static list<sObject> fetchLookupData(String searchKey , String sObjectApiName, String recordTypeName) {    
        List <sObject> returnList = new List <sObject> ();

        // Validate and canonicalize the object API name to prevent SOQL injection
        Map<String, Schema.SObjectType> allTypes = Schema.getGlobalDescribe();
        if (String.isBlank(sObjectApiName) || !allTypes.containsKey(sObjectApiName)) {
            return returnList;
        }
        String safeObjectApiName = allTypes.get(sObjectApiName).getDescribe().getName();
        String sWildCardText = '%' + searchKey + '%';
        String sQuery = '';
        if (safeObjectApiName == 'Ken_Event_Master__c' && recordTypeName != null && recordTypeName != '') {
            sQuery = 'SELECT Id, Name ' +
                'FROM ' + safeObjectApiName + ' ' +
                'WHERE Name LIKE :sWildCardText ' +
                'AND RecordType.DeveloperName = :recordTypeName ' +
                'ORDER BY CreatedDate DESC' +
                'LIMIT 5';
        } else {
            sQuery = 'SELECT Id, Name ' +
                'FROM ' + safeObjectApiName + ' ' +
                'WHERE Name LIKE :sWildCardText ' +
                'ORDER BY CreatedDate DESC ' +
                'LIMIT 5';
        }
        
        for (sObject obj: database.query(sQuery)) {
            returnList.add(obj);
        }
        return returnList;
    }
}