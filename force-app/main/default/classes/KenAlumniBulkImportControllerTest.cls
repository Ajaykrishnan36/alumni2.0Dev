@isTest
private class KenAlumniBulkImportControllerTest {
    private static final String PERSON_RT = 'PersonAccount';

    @testSetup
    static void setup() {
        Id rtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(PERSON_RT).getRecordTypeId();
        // Pre-existing alumni used to exercise the duplicate-overlap warning.
        insert new Account(
            RecordTypeId = rtId,
            FirstName = 'Existing',
            LastName = 'Alumni',
            PersonEmail = 'existing@example.com'
        );
    }

    private static String buildRowsJson() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(row('1', 'REG-001', 'Asha', 'Rao', 'asha.rao@example.com', '9999900001', '2018', 'Acme', 'Bangalore'));
        rows.add(row('2', 'REG-002', 'Existing', 'Alumni', 'existing@example.com', '9999900002', '2016', 'Globex', 'Mumbai')); // duplicate email
        rows.add(row('3', 'REG-003', 'NoEmail', 'Person', '', '9999900003', '2019', 'Initech', 'Pune')); // missing email
        rows.add(row('4', 'REG-004', 'Bad', 'Email', 'not-an-email', '9999900004', '2020', 'Hooli', 'Delhi')); // invalid email
        return JSON.serialize(rows);
    }

    private static Map<String, Object> row(
        String rowNo, String reg, String first, String last, String email,
        String phone, String gradYear, String company, String location
    ) {
        Map<String, Object> r = new Map<String, Object>();
        r.put('RowNumber', rowNo);
        r.put('Registration Number', reg);
        r.put('First Name', first);
        r.put('Last Name', last);
        r.put('Email', email);
        r.put('Phone', phone);
        r.put('Year of Graduation', gradYear);
        r.put('Current Company', company);
        r.put('Current Location', location);
        r.put('Industry', 'Technology');
        return r;
    }

    @isTest
    static void endToEndImportCreatesRecords() {
        // The controller runs the batch with scope size 1 (one transaction per
        // row). An Iterable batch may only invoke execute() once per test, so this
        // end-to-end test stages a SINGLE row. Multi-row / error scenarios are
        // covered in KenAlumniBulkImportBatchTest (which controls the scope size).
        String sessionKey = KenAlumniBulkImportController.createImportSession();
        System.assertNotEquals(null, sessionKey, 'Session key should be returned');
        Map<String, Object> richRow = row('1', 'REG-001', 'Asha', 'Rao', 'asha.rao@example.com', '9999900001', '2018', 'Acme', 'Bangalore');
        richRow.put('Current Designation', 'Engineer');
        richRow.put('LinkedIn URL', 'https://www.linkedin.com/in/asha');
        richRow.put('Bachelors Institute', 'IIT');
        richRow.put('Bachelors Degree', 'B.Tech');
        richRow.put('Bachelors Grade', '9.0');
        richRow.put('Bachelors Grade Type', 'CGPA');
        richRow.put('Bachelors Year', '2018');
        KenAlumniBulkImportController.saveImportChunk(sessionKey, 0,
            JSON.serialize(new List<Map<String, Object>>{ richRow }));

        Test.startTest();
        Id jobId = KenAlumniBulkImportController.startChunkedImport(sessionKey, 'Historic Import', 1);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'A batch job id should be returned');

        List<Account> asha = [SELECT Id FROM Account WHERE PersonEmail = 'asha.rao@example.com'];
        System.assertEquals(1, asha.size(), 'New alumni account should be created');
        System.assertEquals(1, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :asha[0].Id AND RoleType = 'Alumni'], 'Alumni role should be created');

        List<PersonEmployment> employment = [
            SELECT Company_Name__c FROM PersonEmployment WHERE AccountId = :asha[0].Id
        ];
        System.assertEquals(1, employment.size(), 'Company should land on a PersonEmployment row');
        System.assertEquals('Acme', employment[0].Company_Name__c, 'Company should map to PersonEmployment');

        ConstituentRole ashaRole = [
            SELECT Source_Funnel__c FROM ConstituentRole
            WHERE PersonId = :asha[0].Id AND RoleType = 'Alumni' LIMIT 1
        ];
        System.assertEquals('Historical Upload', ashaRole.Source_Funnel__c,
            'The legacy "Historic Import" label should resolve onto Source_Funnel__c');

        Account ashaAcc = [SELECT Linkedin_Profile_URL__c FROM Account WHERE Id = :asha[0].Id LIMIT 1];
        System.assertNotEquals(null, ashaAcc.Linkedin_Profile_URL__c, 'LinkedIn URL should be set on the Person Account');
        System.assertEquals(1, [SELECT COUNT() FROM PersonEducation WHERE AccountId = :asha[0].Id AND Degree_Name__c = 'B.Tech'], 'Bachelors education row should be created');
        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :asha[0].Id AND Currently_Employed__c = true], 'Current employment row should be created');

        List<String> importErrors = KenAlumniBulkImportController.getImportErrors(sessionKey);
        System.assertEquals(0, importErrors.size(),
            'A clean row should log no errors, got: ' + String.join(importErrors, ' || '));

        KenAlumniBulkImportController.SessionStatusInfo session = KenAlumniBulkImportController.getSessionStatus(sessionKey);
        System.assertNotEquals(null, session, 'Session status should be available after the run');
        System.assertEquals(false, session.isRunning, 'The finished session should not be running');
        System.assertEquals('Completed', session.status, 'The final chunk job should mark the session Completed');
        System.assertEquals(1, session.total, 'Total rows should come from the session marker');
        System.assertEquals(1, session.processed, 'The processed row should be counted');
        System.assertEquals(0, session.errors, 'A clean row should not count as failed');
    }

    @isTest
    static void getBatchStatusReturnsInfo() {
        String sessionKey = KenAlumniBulkImportController.createImportSession();
        KenAlumniBulkImportController.saveImportChunk(sessionKey, 0,
            JSON.serialize(new List<Map<String, Object>>{ row('1', 'R1', 'A', 'B', 'solo@example.com', '1', '2015', 'C', 'L') }));
        Test.startTest();
        Id jobId = KenAlumniBulkImportController.startChunkedImport(sessionKey, 'Portal Migration', 1);
        Test.stopTest();

        KenAlumniBulkImportController.BatchStatusInfo info = KenAlumniBulkImportController.getBatchStatus(jobId);
        System.assertNotEquals(null, info, 'Status info should be returned');
        System.assertNotEquals(null, info.status, 'Status string should be populated');

        ConstituentRole soloRole = [
            SELECT Source_Funnel__c FROM ConstituentRole
            WHERE PersonId IN (SELECT Id FROM Account WHERE PersonEmail = 'solo@example.com')
              AND RoleType = 'Alumni'
            LIMIT 1
        ];
        System.assertEquals('Old Portal Migration', soloRole.Source_Funnel__c,
            'The legacy "Portal Migration" label should resolve onto Source_Funnel__c');
    }

    @isTest
    static void getLatestImportSessionReturnsRecentRun() {
        String sessionKey = KenAlumniBulkImportController.createImportSession();
        KenAlumniBulkImportController.saveImportChunk(sessionKey, 0,
            JSON.serialize(new List<Map<String, Object>>{ row('1', 'L1', 'A', 'B', 'latest@example.com', '1', '2015', 'C', 'L') }));
        Test.startTest();
        KenAlumniBulkImportController.startChunkedImport(sessionKey, 'Historic Import', 1);
        Test.stopTest();

        KenAlumniBulkImportController.SessionStatusInfo info = KenAlumniBulkImportController.getLatestImportSession();
        System.assertNotEquals(null, info, 'A recent session should be returned');
        System.assertEquals(sessionKey, info.sessionKey, 'It should be the session we just ran');
        System.assertEquals(false, info.isRunning, 'The finished session should not be running');
        System.assertEquals(1, info.processed, 'The processed row should be counted');
    }

    @isTest
    static void resolveProgramHandlesIdNameAndText() {
        KenAlumniBulkImportController.ProgramResolution blank = KenAlumniBulkImportController.resolveProgram('   ');
        System.assertEquals(false, blank.provided, 'Blank program should not be marked provided');
        System.assertEquals(false, blank.resolved, 'Blank program resolves to nothing');
        System.assertEquals(null, blank.storedValue, 'Blank program stores nothing');

        Learning l = new Learning(Name = 'Resolve Learning');
        insert l;
        LearningProgram lp = new LearningProgram(Name = 'Resolve Program', LearningId = l.Id);
        assignCampus(lp);
        insert lp;
        LearningProgramPlan plan = new LearningProgramPlan(Name = 'Resolve Plan', LearningProgramId = lp.Id);
        insert plan;

        KenAlumniBulkImportController.ProgramResolution byId = KenAlumniBulkImportController.resolveProgram(String.valueOf(plan.Id));
        System.assertEquals(true, byId.resolved, 'An existing program Id resolves');
        System.assertEquals(String.valueOf(plan.Id), byId.programId, 'The program Id is kept');
        System.assertEquals('Resolve Plan', byId.storedValue, 'The stored value is the plan name');

        KenAlumniBulkImportController.ProgramResolution byName = KenAlumniBulkImportController.resolveProgram('Resolve Plan');
        System.assertEquals(true, byName.resolved, 'A matching program name resolves');
        System.assertEquals('Resolve Plan', byName.storedValue, 'A matching name is stored as the plan name');

        KenAlumniBulkImportController.ProgramResolution byProgram = KenAlumniBulkImportController.resolveProgram('Resolve Program');
        System.assertEquals(true, byProgram.resolved, 'A programme name that maps to exactly one plan resolves');
        System.assertEquals(String.valueOf(plan.Id), byProgram.programId, 'The single plan under the programme is linked');
        System.assertEquals('Resolve Plan', byProgram.storedValue, 'The stored value is the resolved plan name');

        KenAlumniBulkImportController.ProgramResolution fakeId = KenAlumniBulkImportController.resolveProgram('0uF000000000001');
        System.assertEquals(false, fakeId.resolved, 'An Id with no matching plan does not resolve');
        System.assertEquals(null, fakeId.programId, 'No lookup value for a nonexistent plan Id');
        System.assertEquals('0uF000000000001', fakeId.storedValue, 'The raw value is kept as text');

        System.assertEquals(false, KenAlumniBulkImportController.isProgramPlanId('001000000000001AAA'), 'An Account Id is not a program Id');

        KenAlumniBulkImportController.ProgramResolution missing = KenAlumniBulkImportController.resolveProgram('No Such Program Name 123');
        System.assertEquals(true, missing.provided, 'A name was provided');
        System.assertEquals(false, missing.resolved, 'An unknown program name should not resolve');
        System.assertEquals(null, missing.programId, 'No Id stored when the name is unknown');
        System.assertEquals('No Such Program Name 123', missing.storedValue, 'An unknown name is kept as text');

        System.assertEquals(2015, KenAlumniBulkImportController.parseYear(' 2015 '), 'A 4-digit year parses');
        System.assertEquals(null, KenAlumniBulkImportController.parseYear('15'), 'A short value is not a year');
        System.assertEquals(null, KenAlumniBulkImportController.parseYear('abcd'), 'A non-numeric value is not a year');
    }

    @isTest
    static void importBatchScopeReadsOrgParameterWithFallback() {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        if (params.Id == null) {
            params.SetupOwnerId = UserInfo.getOrganizationId();
        }
        params.Import_Batch_Scope__c = 50;
        upsert params;
        System.assertEquals(50, KenAlumniBulkImportController.importBatchScope(), 'A valid org parameter should override the default');

        params.Import_Batch_Scope__c = 300;
        update params;
        System.assertEquals(100, KenAlumniBulkImportController.importBatchScope(), 'An out-of-range value should fall back to 100');

        params.Import_Batch_Scope__c = null;
        update params;
        System.assertEquals(100, KenAlumniBulkImportController.importBatchScope(), 'A blank value should fall back to 100');
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
    static void startWithoutChunksThrows() {
        Boolean threw = false;
        try {
            KenAlumniBulkImportController.startChunkedImport('nonexistentsessionkey0001', 'Historic Import', 1);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Starting with no staged chunks should throw');
    }

    @isTest
    static void blankSessionThrowsAndNullStatus() {
        Boolean threw = false;
        try {
            KenAlumniBulkImportController.startChunkedImport('', 'Historic Import', 1);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Blank session key should throw');
        System.assertEquals(null, KenAlumniBulkImportController.getBatchStatus(null), 'Null job id returns null status');
        System.assertEquals(0, KenAlumniBulkImportController.getImportErrors(null).size(), 'Null session returns no errors');
        System.assertEquals(null, KenAlumniBulkImportController.getSessionStatus(null), 'Null session returns null status');
        System.assertEquals(null, KenAlumniBulkImportController.getSessionStatus('missingsessionkey0000000'), 'Unknown session returns null status');
    }
}