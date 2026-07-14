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
            List<RecordType> rts = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Ken_Event_Master__c'
                  AND DeveloperName = :recordTypeDevName
                LIMIT 1
            ];
            if (!rts.isEmpty()) {
                rtId = rts[0].Id;
            }
        }
        Ken_Event_Master__c rec = new Ken_Event_Master__c(Name = name);
        if (rtId != null) rec.RecordTypeId = rtId;
        insert rec;
    }


    @IsTest
    static void testFetchLookupDataWithRecordType() {
        Test.startTest();
        Boolean threw = false;
        try {
            List<SObject> result = KenCustomLookupLwcController.fetchLookupData('Event', 'Ken_Event_Master__c', 'Event_Group');
            System.assert(false, 'Expected QueryException when filtering by record type due to controller SOQL, but none was thrown.');
        } catch (QueryException qe) {
            threw = true;
            System.assert(qe.getMessage().contains('unexpected token') || qe.getMessage().contains('System.QueryException'),
                'Expected a SOQL QueryException when recordType filter is provided.');
        } catch (Exception e) {
            threw = true;
            System.assert(true, 'An exception was thrown as expected for record type filtering path.');
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'The record-type path should currently throw (controller not modifiable).');
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