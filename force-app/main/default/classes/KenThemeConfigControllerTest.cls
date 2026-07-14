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

        Alumni_Org_Parameters__c orgDefaults = new Alumni_Org_Parameters__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Portal_Primary_colour__c = '#111111',
            Portal_Secondary_colour__c = '#222222',
            Portal_Tertiary_colour__c = '#333333',
            Institution_Name__c = 'Kenverse Institute',
            Institution_Alias__c = 'KVI',
            Show_Host_Event__c = true,
            Disable_Event_Fee__c = true
        );
        insert orgDefaults;
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
    }

    @IsTest
    static void getPortalConfigsShowHostEventDefaultsFalseWhenUnchecked() {
        Alumni_Org_Parameters__c orgDefaults = [
            SELECT Id, Show_Host_Event__c
            FROM Alumni_Org_Parameters__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1
        ];
        orgDefaults.Show_Host_Event__c = false;
        update orgDefaults;

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
        Alumni_Org_Parameters__c orgDefaults = [
            SELECT Id, Institution_Name__c, Institution_Alias__c
            FROM Alumni_Org_Parameters__c
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

        System.assertEquals('Kenverse', configs.institutionName, 'Blank institution name should use fallback value.');
        System.assertEquals('Ken42', configs.institutionAlias, 'Blank institution alias should use fallback value.');
    }
}