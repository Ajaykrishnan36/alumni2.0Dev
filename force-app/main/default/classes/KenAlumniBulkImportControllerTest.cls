@isTest
private class KenAlumniBulkImportControllerTest {
    private static final String PERSON_RT = 'Alumni_Person_Account';

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
        Id jobId = KenAlumniBulkImportController.startChunkedImport(sessionKey, 'Historic Import');
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'A batch job id should be returned');

        List<Account> asha = [SELECT Id FROM Account WHERE PersonEmail = 'asha.rao@example.com'];
        System.assertEquals(1, asha.size(), 'New alumni account should be created');
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :asha[0].Id], 'CRM record should be created');
        System.assertEquals(1, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :asha[0].Id AND RoleType = 'Alumni'], 'Alumni role should be created');

        Ken_Alumni_CRM__c crm = [SELECT Data_Source__c, Current_Company__c FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :asha[0].Id LIMIT 1];
        System.assertEquals('Historic Import', crm.Data_Source__c, 'Data source should be tagged');
        System.assertEquals('Acme', crm.Current_Company__c, 'Company should map');

        Account ashaAcc = [SELECT Linkedin_Profile_URL__c FROM Account WHERE Id = :asha[0].Id LIMIT 1];
        System.assertNotEquals(null, ashaAcc.Linkedin_Profile_URL__c, 'LinkedIn URL should be set on the Person Account');
        System.assertEquals(1, [SELECT COUNT() FROM PersonEducation WHERE AccountId = :asha[0].Id AND Degree_Name__c = 'B.Tech'], 'Bachelors education row should be created');
        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :asha[0].Id AND Currently_Employed__c = true], 'Current employment row should be created');

        System.assertEquals(0, KenAlumniBulkImportController.getImportErrors(jobId).size(), 'A clean row should log no errors');
    }

    @isTest
    static void getBatchStatusReturnsInfo() {
        String sessionKey = KenAlumniBulkImportController.createImportSession();
        KenAlumniBulkImportController.saveImportChunk(sessionKey, 0,
            JSON.serialize(new List<Map<String, Object>>{ row('1', 'R1', 'A', 'B', 'solo@example.com', '1', '2015', 'C', 'L') }));
        Test.startTest();
        Id jobId = KenAlumniBulkImportController.startChunkedImport(sessionKey, 'Portal Migration');
        Test.stopTest();

        KenAlumniBulkImportController.BatchStatusInfo info = KenAlumniBulkImportController.getBatchStatus(jobId);
        System.assertNotEquals(null, info, 'Status info should be returned');
        System.assertNotEquals(null, info.status, 'Status string should be populated');

        Ken_Alumni_CRM__c crm = [SELECT Data_Source__c FROM Ken_Alumni_CRM__c WHERE Person_Account__r.PersonEmail = 'solo@example.com' LIMIT 1];
        System.assertEquals('Portal Migration', crm.Data_Source__c, 'Portal Migration source should be tagged');
    }

    @isTest
    static void getLatestImportJobReturnsRecentRun() {
        String sessionKey = KenAlumniBulkImportController.createImportSession();
        KenAlumniBulkImportController.saveImportChunk(sessionKey, 0,
            JSON.serialize(new List<Map<String, Object>>{ row('1', 'L1', 'A', 'B', 'latest@example.com', '1', '2015', 'C', 'L') }));
        Test.startTest();
        Id jobId = KenAlumniBulkImportController.startChunkedImport(sessionKey, 'Historic Import');
        Test.stopTest();

        KenAlumniBulkImportController.BatchStatusInfo info = KenAlumniBulkImportController.getLatestImportJob();
        System.assertNotEquals(null, info, 'A recent job should be returned');
        System.assertEquals(jobId, info.jobId, 'It should be the job we just ran');
        System.assertNotEquals(null, info.isRunning, 'isRunning flag should be populated');
    }

    @isTest
    static void resolveProgramHandlesBlankIdAndUnknownName() {
        KenAlumniBulkImportController.ProgramResolution blank = KenAlumniBulkImportController.resolveProgram('   ');
        System.assertEquals(false, blank.provided, 'Blank program should not be marked provided');
        System.assertEquals(true, blank.resolved, 'Blank program resolves to nothing to store');
        System.assertEquals(null, blank.programId, 'Blank program stores nothing');

        KenAlumniBulkImportController.ProgramResolution byId = KenAlumniBulkImportController.resolveProgram('0uF000000000001');
        System.assertEquals(true, byId.provided, 'An Id value is provided');
        System.assertEquals(true, byId.resolved, 'A well-formed program Id resolves');
        System.assertEquals('0uF000000000001', byId.programId, 'A program Id is stored as-is');

        System.assertEquals(false, KenAlumniBulkImportController.isProgramPlanId('001000000000001AAA'), 'An Account Id is not a program Id');

        KenAlumniBulkImportController.ProgramResolution missing = KenAlumniBulkImportController.resolveProgram('No Such Program Name 123');
        System.assertEquals(true, missing.provided, 'A name was provided');
        System.assertEquals(false, missing.resolved, 'An unknown program name should not resolve');
        System.assertEquals(null, missing.programId, 'No Id stored when the name is unknown');
    }

    @isTest
    static void startWithoutChunksThrows() {
        Boolean threw = false;
        try {
            KenAlumniBulkImportController.startChunkedImport('nonexistentsessionkey0001', 'Historic Import');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Starting with no staged chunks should throw');
    }

    @isTest
    static void blankSessionThrowsAndNullStatus() {
        Boolean threw = false;
        try {
            KenAlumniBulkImportController.startChunkedImport('', 'Historic Import');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Blank session key should throw');
        System.assertEquals(null, KenAlumniBulkImportController.getBatchStatus(null), 'Null job id returns null status');
        System.assertEquals(0, KenAlumniBulkImportController.getImportErrors(null).size(), 'Null job id returns no errors');
    }
}