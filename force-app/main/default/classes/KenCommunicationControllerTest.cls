/**
 * Tests for KenCommunicationController (controller endpoints + the inner SendQueueable).
 * The module stores no per-recipient custom records: recipients are an
 * Account-Id snapshot on the campaign, sent via setTargetObjectId, and
 * analytics are read from standard objects. Tests therefore verify the
 * snapshot send pipeline and the campaign counters; open data (EmailStatus)
 * is system-populated and not assertable in Apex tests, so it degrades to 0.
 */
@IsTest(SeeAllData=false)
private class KenCommunicationControllerTest {

    @TestSetup
    static void seed() {
        Id paRtId;
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }

        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            Account a = new Account();
            if (paRtId != null) {
                a.RecordTypeId = paRtId;
                a.FirstName = 'Comm';
                a.LastName = 'Test' + i;
                a.PersonEmail = 'comm.test' + i + '@example.test';
            } else {
                a.Name = 'Bridge Comm ' + i;
            }
            accts.add(a);
        }
        insert accts;

        List<ConstituentRole> roles = new List<ConstituentRole>();
        for (Integer i = 0; i < 3; i++) {
            ConstituentRole cr = new ConstituentRole(
                PersonId = accts[i].Id,
                RoleType = 'Alumni',
                Source_Funnel__c = 'Self-Declared Lead',
                Registration_Status__c = 'Initial Login Done',
                Graduation_Year__c = String.valueOf(2018 + i),
                Registration_Number__c = 'COMM-' + i
            );
            cr.put('Status', 'Active');
            roles.add(cr);
        }
        insert roles;

        Ken_Segmentation__c seg = new Ken_Segmentation__c(
            Name = 'All Alumni for Comms Test',
            Active__c = true,
            Target_Object__c = 'ConstituentRole'
        );
        seg.Definition_JSON__c = JSON.serialize(new Map<String, Object>{
            'name' => 'All Alumni',
            'targetObject' => 'ConstituentRole',
            'items' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'all_alumni', 'role' => 'Alumni', 'roleLabel' => 'Alumni',
                    'type' => 'ALL', 'criteria' => new List<Object>()
                }
            }
        });
        insert seg;
    }

    @IsTest
    static void testEndToEndCampaignFlow() {
        Ken_Segmentation__c seg = [SELECT Id FROM Ken_Segmentation__c LIMIT 1];

        Test.startTest();
        List<KenCommunicationController.SegmentationOption> opts = KenCommunicationController.listSegmentations(null);
        System.assert(!opts.isEmpty(), 'Should return the seeded segmentation');
        System.assertEquals(3, KenCommunicationController.previewSegmentationCount(seg.Id), 'Resolves 3 alumni');

        Id campId = KenCommunicationController.saveDraftCampaign(
            null, 'Test Campaign', 'Hello {{FirstName}}',
            '<p>Dear {{FirstName}},</p><p>This is a test.</p>',
            seg.Id, 'Alumni Office', 'alumni@example.test'
        );
        System.assertNotEquals(null, campId);

        KenCommunicationController.sendCampaign(campId, null);

        // Snapshot captured, no recipient records exist.
        Ken_Email_Campaign__c afterSend = [
            SELECT Total_Recipients__c, Status__c, Audience_Snapshot_JSON__c
            FROM Ken_Email_Campaign__c WHERE Id = :campId
        ];
        System.assertEquals(3, afterSend.Total_Recipients__c.intValue(), 'Total = 3');
        System.assert(afterSend.Audience_Snapshot_JSON__c.contains('accountIds'), 'Snapshot stored');

        // Run the send pipeline.
        System.enqueueJob(new KenCommunicationController.SendQueueable(campId, 0));
        Test.stopTest();

        Ken_Email_Campaign__c c = [
            SELECT Status__c, Sent_Count__c, Bounced_Count__c, Failed_Count__c, Total_Recipients__c
            FROM Ken_Email_Campaign__c WHERE Id = :campId
        ];
        System.assert(new Set<String>{'Sent', 'Partially Sent', 'Failed'}.contains(c.Status__c),
            'Reached a terminal status: ' + c.Status__c);
        Integer processed = nz(c.Sent_Count__c) + nz(c.Bounced_Count__c) + nz(c.Failed_Count__c);
        System.assertEquals(3, processed, 'Every recipient accounted for');
    }

    @IsTest
    static void testSendValidationErrors() {
        Ken_Segmentation__c seg = [SELECT Id FROM Ken_Segmentation__c LIMIT 1];

        assertThrows(null, 'null campaign');

        Id noSubj = KenCommunicationController.saveDraftCampaign(null, 'No Subj', null, '<p>B</p>', seg.Id, 'X', 'x@y.test');
        assertThrows(noSubj, 'blank subject');

        Id noBody = KenCommunicationController.saveDraftCampaign(null, 'No Body', 'Subject', null, seg.Id, 'X', 'x@y.test');
        assertThrows(noBody, 'blank body');

        Id noSeg = KenCommunicationController.saveDraftCampaign(null, 'No Seg', 'Subject', '<p>B</p>', null, 'X', 'x@y.test');
        assertThrows(noSeg, 'missing segmentation');
    }

    @IsTest
    static void testScheduleCampaign() {
        Ken_Segmentation__c seg = [SELECT Id FROM Ken_Segmentation__c LIMIT 1];
        Id campId = KenCommunicationController.saveDraftCampaign(
            null, 'Scheduled', 'Subj', '<p>Body</p>', seg.Id, 'X', 'x@y.test'
        );
        Test.startTest();
        KenCommunicationController.sendCampaign(campId, Datetime.now().addHours(1));
        Test.stopTest();
        Ken_Email_Campaign__c c = [SELECT Status__c, Scheduled_DateTime__c FROM Ken_Email_Campaign__c WHERE Id = :campId];
        System.assertEquals('Scheduled', c.Status__c);
        System.assertNotEquals(null, c.Scheduled_DateTime__c);
    }

    @IsTest
    static void testListCampaignsAndRecipients() {
        Ken_Segmentation__c seg = [SELECT Id FROM Ken_Segmentation__c LIMIT 1];
        Id campId = KenCommunicationController.saveDraftCampaign(
            null, 'List Test', 'Subj', '<p>Body</p>', seg.Id, 'X', 'x@y.test'
        );
        Test.startTest();
        KenCommunicationController.sendCampaign(campId, null);
        System.enqueueJob(new KenCommunicationController.SendQueueable(campId, 0));
        Test.stopTest();

        System.assert(!KenCommunicationController.listCampaigns(null, 10).isEmpty(), 'Campaign listed');

        KenCommunicationController.CampaignDTO dto = KenCommunicationController.getCampaign(campId);
        System.assertEquals(campId, dto.id);
        System.assertEquals(3, dto.totalRecipients);

        List<KenCommunicationController.RecipientDTO> rcpts =
            KenCommunicationController.listCampaignRecipients(campId, null, 100);
        System.assertEquals(3, rcpts.size(), 'Recipient table rebuilt from snapshot');
        for (KenCommunicationController.RecipientDTO r : rcpts) {
            System.assertEquals('Sent', r.status, 'No bounce/open in test → Sent');
        }
        // Filter that matches nothing still returns a (possibly empty) list.
        System.assertNotEquals(null, KenCommunicationController.listCampaignRecipients(campId, 'Bounced', 100));
    }

    @IsTest
    static void testResolveSegmentationAccountIds() {
        Ken_Segmentation__c seg = [SELECT Id FROM Ken_Segmentation__c LIMIT 1];
        Test.startTest();
        Set<Id> ids = KenAudienceEngineService.resolveSegmentationAccountIds(seg.Id);
        System.assert(KenAudienceEngineService.resolveSegmentationAccountIds(null).isEmpty());
        System.assert(KenAudienceEngineService.resolveAccountIdsFromPayload(null).isEmpty());
        System.assert(KenAudienceEngineService.resolveAccountIdsFromPayload('not-json').isEmpty());
        Test.stopTest();
        System.assertEquals(3, ids.size());
    }

    private static void assertThrows(Id campaignId, String label) {
        Boolean threw = false;
        try { KenCommunicationController.sendCampaign(campaignId, null); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Expected error for ' + label);
    }

    private static Integer nz(Decimal d) { return d == null ? 0 : Integer.valueOf(d); }
}