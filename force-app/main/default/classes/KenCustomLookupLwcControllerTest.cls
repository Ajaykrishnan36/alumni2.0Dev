@IsTest
public class KenCustomLookupLwcControllerTest {

    @testSetup
    static void setupData() {
        createEventMaster('Event 1', 'Event');         // will attach RT if present
        createEventMaster('Event 2', 'Event_Group');   // will attach RT if present
    }

    private static void createEventMaster(String name, String recordTypeDevName) {
        Id rtId = null;
        if (!String.isBlank(recordTypeDevName)) {
            rtId = Schema.SObjectType.Ken_Event_Master__c.getRecordTypeInfosByDeveloperName().get(recordTypeDevName)?.getRecordTypeId();
        }
        Ken_Event_Master__c rec = new Ken_Event_Master__c(Name = name);
        if (rtId != null) rec.RecordTypeId = rtId;
        insert rec;
    }


    @IsTest
    static void testFetchLookupDataWithRecordType() {
        Test.startTest();
        List<SObject> result =
            KenCustomLookupLwcController.fetchLookupData('Event', 'Ken_Event_Master__c', 'Event_Group');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Filtering by record type should return a list, not null.');
        System.assertEquals(
            1,
            result.size(),
            'Only the Event_Group record should match when that record type is requested.'
        );
    }

    @IsTest
    static void testFetchLookupDataWithoutRecordType() {
        Test.startTest();
        List<SObject> result = KenCustomLookupLwcController.fetchLookupData('Event', 'Ken_Event_Master__c', null);
        Test.stopTest();

        System.assert(result != null, 'fetchLookupData should not return null when record type filter is not provided.');
        System.assertEquals(2, result.size(), 'Expected 2 records when no record type filter is provided.');
        System.assert(
            String.valueOf(result[0].get('Name')).contains('Event') ||
            (result.size() > 1 && String.valueOf(result[1].get('Name')).contains('Event')),
            'At least one returned record name should contain "Event".'
        );
    }
}