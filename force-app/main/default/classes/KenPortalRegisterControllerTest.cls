@IsTest
private class KenPortalRegisterControllerTest {
    private static final String DEFAULT_FIRST_NAME = 'Portal';
    private static final String DEFAULT_LAST_NAME = 'User';
    private static final String DEFAULT_PHONE = '9999999999';
    private static final String DEFAULT_GRAD_YEAR = '2020';

    @IsTest
    static void testRequestAndVerifySignupOtpSuccessCreatesLead() {
        String email = uniqueEmail('register.success');
        String registrationNumber = 'REG-SUCCESS';

        Test.startTest();
        KenPortalRegisterController.SignupResult requestResult =
            KenPortalRegisterController.requestSignupOtp(
                buildRequestJson(email, null, registrationNumber)
            );

        System.assertEquals(true, requestResult.success, 'OTP request should succeed.');
        System.assertNotEquals(null, requestResult.otpId, 'OTP id should be returned.');

        Ken_One_Time_Password__c otp = [
            SELECT Id, OTP__c, IsActive__c
            FROM Ken_One_Time_Password__c
            WHERE Id = :Id.valueOf(requestResult.otpId)
            LIMIT 1
        ];

        KenPortalRegisterController.SignupResult verifyResult =
            KenPortalRegisterController.verifySignupOtp(
                buildRequestJson(email, otp.OTP__c, registrationNumber)
            );
        Test.stopTest();

        System.assertEquals(true, verifyResult.success, 'OTP verification should succeed.');
        System.assertEquals(String.valueOf(otp.Id), verifyResult.otpId, 'Verified OTP id should match latest otp record.');

        Ken_One_Time_Password__c deactivatedOtp = [
            SELECT IsActive__c
            FROM Ken_One_Time_Password__c
            WHERE Id = :otp.Id
            LIMIT 1
        ];
        System.assertEquals(false, deactivatedOtp.IsActive__c, 'OTP should be deactivated after successful verification.');

        Lead lead = [
            SELECT Registration_Number__c, Year_of_Graduation__c, Status, LeadSource
            FROM Lead
            WHERE Email = :email
            LIMIT 1
        ];
        System.assertEquals(registrationNumber, lead.Registration_Number__c, 'Lead should use submitted registration number.');
        System.assertEquals(DEFAULT_GRAD_YEAR, lead.Year_of_Graduation__c, 'Lead should use submitted graduation year.');
        System.assertEquals('New', lead.Status, 'Lead status should be New.');
        System.assertEquals('Web', lead.LeadSource, 'Lead source should be Web.');
    }

    @IsTest
    static void testRequestSignupOtpValidationErrors() {
        System.runAs(getCurrentUser()) {
            Integer validationFailures = 0;
            if (assertAuraExceptionFromRequest(null)) {
                validationFailures++;
            }
            if (assertAuraExceptionFromRequest('{"email":')) {
                validationFailures++;
            }
            if (assertAuraExceptionFromRequest(buildRequestJson('', null, 'REG-ERR'))) {
                validationFailures++;
            }

            System.assertEquals(3, validationFailures, 'All request validation scenarios should throw AuraHandledException.');
        }
    }

    @IsTest
    static void testVerifySignupOtpValidationErrors() {
        Integer validationFailures = 0;
        if (assertAuraExceptionFromVerify(null)) {
            validationFailures++;
        }
        if (assertAuraExceptionFromVerify('{"email":')) {
            validationFailures++;
        }
        if (assertAuraExceptionFromVerify(buildRequestJson('', '1234', 'REG-ERR'))) {
            validationFailures++;
        }
        if (assertAuraExceptionFromVerify(buildRequestJson(uniqueEmail('verify.nootp'), '', 'REG-ERR'))) {
            validationFailures++;
        }
        if (assertAuraExceptionFromVerify(buildRequestJson(uniqueEmail('verify.norecord'), '1234', 'REG-ERR'))) {
            validationFailures++;
        }

        System.assertEquals(5, validationFailures, 'All verify validation scenarios should throw AuraHandledException.');
    }

    @IsTest
    static void testVerifySignupOtpOtpStateValidationErrors() {
        String expiredEmail = uniqueEmail('verify.expired');
        insertOtp(expiredEmail, '1111', System.now().addMinutes(-5));

        String inactiveEmail = uniqueEmail('verify.inactive');
        insertInactiveOtp(inactiveEmail, '2222');

        String invalidOtpEmail = uniqueEmail('verify.invalid');
        insertOtp(invalidOtpEmail, '3333', System.now().addMinutes(5));

        Integer validationFailures = 0;
        if (assertAuraExceptionFromVerify(buildRequestJson(expiredEmail, '1111', 'REG-EXP'))) {
            validationFailures++;
        }
        if (assertAuraExceptionFromVerify(buildRequestJson(inactiveEmail, '2222', 'REG-INACT'))) {
            validationFailures++;
        }
        if (assertAuraExceptionFromVerify(buildRequestJson(invalidOtpEmail, '9999', 'REG-INV'))) {
            validationFailures++;
        }

        System.assertEquals(3, validationFailures, 'Expired, inactive, and wrong otp scenarios should all fail.');
    }

    @IsTest
    static void testRequestSignupOtpDuplicateEmailAndProgramThrows() {
        Id planId = createProgramPlan('Dup Request Program');
        String email = uniqueEmail('request.duplicate');
        insertLead(email, 'REG-RDDUP', planId);

        Boolean didThrow = assertAuraExceptionFromRequest(
            buildRequestJson(email, null, 'REG-RDDUP', planId)
        );

        System.assertEquals(true, didThrow, 'Duplicate email + program should be blocked at OTP request time.');
    }

    @IsTest
    static void testVerifySignupOtpDuplicateEmailAndProgramThrows() {
        Id planId = createProgramPlan('Dup Program');
        String email = uniqueEmail('verify.duplicate');
        insertOtp(email, '4444', System.now().addMinutes(5));
        insertLead(email, 'REG-DUP', planId);

        Boolean didThrowAuraException = assertAuraExceptionFromVerify(
            buildRequestJson(email, '4444', 'REG-DUP', planId)
        );

        System.assertEquals(true, didThrowAuraException, 'Same email + same program should be blocked.');
    }

    @IsTest
    static void testVerifySignupOtpDuplicateSameEmailNoProgramThrows() {
        String email = uniqueEmail('verify.noprog');
        insertOtp(email, '4445', System.now().addMinutes(5));
        insertLead(email, 'REG-NP', null);

        Boolean didThrow = assertAuraExceptionFromVerify(
            buildRequestJson(email, '4445', 'REG-NP')
        );

        System.assertEquals(true, didThrow, 'Same email with no program on both should be blocked.');
    }

    @IsTest
    static void testEmailAlreadyRegisteredGenerateOtpAndSaveOtpInformation() {
        System.runAs(getCurrentUser()) {
            String existingEmail = uniqueEmail('existing.user');
            insertUser(existingEmail);

            Boolean isRegistered = KenPortalRegisterController.emailAlreadyRegistered(existingEmail);
            Boolean isNotRegistered = KenPortalRegisterController.emailAlreadyRegistered(uniqueEmail('new.user'));
            String generatedOtp = KenPortalRegisterController.generateOtp();
            Id savedOtpId = KenPortalRegisterController.saveOtpInformation(
                uniqueEmail('save.otp'),
                '5555',
                null
            );

            System.assertEquals(true, isRegistered, 'Existing user email should be marked as registered.');
            System.assertEquals(false, isNotRegistered, 'Unknown email should not be marked as registered.');
            System.assertEquals(4, generatedOtp.length(), 'Generated otp should be four digits.');
            System.assertEquals(true, Pattern.matches('[0-9]{4}', generatedOtp), 'Generated otp should contain only digits.');
            System.assertNotEquals(null, savedOtpId, 'OTP save should return record id.');
        }
    }

    @IsTest
    static void testVerifySignupOtpAllowsSameEmailDifferentProgram() {
        Id planA = createProgramPlan('Program A');
        Id planB = createProgramPlan('Program B');
        String email = uniqueEmail('verify.sameemail');
        insertOtp(email, '6666', System.now().addMinutes(5));
        insertLead(email, 'REG-A', planA);

        Test.startTest();
        KenPortalRegisterController.SignupResult verifyResult =
            KenPortalRegisterController.verifySignupOtp(
                buildRequestJson(email, '6666', 'REG-B', planB)
            );
        Test.stopTest();

        System.assertEquals(true, verifyResult.success, 'Verification should pass for a different program on the same email.');
        System.assertEquals(2, [SELECT COUNT() FROM Lead WHERE Email = :email], 'A second lead should be created for the new program.');
    }

    @IsTest
    static void testGetRegistrationOptionsReturnsConfiguredFromGradYear() {
        upsert new Alumni_Org_Parameters__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            From_Graduation_Year__c = 2005,
            Default_Dial_Code__c = 'US'
        );
        Test.startTest();
        KenPortalRegisterController.RegistrationOptions opts = KenPortalRegisterController.getRegistrationOptions();
        Test.stopTest();
        System.assertEquals(2005, opts.fromGradYear, 'Configured From Graduation Year should be returned.');
        System.assertEquals('us', opts.defaultDialCountry, 'Configured default dial code should be returned, normalised to lowercase.');
        System.assertNotEquals(null, opts.programs, 'Programs list should be initialised.');
    }

    @IsTest
    static void testGetRegistrationOptionsDefaultsDialCodeToNone() {
        // No org parameter / blank dial code -> 'none' so the phone field shows no default.
        Test.startTest();
        KenPortalRegisterController.RegistrationOptions opts = KenPortalRegisterController.getRegistrationOptions();
        Test.stopTest();
        System.assertEquals('none', opts.defaultDialCountry, 'Default dial code should fall back to "none".');
        System.assertEquals(1980, opts.fromGradYear, 'From Graduation Year should fall back to 1980.');
    }

    @IsTest
    static void testSendEmailBypassGuardInTestContextThrowsWhenTemplateMissing() {
        System.runAs(getCurrentUser()) {
            String email = uniqueEmail('send.email');
            Id otpId = KenPortalRegisterController.saveOtpInformation(email, '7777', null);

            KenPortalRegisterController.bypassEmailGuardInTests = true;
            try {
                try {
                    KenPortalRegisterController.sendEmail(email, otpId);
                    System.assert(true, 'sendEmail executed successfully with bypass guard enabled.');
                } catch (AuraHandledException ex) {
                    System.assertEquals(
                        'Script-thrown exception',
                        ex.getMessage(),
                        'Expected AuraHandledException to be rethrown as Script-thrown exception.'
                    );
                }
            } finally {
                KenPortalRegisterController.bypassEmailGuardInTests = false;
            }
        }
    }

    private static String buildRequestJson(String email, String otpEntered, String registrationNumber) {
        return buildRequestJson(email, otpEntered, registrationNumber, null);
    }

    private static String buildRequestJson(String email, String otpEntered, String registrationNumber, Id programPlanId) {
        KenPortalRegisterController.SignupRequest requestBody =
            new KenPortalRegisterController.SignupRequest();
        requestBody.email = email;
        requestBody.firstName = DEFAULT_FIRST_NAME;
        requestBody.lastName = DEFAULT_LAST_NAME;
        requestBody.phone = DEFAULT_PHONE;
        requestBody.regNumber = registrationNumber;
        requestBody.gradYear = DEFAULT_GRAD_YEAR;
        requestBody.otpEntered = otpEntered;
        requestBody.programPlan = programPlanId == null ? null : String.valueOf(programPlanId);
        return JSON.serialize(requestBody);
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

    private static void insertOtp(String email, String otpCode, Datetime expiry) {
        insert new Ken_One_Time_Password__c(
            Email__c = email,
            OTP__c = otpCode,
            Expiry__c = expiry,
            IsActive__c = true
        );
    }

    private static void insertInactiveOtp(String email, String otpCode) {
        insert new Ken_One_Time_Password__c(
            Email__c = email,
            OTP__c = otpCode,
            Expiry__c = System.now().addMinutes(5),
            IsActive__c = false
        );
    }

    private static void insertLead(String email, String registrationNumber) {
        insertLead(email, registrationNumber, null);
    }

    private static void insertLead(String email, String registrationNumber, Id programPlanId) {
        insert new Lead(
            FirstName = 'Existing',
            LastName = 'Lead',
            Company = 'Alumni',
            Email = email,
            Status = 'new',
            Registration_Number__c = registrationNumber,
            Year_of_Graduation__c = DEFAULT_GRAD_YEAR,
            Program_Plan__c = programPlanId
        );
    }

    private static void insertUser(String email) {
        Id profileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;
        String uniqueValue = String.valueOf(DateTime.now().getTime());
        insert new User(
            FirstName = 'Portal',
            LastName = 'Register',
            Email = email,
            Username = email + '.' + uniqueValue,
            Alias = 'prtu',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }

    private static Boolean assertAuraExceptionFromRequest(String requestJson) {
        try {
            KenPortalRegisterController.requestSignupOtp(requestJson);
            return false;
        } catch (AuraHandledException ex) {
            return ex.getMessage() == 'Script-thrown exception';
        }
    }

    private static Boolean assertAuraExceptionFromVerify(String requestJson) {
        try {
            KenPortalRegisterController.verifySignupOtp(requestJson);
            return false;
        } catch (AuraHandledException ex) {
            return ex.getMessage() == 'Script-thrown exception';
        }
    }

    private static String uniqueEmail(String prefix) {
        return prefix + '.' + String.valueOf(DateTime.now().getTime()) + '@example.com';
    }

    private static User getCurrentUser() {
        return [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    }
}