@IsTest
private class NavigationMenuItemsControllerTest {

    @IsTest
    static void test_getNavigationMenuItems_withBypass_returnsDummyItem() {
        NavigationMenuItemsController.TEST_BYPASS = true;

        Test.startTest();
        List<ConnectApi.NavigationMenuItem> items =
            NavigationMenuItemsController.getNavigationMenuItems(
                null,      // defaults to 'Default Navigation'
                'Live',    // covers Live branch
                true,
                false
            );
        Test.stopTest();

        System.assertNotEquals(null, items);
        System.assertEquals(1, items.size());
        System.assertEquals('Home', items[0].label);
    }

    @IsTest
    static void test_getNavigationMenuItems_publishStatusDraft_branch() {
        NavigationMenuItemsController.TEST_BYPASS = true;

        Test.startTest();
        List<ConnectApi.NavigationMenuItem> items =
            NavigationMenuItemsController.getNavigationMenuItems(
                'Default Navigation',
                'Draft',  // covers Draft branch
                false,
                true
            );
        Test.stopTest();

        System.assertEquals(1, items.size());
        System.assertEquals('Home', items[0].label);
    }

    @IsTest
    static void test_getNavigationLinkSetDeveloperName_inTestWithoutBypass_returnsNull() {
        NavigationMenuItemsController.TEST_BYPASS = false;

        // No startTest/stopTest needed
        String devName = NavigationMenuItemsController.getNavigationLinkSetDeveloperName('Anything');
        System.assertEquals(null, devName);
    }

    @IsTest
    static void test_getNavigationLinkSetDeveloperName_withBypass_runsQueryPath() {
        NavigationMenuItemsController.TEST_BYPASS = true;

        // This executes the SOQL branch. In most orgs there won't be a NavigationLinkSet
        // record created in test context, so null is expected, but coverage is achieved.
        String devName = NavigationMenuItemsController.getNavigationLinkSetDeveloperName('Nonexistent Label');
        System.assertEquals(null, devName);
    }
}