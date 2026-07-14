@IsTest
private class KenCustomExceptionTest {

    @TestSetup
    static void setupData() {
        Id profileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;
        User runAsUser = new User(
            FirstName = 'Custom',
            LastName = 'ExceptionUser',
            Email = 'custom.exception.user@example.com',
            Username = 'custom.exception.user.' + DateTime.now().getTime() + '@example.com',
            Alias = 'cexpt',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
        insert runAsUser;
    }

    @IsTest
    static void customExceptionCanBeThrownAndCaught() {
        User runAsUser = [SELECT Id FROM User WHERE Alias = 'cexpt' LIMIT 1];

        System.runAs(runAsUser) {
            Test.startTest();
            try {
                throw new KenCustomException('Custom test exception message');
            } catch (KenCustomException ex) {
                System.assertEquals(
                    'Custom test exception message',
                    ex.getMessage(),
                    'Custom exception message should remain intact when thrown and caught.'
                );
            }
            Test.stopTest();
        }
    }
}