@isTest
private class KenExportCsvControllerTest {

    @isTest
    static void testGetDownloadUrl_success() {
        String csvContent = 'Name,Email,Status\n"Alice","alice@example.com","Active"\n"Bob","bob@example.com","Alumni"';
        String filename   = 'test_export.csv';

        Test.startTest();
        String url = KenExportCsvController.getDownloadUrl(csvContent, filename);
        Test.stopTest();

        System.assertNotEquals(null, url, 'URL should not be null');
        System.assert(
            url.startsWith('/sfc/servlet.shepherd/version/download/'),
            'URL should be a Salesforce content download path'
        );

        List<ContentVersion> cvList = [
            SELECT Title, PathOnClient, Origin, IsMajorVersion
            FROM ContentVersion
            WHERE Title = :filename
        ];
        System.assertEquals(1, cvList.size(), 'One ContentVersion should have been created');
        System.assertEquals(filename,  cvList[0].Title);
        System.assertEquals(filename,  cvList[0].PathOnClient);
        System.assertEquals('H',       cvList[0].Origin);
        System.assertEquals(true,      cvList[0].IsMajorVersion);
    }

    @isTest
    static void testGetDownloadUrl_urlContainsContentVersionId() {
        String csvContent = '"Col1","Col2"\n"val1","val2"';
        String filename   = 'id_check.csv';

        Test.startTest();
        String url = KenExportCsvController.getDownloadUrl(csvContent, filename);
        Test.stopTest();

        ContentVersion cv = [SELECT Id FROM ContentVersion WHERE Title = :filename LIMIT 1];
        System.assert(url.contains(cv.Id), 'Returned URL should contain the ContentVersion Id');
    }

    @isTest
    static void testGetDownloadUrl_exception() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            // null csvContent causes Blob.valueOf(null) to throw NullPointerException
            KenExportCsvController.getDownloadUrl(null, 'export.csv');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'AuraHandledException should have been thrown for null csvContent');
    }
}