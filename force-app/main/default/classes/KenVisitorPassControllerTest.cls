/**
 * KenVisitorPassControllerTest
 *
 * Covers KenVisitorPassController:
 *   - searchVisitorByEmail: blank email, existing contact under student account,
 *     existing contact via broad search, no contact found.
 *   - saveVisitorContact: missing required fields, existing contact (returns Id),
 *     new contact created successfully.
 */
@IsTest
private class KenVisitorPassControllerTest {

    // ── helpers ──────────────────────────────────────────────────────────────

    private static Contact insertContact(String firstName, String lastName, String email) {
        Contact c = new Contact(
            FirstName = firstName,
            LastName  = lastName,
            Email     = email
        );
        insert c;
        return c;
    }

    // ── searchVisitorByEmail ─────────────────────────────────────────────────

    @IsTest
    static void searchVisitorByEmail_blankEmail_returnsNull() {
        Test.startTest();
        KenVisitorPassController.VisitorContactInfo result =
            KenVisitorPassController.searchVisitorByEmail('');
        Test.stopTest();

        System.assertEquals(null, result, 'Blank email must return null');
    }

    @IsTest
    static void searchVisitorByEmail_nullEmail_returnsNull() {
        Test.startTest();
        KenVisitorPassController.VisitorContactInfo result =
            KenVisitorPassController.searchVisitorByEmail(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Null email must return null');
    }

    @IsTest
    static void searchVisitorByEmail_noMatchingContact_returnsNull() {
        Test.startTest();
        KenVisitorPassController.VisitorContactInfo result =
            KenVisitorPassController.searchVisitorByEmail('nobody@nowhere.invalid');
        Test.stopTest();

        System.assertEquals(null, result, 'Non-existing email should return null');
    }

    @IsTest
    static void searchVisitorByEmail_existingContact_returnsInfo() {
        Contact c = insertContact('Jane', 'Doe', 'jane.doe.visitortest@test.example.com');

        Test.startTest();
        KenVisitorPassController.VisitorContactInfo result =
            KenVisitorPassController.searchVisitorByEmail('jane.doe.visitortest@test.example.com');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return contact info for existing email');
        System.assertEquals(c.Id, result.contactId);
        System.assertEquals('Jane', result.firstName);
        System.assertEquals('Doe', result.lastName);
        System.assertEquals('jane.doe.visitortest@test.example.com', result.email);
        System.assertEquals(true, result.found);
    }

    @IsTest
    static void searchVisitorByEmail_emailWithWhitespace_trimsAndFinds() {
        insertContact('Bob', 'Smith', 'bob.smith.visitortest@test.example.com');

        Test.startTest();
        KenVisitorPassController.VisitorContactInfo result =
            KenVisitorPassController.searchVisitorByEmail('  bob.smith.visitortest@test.example.com  ');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Whitespace-padded email should be trimmed and matched');
        System.assertEquals(true, result.found);
    }

    @IsTest
    static void searchVisitorByEmail_contactWithMobilePhone_usesMobile() {
        Contact c = new Contact(
            FirstName   = 'Alice',
            LastName    = 'Mobile',
            Email       = 'alice.mobile.visitortest@test.example.com',
            Phone       = '111-000-0000',
            MobilePhone = '999-888-7777'
        );
        insert c;

        Test.startTest();
        KenVisitorPassController.VisitorContactInfo result =
            KenVisitorPassController.searchVisitorByEmail('alice.mobile.visitortest@test.example.com');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('999-888-7777', result.phone,
            'MobilePhone should take priority over Phone');
    }

    @IsTest
    static void searchVisitorByEmail_contactWithOnlyPhone_usesPhone() {
        Contact c = new Contact(
            FirstName = 'Charlie',
            LastName  = 'PhoneOnly',
            Email     = 'charlie.phoneonly.visitortest@test.example.com',
            Phone     = '555-123-4567'
        );
        insert c;

        Test.startTest();
        KenVisitorPassController.VisitorContactInfo result =
            KenVisitorPassController.searchVisitorByEmail('charlie.phoneonly.visitortest@test.example.com');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('555-123-4567', result.phone,
            'Phone should be used when MobilePhone is blank');
    }

    // ── saveVisitorContact ───────────────────────────────────────────────────

    @IsTest
    static void saveVisitorContact_missingFirstName_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenVisitorPassController.saveVisitorContact(
                '', 'Doe', 'visitor@test.example.com', null, null
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Missing first name should throw AuraHandledException');
    }

    @IsTest
    static void saveVisitorContact_missingLastName_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenVisitorPassController.saveVisitorContact(
                'Jane', '', 'visitor2@test.example.com', null, null
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Missing last name should throw AuraHandledException');
    }

    @IsTest
    static void saveVisitorContact_missingEmail_throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenVisitorPassController.saveVisitorContact(
                'Jane', 'Doe', '', null, null
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Missing email should throw AuraHandledException');
    }

    @IsTest
    static void saveVisitorContact_existingContact_returnsExistingId() {
        Contact existing = insertContact('Existing', 'Visitor', 'existing.visitor.test@test.example.com');

        Test.startTest();
        String returnedId = KenVisitorPassController.saveVisitorContact(
            'Different', 'Name', 'existing.visitor.test@test.example.com', null, null
        );
        Test.stopTest();

        System.assertEquals(existing.Id, returnedId,
            'Should return existing contact Id without creating a duplicate');
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Email = 'existing.visitor.test@test.example.com'],
            'Should not create a second contact');
    }

    @IsTest
    static void saveVisitorContact_newContact_createsAndReturnsId() {
        String email = 'brand.new.visitor.test@test.example.com';

        Test.startTest();
        String returnedId = KenVisitorPassController.saveVisitorContact(
            'Brand', 'New', email, '555-000-1234', null
        );
        Test.stopTest();

        System.assertNotEquals(null, returnedId, 'Should return the new contact Id');
        List<Contact> contacts = [SELECT Id, FirstName, LastName, Email FROM Contact WHERE Email = :email];
        System.assertEquals(1, contacts.size(), 'Exactly one contact should be created');
        System.assertEquals('Brand', contacts[0].FirstName);
        System.assertEquals('New', contacts[0].LastName);
    }

    @IsTest
    static void saveVisitorContact_newContact_withWhitespaceEmail_createsContact() {
        String email = 'whitespace.visitor.test@test.example.com';

        Test.startTest();
        String returnedId = KenVisitorPassController.saveVisitorContact(
            ' Padded ', ' Name ', '  ' + email + '  ', null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, returnedId, 'Should return new contact Id');
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Email = :email]);
    }
}