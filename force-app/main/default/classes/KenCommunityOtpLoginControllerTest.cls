@IsTest(IsParallel=false)
private class KenCommunityOtpLoginControllerTest {
    private static final String KNOWN_EMAIL = 'otp.alumni@example.com';
    private static final String UNKNOWN_EMAIL = 'nobody.otp@example.com';

    /**
     * @description Builds an in-memory User carrying the read-only verification
     *              flags. HasUserVerifiedEmail / HasUserVerifiedPhone are not
     *              writeable, so they can only be set by deserialization.
     */
    private static User userWith(Boolean verifiedEmail, Boolean verifiedPhone, String mobile) {
        Map<String, Object> raw = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => 'User' },
            'Email' => KNOWN_EMAIL,
            'Username' => KNOWN_EMAIL + '.alumni',
            'HasUserVerifiedEmail' => verifiedEmail,
            'HasUserVerifiedPhone' => verifiedPhone
        };
        if (String.isNotBlank(mobile)) {
            raw.put('MobilePhone', mobile);
        }
        return (User) JSON.deserialize(JSON.serialize(raw), User.class);
    }

    private static void setChannel(String channel) {
        Ken_Alm_Org_Parameters__c cs = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        cs.SetupOwnerId = UserInfo.getOrganizationId();
        cs.OTP_Delivery_Channel__c = channel;
        upsert cs;
    }

    /**
     * @description A throwaway internal user to run the signed-in settings paths as, with or
     *              without a mobile number. These tests used to edit the running user's own
     *              record, and saveMobileNumber still writes to whoever is signed in; that row is
     *              shared with every other test class in the run, so whichever transaction got
     *              there second died with UNABLE_TO_LOCK_ROW. Inserted under runAs so the User
     *              DML never mixes with the custom-setting writes.
     */
    private static User internalUser(String mobile) {
        User signingIn = new User(
            Username          = 'otp.settings.' + System.currentTimeMillis() + '.'
                                + Math.abs(Crypto.getRandomInteger()) + '@kenotp.test',
            Email             = 'otp.settings@kenotp.test',
            LastName          = 'OtpSettings',
            Alias             = 'otpsttng',
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = UserInfo.getProfileId(),
            MobilePhone       = mobile
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert signingIn;
        }
        return signingIn;
    }

    @IsTest
    static void resolveContextRejectsBlankIdentifier() {
        KenCommunityOtpLoginController.OtpLoginContextResult res =
            KenCommunityOtpLoginController.resolveOtpLoginContext('   ', 'Email');

        System.assertEquals(false, res.success, 'Blank identifier must not resolve.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_MISSING_IDENTIFIER,
            res.message,
            'Blank identifier should ask for an email address.'
        );
    }

    @IsTest
    static void resolveContextReportsUnknownEmail() {
        KenCommunityOtpLoginController.OtpLoginContextResult res =
            KenCommunityOtpLoginController.resolveOtpLoginContext(UNKNOWN_EMAIL, 'Email');

        System.assertEquals(false, res.success, 'Unknown email must not resolve.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_USER_NOT_FOUND,
            res.message,
            'Unknown email should report account not found.'
        );
        System.assertEquals(true, res.availableChannels.isEmpty(), 'No channels for an unresolved alumnus.');
    }

    @IsTest
    static void emailChannelOfferedWhenOnlyEmailVerified() {
        setChannel('Both');

        List<String> channels = KenCommunityOtpLoginController.resolveAvailableChannels(
            userWith(true, false, null)
        );

        System.assertEquals(1, channels.size(), 'Only the email channel should be offered.');
        System.assertEquals('Email', channels[0], 'Email must be the offered channel.');
    }

    @IsTest
    static void aRegisteredPhoneStillLeavesEmailOnOffer() {
        setChannel('Both');

        List<String> channels = KenCommunityOtpLoginController.resolveAvailableChannels(
            userWith(true, true, '+91 9731456123')
        );

        System.assertEquals(true, channels.contains('Email'),
            'Choosing email must send an email — a registered phone no longer hides the option.');
        System.assertEquals(true, channels.contains('SMS'), 'SMS must remain available.');
    }

    @IsTest
    static void smsNeedsAStoredNumberOnTheUser() {
        setChannel('Both');

        System.assertEquals(
            true,
            KenCommunityOtpLoginController.resolveAvailableChannels(userWith(false, true, null)).isEmpty(),
            'A verified phone flag without a stored number is not usable.'
        );
        System.assertEquals(
            new List<String>{ 'SMS' },
            KenCommunityOtpLoginController.resolveAvailableChannels(userWith(false, false, '+91 9731456123')),
            'A stored number is offered even before the platform has flagged it verified — gating on '
            + 'the flag offered SMS to nobody, and the platform still refuses an unregistered number.'
        );
    }

    @IsTest
    static void unavailableChannelExplainsItself() {
        setChannel('Both');

        User emailUnverified = userWith(false, false, null);
        User noMobile = userWith(true, false, null);

        System.assertEquals(
            KenCommunityOtpLoginController.MSG_EMAIL_NOT_VERIFIED,
            KenCommunityOtpLoginController.channelUnavailableReason(emailUnverified, 'Email'),
            'An unverified email address is something the alumnus can act on.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_NO_MOBILE_ON_FILE,
            KenCommunityOtpLoginController.channelUnavailableReason(noMobile, 'SMS'),
            'No stored number is the reason SMS is missing.'
        );

        setChannel('Email');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_METHOD_NOT_ENABLED,
            KenCommunityOtpLoginController.channelUnavailableReason(noMobile, 'SMS'),
            'An email-only org must say the method is off, not blame the alumnus.'
        );
    }

    @IsTest
    static void contextExplainsWhyTheChosenChannelIsMissing() {
        Account acc = createPortalAlumnus();
        if (acc == null) {
            return;
        }
        setChannel('Both');
        // Only SMS on offer, but the alumnus picked email.
        KenCommunityOtpLoginController.testChannelOverride = new List<String>{ 'SMS' };

        KenCommunityOtpLoginController.OtpLoginContextResult res =
            KenCommunityOtpLoginController.resolveOtpLoginContext(KNOWN_EMAIL, 'Email');

        System.assertEquals(true, res.success, 'The alumnus resolved, so this is still a success.');
        System.assertNotEquals(
            null,
            res.message,
            'A reason must be returned, or the login page falls back to "Please choose another option".'
        );
    }

    @IsTest
    static void platformRefusalDoesNotInviteARetry() {
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_OTP_SIGNIN_BLOCKED,
            KenCommunityOtpLoginController.friendlySendError(
                new KenCustomException('System.SecurityException: We can\'t log in the user. Please contact your administrator.')
            ),
            'Retrying can never fix passwordless being switched off, so must not say "try again".'
        );
    }

    @IsTest
    static void orgConfigNarrowsAvailableChannels() {
        setChannel('Email');
        System.assertEquals(
            new List<String>{ 'Email' },
            KenCommunityOtpLoginController.resolveAvailableChannels(userWith(true, true, '+91 9731456123')),
            'An email-only org offers email alone, even to an alumnus with a registered phone.'
        );

        setChannel('SMS');
        System.assertEquals(
            true,
            KenCommunityOtpLoginController.resolveAvailableChannels(userWith(true, false, null)).isEmpty(),
            'An SMS-only org must not offer the email channel.'
        );
    }

    @IsTest
    static void nullUserYieldsNoChannels() {
        System.assertEquals(
            true,
            KenCommunityOtpLoginController.resolveAvailableChannels(null).isEmpty(),
            'A null user must yield no channels.'
        );
    }

    @IsTest
    static void channelNormalizationFallsBackToEmail() {
        System.assertEquals('Email', KenCommunityOtpLoginController.normalizeChannel(null), 'Blank means email.');
        System.assertEquals('Email', KenCommunityOtpLoginController.normalizeChannel('nonsense'), 'Unknown means email.');
        System.assertEquals('SMS', KenCommunityOtpLoginController.normalizeChannel(' sms '), 'SMS is recognised.');
        System.assertEquals('Both', KenCommunityOtpLoginController.normalizeChannel('both'), 'Both is recognised.');
    }

    @IsTest
    static void configuredChannelDefaultsToEmailWhenUnset() {
        System.assertEquals(
            'Email',
            KenCommunityOtpLoginController.configuredChannel(),
            'An unconfigured org must default to email.'
        );

        setChannel('SMS');
        System.assertEquals(
            'SMS',
            KenCommunityOtpLoginController.configuredChannel(),
            'The configured channel should be honoured.'
        );
    }

    @IsTest
    static void verificationMethodMapsFromChannel() {
        System.assertEquals(
            Auth.VerificationMethod.SMS,
            KenCommunityOtpLoginController.toVerificationMethod('SMS'),
            'SMS must map to the SMS verification method.'
        );
        System.assertEquals(
            Auth.VerificationMethod.EMAIL,
            KenCommunityOtpLoginController.toVerificationMethod('Email'),
            'Email must map to the email verification method.'
        );
    }

    @IsTest
    static void inactiveAlumniAreBlockedAndEmptyAccountsFailOpen() {
        Account inactive = new Account(Name = 'Inactive OTP Alumni');
        insert inactive;
        insert new ConstituentRole(PersonId = inactive.Id, RoleType = 'Alumni', Status = 'Former');

        System.assertEquals(
            false,
            KenCommunityOtpLoginController.isAlumniRoleActive(inactive.Id),
            'An alumnus whose only Alumni role is Former must be blocked.'
        );

        Account active = new Account(Name = 'Active OTP Alumni');
        insert active;
        insert new ConstituentRole(PersonId = active.Id, RoleType = 'Alumni', Status = 'Active');

        System.assertEquals(
            true,
            KenCommunityOtpLoginController.isAlumniRoleActive(active.Id),
            'A non-Former Alumni role must allow OTP login.'
        );

        Account noRows = new Account(Name = 'No CRM Rows');
        insert noRows;
        System.assertEquals(
            true,
            KenCommunityOtpLoginController.isAlumniRoleActive(noRows.Id),
            'Accounts with no CRM rows must fail open.'
        );
        System.assertEquals(
            true,
            KenCommunityOtpLoginController.isAlumniRoleActive(null),
            'A null account must fail open.'
        );
    }

    @IsTest
    static void startUrlSanitizerBlocksOffSiteAndLoginTargets() {
        Account acc = new Account(Name = 'Start Url Alumni');
        insert acc;
        String expected = '/alumni/select-role?accountId=' + acc.Id;

        System.assertEquals(
            expected,
            KenCommunityOtpLoginController.sanitizeStartUrl('https://evil.example.com', acc.Id),
            'Absolute URLs must be rejected.'
        );
        System.assertEquals(
            expected,
            KenCommunityOtpLoginController.sanitizeStartUrl('//evil.example.com', acc.Id),
            'Protocol-relative URLs must be rejected.'
        );
        System.assertEquals(
            expected,
            KenCommunityOtpLoginController.sanitizeStartUrl('/alumni/login', acc.Id),
            'Redirecting back to login must be rejected.'
        );
        System.assertEquals(
            expected,
            KenCommunityOtpLoginController.sanitizeStartUrl(null, acc.Id),
            'A blank start URL must fall back to role selection.'
        );
        System.assertEquals(
            '/alumni/my-profile',
            KenCommunityOtpLoginController.sanitizeStartUrl('/alumni/my-profile', acc.Id),
            'A site-relative path must be preserved.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.DEFAULT_START_URL,
            KenCommunityOtpLoginController.sanitizeStartUrl(null, null),
            'Without an account the portal home is the fallback.'
        );
    }

    @IsTest
    static void maskingHidesMostOfTheIdentifier() {
        System.assertEquals(
            'jo•••@example.com',
            KenCommunityOtpLoginController.maskEmail('john.doe@example.com'),
            'Email masking should keep two leading characters and the domain.'
        );
        System.assertEquals(
            'a•••@example.com',
            KenCommunityOtpLoginController.maskEmail('a@example.com'),
            'Very short local parts keep one character.'
        );
        System.assertEquals(null, KenCommunityOtpLoginController.maskEmail('not-an-email'), 'Non-emails mask to null.');
        System.assertEquals(null, KenCommunityOtpLoginController.maskEmail(null), 'Blank emails mask to null.');

        System.assertEquals(
            '••••••6123',
            KenCommunityOtpLoginController.maskPhone('+91 9731456123'),
            'Phone masking should reveal only the last four digits.'
        );
        System.assertEquals('••••••123', KenCommunityOtpLoginController.maskPhone('123'), 'Short numbers are kept whole.');
        System.assertEquals(null, KenCommunityOtpLoginController.maskPhone('abc'), 'Digitless input masks to null.');
        System.assertEquals(null, KenCommunityOtpLoginController.maskPhone(null), 'Blank phones mask to null.');
    }

    @IsTest
    static void sendOtpRejectsUnresolvableAccount() {
        KenCommunityOtpLoginController.SendOtpResult res =
            KenCommunityOtpLoginController.sendLoginOtp('not-an-id', 'Email');

        System.assertEquals(false, res.success, 'A malformed account id must not send an OTP.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_USER_NOT_FOUND,
            res.message,
            'A malformed account id should report account not found.'
        );

        KenCommunityOtpLoginController.SendOtpResult blank =
            KenCommunityOtpLoginController.sendLoginOtp(null, 'Email');
        System.assertEquals(false, blank.success, 'A blank account id must not send an OTP.');
    }

    @IsTest
    static void sendOtpRejectsAccountWithoutPortalUser() {
        Account acc = new Account(Name = 'No Portal User Alumni');
        insert acc;

        KenCommunityOtpLoginController.SendOtpResult res =
            KenCommunityOtpLoginController.sendLoginOtp(String.valueOf(acc.Id), 'Email');

        System.assertEquals(false, res.success, 'An account with no portal user cannot receive an OTP.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_USER_NOT_FOUND,
            res.message,
            'The alumnus should be reported as not found.'
        );
    }

    @IsTest
    static void verifyOtpRequiresIdentifierAndCode() {
        KenCommunityOtpLoginController.VerifyOtpResult noIdentifier =
            KenCommunityOtpLoginController.verifyLoginOtp('001000000000000', 'Email', '', '1234', null);
        System.assertEquals(false, noIdentifier.success, 'A missing challenge id must fail.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_SESSION_LOST,
            noIdentifier.message,
            'A missing challenge id should ask for a new code.'
        );

        KenCommunityOtpLoginController.VerifyOtpResult noCode =
            KenCommunityOtpLoginController.verifyLoginOtp('001000000000000', 'Email', 'IDENTIFIER', '  ', null);
        System.assertEquals(false, noCode.success, 'A missing code must fail.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_VERIFY_FAILED,
            noCode.message,
            'A missing code should report an invalid OTP.'
        );
    }

    @IsTest
    static void verifyOtpRejectsUnresolvableAccount() {
        KenCommunityOtpLoginController.VerifyOtpResult res =
            KenCommunityOtpLoginController.verifyLoginOtp('not-an-id', 'Email', 'IDENTIFIER', '1234', null);

        System.assertEquals(false, res.success, 'A malformed account id must not verify.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_USER_NOT_FOUND,
            res.message,
            'A malformed account id should report account not found.'
        );
    }

    @IsTest
    static void eligibleUserLookupHandlesBadInput() {
        System.assertEquals(null, KenCommunityOtpLoginController.resolveEligibleUser(null), 'Blank id yields no user.');
        System.assertEquals(
            null,
            KenCommunityOtpLoginController.resolveEligibleUser('not-an-id'),
            'A malformed id yields no user.'
        );
    }

    @IsTest
    static void emailLookupHandlesBlankAndUnmatchedInput() {
        System.assertEquals(
            null,
            KenCommunityOtpLoginController.findPortalUserByEmail('   '),
            'A blank email matches nothing.'
        );
        System.assertEquals(
            null,
            KenCommunityOtpLoginController.findPortalUserByEmail(UNKNOWN_EMAIL),
            'An unmatched email matches nothing.'
        );
    }

    @IsTest
    static void constituentRoleFallbackIsSearched() {
        Account acc = new Account(Name = 'Role Fallback Alumni');
        insert acc;

        ConstituentRole role = new ConstituentRole(
            PersonId = acc.Id,
            Email__c = KNOWN_EMAIL,
            RoleType = 'Alumni'
        );
        try {
            insert role;
        } catch (Exception e) {
            return;
        }

        System.assertEquals(
            null,
            KenCommunityOtpLoginController.findPortalUserByEmail(KNOWN_EMAIL),
            'A role with no portal user still resolves to no user.'
        );
    }

    /**
     * @description Creates a portal user on the Alumni profile so the send and
     *              verify paths can resolve a real target. Returns null when the
     *              org can't support portal user creation in a test context, so
     *              the dependent tests skip instead of failing.
     */
    private static Account createPortalAlumnus() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Alumni' LIMIT 1];
        if (profiles.isEmpty()) {
            return null;
        }

        Account acc = new Account(Name = 'OTP Portal Alumni');
        Contact con;
        try {
            insert acc;
            con = new Contact(LastName = 'OTP Portal', AccountId = acc.Id, Email = KNOWN_EMAIL);
            insert con;
        } catch (Exception e) {
            return null;
        }

        User portalUser = new User(
            FirstName = 'OTP',
            LastName = 'Portal',
            Email = KNOWN_EMAIL,
            Username = 'otp.portal.' + DateTime.now().getTime() + '@example.com',
            Alias = 'otpp',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profiles[0].Id,
            ContactId = con.Id
        );
        try {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert portalUser;
            }
        } catch (Exception e) {
            return null;
        }
        return acc;
    }

    @IsTest
    static void contextResolvesWhenAChannelIsAvailable() {
        Account acc = createPortalAlumnus();
        if (acc == null) {
            return;
        }
        KenCommunityOtpLoginController.testChannelOverride = new List<String>{ 'Email', 'SMS' };

        KenCommunityOtpLoginController.OtpLoginContextResult res =
            KenCommunityOtpLoginController.resolveOtpLoginContext(KNOWN_EMAIL, 'Email');

        System.assertEquals(true, res.success, 'A portal alumnus with a channel must resolve.');
        System.assertEquals(String.valueOf(acc.Id), res.accountId, 'The resolved account should be returned.');
        System.assertEquals(2, res.availableChannels.size(), 'Both channels should be offered.');
        System.assertEquals('SMS', res.defaultChannel,
            'SMS is offered first when available — it is the branded channel and needs no prior verification.');
        System.assertNotEquals(null, res.maskedEmail, 'A masked email should be returned for the picker.');
    }

    @IsTest
    static void sendAndVerifyMintTheSessionOnTheHappyPath() {
        Account acc = createPortalAlumnus();
        if (acc == null) {
            return;
        }
        KenCommunityOtpLoginController.testChannelOverride = new List<String>{ 'Email' };

        KenCommunityOtpLoginController.SendOtpResult send =
            KenCommunityOtpLoginController.sendLoginOtp(String.valueOf(acc.Id), 'Email');

        System.assertEquals(true, send.success, 'The challenge should be issued.');
        System.assertEquals('TEST_IDENTIFIER', send.identifier, 'The platform challenge id should be returned.');
        System.assertEquals('Email', send.channel, 'The requested channel should be echoed back.');
        System.assertNotEquals(null, send.maskedTarget, 'The masked destination should be returned.');

        KenCommunityOtpLoginController.VerifyOtpResult verify = KenCommunityOtpLoginController.verifyLoginOtp(
            String.valueOf(acc.Id),
            'Email',
            send.identifier,
            ' 123456 ',
            '/alumni/'
        );

        System.assertEquals(true, verify.success, 'A valid code should mint a session.');
        System.assertEquals('/alumni/select-role', verify.redirectUrl, 'The platform redirect should be returned.');
        System.assertEquals(String.valueOf(acc.Id), verify.accountId, 'The account should be returned for the client.');
    }

    @IsTest
    static void sendReportsPlatformFailure() {
        Account acc = createPortalAlumnus();
        if (acc == null) {
            return;
        }
        KenCommunityOtpLoginController.testChannelOverride = new List<String>{ 'SMS' };
        KenCommunityOtpLoginController.testInitFail = true;

        KenCommunityOtpLoginController.SendOtpResult res =
            KenCommunityOtpLoginController.sendLoginOtp(String.valueOf(acc.Id), 'SMS');

        System.assertEquals(false, res.success, 'A platform failure must not report success.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_SEND_FAILED,
            res.message,
            'A platform failure should surface the generic send message.'
        );
    }

    @IsTest
    static void verifyReportsRejectedCode() {
        Account acc = createPortalAlumnus();
        if (acc == null) {
            return;
        }
        KenCommunityOtpLoginController.testChannelOverride = new List<String>{ 'Email' };
        KenCommunityOtpLoginController.testVerifySuccess = false;
        KenCommunityOtpLoginController.testVerifyMessage = 'Your verification code is incorrect.';

        KenCommunityOtpLoginController.VerifyOtpResult res = KenCommunityOtpLoginController.verifyLoginOtp(
            String.valueOf(acc.Id),
            'Email',
            'TEST_IDENTIFIER',
            '000000',
            null
        );

        System.assertEquals(false, res.success, 'A rejected code must not mint a session.');
        System.assertEquals(
            'Your verification code is incorrect.',
            res.message,
            'The platform message should be surfaced to the alumnus.'
        );
    }

    @IsTest
    static void unavailableChannelIsRejectedOnSendAndVerify() {
        Account acc = createPortalAlumnus();
        if (acc == null) {
            return;
        }
        KenCommunityOtpLoginController.testChannelOverride = new List<String>{ 'Email' };

        KenCommunityOtpLoginController.SendOtpResult send =
            KenCommunityOtpLoginController.sendLoginOtp(String.valueOf(acc.Id), 'SMS');
        System.assertEquals(false, send.success, 'An unavailable channel must be refused on send.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_METHOD_NOT_ENABLED,
            send.message,
            'The refusal should name the real reason: SMS is not switched on for this org.'
        );

        KenCommunityOtpLoginController.VerifyOtpResult verify = KenCommunityOtpLoginController.verifyLoginOtp(
            String.valueOf(acc.Id),
            'SMS',
            'TEST_IDENTIFIER',
            '123456',
            null
        );
        System.assertEquals(false, verify.success, 'An unavailable channel must be refused on verify.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_METHOD_NOT_ENABLED,
            verify.message,
            'The refusal should name the real reason: SMS is not switched on for this org.'
        );
    }

    @IsTest
    static void inactiveAlumnusIsBlockedAcrossAllEntryPoints() {
        Account acc = createPortalAlumnus();
        if (acc == null) {
            return;
        }
        List<ConstituentRole> alumniRoles = [
            SELECT Id FROM ConstituentRole WHERE PersonId = :acc.Id AND RoleType = 'Alumni'
        ];
        if (alumniRoles.isEmpty()) {
            insert new ConstituentRole(PersonId = acc.Id, RoleType = 'Alumni', Status = 'Former');
        } else {
            for (ConstituentRole existingRole : alumniRoles) {
                existingRole.Status = 'Former';
            }
            update alumniRoles;
        }
        KenCommunityOtpLoginController.testChannelOverride = new List<String>{ 'Email' };

        System.assertEquals(
            KenCommunityOtpLoginController.MSG_INACTIVE,
            KenCommunityOtpLoginController.resolveOtpLoginContext(KNOWN_EMAIL, 'Email').message,
            'A deactivated alumnus must not reach the OTP step.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_INACTIVE,
            KenCommunityOtpLoginController.sendLoginOtp(String.valueOf(acc.Id), 'Email').message,
            'A deactivated alumnus must not be sent a code.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_INACTIVE,
            KenCommunityOtpLoginController.verifyLoginOtp(
                String.valueOf(acc.Id), 'Email', 'TEST_IDENTIFIER', '123456', null
            ).message,
            'A deactivated alumnus must not be able to verify.'
        );
    }

    @IsTest
    static void contextReportsWhenNoChannelIsAvailable() {
        Account acc = createPortalAlumnus();
        if (acc == null) {
            return;
        }
        KenCommunityOtpLoginController.testChannelOverride = new List<String>();

        KenCommunityOtpLoginController.OtpLoginContextResult res =
            KenCommunityOtpLoginController.resolveOtpLoginContext(KNOWN_EMAIL, 'Email');

        System.assertEquals(false, res.success, 'No usable channel means OTP login is unavailable.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_NO_CHANNEL,
            res.message,
            'The alumnus should be pointed back at password login.'
        );
    }

    @IsTest
    static void statusReportsVerificationAndOrgChannels() {
        setChannel('Both');
        Ken_Alm_Org_Parameters__c cs = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        cs.Login_Method__c = 'Both';
        upsert cs;

        KenCommunityOtpLoginController.VerificationStatus status =
            KenCommunityOtpLoginController.getVerificationStatus();

        System.assertNotEquals(null, status, 'A status should always be returned for the running user.');
        System.assertEquals(true, status.emailChannelEnabled, 'A Both org offers the email channel.');
        System.assertEquals(true, status.smsChannelEnabled, 'A Both org offers the SMS channel.');
        System.assertEquals(true, status.otpLoginEnabled, 'A Both org runs OTP login.');

        cs.Login_Method__c = 'Password';
        cs.OTP_Delivery_Channel__c = 'Email';
        update cs;
        KenCommunityOtpLoginController.VerificationStatus passwordOnly =
            KenCommunityOtpLoginController.getVerificationStatus();
        System.assertEquals(false, passwordOnly.otpLoginEnabled, 'A password-only org does not run OTP login.');
        System.assertEquals(false, passwordOnly.smsChannelEnabled, 'An email-channel org does not offer SMS.');
    }

    @IsTest
    static void mobileNumberIsValidatedBeforeSaving() {
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_MOBILE_INVALID,
            KenCommunityOtpLoginController.saveMobileNumber('12345').message,
            'A short number must be rejected.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_MOBILE_INVALID,
            KenCommunityOtpLoginController.saveMobileNumber(null).message,
            'A blank number must be rejected.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_MOBILE_INVALID,
            KenCommunityOtpLoginController.saveMobileNumber('abcdefghij').message,
            'A number with no digits must be rejected.'
        );

        User signingIn = internalUser(null);
        KenCommunityOtpLoginController.VerificationStepResult saved;
        System.runAs(signingIn) {
            saved = KenCommunityOtpLoginController.saveMobileNumber('+91  97314  56123');
        }
        System.assertEquals(true, saved.success, 'A valid 10-digit number should save.');
        User me = [SELECT MobilePhone FROM User WHERE Id = :signingIn.Id LIMIT 1];
        System.assertEquals('+91 97314 56123', me.MobilePhone,
            'A number that already carries a country code is stored as given, with stray whitespace collapsed — '
            + 'the "+" is the only marker of where the country code ends, so regrouping the digits would destroy it.');
    }

    @IsTest
    static void verificationIsRefusedForAnUnsetMobile() {
        KenCommunityOtpLoginController.VerificationStepResult res;
        System.runAs(internalUser(null)) {
            res = KenCommunityOtpLoginController.startVerification('SMS');
        }

        System.assertEquals(false, res.success, 'SMS verification needs a stored number first.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_MOBILE_REQUIRED,
            res.message,
            'The alumnus should be asked to save a mobile number.'
        );
    }

    @IsTest
    static void verificationIssuesAnInPageCode() {
        KenCommunityOtpLoginController.VerificationStepResult res =
            KenCommunityOtpLoginController.startVerification('Email');

        if (res.success) {
            System.assertEquals(null, res.message, 'A successful send needs no error message.');
        } else {
            System.assertEquals(
                KenCommunityOtpLoginController.MSG_ALREADY_VERIFIED,
                res.message,
                'The only expected refusal here is an already-verified address.'
            );
        }
    }

    @IsTest
    static void inPageCodeConfirmationRegistersTheChannel() {
        System.assertEquals(
            true,
            KenCommunityOtpLoginController.confirmVerificationCode('Email', ' 123456 ').success,
            'A valid code should register the channel.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_VERIFY_FAILED,
            KenCommunityOtpLoginController.confirmVerificationCode('Email', '  ').message,
            'A blank code should report an invalid code.'
        );

        KenCommunityOtpLoginController.testVerifySuccess = false;
        KenCommunityOtpLoginController.testVerifyMessage = 'Invalid verification code';
        KenCommunityOtpLoginController.VerificationStepResult rejected =
            KenCommunityOtpLoginController.confirmVerificationCode('Email', '000000');
        System.assertEquals(false, rejected.success, 'A rejected code must not report success.');
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_VERIFY_FAILED,
            rejected.message,
            'A rejected code should use the portal wording.'
        );
    }

    @IsTest
    static void verificationSurfacesPlatformFailureToAdminsOnly() {
        KenCommunityOtpLoginController.testInitFail = true;

        KenCommunityOtpLoginController.VerificationStepResult res;
        System.runAs(internalUser('+91 9731456123')) {
            res = KenCommunityOtpLoginController.startVerification('SMS');
        }

        System.assertEquals(false, res.success, 'A platform failure must not report success.');
        System.assertEquals(
            true,
            res.debugMessage != null && res.debugMessage.contains('initRegisterVerificationMethod'),
            'The raw cause should be captured for admins: ' + res.debugMessage
        );
    }

    @IsTest
    static void unverifiableDetailIsExplainedHonestly() {
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_VERIFICATION_UNSUPPORTED,
            KenCommunityOtpLoginController.friendlyRegisterError(
                new KenCustomException('Could not send code due to :Email not verified')
            ),
            'A detail the platform refuses to verify should not tell the alumnus to retry.'
        );
    }

    @IsTest
    static void rateLimitIsExplainedInPlainLanguage() {
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_TOO_MANY_VERIFICATIONS,
            KenCommunityOtpLoginController.friendlyRegisterError(
                new KenCustomException('You may have attempted too many verifications in the last hour.')
            ),
            'A rate limit should tell the alumnus to wait rather than retry blindly.'
        );
    }


    @IsTest
    static void exceptionDescriptionNamesTheApiAndChannel() {
        String described = KenCommunityOtpLoginController.describeException(
            new KenCustomException('boom'),
            'registerVerificationMethod',
            'Email'
        );
        System.assertEquals(
            true,
            described.contains('registerVerificationMethod') && described.contains('Email') && described.contains('boom'),
            'The description should name the API, channel and cause: ' + described
        );
        System.assertEquals(
            true,
            KenCommunityOtpLoginController.describeException(null, 'registerVerificationMethod', 'SMS')
                .contains('no exception detail'),
            'A null exception should still produce a readable description.'
        );
    }

    @IsTest
    static void registerErrorsAreRewrittenForTheSettingsPage() {
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_ALREADY_VERIFIED,
            KenCommunityOtpLoginController.friendlyRegisterError(
                new KenCustomException('This user is already registered for this verification method.')
            ),
            'An already-registered method should say so.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_METHOD_UNAVAILABLE,
            KenCommunityOtpLoginController.friendlyRegisterError(
                new KenCustomException('This user doesn\'t have access to this verification method.')
            ),
            'A method the org has not enabled should be named as unavailable.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_SEND_FAILED,
            KenCommunityOtpLoginController.friendlyRegisterError(null),
            'Unknown failures fall back to the generic send message.'
        );
    }

    @IsTest
    static void verifyErrorsAreRewrittenForThePortal() {
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_TOO_MANY_ATTEMPTS,
            KenCommunityOtpLoginController.friendlyVerifyError('Too many attempts'),
            'Attempt lockout should tell the alumnus to request a new code.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_VERIFY_FAILED,
            KenCommunityOtpLoginController.friendlyVerifyError('Invalid verification code'),
            'An invalid code should use the portal wording.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_VERIFY_FAILED,
            KenCommunityOtpLoginController.friendlyVerifyError(null),
            'A missing platform message should use the portal wording.'
        );
        System.assertEquals(
            'Something unusual',
            KenCommunityOtpLoginController.friendlyVerifyError('Something unusual'),
            'Unrecognised platform messages should pass through.'
        );
    }

    @IsTest
    static void friendlyErrorNamesTheUnregisteredMethodCase() {
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_NO_CHANNEL,
            KenCommunityOtpLoginController.friendlySendError(
                new KenCustomException('This user doesn\'t have access to this verification method.')
            ),
            'An unregistered verification method should be explained.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_SEND_FAILED,
            KenCommunityOtpLoginController.friendlySendError(new KenCustomException('something else')),
            'Other failures fall back to the generic send message.'
        );
        System.assertEquals(
            KenCommunityOtpLoginController.MSG_SEND_FAILED,
            KenCommunityOtpLoginController.friendlySendError(null),
            'A null exception falls back to the generic send message.'
        );
    }
}