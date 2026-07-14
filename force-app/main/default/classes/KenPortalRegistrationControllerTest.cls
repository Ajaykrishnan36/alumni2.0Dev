@isTest
private class KenPortalRegistrationControllerTest {

    private static KenPortalRegistrationController.RegistrationInput validInput() {
        KenPortalRegistrationController.RegistrationInput inp = new KenPortalRegistrationController.RegistrationInput();
        inp.firstName = 'Test';
        inp.lastName = 'Alumni';
        inp.email = 'reg.test.' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '@example.com';
        inp.countryCode = '+91';
        inp.phone = '9876543210';
        inp.universityRegNumber = 'REG-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        inp.graduationYear = '2020';
        inp.linkedinUrl = 'linkedin.com/in/test-alumni';
        return inp;
    }

    private static Boolean threw(KenPortalRegistrationController.RegistrationInput inp) {
        Boolean caught = false;
        try {
            KenPortalRegistrationController.registerAlumni(inp);
        } catch (Exception e) {
            caught = true;
        }
        return caught;
    }

    @isTest
    static void testSuccessfulRegistrationCreatesAccountAndCrm() {
        KenPortalRegistrationController.RegistrationInput inp = validInput();
        Test.startTest();
        String result = KenPortalRegistrationController.registerAlumni(inp);
        Test.stopTest();

        System.assertEquals('OK', result, 'Should return OK on the happy path');
        List<Account> accs = [
            SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone, Linkedin_Profile_URL__c
            FROM Account WHERE PersonEmail = :inp.email.toLowerCase()
        ];
        System.assertEquals(1, accs.size(), 'Person Account should be created');
        System.assertEquals('Test', accs[0].FirstName);
        System.assert(accs[0].Linkedin_Profile_URL__c.startsWith('https://'), 'LinkedIn URL should be normalised to https');

        List<Ken_Alumni_CRM__c> crm = [
            SELECT Id, Registration_Number__c, Year_of_Graduation__c, Approval_Status__c
            FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :accs[0].Id
        ];
        System.assertEquals(1, crm.size(), 'Alumni CRM record should be created');
        System.assertEquals('2020', crm[0].Year_of_Graduation__c);
        System.assertEquals('Pending', crm[0].Approval_Status__c);
    }

    @isTest
    static void testDuplicateEmailRejected() {
        KenPortalRegistrationController.RegistrationInput first = validInput();
        Test.startTest();
        KenPortalRegistrationController.registerAlumni(first); // creates the account + person contact
        KenPortalRegistrationController.RegistrationInput dup = validInput();
        dup.email = first.email; // same email
        Boolean caught = threw(dup);
        Test.stopTest();
        System.assert(caught, 'Duplicate email should be rejected');
    }

    @isTest
    static void testValidationFailures() {
        System.assert(threw(null), 'Null input should throw');

        KenPortalRegistrationController.RegistrationInput noFirst = validInput();
        noFirst.firstName = '';
        System.assert(threw(noFirst), 'Missing first name should throw');

        KenPortalRegistrationController.RegistrationInput noLast = validInput();
        noLast.lastName = '   ';
        System.assert(threw(noLast), 'Missing last name should throw');

        KenPortalRegistrationController.RegistrationInput badEmail = validInput();
        badEmail.email = 'not-an-email';
        System.assert(threw(badEmail), 'Invalid email should throw');

        KenPortalRegistrationController.RegistrationInput badPhone = validInput();
        badPhone.phone = 'abc123';
        System.assert(threw(badPhone), 'Non-numeric phone should throw');

        KenPortalRegistrationController.RegistrationInput noReg = validInput();
        noReg.universityRegNumber = '';
        System.assert(threw(noReg), 'Missing registration number should throw');

        KenPortalRegistrationController.RegistrationInput badYear = validInput();
        badYear.graduationYear = '20';
        System.assert(threw(badYear), 'Invalid graduation year should throw');

        KenPortalRegistrationController.RegistrationInput badLinkedIn = validInput();
        badLinkedIn.linkedinUrl = 'https://facebook.com/someone';
        System.assert(threw(badLinkedIn), 'Non-LinkedIn URL should throw');
    }

    @isTest
    static void testBlankLinkedInIsAllowed() {
        KenPortalRegistrationController.RegistrationInput inp = validInput();
        inp.linkedinUrl = '';
        Test.startTest();
        String result = KenPortalRegistrationController.registerAlumni(inp);
        Test.stopTest();
        System.assertEquals('OK', result, 'LinkedIn is optional');
    }
}