/**
 * @description Passwordless one-time password login for the alumni portal.
 *
 * Uses the platform's passwordless feature rather than a custom OTP table:
 * System.UserManagement.initPasswordlessLogin issues the challenge and
 * verifyPasswordlessLogin validates the code and mints the Experience Cloud
 * session, returning the redirect URL the browser navigates to. The alumnus's
 * stored password is never written to, so email + password login keeps working
 * before and after every OTP login.
 *
 * The available channels are resolved server side from the org configuration
 * (Ken_Alm_Org_Parameters__c.OTP_Delivery_Channel__c) intersected with what the
 * individual alumnus is actually eligible for, so the login page never offers a
 * channel that would fail. Both sendLoginOtp and verifyLoginOtp re-resolve the
 * target user and re-validate the channel, so a tampered client value can never
 * point the flow at another alumnus or an ineligible channel.
 */
public without sharing class KenCommunityOtpLoginController {
    @TestVisible private static final String CHANNEL_EMAIL = 'Email';
    @TestVisible private static final String CHANNEL_SMS = 'SMS';
    @TestVisible private static final String CHANNEL_BOTH = 'Both';
    @TestVisible private static final String ALUMNI_PROFILE_NAME = 'Alumni';
    @TestVisible private static final String DEFAULT_START_URL = '/alumni/';

    // E.164 permits at most 15 digits including the country code. The floor keeps obvious
    // junk out without excluding countries whose national numbers are shorter than India's.
    @TestVisible private static final Integer MIN_E164_DIGITS = 7;
    @TestVisible private static final Integer MAX_E164_DIGITS = 15;
    // Fallback for a number that carries no country code at all — bulk imports predating
    // the register page's country picker. Ken_Alm_Org_Parameters__c.Default_Dial_Code__c
    // holds an ISO code for the phone-input dropdown, so it yields no digits here and this
    // is what actually applies.
    @TestVisible private static final String DEFAULT_USER_DIAL_CODE = '91';

    @TestVisible private static final String MSG_MISSING_IDENTIFIER = 'Please enter your registered email address.';
    @TestVisible private static final String MSG_MISSING_MOBILE = 'Please enter your registered mobile number.';
    @TestVisible private static final String MSG_USER_NOT_FOUND = 'We couldn\'t find an account with that email address. Please check and try again.';
    @TestVisible private static final String MSG_INACTIVE = 'Your alumni account is inactive. Please contact your institution for assistance.';
    @TestVisible private static final String MSG_NO_CHANNEL = 'One-time password login isn\'t switched on for your account yet. Sign in with your password, then verify your email under Settings > Login & Security to enable it.';
    @TestVisible private static final String MSG_CHANNEL_UNAVAILABLE = 'That verification method isn\'t available for your account. Please choose another option.';
    @TestVisible private static final String MSG_EMAIL_BLOCKED_BY_PHONE = 'Your mobile number is verified, so your code is sent by text rather than email. Please choose the text message option.';
    @TestVisible private static final String MSG_EMAIL_NOT_VERIFIED = 'Your email address isn\'t verified yet. Sign in with your password, then verify it under Settings > Login & Security.';
    @TestVisible private static final String MSG_NO_MOBILE_ON_FILE = 'We don\'t have a mobile number for your account. Sign in with your password and add one under Settings.';
    @TestVisible private static final String MSG_METHOD_NOT_ENABLED = 'That option isn\'t switched on for this portal yet. Please choose another option.';
    @TestVisible private static final String MSG_OTP_SIGNIN_BLOCKED = 'One-time password sign-in isn\'t enabled for your account. Please sign in with your password, or contact your alumni office.';
    @TestVisible private static final String MSG_MOBILE_NOT_REGISTERED = 'Your mobile number isn\'t registered for one-time passwords yet. Sign in with your password, then verify it under Settings > Login & Security.';
    @TestVisible private static final String MSG_SEND_FAILED = 'Unable to send the one-time password right now. Please try again.';
    @TestVisible private static final String MSG_VERIFY_FAILED = 'Invalid or expired one-time password. Please try again.';
    @TestVisible private static final String MSG_SESSION_LOST = 'Your one-time password session has expired. Please request a new code.';
    @TestVisible private static final String MSG_TOO_MANY_ATTEMPTS = 'Too many incorrect attempts. Please request a new code.';
    @TestVisible private static final String MSG_ALREADY_VERIFIED = 'That contact detail is already verified.';
    @TestVisible private static final String MSG_METHOD_UNAVAILABLE = 'That verification method isn\'t enabled for this portal yet.';
    @TestVisible private static final String MSG_MOBILE_REQUIRED = 'Please save a mobile number before verifying it.';
    @TestVisible private static final String MSG_MOBILE_INVALID = 'Please enter a valid 10-digit mobile number.';
    @TestVisible private static final String MSG_TOO_MANY_VERIFICATIONS = 'You\'ve requested too many codes in the last hour. Please wait a while and try again.';
    // Salesforce will only send an in-page verification code to a contact detail it
    // has ALREADY verified, so a first-time verification cannot be completed here.
    @TestVisible private static final String MSG_VERIFICATION_UNSUPPORTED = 'We can\'t verify this contact detail from here yet. Please contact your alumni office.';

    @TestVisible private static String testInitIdentifier = 'TEST_IDENTIFIER';
    @TestVisible private static Boolean testInitFail = false;
    @TestVisible private static Boolean testVerifySuccess = true;
    @TestVisible private static String testVerifyMessage = null;
    @TestVisible private static String testVerifyRedirect = '/alumni/select-role';
    @TestVisible private static List<String> testChannelOverride = null;

    /**
     * @description Result of the first step: resolving the typed identifier to an
     *              alumnus and reporting which OTP channels they may actually use.
     */
    public class OtpLoginContextResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String accountId { get; set; }
        @AuraEnabled public List<String> availableChannels { get; set; }
        @AuraEnabled public String defaultChannel { get; set; }
        @AuraEnabled public String maskedEmail { get; set; }
        @AuraEnabled public String maskedPhone { get; set; }

        public OtpLoginContextResult() {
            success = false;
            availableChannels = new List<String>();
        }
    }

    /**
     * @description Result of issuing an OTP challenge. The identifier is the
     *              opaque platform challenge id the LWC passes back on verify.
     */
    public class SendOtpResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String identifier { get; set; }
        @AuraEnabled public String channel { get; set; }
        @AuraEnabled public String maskedTarget { get; set; }
        // Raw platform text, never rendered to the alumnus.
        @AuraEnabled public String debugMessage { get; set; }

        public SendOtpResult() {
            success = false;
        }
    }

    /**
     * @description Result of verifying an OTP. On success redirectUrl is the
     *              platform-minted login URL the browser must navigate to.
     */
    public class VerifyOtpResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String redirectUrl { get; set; }
        @AuraEnabled public String accountId { get; set; }

        public VerifyOtpResult() {
            success = false;
        }
    }

    /**
     * @description Step 1. Resolves a typed email address to an eligible alumni
     *              portal user and reports the OTP channels available to them.
     *
     * @param identifier Email address typed on the login page.
     * @return Context with availableChannels populated on success, or a
     *         user-safe message explaining why OTP login isn't possible.
     */
    @AuraEnabled(cacheable=false)
    public static OtpLoginContextResult resolveOtpLoginContext(String identifier, String channel) {
        OtpLoginContextResult res = new OtpLoginContextResult();
        String requested = normalizeChannel(channel);
        if (String.isBlank(identifier)) {
            res.message = CHANNEL_SMS.equals(requested) ? MSG_MISSING_MOBILE : MSG_MISSING_IDENTIFIER;
            return res;
        }

        try {
            User alumniUser = CHANNEL_SMS.equals(requested)
                ? findPortalUserByMobile(identifier)
                : findPortalUserByEmail(identifier);
            if (alumniUser == null) {
                res.message = MSG_USER_NOT_FOUND;
                return res;
            }
            if (!isAlumniRoleActive(alumniUser.AccountId)) {
                res.message = MSG_INACTIVE;
                return res;
            }

            ensureUserMobilePhone(alumniUser);
            List<String> channels = resolveAvailableChannels(alumniUser);
            if (channels.isEmpty()) {
                res.message = MSG_NO_CHANNEL;
                return res;
            }

            res.success = true;
            res.accountId = String.valueOf(alumniUser.AccountId);
            res.availableChannels = channels;
            // Offer SMS first whenever it is available. It is the branded channel — the wording is
            // ours through Marketing Cloud rather than a stock Salesforce email — and it is the one
            // the platform will send without the alumnus having verified anything first.
            res.defaultChannel = channels.contains(CHANNEL_SMS) ? CHANNEL_SMS : channels[0];
            res.maskedEmail = maskEmail(String.isNotBlank(alumniUser.Email) ? alumniUser.Email : alumniUser.Username);
            res.maskedPhone = maskPhone(alumniUser.MobilePhone);

            // The alumnus resolved fine, so this is still a success — but they asked for a channel
            // they can't use. Say why. The login page prints this message verbatim and otherwise
            // shows only "Please choose another option", which tells them nothing.
            if (!channels.contains(requested)) {
                res.message = channelUnavailableReason(alumniUser, requested);
            }
            return res;
        } catch (Exception e) {
            res.success = false;
            res.message = MSG_USER_NOT_FOUND;
            return res;
        }
    }

    /**
     * @description Step 2. Issues an OTP challenge on the chosen channel.
     *
     * @param accountId Person Account id returned by resolveOtpLoginContext.
     * @param channel   Either Email or SMS.
     * @return SendOtpResult carrying the opaque platform challenge identifier.
     */
    @AuraEnabled(cacheable=false)
    public static SendOtpResult sendLoginOtp(String accountId, String channel) {
        SendOtpResult res = new SendOtpResult();
        String requested = normalizeChannel(channel);
        User target;
        try {
            trace('sendLoginOtp accountId=' + accountId + ' requestedChannel=' + requested
                + ' runningUser=' + UserInfo.getUserName() + ' (' + UserInfo.getUserId() + ')'
                + ' userType=' + UserInfo.getUserType()
                + ' networkId=' + Network.getNetworkId());

            target = resolveEligibleUser(accountId);
            if (target == null) {
                trace('resolveEligibleUser returned NULL for accountId=' + accountId);
                res.message = MSG_USER_NOT_FOUND;
                return res;
            }
            if (!isAlumniRoleActive(target.AccountId)) {
                trace('alumni role INACTIVE for accountId=' + target.AccountId);
                res.message = MSG_INACTIVE;
                return res;
            }

            ensureUserMobilePhone(target);

            List<String> available = resolveAvailableChannels(target);
            trace('target userId=' + target.Id + ' username=' + target.Username
                + ' accountId=' + target.AccountId
                + ' mobile=[' + target.MobilePhone + ']'
                + ' emailVerified=' + target.HasUserVerifiedEmail
                + ' phoneVerified=' + target.HasUserVerifiedPhone
                + ' configuredChannel=' + configuredChannel()
                + ' availableChannels=' + available);

            if (!available.contains(requested)) {
                trace('channel ' + requested + ' NOT in availableChannels - refusing before platform call');
                res.message = channelUnavailableReason(target, requested);
                return res;
            }

            trace('calling initPasswordlessLogin userId=' + target.Id
                + ' method=' + toVerificationMethod(requested));
            res.identifier = platformInitLogin(target.Id, requested);
            trace('initPasswordlessLogin returned identifier=[' + res.identifier + ']');
            res.success = String.isNotBlank(res.identifier);
            res.channel = requested;
            res.maskedTarget = CHANNEL_SMS.equals(requested)
                ? maskPhone(target.MobilePhone)
                : maskEmail(String.isNotBlank(target.Email) ? target.Email : target.Username);
            if (!res.success) {
                res.message = MSG_SEND_FAILED;
                res.debugMessage = 'initPasswordlessLogin returned a blank identifier for channel ' + requested;
            }
            return res;
        } catch (Exception e) {
            trace('EXCEPTION from initPasswordlessLogin'
                + ' type=' + e.getTypeName()
                + ' message=' + e.getMessage()
                + ' line=' + e.getLineNumber()
                + ' cause=' + (e.getCause() == null ? 'none' : String.valueOf(e.getCause()))
                + ' stack=' + e.getStackTraceString());
            res.success = false;
            res.message = friendlySendError(e, requested);
            res.debugMessage = describeException(e, 'initPasswordlessLogin', requested);
            // A phone-verified alumnus asking for an email code is the one failure with a known
            // cause and a known cure: the org has "Prevent identity verification by email when
            // other methods are registered" switched on. Name it rather than let the generic
            // wording send them round in circles.
            if (CHANNEL_EMAIL.equals(requested) && target != null && target.HasUserVerifiedPhone == true) {
                res.message = MSG_EMAIL_BLOCKED_BY_PHONE;
                res.debugMessage += ' | Likely cause: Setup > Identity Verification > "Prevent identity '
                    + 'verification by email when other methods are registered" is enabled.';
            }
            return res;
        }
    }

    /**
     * @description Step 3. Verifies the code and mints the portal session.
     *
     * @param accountId  Person Account id returned by resolveOtpLoginContext.
     * @param channel    The channel the code was sent on.
     * @param identifier Opaque platform challenge id from sendLoginOtp.
     * @param otpCode    Code typed by the alumnus.
     * @param startUrl   Requested landing page; sanitized before use.
     * @return VerifyOtpResult with the platform-minted redirect URL on success.
     */
    @AuraEnabled(cacheable=false)
    public static VerifyOtpResult verifyLoginOtp(
        String accountId,
        String channel,
        String identifier,
        String otpCode,
        String startUrl
    ) {
        VerifyOtpResult res = new VerifyOtpResult();
        if (String.isBlank(identifier)) {
            res.message = MSG_SESSION_LOST;
            return res;
        }
        if (String.isBlank(otpCode)) {
            res.message = MSG_VERIFY_FAILED;
            return res;
        }

        try {
            User target = resolveEligibleUser(accountId);
            if (target == null) {
                res.message = MSG_USER_NOT_FOUND;
                return res;
            }
            if (!isAlumniRoleActive(target.AccountId)) {
                res.message = MSG_INACTIVE;
                return res;
            }

            String requested = normalizeChannel(channel);
            if (!resolveAvailableChannels(target).contains(requested)) {
                res.message = channelUnavailableReason(target, requested);
                return res;
            }

            VerifyOutcome outcome = platformVerifyLogin(
                target.Id,
                requested,
                identifier,
                otpCode.trim(),
                sanitizeStartUrl(startUrl, target.AccountId)
            );

            if (outcome != null && outcome.success == true && String.isNotBlank(outcome.redirectUrl)) {
                res.success = true;
                res.redirectUrl = outcome.redirectUrl;
                res.accountId = String.valueOf(target.AccountId);
                return res;
            }
            res.message = friendlyVerifyError(outcome == null ? null : outcome.message);
            return res;
        } catch (Exception e) {
            res.success = false;
            res.message = MSG_VERIFY_FAILED;
            return res;
        }
    }

    /**
     * @description Verification state shown on the account settings page.
     */
    public class VerificationStatus {
        @AuraEnabled public Boolean emailVerified { get; set; }
        @AuraEnabled public Boolean phoneVerified { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String mobilePhone { get; set; }
        @AuraEnabled public Boolean emailChannelEnabled { get; set; }
        @AuraEnabled public Boolean smsChannelEnabled { get; set; }
        @AuraEnabled public Boolean otpLoginEnabled { get; set; }

        public VerificationStatus() {
            emailVerified = false;
            phoneVerified = false;
            emailChannelEnabled = false;
            smsChannelEnabled = false;
            otpLoginEnabled = false;
        }
    }

    /**
     * @description Outcome of a settings-page verification step.
     */
    public class VerificationStepResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        // Raw platform text, never rendered to the alumnus. Kept so an admin can
        // read the real cause off the network response when a call fails.
        @AuraEnabled public String debugMessage { get; set; }

        public VerificationStepResult() {
            success = false;
        }
    }

    /**
     * @description Reports which contact details the signed-in alumnus has
     *              verified, so the settings page can show badges and hide
     *              channels the org doesn't run.
     *
     * @return Current verification state for the running user.
     */
    @AuraEnabled(cacheable=false)
    public static VerificationStatus getVerificationStatus() {
        VerificationStatus status = new VerificationStatus();
        User me = [
            SELECT Id, Email, MobilePhone, HasUserVerifiedEmail, HasUserVerifiedPhone
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        status.emailVerified = me.HasUserVerifiedEmail == true;
        status.phoneVerified = me.HasUserVerifiedPhone == true;
        status.email = me.Email;
        status.mobilePhone = me.MobilePhone;

        String channel = configuredChannel();
        status.emailChannelEnabled = CHANNEL_EMAIL.equals(channel) || CHANNEL_BOTH.equals(channel);
        status.smsChannelEnabled = CHANNEL_SMS.equals(channel) || CHANNEL_BOTH.equals(channel);

        Ken_Alm_Org_Parameters__c cs = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        String method = (cs == null || String.isBlank(cs.Login_Method__c)) ? 'Password' : cs.Login_Method__c.trim();
        status.otpLoginEnabled = 'OTP'.equalsIgnoreCase(method) || CHANNEL_BOTH.equalsIgnoreCase(method);
        return status;
    }

    /**
     * @description Stores a mobile number on the signed-in alumnus so it can then
     *              be verified. Salesforce can only SMS a number held on the User
     *              record, and it expects the canonical '+CC NNNNNNNNNN' shape.
     *
     * @param phone Free-form number typed on the settings page.
     * @return Result carrying a user-safe message on failure.
     */
    @AuraEnabled(cacheable=false)
    public static VerificationStepResult saveMobileNumber(String phone) {
        VerificationStepResult res = new VerificationStepResult();
        String formatted = formatMobileForUser(phone);
        if (String.isBlank(formatted)) {
            res.message = MSG_MOBILE_INVALID;
            return res;
        }

        try {
            Database.update(new User(Id = UserInfo.getUserId(), MobilePhone = formatted), true, AccessLevel.SYSTEM_MODE);
            res.success = true;
            return res;
        } catch (Exception e) {
            res.message = 'We couldn\'t save that mobile number. Please try again.';
            return res;
        }
    }

    /**
     * @description Normalises a free-form number into the '+CC NNNNNNNNNN' shape Salesforce
     *              expects on User.MobilePhone before it will SMS it.
     *
     *              A number that already carries a country code is kept exactly as the
     *              Person Account holds it. The '+' is the only thing marking where the
     *              country code ends, so stripping it leaves the code indistinguishable
     *              from the number — which is how every alumnus previously ended up on the
     *              org default regardless of where they registered from, and how a country
     *              whose code and national number total ten digits (Singapore's
     *              '+65 91234567') had its country code absorbed into the number itself.
     *              Salesforce accepts '+CC NNNN' for every country it supports SMS in, so
     *              there is nothing to rebuild.
     *
     *              Only a number with no country code at all falls back to a default.
     *
     * @param phone Free-form number from a form, Lead or Person Account.
     * @return Formatted number, or null when the input is unusable.
     */
    public static String formatMobileForUser(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String trimmed = phone.trim();

        if (trimmed.startsWith('+')) {
            Integer digitCount = trimmed.replaceAll('[^0-9]', '').length();
            if (digitCount < MIN_E164_DIGITS || digitCount > MAX_E164_DIGITS) {
                return null;
            }
            // Collapse stray whitespace; otherwise leave the number exactly as stored.
            return trimmed.replaceAll('\\s+', ' ');
        }

        String digits = trimmed.replaceAll('[^0-9]', '');
        if (digits.length() > 10) {
            digits = digits.substring(digits.length() - 10);
        }
        if (digits.length() != 10) {
            return null;
        }
        Ken_Alm_Org_Parameters__c cs = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        String dial = (cs == null || String.isBlank(cs.Default_Dial_Code__c))
            ? DEFAULT_USER_DIAL_CODE
            : cs.Default_Dial_Code__c.replaceAll('[^0-9]', '');
        return '+' + (String.isBlank(dial) ? DEFAULT_USER_DIAL_CODE : dial) + ' ' + digits;
    }

    /**
     * @description Starts settings-page verification for the signed-in alumnus.
     *
     * Uses initRegisterVerificationMethod, which issues a code the alumnus types
     * on our own page. Two similarly named APIs are the wrong choice here and
     * were both tried first: initVerificationMethod only challenges a channel that
     * is ALREADY verified ("Could not send code due to :Email not verified"), and
     * registerVerificationMethod returns a Salesforce-hosted page the browser has
     * to be redirected to. Only the initRegister/verifyRegister pair registers a
     * new channel without leaving the portal.
     *
     * @param channel Either Email or SMS.
     * @return Result reporting whether a code was issued.
     */
    @AuraEnabled(cacheable=false)
    public static VerificationStepResult startVerification(String channel) {
        VerificationStepResult res = new VerificationStepResult();
        String requested = normalizeChannel(channel);
        try {
            User me = [
                SELECT Id, MobilePhone, HasUserVerifiedEmail, HasUserVerifiedPhone
                FROM User
                WHERE Id = :UserInfo.getUserId()
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (CHANNEL_SMS.equals(requested)) {
                if (String.isBlank(me.MobilePhone)) {
                    res.message = MSG_MOBILE_REQUIRED;
                    return res;
                }
                if (me.HasUserVerifiedPhone == true) {
                    res.message = MSG_ALREADY_VERIFIED;
                    return res;
                }
            } else if (me.HasUserVerifiedEmail == true) {
                res.message = MSG_ALREADY_VERIFIED;
                return res;
            }

            platformInitRegister(requested);
            res.success = true;
            return res;
        } catch (Exception e) {
            res.message = friendlyRegisterError(e);
            res.debugMessage = describeException(e, 'initRegisterVerificationMethod', requested);
            return res;
        }
    }

    /**
     * @description Issues the registration code for a channel the alumnus has not
     *              verified yet. Short-circuited under test because the platform
     *              call sends a real code and consumes verification credits.
     */
    private static void platformInitRegister(String channel) {
        if (Test.isRunningTest()) {
            if (testInitFail) {
                throw new KenCustomException('mock register failure');
            }
            return;
        }
        System.UserManagement.initRegisterVerificationMethod(toVerificationMethod(channel));
    }

    /**
     * @description Confirms the registration code. The platform throws on an
     *              invalid or expired code and returns normally on success, and
     *              takes no challenge identifier — registration is per-session.
     */
    private static void platformVerifyRegister(String channel, String code) {
        if (Test.isRunningTest()) {
            if (!testVerifySuccess) {
                throw new KenCustomException(
                    String.isBlank(testVerifyMessage) ? 'mock verify failure' : testVerifyMessage
                );
            }
            return;
        }
        System.UserManagement.verifyRegisterVerificationMethod(code, toVerificationMethod(channel));
    }

    /**
     * @description Confirms a code the alumnus typed on our own settings page,
     *              which registers the channel and flips the platform's
     *              HasUserVerifiedEmail / HasUserVerifiedPhone flag.
     *
     * @param channel The channel the code was sent on.
     * @param code    Code typed by the alumnus.
     * @return Result describing whether the channel is now verified.
     */
    @AuraEnabled(cacheable=false)
    public static VerificationStepResult confirmVerificationCode(String channel, String code) {
        VerificationStepResult res = new VerificationStepResult();
        if (String.isBlank(code)) {
            res.message = MSG_VERIFY_FAILED;
            return res;
        }
        String requested = normalizeChannel(channel);
        try {
            platformVerifyRegister(requested, code.trim());
            res.success = true;
            return res;
        } catch (Exception e) {
            res.message = friendlyVerifyError(e.getMessage());
            res.debugMessage = describeException(e, 'verifyRegisterVerificationMethod', requested);
            return res;
        }
    }


    /**
     * @description Diagnostic breadcrumb for the OTP login flow, logged at ERROR so it survives
     *              the lower log levels a guest-user trace usually runs at. Every line is prefixed
     *              KEN_OTP so a debug log can be filtered down to just this flow.
     */
    private static void trace(String detail) {
        System.debug(LoggingLevel.ERROR, 'KEN_OTP ' + detail);
    }

    /**
     * @description Builds an admin-facing description of a platform failure so the
     *              real cause is readable from the network response without ever
     *              being shown to the alumnus.
     */
    @TestVisible
    private static String describeException(Exception e, String apiName, String channel) {
        if (e == null) {
            return apiName + ' failed for channel ' + channel + ' with no exception detail.';
        }
        String detail = apiName + ' [' + channel + '] ' + e.getTypeName() + ': ' + e.getMessage();
        if (e.getCause() != null) {
            detail += ' | cause: ' + e.getCause().getMessage();
        }
        return detail;
    }

    /**
     * @description Maps the platform's registration refusals to settings-page
     *              wording. "doesn't have access to this verification method"
     *              means the method isn't enabled for the org, which no amount of
     *              retrying will fix.
     */
    @TestVisible
    private static String friendlyRegisterError(Exception e) {
        String raw = (e == null || e.getMessage() == null) ? '' : e.getMessage().toLowerCase();
        if (raw.contains('already registered')) {
            return MSG_ALREADY_VERIFIED;
        }
        if (raw.contains('access to this verification method')) {
            return MSG_METHOD_UNAVAILABLE;
        }
        if (raw.contains('too many') || raw.contains('rate limit') || raw.contains('exceeded')) {
            return MSG_TOO_MANY_VERIFICATIONS;
        }
        if (raw.contains('not verified')) {
            return MSG_VERIFICATION_UNSUPPORTED;
        }
        return MSG_SEND_FAILED;
    }

    /** @description Plain DTO so callers and tests never construct Auth.VerificationResult. */
    @TestVisible
    private class VerifyOutcome {
        public Boolean success;
        public String message;
        public String redirectUrl;
    }

    /**
     * @description Issues the platform challenge. Short-circuited under test
     *              because the platform call sends a real code and cannot run
     *              in a test context.
     */
    private static String platformInitLogin(Id userId, String channel) {
        if (Test.isRunningTest()) {
            if (testInitFail) {
                throw new KenCustomException('mock init failure');
            }
            return testInitIdentifier;
        }
        return System.UserManagement.initPasswordlessLogin(userId, toVerificationMethod(channel));
    }

    /**
     * @description Verifies the platform challenge and mints the session. Short
     *              circuited under test for the same reason as platformInitLogin.
     */
    private static VerifyOutcome platformVerifyLogin(
        Id userId,
        String channel,
        String identifier,
        String code,
        String startUrl
    ) {
        VerifyOutcome outcome = new VerifyOutcome();
        if (Test.isRunningTest()) {
            outcome.success = testVerifySuccess;
            outcome.message = testVerifyMessage;
            outcome.redirectUrl = testVerifySuccess ? testVerifyRedirect : null;
            return outcome;
        }
        Auth.VerificationResult result = System.UserManagement.verifyPasswordlessLogin(
            userId,
            toVerificationMethod(channel),
            identifier,
            code,
            startUrl
        );
        outcome.success = result != null && result.success == true;
        outcome.message = result == null ? null : result.message;
        outcome.redirectUrl = (outcome.success && result.redirect != null) ? result.redirect.getUrl() : null;
        return outcome;
    }

    @TestVisible
    private static Auth.VerificationMethod toVerificationMethod(String channel) {
        return CHANNEL_SMS.equals(channel) ? Auth.VerificationMethod.SMS : Auth.VerificationMethod.EMAIL;
    }

    /**
     * @description Intersects the org's configured channels with the channels
     *              the alumnus is actually eligible for.
     *
     * Email is suppressed when a mobile number is registered because the org
     * setting "Prevent identity verification by email when other methods are
     * registered" makes Salesforce refuse an email code in that case.
     *
     * @param alumniUser Portal user to evaluate.
     * @return Ordered list of usable channel names; empty when none apply.
     */
    @TestVisible
    private static List<String> resolveAvailableChannels(User alumniUser) {
        List<String> channels = new List<String>();
        if (Test.isRunningTest() && testChannelOverride != null) {
            return testChannelOverride.clone();
        }
        if (alumniUser == null) {
            return channels;
        }

        String configured = configuredChannel();
        Boolean orgAllowsEmail = CHANNEL_EMAIL.equals(configured) || CHANNEL_BOTH.equals(configured);
        Boolean orgAllowsSms = CHANNEL_SMS.equals(configured) || CHANNEL_BOTH.equals(configured);

        // Both channels are offered on their own merits, and the platform stays the authority on
        // whether it will actually issue the challenge. SMS needs only a number on the User
        // record — nobody starts out phone-verified, so gating on that flag offered SMS to no one.
        // Email needs a verified address, which is the platform's own precondition for an email
        // code. Email is deliberately NOT suppressed just because a phone is registered: if the
        // alumnus picks email, they should get an email.
        Boolean smsEligible = String.isNotBlank(alumniUser.MobilePhone);
        Boolean emailEligible = alumniUser.HasUserVerifiedEmail == true;

        if (orgAllowsEmail && emailEligible) {
            channels.add(CHANNEL_EMAIL);
        }
        if (orgAllowsSms && smsEligible) {
            channels.add(CHANNEL_SMS);
        }
        return channels;
    }

    /**
     * @description Copies the alumnus's mobile number onto their User record when it is missing,
     *              because Salesforce will only issue an SMS challenge to a number held there.
     *
     *              Alumni provisioned before the number was mirrored at creation have a blank
     *              User.MobilePhone, and the login page runs as a guest who cannot update a User,
     *              so this is best-effort by design: it repairs the record when the running user
     *              is allowed to, and stays silent when it is not. Alumni provisioned from now on
     *              get the number stamped at creation, so this only matters for older records.
     *
     * @param alumniUser the resolved portal user, updated in place when a number is found
     */
    @TestVisible
    private static void ensureUserMobilePhone(User alumniUser) {

        if (alumniUser == null || String.isNotBlank(alumniUser.MobilePhone) || alumniUser.AccountId == null) {
            return;
        }

        List<Account> accounts = [
            SELECT PersonMobilePhone, Phone
            FROM Account
            WHERE Id = :alumniUser.AccountId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return;
        }

        String formatted = formatMobileForUser(
            String.isNotBlank(accounts[0].PersonMobilePhone) ? accounts[0].PersonMobilePhone : accounts[0].Phone
        );
        if (String.isBlank(formatted)) {
            return;
        }

        alumniUser.MobilePhone = formatted;
        try {
            Database.update(new User(Id = alumniUser.Id, MobilePhone = formatted), true, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'Could not stamp MobilePhone on the portal user: ' + e.getMessage());
        }
    }

    /**
     * @description Explains why a channel the alumnus asked for isn't on offer.
     *
     *              "Choose another option" on its own is useless when the other option is the one
     *              they just tried. Each branch names the actual reason and, where the alumnus can
     *              do something about it, says what.
     *
     * @param alumniUser the resolved portal user
     * @param requested  the channel they asked for
     * @return a message safe to show on the login page
     */
    @TestVisible
    private static String channelUnavailableReason(User alumniUser, String requested) {

        if (alumniUser == null) {
            return MSG_CHANNEL_UNAVAILABLE;
        }

        String configured = configuredChannel();

        if (CHANNEL_SMS.equals(requested)) {
            if (!CHANNEL_SMS.equals(configured) && !CHANNEL_BOTH.equals(configured)) {
                return MSG_METHOD_NOT_ENABLED;
            }
            return String.isBlank(alumniUser.MobilePhone) ? MSG_NO_MOBILE_ON_FILE : MSG_CHANNEL_UNAVAILABLE;
        }

        if (!CHANNEL_EMAIL.equals(configured) && !CHANNEL_BOTH.equals(configured)) {
            return MSG_METHOD_NOT_ENABLED;
        }
        if (alumniUser.HasUserVerifiedEmail != true) {
            return MSG_EMAIL_NOT_VERIFIED;
        }
        return MSG_CHANNEL_UNAVAILABLE;
    }

    /**
     * @description Reads the org's configured OTP channel, defaulting to Email
     *              when the custom setting is blank or holds an unknown value.
     */
    @TestVisible
    private static String configuredChannel() {
        Ken_Alm_Org_Parameters__c cs = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        return normalizeChannel(cs == null ? null : cs.OTP_Delivery_Channel__c);
    }

    @TestVisible
    private static String normalizeChannel(String channel) {
        if (String.isBlank(channel)) {
            return CHANNEL_EMAIL;
        }
        String trimmed = channel.trim();
        if (CHANNEL_SMS.equalsIgnoreCase(trimmed)) {
            return CHANNEL_SMS;
        }
        if (CHANNEL_BOTH.equalsIgnoreCase(trimmed)) {
            return CHANNEL_BOTH;
        }
        return CHANNEL_EMAIL;
    }

    /**
     * @description Re-resolves the portal user from a Person Account id. Used by
     *              send and verify so a client-supplied value can never point the
     *              flow at a different alumnus.
     */
    @TestVisible
    private static User resolveEligibleUser(String accountId) {
        if (String.isBlank(accountId)) {
            return null;
        }
        Id personAccountId;
        try {
            personAccountId = Id.valueOf(accountId);
        } catch (Exception e) {
            return null;
        }

        List<User> users = [
            SELECT Id, Username, Email, AccountId, MobilePhone, HasUserVerifiedEmail, HasUserVerifiedPhone
            FROM User
            WHERE AccountId = :personAccountId
            AND IsActive = true
            AND Profile.Name = :ALUMNI_PROFILE_NAME
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!users.isEmpty()) {
            return users[0];
        }

        List<User> fallback = [
            SELECT Id, Username, Email, AccountId, MobilePhone, HasUserVerifiedEmail, HasUserVerifiedPhone
            FROM User
            WHERE AccountId = :personAccountId
            AND IsActive = true
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return fallback.isEmpty() ? null : fallback[0];
    }

    /**
     * @description Resolves an email address to an active portal user, walking
     *              User email/username, then Person Account email, then the
     *              alumnus's ConstituentRole email.
     *
     * @param email Typed email address.
     * @return Matching user, or null when nothing matches.
     */
    @TestVisible
    private static User findPortalUserByEmail(String email) {
        String normalizedEmail = String.isBlank(email) ? null : email.trim();
        if (String.isBlank(normalizedEmail)) {
            return null;
        }

        List<User> directUsers = [
            SELECT Id, Username, Email, AccountId, MobilePhone, HasUserVerifiedEmail, HasUserVerifiedPhone
            FROM User
            WHERE IsActive = true
            AND AccountId != null
            AND (Email = :normalizedEmail OR Username = :normalizedEmail)
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!directUsers.isEmpty()) {
            return directUsers[0];
        }

        List<Account> accountsByPersonEmail = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail = :normalizedEmail
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!accountsByPersonEmail.isEmpty()) {
            User byAccount = resolveEligibleUser(String.valueOf(accountsByPersonEmail[0].Id));
            if (byAccount != null) {
                return byAccount;
            }
        }

        List<ConstituentRole> roles = [
            SELECT Id, PersonId
            FROM ConstituentRole
            WHERE Email__c = :normalizedEmail
            AND PersonId != null
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (roles.isEmpty()) {
            return null;
        }
        return resolveEligibleUser(String.valueOf(roles[0].PersonId));
    }

    /**
     * @description Resolves a typed mobile number to an active portal user.
     *
     * Matches on the last ten digits so the stored format ('+91 9876543210',
     * '09876543210', '+919876543210') never has to agree with what was typed.
     * The candidate list is deliberately capped and filtered in Apex because a
     * leading-wildcard LIKE cannot use the phone index.
     *
     * @param mobile Typed mobile number in any format.
     * @return Matching user, or null when nothing matches.
     */
    @TestVisible
    private static User findPortalUserByMobile(String mobile) {
        String digits = String.isBlank(mobile) ? '' : mobile.replaceAll('[^0-9]', '');
        if (digits.length() < 10) {
            return null;
        }
        String last10 = digits.substring(digits.length() - 10);
        String likePattern = '%' + last10;

        for (User u : [
            SELECT Id, Username, Email, AccountId, MobilePhone, HasUserVerifiedEmail, HasUserVerifiedPhone
            FROM User
            WHERE IsActive = true
            AND AccountId != null
            AND MobilePhone LIKE :likePattern
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 25
        ]) {
            String stored = String.isBlank(u.MobilePhone) ? '' : u.MobilePhone.replaceAll('[^0-9]', '');
            if (stored.endsWith(last10)) {
                return u;
            }
        }

        for (Account acc : [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = true
            AND (PersonMobilePhone LIKE :likePattern OR Phone LIKE :likePattern)
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 25
        ]) {
            User byAccount = resolveEligibleUser(String.valueOf(acc.Id));
            if (byAccount != null) {
                return byAccount;
            }
        }
        return null;
    }

    /**
     * @description Mirrors the password login kill switch: an alumnus is blocked
     *              when every Alumni ConstituentRole on their account is Former.
     *              Fails open for accounts with no Alumni role so other personas
     *              keep working. Status = 'Former' is the deactivation lever that
     *              replaced Ken_Alumni_CRM__c.Is_Active__c.
     */
    @TestVisible
    private static Boolean isAlumniRoleActive(Id accountId) {
        if (accountId == null) {
            return true;
        }
        List<ConstituentRole> roles = [
            SELECT Id, Status
            FROM ConstituentRole
            WHERE PersonId = :accountId AND RoleType = 'Alumni'
        WITH SYSTEM_MODE
        ];
        if (roles.isEmpty()) {
            return true;
        }
        for (ConstituentRole role : roles) {
            if (role.Status != 'Former') {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Open-redirect guard. Only site-relative paths are honoured;
     *              anything else falls back to the alumnus's role selection page.
     */
    @TestVisible
    private static String sanitizeStartUrl(String startUrl, Id accountId) {
        String fallback = accountId != null
            ? '/alumni/select-role?accountId=' + accountId
            : DEFAULT_START_URL;
        String candidate = startUrl == null ? '' : startUrl.trim();
        if (String.isBlank(candidate) || !candidate.startsWith('/') || candidate.startsWith('//')) {
            return fallback;
        }
        if (candidate.toLowerCase().contains('/login')) {
            return fallback;
        }
        return candidate;
    }

    /**
     * @description Rewrites the platform's verification failures into portal
     *              wording. "Too many attempts" is called out separately because
     *              the alumnus must request a new code rather than retype.
     */
    @TestVisible
    private static String friendlyVerifyError(String platformMessage) {
        String raw = String.isBlank(platformMessage) ? '' : platformMessage.toLowerCase();
        if (raw.contains('too many')) {
            return MSG_TOO_MANY_ATTEMPTS;
        }
        if (raw.contains('invalid') || raw.contains('expired') || String.isBlank(raw)) {
            return MSG_VERIFY_FAILED;
        }
        return platformMessage;
    }

    /**
     * @description Maps the platform's unregistered-method error to an actionable
     *              message instead of leaking raw platform text.
     */
    @TestVisible
    private static String friendlySendError(Exception e) {
        return friendlySendError(e, CHANNEL_EMAIL);
    }

    /**
     * @description As above, but names the channel the alumnus actually chose. "Verify your email"
     *              is useless advice when it was the phone that wasn't registered.
     */
    @TestVisible
    private static String friendlySendError(Exception e, String channel) {
        String raw = (e == null || e.getMessage() == null) ? '' : e.getMessage().toLowerCase();
        if (CHANNEL_SMS.equals(channel) && raw.contains('verification method')) {
            return MSG_MOBILE_NOT_REGISTERED;
        }
        // "We can't log in the user" is the platform refusing passwordless login for this user
        // entirely — usually because it isn't switched on for the site, or this verification
        // method isn't among the ones the site permits. Retrying will never help, so don't
        // invite the alumnus to keep trying.
        if (raw.contains('can\'t log in the user') || raw.contains('cannot log in the user')) {
            return MSG_OTP_SIGNIN_BLOCKED;
        }
        if (raw.contains('verification method') || (raw.contains('verif') && raw.contains('email'))) {
            return MSG_NO_CHANNEL;
        }
        return MSG_SEND_FAILED;
    }

    @TestVisible
    private static String maskEmail(String email) {
        if (String.isBlank(email) || !email.contains('@')) {
            return null;
        }
        String local = email.substringBefore('@');
        String domain = email.substringAfter('@');
        String head = local.length() <= 2 ? local.left(1) : local.left(2);
        return head + '•••@' + domain;
    }

    @TestVisible
    private static String maskPhone(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String digits = phone.replaceAll('[^0-9]', '');
        if (String.isBlank(digits)) {
            return null;
        }
        String tail = digits.length() <= 4 ? digits : digits.substring(digits.length() - 4);
        return '••••••' + tail;
    }
}