@IsTest
private class KenModuleVisibilityControllerTest {

    @IsTest
    static void defaultsToAllShownWhenNoSettingExists() {
        // No Alumni_Module_Settings__c record inserted => every module shown.
        Test.startTest();
        KenModuleVisibilityController.ModuleVisibility mv =
            KenModuleVisibilityController.getModuleVisibility();
        Test.stopTest();

        System.assertNotEquals(null, mv, 'Visibility wrapper should be returned.');
        System.assertEquals(true, mv.home, 'Home should default to shown.');
        System.assertEquals(true, mv.events, 'Events should default to shown.');
        System.assertEquals(true, mv.jobs, 'Jobs should default to shown.');
        System.assertEquals(true, mv.network, 'Network should default to shown.');
        System.assertEquals(true, mv.mentorship, 'Mentorship should default to shown.');
        System.assertEquals(true, mv.fundraise, 'Fundraise should default to shown.');
        System.assertEquals(true, mv.groups, 'Groups should default to shown.');
        System.assertEquals(true, mv.gallery, 'Gallery should default to shown.');
        System.assertEquals(true, mv.businessDirectory, 'Business Directory should default to shown.');
        System.assertEquals(true, mv.feedbackSurvey, 'Feedback and Survey should default to shown.');
        System.assertEquals(true, mv.serviceSupport, 'Service and Support should default to shown.');
    }

    @IsTest
    static void hidesModulesWhenExplicitlyUnchecked() {
        insert new Alumni_Module_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Show_Home__c = true,
            Show_Events__c = false,
            Show_Jobs__c = false,
            Show_Network__c = false,
            Show_Mentorship__c = false,
            Show_Fundraise__c = false,
            Show_Groups__c = false,
            Show_Gallery__c = false,
            Show_Business_Directory__c = false,
            Show_Feedback_Survey__c = false,
            Show_Service_Support__c = false
        );

        Test.startTest();
        KenModuleVisibilityController.ModuleVisibility mv =
            KenModuleVisibilityController.getModuleVisibility();
        Test.stopTest();

        System.assertEquals(true, mv.home, 'Home should remain shown.');
        System.assertEquals(false, mv.events, 'Events should be hidden when unchecked.');
        System.assertEquals(false, mv.jobs, 'Jobs should be hidden when unchecked.');
        System.assertEquals(false, mv.network, 'Network should be hidden when unchecked.');
        System.assertEquals(false, mv.mentorship, 'Mentorship should be hidden when unchecked.');
        System.assertEquals(false, mv.fundraise, 'Fundraise should be hidden when unchecked.');
        System.assertEquals(false, mv.groups, 'Groups should be hidden when unchecked.');
        System.assertEquals(false, mv.gallery, 'Gallery should be hidden when unchecked.');
        System.assertEquals(false, mv.businessDirectory, 'Business Directory should be hidden when unchecked.');
        System.assertEquals(false, mv.feedbackSurvey, 'Feedback and Survey should be hidden when unchecked.');
        System.assertEquals(false, mv.serviceSupport, 'Service and Support should be hidden when unchecked.');
    }

    @IsTest
    static void hidesOnlySelectedModules() {
        insert new Alumni_Module_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Show_Events__c = true,
            Show_Jobs__c = false,
            Show_Fundraise__c = false
        );

        Test.startTest();
        KenModuleVisibilityController.ModuleVisibility mv =
            KenModuleVisibilityController.getModuleVisibility();
        Test.stopTest();

        System.assertEquals(true, mv.events, 'Events should stay shown.');
        System.assertEquals(false, mv.jobs, 'Jobs should be hidden.');
        System.assertEquals(false, mv.fundraise, 'Fundraise should be hidden.');
        System.assertEquals(true, mv.network, 'Untouched modules should remain shown.');
        System.assertEquals(true, mv.groups, 'Untouched modules should remain shown.');
    }
}