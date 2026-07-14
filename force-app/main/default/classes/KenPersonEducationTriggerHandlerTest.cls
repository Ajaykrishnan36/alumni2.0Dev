@IsTest
private class KenPersonEducationTriggerHandlerTest {

    private static Account createPersonAccount() {
        Id paRtId;
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account']) {
            if (rt.IsPersonType) {
                paRtId = rt.Id;
                break;
            }
        }
        Account pa = new Account();
        if (paRtId != null) pa.RecordTypeId = paRtId;
        pa.FirstName = 'Edu';
        pa.LastName = 'Test';
        pa.PersonEmail = 'edu+' + String.valueOf(Crypto.getRandomInteger()) + '@example.com';
        insert pa;
        return pa;
    }

    private static Id createProgramPlan(String name) {
        Learning lrn = new Learning(Name = name + ' Learning');
        insert lrn;
        LearningProgram lp = new LearningProgram(Name = name + ' Program', LearningId = lrn.Id);
        insert lp;
        LearningProgramPlan lpp = new LearningProgramPlan(Name = name, LearningProgramId = lp.Id);
        insert lpp;
        return lpp.Id;
    }

    @IsTest
    static void test_ownInstitute_createsSecondaryLead() {
        Account pa = createPersonAccount();
        Id planId = createProgramPlan('BTech2015');

        Test.startTest();
        insert new PersonEducation(
            AccountId = pa.Id,
            Name = 'B.Tech',
            Degree_Name__c = 'B.Tech',
            Institute_Name__c = 'Ken Institute',
            Institution_Type__c = 'Our Institute',
            Year_of_Completion__c = '2015',
            Program_Plan__c = planId,
            Registration_Number__c = 'REG-12345'
        );
        Test.stopTest();

        List<Lead> leads = [
            SELECT Id, Existing_Account__c, Constituent_Role_Type__c, Email, Institution_Name__c,
                   Year_of_Graduation__c, Program_Plan__c, Registration_Number__c
            FROM Lead
            WHERE Existing_Account__c = :pa.Id
        ];
        System.assertEquals(1, leads.size(), 'An own-institute education should create one Lead');
        System.assertEquals('Secondary', leads[0].Constituent_Role_Type__c, 'Lead should be tagged Secondary');
        System.assertEquals(pa.PersonEmail, leads[0].Email, 'Lead email should match the alumnus');
        System.assertEquals('Ken Institute', leads[0].Institution_Name__c, 'Institute should carry over');
        System.assertEquals(planId, leads[0].Program_Plan__c, 'Program plan should carry to the Lead');
        System.assertEquals('REG-12345', leads[0].Registration_Number__c, 'Registration number should carry to the Lead');

        System.assertEquals(0, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :pa.Id],
            'No role should exist until the lead is verified');
    }

    @IsTest
    static void test_otherInstitute_createsNoLead() {
        Account pa = createPersonAccount();

        Test.startTest();
        insert new PersonEducation(
            AccountId = pa.Id,
            Name = 'MBA',
            Degree_Name__c = 'MBA',
            Institute_Name__c = 'External University',
            Institution_Type__c = 'Other'
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Existing_Account__c = :pa.Id],
            'External institute should not create a lead');
    }

    @IsTest
    static void test_untaggedEducation_createsNoLead() {
        Account pa = createPersonAccount();

        Test.startTest();
        insert new PersonEducation(
            AccountId = pa.Id,
            Name = 'Diploma',
            Degree_Name__c = 'Diploma',
            Institute_Name__c = 'Imported College'
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Existing_Account__c = :pa.Id],
            'Untagged (system) education should not create a lead');
    }

    @IsTest
    static void test_leadVerification_createsRoleOnExistingAccount() {
        Account pa = createPersonAccount();
        insert new PersonEducation(
            AccountId = pa.Id,
            Name = 'B.Tech',
            Degree_Name__c = 'B.Tech',
            Institute_Name__c = 'Ken Institute',
            Institution_Type__c = 'Our Institute',
            Year_of_Completion__c = '2015'
        );
        Lead ld = [SELECT Id, Status FROM Lead WHERE Existing_Account__c = :pa.Id LIMIT 1];

        Test.startTest();
        ld.Status = 'Verified';
        update ld;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE PersonEmail = :pa.PersonEmail],
            'No duplicate account should be created for the existing alumnus');
        System.assert([SELECT COUNT() FROM ConstituentRole WHERE PersonId = :pa.Id AND RoleType = 'Alumni'] >= 1,
            'A ConstituentRole should be created on the existing account');
    }

    @IsTest
    static void test_leadVerification_createsNewRoleEvenWhenProgramMatches() {
        Account pa = createPersonAccount();
        Id planId = createProgramPlan('DupProg');
        insert new ConstituentRole(
            PersonId = pa.Id, RoleType = 'Alumni', Status = 'Active',
            Registration_Status__c = 'Registered', Program_Plan__c = planId, Registration_Number__c = 'REG-DUP'
        );
        insert new PersonEducation(
            AccountId = pa.Id, Name = 'B.Tech', Degree_Name__c = 'B.Tech',
            Institute_Name__c = 'Ken Institute', Institution_Type__c = 'Our Institute',
            Program_Plan__c = planId, Registration_Number__c = 'REG-DUP'
        );
        Lead ld = [SELECT Id FROM Lead WHERE Existing_Account__c = :pa.Id LIMIT 1];

        Test.startTest();
        ld.Status = 'Verified';
        update ld;
        Test.stopTest();

        List<ConstituentRole> roles = [
            SELECT Registration_Status__c FROM ConstituentRole WHERE PersonId = :pa.Id AND RoleType = 'Alumni'
        ];
        System.assertEquals(2, roles.size(), 'A new role should be created even when program+reg match the existing role');
        for (ConstituentRole cr : roles) {
            System.assertEquals('Registered', cr.Registration_Status__c,
                'The new secondary role should mirror the primary role status (Registered)');
        }
    }
}