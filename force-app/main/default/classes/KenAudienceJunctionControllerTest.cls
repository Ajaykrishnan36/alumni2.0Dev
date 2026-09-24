@isTest
private class KenAudienceJunctionControllerTest {

    private static Id createSegmentation() {
        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Test Audience');
        insert seg;
        return seg.Id;
    }

    @isTest
    static void everyRegisteredModuleCarriesTheAudienceLookup() {
        Map<String, String> registry = KenAudienceJunctionController.PARENT_OBJECT_BY_MODULE;

        System.assertEquals(null, registry.get('Business'),
            'Business must stay unregistered: its Segmentation__c lookup was removed');

        for (String moduleKey : registry.keySet()) {
            String parentObject = registry.get(moduleKey);
            Schema.SObjectType parentType = KenNamespaceUtil.resolveSObjectType(parentObject);
            System.assertNotEquals(null, parentType,
                moduleKey + ' points at a missing object: ' + parentObject);
            System.assert(
                parentType.getDescribe().fields.getMap().containsKey(
                    KenAudienceJunctionController.SEG_FIELD),
                parentObject + ' must carry ' + KenAudienceJunctionController.SEG_FIELD
            );
        }
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
    static void linkSegmentationToParent_eventSetsThenReusesLookup() {
        Id segId = createSegmentation();
        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Linkable Event');
        insert evt;

        Test.startTest();
        Id linked1 = KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, segId);
        Id linked2 = KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, segId);
        Id fetched = KenAudienceJunctionController.getLinkedSegmentation('Event', evt.Id);
        Test.stopTest();

        System.assertEquals(evt.Id, linked1, 'Link should report the parent it wrote');
        System.assertEquals(evt.Id, linked2, 'Re-linking the same audience is a no-op');
        System.assertEquals(segId, fetched, 'Lookup should return the linked segmentation');
        System.assertEquals(segId,
            [SELECT Segmentation__c FROM Ken_Event_Master__c WHERE Id = :evt.Id].Segmentation__c,
            'The audience must be stored on the event itself');
    }

    @isTest
    static void linkSegmentationToParent_replacesAnEarlierAudience() {
        Ken_Segmentation__c first = new Ken_Segmentation__c(Name = 'First Choice');
        Ken_Segmentation__c second = new Ken_Segmentation__c(Name = 'Second Choice');
        insert new List<Ken_Segmentation__c>{ first, second };

        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Switching Event');
        insert evt;

        Test.startTest();
        KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, first.Id);
        KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, second.Id);
        Test.stopTest();

        System.assertEquals(second.Id,
            KenAudienceJunctionController.getLinkedSegmentation('Event', evt.Id),
            'A parent holds one audience — the newer choice must replace the older');
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

        System.assertEquals(srv.Id, surveyLink);
        System.assertEquals(segId, surveyFetch);
        if (grp != null) {
            System.assertEquals(grp.Id, groupLink);
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
            'The event should point at the new segmentation');
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

    /**
     * The shared-elsewhere check has to look across modules, not just within one, or a
     * survey editing an audience a group also uses would mutate it under the group.
     */
    @isTest
    static void saveSegmentationForParent_forksWhenSharedAcrossModules() {
        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Cross Module Audience');
        insert seg;

        Ken_Survey__c srv = new Ken_Survey__c(Name = 'Cross Module Survey');
        insert srv;
        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Cross Module Event');
        insert evt;

        KenAudienceJunctionController.linkSegmentationToParent('Survey', srv.Id, seg.Id);
        KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, seg.Id);

        Test.startTest();
        KenAudienceJunctionController.SaveResultDTO result =
            KenAudienceJunctionController.saveSegmentationForParent(
                'Survey', srv.Id, seg.Id, null, samplePayload('Cross Module Audience'), false);
        Test.stopTest();

        System.assertEquals(true, result.forked,
            'An audience an event also uses must fork rather than be edited in place');
        System.assertEquals(seg.Id,
            KenAudienceJunctionController.getLinkedSegmentation('Event', evt.Id),
            'The event must keep the original audience untouched');
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
    static void saveSegmentationForParent_forkIncrementsCleanlyWithoutCompounding() {
        Ken_Event_Master__c evtA = new Ken_Event_Master__c(Name = 'Compound Event A');
        Ken_Event_Master__c evtB = new Ken_Event_Master__c(Name = 'Compound Event B');
        insert new List<Ken_Event_Master__c>{ evtA, evtB };

        Ken_Segmentation__c root = new Ken_Segmentation__c(Name = 'Compound Audience');
        Ken_Segmentation__c copy = new Ken_Segmentation__c(Name = 'Compound Audience (2)');
        insert new List<Ken_Segmentation__c>{ root, copy };

        KenAudienceJunctionController.linkSegmentationToParent('Event', evtA.Id, copy.Id);
        KenAudienceJunctionController.linkSegmentationToParent('Event', evtB.Id, copy.Id);

        Test.startTest();
        KenAudienceJunctionController.SaveResultDTO result =
            KenAudienceJunctionController.saveSegmentationForParent(
                'Event', evtB.Id, copy.Id, null, samplePayload('Compound Audience (2)'), false);
        Test.stopTest();

        System.assertEquals(true, result.forked);
        System.assertEquals('Compound Audience (3)', result.name,
            'Fork of an already-suffixed copy must increment the root, not compound suffixes');
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

    @isTest
    static void linkSegmentationToParent_eventMirrorsAudienceOntoWrapperSurvey() {
        Id segId = createSegmentation();
        Ken_Survey__c wrapper = new Ken_Survey__c(Name = 'Event Feedback');
        insert wrapper;
        Ken_Event_Master__c evt = new Ken_Event_Master__c(
            Name = 'Mirrored Event',
            Survey__c = wrapper.Id
        );
        insert evt;

        Test.startTest();
        KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, segId);
        Test.stopTest();

        System.assertEquals(segId,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :wrapper.Id].Segmentation__c,
            'Event audience must reach the wrapper survey');
    }

    @isTest
    static void linkSegmentationToParent_nonEventModulesSkipTheSurveyMirror() {
        Id segId = createSegmentation();
        Ken_Survey__c srv = new Ken_Survey__c(Name = 'Standalone Survey');
        insert srv;

        Test.startTest();
        KenAudienceJunctionController.linkSegmentationToParent('Survey', srv.Id, segId);
        Test.stopTest();

        System.assertEquals(segId,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :srv.Id].Segmentation__c,
            'A directly linked survey keeps exactly its own audience');
    }

    @isTest
    static void getAudienceForRecord_describesTheLinkedAudience() {
        Ken_Segmentation__c seg = new Ken_Segmentation__c(
            Name = 'Described Audience',
            Definition_JSON__c = '{"logic":{"audiences":"AND"},"items":[{"title":"Alumni",'
                + '"type":"CUSTOM","memberCount":3,"criteria":[{"label":"Registration Status",'
                + '"values":["Initial Login Done"]}]}]}'
        );
        insert seg;

        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Described Event');
        insert evt;
        KenAudienceJunctionController.linkSegmentationToParent('Event', evt.Id, seg.Id);

        Test.startTest();
        KenAudienceJunctionController.AudienceViewDTO view =
            KenAudienceJunctionController.getAudienceForRecord(evt.Id);
        Test.stopTest();

        System.assertEquals(true, view.hasAudience, 'A linked audience must be reported');
        System.assertEquals('Described Audience', view.segmentationName);
        System.assertEquals('Event', view.moduleLabel);
        System.assertEquals(1, view.blocks.size());
        System.assertEquals('Matching a filter', view.blocks[0].typeLabel);
        System.assertEquals('3 members when last saved', view.reachLabel);
        System.assertEquals('Registration Status is Initial Login Done', view.blocks[0].criteria[0]);
    }

    @isTest
    static void getAudienceForRecord_handlesNullAndUnlinkedRecords() {
        Ken_Event_Master__c evt = new Ken_Event_Master__c(Name = 'Bare Event');
        insert evt;

        Test.startTest();
        KenAudienceJunctionController.AudienceViewDTO nullView =
            KenAudienceJunctionController.getAudienceForRecord(null);
        KenAudienceJunctionController.AudienceViewDTO bareView =
            KenAudienceJunctionController.getAudienceForRecord(evt.Id);
        Test.stopTest();

        System.assertEquals(false, nullView.hasAudience, 'A null recordId has no audience');
        System.assertEquals(false, bareView.hasAudience, 'An unlinked event has no audience');
    }
}