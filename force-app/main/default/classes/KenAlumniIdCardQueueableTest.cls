@IsTest
private class KenAlumniIdCardQueueableTest {

    private static final String ALUMNI_RT = 'Alumni_Person_Account';

    private class MockQrSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(200);
            res.setBodyAsBlob(Blob.valueOf('FAKE_QR_PNG_DATA'));
            return res;
        }
    }

    private class MockQrFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(500);
            return res;
        }
    }

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT
            LIMIT 1
        ];
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account']) {
            if (rt.IsPersonType) {
                return rt.Id;
            }
        }
        return null;
    }

    private static User buildRunAsUser() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            Username  = 'idcardqueue.' + System.currentTimeMillis() + '@example.com',
            Email     = 'idcardqueue@example.com',
            LastName  = 'QueueTest',
            Alias     = 'iqtst',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = prof.Id
        );
    }

    @TestSetup
    static void setupData() {
        Id paRtId = getPersonAccountRtId();
        Account pa = new Account(
            LastName     = 'IdCardQueueableUser',
            PersonEmail  = 'idcard.queueable@test.example.com'
        );
        if (paRtId != null) {
            pa.RecordTypeId = paRtId;
        }
        insert pa;

        ConstituentRole cr = new ConstituentRole(
            PersonId               = pa.Id,
            RoleType               = 'Alumni',
            Registration_Status__c = 'Registered',
            Registration_Number__c = 'REG-QUEUE-001'
        );
        if (Schema.SObjectType.ConstituentRole.fields.getMap().containsKey('Status')) {
            cr.put('Status', 'Admitted');
        }
        insert cr;

        insert new Ken_Alumni_CRM__c(
            Person_Account__c     = pa.Id,
            ConstituentRole__c    = cr.Id,
            Registration_Number__c = 'REG-QUEUE-001'
        );
    }

    @IsTest
    static void testExecuteSingleRoleIdSuccess() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new MockQrSuccess());

        User runAsUser = buildRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            Test.startTest();
            System.enqueueJob(new KenAlumniIdCardQueueable(new Set<Id>{ cr.Id }));
            Test.stopTest();
        }

        Ken_Alumni_CRM__c updated = [SELECT ID_Card_URL__c FROM Ken_Alumni_CRM__c LIMIT 1];
        System.assertNotEquals(null, updated.ID_Card_URL__c, 'ID card URL should be set after successful queueable execution');
    }

    @IsTest
    static void testExecuteEmptyRoleIdsNoError() {
        Test.setMock(HttpCalloutMock.class, new MockQrSuccess());

        Test.startTest();
        System.enqueueJob(new KenAlumniIdCardQueueable(new Set<Id>()));
        Test.stopTest();
    }

    @IsTest
    static void testExecuteQrCalloutFailsGraceful() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new MockQrFailure());

        Test.startTest();
        System.enqueueJob(new KenAlumniIdCardQueueable(new Set<Id>{ cr.Id }));
        Test.stopTest();

        Ken_Alumni_CRM__c updated = [SELECT ID_Card_URL__c FROM Ken_Alumni_CRM__c LIMIT 1];
        System.assertNotEquals(null, updated.ID_Card_URL__c, 'ID card URL should be set even when QR callout returns non-200');
    }

    @IsTest
    static void testExecuteRoleWithNoAlumniCrmNoError() {
        Id paRtId = getPersonAccountRtId();
        Account pa2 = new Account(LastName = 'NoCrmAccount');
        if (paRtId != null) {
            pa2.RecordTypeId = paRtId;
        }
        insert pa2;

        ConstituentRole cr2 = new ConstituentRole(
            PersonId               = pa2.Id,
            RoleType               = 'Alumni',
            Registration_Status__c = 'Registered'
        );
        if (Schema.SObjectType.ConstituentRole.fields.getMap().containsKey('Status')) {
            cr2.put('Status', 'Admitted');
        }
        insert cr2;

        Test.setMock(HttpCalloutMock.class, new MockQrSuccess());

        Test.startTest();
        System.enqueueJob(new KenAlumniIdCardQueueable(new Set<Id>{ cr2.Id }));
        Test.stopTest();
    }
}