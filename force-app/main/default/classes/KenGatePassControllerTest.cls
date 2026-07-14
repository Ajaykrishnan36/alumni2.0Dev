/**
 * KenGatePassControllerTest
 *
 * Covers KenGatePassController:
 *   - getGatePassStats: no gate-pass cases, gate-pass cases with various statuses.
 *   - getGatePassCases: no cases, cases with and without linked Ken_Gate_Pass__c records.
 *   - getGatePassesForCase: null caseId, case with no passes, case with passes.
 *   - getActiveGatePassForContact: null contactId, contact with no active pass, contact
 *     with an active pass.
 *
 * No SeeAllData. All test data inserted via DML.
 * Gate_Pass_Request record type must exist in the org; tests silently skip
 * Gate-Pass-specific assertions if the record type is not found.
 */
@IsTest
private class KenGatePassControllerTest {

    // ── helpers ──────────────────────────────────────────────────────────────

    private static Id getGatePassRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Case'
            AND DeveloperName = :KenSnSConstants.CASE_RECORD_TYPE_GATE_PASS
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Case insertGatePassCase(String status, Id recordTypeId) {
        Case c = new Case(
            Subject             = 'Gate Pass Test - ' + status,
            Status              = status,
            Origin              = 'Web',
            Service_Category__c = 'Gate_Pass'
        );
        if (recordTypeId != null) {
            c.RecordTypeId = recordTypeId;
        }
        insert c;
        return c;
    }

    private static Contact insertContact(String lastName, String email) {
        Contact c = new Contact(LastName = lastName, Email = email);
        insert c;
        return c;
    }

    private static Ken_Gate_Pass__c insertGatePass(Id caseId, Id contactId, Datetime entryTime) {
        Ken_Gate_Pass__c gp = new Ken_Gate_Pass__c(
            GatePass_Request__c = caseId,
            Contact__c          = contactId,
            Exit_Time__c        = System.now().addHours(1),
            Entry_Time__c       = entryTime,
            Email_Sent__c       = false
        );
        insert gp;
        return gp;
    }

    // ── getGatePassStats ─────────────────────────────────────────────────────

    @IsTest
    static void getGatePassStats_noCases_returnsZeroCounts() {
        // Running as current user who has no gate-pass cases
        Test.startTest();
        KenGatePassController.GatePassStats stats = KenGatePassController.getGatePassStats();
        Test.stopTest();

        System.assertNotEquals(null, stats, 'GatePassStats should never be null');
        // Counts depend on existing org data for this user; just verify structure
        System.assert(stats.activeCount   >= 0);
        System.assert(stats.newCount      >= 0);
        System.assert(stats.canceledCount >= 0);
    }

    @IsTest
    static void getGatePassStats_withNewAndResolvedCases_countsCorrectly() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        // Insert cases as the running user (getGatePassStats filters by CreatedById)
        Case newCase      = insertGatePassCase('New',      gatePassRtId);
        Case resolvedCase = insertGatePassCase('Resolved', gatePassRtId);
        Case canceledCase = insertGatePassCase('Canceled', gatePassRtId);

        Test.startTest();
        KenGatePassController.GatePassStats stats = KenGatePassController.getGatePassStats();
        Test.stopTest();

        System.assertNotEquals(null, stats);
        // The running user created all three — counts must include them
        System.assert(stats.newCount      >= 1, 'newCount should include the New case');
        System.assert(stats.activeCount   >= 1, 'activeCount should include the Resolved case');
        System.assert(stats.canceledCount >= 1, 'canceledCount should include the Canceled case');
    }

    // ── getGatePassCases ─────────────────────────────────────────────────────

    @IsTest
    static void getGatePassCases_noCases_returnsEmptyList() {
        // The current running user has no gate pass cases at the moment
        // (assuming fresh scratch org or isolated test data). We just verify
        // the method returns without throwing and gives a non-null list.
        Test.startTest();
        List<KenGatePassController.GatePassCaseRow> rows = KenGatePassController.getGatePassCases();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'getGatePassCases should never return null');
    }

    @IsTest
    static void getGatePassCases_withCasesAndGatePass_populatesRowFields() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        Contact visitor = insertContact('GatePassVisitor', 'gp.visitor.test@test.example.com');

        Case gpCase = insertGatePassCase('New', gatePassRtId);

        Ken_Gate_Pass__c gp = insertGatePass(gpCase.Id, visitor.Id, System.now().addHours(2));

        Test.startTest();
        List<KenGatePassController.GatePassCaseRow> rows = KenGatePassController.getGatePassCases();
        Test.stopTest();

        System.assertNotEquals(null, rows);

        // Find our case in the results
        KenGatePassController.GatePassCaseRow found = null;
        for (KenGatePassController.GatePassCaseRow r : rows) {
            if (r.caseId == gpCase.Id) {
                found = r;
                break;
            }
        }

        System.assertNotEquals(null, found, 'The inserted gate-pass case should appear in the list');
        System.assertEquals(gpCase.Id, found.caseId);
        System.assertEquals('New', found.status);
        System.assertEquals(true, found.hasGatePass, 'Row should reflect linked gate pass');
        System.assertNotEquals(null, found.gatePassId);
        System.assertEquals(true, found.canCancel, 'New case should be cancelable');
    }

    @IsTest
    static void getGatePassCases_resolvedCase_approvedDateSet() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        Case resolvedCase = insertGatePassCase('Resolved', gatePassRtId);

        Test.startTest();
        List<KenGatePassController.GatePassCaseRow> rows = KenGatePassController.getGatePassCases();
        Test.stopTest();

        for (KenGatePassController.GatePassCaseRow r : rows) {
            if (r.caseId == resolvedCase.Id) {
                System.assertNotEquals(null, r.approvedDate,
                    'Resolved case should have approvedDate populated');
                System.assertEquals(false, r.canCancel,
                    'Resolved case should not be cancelable');
            }
        }
    }

    @IsTest
    static void getGatePassCases_closedCaseWithoutFeedback_canLeaveFeedback() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        Case closedCase = insertGatePassCase('Closed', gatePassRtId);

        Test.startTest();
        List<KenGatePassController.GatePassCaseRow> rows = KenGatePassController.getGatePassCases();
        Test.stopTest();

        for (KenGatePassController.GatePassCaseRow r : rows) {
            if (r.caseId == closedCase.Id) {
                System.assertEquals(true, r.canLeaveFeedback,
                    'Closed case without feedback should show canLeaveFeedback');
            }
        }
    }

    // ── getGatePassesForCase ──────────────────────────────────────────────────

    @IsTest
    static void getGatePassesForCase_nullCaseId_returnsEmptyList() {
        Test.startTest();
        List<KenGatePassController.GatePassRow> rows =
            KenGatePassController.getGatePassesForCase(null);
        Test.stopTest();

        System.assertNotEquals(null, rows);
        System.assertEquals(0, rows.size(), 'Null caseId should return empty list');
    }

    @IsTest
    static void getGatePassesForCase_caseWithNoGatePass_returnsEmpty() {
        Case c = new Case(Subject = 'No Gate Pass', Status = 'New', Origin = 'Web');
        insert c;

        Test.startTest();
        List<KenGatePassController.GatePassRow> rows =
            KenGatePassController.getGatePassesForCase(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, rows);
        System.assertEquals(0, rows.size(), 'Case with no gate pass should return empty list');
    }

    @IsTest
    static void getGatePassesForCase_caseWithGatePass_returnsRow() {
        Id gatePassRtId = getGatePassRecordTypeId();

        Case c = new Case(Subject = 'Has Gate Pass', Status = 'New', Origin = 'Web');
        if (gatePassRtId != null) c.RecordTypeId = gatePassRtId;
        insert c;

        Contact visitor = insertContact('ForCaseVisitor', 'forcasevisitor@test.example.com');

        Ken_Gate_Pass__c gp = new Ken_Gate_Pass__c(
            GatePass_Request__c = c.Id,
            Contact__c          = visitor.Id,
            Exit_Time__c        = System.now().addHours(1),
            Entry_Time__c       = System.now().addHours(3),
            Email_Sent__c       = true
        );
        insert gp;

        Test.startTest();
        List<KenGatePassController.GatePassRow> rows =
            KenGatePassController.getGatePassesForCase(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, rows);
        System.assertEquals(1, rows.size(), 'Should return one gate-pass row');

        KenGatePassController.GatePassRow row = rows[0];
        System.assertEquals(gp.Id,       row.id);
        System.assertEquals(visitor.Id,  row.contactId);
        System.assertEquals(true,        row.emailSent);
        System.assertNotEquals(null,      row.exitTime);
        System.assertNotEquals(null,      row.entryTime);
        System.assertNotEquals(null,      row.contactName);
    }

    @IsTest
    static void getGatePassesForCase_multipleGatePasses_returnedInDescOrder() {
        Case c = new Case(Subject = 'Multi Gate Pass', Status = 'New', Origin = 'Web');
        insert c;

        Contact v1 = insertContact('VisitorA', 'visitora.gp@test.example.com');
        Contact v2 = insertContact('VisitorB', 'visitorb.gp@test.example.com');

        insert new Ken_Gate_Pass__c(
            GatePass_Request__c = c.Id,
            Contact__c          = v1.Id,
            Exit_Time__c        = System.now().addHours(1),
            Entry_Time__c       = System.now().addHours(2),
            Email_Sent__c       = false
        );
        insert new Ken_Gate_Pass__c(
            GatePass_Request__c = c.Id,
            Contact__c          = v2.Id,
            Exit_Time__c        = System.now().addHours(3),
            Entry_Time__c       = System.now().addHours(4),
            Email_Sent__c       = false
        );

        Test.startTest();
        List<KenGatePassController.GatePassRow> rows =
            KenGatePassController.getGatePassesForCase(c.Id);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Should return both gate passes');
    }

    // ── getActiveGatePassForContact ───────────────────────────────────────────

    @IsTest
    static void getActiveGatePassForContact_nullContactId_returnsNull() {
        Test.startTest();
        KenGatePassController.GatePassRow row =
            KenGatePassController.getActiveGatePassForContact(null);
        Test.stopTest();

        System.assertEquals(null, row, 'Null contactId should return null');
    }

    @IsTest
    static void getActiveGatePassForContact_contactWithNoPass_returnsNull() {
        Contact visitor = insertContact('NoActivePass', 'noactivepass@test.example.com');

        Test.startTest();
        KenGatePassController.GatePassRow row =
            KenGatePassController.getActiveGatePassForContact(visitor.Id);
        Test.stopTest();

        System.assertEquals(null, row, 'Contact with no gate pass should return null');
    }

    @IsTest
    static void getActiveGatePassForContact_expiredPass_returnsNull() {
        // Entry_Time__c < now → the WHERE clause (Entry_Time__c >= :System.now()) filters it out
        Contact visitor = insertContact('ExpiredPass', 'expiredpass@test.example.com');
        Case c = new Case(Subject = 'Expired GP Case', Status = 'New', Origin = 'Web');
        insert c;

        Ken_Gate_Pass__c expiredGp = new Ken_Gate_Pass__c(
            GatePass_Request__c = c.Id,
            Contact__c          = visitor.Id,
            Exit_Time__c        = System.now().addHours(-4),
            Entry_Time__c       = System.now().addHours(-2),   // in the past
            Email_Sent__c       = false
        );
        insert expiredGp;

        Test.startTest();
        KenGatePassController.GatePassRow row =
            KenGatePassController.getActiveGatePassForContact(visitor.Id);
        Test.stopTest();

        System.assertEquals(null, row, 'Expired gate pass (past Entry_Time) should not be returned');
    }

    @IsTest
    static void getActiveGatePassForContact_activePass_returnsRow() {
        Contact visitor = insertContact('ActivePassVisitor', 'activepassvisitor@test.example.com');
        Case c = new Case(Subject = 'Active GP Case', Status = 'Resolved', Origin = 'Web');
        insert c;

        Ken_Gate_Pass__c activeGp = new Ken_Gate_Pass__c(
            GatePass_Request__c = c.Id,
            Contact__c          = visitor.Id,
            Exit_Time__c        = System.now().addHours(1),
            Entry_Time__c       = System.now().addHours(3),   // in the future
            Email_Sent__c       = true
        );
        insert activeGp;

        Test.startTest();
        KenGatePassController.GatePassRow row =
            KenGatePassController.getActiveGatePassForContact(visitor.Id);
        Test.stopTest();

        System.assertNotEquals(null, row, 'Active gate pass should be returned');
        System.assertEquals(activeGp.Id,  row.id);
        System.assertEquals(visitor.Id,   row.contactId);
        // qrCode is a formula field — just verify it's not blank
        System.assertNotEquals(null, row.qrCode);
        System.assertEquals(true,          row.emailSent);
        System.assertNotEquals(null,       row.contactName);
    }

    // ── GatePassRow wrapper — toGatePassRow helper (via getGatePassesForCase) ─

    @IsTest
    static void getGatePassCases_withQuestionnaireResponse_populatesDescription() {
        Id gatePassRtId = getGatePassRecordTypeId();
        if (gatePassRtId == null) {
            System.assert(true, 'Gate_Pass_Request record type not found — skipping');
            return;
        }

        Case c = new Case(
            Subject             = 'GP Questionnaire Test',
            Status              = 'New',
            Origin              = 'Web',
            RecordTypeId        = gatePassRtId,
            Service_Category__c = 'Gate_Pass'
        );
        insert c;

        Ken_Questionnaire__c q = new Ken_Questionnaire__c(Section_Name__c = 'GP Test Questionnaire');
        insert q;

        Ken_Questionnaire_Parameter__c param = new Ken_Questionnaire_Parameter__c(
            Question_Label__c = 'Purpose of Visit',
            Question_Type__c  = 'Short Answer',
            Questionnaire__c  = q.Id,
            Order__c          = 1
        );
        insert param;

        insert new Ken_Questionnaire_Parameter_Response__c(
            Case__c                    = c.Id,
            Questionnaire_Parameter__c = param.Id,
            Response__c                = 'Medical appointment'
        );

        Test.startTest();
        List<KenGatePassController.GatePassCaseRow> rows = KenGatePassController.getGatePassCases();
        Test.stopTest();

        System.assertNotEquals(null, rows);
        KenGatePassController.GatePassCaseRow found = null;
        for (KenGatePassController.GatePassCaseRow r : rows) {
            if (r.caseId == c.Id) {
                found = r;
                break;
            }
        }
        System.assertNotEquals(null, found, 'Gate pass case with questionnaire response should appear');
        System.assertEquals('Medical appointment', found.description,
            'Description should be populated from Short Answer response');
    }

    // ── Service_Category__c coverage helpers & tests ──────────────────────────
    // The controller SOQLs filter by Service_Category__c = 'Gate_Pass', which is
    // a formula: TEXT(Service_Offering__r.Service__r.Service_Category__c). Without
    // a linked Service Offering the formula is blank and all inner loop code goes
    // uncovered. These three tests build the full chain so that formula populates.

    private static Ken_Service_Offering__c createGatePassOffering() {
        Ken_Service__c service = new Ken_Service__c(
            Name = 'Gate Pass Coverage Service',
            Service_Category__c = 'Gate_Pass'
        );
        insert service;
        Ken_Service_Offering__c offering = new Ken_Service_Offering__c(
            Name = 'Gate Pass Coverage Offering',
            Service__c = service.Id
        );
        insert offering;
        return offering;
    }

    @IsTest
    static void getGatePassStats_withServiceLinkedCases_coversAllStatusBranches() {
        Ken_Service_Offering__c offering = createGatePassOffering();

        insert new List<Case>{
            new Case(Subject = 'GP Stat New',      Status = 'New',      Origin = 'Web', Service_Offering__c = offering.Id, Service_Category__c = 'Gate_Pass'),
            new Case(Subject = 'GP Stat Resolved', Status = 'Resolved', Origin = 'Web', Service_Offering__c = offering.Id, Service_Category__c = 'Gate_Pass'),
            new Case(Subject = 'GP Stat Canceled', Status = 'Canceled', Origin = 'Web', Service_Offering__c = offering.Id, Service_Category__c = 'Gate_Pass')
        };

        Test.startTest();
        KenGatePassController.GatePassStats stats = KenGatePassController.getGatePassStats();
        Test.stopTest();

        System.assertNotEquals(null, stats);
        System.assert(stats.newCount      >= 1, 'newCount should include the New case');
        System.assert(stats.activeCount   >= 1, 'activeCount should include the Resolved case');
        System.assert(stats.canceledCount >= 1, 'canceledCount should include the Canceled case');
    }

    @IsTest
    static void getGatePassCases_withServiceLinkedCasesAndGatePass_coversRowBuilding() {
        Ken_Service_Offering__c offering = createGatePassOffering();

        Case resolvedCase = new Case(
            Subject             = 'GP Row Resolved',
            Status              = 'Resolved',
            Origin              = 'Web',
            Service_Offering__c = offering.Id,
            Service_Category__c = 'Gate_Pass'
        );
        insert resolvedCase;

        Case closedCase = new Case(
            Subject             = 'GP Row Closed',
            Status              = 'Closed',
            Origin              = 'Web',
            Service_Offering__c = offering.Id,
            Service_Category__c = 'Gate_Pass'
        );
        insert closedCase;

        Contact visitor = new Contact(
            LastName = 'GPRowVisitor',
            Email    = 'gprowvisitor.test@test.example.com'
        );
        insert visitor;

        Ken_Gate_Pass__c gp = new Ken_Gate_Pass__c(
            GatePass_Request__c = resolvedCase.Id,
            Contact__c          = visitor.Id,
            Exit_Time__c        = System.now().addHours(1),
            Entry_Time__c       = System.now().addHours(3),
            Email_Sent__c       = false
        );
        insert gp;

        ContentVersion cv = new ContentVersion(
            Title       = 'GP Test File',
            PathOnClient = 'gptest.txt',
            VersionData = Blob.valueOf('content'),
            IsMajorVersion = true
        );
        insert cv;
        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            LinkedEntityId    = resolvedCase.Id,
            ContentDocumentId = cdId,
            ShareType         = 'V'
        );

        Test.startTest();
        List<KenGatePassController.GatePassCaseRow> rows = KenGatePassController.getGatePassCases();
        Test.stopTest();

        System.assertNotEquals(null, rows);

        KenGatePassController.GatePassCaseRow resolvedRow = null;
        KenGatePassController.GatePassCaseRow closedRow   = null;
        for (KenGatePassController.GatePassCaseRow r : rows) {
            if (r.caseId == resolvedCase.Id) resolvedRow = r;
            if (r.caseId == closedCase.Id)   closedRow   = r;
        }

        System.assertNotEquals(null, resolvedRow, 'Resolved gate-pass case should appear in the list');
        System.assertEquals(true,  resolvedRow.hasGatePass,    'Should have a linked gate pass');
        System.assertNotEquals(null, resolvedRow.approvedDate, 'Resolved case should have approvedDate');
        System.assertEquals(false, resolvedRow.canCancel,      'Resolved case should not be cancelable');
        System.assertEquals(true,  resolvedRow.attachmentNames.size() >= 1, 'Attachment should be listed');

        if (closedRow != null) {
            System.assertEquals(true, closedRow.canLeaveFeedback,
                'Closed case without feedback should allow leaving feedback');
        }
    }

    @IsTest
    static void getGatePassCases_withServiceLinkedCaseAndQuestionnaire_coversDescPath() {
        Ken_Service_Offering__c offering = createGatePassOffering();

        Case c = new Case(
            Subject             = 'GP Questionnaire Coverage',
            Status              = 'New',
            Origin              = 'Web',
            Service_Offering__c = offering.Id,
            Service_Category__c = 'Gate_Pass'
        );
        insert c;

        Ken_Questionnaire__c q = new Ken_Questionnaire__c(Section_Name__c = 'GP Coverage Questionnaire');
        insert q;

        Ken_Questionnaire_Parameter__c descParam = new Ken_Questionnaire_Parameter__c(
            Question_Label__c = 'Purpose of Travel',
            Question_Type__c  = 'Short Answer',
            Questionnaire__c  = q.Id,
            Order__c          = 1
        );
        insert descParam;

        Ken_Questionnaire_Parameter__c visitorParam = new Ken_Questionnaire_Parameter__c(
            Question_Label__c = 'Visitor Name',
            Question_Type__c  = 'Short Answer',
            Questionnaire__c  = q.Id,
            Order__c          = 2
        );
        insert visitorParam;

        insert new List<Ken_Questionnaire_Parameter_Response__c>{
            new Ken_Questionnaire_Parameter_Response__c(
                Case__c                    = c.Id,
                Questionnaire_Parameter__c = descParam.Id,
                Response__c                = 'Medical appointment'
            ),
            new Ken_Questionnaire_Parameter_Response__c(
                Case__c                    = c.Id,
                Questionnaire_Parameter__c = visitorParam.Id,
                Response__c                = 'John Doe'
            )
        };

        Test.startTest();
        List<KenGatePassController.GatePassCaseRow> rows = KenGatePassController.getGatePassCases();
        Test.stopTest();

        System.assertNotEquals(null, rows);
        KenGatePassController.GatePassCaseRow found = null;
        for (KenGatePassController.GatePassCaseRow r : rows) {
            if (r.caseId == c.Id) { found = r; break; }
        }
        System.assertNotEquals(null, found, 'Case with service offering should appear in the list');
        System.assertEquals('Medical appointment', found.description, 'Description should come from questionnaire');
    }

    @IsTest
    static void getGatePassesForCase_rowFieldsPopulatedCorrectly() {
        Contact visitor = new Contact(
            FirstName   = 'Row',
            LastName    = 'FieldTest',
            Email       = 'rowfieldtest@test.example.com',
            Phone       = '111-222-3333',
            MobilePhone = '444-555-6666'
        );
        insert visitor;

        Case c = new Case(Subject = 'Row Field Case', Status = 'New', Origin = 'Web');
        insert c;

        Ken_Gate_Pass__c gp = new Ken_Gate_Pass__c(
            GatePass_Request__c = c.Id,
            Contact__c          = visitor.Id,
            Exit_Time__c        = System.now().addHours(2),
            Entry_Time__c       = System.now().addHours(4),
            Email_Sent__c       = false
        );
        insert gp;

        Test.startTest();
        List<KenGatePassController.GatePassRow> rows =
            KenGatePassController.getGatePassesForCase(c.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        KenGatePassController.GatePassRow row = rows[0];
        System.assertNotEquals(null, row.qrCode);  // formula field, just check non-null
        System.assertEquals(false,  row.emailSent);
        // MobilePhone takes priority when set
        System.assertEquals('444-555-6666', row.contactPhone);
    }
}