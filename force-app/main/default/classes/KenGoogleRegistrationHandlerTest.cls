@IsTest
private class KenGoogleRegistrationHandlerTest {

    @TestSetup
    static void setupData() {
        Id baseProfileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;

        User runAsUser = new User(
            FirstName = 'Google',
            LastName = 'Runner',
            Email = 'google.runner@example.com',
            Username = 'google.runner.' + DateTime.now().getTime() + '@example.com',
            Alias = 'ggsso',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = baseProfileId
        );
        insert runAsUser;
    }

    @IsTest
    static void createUserReturnsActiveAlumniWhenMatched() {
        User runAsUser = [SELECT Id FROM User WHERE Alias = 'ggsso' LIMIT 1];

        System.runAs(runAsUser) {
            KenGoogleRegistrationHandler handler = new KenGoogleRegistrationHandler();
            List<User> alumniUsers = [
                SELECT Id, Email
                FROM User
                WHERE Profile.Name = 'Alumni'
                AND IsActive = true
                LIMIT 1
            ];
            Auth.UserData googleUser = buildUserData(
                alumniUsers.isEmpty() ? 'alumni.active@example.com' : alumniUsers[0].Email
            );

            Test.startTest();
            if (!alumniUsers.isEmpty()) {
                User returnedUser = handler.createUser(null, googleUser);
                Test.stopTest();
                System.assertEquals(
                    alumniUsers[0].Id,
                    returnedUser.Id,
                    'Handler should return the existing active community user.'
                );
            } else {
                try {
                    handler.createUser(null, googleUser);
                    Test.stopTest();
                    System.assert(false, 'Expected SObjectException when no matching community user exists.');
                } catch (SObjectException ex) {
                    Test.stopTest();
                    System.assert(
                        ex.getMessage().contains('No active user found. Please register first.'),
                        'Exception should indicate that pre-registration is required.'
                    );
                }
            }
        }
    }

    @IsTest
    static void createUserThrowsWhenNoMatchingActiveUserExists() {
        User runAsUser = [SELECT Id FROM User WHERE Alias = 'ggsso' LIMIT 1];

        System.runAs(runAsUser) {
            KenGoogleRegistrationHandler handler = new KenGoogleRegistrationHandler();
            Auth.UserData googleUser = buildUserData('no.match.' + DateTime.now().getTime() + '@example.com');

            Test.startTest();
            try {
                handler.createUser(null, googleUser);
                Test.stopTest();
                System.assert(false, 'Expected SObjectException for unmatched active user lookup.');
            } catch (SObjectException ex) {
                Test.stopTest();
                System.assert(
                    ex.getMessage().contains('No active user found. Please register first.'),
                    'Exception should communicate registration guidance.'
                );
            }
        }
    }

    @IsTest
    static void updateUserRunsWithoutError() {
        User runAsUser = [SELECT Id, Email FROM User WHERE Alias = 'ggsso' LIMIT 1];

        System.runAs(runAsUser) {
            KenGoogleRegistrationHandler handler = new KenGoogleRegistrationHandler();

            Test.startTest();
            handler.updateUser(runAsUser.Id, null, buildUserData(runAsUser.Email));
            Test.stopTest();
        }

        Integer userCount = [SELECT Count() FROM User WHERE Id = :runAsUser.Id];
        System.assertEquals(1, userCount, 'User should remain available after updateUser execution.');
    }

    private static Auth.UserData buildUserData(String email) {
        return new Auth.UserData(
            'google-sub-123',
            'Goo',
            'Gle',
            'Goo Gle',
            email,
            'https://accounts.google.com/sample',
            'googlesample',
            'en_US',
            'Google',
            null,
            new Map<String, String>()
        );
    }
}