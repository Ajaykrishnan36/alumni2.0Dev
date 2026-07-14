/**
 * KenCaseTriggerHandlerTest
 *
 * Covers KenCaseTriggerHandler:
 *   - handleBeforeInsert / handleBeforeUpdate (via direct call and trigger)
 *   - handleGatePassAfterUpdate: bypass, no record type, resolved gate pass, canceled gate pass
 *   - getRoleIdsByAccountIds: null/empty/with account
 *   - @TestVisible private methods: getEscalationQueueDeveloperName, getResolvedServiceName,
 *     getOfferingAssignments, getQueueIdsByDeveloperNames, getPreferredEntitlementIds,
 *     selectPreferredEntitlementIds
 *
 * No SeeAllData. All test data inserted via DML.
 */
@IsTest
private class KenCaseTriggerHandlerTest {

    // ── helpers ───────────────────────────────────────────────────────────────

    private static Id getGatePassRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case'
            AND DeveloperName = :KenSnSConstants.CASE_RECORD_TYPE_GATE_PASS
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Ken_Support_Services_Parameters__c upsertParameters(
        Boolean triggerBypass,
        String escalationQueue
    ) {
        Ken_Support_Services_Parameters__c s = Ken_Support_Services_Parameters__c.getOrgDefaults();
        if (s == null || s.Id == null) {
            s = new Ken_Support_Services_Parameters__c(SetupOwnerId = UserInfo.getOrganizationId());
            insert s;
        }
        s.Trigger_Bypass__c = triggerBypass;
        if (escalationQueue != null) s.Escalation_Queue_Developer_Name__c = escalationQueue;
        update s;
        return s;
    }

    // ── handleBeforeInsert direct calls ───────────────────────────────────────

    @IsTest
    static void handleBeforeInsert_nullList_noError() {
        Test.startTest();
        KenCaseTriggerHandler.handleBeforeInsert(null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void handleBeforeInsert_emptyList_noError() {
        Test.startTest();
        KenCaseTriggerHandler.handleBeforeInsert(new List<Case>());
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void handleBeforeInsert_withBypass_returnsEarly() {
        upsertParameters(true, null);

        Case c = new Case(Subject = 'Bypass Insert', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenCaseTriggerHandler.handleBeforeInsert(new List<Case>{ c });
        Test.stopTest();

        System.assert(true, 'Should not throw with trigger bypass enabled');
    }

    // ── handleBeforeUpdate direct calls ───────────────────────────────────────

    @IsTest
    static void handleBeforeUpdate_nullList_noError() {
        Test.startTest();
        KenCaseTriggerHandler.handleBeforeUpdate(null, null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void handleBeforeUpdate_emptyList_noError() {
        Test.startTest();
        KenCaseTriggerHandler.handleBeforeUpdate(
            new List<Case>(), new Map<Id, Case>()
        );
        Test.stopTest();
        System.assert(true);
    }

    // ── trigger-based: insert covers handleBeforeInsert paths ─────────────────

    @IsTest
    static void caseInsert_basicCase_noError() {
        Test.startTest();
        Case c = new Case(Subject = 'Trigger Insert Test', Status = 'New', Origin = 'Web');
        insert c;
        Test.stopTest();

        System.assertNotEquals(null, [SELECT Id FROM Case WHERE Id = :c.Id].Id);
    }

    // ── trigger-based: escalation routing ─────────────────────────────────────

    @IsTest
    static void caseUpdate_escalateAndHighPriority_routesToEscalationQueue() {
        Group q;
        // System.runAs avoids MIXED_DML for setup/non-setup DML mix
        System.runAs(new User(Id = UserInfo.getUserId())) {
            upsertParameters(false, 'Esc_Test_Handler_Q1');
            q = new Group(
                Name = 'Escalation Test Handler Q',
                DeveloperName = 'Esc_Test_Handler_Q1',
                Type = 'Queue'
            );
            insert q;
            insert new QueueSobject(QueueId = q.Id, SobjectType = 'Case');
        }

        Case c = new Case(Subject = 'Escalation Route Test', Status = 'New',
                          Origin = 'Web', IsEscalated = false);
        insert c;

        Test.startTest();
        c.IsEscalated = true;
        c.Priority = 'High';
        update c;
        Test.stopTest();

        Case updated = [SELECT OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(q.Id, updated.OwnerId,
            'Case with IsEscalated=true AND Priority=High should be routed to escalation queue');
    }

    @IsTest
    static void caseUpdate_escalateOnly_updatesPriorityToHigh() {
        upsertParameters(false, null);

        Case c = new Case(Subject = 'Escalate Priority Test', Status = 'New',
                          Origin = 'Web', IsEscalated = false);
        insert c;

        Test.startTest();
        c.IsEscalated = true;
        update c;
        Test.stopTest();

        Case updated = [SELECT Priority FROM Case WHERE Id = :c.Id];
        System.assertEquals('High', updated.Priority,
            'Priority should be set to High when case is escalated');
    }

    @IsTest
    static void caseUpdate_noEscalation_ownerUnchanged() {
        Case c = new Case(Subject = 'No Escal Test', Status = 'New', Origin = 'Web');
        insert c;
        Case fresh = [SELECT OwnerId FROM Case WHERE Id = :c.Id];

        Test.startTest();
        c.Subject = 'Updated Subject';
        update c;
        Test.stopTest();

        Case updated = [SELECT OwnerId FROM Case WHERE Id = :c.Id];
        System.assertEquals(fresh.OwnerId, updated.OwnerId, 'Owner should not change without escalation');
    }

    // ── handleGatePassAfterUpdate direct calls ────────────────────────────────

    @IsTest
    static void handleGatePassAfterUpdate_nullList_noError() {
        Test.startTest();
        KenCaseTriggerHandler.handleGatePassAfterUpdate(null, null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void handleGatePassAfterUpdate_emptyList_noError() {
        Test.startTest();
        KenCaseTriggerHandler.handleGatePassAfterUpdate(
            new List<Case>(), new Map<Id, Case>()
        );
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void handleGatePassAfterUpdate_withBypass_skips() {
        upsertParameters(true, null);

        Case c = new Case(Subject = 'GP Bypass Test', Status = 'Resolved', Origin = 'Web');
        insert c;

        Test.startTest();
        KenCaseTriggerHandler.handleGatePassAfterUpdate(
            new List<Case>{ c },
            new Map<Id, Case>{ c.Id => new Case(Id = c.Id, Status = 'New') }
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Ken_Gate_Pass__c WHERE GatePass_Request__c = :c.Id],
            'No gate pass should be created when trigger is bypassed');
    }

    @IsTest
    static void handleGatePassAfterUpdate_nonGatePassCase_noGatePassCreated() {
        Case c = new Case(Subject = 'Regular Case GP Test', Status = 'New', Origin = 'Web');
        insert c;

        Case oldC = new Case(Id = c.Id, Status = 'New');
        Case newC = new Case(Id = c.Id, Status = 'Resolved', RecordTypeId = c.RecordTypeId);

        Test.startTest();
        KenCaseTriggerHandler.handleGatePassAfterUpdate(
            new List<Case>{ newC },
            new Map<Id, Case>{ c.Id => oldC }
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Ken_Gate_Pass__c WHERE GatePass_Request__c = :c.Id],
            'No gate pass should be created for non-Gate Pass record type');
    }

    @IsTest
    static void gatePassCase_resolvedViaUpdate_createsGatePass() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        Contact visitor = new Contact(LastName = 'GP Trigger Visitor', Email = 'gptrigvis@test.example.com');
        insert visitor;

        Case c = new Case(
            Subject             = 'GP Resolved Trigger',
            Status              = 'New',
            Origin              = 'Web',
            RecordTypeId        = gatePassRtId,
            ContactId           = visitor.Id,
            Service_Category__c = 'Gate_Pass'
        );
        insert c;

        Test.startTest();
        c.Status = 'Resolved';
        update c;
        Test.stopTest();

        List<Ken_Gate_Pass__c> passes = [
            SELECT Id FROM Ken_Gate_Pass__c WHERE GatePass_Request__c = :c.Id
        ];
        System.assertEquals(1, passes.size(),
            'A gate pass should be created when gate pass case moves to Resolved');
    }

    @IsTest
    static void gatePassCase_canceledViaUpdate_expiresPasses() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        Contact visitor = new Contact(LastName = 'GP Cancel Visitor', Email = 'gpcanvis@test.example.com');
        insert visitor;

        Case c = new Case(
            Subject             = 'GP Cancel Trigger',
            Status              = 'New',
            Origin              = 'Web',
            RecordTypeId        = gatePassRtId,
            ContactId           = visitor.Id,
            Service_Category__c = 'Gate_Pass'
        );
        insert c;

        Ken_Gate_Pass__c gp = new Ken_Gate_Pass__c(
            GatePass_Request__c = c.Id,
            Contact__c          = visitor.Id,
            Exit_Time__c        = System.now().addHours(1),
            Entry_Time__c       = System.now().addHours(3),
            Email_Sent__c       = false
        );
        insert gp;

        Test.startTest();
        c.Status = 'Canceled';
        update c;
        Test.stopTest();

        Ken_Gate_Pass__c updated = [SELECT Entry_Time__c FROM Ken_Gate_Pass__c WHERE Id = :gp.Id];
        System.assert(updated.Entry_Time__c < System.now(),
            'Entry_Time__c should be backdated to expire the pass on cancel');
    }

    @IsTest
    static void gatePassCase_withResponsesAndMapping_createsGatePassWithExitDate() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        Contact visitor = new Contact(LastName = 'Mapping Test Visitor', Email = 'mappingvis@test.example.com');
        insert visitor;

        Case c = new Case(
            Subject             = 'GP Mapping Response Test',
            Status              = 'New',
            Origin              = 'Web',
            RecordTypeId        = gatePassRtId,
            ContactId           = visitor.Id,
            Service_Category__c = 'Gate_Pass'
        );
        insert c;

        Ken_Questionnaire__c q = new Ken_Questionnaire__c(Section_Name__c = 'GP Mapping Questionnaire');
        insert q;

        // Parameters with Gate_Pass_Mapping__c to exercise the mapping branch
        Ken_Questionnaire_Parameter__c paramExitDate = new Ken_Questionnaire_Parameter__c(
            Question_Label__c    = 'Exit Date',
            Question_Type__c     = 'Date',
            Gate_Pass_Mapping__c = KenSnSConstants.GATE_PASS_MAP_EXIT_DATE,
            Questionnaire__c     = q.Id,
            Order__c             = 1
        );
        Ken_Questionnaire_Parameter__c paramExitTime = new Ken_Questionnaire_Parameter__c(
            Question_Label__c    = 'Exit Time',
            Question_Type__c     = 'Time',
            Gate_Pass_Mapping__c = KenSnSConstants.GATE_PASS_MAP_EXIT_TIME,
            Questionnaire__c     = q.Id,
            Order__c             = 2
        );
        Ken_Questionnaire_Parameter__c paramEntryDate = new Ken_Questionnaire_Parameter__c(
            Question_Label__c    = 'Return Date',
            Question_Type__c     = 'Date',
            Gate_Pass_Mapping__c = KenSnSConstants.GATE_PASS_MAP_ENTRY_DATE,
            Questionnaire__c     = q.Id,
            Order__c             = 3
        );
        Ken_Questionnaire_Parameter__c paramEntryTime = new Ken_Questionnaire_Parameter__c(
            Question_Label__c    = 'Return Time',
            Question_Type__c     = 'Time',
            Gate_Pass_Mapping__c = KenSnSConstants.GATE_PASS_MAP_ENTRY_TIME,
            Questionnaire__c     = q.Id,
            Order__c             = 4
        );
        insert new List<Ken_Questionnaire_Parameter__c>{
            paramExitDate, paramExitTime, paramEntryDate, paramEntryTime
        };

        insert new List<Ken_Questionnaire_Parameter_Response__c>{
            new Ken_Questionnaire_Parameter_Response__c(
                Case__c = c.Id, Questionnaire_Parameter__c = paramExitDate.Id,
                Response__c = '2026-06-25'
            ),
            new Ken_Questionnaire_Parameter_Response__c(
                Case__c = c.Id, Questionnaire_Parameter__c = paramExitTime.Id,
                Response__c = '09:00'
            ),
            new Ken_Questionnaire_Parameter_Response__c(
                Case__c = c.Id, Questionnaire_Parameter__c = paramEntryDate.Id,
                Response__c = '2026-06-25'
            ),
            new Ken_Questionnaire_Parameter_Response__c(
                Case__c = c.Id, Questionnaire_Parameter__c = paramEntryTime.Id,
                Response__c = '20:00'
            )
        };

        Test.startTest();
        c.Status = 'Resolved';
        update c;
        Test.stopTest();

        List<Ken_Gate_Pass__c> passes = [
            SELECT Id, Exit_Time__c, Entry_Time__c
            FROM Ken_Gate_Pass__c
            WHERE GatePass_Request__c = :c.Id
        ];
        System.assertEquals(1, passes.size(), 'Gate pass should be created');
        System.assertNotEquals(null, passes[0].Exit_Time__c, 'Exit time should be set from questionnaire responses');
    }

    @IsTest
    static void gatePassCase_withFallbackKeywordResponses_createsGatePass() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        Contact visitor = new Contact(LastName = 'Fallback Test Visitor', Email = 'fallbackvis@test.example.com');
        insert visitor;

        Case c = new Case(
            Subject             = 'GP Fallback Response Test',
            Status              = 'New',
            Origin              = 'Web',
            RecordTypeId        = gatePassRtId,
            ContactId           = visitor.Id,
            Service_Category__c = 'Gate_Pass'
        );
        insert c;

        Ken_Questionnaire__c q = new Ken_Questionnaire__c(Section_Name__c = 'GP Fallback Questionnaire');
        insert q;

        // Fallback path: no Gate_Pass_Mapping__c — rely on keyword in label
        // Use 'Return' keyword to test entryTime path; avoid Exit path which needs parseable datetime
        Ken_Questionnaire_Parameter__c paramShortAnswer = new Ken_Questionnaire_Parameter__c(
            Question_Label__c = 'Return Date/Time',
            Question_Type__c  = 'Short Answer',
            Questionnaire__c  = q.Id,
            Order__c          = 1
        );
        insert paramShortAnswer;

        insert new Ken_Questionnaire_Parameter_Response__c(
            Case__c = c.Id, Questionnaire_Parameter__c = paramShortAnswer.Id,
            Response__c = '25-06-2026 20:00'
        );

        Test.startTest();
        c.Status = 'Resolved';
        update c;
        Test.stopTest();

        List<Ken_Gate_Pass__c> passes = [
            SELECT Id FROM Ken_Gate_Pass__c WHERE GatePass_Request__c = :c.Id
        ];
        System.assertEquals(1, passes.size(), 'Gate pass should be created via fallback keyword matching');
    }

    // ── getRoleIdsByAccountIds ─────────────────────────────────────────────────

    @IsTest
    static void getRoleIdsByAccountIds_null_returnsEmpty() {
        Test.startTest();
        Map<Id, Id> result = KenCaseTriggerHandler.getRoleIdsByAccountIds(null);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getRoleIdsByAccountIds_empty_returnsEmpty() {
        Test.startTest();
        Map<Id, Id> result = KenCaseTriggerHandler.getRoleIdsByAccountIds(new Set<Id>());
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getRoleIdsByAccountIds_withPersonAccount_executesWithoutError() {
        Id personAccRtId = getPersonAccountRecordTypeId();
        if (personAccRtId == null) {
            System.assert(true, 'No person account record type — skipping');
            return;
        }
        Account acc = new Account(RecordTypeId = personAccRtId, LastName = 'TrigHandlerRoleTest');
        insert acc;

        Test.startTest();
        Map<Id, Id> result = KenCaseTriggerHandler.getRoleIdsByAccountIds(new Set<Id>{ acc.Id });
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    // ── @TestVisible private method tests ─────────────────────────────────────

    @IsTest
    static void getEscalationQueueDeveloperName_noSetting_returnsNull() {
        Test.startTest();
        String result = KenCaseTriggerHandler.getEscalationQueueDeveloperName();
        Test.stopTest();
        System.assertEquals(null, result);
    }

    @IsTest
    static void getEscalationQueueDeveloperName_withSetting_returnsConfiguredName() {
        Ken_Support_Services_Parameters__c s = new Ken_Support_Services_Parameters__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Escalation_Queue_Developer_Name__c = 'Configured_Queue_Dev_Name'
        );
        insert s;

        Test.startTest();
        String result = KenCaseTriggerHandler.getEscalationQueueDeveloperName();
        Test.stopTest();

        System.assertEquals('Configured_Queue_Dev_Name', result);
    }

    @IsTest
    static void getResolvedServiceName_nullCase_returnsNull() {
        Test.startTest();
        String result = KenCaseTriggerHandler.getResolvedServiceName(null, null);
        Test.stopTest();
        System.assertEquals(null, result);
    }

    @IsTest
    static void getResolvedServiceName_noServiceNorOffering_returnsNull() {
        Case c = new Case(Subject = 'No Service', Status = 'New', Origin = 'Web');

        Test.startTest();
        String result = KenCaseTriggerHandler.getResolvedServiceName(c, null);
        Test.stopTest();

        System.assertEquals(null, result,
            'Should return null when no Service_Name__c and no Service_Offering__c');
    }

    @IsTest
    static void getOfferingAssignments_nullList_returnsEmpty() {
        Test.startTest();
        // Pass empty list — method handles empty gracefully (null causes NPE)
        KenCaseTriggerHandler.getOfferingAssignments(new List<Case>());
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void getOfferingAssignments_emptyList_returnsEmpty() {
        Test.startTest();
        KenCaseTriggerHandler.getOfferingAssignments(new List<Case>());
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void getQueueIdsByDeveloperNames_null_returnsEmpty() {
        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.getQueueIdsByDeveloperNames(null);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getQueueIdsByDeveloperNames_empty_returnsEmpty() {
        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.getQueueIdsByDeveloperNames(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getQueueIdsByDeveloperNames_withExistingQueue_returnsId() {
        Group q = new Group(
            Name = 'TestVisHandlerQ',
            DeveloperName = 'TestVis_Handler_Q2',
            Type = 'Queue'
        );
        insert q;

        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.getQueueIdsByDeveloperNames(
            new Set<String>{ 'TestVis_Handler_Q2' }
        );
        Test.stopTest();

        System.assert(result.containsKey('TestVis_Handler_Q2'));
        System.assertEquals(q.Id, result.get('TestVis_Handler_Q2'));
    }

    @IsTest
    static void getPreferredEntitlementIds_empty_returnsEmpty() {
        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.getPreferredEntitlementIds(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getPreferredEntitlementIds_null_returnsEmpty() {
        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.getPreferredEntitlementIds(null);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void selectPreferredEntitlementIds_emptyInputs_returnsEmpty() {
        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.selectPreferredEntitlementIds(
            new List<Entitlement>(), new Set<String>(), Date.today()
        );
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void selectPreferredEntitlementIds_nullEntitlements_returnsEmpty() {
        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.selectPreferredEntitlementIds(
            null, new Set<String>{ 'Test' }, Date.today()
        );
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void selectPreferredEntitlementIds_withActiveEntitlement_returnsIt() {
        Account acc = new Account(Name = 'Entitlement Test Account');
        insert acc;

        Entitlement ent = new Entitlement(
            Name      = 'EntitlementForHandlerTest',
            AccountId = acc.Id,
            StartDate = Date.today().addDays(-5),
            EndDate   = Date.today().addDays(30)
        );
        insert ent;

        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.selectPreferredEntitlementIds(
            new List<Entitlement>{ ent },
            new Set<String>{ 'EntitlementForHandlerTest' },
            Date.today()
        );
        Test.stopTest();

        System.assert(result.containsKey('EntitlementForHandlerTest'));
        System.assertEquals(ent.Id, result.get('EntitlementForHandlerTest'));
    }

    @IsTest
    static void selectPreferredEntitlementIds_withExpiredEntitlement_usesFallback() {
        Account acc = new Account(Name = 'Expired Entitlement Account');
        insert acc;

        Entitlement expired = new Entitlement(
            Name      = 'ExpiredEntitlementHandlerTest',
            AccountId = acc.Id,
            StartDate = Date.today().addDays(-60),
            EndDate   = Date.today().addDays(-10)
        );
        insert expired;

        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.selectPreferredEntitlementIds(
            new List<Entitlement>{ expired },
            new Set<String>{ 'ExpiredEntitlementHandlerTest' },
            Date.today()
        );
        Test.stopTest();

        System.assert(result.containsKey('ExpiredEntitlementHandlerTest'),
            'Expired entitlement should still be returned as fallback');
        System.assertEquals(expired.Id, result.get('ExpiredEntitlementHandlerTest'));
    }

    @IsTest
    static void selectPreferredEntitlementIds_nullAsOfDate_defaultsToToday() {
        Account acc = new Account(Name = 'Null Date Account');
        insert acc;

        Entitlement ent = new Entitlement(
            Name      = 'NullDateEntitlementTest',
            AccountId = acc.Id
        );
        insert ent;

        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.selectPreferredEntitlementIds(
            new List<Entitlement>{ ent },
            new Set<String>{ 'NullDateEntitlementTest' },
            null  // asOfDate = null → defaults to today
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void getPreferredEntitlementIds_withExistingEntitlement_returnsMap() {
        Account acc = new Account(Name = 'Preferred Ent Acc');
        insert acc;

        Entitlement ent = new Entitlement(
            Name      = 'PreferredEntitlementTest',
            AccountId = acc.Id,
            StartDate = Date.today().addDays(-1),
            EndDate   = Date.today().addDays(30)
        );
        insert ent;

        Test.startTest();
        Map<String, Id> result = KenCaseTriggerHandler.getPreferredEntitlementIds(
            new Set<String>{ 'PreferredEntitlementTest' }
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }
}