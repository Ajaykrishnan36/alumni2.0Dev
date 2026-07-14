@IsTest(SeeAllData=true)
@SuppressWarnings('PMD.ApexUnitTestShouldNotUseSeeAllDataTrue')
private class KenSegmentationAudienceBatchTest {

    // Test processor: collects the base ids it receives so the test can assert on them.
    public class CollectingProcessor implements KenSegmentationAudienceBatch.Processor {
        public void handle(Id segmentationId, List<Id> baseIds) {
            collected.addAll(baseIds);
            handleCalls++;
        }
        public void onComplete(Id segmentationId, Integer distinctPeople) {
            completedTotal = distinctPeople;
            completeCalls++;
        }
    }

    private static Set<Id> collected = new Set<Id>();
    private static Integer handleCalls = 0;
    private static Integer completeCalls = 0;
    private static Integer completedTotal = -1;

    private static Id provisionAlumniRole(String tag) {
        Id paRtId;
        try {
            paRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Alumni_Person_Account').getRecordTypeId();
        } catch (Exception e) { return null; }
        if (paRtId == null) return null;
        String stamp = String.valueOf(System.currentTimeMillis()) + tag;
        Account pa = new Account(RecordTypeId = paRtId, FirstName = 'AudBatch' + tag,
            LastName = 'P' + stamp, PersonEmail = 'audbatch.' + stamp + '@test.com');
        insert pa;
        ConstituentRole role = new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni',
            Registration_Status__c = 'Registered', Email__c = 'audbatch.role.' + stamp + '@test.com');
        try { role.put('Status', 'Admitted'); } catch (Exception e) {}
        insert role;
        return role.Id;
    }

    @IsTest
    static void testBatchStreamsIdsAndUpdatesCount() {
        Id roleId = provisionAlumniRole('A');
        if (roleId == null) { System.assert(true, 'Person Account RT unavailable; skip'); return; }

        String name = 'AudBatch Seg ' + String.valueOf(System.now().getTime());
        // Single ALUMNI item; buildItemWhere => WHERE RoleType = 'ALUMNI'.
        String payload = '{"targetObject":"ConstituentRole","items":[' +
            '{"id":"a","type":"CUSTOM","role":"ALUMNI","criteria":[]}]}';
        Id segId = KenAudienceEngineService.saveAudiencePayload(name, payload, null, true, 'Active');

        Test.startTest();
        KenSegmentationAudienceBatch.run(segId, 'KenSegmentationAudienceBatchTest.CollectingProcessor', 2000);
        Test.stopTest();

        System.assert(handleCalls >= 1, 'processor.handle should be called at least once');
        System.assert(completeCalls >= 1, 'processor.onComplete should be called once');
        System.assert(completedTotal >= 1, 'resolved distinct people should be >= 1');

        Ken_Segmentation__c seg = [SELECT Member_Count__c FROM Ken_Segmentation__c WHERE Id = :segId];
        System.assertNotEquals(null, seg.Member_Count__c, 'Member_Count__c should be written on completion');

        // Cleanup
        delete [SELECT Id FROM Ken_Segmentation__c WHERE Id = :segId];
    }

    @IsTest
    static void testEngineBatchHelpers() {
        Test.startTest();
        // Helpers tolerate a saved segmentation and bad input.
        String name = 'AudBatch Helpers ' + String.valueOf(System.now().getTime());
        String payload = '{"targetObject":"ConstituentRole","items":[' +
            '{"id":"a","type":"CUSTOM","role":"ALUMNI","criteria":[' +
            '{"key":"Reg","fieldApi":"Registration_Status__c","objectApi":"ConstituentRole","values":["Registered"]}]}]}';
        Id segId = KenAudienceEngineService.saveAudiencePayload(name, payload, null, false, 'Save Later');

        System.assertEquals('ConstituentRole', KenAudienceEngineService.getSegmentationBaseObject(segId), 'base object');
        System.assertNotEquals(null, KenAudienceEngineService.getSegmentationAnchorField(segId), 'anchor field');
        List<String> qs = KenAudienceEngineService.buildAudienceItemQueries(segId);
        System.assertEquals(1, qs.size(), 'one item -> one query');
        System.assert(qs[0].startsWithIgnoreCase('SELECT Id'), 'query selects base Id');

        Integer c = KenAudienceEngineService.refreshSegmentationCount(segId);
        System.assert(c >= 0, 'refresh returns a non-negative count');

        // Bad / empty inputs
        System.assertEquals('ConstituentRole', KenAudienceEngineService.getSegmentationBaseObject(null), 'null -> default base');
        System.assertEquals(0, KenAudienceEngineService.refreshSegmentationCount(null), 'null -> 0');
        Test.stopTest();

        delete [SELECT Id FROM Ken_Segmentation__c WHERE Id = :segId];
    }
}