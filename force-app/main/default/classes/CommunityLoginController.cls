/**
 * @description Controller responsible for handling alumni community login,
 *              password reset via OTP, and post-login navigation logic.
 */
global without sharing class CommunityLoginController {
    @TestVisible private static final Integer RESET_OTP_EXPIRY_MINUTES = 2;
    @TestVisible private static final String RESET_OTP_EMAIL_TEMPLATE = 'Otp_Email_Template_1703842542947';
    @TestVisible private static final String RESET_ORG_WIDE_NAME = 'Ken42';
    @TestVisible private static final String MSG_MISSING_EMAIL = 'Email is required to reset password.';
    @TestVisible private static final String MSG_USER_NOT_FOUND = 'User credentials not found. Please check the email entered.';
    @TestVisible private static final String MSG_EXPIRED_OTP = 'Your OTP has expired. Please request a new one.';
    @TestVisible private static final String MSG_INVALID_OTP = 'The OTP you entered is invalid. Please try again.';
    @TestVisible private static final String REG_STATUS_UNREGISTERED = 'Unregistered';
    @TestVisible private static final String REG_STATUS_VERIFIED = 'Verified';
    @TestVisible private static final String REG_STATUS_REGISTERED = 'Registered';
    private static final String ROLETYPE_ALUMNI = 'Alumni';
    /**
     * @description Wrapper class used to return login results to Aura/LWC,
     *              including the post-login redirect URL and related
     *              Person Account Id.
     */
    public class LoginResult {
        @AuraEnabled public String url;
        @AuraEnabled public Id accountId;
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
            throw new AuraHandledException('Email and password are required.');
        }
        String startUrl = String.isBlank(communityStartUrl) ? '/' : communityStartUrl;
        
        try {
            
            User alumniUser = findCommunityUserByEmail(email);
            
            User loginUser = [
                SELECT Id, Username, AccountId
                FROM User
                WHERE Id = :alumniUser.Id
                LIMIT 1
            ];
            
            if (loginUser.AccountId != null) {
                String registrationStatus;
                
                List<ConstituentRole> roles = [
                    SELECT Registration_Status__c
                    FROM ConstituentRole
                    WHERE PersonId = :loginUser.AccountId
                    AND RoleType = :ROLETYPE_ALUMNI  
                    LIMIT 1
                ];
                if (!roles.isEmpty()) {
                    registrationStatus = roles[0].Registration_Status__c;
                }
                
                if (registrationStatus == REG_STATUS_UNREGISTERED || registrationStatus == REG_STATUS_VERIFIED) {
                    startUrl = '/alumni/onboarding-form';
                } else if (registrationStatus == REG_STATUS_REGISTERED) {
                    startUrl = '/alumni/welcome-page';
                }
            }
            
            if (Test.isRunningTest()) {
                LoginResult mockRes = new LoginResult();
                mockRes.url = '/mockURL';
                mockRes.accountId = loginUser.AccountId;
                return mockRes;
            }
            
            ApexPages.PageReference pageRef = Site.login(loginUser.Username, password, startUrl);
            if (pageRef == null) {
                throw new CustomException('Page not found');
            }
            LoginResult res = new LoginResult();
            res.url = pageRef.getUrl();
            res.accountId = loginUser.AccountId;
            return res;
            
        } catch (Exception e) {
            if (e.getMessage().contains('Your login attempt has failed')) {
                throw new AuraHandledException('Wrong Email or Password. Please try again with correct password or Use Forgot password option to reset password again.');
            }
            throw new AuraHandledException(e.getMessage());
        }
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
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }
        
        User targetUser = findCommunityUserByEmail(email);
        String otpCode = generateOtp();
        Id otpId = saveOtp(email, otpCode, targetUser?.AccountId);
        sendOtpEmail(email, otpId);
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
        if (String.isBlank(email)) {
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }
        if (String.isBlank(otpEntered)) {
            throw new AuraHandledException('Please enter the OTP sent to your email.');
        }
        if (!Schema.sObjectType.One_Time_Password__c.isAccessible()) {
            throw new AuraHandledException('INSUFFICIENT_ACCESS');
        }
        
        One_Time_Password__c otp = fetchLatestActiveOtp(email);
        
        if (otp == null || otp.Expiry__c < System.now()) {
            throw new AuraHandledException(MSG_EXPIRED_OTP);
        }
        
        if (otp.OTP__c != otpEntered) {
            throw new AuraHandledException(MSG_INVALID_OTP);
        }
        
        otp.IsActive__c = false;
        update otp;
    }
    /**
     * @description Resets the password for a community user after
     *              successful OTP verification.
     *
     * @param email       Email address of the user.
     * @param newPassword New password to be set for the user.
     */
    @AuraEnabled
    public static void resetPassword(String email, String newPassword) {
        if (String.isBlank(email)) {
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }
        if (String.isBlank(newPassword) || newPassword.length() < 8) {
            throw new AuraHandledException('Password must be at least 8 characters.');
        }
        
        User targetUser = findCommunityUserByEmail(email);
        if (targetUser == null) {
            throw new AuraHandledException(MSG_USER_NOT_FOUND);
        }
        
        System.setPassword(targetUser.Id, newPassword);
    }
    
    @TestVisible
    private static User findCommunityUserByEmail(String email) {
        List<ConstituentRole> roles = [
            SELECT Id, PersonId
            FROM ConstituentRole
            WHERE Email__c = :email  
            LIMIT 1
        ];
        
        if (roles.isEmpty() || roles[0].PersonId == null) {
            throw new AuraHandledException(MSG_USER_NOT_FOUND);
        }
        
        List<User> users = [
            SELECT Id, AccountId
            FROM User
            WHERE AccountId = :roles[0].PersonId
            AND IsActive = true
            LIMIT 1
            ];
        
        if (users.isEmpty()) {
            throw new AuraHandledException(MSG_USER_NOT_FOUND);
        }
        
        return users[0];
    }
    
    @TestVisible
    private static String generateOtp() {
        Integer randomInt = Math.abs(Crypto.getRandomInteger());
        Integer fourDigitOtp = Math.mod(randomInt, 9000) + 1000;
        return String.valueOf(fourDigitOtp);
    }
    
    @TestVisible
    private static Id saveOtp(String email, String otpCode, Id accountId) {
        if (!Schema.sObjectType.One_Time_Password__c.isCreateable()) {
            return null;
        }
        One_Time_Password__c otp = new One_Time_Password__c();
        otp.Email__c = email;
        otp.Person_Account__c = accountId;
        otp.OTP__c = otpCode;
        otp.IsActive__c = true;
        otp.Expiry__c = System.now().addMinutes(RESET_OTP_EXPIRY_MINUTES);
        insert otp;
        return otp.Id;
    }
    
    @TestVisible
    private static One_Time_Password__c fetchLatestActiveOtp(String email) {
        List<One_Time_Password__c> otps = [
            SELECT Id, OTP__c, Expiry__c, IsActive__c
            FROM One_Time_Password__c
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
        if (Test.isRunningTest()) {
            return;
        }

        List<One_Time_Password__c> otp = [
            SELECT Id, OTP__c
            FROM One_Time_Password__c
            WHERE Id = :otpId
            LIMIT 1
        ];
        
        List<EmailTemplate> templates = [
            SELECT Id,HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :RESET_OTP_EMAIL_TEMPLATE
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new AuraHandledException('OTP email template is missing. Please contact your administrator.');
        }

        
        // Fetch Custom Setting once
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c) ? orgParam.Institution_Alias__c : '';
        
        List<OrgWideEmailAddress> orgIds = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :RESET_ORG_WIDE_NAME
            LIMIT 1
        ];

        EmailTemplate template = templates[0];
        String otpnum = otp[0].OTP__c;
        String body = template.HtmlValue;
     
        body = body.replace('{Institution_Alias}', institutionAlias);
        body = body.replace('{One_Time_Password__c.OTP__c}', otpnum);
        
        Messaging.SingleEmailMessage mail = Messaging.renderStoredEmailTemplate(templates[0].Id, null, otpId);
        mail.setHtmlBody(body);
       
        mail.setSubject(mail.getSubject());
        mail.setToAddresses(new String[] { email });
        mail.setHtmlBody(mail.getHtmlBody());
        mail.setOrgWideEmailAddressId(!orgIds.isEmpty() ? orgIds[0].Id : null);
        mail.setSaveAsActivity(false);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}