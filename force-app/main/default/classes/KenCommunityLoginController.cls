/**
 * @description Controller responsible for handling alumni community login,
 *              password reset via OTP, and post-login navigation logic.
 */
global without sharing class KenCommunityLoginController {
    @TestVisible private static final Integer RESET_OTP_EXPIRY_MINUTES = 1;
    @TestVisible private static final String RESET_OTP_EMAIL_TEMPLATE = 'Otp_Email_Template_1703842542947';
    @TestVisible private static final String RESET_ORG_WIDE_NAME = KenMessagingService.orgWideAddressName();
    @TestVisible private static final String MSG_MISSING_EMAIL = 'Email is required to reset password.';
    @TestVisible private static final String MSG_USER_NOT_FOUND = 'User credentials not found. Please check the email entered.';
    @TestVisible private static final String MSG_EXPIRED_OTP = 'Your OTP has expired. Please request a new one.';
    @TestVisible private static final String MSG_INVALID_OTP = 'The OTP you entered is invalid. Please try again.';
    @TestVisible private static final String MSG_INACTIVE = 'Your alumni account is inactive. Please contact your institution for assistance.';
    @TestVisible private static final String MSG_SIGNIN_FAILED = 'Wrong Email or Password. Please try again with correct password or Use Forgot password option to reset password again.';
    @TestVisible private static final String MSG_LOGIN_FAILED = 'We couldn\'t sign you in right now. Please try again, or contact your alumni office if it keeps happening.';
    @TestVisible private static final String STATUS_FORMER = 'Former';
    @TestVisible private static final String REG_STATUS_UNREGISTERED = 'Unregistered';
    @TestVisible private static final String REG_STATUS_VERIFIED = 'Verified';
    @TestVisible private static final String REG_STATUS_REGISTERED = 'Registered';
    private static final String ROLETYPE_ALUMNI = 'Alumni';

    // Test seam: when true, sendOtpEmail bypasses its Test.isRunningTest() guard so the body
    // executes during tests (for coverage). Default false preserves existing test behavior.
    @TestVisible private static Boolean testExecuteSendOtpEmailBody = false;
    /**
     * @description Wrapper class used to return login results to Aura/LWC,
     *              including the post-login redirect URL and related
     *              Person Account Id.
     */
    public class LoginResult {
        @AuraEnabled public String url;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Boolean requirePasswordReset;
        @AuraEnabled public String pendingResetEmail;
    }
    /**
     * @description Authenticates an alumni community user and determines
     *              the appropriate post-login redirect URL based on
     *              the user's registration status.
     *
     * @param email               Email address of the alumni user.
     * @param password            Password entered by the user.
     * @param communityStartUrl   Optional start URL for community login.
     * @return LoginResult containing redirect URL and related account Id.
     */
    @AuraEnabled(cacheable=false)
    public static LoginResult login(String email, String password, String communityStartUrl) {
        if (String.isBlank(email) || String.isBlank(password)) {
            throw loginError('Email and password are required.');
        }
        
        try {
            
            User alumniUser = findCommunityUserByEmail(email);

            List<User> loginUsers = [
                SELECT Id, Username, AccountId, Email
                FROM User
                WHERE Id = :alumniUser.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (loginUsers.isEmpty()) {
                throw loginError(MSG_USER_NOT_FOUND);
            }
            User loginUser = loginUsers[0];

            assertAlumniRoleActive(loginUser.AccountId);

            String startUrl = loginUser.AccountId != null
                ? '/alumni/select-role?accountId=' + loginUser.AccountId
                : communityStartUrl;

            if (loginUser.AccountId != null && hasPendingTempPasswordReset(loginUser.AccountId)) {
                String userEmail = String.isNotBlank(loginUser.Email) ? loginUser.Email : loginUser.Username;
                String loginWithParams = '/alumni/login?redirectToReset=1&email=' + EncodingUtil.urlEncode(userEmail, 'UTF-8');
                startUrl = '/alumni/secur/logout.jsp?retURL=' + EncodingUtil.urlEncode(loginWithParams, 'UTF-8');
            }
            
            if (Test.isRunningTest()) {
                LoginResult mockRes = new LoginResult();
                mockRes.url = startUrl;
                mockRes.accountId = loginUser.AccountId;
                return mockRes;
            }
            
            ApexPages.PageReference pageRef = Site.login(loginUser.Username, password, startUrl);
            if (pageRef == null) {
                throw new KenCustomException('Page not found');
            }
            LoginResult res = new LoginResult();
            res.url = pageRef.getUrl();
            res.accountId = loginUser.AccountId;
            if (loginUser.AccountId != null && hasPendingTempPasswordReset(loginUser.AccountId)) {
                res.requirePasswordReset = true;
                res.pendingResetEmail = String.isNotBlank(loginUser.Email) ? loginUser.Email : loginUser.Username;
            }
            return res;
            
        } catch (AuraHandledException e) {
            // Already carries wording written for the alumnus. Re-wrapping it would
            // replace that with getMessage()'s 'Script-thrown exception', which is
            // what the login page used to show for every deactivated or
            // unrecognised account.
            throw e;
        } catch (Exception e) {
            String raw = e.getMessage() == null ? '' : e.getMessage();
            if (raw.contains('Your login attempt has failed')) {
                throw loginError(MSG_SIGNIN_FAILED);
            }
            System.debug(LoggingLevel.ERROR, 'KEN_LOGIN unexpected failure for ' + email
                + ' type=' + e.getTypeName() + ' message=' + raw + ' line=' + e.getLineNumber());
            throw loginError(MSG_LOGIN_FAILED);
        }
    }

    /**
     * @description Builds the exception the login page renders. The constructor
     *              argument is what reaches the browser; setMessage keeps
     *              getMessage() truthful so a caller that inspects the message
     *              does not read back 'Script-thrown exception'.
     *
     * @param message Wording safe to show to the alumnus.
     * @return Exception ready to throw.
     */
    @TestVisible
    private static AuraHandledException loginError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    /**
     * @description Blocks portal login only when the alumnus has genuinely been
     *              deactivated — the account holds at least one Alumni
     *              ConstituentRole and every ConstituentRole on it, of any role
     *              type, is Status = 'Former'. A single active role is enough to
     *              let them in, so duplicate or half-migrated role rows can no
     *              longer lock anyone out. Status = 'Former' is the deactivation
     *              lever that replaced Ken_Alumni_CRM__c.Is_Active__c, and that
     *              object is no longer consulted at all.
     *
     *              Fails open on an empty result and on a query failure: an
     *              alumnus with no roles yet, or a role table the running user
     *              cannot read, must not be mistaken for a deactivated one.
     *
     * @param accountId Person Account of the user attempting login.
     */
    @TestVisible
    private static void assertAlumniRoleActive(Id accountId) {
        if (accountId == null) {
            return;
        }

        List<ConstituentRole> roles;
        try {
            roles = [
                SELECT Id, Status, RoleType
                FROM ConstituentRole
                WHERE PersonId = :accountId
            WITH SYSTEM_MODE
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KEN_LOGIN could not read ConstituentRole for ' + accountId + ': ' + e.getMessage());
            return;
        }

        if (roles == null || roles.isEmpty()) {
            return;
        }

        Boolean hasAlumniRole = false;
        for (ConstituentRole role : roles) {
            if (role.Status != STATUS_FORMER) {
                return;
            }
            if (ROLETYPE_ALUMNI.equals(role.RoleType)) {
                hasAlumniRole = true;
            }
        }

        if (!hasAlumniRole) {
            return;
        }
        throw loginError(MSG_INACTIVE);
    }

    /**
     * @description Generates and sends a password reset OTP to the given
     *              email address associated with a community user.
     *
     * @param email Email address of the user requesting password reset.
     */
    @AuraEnabled
    public static void sendResetOtp(String email) {
        if (String.isBlank(email)) {
            throw loginError(MSG_MISSING_EMAIL);
        }
        
        User targetUser = findCommunityUserByEmail(email);
        String otpCode = generateOtp();
        Id otpId = saveOtp(email, otpCode, targetUser?.AccountId, targetUser?.MobilePhone);
        sendOtpEmail(email, otpId);
        KenMessagingService.sendOtpToPhone(
            KenMessagingService.TYPE_OTP_EMAIL,
            targetUser?.MobilePhone,
            null,
            otpCode
        );
    }
    /**
     * @description Verifies a password reset OTP for the given email address
     *              and deactivates it upon successful validation.
     *
     * @param email       Email address used for OTP verification.
     * @param otpEntered  OTP value entered by the user.
     */
    @AuraEnabled
    public static void verifyResetOtp(String email, String otpEntered) {
        validateResetOtp(email, otpEntered);
    }

    /**
     * @description Validates the live reset OTP for an email WITHOUT consuming it.
     *              verifyResetOtp and resetPassword both go through here, so a
     *              password can never be changed by calling resetPassword on its
     *              own: the caller must always present a matching, active,
     *              unexpired OTP. resetPassword consumes the OTP once it wins.
     *
     * @param email       Email address the OTP was issued to.
     * @param otpEntered  OTP value supplied by the caller.
     * @return the matching OTP record, still active.
     */
    @TestVisible
    private static Ken_One_Time_Password__c validateResetOtp(String email, String otpEntered) {
        if (String.isBlank(email)) {
            throw loginError(MSG_MISSING_EMAIL);
        }
        if (String.isBlank(otpEntered)) {
            throw loginError('Please enter the OTP sent to your email.');
        }
        if (!Schema.sObjectType.Ken_One_Time_Password__c.isAccessible()) {
            throw loginError('INSUFFICIENT_ACCESS');
        }

        Ken_One_Time_Password__c otp = fetchLatestActiveOtp(email);

        if (otp == null || otp.Expiry__c < System.now()) {
            throw loginError(MSG_EXPIRED_OTP);
        }

        if (otp.OTP__c != otpEntered) {
            throw loginError(MSG_INVALID_OTP);
        }

        return otp;
    }
    /**
     * @description Resets the password for a community user after
     *              successful OTP verification.
     *
     * @param email       Email address of the user.
     * @param newPassword New password to be set for the user.
     * @param otpEntered  The OTP already verified in the previous step. Revalidated
     *                    here so the password cannot be reset without it.
     */
    @AuraEnabled
    public static void resetPassword(String email, String newPassword, String otpEntered) {
        if (String.isBlank(newPassword) || newPassword.length() < 8) {
            throw loginError('Password must be at least 8 characters.');
        }

        Ken_One_Time_Password__c otp = validateResetOtp(email, otpEntered);

        User targetUser = findCommunityUserByEmail(email);
        if (targetUser == null) {
            throw loginError(MSG_USER_NOT_FOUND);
        }

        otp.IsActive__c = false;
        Database.update(otp, true, AccessLevel.SYSTEM_MODE);

        KenPasswordService.applyNewPassword(targetUser.Id, newPassword);
        markTempPasswordResetCompleted(targetUser.AccountId);
    }
    
    @TestVisible
    private static User findCommunityUserByEmail(String email) {
        String normalizedEmail = String.isBlank(email) ? null : email.trim();
        if (String.isBlank(normalizedEmail)) {
            throw loginError(MSG_USER_NOT_FOUND);
        }

        List<User> directUsers = [
            SELECT Id, AccountId, MobilePhone
            FROM User
            WHERE IsActive = true
            AND AccountId != null
            AND (Email = :normalizedEmail OR Username = :normalizedEmail)
            WITH SYSTEM_MODE
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
            List<User> usersByAccount = [
                SELECT Id, AccountId, MobilePhone
                FROM User
                WHERE AccountId = :accountsByPersonEmail[0].Id
                AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!usersByAccount.isEmpty()) {
                return usersByAccount[0];
            }
        }

        List<ConstituentRole> roles = [
            SELECT Id, PersonId
            FROM ConstituentRole
            WHERE Email__c = :normalizedEmail
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        
        if (roles.isEmpty() || roles[0].PersonId == null) {
            throw loginError(MSG_USER_NOT_FOUND);
        }
        
        List<User> users = [
            SELECT Id, AccountId, MobilePhone
            FROM User
            WHERE AccountId = :roles[0].PersonId
            AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
            ];
        
        if (users.isEmpty()) {
            throw loginError(MSG_USER_NOT_FOUND);
        }
        
        return users[0];
    }

    @TestVisible
    private static void markTempPasswordResetCompleted(Id accountId) {
        if (accountId == null) {
            return;
        }
        if (!KenNamespaceUtil.hasField(Account.SObjectType.getDescribe().fields.getMap(), 'Temp_Password_Reset_Completed__c')) {
            return;
        }

        Account a = new Account(Id = accountId);
        a.put(KenNamespaceUtil.qualifyCustom('Temp_Password_Reset_Completed__c'), true);
        Database.update(a, System.AccessLevel.SYSTEM_MODE);
    }

    @TestVisible
    private static Boolean hasPendingTempPasswordReset(Id accountId) {
        if (accountId == null) {
            return false;
        }

        if (!KenNamespaceUtil.hasField(Account.SObjectType.getDescribe().fields.getMap(), 'Temp_Password_Reset_Completed__c')) {
            return false;
        }

        String accountIdEscaped = String.escapeSingleQuotes(String.valueOf(accountId));
        List<SObject> rows = Database.query(
            'SELECT Temp_Password_Reset_Completed__c FROM Account WHERE Id = \'' + accountIdEscaped + '\' LIMIT 1'
        );
        if (rows.isEmpty()) {
            return false;
        }

        Object raw = rows[0].get(KenNamespaceUtil.qualifyCustom('Temp_Password_Reset_Completed__c'));
        return raw != null && raw instanceof Boolean && ((Boolean) raw) == false;
    }

    @TestVisible
    private static String generateOtp() {
        Integer randomInt = Math.abs(Crypto.getRandomInteger());
        Integer fourDigitOtp = Math.mod(randomInt, 9000) + 1000;
        return String.valueOf(fourDigitOtp);
    }
    
    @TestVisible
    private static Id saveOtp(String email, String otpCode, Id accountId) {
        return saveOtp(email, otpCode, accountId, null);
    }

    /**
     * @description Records the code, and the number it was texted to when the alumnus has one,
     *              so support can tell which channel a missing code was sent on.
     */
    @TestVisible
    private static Id saveOtp(String email, String otpCode, Id accountId, String mobile) {
        if (!Schema.sObjectType.Ken_One_Time_Password__c.isCreateable()) {
            return null;
        }
        Ken_One_Time_Password__c otp = new Ken_One_Time_Password__c();
        otp.Email__c = email;
        otp.Person_Account__c = accountId;
        otp.OTP__c = otpCode;
        otp.Mobile_Number__c = mobile;
        otp.IsActive__c = true;
        otp.Expiry__c = System.now().addMinutes(RESET_OTP_EXPIRY_MINUTES);
        insert otp;
        return otp.Id;
    }
    
    @TestVisible
    private static Ken_One_Time_Password__c fetchLatestActiveOtp(String email) {
        List<Ken_One_Time_Password__c> otps = [
            SELECT Id, OTP__c, Expiry__c, IsActive__c
            FROM Ken_One_Time_Password__c
            WHERE Email__c = :email
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (otps.isEmpty() || Boolean.valueOf(otps[0].IsActive__c) == false) {
            return null;
        }
        return otps[0];
    }
    
    @TestVisible
    private static void sendOtpEmail(String email, Id otpId) {
        if (Test.isRunningTest() && !testExecuteSendOtpEmailBody) {
            return;
        }

        Ken_Alm_Bypass_Settings__c emailSettings = KenSettings.bypass();
        if (emailSettings != null && emailSettings.Skip_Otp_Email_Template__c) {
            return;
        }

        List<Ken_One_Time_Password__c> otp = [
            SELECT Id, OTP__c
            FROM Ken_One_Time_Password__c
            WHERE Id = :otpId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        
        List<EmailTemplate> templates = [
            SELECT Id,HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :RESET_OTP_EMAIL_TEMPLATE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw loginError('OTP email template is missing. Please contact your administrator.');
        }

        
        // Fetch Custom Setting once
        Ken_Alm_Org_Parameters__c orgParam = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c) ? orgParam.Institution_Alias__c : '';
        
        List<OrgWideEmailAddress> orgIds = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :RESET_ORG_WIDE_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        EnhancedLetterhead lh;
        try {
            lh = [
                SELECT LetterheadHeader, LetterheadFooter
                FROM EnhancedLetterhead
                WHERE Name = 'Alumni Letterhead'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
        } catch (Exception e) {
            lh = null;
        }

        String letterheadHeader = lh != null && lh.LetterheadHeader != null ? lh.LetterheadHeader : '';

        String letterheadFooter = lh != null && lh.LetterheadFooter != null ? lh.LetterheadFooter : '';

        EmailTemplate template = templates[0];
        String otpnum = otp[0].OTP__c;

        KenMessagingService.Result routed = KenMessagingService.send(
            new KenMessagingService.Request(KenMessagingService.TYPE_OTP_EMAIL)
                .toEmail(email)
                .attribute('otp', otpnum)
                .attribute('One_Time_Password__c.OTP__c', otpnum)
                .attribute('Institution_Alias', institutionAlias)
        );
        if (routed.handled) {
            return;
        }

        String body = template.HtmlValue;

        body = body.replace('{Institution_Alias}', institutionAlias);
        body = body.replace('{One_Time_Password__c.OTP__c}', otpnum);

        
        String finalBody ='<html><body>' + letterheadHeader + body 
        // + letterheadFooter 
        + '</body></html>';
        
        Messaging.SingleEmailMessage mail = Messaging.renderStoredEmailTemplate(templates[0].Id, null, otpId);
        mail.setHtmlBody(finalBody);
       
        mail.setSubject(mail.getSubject());
        mail.setToAddresses(new String[] { email });
        mail.setHtmlBody(mail.getHtmlBody());
        mail.setOrgWideEmailAddressId(!orgIds.isEmpty() ? orgIds[0].Id : null);
        mail.setSaveAsActivity(false);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}