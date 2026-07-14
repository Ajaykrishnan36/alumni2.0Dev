@IsTest
private class KenEngagementPreferenceControllerTest {

    @TestSetup
    static void setup() {
        insert new List<Ken_Engagement_Preference__c>{
            new Ken_Engagement_Preference__c(
                Name = 'Give back to the community',
                Description__c = 'Support students and causes that matter to you',
                Image_URL__c = '/sfsites/c/resource/eventTest2',
                Icon__c = 'utility:heart',
                Email__c = 'give@example.com',
                Sort_Order__c = 2,
                Is_Active__c = true
            ),
            new Ken_Engagement_Preference__c(
                Name = 'Learn from fellow alumni',
                Image_URL__c = '/sfsites/c/resource/donateImg',
                Sort_Order__c = 1,
                Is_Active__c = true
            ),
            new Ken_Engagement_Preference__c(
                Name = 'Hidden option',
                Sort_Order__c = 3,
                Is_Active__c = false
            )
        };
    }

    @IsTest
    static void returnsActiveOptionsOrderedBySortOrder() {
        Test.startTest();
        List<KenEngagementPreferenceController.PreferenceOption> options =
            KenEngagementPreferenceController.getOptions();
        Test.stopTest();

        System.assertEquals(2, options.size(), 'Only active options should be returned.');
        System.assertEquals('Learn from fellow alumni', options[0].name, 'Lowest sort order should come first.');
        System.assertEquals('Give back to the community', options[1].name, 'Higher sort order should follow.');
        System.assertEquals('/sfsites/c/resource/donateImg', options[0].imageUrl, 'Image URL should be returned.');
        System.assertEquals('utility:heart', options[1].iconUrl, 'Icon should be returned.');
        System.assertEquals('give@example.com', options[1].email, 'Email should be returned.');
        System.assertEquals('Support students and causes that matter to you', options[1].description, 'Description should be returned.');
    }
}