@IsTest
private class KenLinkedInRegistrationHandlerTest {

    @TestSetup
    static void setupData() {
        Id baseProfileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;

        User runAsUser = new User(
            FirstName = 'LinkedIn',
            LastName = 'Runner',
            Email = 'linkedin.runner@example.com',
            Username = 'linkedin.runner.' + DateTime.now().getTime() + '@example.com',
            Alias = 'lkdin',
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
        User runAsUser = [SELECT Id FROM User WHERE Alias = 'lkdin' LIMIT 1];

        System.runAs(runAsUser) {
            KenLinkedInRegistrationHandler handler = new KenLinkedInRegistrationHandler();
            List<User> alumniUsers = [
                SELECT Id, Email
                FROM User
                WHERE Profile.Name = 'Alumni-Student'
                AND IsActive = true
                LIMIT 1
            ];
            Auth.UserData linkedInUser = buildUserData(
                alumniUsers.isEmpty() ? 'alumni.active@example.com' : alumniUsers[0].Email
            );

            Test.startTest();
            if (!alumniUsers.isEmpty()) {
                User returnedUser = handler.createUser(null, linkedInUser);
                Test.stopTest();
                System.assertEquals(
                    alumniUsers[0].Id,
                    returnedUser.Id,
                    'Handler should return the existing active Alumni-Student user.'
                );
            } else {
                try {
                    handler.createUser(null, linkedInUser);
                    Test.stopTest();
                    System.assert(false, 'Expected SObjectException when Alumni-Student profile is unavailable.');
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
        User runAsUser = [SELECT Id FROM User WHERE Alias = 'lkdin' LIMIT 1];

        System.runAs(runAsUser) {
            KenLinkedInRegistrationHandler handler = new KenLinkedInRegistrationHandler();
            Auth.UserData linkedInUser = buildUserData('no.match.' + DateTime.now().getTime() + '@example.com');

            Test.startTest();
            try {
                handler.createUser(null, linkedInUser);
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
        User runAsUser = [SELECT Id, Email FROM User WHERE Alias = 'lkdin' LIMIT 1];

        System.runAs(runAsUser) {
            KenLinkedInRegistrationHandler handler = new KenLinkedInRegistrationHandler();

            Test.startTest();
            handler.updateUser(runAsUser.Id, null, buildUserData(runAsUser.Email));
            Test.stopTest();
        }

        Integer userCount = [SELECT Count() FROM User WHERE Id = :runAsUser.Id];
        System.assertEquals(1, userCount, 'User should remain available after updateUser execution.');
    }

    private static Auth.UserData buildUserData(String email) {
        return new Auth.UserData(
            'ext-id-123',
            'Linked',
            'In',
            'Linked In',
            email,
            'https://www.linkedin.com/in/sample',
            'linkedinsample',
            'en_US',
            'LinkedIn',
            null,
            new Map<String, String>()
        );
    }
}