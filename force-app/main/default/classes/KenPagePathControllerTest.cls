@IsTest
private class KenPagePathControllerTest {

    @IsTest
    static void testBlankServiceIdReturnsNull() {
        Test.startTest();
        String result1 = KenPagePathController.getServiceName(null);
        String result2 = KenPagePathController.getServiceName('');
        String result3 = KenPagePathController.getServiceName('   ');
        Test.stopTest();

        System.assertEquals(null, result1);
        System.assertEquals(null, result2);
        System.assertEquals(null, result3);
    }

    @IsTest
    static void testValidRecordReturnsName() {
        Account a = new Account(Name = 'Test Service Name');
        insert a;

        Test.startTest();
        String result = KenPagePathController.getServiceName((String)a.Id);
        Test.stopTest();

        System.assertEquals('Test Service Name', result);
    }

    @IsTest
    static void testInvalidIdStringHitsCatchAndReturnsNull() {
        Test.startTest();
        String result = KenPagePathController.getServiceName('not-an-id');
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void testValidButNonexistentIdReturnsNull() {
        // Create a record only to get a valid Id format/prefix (no hardcoding)
        Account a = new Account(Name = 'Temp For Id');
        insert a;

        // Build a new Id that is valid format but does NOT exist:
        // flip the last character to something different.
        String existingId = (String)a.Id; // 18-char in Apex string context typically
        String lastChar = existingId.right(1);
        String newLastChar = (lastChar == 'A') ? 'B' : 'A';
        String nonExistentId = existingId.left(existingId.length() - 1) + newLastChar;

        // Sanity: ensure it's not accidentally the same
        System.assertNotEquals(existingId, nonExistentId, 'Should differ from existing Id');

        Test.startTest();
        String result = KenPagePathController.getServiceName(nonExistentId);
        Test.stopTest();

        System.assertEquals(null, result, 'Query should return empty and method should return null');
    }
}