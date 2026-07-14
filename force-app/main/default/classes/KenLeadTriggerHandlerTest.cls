@IsTest
private class KenLeadTriggerHandlerTest {

    private static final Id ALUMNI_LEAD_RT_ID = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Alumni Lead').getRecordTypeId();

    private static Lead newLead(String status, String email) {
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        Lead l = new Lead();
        l.LastName = 'Tester';
        l.Company  = 'TestCo';
        l.Status   = status;
        l.Email    = email;
        l.RecordTypeId = ALUMNI_LEAD_RT_ID;

        // REQUIRED in your org (from error)
        l.Registration_Number__c = 'REG-' + uniq;

        return l;
    }

    @IsTest
    static void testInsert_setsTokenAndExpiry() {
        Lead l = newLead('Verified', 'a@test.com');

        Test.startTest();
        insert l;
        Test.stopTest();

        Lead got = [
            SELECT Verification_Token__c, Token_Expiration_Date__c
            FROM Lead
            WHERE Id = :l.Id
            LIMIT 1
        ];

        System.assert(!String.isBlank(got.Verification_Token__c), 'Token should be generated');
        System.assertNotEquals(null, got.Token_Expiration_Date__c, 'Expiry should be set');
        System.assert(got.Token_Expiration_Date__c > System.now(), 'Expiry should be in future');
    }

    @IsTest
static void testUpdate_toVerified_executesAfterUpdateVerifiedFlow() {
    Lead l = newLead('Open - Not Contacted', 'b@test.com');
    insert l;

    Test.startTest();
    l.Status = 'Verified';
    update l;
    Test.stopTest();

    Lead got = [
        SELECT Status, Verification_Token__c, Token_Expiration_Date__c
        FROM Lead
        WHERE Id = :l.Id
        LIMIT 1
    ];

    // It may end up Converted due to KenAlumniOnboardingService.markLeadsConverted(...)
    System.assert(
        got.Status == 'Verified' || got.Status == 'Converted',
        'Expected Status Verified or Converted, but got: ' + got.Status
    );

    System.assert(!String.isBlank(got.Verification_Token__c));
    System.assertNotEquals(null, got.Token_Expiration_Date__c);
}

@IsTest
static void testResendMagicLink_errorBranches_typeOnly() {
    // MISSING_LEAD_ID
    try {
        KenLeadTriggerHandler.resendMagicLink(null);
        System.assert(false, 'Expected AuraHandledException');
    } catch (Exception e) {
        System.assert(
            e.getTypeName().endsWith('AuraHandledException'),
            'Expected AuraHandledException, Actual: ' + e.getTypeName()
        );
    }

    // MISSING_LEAD (fake Id)
    try {
        KenLeadTriggerHandler.resendMagicLink((Id)'00Q000000000000AAA');
        System.assert(false, 'Expected AuraHandledException');
    } catch (Exception e) {
        System.assert(
            e.getTypeName().endsWith('AuraHandledException'),
            'Expected AuraHandledException, Actual: ' + e.getTypeName()
        );
    }

    // NOT_VERIFIED
    Lead notVerified = newLead('Open - Not Contacted', 'nv@test.com');
    insert notVerified;

    try {
        KenLeadTriggerHandler.resendMagicLink(notVerified.Id);
        System.assert(false, 'Expected AuraHandledException');
    } catch (Exception e) {
        System.assert(
            e.getTypeName().endsWith('AuraHandledException'),
            'Expected AuraHandledException, Actual: ' + e.getTypeName()
        );
    }

    // MISSING_EMAIL
    Lead noEmail = newLead('Verified', null);
    insert noEmail;

    try {
        KenLeadTriggerHandler.resendMagicLink(noEmail.Id);
        System.assert(false, 'Expected AuraHandledException');
    } catch (Exception e) {
        System.assert(
            e.getTypeName().endsWith('AuraHandledException'),
            'Expected AuraHandledException, Actual: ' + e.getTypeName()
        );
    }
}

    @IsTest
    static void testUpdate_toRejected_executesRejectionLogic_earlyReturnWithoutTemplates() {
        Lead l = newLead('Verified', 'c@test.com');
        insert l;

        Test.startTest();
        l.Status = 'Rejected';
        update l;
        Test.stopTest();

        Lead got = [SELECT Status FROM Lead WHERE Id = :l.Id LIMIT 1];
        System.assertEquals('Rejected', got.Status);
    }

    @IsTest
    static void testResendMagicLink_success_regeneratesTokenWhenExpiredOrMissing() {
        Lead l = newLead('Verified', 'regen@test.com');
        insert l;

        // Force expired + missing token
        l.Verification_Token__c = null;
        l.Token_Expiration_Date__c = System.now().addHours(-1);
        update l;

        Test.startTest();
        KenLeadTriggerHandler.resendMagicLink(l.Id);
        Test.stopTest();

        Lead got = [
            SELECT Verification_Token__c, Token_Expiration_Date__c
            FROM Lead
            WHERE Id = :l.Id
            LIMIT 1
        ];

        System.assert(!String.isBlank(got.Verification_Token__c), 'Token should be regenerated');
        System.assert(got.Token_Expiration_Date__c > System.now(), 'Expiry should be extended');
    }

    @IsTest
    static void testFetchTemplateByDeveloperName_blankInput_returnsNull() {
        System.assertEquals(null, KenLeadTriggerHandler.fetchTemplateByDeveloperName(null));
        System.assertEquals(null, KenLeadTriggerHandler.fetchTemplateByDeveloperName(''));
        System.assertEquals(null, KenLeadTriggerHandler.fetchTemplateByDeveloperName('   '));
    }
}