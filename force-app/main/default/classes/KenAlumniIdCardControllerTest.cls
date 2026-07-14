@IsTest
private class KenAlumniIdCardControllerTest {

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
            Username  = 'idcardctrl.' + System.currentTimeMillis() + '@example.com',
            Email     = 'idcardctrl@example.com',
            LastName  = 'IdCardCtrl',
            Alias     = 'idcc',
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
            FirstName   = 'IdCard',
            LastName    = 'Controller',
            PersonEmail = 'idcard.controller@test.example.com'
        );
        if (paRtId != null) {
            pa.RecordTypeId = paRtId;
        }
        insert pa;

        ConstituentRole cr = new ConstituentRole(
            PersonId               = pa.Id,
            RoleType               = 'Alumni',
            Registration_Status__c = 'Registered',
            Registration_Number__c = 'REG-CTRL-001'
        );
        if (Schema.SObjectType.ConstituentRole.fields.getMap().containsKey('Status')) {
            cr.put('Status', 'Admitted');
        }
        insert cr;

        insert new Ken_Alumni_CRM__c(
            Person_Account__c  = pa.Id,
            ConstituentRole__c = cr.Id,
            Profile_Photo_URL__c = 'https://example.com/photo.jpg'
        );
    }

    @IsTest
    static void testConstructorWithRoleIdAndQrData() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];

        User runAsUser = buildRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            PageReference pageRef = new PageReference('/apex/KenAlumniIdCard');
            pageRef.getParameters().put('roleId', cr.Id);
            pageRef.getParameters().put('qrData', 'FAKE_BASE64_QR');
            Test.setCurrentPage(pageRef);

            Test.startTest();
            KenAlumniIdCardController ctrl = new KenAlumniIdCardController();
            Test.stopTest();

            System.assertNotEquals(null, ctrl.roleId, 'roleId should be set from page parameter');
            System.assertEquals(true, ctrl.hasQrCode, 'hasQrCode should be true when qrData is provided');
            System.assertNotEquals(null, ctrl.alumniName, 'alumniName should be populated from ConstituentRole.PersonId');
            System.assertEquals(true, ctrl.hasPhoto, 'hasPhoto should be true when CRM profile photo URL exists');
        }
    }

    @IsTest
    static void testConstructorWithRoleIdNoQr() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];

        PageReference pageRef = new PageReference('/apex/KenAlumniIdCard');
        pageRef.getParameters().put('roleId', cr.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        KenAlumniIdCardController ctrl = new KenAlumniIdCardController();
        Test.stopTest();

        System.assertEquals(false, ctrl.hasQrCode, 'hasQrCode should be false when no qrData param is provided');
        System.assertNotEquals(null, ctrl.roleId, 'roleId should be populated from page parameter');
    }

    @IsTest
    static void testConstructorBlankRoleId() {
        PageReference pageRef = new PageReference('/apex/KenAlumniIdCard');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        KenAlumniIdCardController ctrl = new KenAlumniIdCardController();
        Test.stopTest();

        System.assertEquals(false, ctrl.hasPhoto, 'hasPhoto should be false when no roleId is provided');
        System.assertEquals(false, ctrl.hasQrCode, 'hasQrCode should be false when no roleId is provided');
    }

    @IsTest
    static void testConstructorInvalidRoleId() {
        PageReference pageRef = new PageReference('/apex/KenAlumniIdCard');
        pageRef.getParameters().put('roleId', 'INVALID_ID_VALUE');
        Test.setCurrentPage(pageRef);

        Test.startTest();
        KenAlumniIdCardController ctrl = new KenAlumniIdCardController();
        Test.stopTest();

        System.assertEquals(false, ctrl.hasPhoto, 'hasPhoto should be false when roleId lookup returns no records');
    }

    @IsTest
    static void testConstructorGraduationYearChars() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];
        if (Schema.SObjectType.ConstituentRole.fields.getMap().containsKey('Graduation_Year__c')) {
            cr.put('Graduation_Year__c', '2024');
            update cr;
        }

        PageReference pageRef = new PageReference('/apex/KenAlumniIdCard');
        pageRef.getParameters().put('roleId', cr.Id);
        Test.setCurrentPage(pageRef);

        Test.startTest();
        KenAlumniIdCardController ctrl = new KenAlumniIdCardController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.yearChars, 'yearChars list should be initialized');
    }
}