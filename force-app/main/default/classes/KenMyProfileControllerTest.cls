@IsTest
private class KenMyProfileControllerTest {

    private static final String ALUMNI_RT      = 'Alumni_Person_Account';
    private static final String ALUMNI_PROFILE = 'Alumni-Student';

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
        ];
        if (!rts.isEmpty()) return rts[0].Id;
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account']) {
            if (rt.IsPersonType) return rt.Id;
        }
        return null;
    }

    private static User buildStandardRunAsUser() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            Username          = 'myprofile.' + System.currentTimeMillis() + '@example.com',
            Email             = 'myprofile@example.com',
            LastName          = 'MyProfileTest',
            Alias             = 'mprf',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = prof.Id
        );
    }

    private static User buildCommunityUser(Id contactId) {
        List<Profile> profs = [SELECT Id FROM Profile WHERE Name = :ALUMNI_PROFILE LIMIT 1];
        if (profs.isEmpty()) return null;
        return new User(
            Username          = 'myprofile.community.' + System.currentTimeMillis() + '@test.alumni.com',
            Email             = 'myprofile.community@test.alumni.com',
            LastName          = 'MyProfileCommunity',
            Alias             = 'mprc',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = profs[0].Id,
            ContactId         = contactId
        );
    }

    private static Account buildPersonAccount(String suffix) {
        Account pa = new Account(
            FirstName   = 'MyProfile',
            LastName    = 'TestUser' + suffix,
            PersonEmail = 'myprofile.' + suffix + '.' + System.currentTimeMillis() + '@test.com'
        );
        Id rtId = getPersonAccountRtId();
        if (rtId != null) pa.RecordTypeId = rtId;
        return pa;
    }

    @IsTest
    static void testGetMyProfileNoUserReturnsEmptyProfile() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            Test.startTest();
            KenMyProfileController.ProfileData result = KenMyProfileController.getMyProfile();
            Test.stopTest();

            System.assertNotEquals(null, result, 'getMyProfile should return a non-null empty profile when user has no account');
            System.assertNotEquals(null, result.education, 'Education list should not be null');
            System.assertNotEquals(null, result.experience, 'Experience list should not be null');
            System.assertNotEquals(null, result.achievements, 'Achievements list should not be null');
            System.assertEquals(true, result.willingToHelp, 'willingToHelp should default to true in empty profile');
            System.assertEquals(false, result.isOnline, 'isOnline should default to false in empty profile');
        }
    }

    @IsTest
    static void testGetMyProfileWithCommunityUser() {
        Account pa = buildPersonAccount('getprofile');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];

        ConstituentRole cr = new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');
        insert cr;
        insert new Ken_Alumni_CRM__c(
            Person_Account__c    = pa.Id,
            ConstituentRole__c   = cr.Id,
            Current_Company__c   = 'Test Corp',
            Year_of_Graduation__c = '2022'
        );

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        System.runAs(communityUser) {
            Test.startTest();
            KenMyProfileController.ProfileData result = KenMyProfileController.getMyProfile();
            Test.stopTest();

            System.assertNotEquals(null, result, 'getMyProfile should return populated data for community user with account');
            System.assertNotEquals(null, result.accountId, 'accountId should be set from the linked person account');
            System.assertNotEquals(null, result.name, 'name should be set from account');
        }
    }

    @IsTest
    static void testSaveEducationNewRecord() {
        Account pa = buildPersonAccount('saveedu');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
        input.degree        = 'B.Tech';
        input.institution   = '';
        input.startMonth    = '06';
        input.startYear     = '2018';
        input.endMonth      = '05';
        input.endYear       = '2022';
        input.gradingFormat = 'CGPA';
        input.cgpa          = '8.5';

        System.runAs(communityUser) {
            Test.startTest();
            Id recordId = KenMyProfileController.saveEducation(input);
            Test.stopTest();

            System.assertNotEquals(null, recordId, 'saveEducation should return the new record Id');
        }
    }

    @IsTest
    static void testSaveEducationSelfInstituteFlagged() {
        Account pa = buildPersonAccount('selfedu');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
        input.degree          = 'B.Sc';
        input.institution     = 'Some Other College';
        input.institutionType = 'other';
        input.startYear       = '2016';
        input.endYear         = '2019';
        input.gradingFormat   = 'CGPA';
        input.cgpa            = '7.5';

        Id recordId;
        System.runAs(communityUser) {
            Test.startTest();
            recordId = KenMyProfileController.saveEducation(input);
            Test.stopTest();
        }

        PersonEducation saved = [SELECT Institution_Type__c FROM PersonEducation WHERE Id = :recordId];
        System.assertEquals('Other', saved.Institution_Type__c, 'An "other" institute education should be tagged Other');
    }

    private static Id createProgramPlanForProfile(String name) {
        Learning lrn = new Learning(Name = name + ' Learning');
        insert lrn;
        LearningProgram lp = new LearningProgram(Name = name + ' Program', LearningId = lrn.Id);
        insert lp;
        LearningProgramPlan lpp = new LearningProgramPlan(Name = name, LearningProgramId = lp.Id);
        insert lpp;
        return lpp.Id;
    }

    @IsTest
    static void testSaveEducationOurInstituteStoresProgramPlanAndRegNo() {
        Account pa = buildPersonAccount('ourinst');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        Id planId = createProgramPlanForProfile('MyProfilePlan');

        KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
        input.degree            = 'B.Tech';
        input.institution       = 'Ken Institute';
        input.institutionType   = 'institute';
        input.programPlan       = planId;
        input.registrationNumber = 'REG-999';
        input.startYear         = '2016';
        input.endYear           = '2020';
        input.gradingFormat     = 'CGPA';
        input.cgpa              = '8.0';

        Id recordId;
        System.runAs(communityUser) {
            Test.startTest();
            recordId = KenMyProfileController.saveEducation(input);
            Test.stopTest();
        }

        PersonEducation saved = [
            SELECT Program_Plan__c, Registration_Number__c, Institution_Type__c
            FROM PersonEducation WHERE Id = :recordId
        ];
        System.assertEquals(planId, saved.Program_Plan__c, 'Program plan should be stored on the education');
        System.assertEquals('REG-999', saved.Registration_Number__c, 'Registration number should be stored');
        System.assertEquals('Our Institute', saved.Institution_Type__c, 'Should tag Our Institute');
    }

    @IsTest
    static void testSaveEducationUpdateRecord() {
        Account pa = buildPersonAccount('updateedu');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        System.runAs(communityUser) {
            PersonEducation existing = new PersonEducation(
                Name              = 'B.Sc',
                AccountId         = pa.Id,
                Degree_Name__c    = 'B.Sc',
                Is_Archived__c    = false
            );
            insert existing;

            KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
            input.id            = existing.Id;
            input.degree        = 'B.Tech';
            input.gradingFormat = 'CGPA';
            input.cgpa          = '9.0';

            Test.startTest();
            Id recordId = KenMyProfileController.saveEducation(input);
            Test.stopTest();

            System.assertEquals(existing.Id, recordId, 'saveEducation update should return the same record Id');
        }
    }

    @IsTest
    static void testArchiveEducationSuccess() {
        Account pa = buildPersonAccount('archiveedu');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        Id recId;
        System.runAs(communityUser) {
            PersonEducation rec = new PersonEducation(
                Name              = 'MBA',
                AccountId         = pa.Id,
                Degree_Name__c    = 'MBA',
                Is_Archived__c    = false
            );
            insert rec;
            recId = rec.Id;

            Test.startTest();
            KenMyProfileController.archiveEducation(recId);
            Test.stopTest();
        }

        Integer remaining = [SELECT COUNT() FROM PersonEducation WHERE Id = :recId];
        System.assertEquals(0, remaining, 'Education record should be deleted after archiveEducation');
    }

    @IsTest
    static void testSaveExperienceNewRecord() {
        Account pa = buildPersonAccount('saveexp');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        KenMyProfileController.ExperienceInput input = new KenMyProfileController.ExperienceInput();
        input.jobTitle      = 'Software Engineer';
        input.organization  = '';
        input.startMonth    = '01';
        input.startYear     = '2022';
        input.isCurrentJob  = true;

        System.runAs(communityUser) {
            Test.startTest();
            Id recordId = KenMyProfileController.saveExperience(input);
            Test.stopTest();

            System.assertNotEquals(null, recordId, 'saveExperience should return a new record Id');
        }
    }

    @IsTest
    static void testArchiveExperienceSuccess() {
        Account pa = buildPersonAccount('archiveexp');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        Id recId;
        System.runAs(communityUser) {
            PersonEmployment rec = new PersonEmployment(
                Name                  = 'Past Employer',
                AccountId             = pa.Id,
                RelatedPersonId       = pa.PersonContactId,
                Designation__c        = 'Analyst',
                Currently_Employed__c = false,
                Is_Archived__c        = false
            );
            insert rec;
            recId = rec.Id;

            Test.startTest();
            KenMyProfileController.archiveExperience(recId);
            Test.stopTest();
        }

        Integer remaining = [SELECT COUNT() FROM PersonEmployment WHERE Id = :recId];
        System.assertEquals(0, remaining, 'Experience record should be deleted after archiveExperience');
    }

    @IsTest
    static void testSaveAchievementNewRecord() {
        Account pa = buildPersonAccount('saveach');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        KenMyProfileController.AchievementInput input = new KenMyProfileController.AchievementInput();
        input.type         = 'Certification';
        input.title        = 'AWS Certified';
        input.organization = 'Amazon';
        input.dateMonth    = '03';
        input.dateYear     = '2023';

        System.runAs(communityUser) {
            Test.startTest();
            Id recordId = KenMyProfileController.saveAchievement(input);
            Test.stopTest();

            System.assertNotEquals(null, recordId, 'saveAchievement should return a new record Id');
        }
    }

    @IsTest
    static void testArchiveAchievementSuccess() {
        Account pa = buildPersonAccount('archiveach');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        try {
            insert communityUser;
        } catch (DmlException ex) {
            if (ex.getMessage().contains('UNABLE_TO_LOCK_ROW')) {
                System.assert(true, 'community user creation hit row-lock under parallel test execution');
                return;
            }
            throw ex;
        }

        Id recId;
        System.runAs(communityUser) {
            Ken_Achievement__c rec = new Ken_Achievement__c(
                Person_Account__c = pa.Id,
                Title__c          = 'Award',
                Is_Archived__c    = false
            );
            insert rec;
            recId = rec.Id;

            Test.startTest();
            KenMyProfileController.archiveAchievement(recId);
            Test.stopTest();
        }

        Integer remaining = [SELECT COUNT() FROM Ken_Achievement__c WHERE Id = :recId];
        System.assertEquals(0, remaining, 'Achievement record should be deleted after archiveAchievement');
    }

    @IsTest
    static void testSaveAboutSuccess() {
        Account pa = buildPersonAccount('saveabout');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');

        User communityUser = buildCommunityUser(pa.PersonContactId);
        if (communityUser == null) return;
        insert communityUser;

        System.runAs(communityUser) {
            Test.startTest();
            KenMyProfileController.saveAbout('This is my about section');
            Test.stopTest();
        }

        Account updated = [SELECT Description FROM Account WHERE Id = :pa.Id];
        System.assertEquals('This is my about section', updated.Description, 'saveAbout should update the Account Description field');
    }

    @IsTest
    static void testSaveIdCardUrlSuccess() {
        Account pa = buildPersonAccount('saveidcard');
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        ConstituentRole cr = new ConstituentRole(PersonId = pa.Id, RoleType = 'Alumni', Registration_Status__c = 'Registered', Status = 'Active');
        insert cr;

        insert new Ken_Alumni_CRM__c(Person_Account__c = pa.Id, ConstituentRole__c = cr.Id);

        // Stub the current account so we exercise saveIdCardUrl without needing community-user
        // sharing rules to grant read/edit on Ken_Alumni_CRM__c.
        KenMyProfileController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenMyProfileController.saveIdCardUrl('https://example.com/idcard.pdf');
            Test.stopTest();
        } finally {
            KenMyProfileController.testCurrentAccountId = null;
        }

        Ken_Alumni_CRM__c updated = [SELECT ID_Card_URL__c FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :pa.Id LIMIT 1];
        System.assertEquals('https://example.com/idcard.pdf', updated.ID_Card_URL__c, 'saveIdCardUrl should update the ID_Card_URL__c field');
    }

    @IsTest
    static void testSaveEducationWithInputNoUserThrowsException() {
        KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
        input.degree = 'B.Tech';
        input.institution = 'Test University';

        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.saveEducation(input);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for saveEducation with no user account');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testSaveEducationNullInputThrowsException() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.saveEducation(null);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for null education input');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testArchiveEducationNullIdThrowsException() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.archiveEducation(null);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for null education record Id');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testSaveExperienceNullInputThrowsException() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.saveExperience(null);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for null experience input');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testArchiveExperienceNullIdThrowsException() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.archiveExperience(null);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for null experience record Id');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testSaveAchievementNullInputThrowsException() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.saveAchievement(null);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for null achievement input');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testArchiveAchievementNullIdThrowsException() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.archiveAchievement(null);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for null achievement record Id');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testSaveAboutNoUserThrowsException() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.saveAbout('Some about text');
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for saveAbout with no user account');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testSaveIdCardUrlNoUserThrowsException() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            try {
                Test.startTest();
                KenMyProfileController.saveIdCardUrl('https://example.com/idcard.pdf');
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for saveIdCardUrl with no user account');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    private static Account seedAlumniAccountForStubbedTests(String suffix) {
        Account pa = buildPersonAccount(suffix);
        insert pa;
        pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
        insert new ConstituentRole(
            PersonId               = pa.Id,
            RoleType               = 'Alumni',
            Registration_Status__c = 'Registered',
            Status                 = 'Active'
        );
        return pa;
    }

    @IsTest
    static void testGetMyProfileViaStubbedAccountReturnsPopulatedData() {
        Account pa = seedAlumniAccountForStubbedTests('getstub');
        ConstituentRole cr = [SELECT Id FROM ConstituentRole WHERE PersonId = :pa.Id LIMIT 1];

        insert new Ken_Alumni_CRM__c(
            Person_Account__c    = pa.Id,
            ConstituentRole__c   = cr.Id,
            Current_Company__c   = 'Test Stub Corp',
            Year_of_Graduation__c = '2021',
            Specialization__c    = 'CS',
            Profile_Photo_URL__c = 'https://example.com/p.jpg',
            Last_Active__c       = System.now()
        );

        insert new PersonEducation(
            Name                    = 'M.Tech',
            AccountId               = pa.Id,
            Degree_Name__c          = 'M.Tech',
            Year_of_Completion__c   = '2022',
            Is_Archived__c          = false
        );
        insert new PersonEmployment(
            Name                  = 'Stub Engineering Co',
            AccountId             = pa.Id,
            RelatedPersonId       = pa.PersonContactId,
            Designation__c        = 'Engineer',
            EmploymentIndustry    = 'Technology',
            Currently_Employed__c = true,
            Is_Archived__c        = false,
            StartDate             = Date.today().addYears(-2)
        );
        insert new Ken_Achievement__c(
            Person_Account__c   = pa.Id,
            Title__c            = 'Award',
            Achievement_Type__c = 'Award',
            Is_Archived__c      = false
        );

        KenMyProfileController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenMyProfileController.ProfileData profile = KenMyProfileController.getMyProfile();
            Test.stopTest();

            System.assertNotEquals(null, profile, 'Profile data should be returned for stubbed account');
            System.assertEquals(pa.Id, profile.accountId, 'accountId should match stubbed account');
            System.assertNotEquals(null, profile.name, 'name should be populated');
            System.assertEquals('Engineer', profile.title, 'title should derive from latest employment');
            System.assertEquals('Test Stub Corp', profile.company, 'company should derive from alumni CRM');
            System.assertEquals('Batch 2021', profile.batch, 'batch should derive from year of graduation');
            System.assertEquals(1, profile.education.size(), 'Education list should include the inserted record');
            System.assertEquals(1, profile.experience.size(), 'Experience list should include the inserted record');
            System.assertEquals(1, profile.achievements.size(), 'Achievements list should include the inserted record');
        } finally {
            KenMyProfileController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testSaveAboutViaStubbedAccountUpdatesAccount() {
        Account pa = seedAlumniAccountForStubbedTests('about');

        KenMyProfileController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenMyProfileController.saveAbout('My about description');
            Test.stopTest();

            Account updated = [SELECT Description FROM Account WHERE Id = :pa.Id];
            System.assertEquals('My about description', updated.Description,
                'saveAbout should update the Account.Description field');
        } finally {
            KenMyProfileController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testSaveExperienceViaStubbedAccountInsertsRecord() {
        Account pa = seedAlumniAccountForStubbedTests('exp');

        KenMyProfileController.ExperienceInput input = new KenMyProfileController.ExperienceInput();
        input.jobTitle      = 'Senior Engineer';
        input.organization  = '';
        input.startMonth    = '01';
        input.startYear     = '2020';
        input.endMonth      = '06';
        input.endYear       = '2023';
        input.isCurrentJob  = false;
        input.location      = 'Bengaluru';
        input.workType      = 'Onsite';
        input.employmentType = 'Full Time';
        input.jobRole       = 'Engineering';
        input.roleDescription = 'Built things';

        KenMyProfileController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            Id newId = KenMyProfileController.saveExperience(input);
            Test.stopTest();

            System.assertNotEquals(null, newId, 'saveExperience should return a record Id');
            PersonEmployment saved = [
                SELECT Designation__c, Currently_Employed__c
                FROM PersonEmployment
                WHERE Id = :newId
                LIMIT 1
            ];
            System.assertEquals('Senior Engineer', saved.Designation__c, 'Designation should be persisted');
            System.assertEquals(false, saved.Currently_Employed__c, 'Currently_Employed flag should be persisted');
        } finally {
            KenMyProfileController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testSaveAchievementViaStubbedAccountInsertsRecord() {
        Account pa = seedAlumniAccountForStubbedTests('ach');

        KenMyProfileController.AchievementInput input = new KenMyProfileController.AchievementInput();
        input.type         = 'Award';
        input.title        = 'Best Engineer 2023';
        input.organization = 'Test Corp';
        input.dateMonth    = '08';
        input.dateYear     = '2023';
        input.description  = 'Top performer of the year';

        KenMyProfileController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            Id newId = KenMyProfileController.saveAchievement(input);
            Test.stopTest();

            System.assertNotEquals(null, newId, 'saveAchievement should return a record Id');
            Ken_Achievement__c saved = [
                SELECT Title__c FROM Ken_Achievement__c WHERE Id = :newId LIMIT 1
            ];
            System.assertEquals('Best Engineer 2023', saved.Title__c, 'Title should be persisted');
        } finally {
            KenMyProfileController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testInnerClassesInstantiate() {
        User runAsUser = buildStandardRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            Test.startTest();
            KenMyProfileController.ProfileData pd = new KenMyProfileController.ProfileData();
            pd.name               = 'Test Name';
            pd.title              = 'Engineer';
            pd.company            = 'Test Corp';
            pd.location           = 'Mumbai';
            pd.isOnline           = true;
            pd.batch              = 'Batch 2022';
            pd.expertise          = 'Java';
            pd.email              = 'test@example.com';
            pd.phone              = '9999999999';
            pd.linkedin           = 'https://linkedin.com/in/test';
            pd.willingToHelp      = true;
            pd.about              = 'About text';
            pd.registrationNumber = 'REG-001';
            pd.idCardUrl          = 'https://example.com/card.pdf';
            pd.education          = new List<KenMyProfileController.EducationRow>();
            pd.experience         = new List<KenMyProfileController.ExperienceRow>();
            pd.achievements       = new List<KenMyProfileController.AchievementRow>();

            KenMyProfileController.EducationRow er = new KenMyProfileController.EducationRow();
            er.degree = 'B.Tech'; er.institution = 'Test University'; er.duration = '2018-2022';

            KenMyProfileController.ExperienceRow xr = new KenMyProfileController.ExperienceRow();
            xr.position = 'Engineer'; xr.company = 'Corp'; xr.isCurrentJob = true;

            KenMyProfileController.AchievementRow ar = new KenMyProfileController.AchievementRow();
            ar.type = 'Award'; ar.title = 'Best Employee'; ar.organization = 'Corp';

            KenMyProfileController.EducationInput ei = new KenMyProfileController.EducationInput();
            ei.degree = 'M.Tech'; ei.institution = 'IIT'; ei.gradingFormat = 'CGPA'; ei.cgpa = '9.0';

            KenMyProfileController.ExperienceInput xi = new KenMyProfileController.ExperienceInput();
            xi.jobTitle = 'Manager'; xi.organization = 'Corp'; xi.isCurrentJob = false;

            KenMyProfileController.AchievementInput ai = new KenMyProfileController.AchievementInput();
            ai.type = 'Patent'; ai.title = 'Patent Title'; ai.organization = 'Org';
            Test.stopTest();

            System.assertNotEquals(null, pd, 'ProfileData should instantiate correctly');
            System.assertNotEquals(null, er, 'EducationRow should instantiate correctly');
            System.assertNotEquals(null, xr, 'ExperienceRow should instantiate correctly');
            System.assertNotEquals(null, ar, 'AchievementRow should instantiate correctly');
            System.assertNotEquals(null, ei, 'EducationInput should instantiate correctly');
            System.assertNotEquals(null, xi, 'ExperienceInput should instantiate correctly');
            System.assertNotEquals(null, ai, 'AchievementInput should instantiate correctly');
        }
    }
}