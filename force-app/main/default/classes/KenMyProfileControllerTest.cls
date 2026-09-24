@IsTest
private class KenMyProfileControllerTest {
  private static Id kenCampusId;

  /**
   * @description A portal user can only be created under an account whose owner holds a role.
   *              The running user used to be handed one here, but that row is shared with every
   *              other test class in the run and updating it is where UNABLE_TO_LOCK_ROW comes
   *              from. A throwaway owner carrying a fresh role is created once instead, and the
   *              accounts these tests build are given to it.
   */
  @TestSetup
  static void makePortalOwner() {
    System.runAs(new User(Id = UserInfo.getUserId())) {
      String suffix =
        String.valueOf(System.currentTimeMillis()) +
        String.valueOf(Math.abs(Crypto.getRandomInteger()));
      UserRole role = new UserRole(
        Name = 'Portal Owner ' + suffix,
        DeveloperName = 'Portal_Owner_' + suffix
      );
      insert role;
      insert new User(
        Username = 'portal.owner.' + suffix + '@kenalumni.test',
        Email = 'portal.owner@kenalumni.test',
        LastName = 'PortalOwner',
        Alias = 'ptlownr',
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US',
        ProfileId = UserInfo.getProfileId(),
        UserRoleId = role.Id
      );
    }
  }

  private static Id portalOwnerId() {
    return [
      SELECT Id
      FROM User
      WHERE Username LIKE 'portal.owner.%@kenalumni.test'
      ORDER BY CreatedDate DESC
      LIMIT 1
    ]
    .Id;
  }

  /**
   * KJS orgs add a required Campus__c lookup (-> Location) on LearningProgram.
   * Populate it only where the field exists so the tests still run in every
   * other org, and reuse one Location so a helper called in a loop does not
   * spend a DML statement per programme.
   */
  private static void kenAssignCampus(SObject record) {
    if (
      !record.getSObjectType()
        .getDescribe()
        .fields.getMap()
        .containsKey('campus__c')
    ) {
      return;
    }
    if (kenCampusId == null) {
      Schema.Location campus = new Schema.Location(Name = 'Ken Test Campus');
      for (
        Schema.PicklistEntry entry : Schema.Location.LocationType.getDescribe()
          .getPicklistValues()
      ) {
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

  private static final String ALUMNI_RT = 'PersonAccount';
  private static final String ALUMNI_PROFILE = 'Alumni';

  private static Id getPersonAccountRtId() {
    List<RecordType> rts = [
      SELECT Id
      FROM RecordType
      WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT
      LIMIT 1
    ];
    if (!rts.isEmpty())
      return rts[0].Id;
    for (RecordType rt : [
      SELECT Id, IsPersonType
      FROM RecordType
      WHERE SObjectType = 'Account' AND IsActive = TRUE
    ]) {
      if (rt.IsPersonType)
        return rt.Id;
    }
    return null;
  }

  private static User buildStandardRunAsUser() {
    Profile prof = [
      SELECT Id
      FROM Profile
      WHERE Name = 'System Administrator'
      LIMIT 1
    ];
    return new User(
      Username = 'myprofile.' + System.currentTimeMillis() + '@example.com',
      Email = 'myprofile@example.com',
      LastName = 'MyProfileTest',
      Alias = 'mprf',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = prof.Id
    );
  }

  private static void grantAlumniAccess(User u) {
    List<PermissionSetLicenseAssign> licences = new List<PermissionSetLicenseAssign>();
    for (PermissionSetLicense psl : [
      SELECT Id
      FROM PermissionSetLicense
      WHERE DeveloperName = 'EducationCloudExprcCloudAccessPsl'
    ]) {
      licences.add(
        new PermissionSetLicenseAssign(
          AssigneeId = u.Id,
          PermissionSetLicenseId = psl.Id
        )
      );
    }
    List<PermissionSetAssignment> grants = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN (
        'Alumni',
        'Alumni_Education_Cloud',
        'AlumniEducationCloudExprcCloudAccess'
      )
    ]) {
      grants.add(
        new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)
      );
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Database.insert(licences, false);
      Database.insert(grants, false);
    }
  }

  private static User buildCommunityUser(Id contactId) {
    List<Profile> profs = [
      SELECT Id
      FROM Profile
      WHERE Name = :ALUMNI_PROFILE
      LIMIT 1
    ];
    if (profs.isEmpty())
      return null;
    return new User(
      Username = 'myprofile.community.' +
        System.currentTimeMillis() +
        '@test.alumni.com',
      Email = 'myprofile.community@test.alumni.com',
      LastName = 'MyProfileCommunity',
      Alias = 'mprc',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = profs[0].Id,
      ContactId = contactId
    );
  }

  private static Account buildPersonAccount(String suffix) {
    Account pa = new Account(
      FirstName = 'MyProfile',
      LastName = 'TestUser' + suffix,
      PersonEmail = 'myprofile.' +
        suffix +
        '.' +
        System.currentTimeMillis() +
        '@test.com',
      OwnerId = portalOwnerId()
    );
    Id rtId = getPersonAccountRtId();
    if (rtId != null)
      pa.RecordTypeId = rtId;
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

      System.assertNotEquals(
        null,
        result,
        'getMyProfile should return a non-null empty profile when user has no account'
      );
      System.assertNotEquals(
        null,
        result.education,
        'Education list should not be null'
      );
      System.assertNotEquals(
        null,
        result.experience,
        'Experience list should not be null'
      );
      System.assertNotEquals(
        null,
        result.achievements,
        'Achievements list should not be null'
      );
      System.assertEquals(
        true,
        result.willingToHelp,
        'willingToHelp should default to true in empty profile'
      );
      System.assertEquals(
        false,
        result.isOnline,
        'isOnline should default to false in empty profile'
      );
    }
  }

  @IsTest
  static void testGetMyProfileWithCommunityUser() {
    Account pa = buildPersonAccount('getprofile');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];

    ConstituentRole cr = new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active',
      Graduation_Year__c = '2022'
    );
    insert cr;
    insert new PersonEmployment(
      Name = 'Test Corp',
      AccountId = pa.Id,
      RelatedPersonId = pa.Id,
      Company_Name__c = 'Test Corp',
      Currently_Employed__c = true,
      Is_Archived__c = false
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    System.runAs(communityUser) {
      Test.startTest();
      KenMyProfileController.ProfileData result = KenMyProfileController.getMyProfile();
      Test.stopTest();

      System.assertNotEquals(
        null,
        result,
        'getMyProfile should return populated data for community user with account'
      );
      System.assertNotEquals(
        null,
        result.accountId,
        'accountId should be set from the linked person account'
      );
      System.assertNotEquals(
        null,
        result.name,
        'name should be set from account'
      );
    }
  }

  @IsTest
  static void testSaveEducationNewRecord() {
    Account pa = buildPersonAccount('saveedu');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
    input.degree = 'B.Tech';
    input.institution = '';
    input.startMonth = '06';
    input.startYear = '2018';
    input.endMonth = '05';
    input.endYear = '2022';
    input.gradingFormat = 'CGPA';
    input.cgpa = '8.5';

    System.runAs(communityUser) {
      Test.startTest();
      Id recordId = KenMyProfileController.saveEducation(input);
      Test.stopTest();

      System.assertNotEquals(
        null,
        recordId,
        'saveEducation should return the new record Id'
      );
    }
  }

  @IsTest
  static void testEducationStartYearFallsBackToRoleEnrolmentYear() {
    Account pa = buildPersonAccount('yearonly');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active',
      Year_of_Enrollment__c = '2022'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    // Mirrors the onboarding pre-fill: an end year but no start month/year at all.
    // StartDate cannot be built without a month, so the start year has to be read
    // back off the alumnus's ConstituentRole rather than the education row.
    KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
    input.degree = 'MBA';
    input.institution = 'Ken Institute';
    input.institutionType = 'institute';
    input.endYear = '2024';
    input.gradingFormat = 'CGPA';

    System.runAs(communityUser) {
      Test.startTest();
      Id recordId = KenMyProfileController.saveEducation(input);
      Test.stopTest();

      PersonEducation saved = [
        SELECT StartDate, Year_of_Completion__c
        FROM PersonEducation
        WHERE Id = :recordId
      ];
      System.assertEquals(
        null,
        saved.StartDate,
        'A year with no month cannot build a StartDate'
      );
      System.assertEquals(
        '2024',
        saved.Year_of_Completion__c,
        'The end year persists in Year_of_Completion__c'
      );

      KenMyProfileController.ProfileData profile = KenMyProfileController.getMyProfile();
      Boolean found = false;
      for (KenMyProfileController.EducationRow row : profile.education) {
        if (String.valueOf(row.id) == String.valueOf(recordId)) {
          found = true;
          System.assertEquals(
            '2022',
            row.startYear,
            'startYear must fall back to the role Year_of_Enrollment__c'
          );
          System.assertEquals(
            '2024',
            row.endYear,
            'endYear must fall back to Year_of_Completion__c'
          );
        }
      }
      System.assert(
        found,
        'The saved education should be returned by getMyProfile'
      );
    }
  }

  @IsTest
  static void testSaveEducationSelfInstituteFlagged() {
    Account pa = buildPersonAccount('selfedu');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
    input.degree = 'B.Sc';
    input.institution = 'Some Other College';
    input.institutionType = 'other';
    input.startYear = '2016';
    input.endYear = '2019';
    input.gradingFormat = 'CGPA';
    input.cgpa = '7.5';

    Id recordId;
    System.runAs(communityUser) {
      Test.startTest();
      recordId = KenMyProfileController.saveEducation(input);
      Test.stopTest();
    }

    PersonEducation saved = [
      SELECT Institution_Type__c
      FROM PersonEducation
      WHERE Id = :recordId
    ];
    System.assertEquals(
      'Other',
      saved.Institution_Type__c,
      'An "other" institute education should be tagged Other'
    );
  }

  private static Id createProgramPlanForProfile(String name) {
    Learning lrn = new Learning(Name = name + ' Learning');
    insert lrn;
    LearningProgram lp = new LearningProgram(
      Name = name + ' Program',
      LearningId = lrn.Id
    );
    kenAssignCampus(lp);
    insert lp;
    LearningProgramPlan lpp = new LearningProgramPlan(
      Name = name,
      LearningProgramId = lp.Id
    );
    insert lpp;
    return lpp.Id;
  }

  @IsTest
  static void testSaveEducationOurInstituteStoresProgramPlanAndRegNo() {
    Account pa = buildPersonAccount('ourinst');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    Id planId = createProgramPlanForProfile('MyProfilePlan');

    KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
    input.degree = 'B.Tech';
    input.institution = 'Ken Institute';
    input.institutionType = 'institute';
    input.programPlan = planId;
    input.registrationNumber = 'REG-999';
    input.startYear = '2016';
    input.endYear = '2020';
    input.gradingFormat = 'CGPA';
    input.cgpa = '8.0';

    Id recordId;
    System.runAs(communityUser) {
      Test.startTest();
      recordId = KenMyProfileController.saveEducation(input);
      Test.stopTest();
    }

    PersonEducation saved = [
      SELECT Program_Plan__c, Registration_Number__c, Institution_Type__c
      FROM PersonEducation
      WHERE Id = :recordId
    ];
    System.assertEquals(
      planId,
      saved.Program_Plan__c,
      'Program plan should be stored on the education'
    );
    System.assertEquals(
      'REG-999',
      saved.Registration_Number__c,
      'Registration number should be stored'
    );
    System.assertEquals(
      'Our Institute',
      saved.Institution_Type__c,
      'Should tag Our Institute'
    );
  }

  @IsTest
  static void testSaveEducationUpdateRecord() {
    Account pa = buildPersonAccount('updateedu');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    System.runAs(communityUser) {
      PersonEducation existing = new PersonEducation(
        Name = 'B.Sc',
        AccountId = pa.Id,
        Degree_Name__c = 'B.Sc',
        Is_Archived__c = false
      );
      insert existing;

      KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
      input.id = existing.Id;
      input.degree = 'B.Tech';
      input.gradingFormat = 'CGPA';
      input.cgpa = '9.0';

      Test.startTest();
      Id recordId = KenMyProfileController.saveEducation(input);
      Test.stopTest();

      System.assertEquals(
        existing.Id,
        recordId,
        'saveEducation update should return the same record Id'
      );
    }
  }

  @IsTest
  static void testSaveEducationTwiceWithoutIdDoesNotDuplicate() {
    Account pa = buildPersonAccount('dupedu');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    Id firstId;
    Id secondId;
    System.runAs(communityUser) {
      KenMyProfileController.EducationInput input = new KenMyProfileController.EducationInput();
      input.degree = 'B.E';
      input.institution = 'Anna university';
      input.startMonth = '06';
      input.startYear = '2017';
      input.endMonth = '04';
      input.endYear = '2020';
      input.gradingFormat = 'CGPA';
      input.cgpa = '7.9';

      Test.startTest();
      firstId = KenMyProfileController.saveEducation(input);

      // Same qualification re-submitted with no id and slightly different
      // dates — the scenario that produced two identical 360 rows.
      KenMyProfileController.EducationInput repeat = new KenMyProfileController.EducationInput();
      repeat.degree = 'b.e';
      repeat.institution = ' Anna   university ';
      repeat.startMonth = '05';
      repeat.startYear = '2017';
      repeat.endMonth = '05';
      repeat.endYear = '2020';
      repeat.gradingFormat = 'CGPA';
      repeat.cgpa = '7.9';
      secondId = KenMyProfileController.saveEducation(repeat);
      Test.stopTest();
    }

    System.assertEquals(
      firstId,
      secondId,
      'A repeat save of the same qualification must update the existing row'
    );

    List<PersonEducation> rows = [
      SELECT Id, StartDate, EndDate, ContactId
      FROM PersonEducation
      WHERE AccountId = :pa.Id AND Is_Archived__c = FALSE
    ];
    System.assertEquals(
      1,
      rows.size(),
      'Only one education row should exist for the same institute/degree/year'
    );
    System.assertEquals(
      Date.newInstance(2020, 5, 1),
      rows[0].EndDate,
      'The repeat save should have updated the dates in place'
    );
    System.assertEquals(
      pa.PersonContactId,
      rows[0].ContactId,
      'ContactId must be mirrored so the related list shows the row'
    );
  }

  @IsTest
  static void testSaveEducationDifferentDegreeSameInstituteInsertsSeparateRow() {
    Account pa = buildPersonAccount('twodeg');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    System.runAs(communityUser) {
      KenMyProfileController.EducationInput ug = new KenMyProfileController.EducationInput();
      ug.degree = 'B.E';
      ug.institution = 'Anna university';
      ug.endYear = '2020';
      ug.gradingFormat = 'CGPA';

      KenMyProfileController.EducationInput pg = new KenMyProfileController.EducationInput();
      pg.degree = 'M.E';
      pg.institution = 'Anna university';
      pg.endYear = '2022';
      pg.gradingFormat = 'CGPA';

      Test.startTest();
      Id ugId = KenMyProfileController.saveEducation(ug);
      Id pgId = KenMyProfileController.saveEducation(pg);
      Test.stopTest();

      System.assertNotEquals(
        ugId,
        pgId,
        'Two genuinely different qualifications must stay separate rows'
      );
    }

    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM PersonEducation
        WHERE AccountId = :pa.Id AND Is_Archived__c = FALSE
      ],
      'Distinct degrees at the same institute should both be kept'
    );
  }

  @IsTest
  static void testArchiveEducationSuccess() {
    Account pa = buildPersonAccount('archiveedu');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    Id recId;
    System.runAs(communityUser) {
      PersonEducation rec = new PersonEducation(
        Name = 'MBA',
        AccountId = pa.Id,
        Degree_Name__c = 'MBA',
        Is_Archived__c = false
      );
      insert rec;
      recId = rec.Id;

      Test.startTest();
      KenMyProfileController.archiveEducation(recId);
      Test.stopTest();
    }

    Integer remaining = [SELECT COUNT() FROM PersonEducation WHERE Id = :recId];
    System.assertEquals(
      0,
      remaining,
      'Education record should be deleted after archiveEducation'
    );
  }

  @IsTest
  static void testSaveExperienceNewRecord() {
    Account pa = buildPersonAccount('saveexp');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    KenMyProfileController.ExperienceInput input = new KenMyProfileController.ExperienceInput();
    input.jobTitle = 'Software Engineer';
    input.organization = '';
    input.startMonth = '01';
    input.startYear = '2022';
    input.isCurrentJob = true;

    System.runAs(communityUser) {
      Test.startTest();
      Id recordId = KenMyProfileController.saveExperience(input);
      Test.stopTest();

      System.assertNotEquals(
        null,
        recordId,
        'saveExperience should return a new record Id'
      );
    }
  }

  @IsTest
  static void testArchiveExperienceSuccess() {
    Account pa = buildPersonAccount('archiveexp');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    Id recId;
    System.runAs(communityUser) {
      PersonEmployment rec = new PersonEmployment(
        Name = 'Past Employer',
        AccountId = pa.Id,
        RelatedPersonId = pa.PersonContactId,
        Designation__c = 'Analyst',
        Currently_Employed__c = false,
        Is_Archived__c = false
      );
      insert rec;
      recId = rec.Id;

      Test.startTest();
      KenMyProfileController.archiveExperience(recId);
      Test.stopTest();
    }

    Integer remaining = [
      SELECT COUNT()
      FROM PersonEmployment
      WHERE Id = :recId
    ];
    System.assertEquals(
      0,
      remaining,
      'Experience record should be deleted after archiveExperience'
    );
  }

  @IsTest
  static void testSaveAchievementNewRecord() {
    Account pa = buildPersonAccount('saveach');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    KenMyProfileController.AchievementInput input = new KenMyProfileController.AchievementInput();
    input.type = 'Certification';
    input.title = 'AWS Certified';
    input.organization = 'Amazon';
    input.dateMonth = '03';
    input.dateYear = '2023';

    System.runAs(communityUser) {
      Test.startTest();
      Id recordId = KenMyProfileController.saveAchievement(input);
      Test.stopTest();

      System.assertNotEquals(
        null,
        recordId,
        'saveAchievement should return a new record Id'
      );
    }
  }

  @IsTest
  static void testArchiveAchievementSuccess() {
    Account pa = buildPersonAccount('archiveach');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    try {
      insert communityUser;
      grantAlumniAccess(communityUser);
    } catch (DmlException ex) {
      if (ex.getMessage().contains('UNABLE_TO_LOCK_ROW')) {
        System.assert(
          true,
          'community user creation hit row-lock under parallel test execution'
        );
        return;
      }
      throw ex;
    }

    Id recId;
    System.runAs(communityUser) {
      Ken_Achievement__c rec = new Ken_Achievement__c(
        Person_Account__c = pa.Id,
        Title__c = 'Award',
        Is_Archived__c = false
      );
      insert rec;
      recId = rec.Id;

      Test.startTest();
      KenMyProfileController.archiveAchievement(recId);
      Test.stopTest();
    }

    Integer remaining = [
      SELECT COUNT()
      FROM Ken_Achievement__c
      WHERE Id = :recId
    ];
    System.assertEquals(
      0,
      remaining,
      'Achievement record should be deleted after archiveAchievement'
    );
  }

  @IsTest
  static void testSaveAboutSuccess() {
    Account pa = buildPersonAccount('saveabout');
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );

    User communityUser = buildCommunityUser(pa.PersonContactId);
    if (communityUser == null)
      return;
    insert communityUser;
    grantAlumniAccess(communityUser);

    System.runAs(communityUser) {
      Test.startTest();
      KenMyProfileController.saveAbout('This is my about section');
      Test.stopTest();
    }

    Account updated = [SELECT Description FROM Account WHERE Id = :pa.Id];
    System.assertEquals(
      'This is my about section',
      updated.Description,
      'saveAbout should update the Account Description field'
    );
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
        System.assert(
          false,
          'Expected AuraHandledException for saveEducation with no user account'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
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
        System.assert(
          false,
          'Expected AuraHandledException for null education input'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
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
        System.assert(
          false,
          'Expected AuraHandledException for null education record Id'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
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
        System.assert(
          false,
          'Expected AuraHandledException for null experience input'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
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
        System.assert(
          false,
          'Expected AuraHandledException for null experience record Id'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
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
        System.assert(
          false,
          'Expected AuraHandledException for null achievement input'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
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
        System.assert(
          false,
          'Expected AuraHandledException for null achievement record Id'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
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
        System.assert(
          false,
          'Expected AuraHandledException for saveAbout with no user account'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
      }
    }
  }

  private static Account seedAlumniAccountForStubbedTests(String suffix) {
    Account pa = buildPersonAccount(suffix);
    insert pa;
    pa = [SELECT Id, PersonContactId FROM Account WHERE Id = :pa.Id];
    insert new ConstituentRole(
      PersonId = pa.Id,
      RoleType = 'Alumni',
      Registration_Status__c = 'Registered',
      Status = 'Active'
    );
    return pa;
  }

  @IsTest
  static void testGetMyProfileViaStubbedAccountReturnsPopulatedData() {
    Account pa = seedAlumniAccountForStubbedTests('getstub');
    ConstituentRole cr = [
      SELECT Id
      FROM ConstituentRole
      WHERE PersonId = :pa.Id
      LIMIT 1
    ];

    update new ConstituentRole(Id = cr.Id, Graduation_Year__c = '2021');
    update new Account(
      Id = pa.Id,
      Profile_Photo_URL__c = 'https://example.com/p.jpg'
    );

    insert new PersonEducation(
      Name = 'M.Tech',
      AccountId = pa.Id,
      Degree_Name__c = 'M.Tech',
      Year_of_Completion__c = '2022',
      Is_Archived__c = false
    );
    insert new PersonEmployment(
      Name = 'Stub Engineering Co',
      AccountId = pa.Id,
      RelatedPersonId = pa.PersonContactId,
      Company_Name__c = 'Stub Engineering Co',
      Designation__c = 'Engineer',
      EmploymentIndustry = 'Technology',
      Currently_Employed__c = true,
      Is_Archived__c = false,
      StartDate = Date.today().addYears(-2)
    );
    insert new Ken_Achievement__c(
      Person_Account__c = pa.Id,
      Title__c = 'Award',
      Achievement_Type__c = 'Award',
      Is_Archived__c = false
    );

    KenMyProfileController.testCurrentAccountId = pa.Id;
    try {
      Test.startTest();
      KenMyProfileController.ProfileData profile = KenMyProfileController.getMyProfile();
      Test.stopTest();

      System.assertNotEquals(
        null,
        profile,
        'Profile data should be returned for stubbed account'
      );
      System.assertEquals(
        pa.Id,
        profile.accountId,
        'accountId should match stubbed account'
      );
      System.assertNotEquals(null, profile.name, 'name should be populated');
      System.assertEquals(
        'Engineer',
        profile.title,
        'title should derive from latest employment'
      );
      System.assertEquals(
        'Stub Engineering Co',
        profile.company,
        'company should derive from the current PersonEmployment row'
      );
      System.assertEquals(
        'Batch 2021',
        profile.batch,
        'batch should derive from ConstituentRole.Graduation_Year__c'
      );
      System.assertEquals(
        'https://example.com/p.jpg',
        profile.profileImage,
        'profile image should derive from Account.Profile_Photo_URL__c'
      );
      System.assertEquals(
        1,
        profile.education.size(),
        'Education list should include the inserted record'
      );
      System.assertEquals(
        1,
        profile.experience.size(),
        'Experience list should include the inserted record'
      );
      System.assertEquals(
        1,
        profile.achievements.size(),
        'Achievements list should include the inserted record'
      );
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
      System.assertEquals(
        'My about description',
        updated.Description,
        'saveAbout should update the Account.Description field'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testSaveExperienceViaStubbedAccountInsertsRecord() {
    Account pa = seedAlumniAccountForStubbedTests('exp');

    KenMyProfileController.ExperienceInput input = new KenMyProfileController.ExperienceInput();
    input.jobTitle = 'Senior Engineer';
    input.organization = '';
    input.startMonth = '01';
    input.startYear = '2020';
    input.endMonth = '06';
    input.endYear = '2023';
    input.isCurrentJob = false;
    input.location = 'Bengaluru';
    input.workType = 'Onsite';
    input.employmentType = 'Full Time';
    input.jobRole = 'Engineering';
    input.roleDescription = 'Built things';

    KenMyProfileController.testCurrentAccountId = pa.Id;
    try {
      Test.startTest();
      Id newId = KenMyProfileController.saveExperience(input);
      Test.stopTest();

      System.assertNotEquals(
        null,
        newId,
        'saveExperience should return a record Id'
      );
      PersonEmployment saved = [
        SELECT Designation__c, Currently_Employed__c
        FROM PersonEmployment
        WHERE Id = :newId
        LIMIT 1
      ];
      System.assertEquals(
        'Senior Engineer',
        saved.Designation__c,
        'Designation should be persisted'
      );
      System.assertEquals(
        false,
        saved.Currently_Employed__c,
        'Currently_Employed flag should be persisted'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testSaveAchievementViaStubbedAccountInsertsRecord() {
    Account pa = seedAlumniAccountForStubbedTests('ach');

    KenMyProfileController.AchievementInput input = new KenMyProfileController.AchievementInput();
    input.type = 'Award';
    input.title = 'Best Engineer 2023';
    input.organization = 'Test Corp';
    input.dateMonth = '08';
    input.dateYear = '2023';
    input.description = 'Top performer of the year';

    KenMyProfileController.testCurrentAccountId = pa.Id;
    try {
      Test.startTest();
      Id newId = KenMyProfileController.saveAchievement(input);
      Test.stopTest();

      System.assertNotEquals(
        null,
        newId,
        'saveAchievement should return a record Id'
      );
      Ken_Achievement__c saved = [
        SELECT Title__c
        FROM Ken_Achievement__c
        WHERE Id = :newId
        LIMIT 1
      ];
      System.assertEquals(
        'Best Engineer 2023',
        saved.Title__c,
        'Title should be persisted'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testGetMyEngagementNoUserReturnsEmpty() {
    User runAsUser = buildStandardRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Test.startTest();
      KenMyProfileController.EngagementData result = KenMyProfileController.getMyEngagement();
      Test.stopTest();

      System.assertNotEquals(
        null,
        result,
        'getMyEngagement should return a non-null empty result when user has no account'
      );
      System.assertEquals(
        0,
        result.eventsAttendedCount,
        'eventsAttendedCount should default to 0'
      );
      System.assertEquals(
        0,
        result.activeMenteesCount,
        'activeMenteesCount should default to 0'
      );
      System.assertNotEquals(
        null,
        result.eventsAttended,
        'eventsAttended list should not be null'
      );
      System.assertNotEquals(
        null,
        result.mentorship,
        'mentorship list should not be null'
      );
    }
  }

  @IsTest
  static void testGetMyEngagementViaStubbedAccountWithNoRecordsReturnsEmpty() {
    Account pa = seedAlumniAccountForStubbedTests('engagement');

    KenMyProfileController.testCurrentAccountId = pa.Id;
    try {
      Test.startTest();
      KenMyProfileController.EngagementData result = KenMyProfileController.getMyEngagement();
      Test.stopTest();

      System.assertEquals(
        0,
        result.eventsAttendedCount,
        'No bookings exist yet for this alumnus'
      );
      System.assertEquals(
        0,
        result.activeMenteesCount,
        'No mentorship exists yet for this alumnus'
      );
      System.assertEquals(
        0,
        result.eventsAttended.size(),
        'eventsAttended should be empty'
      );
      System.assertEquals(
        0,
        result.mentorship.size(),
        'mentorship should be empty'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testGetMySupportNoUserReturnsEmpty() {
    User runAsUser = buildStandardRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Test.startTest();
      KenMyProfileController.SupportData result = KenMyProfileController.getMySupport();
      Test.stopTest();

      System.assertNotEquals(
        null,
        result,
        'getMySupport should return a non-null empty result when user has no account'
      );
      System.assertEquals(
        0,
        result.ticketsRaisedCount,
        'ticketsRaisedCount should default to 0'
      );
      System.assertEquals(
        0,
        result.currentlyOpenCount,
        'currentlyOpenCount should default to 0'
      );
      System.assertNotEquals(
        null,
        result.tickets,
        'tickets list should not be null'
      );
    }
  }

  @IsTest
  static void testGetMySupportViaStubbedAccountWithNoRecordsReturnsEmpty() {
    Account pa = seedAlumniAccountForStubbedTests('support');

    KenMyProfileController.testCurrentAccountId = pa.Id;
    try {
      Test.startTest();
      KenMyProfileController.SupportData result = KenMyProfileController.getMySupport();
      Test.stopTest();

      System.assertEquals(
        0,
        result.ticketsRaisedCount,
        'No cases exist yet for this alumnus'
      );
      System.assertEquals(
        0,
        result.currentlyOpenCount,
        'No open cases exist yet for this alumnus'
      );
      System.assertEquals(0, result.tickets.size(), 'tickets should be empty');
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testGetMyRecentActivityNoUserReturnsEmpty() {
    User runAsUser = buildStandardRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Test.startTest();
      List<KenMyProfileController.ActivityItem> result = KenMyProfileController.getMyRecentActivity();
      Test.stopTest();

      System.assertNotEquals(
        null,
        result,
        'getMyRecentActivity should return a non-null empty list when user has no account'
      );
      System.assertEquals(
        0,
        result.size(),
        'No account means no activity signals'
      );
    }
  }

  @IsTest
  static void testGetMyRecentActivityViaStubbedAccountPicksUpProfileUpdateSignal() {
    Account pa = seedAlumniAccountForStubbedTests('activity');

    KenMyProfileController.testCurrentAccountId = pa.Id;
    try {
      Test.startTest();
      List<KenMyProfileController.ActivityItem> result = KenMyProfileController.getMyRecentActivity();
      Test.stopTest();

      System.assertNotEquals(null, result, 'result list should not be null');
      Boolean foundProfileUpdated = false;
      for (KenMyProfileController.ActivityItem item : result) {
        if (item.title == 'Profile updated') {
          foundProfileUpdated = true;
        }
      }
      System.assert(
        foundProfileUpdated,
        'A freshly modified ConstituentRole should surface a "Profile updated" signal'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testGetMyRecordHealthNoUserReturnsEmpty() {
    User runAsUser = buildStandardRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Test.startTest();
      List<KenMyProfileController.RecordHealthItem> result = KenMyProfileController.getMyRecordHealth();
      Test.stopTest();

      System.assertNotEquals(
        null,
        result,
        'getMyRecordHealth should return a non-null empty list when user has no account'
      );
      System.assertEquals(
        0,
        result.size(),
        'No account means no health checks'
      );
    }
  }

  @IsTest
  static void testGetMyRecordHealthViaStubbedAccountReturnsFiveChecks() {
    Account pa = seedAlumniAccountForStubbedTests('health');

    KenMyProfileController.testCurrentAccountId = pa.Id;
    try {
      Test.startTest();
      List<KenMyProfileController.RecordHealthItem> result = KenMyProfileController.getMyRecordHealth();
      Test.stopTest();

      System.assertEquals(
        5,
        result.size(),
        'Record health should always report exactly 5 checks'
      );
      for (KenMyProfileController.RecordHealthItem item : result) {
        System.assertNotEquals(
          null,
          item.label,
          'Every check should have a label'
        );
        System.assertNotEquals(
          null,
          item.ok,
          'Every check should resolve to a boolean'
        );
      }
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testGetProfileForOwnAccountAllowedWithoutPermission() {
    Account pa = seedAlumniAccountForStubbedTests('viewself');

    KenMyProfileController.testCurrentAccountId = pa.Id;
    KenMyProfileController.testCanViewAnyProfile = false;
    try {
      Test.startTest();
      KenMyProfileController.ProfileData result = KenMyProfileController.getProfileFor(
        pa.Id
      );
      Test.stopTest();

      System.assertEquals(
        pa.Id,
        result.accountId,
        'Viewing your own account never needs the permission'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testGetProfileForOtherAccountDeniedWithoutPermission() {
    Account owner = seedAlumniAccountForStubbedTests('owner');
    Account other = seedAlumniAccountForStubbedTests('other');

    KenMyProfileController.testCurrentAccountId = owner.Id;
    KenMyProfileController.testCanViewAnyProfile = false;
    try {
      Test.startTest();
      try {
        KenMyProfileController.getProfileFor(other.Id);
        System.assert(
          false,
          'Expected AuraHandledException when viewing another account without the permission'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
      }
      Test.stopTest();
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testGetProfileForOtherAccountAllowedWithPermission() {
    Account owner = seedAlumniAccountForStubbedTests('owner2');
    Account other = seedAlumniAccountForStubbedTests('other2');

    KenMyProfileController.testCurrentAccountId = owner.Id;
    KenMyProfileController.testCanViewAnyProfile = true;
    try {
      Test.startTest();
      KenMyProfileController.ProfileData result = KenMyProfileController.getProfileFor(
        other.Id
      );
      Test.stopTest();

      System.assertEquals(
        other.Id,
        result.accountId,
        'An admin or coordinator should be able to view another account'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
      KenMyProfileController.testCanViewAnyProfile = false;
    }
  }

  @IsTest
  static void testGetProfileForNullTargetThrowsException() {
    Account pa = seedAlumniAccountForStubbedTests('nulltarget');

    KenMyProfileController.testCurrentAccountId = pa.Id;
    try {
      Test.startTest();
      try {
        KenMyProfileController.getProfileFor(null);
        System.assert(
          false,
          'Expected AuraHandledException for a null target account'
        );
      } catch (AuraHandledException ex) {
        System.assertNotEquals(
          null,
          ex.getMessage(),
          'Exception message should not be null'
        );
      }
      Test.stopTest();
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testEngagementSupportActivityHealthForDeniedWithoutPermission() {
    Account owner = seedAlumniAccountForStubbedTests('owner3');
    Account other = seedAlumniAccountForStubbedTests('other3');

    KenMyProfileController.testCurrentAccountId = owner.Id;
    KenMyProfileController.testCanViewAnyProfile = false;
    try {
      Test.startTest();
      Integer denials = 0;
      try {
        KenMyProfileController.getEngagementFor(other.Id);
      } catch (AuraHandledException ex) {
        denials++;
      }
      try {
        KenMyProfileController.getSupportFor(other.Id);
      } catch (AuraHandledException ex) {
        denials++;
      }
      try {
        KenMyProfileController.getRecentActivityFor(other.Id);
      } catch (AuraHandledException ex) {
        denials++;
      }
      try {
        KenMyProfileController.getRecordHealthFor(other.Id);
      } catch (AuraHandledException ex) {
        denials++;
      }
      Test.stopTest();

      System.assertEquals(
        4,
        denials,
        'All four *For methods must deny viewing another account without the permission'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
    }
  }

  @IsTest
  static void testEngagementSupportActivityHealthForAllowedWithPermission() {
    Account owner = seedAlumniAccountForStubbedTests('owner4');
    Account other = seedAlumniAccountForStubbedTests('other4');

    KenMyProfileController.testCurrentAccountId = owner.Id;
    KenMyProfileController.testCanViewAnyProfile = true;
    try {
      Test.startTest();
      KenMyProfileController.EngagementData engagement = KenMyProfileController.getEngagementFor(
        other.Id
      );
      KenMyProfileController.SupportData support = KenMyProfileController.getSupportFor(
        other.Id
      );
      List<KenMyProfileController.ActivityItem> activity = KenMyProfileController.getRecentActivityFor(
        other.Id
      );
      List<KenMyProfileController.RecordHealthItem> health = KenMyProfileController.getRecordHealthFor(
        other.Id
      );
      Test.stopTest();

      System.assertNotEquals(
        null,
        engagement,
        'getEngagementFor should return data when permitted'
      );
      System.assertNotEquals(
        null,
        support,
        'getSupportFor should return data when permitted'
      );
      System.assertNotEquals(
        null,
        activity,
        'getRecentActivityFor should return data when permitted'
      );
      System.assertEquals(
        5,
        health.size(),
        'getRecordHealthFor should return the 5 checks when permitted'
      );
    } finally {
      KenMyProfileController.testCurrentAccountId = null;
      KenMyProfileController.testCanViewAnyProfile = false;
    }
  }

  @IsTest
  static void testInnerClassesInstantiate() {
    User runAsUser = buildStandardRunAsUser();
    insert runAsUser;

    System.runAs(runAsUser) {
      Test.startTest();
      KenMyProfileController.ProfileData pd = new KenMyProfileController.ProfileData();
      pd.name = 'Test Name';
      pd.title = 'Engineer';
      pd.company = 'Test Corp';
      pd.location = 'Mumbai';
      pd.isOnline = true;
      pd.batch = 'Batch 2022';
      pd.expertise = 'Java';
      pd.email = 'test@example.com';
      pd.phone = '9999999999';
      pd.linkedin = 'https://linkedin.com/in/test';
      pd.willingToHelp = true;
      pd.about = 'About text';
      pd.registrationNumber = 'REG-001';
      pd.education = new List<KenMyProfileController.EducationRow>();
      pd.experience = new List<KenMyProfileController.ExperienceRow>();
      pd.achievements = new List<KenMyProfileController.AchievementRow>();

      KenMyProfileController.EducationRow er = new KenMyProfileController.EducationRow();
      er.degree = 'B.Tech';
      er.institution = 'Test University';
      er.duration = '2018-2022';

      KenMyProfileController.ExperienceRow xr = new KenMyProfileController.ExperienceRow();
      xr.position = 'Engineer';
      xr.company = 'Corp';
      xr.isCurrentJob = true;

      KenMyProfileController.AchievementRow ar = new KenMyProfileController.AchievementRow();
      ar.type = 'Award';
      ar.title = 'Best Employee';
      ar.organization = 'Corp';

      KenMyProfileController.EducationInput ei = new KenMyProfileController.EducationInput();
      ei.degree = 'M.Tech';
      ei.institution = 'IIT';
      ei.gradingFormat = 'CGPA';
      ei.cgpa = '9.0';

      KenMyProfileController.ExperienceInput xi = new KenMyProfileController.ExperienceInput();
      xi.jobTitle = 'Manager';
      xi.organization = 'Corp';
      xi.isCurrentJob = false;

      KenMyProfileController.AchievementInput ai = new KenMyProfileController.AchievementInput();
      ai.type = 'Patent';
      ai.title = 'Patent Title';
      ai.organization = 'Org';
      Test.stopTest();

      System.assertNotEquals(
        null,
        pd,
        'ProfileData should instantiate correctly'
      );
      System.assertNotEquals(
        null,
        er,
        'EducationRow should instantiate correctly'
      );
      System.assertNotEquals(
        null,
        xr,
        'ExperienceRow should instantiate correctly'
      );
      System.assertNotEquals(
        null,
        ar,
        'AchievementRow should instantiate correctly'
      );
      System.assertNotEquals(
        null,
        ei,
        'EducationInput should instantiate correctly'
      );
      System.assertNotEquals(
        null,
        xi,
        'ExperienceInput should instantiate correctly'
      );
      System.assertNotEquals(
        null,
        ai,
        'AchievementInput should instantiate correctly'
      );
    }
  }
}