@IsTest
private class KenPersonEducationTriggerHandlerTest {

    private static Id kenCampusId;

    /**
     * KJS orgs add a required Campus__c lookup (-> Location) on LearningProgram.
     * Populate it only where the field exists so the tests still run in every
     * other org, and reuse one Location so a helper called in a loop does not
     * spend a DML statement per programme.
     */
    private static void kenAssignCampus(SObject record) {
        if (!record.getSObjectType().getDescribe().fields.getMap().containsKey('campus__c')) {
            return;
        }
        if (kenCampusId == null) {
            Schema.Location campus = new Schema.Location(Name = 'Ken Test Campus');
            for (Schema.PicklistEntry entry : Schema.Location.LocationType.getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    campus.LocationType = entry.getValue();
                    break;
                }
            }
            insert campus;
            kenCampusId = campus.Id;
        }
        record.put('Campus__c', kenCampusId);
    }

    /**
     * A person-account RecordType the RUNNING USER can actually use. Querying
     * RecordType.IsPersonType alone returns types the user has no access to,
     * which fails with INVALID_CROSS_REFERENCE_KEY, so intersect that with the
     * describe's isAvailable() infos. Schema.RecordTypeInfo has no
     * isPersonType(), hence the two-source intersection by Id.
     */
    private static Id personAccountRecordTypeId() {
        Set<Id> personTypeIds = new Set<Id>();
        for (RecordType rt : [
            SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true AND IsActive = true
        ]) {
            personTypeIds.add(rt.Id);
        }
        for (Schema.RecordTypeInfo info : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (info.isAvailable() && !info.isMaster() && personTypeIds.contains(info.getRecordTypeId())) {
                return info.getRecordTypeId();
            }
        }
        return null;
    }

    private static Account createPersonAccount() {
        Id paRtId = personAccountRecordTypeId();
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
        kenAssignCampus(lp);
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
        Lead ld = new Lead(
            RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Alumni Lead').getRecordTypeId(),
            FirstName = pa.FirstName,
            LastName = pa.LastName,
            Company = 'Alumni',
            Email = pa.PersonEmail,
            Status = 'new',
            Existing_Account__c = pa.Id,
            Constituent_Role_Type__c = 'Secondary',
            Institution_Name__c = 'Ken Institute',
            Program_Plan__c = planId,
            Registration_Number__c = 'REG-DUP'
        );
        insert ld;

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

    @IsTest
    static void test_ownInstitute_alreadyHeldProgramme_createsNoLead() {
        Account pa = createPersonAccount();
        Id planId = createProgramPlan('HeldProg');
        insert new ConstituentRole(
            PersonId = pa.Id, RoleType = 'Alumni', Status = 'Active',
            Registration_Status__c = 'Onboarding In Progress', Program_Plan__c = planId
        );

        Test.startTest();
        insert new PersonEducation(
            AccountId = pa.Id, Name = 'B.Tech', Degree_Name__c = 'B.Tech',
            Institute_Name__c = 'Ken Institute', Institution_Type__c = 'Our Institute',
            Year_of_Completion__c = '2015', Program_Plan__c = planId
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Lead WHERE Existing_Account__c = :pa.Id],
            'The onboarding seed describes a programme the alumnus already holds, so no new-role lead should be raised');
        System.assertEquals(1, [SELECT COUNT() FROM ConstituentRole WHERE PersonId = :pa.Id AND RoleType = 'Alumni'],
            'The existing role must remain the only one');
    }

    @IsTest
    static void test_ownInstitute_differentProgramme_stillCreatesLead() {
        Account pa = createPersonAccount();
        Id heldPlanId = createProgramPlan('HeldOther');
        Id newPlanId = createProgramPlan('BrandNew');
        insert new ConstituentRole(
            PersonId = pa.Id, RoleType = 'Alumni', Status = 'Active',
            Registration_Status__c = 'Registered', Program_Plan__c = heldPlanId
        );

        Test.startTest();
        insert new PersonEducation(
            AccountId = pa.Id, Name = 'MTech', Degree_Name__c = 'MTech',
            Institute_Name__c = 'Ken Institute', Institution_Type__c = 'Our Institute',
            Year_of_Completion__c = '2020', Program_Plan__c = newPlanId
        );
        Test.stopTest();

        List<Lead> leads = [SELECT Program_Plan__c FROM Lead WHERE Existing_Account__c = :pa.Id];
        System.assertEquals(1, leads.size(), 'A genuinely new programme must still raise a new-role lead');
        System.assertEquals(newPlanId, leads[0].Program_Plan__c, 'The lead should carry the new programme');
    }
}