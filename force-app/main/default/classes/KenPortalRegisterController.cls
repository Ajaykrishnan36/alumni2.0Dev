/**
 * @description Controller responsible for alumni portal registration,
 *              including OTP generation, verification, and lead creation.
 */
public without sharing class KenPortalRegisterController {

    private static final String DUPLICATE_REGNUM_MESSAGE = 'An account with this Registration number already exists. Please login or reset your password.';
    @TestVisible private static final Integer OTP_EXPIRY_MINUTES = 2;
    @TestVisible private static final String OTP_EMAIL_TEMPLATE = 'Otp_Email_Template_1703842542947';
    @TestVisible private static final String ORG_WIDE_NAME = 'Alumni Management';
    @TestVisible private static final String PERSON_ACCOUNT_RT = 'Alumni_Person_Account';
    @TestVisible private static Boolean bypassEmailGuardInTests = false;
    @TestVisible private static final String MSG_MISSING_EMAIL = 'Please provide an email address.';
    @TestVisible private static final String MSG_MISSING_OTP = 'Please enter the OTP sent to your email.';
    @TestVisible private static final String MSG_EXPIRED_OTP = 'Your OTP has expired. Please request a new one.';
    @TestVisible private static final String MSG_INVALID_OTP = 'The OTP you entered is invalid. Please try again.';
/**
 * @description Wrapper class representing the result of a signup
 *              OTP request or verification operation.
 */
    public class SignupResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String otpId;
    }
/**
 * @description Request payload wrapper containing user details
 *              submitted during alumni signup.
 */
    public class SignupRequest {
        @AuraEnabled public String email;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String phone;
        @AuraEnabled public String regNumber;
        @AuraEnabled public String gradYear;
        @AuraEnabled public String otpEntered;
        // Extended fields — institute (free-text dropdown), program plan (Id from picklist).
        @AuraEnabled public String institutionName;
        @AuraEnabled public String programPlan; // LearningProgramPlan.Id when picked from the combobox
        @AuraEnabled public String referalCode;  // encrypted Account ID from ?referal= URL param
    }

    public class OptionDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public OptionDTO(String l, String v) { this.label = l; this.value = v; }
    }
    public class RegistrationOptions {
        @AuraEnabled public List<OptionDTO> institutes;
        @AuraEnabled public List<OptionDTO> programs;
        @AuraEnabled public Integer fromGradYear;
        @AuraEnabled public String defaultDialCountry;
    }

    private static final Integer DEFAULT_FROM_GRAD_YEAR = 1980;
    private static final String DEFAULT_DIAL_NONE = 'none';

    /**
     * Options for the Lead-register page combobox fields. Institutes are the
     * distinct Institution_Name__c values found on existing ConstituentRoles
     * (a formula field, so we de-dupe in-memory). Programs are
     * LearningProgramPlan rows (label = Name, value = Id) — same source as the
     * onboarding flow's program-plan picker.
     */
    @AuraEnabled(cacheable=true)
    public static RegistrationOptions getRegistrationOptions() {
        RegistrationOptions out = new RegistrationOptions();
        out.institutes = new List<OptionDTO>();
        out.programs   = new List<OptionDTO>();

        // Institutes — distinct from existing alumni data.
        Set<String> seen = new Set<String>();
        for (ConstituentRole cr : [
            SELECT Institution_Name__c FROM ConstituentRole
            WHERE Institution_Name__c != null LIMIT 5000
        ]) {
            String n = cr.Institution_Name__c;
            if (String.isNotBlank(n) && !seen.contains(n)) {
                seen.add(n);
                out.institutes.add(new OptionDTO(n, n));
            }
        }
        // Stable alphabetical order.
        out.institutes.sort(new InstituteByLabel());

        // Programs — LearningProgramPlan rows (Id is the value).
        for (LearningProgramPlan p : [
            SELECT Id, Name FROM LearningProgramPlan WHERE Name != null ORDER BY Name LIMIT 500
        ]) {
            out.programs.add(new OptionDTO(p.Name, p.Id));
        }

        out.fromGradYear = DEFAULT_FROM_GRAD_YEAR;
        out.defaultDialCountry = DEFAULT_DIAL_NONE;
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        if (orgParam != null) {
            if (orgParam.From_Graduation_Year__c != null) {
                Integer configured = Integer.valueOf(orgParam.From_Graduation_Year__c);
                if (configured >= 1900 && configured <= Date.today().year()) {
                    out.fromGradYear = configured;
                }
            }
            if (String.isNotBlank(orgParam.Default_Dial_Code__c)) {
                out.defaultDialCountry = orgParam.Default_Dial_Code__c.trim().toLowerCase();
            }
        }
        return out;
    }

    // Apex doesn't allow List<OptionDTO>.sort() with a Comparator literal, so a
    // tiny helper class lets us alpha-sort the institute list.
    private class InstituteByLabel implements Comparator<OptionDTO> {
        public Integer compare(OptionDTO a, OptionDTO b) {
            String la = a == null || a.label == null ? '' : a.label.toLowerCase();
            String lb = b == null || b.label == null ? '' : b.label.toLowerCase();
            return la.compareTo(lb);
        }
    }
/**
 * @description Generates and sends an OTP to the provided email
 *              address for alumni signup verification. Blocks early
 *              if the email + program combination already exists.
 *
 * @param requestJson JSON string containing signup request details.
 * @return SignupResult containing OTP metadata.
 */
    @AuraEnabled(cacheable=false)
    public static SignupResult requestSignupOtp(String requestJson) {
        if (String.isBlank(requestJson)) {
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }

        SignupRequest request;
        try {
            request = (SignupRequest) JSON.deserialize(requestJson, SignupRequest.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid request format: ' + e.getMessage());
        }

        if (String.isBlank(request.email)) {
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }

        // Dedup check: block before sending OTP if email+program already registered.
        Id resolvedPlanId = resolveProgramPlanId(request.programPlan);
        checkEmailProgramDuplicate(request.email, resolvedPlanId);

        String otpCode = generateOtp();
        Id otpId = saveOtpInformation(request.email, otpCode, null);
        sendEmail(request.email, otpId);

        SignupResult result = new SignupResult();
        result.success = true;
        result.otpId = String.valueOf(otpId);
        result.message = 'OTP sent to email.';
        return result;
    }
/**
 * @description Verifies the submitted signup OTP and creates a new
 *              Lead record upon successful validation.
 *
 * @param requestJson JSON string containing email, OTP, and user details.
 * @return SignupResult indicating verification outcome.
 */
    @AuraEnabled(cacheable=false)
    public static SignupResult verifySignupOtp(String requestJson) {
        if (String.isBlank(requestJson)) {
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }

        SignupRequest request;
        try {
            request = (SignupRequest) JSON.deserialize(requestJson, SignupRequest.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid request format: ' + e.getMessage());
        }

        if (String.isBlank(request.email)) {
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }
        if (String.isBlank(request.otpEntered)) {
            throw new AuraHandledException(MSG_MISSING_OTP);
        }

        List<Ken_One_Time_Password__c> otps = [
            SELECT Id, Expiry__c, OTP__c, IsActive__c
            FROM Ken_One_Time_Password__c
            WHERE Email__c = :request.email
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];

        if (otps.isEmpty() || otps[0].Expiry__c < System.now() || Boolean.valueOf(otps[0].IsActive__c) == false) {
            throw new AuraHandledException(MSG_EXPIRED_OTP);
        }

        if (otps[0].OTP__c != request.otpEntered) {
            throw new AuraHandledException(MSG_INVALID_OTP);
        }

        otps[0].IsActive__c = false;
        update otps[0];

        // programPlan now arrives as a LearningProgramPlan.Id from the combobox.
        Id resolvedPlanId = resolveProgramPlanId(request.programPlan);

        // Safety-net dedup (primary check is in requestSignupOtp).
        checkEmailProgramDuplicate(request.email, resolvedPlanId);

        if (!Schema.sObjectType.Lead.isCreateable()) {
            throw new AuraHandledException('INSUFFICIENT_CREATE_ACCESS');
        }

        // Resolve referral code to the referring alumni's Account ID
        Id referredById = KenReferralService.resolveReferrerAccountId(request.referalCode);
        Boolean isReferral = referredById != null;

        Lead leadRecord = new Lead(
            FirstName = request.firstName,
            LastName = request.lastName,
            Company = 'Alumni',
            Email = request.email,
            Phone = request.phone,
            Registration_Number__c = String.isNotBlank(request.regNumber) ? request.regNumber : null,
            Year_of_Graduation__c = request.gradYear,
            Institution_Name__c = String.isNotBlank(request.institutionName) ? request.institutionName : null,
            Program_Plan__c = resolvedPlanId,
            Status = 'new',
            LeadSource = isReferral ? 'Referral' : 'Web',
            Referred_By__c = referredById,
            RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Alumni Lead').getRecordTypeId()
        );
        insert leadRecord;

        SignupResult result = new SignupResult();
        result.success = true;
        result.message = 'OTP verified successfully.';
        result.otpId = String.valueOf(otps[0].Id);
        return result;
    }

    private static Id resolveProgramPlanId(String pp) {
        if (String.isBlank(pp)) return null;
        pp = pp.trim();
        try { return (Id) pp; } catch (Exception e) { /* not an Id — fall through to name lookup */ }
        String ppLike = '%' + String.escapeSingleQuotes(pp) + '%';
        List<LearningProgramPlan> plans = [SELECT Id FROM LearningProgramPlan WHERE Name LIKE :ppLike LIMIT 1];
        return plans.isEmpty() ? null : plans[0].Id;
    }

    private static void checkEmailProgramDuplicate(String email, Id planId) {
        if (String.isBlank(email)) return;
        List<Lead> dup = planId != null
            ? [SELECT Id FROM Lead WHERE Email = :email AND Program_Plan__c = :planId LIMIT 1]
            : [SELECT Id FROM Lead WHERE Email = :email AND Program_Plan__c = null LIMIT 1];
        if (!dup.isEmpty()) {
            throw new AuraHandledException('An account with this email and program already exists. Please login.');
        }
    }

    @TestVisible
    private static Boolean emailAlreadyRegistered(String email) {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE Username = :email OR Email = :email
            LIMIT 1
        ];

        if (!users.isEmpty()) {
            return true;
        }

        return false;
    }

    @TestVisible
    private static String generateOtp() {
        Integer randomInt = Math.abs(Crypto.getRandomInteger());
        Integer fourDigitOtp = Math.mod(randomInt, 9000) + 1000;
        return String.valueOf(fourDigitOtp);
    }

    @TestVisible
    private static Id saveOtpInformation(String email, String otpNumberEmail, Id accountId) {
        if (!Schema.sObjectType.Ken_One_Time_Password__c.isCreateable()) {
        return null;
    }
        Ken_One_Time_Password__c otp = new Ken_One_Time_Password__c();
        otp.Email__c = email;
        otp.Person_Account__c = accountId;
        otp.OTP__c = otpNumberEmail;
        otp.Expiry__c = System.now().addMinutes(OTP_EXPIRY_MINUTES);

        insert otp;
        return otp.Id;
    }

    @TestVisible
    private static void sendEmail(String email, Id otpId) {
        if (Test.isRunningTest() && !bypassEmailGuardInTests) {
            return;
        }

        Alumni_Email_Settings__c emailSettings = Alumni_Email_Settings__c.getOrgDefaults();
        if (emailSettings != null && emailSettings.Bypass_Otp_Email_Template__c) {
            return;
        }

        List<Ken_One_Time_Password__c> otp = [
            SELECT Id, OTP__c
            FROM Ken_One_Time_Password__c
            WHERE Id = :otpId
            LIMIT 1
        ];

        List<EmailTemplate> templates = [
            SELECT Id,HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :OTP_EMAIL_TEMPLATE
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            throw new AuraHandledException('OTP email template is missing. Please contact your administrator.');
        }

        List<OrgWideEmailAddress> orgIds = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :ORG_WIDE_NAME
            LIMIT 1
        ];

        EnhancedLetterhead lh;
        try {
            lh = [
                SELECT LetterheadHeader, LetterheadFooter
                FROM EnhancedLetterhead
                WHERE Name = 'Alumni Letterhead'
                LIMIT 1
            ];
        } catch (Exception e) {
            lh = null;
        }

        String letterheadHeader = lh != null && lh.LetterheadHeader != null ? lh.LetterheadHeader : '';

        String letterheadFooter = lh != null && lh.LetterheadFooter != null ? lh.LetterheadFooter : '';

         // Fetch Custom Setting once
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c) ? orgParam.Institution_Alias__c : '';

        EmailTemplate template = templates[0];
        String otpnum = otp[0].OTP__c;
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