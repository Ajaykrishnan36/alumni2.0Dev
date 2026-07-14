@isTest
private class KenCommunityLoginV2ControllerTest {

    @isTest
    static void blank_inputs_throw() {
        try {
            KenCommunityLoginV2Controller.login('', 'pwd', '/');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void no_user_throws() {
        try {
            KenCommunityLoginV2Controller.login('nobody-xyz-987@example.com', 'whatever', '/');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void test_mode_returns_mock() {
        // Pick any active user for the test
        User u = [SELECT Id, Username FROM User WHERE IsActive = true LIMIT 1];
        Test.startTest();
        KenCommunityLoginV2Controller.LoginResult res = KenCommunityLoginV2Controller.login(u.Username, 'irrelevant', '/alumninew/');
        Test.stopTest();
        System.assertEquals('/alumninew/', res.url);
        System.assertEquals(u.Id, res.userId);
    }
}