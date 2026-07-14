@IsTest
private class KenAlumniSpotlightControllerTest {

    private static User buildRunAsUser() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            Username  = 'spotlight.test.' + System.currentTimeMillis() + '@example.com',
            Email     = 'spotlight.test@example.com',
            LastName  = 'SpotlightTest',
            Alias     = 'sptst',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = prof.Id
        );
    }

    @TestSetup
    static void setupData() {
        insert new List<KenAlumniSpotlight__c>{
            new KenAlumniSpotlight__c(
                Name             = 'Spotlight Active',
                Title__c         = 'Active Title',
                Description__c   = 'Active Description',
                Content_Link__c  = 'https://example.com',
                Type__c          = 'Image',
                Is_Active__c     = true,
                Display_Order__c = 1,
                Featured_From__c = Date.today().addDays(-1),
                Featured_To__c   = Date.today().addDays(1)
            ),
            new KenAlumniSpotlight__c(
                Name             = 'Spotlight No Dates',
                Title__c         = 'No Dates Title',
                Is_Active__c     = true,
                Display_Order__c = 2
            ),
            new KenAlumniSpotlight__c(
                Name             = 'Spotlight Inactive',
                Title__c         = 'Inactive Title',
                Is_Active__c     = false,
                Display_Order__c = 3
            ),
            new KenAlumniSpotlight__c(
                Name           = 'Spotlight Expired',
                Title__c       = 'Expired Title',
                Is_Active__c   = true,
                Display_Order__c = 4,
                Featured_To__c = Date.today().addDays(-1)
            )
        };
    }

    @IsTest
    static void testGetAlumniSpotlightsReturnsActiveRecords() {
        User runAsUser = buildRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            Test.startTest();
            List<KenAlumniSpotlightController.SpotlightRow> rows = KenAlumniSpotlightController.getAlumniSpotlights();
            Test.stopTest();

            System.assertNotEquals(null, rows, 'Result list should not be null');

            Set<String> returnedNames = new Set<String>();
            for (KenAlumniSpotlightController.SpotlightRow row : rows) {
                returnedNames.add(row.name);
            }
            System.assertEquals(true, returnedNames.contains('Spotlight Active'),
                'Active record within date range should be returned');
            System.assertEquals(true, returnedNames.contains('Spotlight No Dates'),
                'Active record without date bounds should be returned');
            System.assertEquals(false, returnedNames.contains('Spotlight Inactive'),
                'Inactive record should be excluded');
        }
    }

    @IsTest
    static void testGetAlumniSpotlightsRowFieldsPopulated() {
        Test.startTest();
        List<KenAlumniSpotlightController.SpotlightRow> rows = KenAlumniSpotlightController.getAlumniSpotlights();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Rows list should not be null');
        System.assertEquals(true, rows.size() > 0, 'Should have at least one active spotlight');

        KenAlumniSpotlightController.SpotlightRow firstRow = rows[0];
        System.assertNotEquals(null, firstRow.id, 'Spotlight row id should not be null');
        System.assertNotEquals(null, firstRow.name, 'Spotlight row name should not be null');
        System.assertNotEquals(null, firstRow.title, 'Spotlight row title should not be null');
        System.assertNotEquals(null, firstRow.displayOrder, 'Spotlight row displayOrder should not be null');
        System.assertEquals('Image', firstRow.contentType, 'Spotlight row contentType should reflect Type__c');
    }

    @IsTest
    static void testGetAlumniSpotlightsEmptyWhenNoneActive() {
        delete [SELECT Id FROM KenAlumniSpotlight__c WHERE Is_Active__c = true];

        Test.startTest();
        List<KenAlumniSpotlightController.SpotlightRow> rows = KenAlumniSpotlightController.getAlumniSpotlights();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Result should be an empty list, not null');
        System.assertEquals(0, rows.size(), 'No active spotlights should return empty list');
    }
}