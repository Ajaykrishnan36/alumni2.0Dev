@IsTest
private class KenThemeConfigControllerTest {

    @TestSetup
    static void setupData() {
        Id profileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;
        User runAsUser = new User(
            FirstName = 'Portal',
            LastName = 'ConfigTester',
            Email = 'portal.config.tester@example.com',
            Username = 'portal.config.tester.' + DateTime.now().getTime() + '@example.com',
            Alias = 'pctst',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
        insert runAsUser;

        Ken_Alm_Org_Parameters__c orgDefaults = new Ken_Alm_Org_Parameters__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Portal_Primary_colour__c = '#111111',
            Portal_Secondary_colour__c = '#222222',
            Portal_Tertiary_colour__c = '#333333',
            Institution_Name__c = 'Kenverse Institute',
            Institution_Alias__c = 'KVI',
            Disable_Event_Fee__c = true,
            Google_SSO_Provider__c = 'GoogleNewSSO'
        );
        insert orgDefaults;

        // "Host an event" is now driven by Ken_Alm_Module_Settings__c (Allow Create Events).
        insert new Ken_Alm_Module_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Allow_Create_Events__c = true
        );
    }

    @IsTest
    static void getPortalConfigsReturnsConfiguredValues() {
        User runAsUser = [SELECT Id FROM User WHERE Alias = 'pctst' LIMIT 1];
        KenThemeConfigController.portalconfigs configs;
        System.runAs(runAsUser) {
            Test.startTest();
            configs = KenThemeConfigController.getPortalConfigs();
            Test.stopTest();
        }

        System.assertNotEquals(null, configs, 'Portal config wrapper should be returned.');
        System.assertEquals('#111111', configs.primaryColor, 'Primary color should come from org defaults.');
        System.assertEquals('#222222', configs.secondaryColor, 'Secondary color should come from org defaults.');
        System.assertEquals('#333333', configs.tertiaryColor, 'Tertiary color should come from org defaults.');
        System.assertEquals('Kenverse Institute', configs.institutionName, 'Institution name should come from org defaults.');
        System.assertEquals('KVI', configs.institutionAlias, 'Institution alias should come from org defaults.');
        System.assertEquals(true, configs.showHostEvent, 'Show Host Event flag should reflect the org default checkbox.');
        System.assertEquals(true, configs.disableEventFee, 'Disable Event Fee flag should reflect the org default checkbox.');
        System.assertEquals('GoogleNewSSO', configs.googleSsoProvider, 'Google SSO provider should come from org defaults.');
    }

    @IsTest
    static void getPortalConfigsHidesGoogleSsoWhenUnconfigured() {
        Ken_Alm_Org_Parameters__c orgDefaults = [
            SELECT Id, Google_SSO_Provider__c
            FROM Ken_Alm_Org_Parameters__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1
        ];
        orgDefaults.Google_SSO_Provider__c = '';
        update orgDefaults;

        User runAsUser = [SELECT Id FROM User WHERE Alias = 'pctst' LIMIT 1];
        KenThemeConfigController.portalconfigs configs;
        System.runAs(runAsUser) {
            Test.startTest();
            configs = KenThemeConfigController.getPortalConfigs();
            Test.stopTest();
        }

        System.assertEquals(null, configs.googleSsoProvider, 'A blank Google SSO provider should stay null so the login button is hidden.');
    }

    @IsTest
    static void getPortalConfigsShowHostEventDefaultsFalseWhenUnchecked() {
        Ken_Alm_Module_Settings__c ms = [
            SELECT Id, Allow_Create_Events__c
            FROM Ken_Alm_Module_Settings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1
        ];
        ms.Allow_Create_Events__c = false;
        update ms;

        User runAsUser = [SELECT Id FROM User WHERE Alias = 'pctst' LIMIT 1];
        KenThemeConfigController.portalconfigs configs;
        System.runAs(runAsUser) {
            Test.startTest();
            configs = KenThemeConfigController.getPortalConfigs();
            Test.stopTest();
        }

        System.assertEquals(false, configs.showHostEvent, 'Show Host Event flag should be false when the checkbox is unchecked.');
    }

    @IsTest
    static void getPortalConfigsUsesFallbackForBlankInstitutionValues() {
        Ken_Alm_Org_Parameters__c orgDefaults = [
            SELECT Id, Institution_Name__c, Institution_Alias__c
            FROM Ken_Alm_Org_Parameters__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1
        ];
        orgDefaults.Institution_Name__c = '   ';
        orgDefaults.Institution_Alias__c = '';
        update orgDefaults;

        User runAsUser = [SELECT Id FROM User WHERE Alias = 'pctst' LIMIT 1];
        KenThemeConfigController.portalconfigs configs;
        System.runAs(runAsUser) {
            Test.startTest();
            configs = KenThemeConfigController.getPortalConfigs();
            Test.stopTest();
        }

        System.assertEquals('Institute Name', configs.institutionName, 'Blank institution name should use fallback value.');
        System.assertEquals('Institute', configs.institutionAlias, 'Blank institution alias should use fallback value.');
    }

    @IsTest
    static void getPortalConfigsDefaultsLoginToPasswordAndEmail() {
        User runAsUser = [SELECT Id FROM User WHERE Alias = 'pctst' LIMIT 1];
        KenThemeConfigController.portalconfigs configs;
        System.runAs(runAsUser) {
            Test.startTest();
            configs = KenThemeConfigController.getPortalConfigs();
            Test.stopTest();
        }

        System.assertEquals('Password', configs.loginMethod, 'An unconfigured org should keep password login.');
        System.assertEquals('Email', configs.otpDeliveryChannel, 'An unconfigured org should default to the email channel.');
    }

    @IsTest
    static void getPortalConfigsReturnsConfiguredLoginSettings() {
        Ken_Alm_Org_Parameters__c orgDefaults = [
            SELECT Id, Login_Method__c, OTP_Delivery_Channel__c
            FROM Ken_Alm_Org_Parameters__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1
        ];
        orgDefaults.Login_Method__c = ' Both ';
        orgDefaults.OTP_Delivery_Channel__c = ' SMS ';
        update orgDefaults;

        User runAsUser = [SELECT Id FROM User WHERE Alias = 'pctst' LIMIT 1];
        KenThemeConfigController.portalconfigs configs;
        System.runAs(runAsUser) {
            Test.startTest();
            configs = KenThemeConfigController.getPortalConfigs();
            Test.stopTest();
        }

        System.assertEquals('Both', configs.loginMethod, 'The configured login method should be trimmed and returned.');
        System.assertEquals('SMS', configs.otpDeliveryChannel, 'The configured OTP channel should be trimmed and returned.');
    }
}