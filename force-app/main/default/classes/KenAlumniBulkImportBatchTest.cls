@isTest
private class KenAlumniBulkImportBatchTest {
    private static final String PROCESS = 'Alumni Bulk Import';
    private static final String PERSON_RT = 'Alumni_Person_Account';

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
    // Per-row atomicity is preserved by the per-row Savepoint inside execute();
    // production runs with scope size 1 (one transaction per row).
    private static Id stageAndRun(List<Map<String, Object>> rows, String dataSource) {
        String sessionKey = KenAlumniBulkImportController.createSessionKey();
        KenAlumniBulkImportController.saveChunk(PROCESS, sessionKey, 0, JSON.serialize(rows));
        return Database.executeBatch(new KenAlumniBulkImportBatch(PROCESS, sessionKey, dataSource), 200);
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
        // The lead-verification flow creates one account-level CRM per person.
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :acc.Id], 'One CRM per account');

        // Blank data source falls back to default.
        Ken_Alumni_CRM__c crm = [SELECT Data_Source__c FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :acc.Id LIMIT 1];
        System.assertEquals('Historic Import', crm.Data_Source__c, 'Blank data source defaults to Historic Import');
    }

    @isTest
    static void invalidFieldRejectsWholeRow() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row('1', 'BADPROG-1', 'rejectme@example.com', 'THIS_IS_NOT_A_REAL_PROGRAM_VALUE')
        };
        Test.startTest();
        Id jobId = stageAndRun(rows, 'Historic Import');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'rejectme@example.com'], 'No account should be created for a rejected row');
        System.assertEquals(0, [SELECT COUNT() FROM Ken_Alumni_CRM__c], 'No CRM should be created for a rejected row');
        List<Ken_Logs__c> errors = [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :String.valueOf(jobId) AND Log_Type__c = 'Error'];
        System.assert(!errors.isEmpty(), 'A field error should be logged');
        System.assert(errors[0].Message__c.contains('did not match any program record'), 'Error should explain the unmatched program');
    }

    @isTest
    static void programIdStoredAsIsAndStatusApplied() {
        Map<String, Object> r = row('1', 'PROG-1', 'progid@example.com', '0uF000000000001');
        r.put('Status', 'Registered');
        Test.startTest();
        stageAndRun(new List<Map<String, Object>>{ r }, 'Historic Import');
        Test.stopTest();

        Account acc = [SELECT Id FROM Account WHERE PersonEmail = 'progid@example.com' LIMIT 1];
        Ken_Alumni_CRM__c crm = [SELECT Program__c FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :acc.Id LIMIT 1];
        System.assertEquals('0uF000000000001', crm.Program__c, 'A program Id should be stored verbatim');

        ConstituentRole cr = [SELECT Registration_Status__c FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni' LIMIT 1];
        System.assertEquals('Registered', cr.Registration_Status__c, 'The Status column should set the registration stage');
    }

    @isTest
    static void invalidStatusRejectsRow() {
        Map<String, Object> r = row('1', 'BADST-1', 'badstatus@example.com', '');
        r.put('Status', 'NotAStatus');
        Test.startTest();
        Id jobId = stageAndRun(new List<Map<String, Object>>{ r }, 'Historic Import');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'badstatus@example.com'], 'An invalid status should reject the row');
        Boolean sawStatus = false;
        for (Ken_Logs__c l : [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :String.valueOf(jobId) AND Log_Type__c = 'Error']) {
            if (l.Message__c.contains('Status')) sawStatus = true;
        }
        System.assert(sawStatus, 'The status validation error should be logged');
    }

    @isTest
    static void promotesUnlinkedCrmRecord() {
        Id rtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(PERSON_RT).getRecordTypeId();
        Account acc = new Account(RecordTypeId = rtId, FirstName = 'Pre', LastName = 'Existing', PersonEmail = 'promote@example.com');
        insert acc;
        Ken_Alumni_CRM__c unlinked = new Ken_Alumni_CRM__c(Person_Account__c = acc.Id);
        insert unlinked;

        Test.startTest();
        stageAndRun(new List<Map<String, Object>>{ row('1', 'PR-1', 'promote@example.com', '') }, 'Portal Migration');
        Test.stopTest();

        // The existing account-level CRM is reused (not duplicated) and tagged.
        List<Ken_Alumni_CRM__c> crms = [SELECT Id, Data_Source__c FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :acc.Id];
        System.assertEquals(1, crms.size(), 'Existing CRM should be reused, not duplicated');
        System.assertEquals('Portal Migration', crms[0].Data_Source__c, 'Reused CRM should be tagged');
        System.assertEquals(1, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni'], 'An alumni role should be created');
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
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :acc.Id], 'No duplicate CRM on re-import');
    }

    @isTest
    static void mixedRowsImportGoodRowsAndLogFailures() {
        Id rtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(PERSON_RT).getRecordTypeId();
        insert new Account(RecordTypeId = rtId, FirstName = 'Existing', LastName = 'Alumni', PersonEmail = 'dup@example.com');

        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row('1', 'GOOD-1', 'good@example.com', ''),
            row('2', 'BLANK-1', '', ''),
            row('3', 'BADEMAIL-1', 'not-an-email', ''),
            row('4', 'DUP-1', 'dup@example.com', '')
        };
        Test.startTest();
        Id jobId = stageAndRun(rows, 'Historic Import');
        Test.stopTest();

        // Good row imported.
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'good@example.com'], 'Valid row should be imported');
        // Bad-email rows skipped — no accounts created.
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'not-an-email'], 'Invalid email row should be skipped');
        // Duplicate did not create a second account.
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = 'dup@example.com'], 'No duplicate account created');

        List<Ken_Logs__c> logs = [SELECT Message__c, Log_Type__c FROM Ken_Logs__c WHERE Reference_Id__c = :String.valueOf(jobId)];
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

    @isTest
    static void emptyChunkIsNoOp() {
        Test.startTest();
        Id jobId = Database.executeBatch(new KenAlumniBulkImportBatch(PROCESS, KenAlumniBulkImportController.createSessionKey(), 'Historic Import'), 1);
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job should still be created for an empty session');
        System.assertEquals(0, [SELECT COUNT() FROM Ken_Alumni_CRM__c], 'No records created for empty session');
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
        Id jobId = stageAndRun(new List<Map<String, Object>>{ badGrade, badDate }, 'Historic Import');
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'badgrade@example.com'], 'Invalid grade type should reject the whole row');
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE PersonEmail = 'baddate@example.com'], 'Invalid date should reject the whole row');

        Boolean sawGrade = false, sawDate = false;
        for (Ken_Logs__c l : [SELECT Message__c FROM Ken_Logs__c WHERE Reference_Id__c = :String.valueOf(jobId) AND Log_Type__c = 'Error']) {
            if (l.Message__c.contains('Grade Type')) sawGrade = true;
            if (l.Message__c.contains('not a valid date')) sawDate = true;
        }
        System.assert(sawGrade, 'An invalid grade type should be logged');
        System.assert(sawDate, 'An invalid date should be logged');
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
    }
}