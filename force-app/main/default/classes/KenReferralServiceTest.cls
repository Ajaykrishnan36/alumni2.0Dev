@IsTest
private class KenReferralServiceTest {

    private static final String ALUMNI_RT = 'PersonAccount';

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
        ];
        if (!rts.isEmpty()) return rts[0].Id;
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account' AND IsActive = true]) {
            if (rt.IsPersonType) return rt.Id;
        }
        return null;
    }

    private static Account buildPersonAccount(String suffix, String referralCode) {
        Account pa = new Account(
            FirstName   = 'Referral',
            LastName    = 'TestUser' + suffix,
            PersonEmail = 'referral.' + suffix + '.' + System.currentTimeMillis() + '@test.com',
            Referral_Code__c = referralCode
        );
        Id rtId = getPersonAccountRtId();
        if (rtId != null) pa.RecordTypeId = rtId;
        return pa;
    }

    private static User buildAdminUser() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            Username          = 'referral.admin.' + System.currentTimeMillis() + '@example.com',
            Email             = 'referral.admin@example.com',
            LastName          = 'ReferralAdmin',
            Alias             = 'rfa',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = prof.Id
        );
    }

    @TestSetup
    static void makeData() {
        // Org default Portal URL used to build the referral link.
        Ken_Alm_Org_Parameters__c p = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        if (p == null || p.Id == null) {
            p = new Ken_Alm_Org_Parameters__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        p.Portal_URL__c = 'https://portal.example.com/';
        upsert p;

        insert new List<Account>{
            buildPersonAccount('WithCode', 'EXISTINGCODE1'),
            buildPersonAccount('NoCode', null)
        };
    }

    // resolveReferrerAccountId — found, unknown, null, blank
    @IsTest
    static void resolveReferrerAccountId_variants() {
        Account withCode = [SELECT Id FROM Account WHERE Referral_Code__c = 'EXISTINGCODE1' LIMIT 1];
        Test.startTest();
        Id found     = KenReferralService.resolveReferrerAccountId('EXISTINGCODE1');
        Id notFound  = KenReferralService.resolveReferrerAccountId('DOES_NOT_EXIST');
        Id nullCode  = KenReferralService.resolveReferrerAccountId(null);
        Id blankCode = KenReferralService.resolveReferrerAccountId('   ');
        Test.stopTest();
        System.assertEquals(withCode.Id, found, 'Known code should resolve to its account');
        System.assertEquals(null, notFound, 'Unknown code should be null');
        System.assertEquals(null, nullCode, 'Null code should be null');
        System.assertEquals(null, blankCode, 'Blank code should be null');
    }

    /*
     * The two tests below name their Account through the seam rather than inserting a portal
     * User and running as them. That insert was the only thing here that could fail: portal-user
     * creation contends on shared rows, so under a full parallel RunLocalTests it intermittently
     * threw UNABLE_TO_LOCK_ROW. It also carried an `if (u == null) return;` escape that silently
     * turned both tests into no-ops in any org without an 'Alumni' profile.
     */

    // getReferralLink — account already has a code (no generation, no update needed)
    @IsTest
    static void getReferralLink_existingCode() {
        Account acc = [SELECT Id FROM Account WHERE Referral_Code__c = 'EXISTINGCODE1' LIMIT 1];
        KenReferralService.testRunningAccountId = acc.Id;

        Test.startTest();
        String link = KenReferralService.getReferralLink();
        Test.stopTest();

        System.assertNotEquals(null, link, 'Link should be built for a community user with an account');
        System.assertEquals('https://portal.example.com/SelfRegister?referal=EXISTINGCODE1', link,
            'Link should embed the existing referral code against the org Portal_URL__c');
    }

    // getReferralLink — account has no code yet (exercises generateCode + update path)
    @IsTest
    static void getReferralLink_generatesCode() {
        Account acc = [SELECT Id FROM Account
                       WHERE Referral_Code__c = null AND IsPersonAccount = true LIMIT 1];
        KenReferralService.testRunningAccountId = acc.Id;

        Test.startTest();
        String link = KenReferralService.getReferralLink();
        Test.stopTest();

        System.assertNotEquals(null, link, 'A missing code should be generated, not fatal');
        System.assert(link.startsWith('https://portal.example.com/SelfRegister?referal='),
            'Link should be a SelfRegister URL: ' + link);
        Account after = [SELECT Referral_Code__c FROM Account WHERE Id = :acc.Id];
        System.assertNotEquals(null, after.Referral_Code__c,
            'The generated code should be persisted back to the Account');
        System.assert(link.endsWith(after.Referral_Code__c),
            'The link should carry the code that was just stored');
    }

    // getReferralLink — running user has no Account -> null (early return branch)
    @IsTest
    static void getReferralLink_noAccount() {
        User admin = buildAdminUser();
        insert admin;
        System.runAs(admin) {
            Test.startTest();
            String link = KenReferralService.getReferralLink();
            Test.stopTest();
            System.assertEquals(null, link, 'A user without an Account should get a null link');
        }
    }
}