@IsTest
private class KenAlumniIdCardServiceTest {

    private static final String ALUMNI_RT = 'Alumni_Person_Account';

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
            Username  = 'idcardservice.' + System.currentTimeMillis() + '@example.com',
            Email     = 'idcardservice@example.com',
            LastName  = 'IdCardTest',
            Alias     = 'icsvc',
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
            LastName     = 'IdCardUser',
            PersonEmail  = 'idcard.service@test.example.com'
        );
        if (paRtId != null) {
            pa.RecordTypeId = paRtId;
        }
        insert pa;

        ConstituentRole cr = new ConstituentRole(
            PersonId               = pa.Id,
            RoleType               = 'Alumni',
            Registration_Status__c = 'Registered'
        );
        if (Schema.SObjectType.ConstituentRole.fields.getMap().containsKey('Status')) {
            cr.put('Status', 'Admitted');
        }
        insert cr;

        insert new Ken_Alumni_CRM__c(
            Person_Account__c     = pa.Id,
            ConstituentRole__c    = cr.Id,
            Registration_Number__c = 'OLD-REG-001',
            ID_Card_URL__c        = 'https://old.url/card.pdf'
        );
    }

    @IsTest
    static void testInitializeForRegisteredNullMap() {
        User runAsUser = buildRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            Test.startTest();
            KenAlumniIdCardService.initializeForRegistered(null);
            Test.stopTest();
        }
    }

    @IsTest
    static void testInitializeForRegisteredEmptyMap() {
        Test.startTest();
        KenAlumniIdCardService.initializeForRegistered(new Map<Id, String>());
        Test.stopTest();
    }

    @IsTest
    static void testInitializeForRegisteredNoMatchingAlumni() {
        Id paRtId = getPersonAccountRtId();
        Account pa2 = new Account(LastName = 'NoAlumniCRM');
        if (paRtId != null) {
            pa2.RecordTypeId = paRtId;
        }
        insert pa2;

        ConstituentRole cr2 = new ConstituentRole(
            PersonId               = pa2.Id,
            RoleType               = 'Alumni',
            Registration_Status__c = 'Unregistered'
        );
        if (Schema.SObjectType.ConstituentRole.fields.getMap().containsKey('Status')) {
            cr2.put('Status', 'Admitted');
        }
        insert cr2;

        Test.startTest();
        KenAlumniIdCardService.initializeForRegistered(new Map<Id, String>{ cr2.Id => 'NEW-REG-999' });
        Test.stopTest();
    }

    @IsTest
    static void testInitializeForRegisteredUpdatesRegNumberAndClearsUrl() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];

        Test.startTest();
        KenAlumniIdCardService.initializeForRegistered(new Map<Id, String>{ cr.Id => 'NEW-REG-001' });
        Test.stopTest();

        Ken_Alumni_CRM__c updated = [
            SELECT Registration_Number__c, ID_Card_URL__c FROM Ken_Alumni_CRM__c LIMIT 1
        ];
        System.assertEquals('NEW-REG-001', updated.Registration_Number__c, 'Registration number should be updated to NEW-REG-001');
        System.assertEquals(null, updated.ID_Card_URL__c, 'ID card URL should be cleared to null');
    }

    @IsTest
    static void testInitializeForRegisteredClearsUrlWhenRegNumberSame() {
        Ken_Alumni_CRM__c alumni = [SELECT Id, ConstituentRole__c FROM Ken_Alumni_CRM__c LIMIT 1];
        alumni.Registration_Number__c = 'SAME-REG';
        update alumni;

        Test.startTest();
        KenAlumniIdCardService.initializeForRegistered(
            new Map<Id, String>{ alumni.ConstituentRole__c => 'SAME-REG' }
        );
        Test.stopTest();

        Ken_Alumni_CRM__c updated = [SELECT ID_Card_URL__c FROM Ken_Alumni_CRM__c LIMIT 1];
        System.assertEquals(null, updated.ID_Card_URL__c, 'ID card URL should be cleared even when reg number is unchanged');
    }

    @IsTest
    static void testInitializeForRegisteredBlankRegNumberSkipsRegUpdate() {
        Ken_Alumni_CRM__c alumni = [SELECT Id, ConstituentRole__c FROM Ken_Alumni_CRM__c LIMIT 1];

        Test.startTest();
        KenAlumniIdCardService.initializeForRegistered(
            new Map<Id, String>{ alumni.ConstituentRole__c => '' }
        );
        Test.stopTest();

        Ken_Alumni_CRM__c updated = [SELECT ID_Card_URL__c FROM Ken_Alumni_CRM__c LIMIT 1];
        System.assertEquals(null, updated.ID_Card_URL__c, 'ID card URL should be cleared when blank reg number is passed');
    }
}