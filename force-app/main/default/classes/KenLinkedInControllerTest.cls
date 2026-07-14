@isTest
private class KenLinkedInControllerTest {

    private static final String SYNC_EMAIL = 'sync.test@example.test';

    @testSetup
    static void setup() {
        // Inserted in @testSetup so it's committed before each test method —
        // avoids "uncommitted work pending" before the callout in the
        // SYNCHRONOUS (non-@future) path.
        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1];
        Account pa = new Account(
            RecordTypeId = rt.Id,
            FirstName = 'Sync',
            LastName = 'Tester',
            PersonEmail = SYNC_EMAIL,
            Linkedin_Profile_URL__c = 'https://www.linkedin.com/in/test'
        );
        insert pa;
        insert new Ken_Alumni_CRM__c(Person_Account__c = pa.Id);
        LinkedIn_Config__c cfg = LinkedIn_Config__c.getOrgDefaults();
        cfg.LinkedIn_Endpoint__c = 'https://linkedin-api.pichainlabs.com/api/v1/enrich/batch';
        cfg.LinkedIn_Token__c = 'test-api-key';
        upsert cfg;
    }

    private static final String PROFILE_JSON =
        '{"results":[{"url":"https://www.linkedin.com/in/test","profile":{' +
        '"first_name":"Asha","last_name":"Rao","summary":"Engineer and alum",' +
        '"profile_pic_url":"https://media.licdn.com/dms/image/test.jpg",' +
        '"experiences":[{"title":"Senior Engineer","company":"Acme Corp","location":"Bangalore",' +
        '"starts_at":{"day":1,"month":6,"year":2019},"ends_at":null}],' +
        '"education":[{"school":"MIT","degree_name":"B.Tech","field_of_study":"CSE","grade":"A",' +
        '"starts_at":{"day":1,"month":8,"year":2014},"ends_at":{"day":1,"month":5,"year":2018}}],' +
        '"certifications":[{"name":"Salesforce Admin","authority":"Salesforce","license_number":"ABC123",' +
        '"url":"https://example.com/cert","starts_at":{"day":1,"month":1,"year":2021}}]' +
        '}}]}';

    private class LinkedInMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (req.getMethod() == 'GET') {
                res.setBodyAsBlob(Blob.valueOf('x'.repeat(300)));
            } else {
                res.setHeader('Content-Type', 'application/json');
                res.setBody(PROFILE_JSON);
            }
            return res;
        }
    }

    private static Id createAlumni(String email) {
        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1];
        Account pa = new Account(
            RecordTypeId = rt.Id,
            FirstName = 'Asha',
            LastName = 'Rao',
            PersonEmail = email,
            Linkedin_Profile_URL__c = 'https://www.linkedin.com/in/test'
        );
        insert pa;
        insert new Ken_Alumni_CRM__c(Person_Account__c = pa.Id);
        return pa.Id;
    }

    @isTest
    static void testSyncStoresProfile() {
        Id accId = createAlumni('sync.store@example.test');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new LinkedInMock());
        KenLinkedInController.syncAlumni(accId); // runs the callout in the @future txn
        Test.stopTest();

        List<PersonEmployment> emp = [
            SELECT Designation__c, Company_Name__c, Currently_Employed__c, LinkedIn_Sourced__c
            FROM PersonEmployment WHERE AccountId = :accId AND Is_Archived__c = false
        ];
        System.assertEquals(1, emp.size(), 'One employment row from LinkedIn');
        System.assertEquals('Senior Engineer', emp[0].Designation__c, 'Title maps to Designation');
        System.assertEquals('Acme Corp', emp[0].Company_Name__c, 'Company maps');
        System.assertEquals(true, emp[0].Currently_Employed__c, 'Open-ended experience is current');
        System.assertEquals(true, emp[0].LinkedIn_Sourced__c, 'Flagged LinkedIn sourced');

        List<PersonEducation> edu = [
            SELECT Institute_Name__c, Degree_Name__c, Year_of_Completion__c
            FROM PersonEducation WHERE AccountId = :accId AND Is_Archived__c = false
        ];
        System.assertEquals(1, edu.size(), 'One education row');
        System.assertEquals('MIT', edu[0].Institute_Name__c, 'School maps to Institute');
        System.assertEquals('2018', edu[0].Year_of_Completion__c, 'End year maps to Year of Completion');

        Account acc = [SELECT PersonContactId, Last_LinkedIn_Sync__c FROM Account WHERE Id = :accId];
        System.assertNotEquals(null, acc.Last_LinkedIn_Sync__c, 'Sync timestamp stamped');
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Certificate_Details__c WHERE Contact__c = :acc.PersonContactId], 'One certificate row');
    }

    @isTest
    static void testResyncArchivesPriorLinkedInRows() {
        Id accId = createAlumni('sync.resync@example.test');
        Id contactId = [SELECT PersonContactId FROM Account WHERE Id = :accId].PersonContactId;
        // Simulate a prior LinkedIn sync row.
        insert new PersonEmployment(
            Name = 'Old Co', AccountId = accId, RelatedPersonId = contactId,
            Company_Name__c = 'Old Co', Designation__c = 'Old Role',
            LinkedIn_Sourced__c = true, Is_Archived__c = false
        );

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new LinkedInMock());
        KenLinkedInController.syncAlumni(accId);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :accId AND Is_Archived__c = false], 'Only the latest employment stays active');
        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :accId AND Is_Archived__c = true], 'Prior LinkedIn employment archived');
    }

    @isTest
    static void testNoUrlIsNoOp() {
        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1];
        Account pa = new Account(RecordTypeId = rt.Id, FirstName = 'No', LastName = 'Url', PersonEmail = 'nourl@example.test');
        insert pa;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new LinkedInMock());
        KenLinkedInController.syncAlumni(pa.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :pa.Id], 'No records when no LinkedIn URL');
    }

    private class ErrorMock implements HttpCalloutMock {
        private final Integer status;
        public ErrorMock(Integer s) { this.status = s; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.status);
            res.setBody('{"error":"unauthorized"}');
            return res;
        }
    }

    @isTest
    static void testSyncAlumniSyncSuccess() {
        Id accId = [SELECT Id FROM Account WHERE PersonEmail = :SYNC_EMAIL LIMIT 1].Id;
        Test.setMock(HttpCalloutMock.class, new LinkedInMock());
        Test.startTest();
        KenLinkedInController.syncAlumniSync(accId); // synchronous, no @future
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :accId AND Is_Archived__c = false], 'Synchronous sync inserts employment');
        System.assertNotEquals(null, [SELECT Last_LinkedIn_Sync__c FROM Account WHERE Id = :accId].Last_LinkedIn_Sync__c, 'Last sync timestamp set');
    }

    @isTest
    static void testSyncAlumniSyncReports401() {
        Id accId = [SELECT Id FROM Account WHERE PersonEmail = :SYNC_EMAIL LIMIT 1].Id;
        Test.setMock(HttpCalloutMock.class, new ErrorMock(401));
        Boolean threw = false;
        Test.startTest();
        try {
            KenLinkedInController.syncAlumniSync(accId);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Provider 401 should surface as AuraHandledException');
        System.assertEquals(0, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :accId], 'No records inserted on auth failure');
    }

    @isTest
    static void testSyncAlumniSyncNoUrl() {
        RecordType rt = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1];
        Account pa = new Account(RecordTypeId = rt.Id, FirstName = 'No', LastName = 'Url', PersonEmail = 'nourl.sync@example.test');
        insert pa;
        Boolean threw = false;
        Test.startTest();
        try {
            KenLinkedInController.syncAlumniSync(pa.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Missing LinkedIn URL should throw');
    }

    @isTest
    static void testBulkEntryPoint() {
        Id accId = createAlumni('sync.bulk@example.test');
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new LinkedInMock());
        KenLinkedInController.syncAlumniBulk(new List<Id>{ accId });
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :accId AND Is_Archived__c = false], 'Bulk entry runs the sync');
    }

    @isTest
    static void testGetLinkedInDataByAccountId() {
        Id accId = createAlumni('getby.account@example.test');
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new LinkedInMock());
        KenLinkedInController.getLinkedInData(accId, null);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :accId AND Is_Archived__c = false], 'getLinkedInData by accountId syncs');
    }

    @isTest
    static void testGetLinkedInDataByEmail() {
        Id accId = createAlumni('getby.email@example.test');
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new LinkedInMock());
        KenLinkedInController.getLinkedInData(null, 'getby.email@example.test');
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM PersonEmployment WHERE AccountId = :accId AND Is_Archived__c = false], 'getLinkedInData by email resolves and syncs');
    }

    @isTest
    static void testGetLinkedInDataNoTargetThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenLinkedInController.getLinkedInData(null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Missing both accountId and email throws');
    }

    @isTest
    static void testFetchProfilePreview() {
        Test.setMock(HttpCalloutMock.class, new LinkedInMock());
        Test.startTest();
        KenLinkedInController.ProfilePreview preview =
            KenLinkedInController.fetchProfilePreview('https://www.linkedin.com/in/test');
        Test.stopTest();
        System.assertEquals(1, preview.experiencesCount, 'Mock returns one experience');
        System.assertEquals(1, preview.educationCount, 'Mock returns one education');
        System.assertEquals(1, preview.certificationsCount, 'Mock returns one certification');
        System.assertNotEquals(null, preview.rawJson, 'Raw payload is serialised');
    }

    @isTest
    static void testFetchProfilePreviewBlankUrl() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenLinkedInController.fetchProfilePreview('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank URL throws AuraHandledException');
    }

    @isTest
    static void testSyncCurrentUserFromLinkedInNoAccount() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenLinkedInController.syncCurrentUserFromLinkedIn('https://www.linkedin.com/in/test');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'No linked Person Account throws');
    }

    @isTest
    static void testSyncCurrentUserFromLinkedInBlankUrl() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenLinkedInController.syncCurrentUserFromLinkedIn('');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Blank LinkedIn URL throws');
    }

    @isTest
    static void testSyncAlumniNullId() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenLinkedInController.syncAlumni(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Null accountId throws');
    }

    @isTest
    static void testSyncAlumniBulkEmpty() {
        Test.startTest();
        KenLinkedInController.syncAlumniBulk(null);
        KenLinkedInController.syncAlumniBulk(new List<Id>());
        Test.stopTest();
        // Verifies the empty paths return cleanly with no exception.
    }
}