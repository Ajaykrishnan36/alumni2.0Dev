public without sharing class KenAlumniSpotlightController {

    @AuraEnabled(cacheable=true)
    public static List<SpotlightRow> getAlumniSpotlights() {
        Date today = Date.today();
        List<KenAlumniSpotlight__c> records = [
            SELECT Id, Name, Title__c, Description__c, Content_Link__c, Display_Order__c, Type__c
            FROM KenAlumniSpotlight__c
            WHERE Is_Active__c = true
              AND (Featured_From__c = null OR Featured_From__c <= :today)
              AND (Featured_To__c   = null OR Featured_To__c   >= :today)
            ORDER BY Display_Order__c ASC NULLS LAST
            LIMIT 20
        ];

        List<SpotlightRow> rows = new List<SpotlightRow>();
        for (KenAlumniSpotlight__c r : records) {
            SpotlightRow row    = new SpotlightRow();
            row.id              = r.Id;
            row.name            = r.Name;
            row.title           = r.Title__c;
            row.description     = r.Description__c;
            row.contentLink     = r.Content_Link__c;
            row.displayOrder    = r.Display_Order__c != null ? Integer.valueOf(r.Display_Order__c) : 0;
            row.contentType     = r.Type__c;
            rows.add(row);
        }
        return rows;
    }

    public class SpotlightRow {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  title;
        @AuraEnabled public String  description;
        @AuraEnabled public String  contentLink;
        @AuraEnabled public Integer displayOrder;
        @AuraEnabled public String  contentType;
    }
}