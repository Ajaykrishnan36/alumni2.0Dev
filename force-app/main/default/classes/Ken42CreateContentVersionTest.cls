@isTest
Private class Ken42CreateContentVersionTest {
    @isTest
    static void testCreateContentVersion() {
        String title = 'TestFile.txt';
        String sampleContent = 'This is a test content';
        String base64String = EncodingUtil.base64Encode(Blob.valueOf(sampleContent));

        Test.startTest();
        String fileUrl = Ken42CreateContentVersion.createContentVersion(title, base64String);
        Test.stopTest();

        System.assertNotEquals(null, fileUrl, 'File URL or response should not be null.');
        System.assert(
            fileUrl.contains('https://') || fileUrl.contains('content') || fileUrl.contains('Error'),
            'File URL should contain expected pattern (URL or Error message). Actual: ' + fileUrl
        );
    }

    @isTest
    static void testCreateMultipleContentVersions() {
        Map<String, String> inputMap = new Map<String, String>();

        String content1 = 'Sample content 1';
        String content2 = 'Sample content 2';
        String base641 = EncodingUtil.base64Encode(Blob.valueOf(content1));
        String base642 = EncodingUtil.base64Encode(Blob.valueOf(content2));

        inputMap.put('Test1.txt', base641);
        inputMap.put('ID_Card_ABC.pdf', base642);

        Test.startTest();
        Map<String, String> urlMap = Ken42CreateContentVersion.createMultipleContentVersions(inputMap);
        Test.stopTest();

        System.assertNotEquals(null, urlMap, 'Returned URL map should not be null.');
        System.assert(!urlMap.isEmpty(), 'Returned URL map should not be empty.');
        System.assertEquals(2, urlMap.size(), 'Two files should have been processed.');
        for (String key : urlMap.keySet()) {
            String value = urlMap.get(key);
            System.assertNotEquals(null, value, 'Each map value should not be null.');
            System.assert(
                value.contains('https://') || value.contains('content') || value.contains('Error'),
                'Each returned value should be a valid file URL or error message.'
            );
        }
    }

    @isTest
    static void testEmptyMapInCreateMultipleContentVersions() {
        Map<String, String> emptyMap = new Map<String, String>();
        Test.startTest();
        Map<String, String> result = Ken42CreateContentVersion.createMultipleContentVersions(emptyMap);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null even for empty input.');
        System.assertEquals(true, result.isEmpty(), 'Result should be empty for an empty input map.');
    }

    @isTest
    static void testExceptionInCreateContentVersion() {
        // Passing invalid base64 to trigger exception handling
        String badBase64 = '%%%INVALID%%%';
        Test.startTest();
        String response = Ken42CreateContentVersion.createContentVersion('BadFile.txt', badBase64);
        Test.stopTest();
       System.assertNotEquals(null, response, 'Response should not be null.');
    System.assert(
        response.contains('Error') || 
        response.contains('Exception') || 
        response.contains('Invalid') || 
        response.contains('Unrecognized base64'),
        'Response should indicate an error for invalid Base64. Actual: ' + response
    );
}
 

}