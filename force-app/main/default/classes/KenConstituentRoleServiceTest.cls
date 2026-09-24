@IsTest
private class KenConstituentRoleServiceTest {

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'PersonAccount' LIMIT 1
        ];
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account' AND IsActive = true]) {
            if (rt.IsPersonType) {
                return rt.Id;
            }
        }
        return null;
    }

    private static Account createPersonAccount(String lastName) {
        Account acc = new Account(
            FirstName = 'Role',
            LastName = lastName,
            PersonEmail = lastName.toLowerCase() + '@test.example.com'
        );
        Id rtId = getPersonAccountRtId();
        if (rtId != null) {
            acc.RecordTypeId = rtId;
        }
        insert acc;
        return acc;
    }

    private static ConstituentRole createAlumniRole(Id personAccountId) {
        ConstituentRole role = new ConstituentRole(
            PersonId = personAccountId,
            RoleType = 'Alumni',
            Status = 'Active'
        );
        insert role;
        return role;
    }

    @IsTest
    static void updateLastLoginStampsOwnRole() {
        Account acc = createPersonAccount('Stamper');
        ConstituentRole role = createAlumniRole(acc.Id);
        KenConstituentRoleService.testCurrentAccountId = acc.Id;

        Test.startTest();
        KenConstituentRoleService.updateLastLogin(role.Id);
        Test.stopTest();

        ConstituentRole after = [SELECT Last_Login__c FROM ConstituentRole WHERE Id = :role.Id];
        System.assertNotEquals(null, after.Last_Login__c, 'Last_Login__c should be stamped on the selected role');
    }

    @IsTest
    static void updateLastLoginIgnoresForeignRole() {
        Account mine = createPersonAccount('Mine');
        Account theirs = createPersonAccount('Theirs');
        ConstituentRole theirRole = createAlumniRole(theirs.Id);
        KenConstituentRoleService.testCurrentAccountId = mine.Id;

        Test.startTest();
        KenConstituentRoleService.updateLastLogin(theirRole.Id);
        Test.stopTest();

        ConstituentRole after = [SELECT Last_Login__c FROM ConstituentRole WHERE Id = :theirRole.Id];
        System.assertEquals(null, after.Last_Login__c, 'A role belonging to another account must not be stamped');
    }

    @IsTest
    static void updateLastLoginNoOpWithoutRoleOrAccount() {
        Account acc = createPersonAccount('NoOp');
        ConstituentRole role = createAlumniRole(acc.Id);

        Test.startTest();
        KenConstituentRoleService.updateLastLogin(null);
        KenConstituentRoleService.updateLastLogin(role.Id);
        Test.stopTest();

        ConstituentRole after = [SELECT Last_Login__c FROM ConstituentRole WHERE Id = :role.Id];
        System.assertEquals(null, after.Last_Login__c, 'No stamp expected when the running user has no Person Account');
    }

    @IsTest
    static void getActiveRolePrefersLatestLogin() {
        Account acc = createPersonAccount('Latest');
        ConstituentRole older = createAlumniRole(acc.Id);
        ConstituentRole newer = createAlumniRole(acc.Id);
        older.Last_Login__c = System.now();
        newer.Last_Login__c = System.now().addDays(-3);
        update new List<ConstituentRole>{ older, newer };
        KenConstituentRoleService.testCurrentAccountId = acc.Id;

        Test.startTest();
        Id resolved = KenConstituentRoleService.getActiveConstituentRoleId();
        Test.stopTest();

        System.assertEquals(older.Id, resolved, 'The role with the most recent Last_Login__c should win');
    }

    @IsTest
    static void getActiveRoleFallsBackToNewestCreated() {
        Account acc = createPersonAccount('Fallback');
        ConstituentRole first = createAlumniRole(acc.Id);
        ConstituentRole second = createAlumniRole(acc.Id);
        Test.setCreatedDate(first.Id, System.now().addDays(-1));
        KenConstituentRoleService.testCurrentAccountId = acc.Id;

        Test.startTest();
        Id resolved = KenConstituentRoleService.getActiveConstituentRoleId();
        Test.stopTest();

        System.assertEquals(second.Id, resolved, 'Without any Last_Login__c the newest role should win');
    }

    @IsTest
    static void getActiveRoleNullWithoutAccount() {
        Test.startTest();
        Id resolved = KenConstituentRoleService.getActiveConstituentRoleId();
        Test.stopTest();

        System.assertEquals(null, resolved, 'Internal users without a Person Account resolve to null');
    }

    @IsTest
    static void roleSeamShortCircuits() {
        Account acc = createPersonAccount('Seam');
        ConstituentRole role = createAlumniRole(acc.Id);
        KenConstituentRoleService.testCurrentRoleId = role.Id;

        Test.startTest();
        Id resolved = KenConstituentRoleService.getActiveConstituentRoleId();
        Test.stopTest();

        System.assertEquals(role.Id, resolved, 'testCurrentRoleId seam should be returned directly');
    }

    @IsTest
    static void ensureSessionLastLoginStampsResolvedRole() {
        Account acc = createPersonAccount('Ensure');
        ConstituentRole role = new ConstituentRole(
            PersonId = acc.Id,
            RoleType = 'Alumni',
            Status = 'Active',
            Registration_Status__c = 'Initial Login Done'
        );
        insert role;
        KenConstituentRoleService.testCurrentAccountId = acc.Id;

        Test.startTest();
        String status = KenConstituentRoleService.ensureSessionLastLogin();
        Test.stopTest();

        ConstituentRole after = [SELECT Last_Login__c FROM ConstituentRole WHERE Id = :role.Id];
        System.assertNotEquals(null, after.Last_Login__c, 'Session catch-all should stamp the resolved active role');
        System.assertEquals('Initial Login Done', status, 'The stamped role registration status should be returned');
    }

    @IsTest
    static void ensureSessionLastLoginNoOpWithoutRole() {
        Account acc = createPersonAccount('EnsureNoOp');
        ConstituentRole role = createAlumniRole(acc.Id);

        Test.startTest();
        String status = KenConstituentRoleService.ensureSessionLastLogin();
        Test.stopTest();

        ConstituentRole after = [SELECT Last_Login__c FROM ConstituentRole WHERE Id = :role.Id];
        System.assertEquals(null, after.Last_Login__c, 'No stamp expected when the running user has no Person Account');
        System.assertEquals(null, status, 'No status expected when the running user has no Person Account');
    }

    @IsTest
    static void getCurrentUserAccountIdSeam() {
        Account acc = createPersonAccount('AccSeam');
        KenConstituentRoleService.testCurrentAccountId = acc.Id;

        System.assertEquals(acc.Id, KenConstituentRoleService.getCurrentUserAccountId(), 'Account seam should be honored');
    }
}