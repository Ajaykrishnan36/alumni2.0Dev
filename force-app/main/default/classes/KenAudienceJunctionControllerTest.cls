@isTest
private class KenAudienceJunctionControllerTest {

    private static Id createSegmentation() {
        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Test Audience');
        insert seg;
        return seg.Id;
    }

    @isTest
    static void getLinkedSegmentation_returnsNullWhenParentIdNull() {
        Test.startTest();
        Id result = KenAudienceJunctionController.getLinkedSegmentation('Event', null);
        Test.stopTest();
        System.assertEquals(null, result, 'Null parentId should yield null');
    }

    @isTest
    static void getLinkedSegmentation_throwsOnUnknownParentType() {
        Id segId = createSegmentation();
        Boolean threw = false;
        Test.startTest();
        try {
            KenAudienceJunctionController.getLinkedSegmentation('Job', segId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Unknown parent type should throw');
    }

    @isTest
    static void linkSegmentationToParent_eventCreatesThenReusesLink() {
        Id segId = createSegmentation();
        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Linkable Event');
        insert evt;

        Test.startTest();
        Id linkId1 = KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, segId);
        Id linkId2 = KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, segId);
        Id fetched = KenAudienceJunctionController.getLinkedSegmentation('Event', evt.Id);
        Test.stopTest();

        System.assertNotEquals(null, linkId1);
        System.assertEquals(linkId1, linkId2, 'Second call should return same link Id');
        System.assertEquals(segId, fetched, 'Lookup should return the linked segmentation');
    }

    @isTest
    static void linkSegmentationToParent_surveyAndGroupRouting() {
        Id segId = createSegmentation();

        Ken_Survey__c srv = new Ken_Survey__c(Name = 'Linkable Survey');
        insert srv;

        Ken_Group__c grp;
        try {
            grp = new Ken_Group__c(Name = 'Linkable Group');
            insert grp;
        } catch (Exception ignored) {
            grp = null;
        }

        Test.startTest();
        Id surveyLink = KenAudienceJunctionController.linkSegmentationToParent('Survey', srv.Id, segId);
        Id surveyFetch = KenAudienceJunctionController.getLinkedSegmentation('Survey', srv.Id);
        Id groupLink;
        Id groupFetch;
        if (grp != null) {
            groupLink = KenAudienceJunctionController.linkSegmentationToParent('Group', grp.Id, segId);
            groupFetch = KenAudienceJunctionController.getLinkedSegmentation('Group', grp.Id);
        }
        Test.stopTest();

        System.assertNotEquals(null, surveyLink);
        System.assertEquals(segId, surveyFetch);
        if (grp != null) {
            System.assertNotEquals(null, groupLink);
            System.assertEquals(segId, groupFetch);
        }
    }

    @isTest
    static void linkSegmentationToParent_throwsWhenIdsMissing() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenAudienceJunctionController.linkSegmentationToParent('Event', null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Missing Ids should throw');
    }

    private static String samplePayload(String name) {
        return '{"name":"' + name + '","targetObject":"ConstituentRole","items":[]}';
    }

    @isTest
    static void saveSegmentationForParent_createsAndLinksNewSegmentation() {
        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Save New Event');
        insert evt;

        Test.startTest();
        KenAudienceJunctionController.SaveResultDTO result =
            KenAudienceJunctionController.saveSegmentationForParent(
                'Event', evt.Id, null, 'Brand New Audience', samplePayload('Brand New Audience'), false);
        Test.stopTest();

        System.assertNotEquals(null, result.segmentationId, 'Segmentation should be created');
        System.assertEquals('Brand New Audience', result.name);
        System.assertEquals(false, result.forked);
        System.assertEquals((Id) result.segmentationId,
            KenAudienceJunctionController.getLinkedSegmentation('Event', evt.Id),
            'Junction should link the event to the new segmentation');
    }

    @isTest
    static void saveSegmentationForParent_updatesInPlaceWhenExclusive() {
        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Exclusive Event');
        insert evt;

        KenAudienceJunctionController.SaveResultDTO first =
            KenAudienceJunctionController.saveSegmentationForParent(
                'Event', evt.Id, null, 'Exclusive Audience', samplePayload('Exclusive Audience'), false);

        Test.startTest();
        KenAudienceJunctionController.SaveResultDTO second =
            KenAudienceJunctionController.saveSegmentationForParent(
                'Event', evt.Id, (Id) first.segmentationId, null, samplePayload('Exclusive Audience'), false);
        Test.stopTest();

        System.assertEquals(first.segmentationId, second.segmentationId,
            'Segmentation used only by this record should be updated in place');
        System.assertEquals(false, second.forked);
        System.assertEquals('Exclusive Audience', second.name, 'Name should be kept on in-place update');
    }

    @isTest
    static void saveSegmentationForParent_forksWhenSharedWithAnotherRecord() {
        Ken_Event_Master__c evtA = new Ken_Event_Master__c(Name = 'Shared Event A');
        Ken_Event_Master__c evtB = new Ken_Event_Master__c(Name = 'Shared Event B');
        insert new List<Ken_Event_Master__c>{ evtA, evtB };

        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Shared Audience');
        insert seg;
        KenAudienceJunctionController.linkSegmentationToParent('Event', evtA.Id, seg.Id);
        KenAudienceJunctionController.linkSegmentationToParent('Event', evtB.Id, seg.Id);

        Test.startTest();
        KenAudienceJunctionController.SaveResultDTO result =
            KenAudienceJunctionController.saveSegmentationForParent(
                'Event', evtB.Id, seg.Id, null, samplePayload('Shared Audience'), false);
        Test.stopTest();

        System.assertNotEquals(seg.Id, (Id) result.segmentationId,
            'Editing a segmentation used by another record must create a new one');
        System.assertEquals(true, result.forked);
        System.assertEquals('Shared Audience (2)', result.name, 'Fork should get a unique suffixed name');
        System.assertEquals((Id) result.segmentationId,
            KenAudienceJunctionController.getLinkedSegmentation('Event', evtB.Id),
            'Event B should be re-pointed to the forked segmentation');
        System.assertEquals(seg.Id,
            KenAudienceJunctionController.getLinkedSegmentation('Event', evtA.Id),
            'Event A must keep the original segmentation');
    }

    @isTest
    static void saveSegmentationForParent_forceForkForksExclusiveSegmentation() {
        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Force Fork Event');
        insert evt;

        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Picked Template');
        insert seg;

        Test.startTest();
        KenAudienceJunctionController.SaveResultDTO result =
            KenAudienceJunctionController.saveSegmentationForParent(
                'Event', evt.Id, seg.Id, null, samplePayload('Picked Template'), true);
        Test.stopTest();

        System.assertNotEquals(seg.Id, (Id) result.segmentationId,
            'forceFork must never mutate the picked segmentation');
        System.assertEquals(true, result.forked);
        System.assertEquals((Id) result.segmentationId,
            KenAudienceJunctionController.getLinkedSegmentation('Event', evt.Id));
    }

    @isTest
    static void saveSegmentationForParent_throwsWithoutPayloadOrName() {
        Boolean threwOnPayload = false;
        Boolean threwOnName = false;
        Test.startTest();
        try {
            KenAudienceJunctionController.saveSegmentationForParent('Event', null, null, 'X', null, false);
        } catch (AuraHandledException e) {
            threwOnPayload = true;
        }
        try {
            KenAudienceJunctionController.saveSegmentationForParent('Event', null, null, null, samplePayload('X'), false);
        } catch (AuraHandledException e) {
            threwOnName = true;
        }
        Test.stopTest();
        System.assert(threwOnPayload, 'Missing payload should throw');
        System.assert(threwOnName, 'Missing name on create should throw');
    }
}