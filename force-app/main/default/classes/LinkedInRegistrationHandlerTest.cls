/**
 * @description Tests for LinkedInRegistrationHandler — the Auth.RegistrationHandler that links
 *              a LinkedIn SSO identity to an existing community user. Verifies that an
 *              unrecognized LinkedIn profile (no matching active community account) throws,
 *              which is what drives the login page's "redirect to registration" behavior.
 */
@IsTest
private class LinkedInRegistrationHandlerTest {
    private static Auth.UserData buildUserData(String email) {
        return new Auth.UserData(
            'linkedin-sub-' + email, // identifier (the LinkedIn `sub`)
            'Ada', // firstName
            'Lovelace', // lastName
            'Ada Lovelace', // fullName
            email, // email
            null, // link
            email, // username
            'en-US', // locale
            'LinkedInNew', // provider
            null, // siteLoginUrl
            new Map<String, String>() // attributeMap
        );
    }

    @IsTest
    static void createUserThrowsWhenNoMatchingAccount() {
        LinkedInRegistrationHandler handler = new LinkedInRegistrationHandler();
        Auth.UserData data = buildUserData('no.match.' + System.currentTimeMillis() + '@example.com');

        Boolean threw = false;
        Test.startTest();
        try {
            handler.createUser(null, data);
        } catch (Exception e) {
            threw = true;
            System.assertEquals(
                true,
                e.getMessage().toLowerCase().contains('register'),
                'Error should direct the user to register: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'createUser must throw when no matching community account exists for the LinkedIn email.');
    }

    @IsTest
    static void updateUserCompletesForExistingUser() {
        LinkedInRegistrationHandler handler = new LinkedInRegistrationHandler();

        Test.startTest();
        handler.updateUser(UserInfo.getUserId(), null, buildUserData('whoever@example.com'));
        Test.stopTest();

        System.assert(true, 'updateUser should complete without error for a valid user id.');
    }
}