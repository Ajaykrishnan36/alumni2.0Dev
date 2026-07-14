@IsTest
private class KenAssignmentHelperTest {

    // ─── helpers ────────────────────────────────────────────────────────────

    private static Integer userCounter = 0;

    private static User makeUser(String lastName) {
        userCounter++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            FirstName    = 'Test',
            LastName     = lastName,
            Email        = 'kentest' + userCounter + '@testorg.invalid',
            Username     = 'kentest' + userCounter + Datetime.now().getTime() + '@testorg.invalid',
            Alias        = ('kt' + userCounter).left(8),
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId    = p.Id
        );
        // Wrap in System.runAs to avoid Mixed DML when followed by non-setup DML
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static Group makeQueue(String devName) {
        Group q = new Group(
            Name          = devName,
            DeveloperName = devName,
            Type          = 'Queue'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert q;
        }
        return q;
    }

    private static void addToQueue(Id queueId, Id userId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(GroupId = queueId, UserOrGroupId = userId);
        }
    }

    private static Ken_Assignment_Rule__c makeRule(
        String  name,
        String  refField,
        String  operator,
        String  refValue,
        String  ownerType,
        Id      assignedUser,
        String  assignedQueue,
        Boolean isRoundRobin,
        Integer sequence,
        Boolean isActive
    ) {
        return new Ken_Assignment_Rule__c(
            Name                  = name,
            sObject__c            = 'Case',
            ReferenceField__c     = refField,
            ReferenceFieldType__c = 'Text',
            Operator__c           = operator,
            ReferenceValue__c     = refValue,
            OwnerType__c          = ownerType,
            AssignedUserAsOwner__c = assignedUser,
            AssignedQueue__c      = assignedQueue,
            IsRoundRobin__c       = isRoundRobin,
            Sequence__c           = sequence,
            IsActive__c           = isActive,
            Index__c              = 0
        );
    }

    private static Ken_Assignment_Rule__c makeRule(
        String  name,
        String  refField,
        String  operator,
        String  refValue,
        String  ownerType,
        Id      assignedUser,
        String  assignedQueue,
        Boolean isRoundRobin,
        Integer sequence,
        Boolean isActive,
        String  stage
    ) {
        Ken_Assignment_Rule__c r = makeRule(name, refField, operator, refValue, ownerType,
                                            assignedUser, assignedQueue, isRoundRobin, sequence, isActive);
        r.Stage__c = stage;
        return r;
    }

    // ─── tests ──────────────────────────────────────────────────────────────

    @IsTest
    static void test_emptyList_noError() {
        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>());
        Test.stopTest();
        System.assert(true, 'Should not throw on empty list');
    }

    @IsTest
    static void test_noRules_ownerUnchanged() {
        // No rules → OwnerId stays null
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertEquals(null, c.OwnerId, 'OwnerId should remain null when no active rules exist');
    }

    @IsTest
    static void test_userAssignment() {
        User u = makeUser('AssignUser');
        insert makeRule('User Rule', 'Subject', '=', 'Yoga', 'User', u.Id, null, false, 1, true);

        Case c = new Case(Subject = 'Yoga', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertEquals(u.Id, c.OwnerId, 'OwnerId should be the configured user');
    }

    @IsTest
    static void test_queueAssignment_noRoundRobin() {
        Group q = makeQueue('KenTestDirectQ');
        insert makeRule('Queue Rule', 'Subject', '=', 'Finance', 'Queue', null, 'KenTestDirectQ', false, 1, true);

        Case c = new Case(Subject = 'Finance', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertEquals(q.Id, c.OwnerId, 'OwnerId should be the queue Id');
    }

    @IsTest
    static void test_roundRobin_assignsInOrder() {
        User u1 = makeUser('RROne');
        User u2 = makeUser('RRTwo');
        Group q  = makeQueue('KenTestRRQ');
        addToQueue(q.Id, u1.Id);
        addToQueue(q.Id, u2.Id);

        insert makeRule('RR Rule', 'Subject', '=', 'RR', 'Queue', null, 'KenTestRRQ', true, 1, true);

        Case c1 = new Case(Subject = 'RR', Status = 'New', Origin = 'Web');
        Case c2 = new Case(Subject = 'RR', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c1, c2 });
        Test.stopTest();

        System.assertEquals(u1.Id, c1.OwnerId, 'Case 1 → first queue member');
        System.assertEquals(u2.Id, c2.OwnerId, 'Case 2 → second queue member');

        Ken_Assignment_Rule__c updated = [SELECT Index__c FROM Ken_Assignment_Rule__c LIMIT 1];
        System.assertEquals(2, (Integer) updated.Index__c, 'Index__c should be 2 after 2 assignments');
    }

    @IsTest
    static void test_roundRobin_wrapsAround() {
        User u1 = makeUser('WrapOne');
        User u2 = makeUser('WrapTwo');
        Group q  = makeQueue('KenTestWrapQ');
        addToQueue(q.Id, u1.Id);
        addToQueue(q.Id, u2.Id);

        Ken_Assignment_Rule__c rule = makeRule('Wrap Rule', 'Subject', '=', 'Wrap', 'Queue', null, 'KenTestWrapQ', true, 1, true);
        rule.Index__c = 1; // start at second user
        insert rule;

        Case c1 = new Case(Subject = 'Wrap', Status = 'New', Origin = 'Web');
        Case c2 = new Case(Subject = 'Wrap', Status = 'New', Origin = 'Web');
        Case c3 = new Case(Subject = 'Wrap', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c1, c2, c3 });
        Test.stopTest();

        // Index=1 → u2 | Index=2 (>=size 2) wraps → u1 | Index=1 → u2
        System.assertEquals(u2.Id, c1.OwnerId, 'Case 1 → u2 (index 1)');
        System.assertEquals(u1.Id, c2.OwnerId, 'Case 2 → u1 (index wraps to 0)');
        System.assertEquals(u2.Id, c3.OwnerId, 'Case 3 → u2 (index 1)');
    }

    @IsTest
    static void test_inactiveRule_skipped() {
        User u = makeUser('Inactive');
        insert makeRule('Inactive Rule', 'Subject', '=', 'Test', 'User', u.Id, null, false, 1, false);

        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertNotEquals(u.Id, c.OwnerId, 'Inactive rule must not assign OwnerId');
    }

    @IsTest
    static void test_sequenceOrdering_firstMatchWins() {
        User u1 = makeUser('SeqFirst');
        User u2 = makeUser('SeqSecond');

        insert new List<Ken_Assignment_Rule__c>{
            makeRule('Seq2', 'Subject', '=', 'Seq', 'User', u2.Id, null, false, 2, true),
            makeRule('Seq1', 'Subject', '=', 'Seq', 'User', u1.Id, null, false, 1, true)
        };

        Case c = new Case(Subject = 'Seq', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertEquals(u1.Id, c.OwnerId, 'Rule with Sequence 1 should win over Sequence 2');
    }

    @IsTest
    static void test_operator_notEquals() {
        User u = makeUser('NEOp');
        insert makeRule('NE Rule', 'Subject', '!=', 'Other', 'User', u.Id, null, false, 1, true);

        Case c = new Case(Subject = 'MyCase', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertEquals(u.Id, c.OwnerId, '!= should match when field value differs from rule value');
    }

    @IsTest
    static void test_operator_in() {
        User u = makeUser('INOp');
        insert makeRule('IN Rule', 'Subject', 'IN', 'Yoga;Music;Dance', 'User', u.Id, null, false, 1, true);

        Case c = new Case(Subject = 'Music', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertEquals(u.Id, c.OwnerId, 'IN operator should match when field value is in the list');
    }

    @IsTest
    static void test_operator_notIn() {
        User u = makeUser('NINOp');
        insert makeRule('NOT IN Rule', 'Subject', 'NOT IN', 'Yoga;Music', 'User', u.Id, null, false, 1, true);

        Case c = new Case(Subject = 'Dance', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertEquals(u.Id, c.OwnerId, 'NOT IN should match when field value is not in the list');
    }

    @IsTest
    static void test_noMatchingRule_ownerUnchanged() {
        User u = makeUser('NoMatch');
        insert makeRule('Miss Rule', 'Subject', '=', 'Expected', 'User', u.Id, null, false, 1, true);

        Case c = new Case(Subject = 'Different', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertNotEquals(u.Id, c.OwnerId, 'Non-matching rule must not change OwnerId');
    }

    @IsTest
    static void test_roundRobin_emptyQueue_noError() {
        // Queue exists but has no members → owner stays unchanged, no crash
        makeQueue('KenTestEmptyQ');
        insert makeRule('Empty Q Rule', 'Subject', '=', 'Empty', 'Queue', null, 'KenTestEmptyQ', true, 1, true);

        Case c = new Case(Subject = 'Empty', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertEquals(null, c.OwnerId, 'Empty queue should leave OwnerId unchanged');
    }

    @IsTest
    static void test_bulk_differentRulesPerCase() {
        User u1 = makeUser('BulkOne');
        User u2 = makeUser('BulkTwo');

        insert new List<Ken_Assignment_Rule__c>{
            makeRule('Bulk Yoga',  'Subject', '=', 'Yoga',  'User', u1.Id, null, false, 1, true),
            makeRule('Bulk Music', 'Subject', '=', 'Music', 'User', u2.Id, null, false, 2, true)
        };

        Case c1 = new Case(Subject = 'Yoga',  Status = 'New', Origin = 'Web');
        Case c2 = new Case(Subject = 'Music', Status = 'New', Origin = 'Web');
        Case c3 = new Case(Subject = 'Other', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c1, c2, c3 });
        Test.stopTest();

        System.assertEquals(u1.Id, c1.OwnerId, 'Yoga case → u1');
        System.assertEquals(u2.Id, c2.OwnerId, 'Music case → u2');
        System.assertEquals(null,  c3.OwnerId, 'Unmatched case → no owner set');
    }

    // ── INCLUDES operator ──────────────────────────────────────────────────────

    @IsTest
    static void test_operator_includes() {
        User u = makeUser('INLCUser');
        insert makeRule('INCLUDES Rule', 'Subject', 'INCLUDES', 'Music', 'User', u.Id, null, false, 1, true);
        Case c = new Case(Subject = 'Music', Status = 'New', Origin = 'Web');
        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();
        System.assertEquals(u.Id, c.OwnerId, 'INCLUDES should match when field value contains rule value');
    }

    @IsTest
    static void test_operator_includes_noMatch() {
        User u = makeUser('INLCNoMatch');
        insert makeRule('INCLUDES No Match', 'Subject', 'INCLUDES', 'Dance', 'User', u.Id, null, false, 1, true);
        Case c = new Case(Subject = 'Music', Status = 'New', Origin = 'Web');
        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();
        System.assertNotEquals(u.Id, c.OwnerId, 'INCLUDES should not match when value not in field');
    }

    // ── parseRelationshipFormula (@TestVisible) ────────────────────────────────

    @IsTest
    static void parseRelationshipFormula_validCustomLookup_returnsResolution() {
        Map<String, Schema.SObjectField> caseFieldMap = Schema.SObjectType.Case.fields.getMap();
        Test.startTest();
        KenAssignmentHelper.FormulaResolution res =
            KenAssignmentHelper.parseRelationshipFormula('Service_Offering__r.Name', caseFieldMap);
        Test.stopTest();
        if (caseFieldMap.containsKey('service_offering__c')) {
            System.assertNotEquals(null, res);
            System.assertEquals('Service_Offering__c', res.lookupField);
            System.assertEquals('Name', res.soqlField);
        } else {
            System.assert(true, 'Service_Offering__c not on Case — skipping');
        }
    }

    @IsTest
    static void parseRelationshipFormula_tooShort_returnsNull() {
        Map<String, Schema.SObjectField> caseFieldMap = Schema.SObjectType.Case.fields.getMap();
        Test.startTest();
        KenAssignmentHelper.FormulaResolution res =
            KenAssignmentHelper.parseRelationshipFormula('NoDotsHere', caseFieldMap);
        Test.stopTest();
        System.assertEquals(null, res, 'Formula without dot should return null');
    }

    @IsTest
    static void parseRelationshipFormula_noRelationshipSuffix_returnsNull() {
        Map<String, Schema.SObjectField> caseFieldMap = Schema.SObjectType.Case.fields.getMap();
        Test.startTest();
        KenAssignmentHelper.FormulaResolution res =
            KenAssignmentHelper.parseRelationshipFormula('SomeField.Name', caseFieldMap);
        Test.stopTest();
        System.assertEquals(null, res, 'Formula with no __r suffix should return null');
    }

    @IsTest
    static void parseRelationshipFormula_lookupFieldNotInMap_returnsNull() {
        Map<String, Schema.SObjectField> caseFieldMap = Schema.SObjectType.Case.fields.getMap();
        Test.startTest();
        KenAssignmentHelper.FormulaResolution res =
            KenAssignmentHelper.parseRelationshipFormula('FakeField__r.Name', caseFieldMap);
        Test.stopTest();
        System.assertEquals(null, res, 'Formula with lookup not in fieldMap should return null');
    }

    @IsTest
    static void parseRelationshipFormula_twoHopFormula_returnsNestedSoqlField() {
        Map<String, Schema.SObjectField> caseFieldMap = Schema.SObjectType.Case.fields.getMap();
        Test.startTest();
        KenAssignmentHelper.FormulaResolution res =
            KenAssignmentHelper.parseRelationshipFormula(
                'Service_Offering__r.Service__r.Name', caseFieldMap
            );
        Test.stopTest();
        if (caseFieldMap.containsKey('service_offering__c')) {
            System.assertNotEquals(null, res);
            // Two-hop formula: first hop is removed, soqlField = 'Service__r.Name'
            System.assertEquals('Service__r.Name', res.soqlField);
        } else {
            System.assert(true, 'Skipped — Service_Offering__c not present');
        }
    }

    // ── getNestedValue (@TestVisible) ─────────────────────────────────────────

    @IsTest
    static void getNestedValue_simplePath_returnsValue() {
        Ken_Service__c svc = new Ken_Service__c(Name = 'Nested Test Service');
        insert svc;
        Ken_Service__c freshSvc = [SELECT Id, Name FROM Ken_Service__c WHERE Id = :svc.Id];
        Test.startTest();
        String val = KenAssignmentHelper.getNestedValue(freshSvc, 'Name');
        Test.stopTest();
        System.assertEquals('Nested Test Service', val);
    }

    @IsTest
    static void getNestedValue_nestedPath_returnsNestedValue() {
        Ken_Service__c svc = new Ken_Service__c(Name = 'Parent Service Nested');
        insert svc;
        Ken_Service_Offering__c off = new Ken_Service_Offering__c(Name = 'Child Offering Nested', Service__c = svc.Id);
        insert off;
        Ken_Service_Offering__c freshOff = [
            SELECT Id, Name, Service__r.Name FROM Ken_Service_Offering__c WHERE Id = :off.Id
        ];
        Test.startTest();
        String svcName = KenAssignmentHelper.getNestedValue(freshOff, 'Service__r.Name');
        Test.stopTest();
        System.assertEquals('Parent Service Nested', svcName);
    }

    @IsTest
    static void getNestedValue_nullParentTraversal_returnsNull() {
        // Account.Parent is a valid relationship that is null when no parent is set
        Account acc = new Account(Name = 'No Parent Account');
        Test.startTest();
        String val = KenAssignmentHelper.getNestedValue(acc, 'Parent.Name');
        Test.stopTest();
        System.assertEquals(null, val, 'Null parent traversal should return null');
    }

    @IsTest
    static void getNestedValue_nullFieldValue_returnsNull() {
        Account acc = new Account(Name = 'Test No Phone');
        Test.startTest();
        String val = KenAssignmentHelper.getNestedValue(acc, 'Phone');
        Test.stopTest();
        System.assertEquals(null, val, 'Null field value should return null');
    }

    // ── resolveFormulaFields (@TestVisible) ───────────────────────────────────

    @IsTest
    static void resolveFormulaFields_emptyRules_noError() {
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Web');
        Test.startTest();
        KenAssignmentHelper.resolveFormulaFields(
            new List<SObject>{ c }, new List<Ken_Assignment_Rule__c>(), 'Case'
        );
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void resolveFormulaFields_nonFormulaField_skips() {
        List<Ken_Assignment_Rule__c> rules = new List<Ken_Assignment_Rule__c>{
            makeRule('NoFormula', 'Subject', '=', 'Skip', 'User', UserInfo.getUserId(), null, false, 1, true)
        };
        insert rules;
        Case c = new Case(Subject = 'Skip', Status = 'New', Origin = 'Web');
        Test.startTest();
        KenAssignmentHelper.resolveFormulaFields(new List<SObject>{ c }, rules, 'Case');
        Test.stopTest();
        System.assertEquals('Skip', c.Subject);
    }

    @IsTest
    static void resolveFormulaFields_withFormulaRuleAndOffering_executesWithoutError() {
        Map<String, Schema.SObjectField> caseFieldMap = Schema.SObjectType.Case.fields.getMap();
        String formulaFieldName = null;
        for (String fname : caseFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = caseFieldMap.get(fname).getDescribe();
            if (String.isNotBlank(dfr.getCalculatedFormula())
                && dfr.getCalculatedFormula().contains('__r')) {
                formulaFieldName = dfr.getName();
                break;
            }
        }
        if (formulaFieldName == null) {
            System.assert(true, 'No relationship-formula fields on Case — skipping');
            return;
        }
        List<Ken_Assignment_Rule__c> rules = new List<Ken_Assignment_Rule__c>{
            makeRule('FormulaTestRule', formulaFieldName, '=', 'TestValue',
                     'User', UserInfo.getUserId(), null, false, 1, true)
        };
        insert rules;
        Ken_Service__c svc = new Ken_Service__c(Name = 'Formula Svc');
        insert svc;
        Ken_Service_Offering__c off = new Ken_Service_Offering__c(Name = 'Formula Off', Service__c = svc.Id);
        insert off;
        Case c = new Case(Subject = 'Formula Test', Status = 'New', Origin = 'Web',
                          Service_Offering__c = off.Id);
        Test.startTest();
        KenAssignmentHelper.resolveFormulaFields(new List<SObject>{ c }, rules, 'Case');
        Test.stopTest();
        System.assert(true, 'resolveFormulaFields with formula field should complete without error');
    }

    // ── matchesCriteria (@TestVisible) ────────────────────────────────────────

    @IsTest
    static void matchesCriteria_equalsMatch_returnsTrue() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
        Ken_Assignment_Rule__c rule = makeRule('MC Eq', 'Subject', '=', 'TestSubject',
                                               'User', null, null, false, 1, true);
        Case c = new Case(Subject = 'TestSubject', Status = 'New', Origin = 'Web');
        Test.startTest();
        Boolean result = KenAssignmentHelper.matchesCriteria(c, rule, fieldMap);
        Test.stopTest();
        System.assertEquals(true, result);
    }

    @IsTest
    static void matchesCriteria_equalsNoMatch_returnsFalse() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
        Ken_Assignment_Rule__c rule = makeRule('MC EqNo', 'Subject', '=', 'Expected',
                                               'User', null, null, false, 1, true);
        Case c = new Case(Subject = 'Actual', Status = 'New', Origin = 'Web');
        Test.startTest();
        Boolean result = KenAssignmentHelper.matchesCriteria(c, rule, fieldMap);
        Test.stopTest();
        System.assertEquals(false, result);
    }

    @IsTest
    static void matchesCriteria_includesOperator_returnsTrue() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
        Ken_Assignment_Rule__c rule = makeRule('MC Inc', 'Subject', 'INCLUDES', 'Music',
                                               'User', null, null, false, 1, true);
        Case c = new Case(Subject = 'Music', Status = 'New', Origin = 'Web');
        Test.startTest();
        Boolean result = KenAssignmentHelper.matchesCriteria(c, rule, fieldMap);
        Test.stopTest();
        System.assertEquals(true, result);
    }

    @IsTest
    static void matchesCriteria_unknownOperator_returnsFalse() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
        Ken_Assignment_Rule__c rule = makeRule('MC Unk', 'Subject', 'UNKNOWN_OP', 'X',
                                               'User', null, null, false, 1, true);
        Case c = new Case(Subject = 'X', Status = 'New', Origin = 'Web');
        Test.startTest();
        Boolean result = KenAssignmentHelper.matchesCriteria(c, rule, fieldMap);
        Test.stopTest();
        System.assertEquals(false, result, 'Unknown operator should return false');
    }

    // ── matchesCriteria 4-param (formula override map) ────────────────────────

    @IsTest
    static void matchesCriteria_4param_withMatchingOverride_returnsTrue() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
        Ken_Assignment_Rule__c rule = makeRule('MC4 Override', 'Subject', '=', 'OverrideValue',
                                               'User', null, null, false, 1, true);
        // Record value doesn't match, but override does — override should win
        Case c = new Case(Subject = 'RecordValue', Status = 'New', Origin = 'Web');
        Map<String, Object> overrides = new Map<String, Object>{ 'Subject' => 'OverrideValue' };
        Test.startTest();
        Boolean result = KenAssignmentHelper.matchesCriteria(c, rule, fieldMap, overrides);
        Test.stopTest();
        System.assertEquals(true, result, '4-param matchesCriteria should use override value when present');
    }

    @IsTest
    static void matchesCriteria_4param_overrideNoMatch_returnsFalse() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
        Ken_Assignment_Rule__c rule = makeRule('MC4 OvNoMatch', 'Subject', '=', 'Expected',
                                               'User', null, null, false, 1, true);
        Case c = new Case(Subject = 'Expected', Status = 'New', Origin = 'Web');
        // Override present but value doesn't match rule
        Map<String, Object> overrides = new Map<String, Object>{ 'Subject' => 'WrongValue' };
        Test.startTest();
        Boolean result = KenAssignmentHelper.matchesCriteria(c, rule, fieldMap, overrides);
        Test.stopTest();
        System.assertEquals(false, result, 'Override value that does not match rule should return false');
    }

    @IsTest
    static void matchesCriteria_4param_overrideMissesField_usesRecordValue() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
        Ken_Assignment_Rule__c rule = makeRule('MC4 RecFallback', 'Subject', '=', 'RecordValue',
                                               'User', null, null, false, 1, true);
        Case c = new Case(Subject = 'RecordValue', Status = 'New', Origin = 'Web');
        // Override exists but doesn't cover Subject — should fall back to record value
        Map<String, Object> overrides = new Map<String, Object>();
        Test.startTest();
        Boolean result = KenAssignmentHelper.matchesCriteria(c, rule, fieldMap, overrides);
        Test.stopTest();
        System.assertEquals(true, result, 'Should fall back to record value when field not in override map');
    }

    @IsTest
    static void matchesCriteria_4param_nullOverrides_usesRecordValue() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Case.fields.getMap();
        Ken_Assignment_Rule__c rule = makeRule('MC4 NullOv', 'Subject', '=', 'MyValue',
                                               'User', null, null, false, 1, true);
        Case c = new Case(Subject = 'MyValue', Status = 'New', Origin = 'Web');
        Test.startTest();
        Boolean result = KenAssignmentHelper.matchesCriteria(c, rule, fieldMap, null);
        Test.stopTest();
        System.assertEquals(true, result, 'Null overrides should fall back to record value');
    }

    // ── resolveFormulaFields return value ─────────────────────────────────────

    @IsTest
    static void resolveFormulaFields_returnsNonNullMap() {
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Web');
        Test.startTest();
        Map<SObject, Map<String, Object>> result = KenAssignmentHelper.resolveFormulaFields(
            new List<SObject>{ c }, new List<Ken_Assignment_Rule__c>(), 'Case'
        );
        Test.stopTest();
        System.assertNotEquals(null, result, 'resolveFormulaFields should always return a non-null Map');
        System.assertEquals(0, result.size(), 'Empty rules should produce an empty override map');
    }

    // ── Stage-based overload ───────────────────────────────────────────────────

    @IsTest
    static void test_stagedAssignment_financeStage_assignsCorrectly() {
        User u = makeUser('FinanceStageUser');
        insert makeRule('Finance Stage Rule', 'Subject', '=', 'FinanceCase',
                        'User', u.Id, null, false, 1, true, KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);

        Case c = new Case(Subject = 'FinanceCase', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c }, KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);
        Test.stopTest();

        System.assertEquals(u.Id, c.OwnerId, 'Finance-stage rule should assign owner when Finance stage is requested');
    }

    @IsTest
    static void test_stagedAssignment_blankStageRuleNotMatchedByFinanceStage() {
        User u = makeUser('BlankStageExcluded');
        insert makeRule('Blank Stage Rule', 'Subject', '=', 'FinanceCase',
                        'User', u.Id, null, false, 1, true);
        // Stage__c = null on this rule — must NOT be returned when stage = 'Finance'

        Case c = new Case(Subject = 'FinanceCase', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c }, KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);
        Test.stopTest();

        System.assertNotEquals(u.Id, c.OwnerId, 'Blank-stage rule must not match when Finance stage is requested');
    }

    @IsTest
    static void test_stagedAssignment_financeStageRuleNotMatchedByNullStage() {
        User u = makeUser('FinanceRuleExcluded');
        insert makeRule('Finance Excluded', 'Subject', '=', 'GeneralCase',
                        'User', u.Id, null, false, 1, true, KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);
        // Stage__c = 'Finance' — must NOT be returned when calling updateRecordOwner with no stage (null)

        Case c = new Case(Subject = 'GeneralCase', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c });
        Test.stopTest();

        System.assertNotEquals(u.Id, c.OwnerId, 'Finance-stage rule must not match when general (null) stage is requested');
    }

    @IsTest
    static void test_stagedAssignment_emptyList_withStage_noError() {
        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>(), KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);
        Test.stopTest();
        System.assert(true, 'Should not throw on empty list with stage');
    }

    @IsTest
    static void test_stagedAssignment_nullList_withStage_noError() {
        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(null, KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);
        Test.stopTest();
        System.assert(true, 'Should not throw on null list with stage');
    }

    @IsTest
    static void test_stagedAssignment_noRules_ownerUnchanged() {
        Case c = new Case(Subject = 'No Finance Rules', Status = 'New', Origin = 'Web');

        Test.startTest();
        KenAssignmentHelper.updateRecordOwner(new List<SObject>{ c }, KenSnSConstants.ASSIGNMENT_STAGE_FINANCE);
        Test.stopTest();

        System.assertEquals(null, c.OwnerId, 'OwnerId should remain null when no Finance-stage rules exist');
    }

    @IsTest
    static void resolveFormulaFields_nonFormulaRule_returnsEmptyOverrides() {
        Ken_Assignment_Rule__c rule = makeRule('NoFormula2', 'Subject', '=', 'Test',
                                               'User', UserInfo.getUserId(), null, false, 1, true);
        insert rule;
        Case c = new Case(Subject = 'Test', Status = 'New', Origin = 'Web');
        Test.startTest();
        Map<SObject, Map<String, Object>> result = KenAssignmentHelper.resolveFormulaFields(
            new List<SObject>{ c }, new List<Ken_Assignment_Rule__c>{ rule }, 'Case'
        );
        Test.stopTest();
        System.assertNotEquals(null, result);
        // Subject is not a formula field — no overrides expected
        System.assertEquals(0, result.size(), 'Non-formula field should produce no override entries');
    }
}