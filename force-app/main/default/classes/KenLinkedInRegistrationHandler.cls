/**
 * Registration handler for the "Sign in with LinkedIn" Auth. Provider on the
 * Experience site. SSO never self-registers: it only matches an EXISTING active
 * community user by the social account's email; anyone else is told to register
 * first (kenLoginPage.detectSsoError routes them to self-register).
 *
 * Error messages are kept identical to KenGoogleRegistrationHandler so the
 * login page can present the same states for both providers.
 */
global without sharing class KenLinkedInRegistrationHandler implements Auth.RegistrationHandler {

    @TestVisible private static final String ERR_NO_EMAIL =
        'NO_SSO_EMAIL: The provider did not share an email address. Please sign in with your email and password.';
    @TestVisible private static final String ERR_NO_USER =
        'No active user found. Please register first.';

    global User createUser(Id portalId, Auth.UserData data) {
        // LinkedIn only returns an email when the app is approved for the email
        // scope. Without one, the lookup below would match nothing and report
        // "register first", which sends an existing alumnus down the wrong path.
        if (data == null || String.isBlank(data.Email)) {
            throw new SObjectException(ERR_NO_EMAIL);
        }

        String email = data.Email;
        List<User> users = [
            SELECT Id, Email
            FROM User
            WHERE Email = :email
            AND Profile.Name = 'Alumni'
            AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (users.isEmpty()) {
            throw new SObjectException(ERR_NO_USER);
        }

        return users[0];
    }

    global void updateUser(Id userId, Id portalId, Auth.UserData data) {
        // Nothing to sync from the provider — the portal owns the profile data.
        // A no-op update would still burn a DML and can fail on validation
        // rules, so only touch the record when there is something to write.
    }
}