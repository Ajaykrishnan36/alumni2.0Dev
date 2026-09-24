@isTest
private class KenAlumniBulkImportBatchTest {
    private static final String PROCESS = 'Alumni Bulk Import';
    private static final String PERSON_RT = 'PersonAccount';

    private static Map<String, Object> row(String rowNo, String reg, String email, String program) {
        Map<String, Object> r = new Map<String, Object>();
        r.put('RowNumber', rowNo);
        r.put('Registration Number', reg);
        r.put('First Name', 'Test');
        r.put('Last Name', 'User');
        r.put('Email', email);
        r.put('Phone', '9000000000');
        r.put('Year of Graduation', '2017');
        r.put('Current Company', 'Initech');
        r.put('Current Location', 'Hyderabad');
        r.put('Industry', 'Software');
        r.put('Program', program);
        return r;
    }

    // Tests use a scope large enough to process all staged rows in ONE execute,
    // because an Iterable batch may only invoke execute() once per test method.
    // Production also runs bulkified at scope 200; row isolation comes from
    // partial-success DML plus savepoint split-retry around provisioning.
    // Returns the session key — row logs are keyed by it (Reference_Id__c).
    private static String stageAndRun(List<Map<String, Object>> rows, String dataSource) {
        String sessionKey = KenAlumniBulkImportController.createSessionKey();
        KenAlumniBulkImportController.saveChunk(PROCESS, sessionKey, 0, JSON.serialize(rows));
        Database.executeBatch(new KenAlumniBulkImportBatch(PROCESS, sessionKey, dataSource), 200);
        return sessionKey;
    }

    private static Id createProgramPlan(String name) {
        Learning l = new Learning(Name = name + ' Learning');
        insert l;
        LearningProgram lp = new LearningProgram(Name = name + ' Program', LearningId = l.Id);
        assignCampus(lp);
        insert lp;
        LearningProgramPlan plan = new LearningProgramPlan(Name = name, LearningProgramId = lp.Id);
        insert plan;
        return plan.Id;
    }

    /**
     * The person-account record type developer name differs per org fork
     * (PersonAccount vs Alumni_Person_Account); prefer PERSON_RT and fall back
     * to any person-type record type so the tests run in every org.
     */
    private static Id personAccountRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> byDevName = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        if (byDevName.containsKey(PERSON_RT)) {
            return byDevName.get(PERSON_RT).getRecordTypeId();
        }
        for (RecordType rt : [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true AND IsActive = true LIMIT 1]) {
            return rt.Id;
        }
        return null;
    }

    /**
     * KJS orgs add a required Campus__c lookup (→ Location) on LearningProgram;
     * populate it only where the field exists so the tests run in every org.
     */
    private static void assignCampus(SObject record) {
        if (!record.getSObjectType().getDescribe().fields.getMap().containsKey('campus__c')) return;
        Schema.Location campus = new Schema.Location(Name = 'Import Test Campus');
        for (Schema.PicklistEntry entry : Schema.Location.LocationType.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                campus.LocationType = entry.getValue();
                break;
            }
        }
        insert campus;
        record.put('Campus__c', campus.Id);
    }

    @isTest
    static void multiProgramSamePersonCreatesMultipleRoles() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row('1', 'MBA-1', 'multi@example.com', ''),
            row('2', 'BBA-2', 'multi@example.com', '')
        };
        Test.startTest();
        stageAndRun(rows, '');
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE PersonEmail = 'multi@example.com' LIMIT 1];
        System.assertEquals(2, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni'], 'Two roles for two registration numbers');
        // Blank data source falls back to the default, stamped on the role.
        List<ConstituentRole> sourced = [
            SELECT Source_Funnel__c FROM ConstituentRole
            WHERE PersonId = :acc.Id AND RoleType = 'Alumni' AND Source_Funnel__c != null
        ];
        System.assertNotEquals(0, sourced.size(), 'Source funnel should be stamped on at least one role');
        System.assertEquals('Historical Upload', sourced[0].Source_Funnel__c,
            'Blank data source defaults to Historical Upload');
    }

    @isTest
    static void unmatchedProgramRejectsRow() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row('1', 'TXTPROG-1', 'textprog@example.com', 'Executive MBA (Legacy 2004)')
        };
        Test.startTest();
        String sessionKey = stageAndRun(rows, 'Historic Import');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'textprog@example.com'], 'A program that matches nothing must reject the row');
        Boolean sawError = false;
        for (Ken_Logs__c l : [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :sessionKey AND Log_Type__c = 'Error']) {
            if (l.Message__c.contains('does not match any program')) sawError = true;
        }
        System.assert(sawError, 'The unmatched program should be logged as a row error');
    }

    @isTest
    static void programIdResolvesToLookupAndStatusApplied() {
        Id planId = createProgramPlan('Import Plan A');
        Map<String, Object> r = row('1', 'PROG-1', 'progid@example.com', String.valueOf(planId));
        r.put('Status', 'Registered');
        Test.startTest();
        stageAndRun(new List<Map<String, Object>>{ r }, 'Historic Import');
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE PersonEmail = 'progid@example.com' LIMIT 1];

        ConstituentRole cr = [SELECT Registration_Status__c, Program_Plan__c FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni' LIMIT 1];
        System.assertEquals(planId, cr.Program_Plan__c, 'The resolved program should be stamped on the role lookup');
        System.assertEquals('Registered', cr.Registration_Status__c, 'The Status column should set the registration stage');
    }

    /**
     * A retired column must be ignored, not fatal. Specialization was validated
     * against a picklist map entry that the Ken_Alumni_CRM__c removal deleted, so
     * any row carrying a value dereferenced null in validateRow and took the whole
     * scope down with it — a 100-row import landed nothing and still reported
     * Completed. No test row populated the column, which is why it shipped.
     */
    @isTest
    static void retiredSpecializationColumnDoesNotBreakTheImport() {
        Id planId = createProgramPlan('Import Plan Spec');
        Map<String, Object> r = row('1', 'SPEC-1', 'spec@example.com', 'Import Plan Spec');
        r.put('Specialization', 'Data Science');
        Test.startTest();
        String sessionKey = stageAndRun(new List<Map<String, Object>>{ r }, 'Historic Import');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'spec@example.com'],
            'A row carrying the retired Specialization column must still import');
        ConstituentRole cr = [
            SELECT Program_Plan__c FROM ConstituentRole
            WHERE PersonId IN (SELECT Id FROM Account WHERE PersonEmail = 'spec@example.com') AND RoleType = 'Alumni'
            LIMIT 1
        ];
        System.assertEquals(planId, cr.Program_Plan__c, 'The rest of the row must import normally');
        for (Ken_Logs__c l : [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :sessionKey AND Log_Type__c = 'Error']) {
            System.assert(!l.Message__c.contains('de-reference'),
                'A retired column must not raise a null dereference: ' + l.Message__c);
        }
    }

    @isTest
    static void programNameResolvesAndFakeIdRejectsRow() {
        Id planId = createProgramPlan('Import Plan B');
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row('1', 'NAME-1', 'progname@example.com', 'Import Plan B'),
            row('2', 'FAKE-1', 'progfake@example.com', '0uF000000000001')
        };
        Test.startTest();
        String sessionKey = stageAndRun(rows, 'Historic Import');
        Test.stopTest();

        Account named = [SELECT Id FROM Account WHERE PersonEmail = 'progname@example.com' LIMIT 1];
        ConstituentRole namedRole = [SELECT Program_Plan__c FROM ConstituentRole WHERE PersonId = :named.Id AND RoleType = 'Alumni' LIMIT 1];
        System.assertEquals(planId, namedRole.Program_Plan__c, 'A matching program name should populate the role lookup');

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'progfake@example.com'], 'A plan Id that does not exist must reject the row');
        Boolean sawError = false;
        for (Ken_Logs__c l : [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :sessionKey AND Log_Type__c = 'Error']) {
            if (l.Message__c.contains('does not match any program')) sawError = true;
        }
        System.assert(sawError, 'The nonexistent plan Id should be logged as a row error');
    }

    @isTest
    static void enrollmentYearAndPicklistProfileFieldsImported() {
        Map<String, Object> r = row('1', 'ENR-1', 'enroll@example.com', '');
        r.put('Year of Enrollment', '2017');
        r.put('Nationality', 'Indian');
        r.put('Blood Group', 'O+');
        Test.startTest();
        stageAndRun(new List<Map<String, Object>>{ r }, 'Historic Import');
        Test.stopTest();

        Account acc = [SELECT Id, Nationality__c, Blood_Group__c, PersonMobilePhone FROM Account WHERE PersonEmail = 'enroll@example.com' LIMIT 1];
        System.assertEquals('Indian', acc.Nationality__c, 'Nationality should be set on the Person Account');
        System.assertEquals('O+', acc.Blood_Group__c, 'Blood group should be set on the Person Account');
        System.assertEquals('9000000000', acc.PersonMobilePhone, 'Phone should be mirrored into PersonMobilePhone');
        ConstituentRole cr = [SELECT Id, Year_of_Enrollment__c, Source_Funnel__c FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni' LIMIT 1];
        System.assertEquals('2017', cr.Year_of_Enrollment__c, 'Year of Enrollment equal to the Year of Graduation is allowed and should pass through to the role');
        System.assertEquals('Historical Upload', cr.Source_Funnel__c, 'A historic import should stamp the Historical Upload funnel, not Self-Declared Lead');
    }

    @isTest
    static void invalidEnrollmentYearOrPicklistValueRejectsRow() {
        Map<String, Object> badNationality = row('1', 'BADN-1', 'badnat@example.com', '');
        badNationality.put('Nationality', 'Martian');
        Map<String, Object> badEnroll = row('2', 'BADE-1', 'badenroll@example.com', '');
        badEnroll.put('Year of Enrollment', '2019');
        Map<String, Object> badYearFormat = row('3', 'BADF-1', 'badformat@example.com', '');
        badYearFormat.put('Year of Enrollment', 'abcd');

        Test.startTest();
        String sessionKey = stageAndRun(new List<Map<String, Object>>{ badNationality, badEnroll, badYearFormat }, 'Historic Import');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail IN ('badnat@example.com', 'badenroll@example.com', 'badformat@example.com')], 'Invalid values should reject the whole row');
        Boolean sawNationality = false, sawOrder = false, sawFormat = false;
        for (Ken_Logs__c l : [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :sessionKey AND Log_Type__c = 'Error']) {
            if (l.Message__c.contains('Nationality')) sawNationality = true;
            if (l.Message__c.contains('later than the Year of Graduation')) sawOrder = true;
            if (l.Message__c.contains('not a valid year')) sawFormat = true;
        }
        System.assert(sawNationality, 'The invalid nationality should be logged');
        System.assert(sawOrder, 'Enrollment after graduation should be logged');
        System.assert(sawFormat, 'A non-year enrollment value should be logged');
    }

    @isTest
    static void invalidStatusRejectsRow() {
        Map<String, Object> r = row('1', 'BADST-1', 'badstatus@example.com', '');
        r.put('Status', 'NotAStatus');
        Test.startTest();
        String sessionKey = stageAndRun(new List<Map<String, Object>>{ r }, 'Historic Import');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'badstatus@example.com'], 'An invalid status should reject the row');
        Boolean sawStatus = false;
        for (Ken_Logs__c l : [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :sessionKey AND Log_Type__c = 'Error']) {
            if (l.Message__c.contains('Status')) sawStatus = true;
        }
        System.assert(sawStatus, 'The status validation error should be logged');
    }

    @isTest
    static void importAgainstPreExistingAccountStampsTheRole() {
        Id rtId = personAccountRecordTypeId();
        Account acc = new Account(RecordTypeId = rtId, FirstName = 'Pre', LastName = 'Existing', PersonEmail = 'promote@example.com');
        insert acc;

        Test.startTest();
        stageAndRun(new List<Map<String, Object>>{ row('1', 'PR-1', 'promote@example.com', '') }, 'Portal Migration');
        Test.stopTest();

        List<ConstituentRole> roles = [SELECT Source_Funnel__c FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni'];
        System.assertEquals(1, roles.size(), 'An alumni role should be created');
        System.assertEquals('Old Portal Migration', roles[0].Source_Funnel__c, 'A portal-migration import should stamp the Old Portal Migration funnel');
    }

    @isTest
    static void reimportSameRowIsIdempotent() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{ row('1', 'IDEMP-1', 'idem@example.com', '') };
        Test.startTest();
        stageAndRun(rows, 'Historic Import');
        stageAndRun(rows, 'Historic Import');
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE PersonEmail = 'idem@example.com' LIMIT 1];
        System.assertEquals(1, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni'], 'No duplicate role on re-import');
    }

    @isTest
    static void mixedRowsImportGoodRowsAndLogFailures() {
        Id rtId = personAccountRecordTypeId();
        insert new Account(RecordTypeId = rtId, FirstName = 'Existing', LastName = 'Alumni', PersonEmail = 'dup@example.com');

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row('1', 'GOOD-1', 'good@example.com', ''),
            row('2', 'BLANK-1', '', ''),
            row('3', 'BADEMAIL-1', 'not-an-email', ''),
            row('4', 'DUP-1', 'dup@example.com', '')
        };
        Test.startTest();
        String sessionKey = stageAndRun(rows, 'Historic Import');
        Test.stopTest();

        // Good row imported.
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'good@example.com'], 'Valid row should be imported');
        // Bad-email rows skipped — no accounts created.
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'not-an-email'], 'Invalid email row should be skipped');
        // Duplicate did not create a second account.
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'dup@example.com'], 'No duplicate account created');

        List<Ken_Logs__c> logs = [SELECT Message__c, Log_Type__c FROM Ken_Logs__c WHERE Reference_Id__c = :sessionKey];
        Boolean sawMissing = false, sawInvalid = false, sawDup = false;
        for (Ken_Logs__c l : logs) {
            if (l.Message__c.contains('Email is required')) sawMissing = true;
            if (l.Message__c.contains('not a valid email')) sawInvalid = true;
            if (l.Message__c.contains('Possible duplicate')) sawDup = true;
        }
        System.assert(sawMissing, 'Missing email should be logged');
        System.assert(sawInvalid, 'Invalid email should be logged');
        System.assert(sawDup, 'Duplicate overlap should be logged as a warning');
    }

    // Verifies the heap-safe chunk chain: each job loads ONLY the first staged
    // chunk file and deletes it in finish(). Chaining itself can't run in tests,
    // so the second chunk is drained by invoking the batch contract directly.
    @isTest
    static void processesOneChunkPerJobThenDrainsTheNext() {
        String sessionKey = KenAlumniBulkImportController.createSessionKey();
        KenAlumniBulkImportController.saveChunk(PROCESS, sessionKey, 0,
            JSON.serialize(new List<Map<String, Object>>{ row('1', 'CHAIN-1', 'chain1@example.com', '') }));
        KenAlumniBulkImportController.saveChunk(PROCESS, sessionKey, 1,
            JSON.serialize(new List<Map<String, Object>>{ row('2', 'CHAIN-2', 'chain2@example.com', '') }));

        Test.startTest();
        Database.executeBatch(new KenAlumniBulkImportBatch(PROCESS, sessionKey, 'Historic Import'), 200);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'chain1@example.com'], 'First chunk row should be imported');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'chain2@example.com'], 'Second chunk should be left for the chained job');
        System.assertEquals(1, KenAlumniBulkImportController.getChunkVersionIds(PROCESS, sessionKey).size(), 'The processed chunk file should be deleted; the next chunk should remain');

        KenAlumniBulkImportBatch next = new KenAlumniBulkImportBatch(PROCESS, sessionKey, 'Historic Import');
        List<String> items = (List<String>) next.start(null);
        System.assertEquals(1, items.size(), 'The chained job should pick up the remaining chunk');
        next.execute(null, items);
        next.finish(null);

        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'chain2@example.com'], 'The drained chunk row should be imported');
        System.assertEquals(0, KenAlumniBulkImportController.getChunkVersionIds(PROCESS, sessionKey).size(), 'All chunk files should be deleted once processed');
    }

    @isTest
    static void emptyChunkIsNoOp() {
        Test.startTest();
        Id jobId = Database.executeBatch(new KenAlumniBulkImportBatch(PROCESS, KenAlumniBulkImportController.createSessionKey(), 'Historic Import'), 1);
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job should still be created for an empty session');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'emptysession@example.com'],
            'No records created for an empty session');
    }

    // Builds the base row plus all Alumni 360 profile / education / employment columns.
    private static Map<String, Object> richRow(String rowNo, String reg, String email) {
        Map<String, Object> r = row(rowNo, reg, email, '');
        r.put('Date of Birth', '1995-08-15');
        r.put('LinkedIn URL', 'https://www.linkedin.com/in/rich');
        r.put('Languages Known', 'English, Hindi');
        r.put('Address Street', '1 Park Ave');
        r.put('Address City', 'Pune');
        r.put('Address State', 'Maharashtra');
        r.put('Address Postal Code', '411001');
        r.put('Address Country', 'India');
        r.put('Current Designation', 'Lead Engineer');
        r.put('Employment Start Date', '2020-01-10');
        r.put('10th School', 'City School');
        r.put('10th Grade', '90');
        r.put('10th Grade Type', 'Percentage');
        r.put('10th Year', '2010');
        r.put('Bachelors Institute', 'COEP');
        r.put('Bachelors Degree', 'B.Tech IT');
        r.put('Bachelors Grade', '8.1');
        r.put('Bachelors Grade Type', 'CGPA');
        r.put('Bachelors Year', '2016');
        return r;
    }

    @isTest
    static void richRowCreatesProfileEducationAndEmployment() {
        Test.startTest();
        stageAndRun(new List<Map<String, Object>>{ richRow('1', 'RICH-1', 'rich@example.com') }, 'Historic Import');
        Test.stopTest();

        Account acc = [
            SELECT Id, PersonBirthdate, Linkedin_Profile_URL__c, Languages_Known__c,
                   PersonMailingCity, PersonMailingState, PersonMailingCountry
            FROM Account WHERE PersonEmail = 'rich@example.com' LIMIT 1
        ];
        System.assertEquals(Date.newInstance(1995, 8, 15), acc.PersonBirthdate, 'DOB should be parsed and set');
        System.assertEquals('English, Hindi', acc.Languages_Known__c, 'Languages should be set');
        System.assertEquals('Pune', acc.PersonMailingCity, 'City should be set');
        System.assertEquals('Maharashtra', acc.PersonMailingState, 'State should be set');
        System.assertEquals('India', acc.PersonMailingCountry, 'Country should be set');
        System.assert(acc.Linkedin_Profile_URL__c != null && acc.Linkedin_Profile_URL__c.contains('linkedin.com'), 'LinkedIn URL should be set');

        // The mailing address must also land on Ken_Address__c — the object the
        // portal map and Alumni 360 read; PersonMailing* fields alone are invisible there.
        List<Ken_Address__c> addrs = [
            SELECT Street__c, City__c, State__c, Pincode__c, Country__c
            FROM Ken_Address__c WHERE Person_Account__c = :acc.Id AND Address_Type__c = 'Mailing'
        ];
        System.assertEquals(1, addrs.size(), 'A mailing Ken_Address__c row should be created for the map');
        System.assertEquals('Pune', addrs[0].City__c, 'Address city should map to Ken_Address__c');
        System.assertEquals('Maharashtra', addrs[0].State__c, 'Address state should map to Ken_Address__c');
        System.assertEquals('India', addrs[0].Country__c, 'Address country should map to Ken_Address__c');
        System.assertEquals('1 Park Ave', addrs[0].Street__c, 'Address street should map to Ken_Address__c');
        System.assertEquals('411001', addrs[0].Pincode__c, 'Postal code should map to Ken_Address__c');

        Map<String, PersonEducation> byDegree = new Map<String, PersonEducation>();
        for (PersonEducation e : [
            SELECT Degree_Name__c, Institute_Name__c, Grade__c, Grade_Type__c, Year_of_Completion__c
            FROM PersonEducation WHERE AccountId = :acc.Id
        ]) {
            byDegree.put(e.Degree_Name__c, e);
        }
        System.assertEquals(2, byDegree.size(), 'Two education rows (10th + Bachelors) should be created');
        System.assert(byDegree.containsKey('10th'), 'A 10th education row should exist (fixed degree name)');
        System.assertEquals('City School', byDegree.get('10th').Institute_Name__c, '10th institute should map');
        System.assertEquals('Percentage', byDegree.get('10th').Grade_Type__c, '10th grade type should map');
        System.assertEquals('2010', byDegree.get('10th').Year_of_Completion__c, '10th year should map');
        System.assert(byDegree.containsKey('B.Tech IT'), 'Bachelors row keyed by the provided degree should exist');
        System.assertEquals('COEP', byDegree.get('B.Tech IT').Institute_Name__c, 'Bachelors institute should map');
        System.assertEquals('CGPA', byDegree.get('B.Tech IT').Grade_Type__c, 'Bachelors grade type should map');

        List<PersonEmployment> emp = [
            SELECT Company_Name__c, Designation__c, Location__c, StartDate, Currently_Employed__c
            FROM PersonEmployment WHERE AccountId = :acc.Id
        ];
        System.assertEquals(1, emp.size(), 'One current employment row should be created');
        System.assertEquals('Initech', emp[0].Company_Name__c, 'Company should come from Current Company');
        System.assertEquals('Lead Engineer', emp[0].Designation__c, 'Designation should come from Current Designation');
        System.assertEquals('Hyderabad', emp[0].Location__c, 'Location should come from Current Location');
        System.assertEquals(true, emp[0].Currently_Employed__c, 'Should be marked currently employed');
        System.assertEquals(Date.newInstance(2020, 1, 10), emp[0].StartDate, 'Employment start date should be parsed');
    }

    @isTest
    static void invalidGradeTypeOrDateRejectsRow() {
        Map<String, Object> badGrade = row('1', 'BADG-1', 'badgrade@example.com', '');
        badGrade.put('Bachelors Institute', 'Somewhere');
        badGrade.put('Bachelors Grade Type', 'NotAGradeType');
        Map<String, Object> badDate = row('2', 'BADD-1', 'baddate@example.com', '');
        badDate.put('Date of Birth', '2020-13-45');

        Test.startTest();
        String sessionKey = stageAndRun(new List<Map<String, Object>>{ badGrade, badDate }, 'Historic Import');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'badgrade@example.com'], 'Invalid grade type should reject the whole row');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'baddate@example.com'], 'Invalid date should reject the whole row');

        Boolean sawGrade = false, sawDate = false;
        for (Ken_Logs__c l : [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :sessionKey AND Log_Type__c = 'Error']) {
            if (l.Message__c.contains('Grade Type')) sawGrade = true;
            if (l.Message__c.contains('not a valid date')) sawDate = true;
        }
        System.assert(sawGrade, 'An invalid grade type should be logged');
        System.assert(sawDate, 'An invalid date should be logged');
    }

    // Forces the CPU checkpoint (guard lowered to -1) so the second occurrence
    // of a repeated email is deferred to a restaged chunk instead of processed
    // in the same transaction, then drains that chunk and verifies both rows land.
    @isTest
    static void cpuPressureDefersDuplicatePassToRestagedChunk() {
        KenAlumniBulkImportBatch.cpuGuardMs = -1;
        String sessionKey = KenAlumniBulkImportController.createSessionKey();
        KenAlumniBulkImportController.saveChunk(PROCESS, sessionKey, 0, JSON.serialize(new List<Map<String, Object>>{
            row('1', 'CPU-1', 'cpudefer@example.com', ''),
            row('2', 'CPU-2', 'cpudefer@example.com', '')
        }));
        Test.startTest();
        Database.executeBatch(new KenAlumniBulkImportBatch(PROCESS, sessionKey, 'Historic Import'), 200);
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE PersonEmail = 'cpudefer@example.com' LIMIT 1];
        System.assertEquals(1, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni'], 'Only the first pass should run under CPU pressure');
        System.assertEquals(1, KenAlumniBulkImportController.getChunkVersionIds(PROCESS, sessionKey).size(), 'The deferred row should be restaged as a new chunk');

        KenAlumniBulkImportBatch.cpuGuardMs = 40000;
        KenAlumniBulkImportBatch next = new KenAlumniBulkImportBatch(PROCESS, sessionKey, 'Historic Import');
        List<String> items = (List<String>) next.start(null);
        next.execute(null, items);
        next.finish(null);

        System.assertEquals(2, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni'], 'The restaged row should import when its chunk is drained');
        System.assertEquals(0, KenAlumniBulkImportController.getChunkVersionIds(PROCESS, sessionKey).size(), 'All chunk files should be gone once processed');
    }

    @isTest
    static void reimportRichRowDoesNotDuplicateChildRecords() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{ richRow('1', 'RICH-2', 'richidem@example.com') };
        Test.startTest();
        stageAndRun(rows, 'Historic Import');
        stageAndRun(rows, 'Historic Import');
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE PersonEmail = 'richidem@example.com' LIMIT 1];
        System.assertEquals(2, [SELECT COUNT() FROM PersonEducation WHERE AccountId = :acc.Id], 'Re-import should update education rows in place, not duplicate them');
        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :acc.Id], 'Re-import should update the current employment row, not duplicate it');
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Address__c WHERE Person_Account__c = :acc.Id AND Address_Type__c = 'Mailing'], 'Re-import should update the mailing address in place, not duplicate it');
    }
}