public with sharing class KenPagePathController {
    
    /**
     * Get service name by service ID
     * @param serviceId The ID of the service record
     * @return The name of the service, or null if not found
     */
    @AuraEnabled(cacheable=true)
    public static String getServiceName(String serviceId) {
        if (String.isBlank(serviceId)) {
            return null;
        }

        try {
            // Get the SObject type from the ID
            Id recordId = Id.valueOf(serviceId);
            Schema.SObjectType sObjectType = recordId.getSObjectType();
            String objectName = sObjectType.getDescribe().getName();
            
            // Build dynamic SOQL query
            String soqlQuery = 'SELECT Name FROM ' + String.escapeSingleQuotes(objectName) + 
                              ' WHERE Id = :serviceId LIMIT 1';
            List<SObject> records = Database.query(soqlQuery);

            if (records != null && !records.isEmpty()) {
                return (String)records[0].get('Name');
            }

            return null;
        } catch (Exception e) {
            System.debug('Error fetching service name: ' + e.getMessage());
            return null;
        }
    }
}