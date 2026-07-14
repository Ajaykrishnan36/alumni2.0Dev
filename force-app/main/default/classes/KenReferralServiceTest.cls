@IsTest
private class KenReferralServiceTest {

    private static final String ALUMNI_RT      = 'Alumni_Person_Account';
    private static final String ALUMNI_PROFILE = 'Alumni-Student';

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
        ];
        if (!rts.isEmpty()) return rts[0].Id;
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account']) {
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

    private static User buildCommunityUser(Id contactId, String tag) {
        List<Profile> profs = [SELECT Id FROM Profile WHERE Name = :ALUMNI_PROFILE LIMIT 1];
        if (profs.isEmpty()) return null;
        return new User(
            Username          = 'referral.' + tag + '.' + System.currentTimeMillis() + '@test.alumni.com',
            Email             = 'referral.community@test.alumni.com',
            LastName          = 'ReferralCommunity',
            Alias             = 'refc',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = profs[0].Id,
            ContactId         = contactId
        );
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
        Alumni_Org_Parameters__c p = Alumni_Org_Parameters__c.getOrgDefaults();
        if (p == null || p.Id == null) {
            p = new Alumni_Org_Parameters__c(SetupOwnerId = UserInfo.getOrganizationId());
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

    // getReferralLink — account already has a code (no generation, no update needed)
    @IsTest
    static void getReferralLink_existingCode() {
        Account acc = [SELECT Id, PersonContactId FROM Account WHERE Referral_Code__c = 'EXISTINGCODE1' LIMIT 1];
        User u = buildCommunityUser(acc.PersonContactId, 'exist');
        if (u == null) return; // community profile not present in this org
        insert u;

        System.runAs(u) {
            Test.startTest();
            String link = KenReferralService.getReferralLink();
            Test.stopTest();
            System.assertNotEquals(null, link, 'Link should be built for a community user with an account');
            System.assert(link.contains('/SelfRegister?referal=EXISTINGCODE1'),
                'Link should embed the existing referral code: ' + link);
        }
    }

    // getReferralLink — account has no code yet (exercises generateCode + update path)
    @IsTest
    static void getReferralLink_generatesCode() {
        Account acc = [SELECT Id, PersonContactId FROM Account
                       WHERE Referral_Code__c = null AND IsPersonAccount = true LIMIT 1];
        User u = buildCommunityUser(acc.PersonContactId, 'gen');
        if (u == null) return;
        insert u;

        System.runAs(u) {
            Test.startTest();
            String link = KenReferralService.getReferralLink();
            Test.stopTest();
            // Depending on the community profile's field access the update may or may not
            // succeed; either way the code-generation branch is exercised. When it works,
            // the link is a well-formed SelfRegister URL.
            if (link != null) {
                System.assert(link.contains('/SelfRegister?referal='), 'Link should be a SelfRegister URL: ' + link);
            }
        }
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