@isTest
private class KenFileUploadControllerTest {
    @isTest
    static void testUploadAndGetPublicUrl() {
        String fileName = 'testFile.txt';
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf('Test content'));
        
        Test.startTest();
        String result = KenFileUploadController.uploadAndGetPublicUrl(fileName, base64Content);
        Test.stopTest();
    }
    
    @isTest
static void testUploadImage_Account_Success() {
    Account acc = new Account(Name = 'Test Account');
    insert acc;

    String raw = EncodingUtil.base64Encode(Blob.valueOf('fake image bytes'));
    String base64Data = 'data:image/png;base64,' + raw;

    Test.startTest();
        KenFileUploadController.uploadImage(
            acc.Id,
            'Account',
            'logo.png',
            base64Data
        );
    Test.stopTest();

    Account updated = [SELECT Id, Logo_File_URL__c FROM Account WHERE Id = :acc.Id];
    System.assertNotEquals(null, updated.Logo_File_URL__c, 'Logo_File_URL__c should be populated');
}

    @isTest
    static void testUploadImageUnconfiguredObject() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Boolean threw = false;
        Test.startTest();
            try {
                KenFileUploadController.uploadImage(acc.Id, 'Contact', 'logo.png', 'data:image/png;base64,AAAA');
            } catch (Exception e) {
                threw = true;
            }
        Test.stopTest();
        System.assertEquals(true, threw, 'Unconfigured object should raise an exception');
    }

    @isTest
    static void testUploadImageMissingInputs() {
        Boolean threw = false;
        Test.startTest();
            try {
                KenFileUploadController.uploadImage(null, null, 'logo.png', 'data:image/png;base64,AAAA');
            } catch (Exception e) {
                threw = true;
            }
        Test.stopTest();
        System.assertEquals(true, threw, 'Missing record Id / object name should raise an exception');
    }

}