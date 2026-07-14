/**
 * @description Class responsible for handling alumni onboarding workflows,
 *              including sending and verifying onboarding OTPs,
 *              managing role-based onboarding states,
 *              sending user notifications via email,
 *              configuring the Ken alumni onboarding process,
 *              and saving profile-related URLs.
 */

public without sharing class KenPortalOnbordingController {
    
    @TestVisible private static final String PERSON_ACCOUNT_RT = 'Alumni_Person_Account';
    @TestVisible private static final Integer ONBOARD_OTP_EXPIRY_MINUTES = 2;
    @TestVisible private static final String ONBOARD_OTP_EMAIL_TEMPLATE = 'Otp_Email_Template_1703842542947';
    @TestVisible private static final String ONBOARD_ORG_WIDE_NAME = 'Alumni Management';
    @TestVisible private static final String MSG_MISSING_EMAIL = 'Email is required to reset password.';
    @TestVisible private static final String MSG_USER_NOT_FOUND = 'User credentials not found. Please check the email entered.';
    @TestVisible private static final String MSG_EXPIRED_OTP = 'Your OTP has expired. Please request a new one.';
    @TestVisible private static final String MSG_INVALID_OTP = 'The OTP you entered is invalid. Please try again.';
    @TestVisible private static final String REG_STATUS_UNREGISTERED = 'Unregistered';
    @TestVisible private static final String REG_STATUS_VERIFIED = 'Verified';
    @TestVisible private static final String REG_STATUS_REGISTERED = 'Registered';
    @TestVisible private static final String REG_STATUS_INITIAL_LOGIN_DONE = 'Initial Login Done';
    private static final String ROLETYPE_ALUMNI = 'Alumni';
    private static Map<String, String> Employment_Type_By_Lower = null;
    /**
     * @description Wrapper representing the current onboarding state
     *              of an alumni user.
     */
    
    public class OnboardingState {
        @AuraEnabled public Boolean isVerified;
        @AuraEnabled public String email;
        @AuraEnabled public Boolean verificationRequired;
    }
    /**
     * @description Data transfer object used for sending and receiving
     *              alumni profile information during onboarding.
     */
    
    public class ProfilePayload {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phoneNumber;
        @AuraEnabled public String linkedinUrl;
        @AuraEnabled public String twitterUrl;
        @AuraEnabled public String country;
        @AuraEnabled public String state;
        @AuraEnabled public String currentCity;
        @AuraEnabled public String graduationYear;
        @AuraEnabled public String programme;
        @AuraEnabled public String programmeId;
        @AuraEnabled public Boolean agreeToTerms;
        @AuraEnabled public String profileImageUrl;
    }
    /**
     * @description Sends an onboarding OTP to the specified email address
     *              for alumni verification.
     *
     * @param email     Email address to send the onboarding OTP.
     * @param accountId Person Account Id associated with the user.
     */
    
    // === Onboarding OTP ===
    @AuraEnabled
    public static void sendOnboardingOtp(String email, String accountId, String roleId, String token) {
        if (String.isBlank(email)) {
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }

        Id roleRecordId = normalizeId(roleId);
        Id resolvedAccountId = resolveAccountId(normalizeId(accountId), roleRecordId);
        Account pa = getPersonAccountForContext(resolvedAccountId);
        if (pa == null) {
            throw new AuraHandledException('NO_PERSON_ACCOUNT');
        }
        ensureAlumniRoleExists(roleRecordId, pa.Id);
        
        String otpCode = generateOtp();
        Id otpId = saveOtp(email, otpCode, pa.Id);
        sendOtpEmail(email, otpId);
    }
    /**
     * @description Verifies the onboarding OTP, updates registration status,
     *              and logs in the alumni user if verification succeeds.
     *
     * @param email      Email address used for OTP verification.
     * @param otpEntered OTP value entered by the user.
     * @param accountId  Person Account Id of the alumni user.
     * @return           Redirect URL for onboarding or login flow.
     */
    
    @AuraEnabled
    public static String verifyOnboardingOtp(String email, String otpEntered, String accountId, String roleId, String token) {
        if (String.isBlank(email)) {
            throw new AuraHandledException(MSG_MISSING_EMAIL);
        }
        if (String.isBlank(otpEntered)) {
            throw new AuraHandledException('Please enter the OTP sent to your email.');
        }

        Id roleRecordId = normalizeId(roleId);
        Id resolvedAccountId = resolveAccountId(normalizeId(accountId), roleRecordId);
        Account pa = getPersonAccountForContext(resolvedAccountId);
        if (pa == null) {
            throw new AuraHandledException('NO_PERSON_ACCOUNT');
        }
        ensureAlumniRoleExists(roleRecordId, pa.Id);
        
        Ken_One_Time_Password__c otp = fetchLatestActiveOtp(email, pa.Id);
        
        if (otp == null || otp.Expiry__c < System.now()) {
            throw new AuraHandledException(MSG_EXPIRED_OTP);
        }
        
        if (otp.OTP__c != otpEntered) {
            throw new AuraHandledException(MSG_INVALID_OTP);
        }
        
        otp.IsActive__c = false;
        update otp;
        
        if (String.isNotBlank(email)) {
            updateConstituentRoleEmail(roleRecordId, pa.Id, email);
            try {
                updateLeadDetails(pa.Id, roleRecordId, email);
            } catch (Exception ex) {
                System.debug('OTP verify: lead sync skipped. ' + ex.getMessage());
            }
            try {
                if (String.isNotBlank(token)) {
                    expireLeadTokenByToken(token);
                } else {
                    expireLeadTokenByCriteria(pa.Id, roleRecordId, email);
                }
            } catch (Exception ex) {
                System.debug('OTP verify: lead token expiry skipped. ' + ex.getMessage());
            }
        }
        updateRegistrationStatus(roleRecordId, pa.Id, REG_STATUS_VERIFIED);
        KenAlumniOnboardingService.UserLoginInfo info = KenAlumniOnboardingService.getLatestLoginInfo(pa.Id);
        if (info != null && info.user != null && String.isNotBlank(info.tempPassword)) {
            return KenCommunityLoginController.login(
                info.user.Username,
                info.tempPassword,
                '/alumni/onboarding-form?roleId=' + roleRecordId
            ).url;
        }
        return null;
    }

    /**
     * @description Completes onboarding verification WITHOUT an OTP, for orgs where
     *              Alumni_Org_Parameters__c.Constituent_Role_Verification_Required__c
     *              is false. The magic-link click is treated as sufficient proof, so
     *              this mirrors verifyOnboardingOtp's tail — mark the role Verified,
     *              expire the lead token, and log the user in — but skips the code check.
     *
     * @return Redirect/login URL for the onboarding form, or null if no login was issued.
     */
    @AuraEnabled
    public static String autoVerifyOnboarding(String email, String accountId, String roleId, String token) {
        Id roleRecordId = normalizeId(roleId);
        Id resolvedAccountId = resolveAccountId(normalizeId(accountId), roleRecordId);
        Account pa = getPersonAccountForContext(resolvedAccountId);
        if (pa == null) {
            throw new AuraHandledException('NO_PERSON_ACCOUNT');
        }
        ensureAlumniRoleExists(roleRecordId, pa.Id);

        String resolvedEmail = String.isNotBlank(email) ? email : pa.PersonEmail;
        if (String.isNotBlank(resolvedEmail)) {
            updateConstituentRoleEmail(roleRecordId, pa.Id, resolvedEmail);
            try {
                updateLeadDetails(pa.Id, roleRecordId, resolvedEmail);
            } catch (Exception ex) {
                System.debug('Auto verify: lead sync skipped. ' + ex.getMessage());
            }
            try {
                if (String.isNotBlank(token)) {
                    expireLeadTokenByToken(token);
                } else {
                    expireLeadTokenByCriteria(pa.Id, roleRecordId, resolvedEmail);
                }
            } catch (Exception ex) {
                System.debug('Auto verify: lead token expiry skipped. ' + ex.getMessage());
            }
        }
        updateRegistrationStatus(roleRecordId, pa.Id, REG_STATUS_VERIFIED);
        KenAlumniOnboardingService.UserLoginInfo info = KenAlumniOnboardingService.getLatestLoginInfo(pa.Id);

        if (info != null && info.user != null && String.isNotBlank(info.tempPassword)) {
            return KenCommunityLoginController.login(
                info.user.Username,
                info.tempPassword,
                '/alumni/onboarding-form?roleId=' + roleRecordId
            ).url;
        }
        return null;
    }
    /**
     * @description Retrieves the current onboarding verification state
     *              for the given person account.
     *
     * @param accountId Person Account Id of the alumni user.
     * @return          OnboardingState containing verification status and email.
     */
    
    @AuraEnabled(cacheable=false)
    public static OnboardingState getOnboardingState(String accountId, String roleId) {
        Id roleRecordId = normalizeId(roleId);
        Id resolvedAccountId = resolveAccountId(normalizeId(accountId), roleRecordId);
        Account pa = getPersonAccountForContext(resolvedAccountId);
        if (pa == null) {
            throw new AuraHandledException('NO_PERSON_ACCOUNT');
        }
        OnboardingState state = new OnboardingState();
        state.isVerified = false;
        state.email = pa.PersonEmail;

        ConstituentRole cr = fetchAlumniRoleById(roleRecordId, pa.Id);
        if (cr != null) {
            state.isVerified = cr.Registration_Status__c == REG_STATUS_VERIFIED ||
                cr.Registration_Status__c == REG_STATUS_REGISTERED ||
                cr.Registration_Status__c == REG_STATUS_INITIAL_LOGIN_DONE;
            if (String.isNotBlank(cr.Email__c)) {
                state.email = cr.Email__c;
            }
        }

        // OTP verification is required by default; admins can switch it off via
        // Alumni_Org_Parameters__c so onboarding skips the verification screen.
        state.verificationRequired = true;
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        if (orgParam != null && orgParam.Constituent_Role_Verification_Required__c == false) {
            state.verificationRequired = false;
        }
        return state;
    }
    /**
     * @description Wrapper representing an alumni employment record
     *              used for UI data exchange.
     */
    
    public class EmploymentRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String jobTitle;
        @AuraEnabled public String organization;
        @AuraEnabled public String startDate;
        @AuraEnabled public String endDate;
        @AuraEnabled public Boolean isCurrentJob;
        @AuraEnabled public String industry;
        @AuraEnabled public String location;
        @AuraEnabled public String roleDescription;
        @AuraEnabled public String country;
        @AuraEnabled public String roleSummary;
        @AuraEnabled public String employmentType;
        @AuraEnabled public String jobRole;
    }
    /**
     * @description Generic response wrapper indicating success or failure
     *              of a save operation.
     */
    
    public class SaveResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }
    /**
     * @description Generic label-value pair used for dropdown and
     *              selection options.
     */
    
    public class OptionValue {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }
    /**
     * @description Retrieves the basic profile details of the currently
     *              logged-in alumni user.
     *
     * @return ProfilePayload containing basic profile information.
     */
    
    @AuraEnabled(cacheable=false)
    public static ProfilePayload getBasicProfile(String roleId) {
        Id roleRecordId = normalizeId(roleId);
        Id accountIdFromRole = getAccountIdByRole(roleRecordId);
        Account pa = accountIdFromRole != null
            ? fetchPersonAccountById(accountIdFromRole)
            : getCurrentUserPersonAccount();
        if (pa == null) {
            return null;
        }
        
        return buildProfilePayload(pa.Id, roleRecordId);
    }
    
    @TestVisible
    private static Account fetchPersonAccountByEmail(String email) {
        if (String.isBlank(email)) {
            return null;
        }
        
        List<Account> accounts = [
            SELECT Id, RecordTypeId, FirstName, LastName, PersonEmail, Phone, PersonMobilePhone, Linkedin_Profile_URL__c, Twitter_Profile_URL__c
            FROM Account
            WHERE PersonEmail = :email
            AND IsPersonAccount = true
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }
    
    private static Account fetchPersonAccountById(Id accountId) {
        if (accountId == null) {
            return null;
        }

        List<Account> accounts = [
            SELECT Id, RecordTypeId, FirstName, LastName, PersonEmail,
                   Phone, PersonMobilePhone, Linkedin_Profile_URL__c, Twitter_Profile_URL__c
            FROM Account
            WHERE Id = :accountId
            AND IsPersonAccount = true
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }
    /**
     * @description Saves or updates the basic alumni profile information
     *              provided during onboarding.
     *
     * @param requestJson JSON string containing profile details.
     * @return            ProfilePayload indicating save status and account Id.
     */
    
    @AuraEnabled(cacheable=false)
    public static ProfilePayload saveBasicProfile(String requestJson, String roleId) {
        
        
        if (String.isBlank(requestJson)) {
            throw new AuraHandledException('INVALID_REQUEST');
        }
        
        ProfilePayload request;
        try {
            // Manually deserialize the JSON string into ProfilePayload
            request = (ProfilePayload) JSON.deserialize(requestJson, ProfilePayload.class);
            
        } catch (Exception e) {
            
            throw new AuraHandledException('Invalid request format: ' + e.getMessage());
        }
        
        if (String.isNotBlank(request.profileImageUrl)) {
            request.profileImageUrl = resolveProfileImageUrl(request.profileImageUrl, request.email);
        }

        Id roleRecordId = normalizeId(roleId);
        Id accountIdFromRole = getAccountIdByRole(roleRecordId);
        Account personAccount = accountIdFromRole != null
            ? fetchPersonAccountById(accountIdFromRole)
            : upsertPersonAccount(request.email, request);
        if (personAccount == null) {
            personAccount = upsertPersonAccount(request.email, request);
        }
        updatePersonAccount(personAccount, request);
        upsertKenAlumniProfile(personAccount.Id, roleRecordId, request);
        upsertKenAddress(personAccount.Id, request);
        updateConstituentRoleProgram(roleRecordId, personAccount.Id, request.programmeId, request.programme, request.graduationYear);
        
        ProfilePayload response = new ProfilePayload();
        response.success = true;
        response.message = 'Basic profile saved successfully.';
        response.accountId = personAccount != null ? personAccount.Id : null;
        return response;
        
        
    }
    
    @TestVisible
    private static String resolveProfileImageUrl(String imageValue, String email) {
        if (String.isBlank(imageValue)) {
            return imageValue;
        }
        
        if (imageValue.startsWith('http://') || imageValue.startsWith('https://')) {
            return imageValue;
        }
        
        if (!imageValue.startsWith('data:') || !imageValue.contains('base64,')) {
            return imageValue;
        }
        
        String base64Data = imageValue.substringAfter('base64,');
        String extension = extractFileExtension(imageValue);
        String safeEmail = String.isNotBlank(email) ? email.replace('@', '_').replace('.', '_') : 'user';
        String title = 'profile_' + safeEmail + '_' + String.valueOf(System.now().getTime()) + extension;
        return KenCreateContentVersion.createContentVersion(title, base64Data);
    }
    
    @TestVisible
    private static String extractFileExtension(String dataUrl) {
        if (String.isBlank(dataUrl)) {
            return '.png';
        }
        
        String mime = '';
        if (dataUrl.startsWith('data:') && dataUrl.contains(';')) {
            mime = dataUrl.substringBetween('data:', ';');
        }
        
        if (mime == 'image/jpeg') {
            return '.jpg';
        }
        if (mime == 'image/png') {
            return '.png';
        }
        if (mime == 'image/svg+xml') {
            return '.svg';
        }
        if (mime == 'image/webp') {
            return '.webp';
        }
        return '.png';
    }
    
    @TestVisible
    private static Account upsertPersonAccount(String email, ProfilePayload request) {
        Account personAccount = String.isBlank(email) ? null : fetchPersonAccountByEmail(email);
        
        if (personAccount == null) {
            personAccount = new Account();
            Schema.RecordTypeInfo paRtInfo = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(PERSON_ACCOUNT_RT);
            if (paRtInfo == null) {
                throw new AuraHandledException('Person Account record type is missing. Please contact your administrator.');
            }
            personAccount.RecordTypeId = paRtInfo.getRecordTypeId();
        }
        
        return personAccount;
    }
    
    private static void updatePersonAccount(Account personAccount, ProfilePayload request) {
        if (personAccount == null || request == null) {
            return;
        }
        if (personAccount.Id == null && !Schema.sObjectType.Account.isCreateable()) {
            return;
        }
        if (personAccount.Id != null && !Schema.sObjectType.Account.isUpdateable()) {
            return;
        }
        
        personAccount.FirstName = String.isNotBlank(request.firstName) ? request.firstName : null;
        personAccount.LastName = String.isNotBlank(request.lastName) ? request.lastName : 'User';
        if (String.isNotBlank(request.email)) {
            personAccount.PersonEmail = request.email;
        }
        personAccount.Phone = request.phoneNumber;
        if (String.isNotBlank(request.phoneNumber)) {
            personAccount.PersonMobilePhone = request.phoneNumber;
        }
        personAccount.Linkedin_Profile_URL__c = request.linkedinUrl;
        personAccount.Twitter_Profile_URL__c = request.twitterUrl;
        
        
        if (personAccount.Id == null) {
            insert personAccount;
        } else {
            update personAccount;
        }
    }
    
    @TestVisible
    private static Id testCurrentAccountId;

    private static Id getCurrentUserAccountId() {
        if (Test.isRunningTest() && testCurrentAccountId != null) {
            return testCurrentAccountId;
        }
        Id userId = UserInfo.getUserId();
        if (userId == null) {
            return null;
        }

        List<User> users = [
            SELECT AccountId
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].AccountId;
    }
    
    private static Account getPersonAccountForContext(Id accountIdParam) {
        Id resolved = accountIdParam != null ? accountIdParam : getCurrentUserAccountId();
        return resolved == null ? null : fetchPersonAccountById(resolved);
    }

    private static Id resolveAccountId(Id accountIdParam, Id roleIdParam) {
        if (accountIdParam != null) {
            return accountIdParam;
        }
        Id accountIdFromRole = getAccountIdByRole(roleIdParam);
        if (accountIdFromRole != null) {
            return accountIdFromRole;
        }
        return getCurrentUserAccountId();
    }

    private static Id getAccountIdByRole(Id roleId) {
        if (roleId == null) {
            return null;
        }
        List<ConstituentRole> roles = [
            SELECT PersonId
            FROM ConstituentRole
            WHERE Id = :roleId
            AND RoleType = :ROLETYPE_ALUMNI
            LIMIT 1
        ];
        return roles.isEmpty() ? null : roles[0].PersonId;
    }
    
    private static Account getCurrentUserPersonAccount() {
        Id accountId = getCurrentUserAccountId();
        return accountId == null ? null : fetchPersonAccountById(accountId);
    }
    
    // Safe Id parsing for values coming from the client/session
    private static Id normalizeId(String rawId) {
        if (String.isBlank(rawId)) {
            return null;
        }
        try {
            return (Id) rawId;
        } catch (Exception e) {
            return null;
        }
    }
    
    private static ProfilePayload buildProfilePayload(Id accountId, Id roleId) {
        if (accountId == null) {
            return null;
        }
        
        Account pa = fetchPersonAccountById(accountId);
        if (pa == null) {
            return null;
        }
        
        ConstituentRole alumniRole = fetchAlumniRoleById(roleId, accountId);
        
        List<Ken_Alumni_CRM__c> alumniList = [
            SELECT Agree_to_T_C__c, Program__c, Profile_Photo_URL__c
            FROM Ken_Alumni_CRM__c
            WHERE ConstituentRole__c = :roleId
            LIMIT 1
        ];

        List<Ken_Address__c> addressList = [
            SELECT City__c, State__c, Country__c
            FROM Ken_Address__c
            WHERE Person_Account__c = :accountId
            AND Address_Type__c = 'Mailing'
            LIMIT 1
        ];

        ProfilePayload data = new ProfilePayload();
        data.accountId = pa.Id;
        data.firstName = pa.FirstName;
        data.lastName = pa.LastName;
        data.email = alumniRole != null && !String.isBlank(alumniRole.Email__c) ? alumniRole.Email__c : pa.PersonEmail;
        data.phoneNumber = String.isNotBlank(pa.Phone) ? pa.Phone : pa.PersonMobilePhone;
        data.linkedinUrl = pa.Linkedin_Profile_URL__c;
        data.twitterUrl = pa.Twitter_Profile_URL__c;
        
        // Program + Graduation Year prefer the ConstituentRole (set by Lead
        // conversion) and fall back to Ken_Alumni_CRM__c when no role is
        // attached. Previously these only filled when the CRM row existed,
        // which left the onboarding form blank for fresh leads.
        if (alumniRole != null) {
            data.programme = String.isNotBlank(alumniRole.Program_Plan__c) ? alumniRole.Program_Plan__c : null;
            data.graduationYear = String.isNotBlank(alumniRole.Graduation_Year__c) ? alumniRole.Graduation_Year__c : null;
            data.programmeId = data.programme;
        }
        if (!alumniList.isEmpty()) {
            Ken_Alumni_CRM__c alumni = alumniList[0];
            data.agreeToTerms = alumni.Agree_to_T_C__c;
            if (String.isBlank(data.programme)) {
                data.programme   = alumni.Program__c;
                data.programmeId = data.programme;
            }
            data.profileImageUrl = alumni.Profile_Photo_URL__c;
        }
        if (!addressList.isEmpty()) {
            Ken_Address__c address = addressList[0];
            data.country = address.Country__c;
            data.state = address.State__c;
            data.currentCity = address.City__c;
        }
        
        return data;
    }
    
    
    // === Address + Alumni CRM ===
    @TestVisible
    private static Ken_Address__c upsertKenAddress(Id accountId, ProfilePayload request) {
        if (accountId == null) {
            return null;
        }
        if (!Schema.sObjectType.Ken_Address__c.isAccessible()) {
            return null;
        }
        
        Ken_Address__c address;
        List<Ken_Address__c> existingAddresses = [
            SELECT Id, City__c, Country__c, State__c, Address_Type__c, Person_Account__c
            FROM Ken_Address__c
            WHERE Person_Account__c = :accountId
            AND Address_Type__c = 'Mailing'
            LIMIT 1
        ];
        if (!existingAddresses.isEmpty()) {
            address = existingAddresses[0];
            if (!Schema.sObjectType.Ken_Address__c.isUpdateable()) {
                return address;
            }
        } else {
            if (!Schema.sObjectType.Ken_Address__c.isCreateable()) {
                return null;
            }
            address = new Ken_Address__c();
            address.Person_Account__c = accountId;
            address.Address_Type__c = 'Mailing';
        }
        
        address.City__c = request != null ? request.currentCity : null;
        address.Country__c = request != null ? request.country : null;
        address.State__c = request != null ? request.state : null;
        
        if (address.Id == null) {
            insert address;
        } else {
            update address;
        }
        
        return address;
    }
    
    @TestVisible
    private static Ken_Alumni_CRM__c upsertKenAlumniProfile(Id accountId, ProfilePayload request) {
        return upsertKenAlumniProfile(accountId, null, request);
    }

    @TestVisible
    private static Ken_Alumni_CRM__c upsertKenAlumniProfile(Id accountId, Id constituentRoleId, ProfilePayload request) {
        if (accountId == null || constituentRoleId == null || !Schema.sObjectType.Ken_Alumni_CRM__c.isAccessible()) {
            return null;
        }

        Ken_Alumni_CRM__c record;
        List<Ken_Alumni_CRM__c> existing = [
            SELECT Id, Agree_to_T_C__c, Program__c, Current_Location__c, Profile_Photo_URL__c
            FROM Ken_Alumni_CRM__c
            WHERE ConstituentRole__c = :constituentRoleId
            LIMIT 1
        ];

        if (!existing.isEmpty()) {
            if (!Schema.sObjectType.Ken_Alumni_CRM__c.isUpdateable()) {
                return existing[0];
            }
            record = existing[0];
        } else {
            if (!Schema.sObjectType.Ken_Alumni_CRM__c.isCreateable()) {
                return null;
            }
            record = new Ken_Alumni_CRM__c();
            record.Person_Account__c   = accountId;
            record.ConstituentRole__c  = constituentRoleId;
            record.Registration_Date__c = Date.today();
        }

        record.Agree_to_T_C__c = request.agreeToTerms != null ? request.agreeToTerms : false;
        if (request != null) {
            record.Program__c = !String.isBlank(request.programmeId) ? request.programmeId : request.programme;
        }

        if (!String.isBlank(request.profileImageUrl)) {
            record.Profile_Photo_URL__c = request.profileImageUrl;
        }

        if (record.Id == null) {
            insert record;
        } else {
            update record;
        }
        return record;
    }
    
    @TestVisible
    private static void updateConstituentRoleProgram(Id roleId, Id accountId, String programmeId, String programme, String graduationYear) {
        ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
        if (cr == null) return;
        
        String programValue = !String.isBlank(programmeId) ? programmeId : programme;
        
        Boolean programChanged = String.isNotBlank(programValue) && cr.Program_Plan__c != programValue;
        Boolean yearChanged = graduationYear != cr.Graduation_Year__c; // handles null vs value too
        
        if (programChanged || yearChanged) {
            ConstituentRole upd = new ConstituentRole(Id = cr.Id);
            if (programChanged) upd.Program_Plan__c = programValue;
            if (yearChanged) upd.Graduation_Year__c = graduationYear;
            update upd;
        }
    }
    
    
    /**
     * @description Retrieves available learning program options for
     *              alumni selection during onboarding.
     *
     * @return List of OptionValue entries representing programs.
     */
    
    // === Program Options ===
    @AuraEnabled(cacheable=true)
    public static List<OptionValue> getLearningProgramOptions() {
        List<OptionValue> results = new List<OptionValue>();
        Schema.DescribeFieldResult dfr = ConstituentRole.Program_Plan__c.getDescribe();
        Schema.DisplayType fieldType = dfr.getType();
        
        if (fieldType == Schema.DisplayType.Picklist || fieldType == Schema.DisplayType.MultiPicklist) {
            for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
                if (entry == null || String.isBlank(entry.getValue())) {
                    continue;
                }
                OptionValue opt = new OptionValue();
                opt.label = entry.getLabel();
                opt.value = entry.getValue();
                results.add(opt);
            }
        } else if (fieldType == Schema.DisplayType.Reference) {
            List<Schema.SObjectType> refs = dfr.getReferenceTo();
            if (!refs.isEmpty()) {
                String targetObject = refs[0].getDescribe().getName();
                try {
                    List<SObject> rows = Database.query('SELECT Id, Name FROM ' + targetObject + ' ORDER BY Name LIMIT 200');
                    for (SObject row : rows) {
                        String idVal = (String) row.get('Id');
                        String nameVal = (String) row.get('Name');
                        if (String.isBlank(idVal) || String.isBlank(nameVal)) {
                            continue;
                        }
                        OptionValue opt = new OptionValue();
                        opt.label = nameVal;
                        opt.value = idVal;
                        results.add(opt);
                    }
                } catch (Exception e) {
                    throw new AuraHandledException(
                        'unable to load learning program options:'+ e.getmessage()
                        );
                }
            }
        }
        return results;
    }
    /**
     * @description Retrieves active employment details for the currently
     *              logged-in alumni user.
     *
     * @return List of EmploymentRecord entries for the user.
     */
    
    @AuraEnabled(cacheable=false)
    public static List<EmploymentRecord> getEmploymentDetails(String roleId) {
        List<EmploymentRecord> results = new List<EmploymentRecord>();
        
        try {
            Id roleRecordId = normalizeId(roleId);
            Id accountId = resolveAccountId(null, roleRecordId);
            if (accountId == null) {
                return results;
            }
            
            List<PersonEmployment> empRecords = [
            SELECT Id, Company_Name__c, Designation__c, EmploymentIndustry, Location__c,
                   StartDate, EndDate, Currently_Employed__c, EmploymentType, Description__c, Is_Archived__c, Job_Role__c
            FROM PersonEmployment
            WHERE AccountId = :accountId
            AND (Is_Archived__c = false OR Is_Archived__c = null)
            ORDER BY StartDate DESC
        ];

            for (PersonEmployment emp : empRecords) {
                EmploymentRecord rec = new EmploymentRecord();
                rec.id = String.valueOf(emp.Id);
                rec.organization = emp.Company_Name__c;
                rec.jobTitle = emp.Designation__c;
                rec.industry = emp.EmploymentIndustry;
                rec.location = emp.Location__c;
                rec.country = emp.Location__c;
                rec.isCurrentJob = emp.Currently_Employed__c;
                rec.startDate = emp.StartDate != null ? String.valueOf(emp.StartDate) : null;
                rec.endDate = emp.EndDate != null ? String.valueOf(emp.EndDate) : null;
                rec.employmentType = emp.EmploymentType;
                rec.roleDescription = emp.Description__c;
                rec.roleSummary = emp.Description__c;
                rec.jobRole = emp.Job_Role__c;

                results.add(rec);
            }
            
            return results;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving employment details: ' + e.getMessage());
        }
    }
    /**
     * @description Creates, updates, or archives alumni employment details
     *              based on the submitted employment data.
     *
     * @param requestJson JSON string containing employment records.
     * @return            SaveResult indicating operation success or failure.
     */
    
    @AuraEnabled
    public static SaveResult saveEmploymentDetails(String requestJson, String roleId) {
        SaveResult result = new SaveResult();
        try {
            if (String.isBlank(requestJson)) {
                throw new AuraHandledException('INVALID_REQUEST');
            }
            
            List<EmploymentRecord> records;
            try {
                records = (List<EmploymentRecord>) JSON.deserialize(requestJson, List<EmploymentRecord>.class);
            } catch (Exception e) {
                throw new AuraHandledException('Invalid request format: ' + e.getMessage());
            }
            
            Id roleRecordId = normalizeId(roleId);
            Id accountId = resolveAccountId(null, roleRecordId);
            if (accountId == null) {
                throw new AuraHandledException('NO_PERSON_ACCOUNT');
            }
            
            // Load existing employment records to update/archieve
            List<PersonEmployment> existingRecords = [
                SELECT Id, Is_Archived__c
                FROM PersonEmployment
                WHERE AccountId = :accountId
            ];
            Map<Id, PersonEmployment> existingById = new Map<Id, PersonEmployment>(existingRecords);
            Set<Id> incomingIds = new Set<Id>();

            // PersonEmployment.RelatedPersonId is required; resolve from the Person Account's Contact.
            Id relatedPersonId;
            List<Account> personAccts = [
                SELECT PersonContactId FROM Account WHERE Id = :accountId LIMIT 1
            ];
            if (!personAccts.isEmpty()) {
                relatedPersonId = personAccts[0].PersonContactId;
            }

            List<PersonEmployment> toUpsert = new List<PersonEmployment>();

            for (EmploymentRecord rec : records) {
                if (rec == null) {
                    continue;
                }

                PersonEmployment emp;
                if (isSalesforceId(rec.id) && existingById.containsKey(Id.valueOf(rec.id))) {
                    emp = existingById.get(Id.valueOf(rec.id));
                    incomingIds.add(emp.Id);
                } else {
                    emp = new PersonEmployment();
                    emp.AccountId = accountId;
                    if (relatedPersonId != null) {
                        emp.RelatedPersonId = relatedPersonId;
                    }
                }
                String companyName = rec.organization;
                // PersonEmployment.Name has the standard label "Employer" and is required. Mirror it
                // into Company_Name__c; reads use Company_Name__c.
                emp.Name = String.isNotBlank(companyName) ? companyName : 'Employer';
                emp.Company_Name__c = companyName;
                emp.Designation__c = rec.jobTitle;
                emp.EmploymentIndustry = rec.industry;
                emp.Location__c = String.isNotBlank(rec.location) ? rec.location : rec.country;
                emp.Currently_Employed__c = rec.isCurrentJob != null ? rec.isCurrentJob : false;
                emp.EmploymentType = normalizeEmploymentType(rec.employmentType);
                emp.Description__c = String.isNotBlank(rec.roleDescription) ? rec.roleDescription : rec.roleSummary;
                emp.Job_Role__c = rec.jobRole;


                // Parse dates
                emp.StartDate = String.isNotBlank(rec.startDate) ? Date.valueOf(rec.startDate) : null;
                if (!emp.Currently_Employed__c) {
                    emp.EndDate = String.isNotBlank(rec.endDate) ? Date.valueOf(rec.endDate) : null;
                } else {
                    emp.EndDate = null;
                }

                toUpsert.add(emp);
            }

            if (!toUpsert.isEmpty()) {
                upsert toUpsert;
            }

            List<PersonEmployment> toArchive = new List<PersonEmployment>();
            for (PersonEmployment existing : existingRecords) {
                if (existing.Id != null && !incomingIds.contains(existing.Id)) {
                    if (existing.Is_Archived__c != true) {
                        toArchive.add(new PersonEmployment(
                            Id = existing.Id,
                        Is_Archived__c = true
                            ));
                    }
                }
            }
            
            if (!toArchive.isEmpty()) {
                update toArchive;
            }
            
            result.success = true;
            result.message = 'Employment details saved successfully.';
            return result;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving employment details: ' + e.getMessage());
        }
    }
    /**
     * @description Saves alumni engagement and communication preferences
     *              and updates registration status.
     *
     * @param preferences Engagement preferences data.
     * @return            SaveResult indicating save outcome.
     */
    
    // === Engagement ===
    @AuraEnabled
    public static SaveResult saveEngagementPreferences(String preferences, String roleId) {
        SaveResult result = new SaveResult();
        
        try {
            Id roleRecordId = normalizeId(roleId);
            Id accountId = resolveAccountId(null, roleRecordId);
            if (accountId == null) {
                throw new AuraHandledException('NO_PERSON_ACCOUNT');
            }
            
            List<Ken_Alumni_CRM__c> crms = [
                SELECT Id, Preferences__c, Engagement_Preferences__c
                FROM Ken_Alumni_CRM__c
                WHERE ConstituentRole__c = :roleRecordId
                LIMIT 1
            ];

            Ken_Alumni_CRM__c crm;
            if (!crms.isEmpty()) {
                crm = crms[0];
            } else {
                crm = new Ken_Alumni_CRM__c();
                crm.Person_Account__c  = accountId;
                crm.ConstituentRole__c = roleRecordId;
            }

            // Semicolon-separated names from the configurable
            // Ken_Engagement_Preference__c object. Stored as plain text so
            // admin-added preferences save without restricted-picklist errors
            // (Preferences__c is a restricted multiselect and stays legacy-only).
            String prefText = preferences == null ? '' : preferences;
            if (prefText.length() > 255) {
                prefText = prefText.substring(0, 255);
            }
            crm.Engagement_Preferences__c = prefText;
            
            if (!Schema.sObjectType.Ken_Alumni_CRM__c.isCreateable() ||
            !Schema.sObjectType.Ken_Alumni_CRM__c.isUpdateable()) {
                throw new AuraHandledException('INSUFFICIENT_ACCESS');
            }
            upsert crm;
            updateRegistrationStatus(roleRecordId, accountId, REG_STATUS_REGISTERED);
            
            result.success = true;
            result.message = 'Preferences saved successfully.';
            return result;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving preferences: ' + e.getMessage());
        }
    }
    /**
     * @description Retrieves the saved engagement preferences for the
     *              currently logged-in alumni user.
     *
     * @return Engagement preferences data as a string.
     */
    
    @AuraEnabled(cacheable=false)
    public static String getEngagementPreferences(String roleId) {
        Id roleRecordId = normalizeId(roleId);
        Id accountId = resolveAccountId(null, roleRecordId);
        if (accountId == null) {
            throw new AuraHandledException('NO_PERSON_ACCOUNT');
        }
        
        List<Ken_Alumni_CRM__c> crms = [
            SELECT Preferences__c, Engagement_Preferences__c
            FROM Ken_Alumni_CRM__c
            WHERE ConstituentRole__c = :roleRecordId
            LIMIT 1
        ];
        if (crms.isEmpty()) {
            return null;
        }
        // Text field is the source of truth; fall back to the legacy
        // multiselect for alumni who saved before the switch.
        return String.isNotBlank(crms[0].Engagement_Preferences__c)
            ? crms[0].Engagement_Preferences__c
            : crms[0].Preferences__c;
    }
    /**
     * @description Marks the alumni user as having completed the initial
     *              login after onboarding.
     *
     * @return SaveResult indicating whether the update was successful.
     */
    
    @AuraEnabled
    public static SaveResult markLoggedInOnce(String roleId) {
        SaveResult result = new SaveResult();
        
        try {
            Id roleRecordId = normalizeId(roleId);
            Id accountId = resolveAccountId(null, roleRecordId);
            if (accountId == null) {
                throw new AuraHandledException('NO_PERSON_ACCOUNT');
            }
            
            ConstituentRole cr = fetchAlumniRoleById(roleRecordId, accountId);
            if (cr == null) {
                throw new AuraHandledException('ALUMNI_ROLE_NOT_FOUND');
            }
            
            if (cr.Registration_Status__c != REG_STATUS_INITIAL_LOGIN_DONE) {
                update new ConstituentRole(
                    Id = cr.Id,
                    Registration_Status__c = REG_STATUS_INITIAL_LOGIN_DONE
                    );
            }
            
            result.success = true;
            result.message = 'Marked login as completed.';
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating login status: ' + e.getMessage());
        }
    }
    
    // === Employment Helpers ===
    @TestVisible
    private static String normalizeEmploymentType(String inputValue) {
        if (String.isBlank(inputValue)) {
            return null;
        }
        
        String normalized = inputValue.trim().toLowerCase();
        Map<String, String> valueByLower = getEmploymentTypeValueMap();
        if (valueByLower.containsKey(normalized)) {
            return valueByLower.get(normalized);
        }
        
        String noHyphen = normalized.replace('-', ' ');
        noHyphen = noHyphen.replaceAll('\\s+', ' ').trim();
        if (valueByLower.containsKey(noHyphen)) {
            return valueByLower.get(noHyphen);
        }
        
        return null;
    }
    
    private static Map<String, String> getEmploymentTypeValueMap() {
        if (Employment_Type_By_Lower != null) {
            return Employment_Type_By_Lower;
        }
        
        Employment_Type_By_Lower = new Map<String, String>();
        for (Schema.PicklistEntry entry : PersonEmployment.EmploymentType.getDescribe().getPicklistValues()) {
            String value = entry.getValue();
            if (String.isNotBlank(value)) {
                Employment_Type_By_Lower.put(value.toLowerCase(), value);
            }
        }
        return Employment_Type_By_Lower;
    }
    
    @TestVisible
    private static Boolean isSalesforceId(String value) {
        if (String.isBlank(value)) {
            return false;
        }
        try {
            Id temp = (Id) value;
            return temp != null;
        } catch (Exception e) {
            return false;
        }
    }
    
    @TestVisible
    private static void updateConstituentRoleEmail(Id roleId, Id accountId, String email) {
        if (roleId == null || String.isBlank(email)) {
            return;
        }

        ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
        if (cr == null || cr.Email__c == email) {
            return;
        }

        update new ConstituentRole(
            Id = cr.Id,
            Email__c = email
        );
    }

    @TestVisible
    private static Lead findLeadForRole(Id accountId, Id roleId, String email) {
        ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
        if (cr == null) {
            return null;
        }
        Id effectiveAccountId = accountId != null ? accountId : cr.PersonId;

        if (ConstituentRole.SObjectType.getDescribe().fields.getMap().containsKey('Lead__c') && cr.Lead__c != null) {
            List<Lead> byLookup = [
                SELECT Id, Email, Phone, Year_of_Graduation__c, Program_Plan__c, Registration_Number__c
                FROM Lead
                WHERE Id = :cr.Lead__c
                LIMIT 1
            ];
            if (!byLookup.isEmpty()) {
                return byLookup[0];
            }
        }

        if (String.isNotBlank(cr.Registration_Number__c)) {
            List<Lead> byReg = [
                SELECT Id, Email, Phone, Year_of_Graduation__c, Program_Plan__c, Registration_Number__c
                FROM Lead
                WHERE Registration_Number__c = :cr.Registration_Number__c
                ORDER BY CreatedDate DESC
            ];
            if (byReg.size() > 1) {
                throw new AuraHandledException('Duplicate lead detected for registration number. Please contact support.');
            }
            if (!byReg.isEmpty()) {
                return byReg[0];
            }
        }

        Set<String> candidateEmails = new Set<String>();
        if (String.isNotBlank(email)) {
            candidateEmails.add(email);
        }
        if (String.isNotBlank(cr.Email__c)) {
            candidateEmails.add(cr.Email__c);
        }
        Account pa = fetchPersonAccountById(effectiveAccountId);
        if (pa != null && String.isNotBlank(pa.PersonEmail)) {
            candidateEmails.add(pa.PersonEmail);
        }

        if (!candidateEmails.isEmpty() && cr.Program_Plan__c != null) {
            List<Lead> byProgramAndEmail = [
                SELECT Id, Email, Phone, Year_of_Graduation__c, Program_Plan__c, Registration_Number__c
                FROM Lead
                WHERE Program_Plan__c = :cr.Program_Plan__c
                AND Email IN :candidateEmails
                ORDER BY CreatedDate DESC
            ];
            if (!byProgramAndEmail.isEmpty()) {
                return byProgramAndEmail[0];
            }
        }

        if (!candidateEmails.isEmpty()) {
            List<Lead> byEmail = [
                SELECT Id, Email, Phone, Year_of_Graduation__c, Program_Plan__c, Registration_Number__c
                FROM Lead
                WHERE Email IN :candidateEmails
                ORDER BY CreatedDate DESC
            ];
            if (!byEmail.isEmpty()) {
                if (cr.Program_Plan__c != null) {
                    for (Lead l : byEmail) {
                        if (l.Program_Plan__c == cr.Program_Plan__c) {
                            return l;
                        }
                    }
                }
                return byEmail[0];
            }
        }

        return null;
    }
    
    @TestVisible
    private static void updateLeadDetails(Id accountId, Id roleId, String email) {
        if (accountId == null) {
            return;
        }
        
        List<Account> paList = [
            SELECT Id, PersonEmail, Phone, PersonMobilePhone
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        Account pa = paList.isEmpty() ? null : paList[0];
        
        if (pa == null) {
            return;
        }

        Lead lead = findLeadForRole(accountId, roleId, email);
        if (lead == null) {
            return;
        }
        
        Ken_Alumni_CRM__c crm = null;
        if (Schema.sObjectType.Ken_Alumni_CRM__c.isAccessible()) {
            List<Ken_Alumni_CRM__c> crms = [
                SELECT Id, Program__c, Year_of_Graduation__c
                FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c = :accountId
                LIMIT 1
            ];
            if (!crms.isEmpty()) {
                crm = crms[0];
            }
        }

        ConstituentRole selectedRole = fetchAlumniRoleById(roleId, accountId);
        
        Lead leadToUpdate = new Lead(
            Id = lead.Id,
            Phone = (lead != null && String.isNotBlank(lead.Phone)) ? lead.Phone : (String.isNotBlank(pa.Phone) ? pa.Phone : pa.PersonMobilePhone)
            );
        
        // Sync graduation year/program between lead and CRM
        if (crm != null) {
            if (crm.Year_of_Graduation__c != null) {
                leadToUpdate.Year_of_Graduation__c = crm.Year_of_Graduation__c;
            } else if (lead != null && lead.Year_of_Graduation__c != null) {
                crm.Year_of_Graduation__c = lead.Year_of_Graduation__c;
                update crm;
            }
            
            String programValue = selectedRole != null ? selectedRole.Program_Plan__c : null;
            if (String.isNotBlank(programValue)) {
                leadToUpdate.Program_Plan__c = programValue;
                crm.Program__c = programValue;
                if (crm != null && Schema.sObjectType.Ken_Alumni_CRM__c.isUpdateable()) {
                    update crm;
                }
            } else if (crm.Program__c != null) {
                leadToUpdate.Program_Plan__c = crm.Program__c;
            } else if (lead != null && lead.Program_Plan__c != null) {
                crm.Program__c = lead.Program_Plan__c;
                if (crm != null && Schema.sObjectType.Ken_Alumni_CRM__c.isUpdateable()) {
                    update crm;
                }
            }
        }
        
        // Sync phone back to account if missing
        if (lead != null && String.isNotBlank(lead.Phone) && String.isBlank(pa.Phone) && String.isBlank(pa.PersonMobilePhone)) {
            pa.Phone = lead.Phone;
            pa.PersonMobilePhone = lead.Phone;
            if (Schema.sObjectType.Account.isUpdateable()) {
                update pa;
            }
        }
        
        if (Schema.sObjectType.Lead.isUpdateable()) {
            update leadToUpdate;
        }
        
    }
    
    // === OTP Helpers ===
    @TestVisible
    private static void ensureAlumniRoleExists(Id roleId, Id accountId) {
        ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
        if (cr == null) {
            throw new AuraHandledException('ALUMNI_ROLE_NOT_FOUND');
        }
    }
    
    @TestVisible
    private static User findUserByEmail(String email) {
        List<User> users = [
            SELECT Id, AccountId
            FROM User
            WHERE Email = :email
            AND IsActive = true 
            LIMIT 1
        ];
        
        if (users.isEmpty()) {
            throw new AuraHandledException(MSG_USER_NOT_FOUND);
        }
        
        return users[0];
    }
    
    @TestVisible
    private static void expireLeadTokenByToken(String token) {
        if (String.isBlank(token) || !Schema.sObjectType.Lead.isUpdateable()) {
            return;
        }
        List<Lead> leads = [
            SELECT Id
            FROM Lead
            WHERE Verification_Token__c = :token
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            return;
        }
        update new Lead(
            Id = leads[0].Id,
            Verification_Token__c = null,
            Token_Expiration_Date__c = null
        );
    }

    @TestVisible
    private static void expireLeadTokenByCriteria(Id accountId, Id roleId, String email) {
        if (!Schema.sObjectType.Lead.isUpdateable()) {
            return;
        }
        Lead lead = findLeadForRole(accountId, roleId, email);
        if (lead == null) {
            return;
        }
        update new Lead(
            Id = lead.Id,
            Verification_Token__c = null,
            Token_Expiration_Date__c = null
            );
    }
    
    @TestVisible
    private static String generateOtp() {
        Integer randomInt = Math.abs(Crypto.getRandomInteger());
        Integer fourDigitOtp = Math.mod(randomInt, 9000) + 1000;
        return String.valueOf(fourDigitOtp);
    }
    
    @TestVisible
    private static Id saveOtp(String email, String otpCode, Id accountId) {
        Ken_One_Time_Password__c otp = new Ken_One_Time_Password__c();
        otp.Email__c = email;
        otp.Person_Account__c = accountId;
        otp.OTP__c = otpCode;
        otp.IsActive__c = true;
        otp.Expiry__c = System.now().addMinutes(ONBOARD_OTP_EXPIRY_MINUTES);
        if (!Schema.sObjectType.Ken_One_Time_Password__c.isCreateable()) {
            return null;
        }
        insert otp;
        return otp.Id;
    }
    
    @TestVisible
    private static Ken_One_Time_Password__c fetchLatestActiveOtp(String email, Id accountId) {
        List<Ken_One_Time_Password__c> otps = [
            SELECT Id, OTP__c, Expiry__c, IsActive__c
            FROM Ken_One_Time_Password__c
            WHERE Email__c = :email
            AND IsActive__c = true
            AND Person_Account__c = :accountId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (otps.isEmpty()) {
            return null;
        }
        return otps[0];
    }
    
    @TestVisible
    private static void sendOtpEmail(String email, Id otpId) {
        if (Test.isRunningTest()) {
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
            WHERE DeveloperName = :ONBOARD_OTP_EMAIL_TEMPLATE
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new AuraHandledException('OTP email template is missing. Please contact your administrator.');
        }
        
        List<OrgWideEmailAddress> orgIds = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :ONBOARD_ORG_WIDE_NAME
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
    
    private static Map<String, Account> getOrCreateCompanyAccounts(List<EmploymentRecord> records) {
        Map<String, Account> result = new Map<String, Account>();
        if (records == null || records.isEmpty()) {
            return result;
        }
        
        Map<String, String> nameByKey = new Map<String, String>();
        for (EmploymentRecord rec : records) {
            if (rec != null && String.isNotBlank(rec.organization)) {
                String normalized = rec.organization.trim();
                nameByKey.put(normalized.toLowerCase(), normalized);
            }
        }
        if (nameByKey.isEmpty()) {
            return result;
        }
        
        Id companyRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Company')
            .getRecordTypeId();
        
        for (Account a : [
            SELECT Id, Name
            FROM Account
            WHERE RecordTypeId = :companyRtId
            AND Name IN :nameByKey.values()
        ]) {
            result.put(a.Name.trim().toLowerCase(), a);
        }
        
        List<Account> toInsert = new List<Account>();
        for (String nameKey : nameByKey.keySet()) {
            if (!result.containsKey(nameKey)) {
                String nameValue = nameByKey.get(nameKey);
                toInsert.add(new Account(
                    RecordTypeId = companyRtId,
                Name = nameValue
                    ));
            }
        }
        
        if (!toInsert.isEmpty()) {
            if (!toInsert.isEmpty() && Schema.sObjectType.Account.isCreateable()) {
                insert toInsert;
            }
            for (Account a : toInsert) {
                result.put(a.Name.trim().toLowerCase(), a);
            }
        }
        
        return result;
    }
    
    @TestVisible
    private static ConstituentRole fetchAlumniRoleById(Id roleId, Id accountId) {
        if (roleId == null) {
            return null;
        }
        List<ConstituentRole> roles;
        if (accountId != null) {
            roles = [
                SELECT Id, PersonId, Registration_Status__c, Email__c, Program_Plan__c, Graduation_Year__c, Registration_Number__c, Lead__c
                FROM ConstituentRole
                WHERE Id = :roleId
                AND PersonId = :accountId
                AND RoleType = :ROLETYPE_ALUMNI
                LIMIT 1
            ];
        } else {
            roles = [
                SELECT Id, PersonId, Registration_Status__c, Email__c, Program_Plan__c, Graduation_Year__c, Registration_Number__c, Lead__c
                FROM ConstituentRole
                WHERE Id = :roleId
                AND RoleType = :ROLETYPE_ALUMNI
                LIMIT 1
            ];
        }
        return roles.isEmpty() ? null : roles[0];
    }
    
    @TestVisible
    private static void updateRegistrationStatus(Id roleId, Id accountId, String targetStatus) {
        if (roleId == null || String.isBlank(targetStatus)) {
            return;
        }
        ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
        if (cr == null) {
            return;
        }
        if (cr.Registration_Status__c == targetStatus) {
            return;
        }
        update new ConstituentRole(
            Id = cr.Id,
        Registration_Status__c = targetStatus
            );
    }
}