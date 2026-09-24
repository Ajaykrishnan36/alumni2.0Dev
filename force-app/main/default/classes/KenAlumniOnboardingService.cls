/**
 * @description Service class responsible for alumni onboarding workflows,
 *              including lead verification, person account creation,
 *              constituent role management, and post-registration updates.
 *
 * @author
 * @since
 */


public without sharing class KenAlumniOnboardingService {
    
    private static final String PERSON_ACCOUNT_RT_DEVNAME = 'PersonAccount';
    private static final String ALUMNI_PROFILE_NAME = 'Alumni';
    // Fallback only — resolveTimezone() prefers the org parameter. This decides
    // which clock Salesforce's own screens use (reports, list views, record
    // pages); it has no bearing on stored data, which is always UTC, nor on the
    // portal's pages, which follow the visitor's device.
    private static final String DEFAULT_TIMEZONE = 'Asia/Kolkata';
    private static final String DEFAULT_LOCALE = 'en_IN';
    private static final String DEFAULT_LANGUAGE = 'en_US';
    private static final String DEFAULT_EMAIL_ENCODING = 'UTF-8';
    private static final String ROLETYPE_ALUMNI = 'Alumni';
    private static final String CR_STATUS_ACTIVE = 'Active';
    private static final String CR_STATUS_UNREGISTERED = 'Unregistered';
    private static final String CR_STATUS_REGISTERED = 'Registered';
    private static final String CR_STATUS_INITIAL_LOGIN_DONE = 'Initial Login Done';
    private static final String CR_STATUS_ONBOARDING_IN_PROGRESS = 'Onboarding In Progress';
    // Lifecycle order used to pick the furthest-progressed status when a person
    // already holds one or more roles — a new role inherits that max status so an
    // already-active alumnus skips onboarding and lands on the portal home.
    private static final Map<String, Integer> REG_STATUS_RANK = new Map<String, Integer>{
        'Unregistered' => 0,
        'Unverified' => 0,
        'Onboarding In Progress' => 1,
        'Registered' => 2,
        'Initial Login Done' => 3
    };
    private static final Integer TEMP_PWD_LEN = 12;
    private static final String INST_TYPE_OWN = 'Our Institute';
    /**
     * Bulk import brings real education rows from its own CSV columns, so it switches this
     * off rather than adding a blank-degree row per imported alumnus.
     */
    public static Boolean seedEducationOnProvision = true;
    private static final String ALUMNI_PERMISSION_SET_NAME = 'Alumni';
    private static final String SUPPORT_SERVICES_PERMISSION_SET_NAME = 'Support_And_Services_User_Access';
    @TestVisible private static final String ORG_WIDE_NAME = KenMessagingService.orgWideAddressName();
    /**
     * @description Wrapper class holding temporary login credentials
     *              generated during alumni onboarding.
     */
    public class UserLoginInfo {
        public User user;
        public String tempPassword;
        /**
         * @description Constructs a UserLoginInfo instance with the
         *              specified user and temporary password.
         *
         * @param user         Community user record.
         * @param tempPassword Temporary password generated for login.
         */
        public UserLoginInfo(User user, String tempPassword) {
            this.user = user;
            this.tempPassword = tempPassword;
        }
    }
    
    @TestVisible private static Map<Id, UserLoginInfo> latestLoginInfoByAccount = new Map<Id, UserLoginInfo>();
    @TestVisible private static Set<Id> processedAccountIdsThisTxn = new Set<Id>();

    private class ConstituentRoleResult {
        public Map<String, ConstituentRole> rolesByCompositeKey = new Map<String, ConstituentRole>();
        public Set<Id> newlyCreatedRoleIds = new Set<Id>();
    }
    /**
     * @description Processes a verified lead token, provisions required
     *              alumni records, and returns the onboarding URL.
     *
     * @param token Verification token associated with the lead.
     * @return Onboarding redirect URL for the alumni user.
     */
    @AuraEnabled
    public static String processVerifiedLead(String token) {
        try {
            if (String.isBlank(token)) {
                throw new AuraHandledException('INVALID_TOKEN');
            }
            
            Lead lead = fetchLeadByToken(token);
            validateToken(lead);
            
            Map<String, Account> paByEmail = createOrGetPersonAccounts(new List<Lead>{ lead });
            Account pa = paByEmail.get(lead.Email != null ? lead.Email.toLowerCase() : null);
            
            if (pa == null || pa.Id == null) {
                throw new AuraHandledException('NO_PERSON_ACCOUNT');
            }
            
            pa = fetchPersonAccountById(pa.Id);
            
            createOrGetAlumniPreferences(new List<Account>{ pa });
            Map<String, Lead> leadByEmail = new Map<String, Lead>();
            leadByEmail.put(lead.Email.toLowerCase(), lead);
            
            ConstituentRoleResult roleResult = createOrGetConstituentRoles(
                new List<Account>{ pa },
                leadByEmail,
                CR_STATUS_UNREGISTERED
            );

            String roleKey = buildRoleCompositeKey(pa.Id, lead.Program_Plan__c, lead.Registration_Number__c);
            ConstituentRole selectedRole = roleResult.rolesByCompositeKey.get(roleKey);
            if (selectedRole == null) {
                selectedRole = findRoleForLead(pa.Id, lead);
            }
            if (selectedRole == null || selectedRole.Id == null) {
                throw new AuraHandledException('ALUMNI_ROLE_NOT_FOUND');
            }

            // The magic link is single use, and the role's registration status is
            // what records that it has been spent: opening the link moves the role
            // off Unregistered to Onboarding In Progress. Anything ranked above
            // Unregistered therefore means this link has already been walked
            // through once, so the alumnus is sent to login instead of re-entering
            // onboarding on a role that is already underway.
            //
            // The status is the gate rather than a cleared token because the token
            // is what resendMagicLink looks the lead up by — clearing it on first
            // use left the alumnus with no way back in.
            //
            // A role inserted in this very transaction cannot have been walked
            // through before, whatever status it carries. It can be born past
            // Unregistered — createOrGetConstituentRoles gives a secondary role the
            // furthest-progressed status on the account — so without this exemption
            // an alumnus added to a second programme would be refused a link they
            // had never clicked.
            Boolean roleJustCreated = roleResult.newlyCreatedRoleIds.contains(selectedRole.Id);

            if (!roleJustCreated && isLinkAlreadyUsed(selectedRole.Registration_Status__c)) {
                throw new AuraHandledException(
                    CR_STATUS_ONBOARDING_IN_PROGRESS.equals(selectedRole.Registration_Status__c)
                        ? 'ONBOARDING_IN_PROGRESS'
                        : 'ALREADY_REGISTERED'
                );
            }
            
            return '/alumni/onboarding-form?accountId=' + pa.Id + '&roleId=' + selectedRole.Id + '&token=' + token;
            
        } catch (AuraHandledException e) {
            throw e;
        }
    }
    
    private static Lead fetchLeadByToken(String token) {
        List<Lead> leads = [
            SELECT Id, Email, FirstName, LastName, Phone, Year_of_Graduation__c, Registration_Number__c,
                   Program_Plan__c, Referred_By__c, Year_of_Enrollment__c,
                   Verification_Token__c, Token_Expiration_Date__c
            FROM Lead
            WHERE Verification_Token__c = :token
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        
        if (leads.isEmpty()) {
            throw new AuraHandledException('EXPIRED');
        }
        
        return leads[0];
    }
    
    private static void validateToken(Lead lead) {
        if (lead == null) {
            throw new AuraHandledException('EXPIRED');
        }
        
        if (lead.Token_Expiration_Date__c == null || lead.Token_Expiration_Date__c < System.now()) {
            throw new AuraHandledException('EXPIRED');
        }
        
        if (String.isBlank(lead.Email)) {
            throw new AuraHandledException('Lead email is required.');
        }
    }
    /**
     * @description Expires verification tokens for the given leads by clearing
     *              token fields and marking the leads as converted.
     *
     * @param leads List of Lead records whose tokens must be expired.
     */
    
    private static void expireTokens(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        
        
        List<Lead> toUpdate = new List<Lead>();
        
        for (Lead l : leads) {
            if (l != null && l.Id != null) {
                toUpdate.add(new Lead(
                    Id = l.Id,
                Verification_Token__c = '',
                Token_Expiration_Date__c = null,
                Status = 'Converted',
                Is_Converted__c = true
                    ));
            }
        }
        
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
        }
    }
    
    private static Account fetchPersonAccountById(Id accountId) {
        return [
            SELECT Id, FirstName, LastName, PersonEmail, PersonContactId,
                   PersonMobilePhone, Phone
            FROM Account
            WHERE Id = :accountId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }
    /**
     * @description Provisions person accounts, alumni CRM records,
     *              and constituent roles for verified leads.
     *
     * @param leads List of verified Lead records.
     */
    public static void provisionOnLeadVerification(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        
        List<Lead> validLeads = new List<Lead>();
        for (Lead l : leads) {
            if (l != null && String.isNotBlank(l.Email)) {
                validLeads.add(l);
            }
        }
        
        if (validLeads.isEmpty()) {
            return;
        }
        
        Map<String, Lead> leadByEmail = new Map<String, Lead>();
        for (Lead l : validLeads) {
            leadByEmail.put(l.Email.toLowerCase(), l);
        }
        
        Map<String, Account> paByEmail = createOrGetPersonAccounts(validLeads);
        Set<Id> accountIds = new Set<Id>();
        for (Account a : paByEmail.values()) {
            if (a != null && a.Id != null) {
                accountIds.add(a.Id);
            }
        }
        List<Account> accounts = fetchPersonAccountsByIds(accountIds);
        
        ConstituentRoleResult roleResult = createOrGetConstituentRoles(accounts, leadByEmail, CR_STATUS_UNREGISTERED);
        sendExistingUserNewRoleEmail(accounts, roleResult);
    }
    /**
     * @description Resends the magic login link for a lead identified by a
     *              verification token.
     *
     *              Throws an error if the token is invalid or expired.
     *
     * @param token Verification token associated with the lead.
     */
    
    @AuraEnabled
    public static void resendMagicLink(String token) {
        if (String.isBlank(token)) {
            throw new AuraHandledException('INVALID_TOKEN');
        }
        Lead lead = fetchLeadByToken(token);
        if (lead == null || lead.Id == null) {
            throw new AuraHandledException('EXPIRED');
        }
        KenLeadTriggerHandler.resendMagicLink(lead.Id);
    }
    /**
     * @description Updates Alumni ConstituentRole records to Registered status
     *              for person accounts matching the provided leads.
     *
     * @param leads List of leads whose related constituent roles must be updated.
     */
    
    public static void markConstituentRolesRegistered(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        
        Set<String> emails = new Set<String>();
        for (Lead l : leads) {
            if (l != null && String.isNotBlank(l.Email)) {
                emails.add(l.Email.toLowerCase());
            }
        }
        
        if (emails.isEmpty()) {
            return;
        }
        
        Map<Id, Account> accountsById = new Map<Id, Account>();
        for (Account a : [
            SELECT Id, PersonEmail
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail IN :emails
        WITH SYSTEM_MODE
        ]) {
            accountsById.put(a.Id, a);
        }
        
        if (accountsById.isEmpty()) {
            return;
        }
        
        List<ConstituentRole> toUpdate = new List<ConstituentRole>();
        for (ConstituentRole cr : [
            SELECT Id, PersonId, Registration_Status__c
            FROM ConstituentRole
            WHERE PersonId IN :accountsById.keySet()
            AND RoleType = :ROLETYPE_ALUMNI
        WITH SYSTEM_MODE
        ]) {
            if (cr.Registration_Status__c != CR_STATUS_REGISTERED) {
                toUpdate.add(new ConstituentRole(
                    Id = cr.Id,
                Registration_Status__c = CR_STATUS_REGISTERED
                    ));
            }
        }
        
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
        }
    }
    /**
     * @description Marks the given leads as converted by updating status
     *              and conversion flags.
     *
     * @param leads List of Lead records to be converted.
     */
    
    public static void markLeadsConverted(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        linkLeadsToConstituentRoles(leads);
        
        List<Lead> toUpdate = new List<Lead>();
        for (Lead l : leads) {
            if (l != null && l.Id != null && l.Status != 'Converted') {
                toUpdate.add(new Lead(
                    Id = l.Id,
                Status = 'Converted',
                Is_Converted__c = true
                    ));
            }
        }
        
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
        }
    }
    /**
     * @description Creates new Person Accounts or updates existing ones
     *              based on the provided leads, using email as the unique key.
     *
     * @param leads List of Lead records used to create or update Person Accounts.
     * @return Map of normalized email to corresponding Person Account.
     */
    
    private static Map<String, Account> createOrGetPersonAccounts(List<Lead> leads) {
        Map<String, Account> result = new Map<String, Account>();
        
        Set<String> emails = new Set<String>();
        for (Lead l : leads) {
            if (l != null && String.isNotBlank(l.Email)) {
                emails.add(l.Email.toLowerCase());
            }
        }
        
        for (Account a : [
            SELECT Id, PersonEmail, Phone
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail IN :emails
        WITH SYSTEM_MODE
        ]) {
            result.put(a.PersonEmail.toLowerCase(), a);
        }

        Set<Id> explicitAccountIds = new Set<Id>();
        for (Lead l : leads) {
            if (l == null) {
                continue;
            }
            Object existingAcct = l.getPopulatedFieldsAsMap().get(KenNamespaceUtil.qualifyCustom('Existing_Account__c'));
            if (existingAcct != null) {
                explicitAccountIds.add((Id) existingAcct);
            }
        }
        if (!explicitAccountIds.isEmpty()) {
            for (Account a : [
                SELECT Id, PersonEmail, Phone
                FROM Account
                WHERE Id IN :explicitAccountIds AND IsPersonAccount = true
            WITH SYSTEM_MODE
            ]) {
                if (String.isNotBlank(a.PersonEmail)) {
                    result.put(a.PersonEmail.toLowerCase(), a);
                }
            }
        }

        List<Account> toUpdate = new List<Account>();
        
        
        Id rtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(PERSON_ACCOUNT_RT_DEVNAME).getRecordTypeId();
        
        List<Account> toInsert = new List<Account>();
        
        for (Lead l : leads) {
            String emailKey = l.Email.toLowerCase();
            if (!result.containsKey(emailKey)) {
                toInsert.add(new Account(
                    RecordTypeId = rtId,
                FirstName = l.FirstName,
                LastName = String.isBlank(l.LastName) ? 'Alumni' : l.LastName,
                PersonEmail = l.Email,
                Phone = l.Phone
                    ));
            } else {
                Account existing = result.get(emailKey);
                if (String.isNotBlank(l.Phone) && existing.Phone != l.Phone){
                    toUpdate.add(new Account(
                        Id = existing.Id,
                    Phone = l.Phone
                        ));
                }
            }
        }
        
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, true, AccessLevel.SYSTEM_MODE);
            for (Account a : toInsert) {
                result.put(a.PersonEmail.toLowerCase(), a);
            }
        }
        
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
        }
        
        return result;
    }
    
    private static void createOrGetAlumniPreferences(List<Account> accounts) {
        Set<Id> accountIds = new Set<Id>();
        for (Account a : accounts) {
            accountIds.add(a.Id);
        }

        Set<Id> existing = new Set<Id>();
        for (Ken_Alumni_Preferences__c pref : [
            SELECT Person_Account__c
            FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c IN :accountIds
        WITH SYSTEM_MODE
        ]) {
            existing.add(pref.Person_Account__c);
        }

        List<Ken_Alumni_Preferences__c> toInsert = new List<Ken_Alumni_Preferences__c>();
        for (Id accountId : accountIds) {
            if (!existing.contains(accountId)) {
                toInsert.add(new Ken_Alumni_Preferences__c(
                    Person_Account__c                           = accountId,
                    Is_Restricted_Account__c                       = true,
                    How_often_would_you_like_to_hear_from_us__c = 'Daily',
                    Notify_in_real_time__c                      = true,
                    Who_can_invite_me_to_events__c              = 'Everyone',
                    Receive_Invited_Event_Alerts__c             = true,
                    Who_can_invite_me_to_groups__c              = 'Everyone',
                    Receive_updates_from_joined_groups__c       = true,
                    Open_to_work__c                             = true,
                    Willing_to_be_a_mentor__c                   = false
                ));
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, true, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * @description Creates or updates Alumni ConstituentRole records
     *
     * @param accounts       List of Person Accounts.
     * @param leadByEmail    Map of lowercase email to Lead record.
     * @param statusForNew   Registration status to apply for newly created roles.
     * @return Map of Person Account Id to ConstituentRole.
     */
    
    private static ConstituentRoleResult createOrGetConstituentRoles(
        List<Account> accounts,
        Map<String, Lead> leadByEmail,
        String statusForNew
    ) {
        ConstituentRoleResult result = new ConstituentRoleResult();
        if (accounts == null || accounts.isEmpty()) {
            return result;
        }
        
        Set<Id> accountIds = new Set<Id>();
        for (Account a : accounts) {
            accountIds.add(a.Id);
        }
        
        Map<Id, String> accountToExistingStatus = new Map<Id, String>();
        for (ConstituentRole cr : [
            SELECT Id, PersonId, Graduation_Year__c, Program_Plan__c, Registration_Number__c, Registration_Status__c, Email__c, Lead__c, Referred_By__c, Year_of_Enrollment__c
            FROM ConstituentRole
            WHERE PersonId IN :accountIds
            AND RoleType = :ROLETYPE_ALUMNI
        WITH SYSTEM_MODE
        ]) {
            String key = buildRoleCompositeKey(cr.PersonId, cr.Program_Plan__c, cr.Registration_Number__c);
            result.rolesByCompositeKey.put(key, cr);
            // Keep the MAX-ranked status across ALL of the person's roles, so a new
            // role inherits the furthest-progressed state (not just the first one
            // seen) — an already-active alumnus therefore stays active.
            if (String.isNotBlank(cr.Registration_Status__c)) {
                accountToExistingStatus.put(cr.PersonId,
                    higherStatus(accountToExistingStatus.get(cr.PersonId), cr.Registration_Status__c));
            }
        }
        
        List<ConstituentRole> toUpdate = new List<ConstituentRole>();
        List<ConstituentRole> toInsert = new List<ConstituentRole>();
        for (Account a : accounts) {
            Lead lead = (a.PersonEmail != null && leadByEmail != null)
                ? leadByEmail.get(a.PersonEmail.toLowerCase())
                : null;
            if (lead == null) {
                continue;
            }

            String leadProgramPlan = safeLeadString(lead, 'Program_Plan__c');
            String leadRegistrationNumber = safeLeadString(lead, 'Registration_Number__c');
            String leadGraduationYear = safeLeadString(lead, 'Year_of_Graduation__c');
            String leadEnrollmentYear = safeLeadString(lead, 'Year_of_Enrollment__c');

            Boolean isSecondaryLead =
                'Secondary'.equals((String) lead.getPopulatedFieldsAsMap().get(KenNamespaceUtil.qualifyCustom('Constituent_Role_Type__c')))
                || lead.getPopulatedFieldsAsMap().get(KenNamespaceUtil.qualifyCustom('Existing_Account__c')) != null;

            String roleKey = buildRoleCompositeKey(a.Id, leadProgramPlan, leadRegistrationNumber);
            if (isSecondaryLead || !result.rolesByCompositeKey.containsKey(roleKey)) {
                toInsert.add(new ConstituentRole(
                    PersonId = a.Id,
                    RoleType = ROLETYPE_ALUMNI,
                    Status = CR_STATUS_ACTIVE,
                    Registration_Status__c = (isSecondaryLead
                            && accountToExistingStatus.containsKey(a.Id)
                            && String.isNotBlank(accountToExistingStatus.get(a.Id)))
                        ? accountToExistingStatus.get(a.Id)
                        : statusForNew,
                    Source_Funnel__c = deriveSourceFunnel(lead),
                    Lead__c = lead.Id,
                    Registration_Number__c = leadRegistrationNumber,
                    Program_Plan__c = leadProgramPlan,
                    Email__c = a.PersonEmail,
                    EffectiveStartDate = Date.today(),
                    Graduation_Year__c = leadGraduationYear,
                    Year_of_Enrollment__c = leadEnrollmentYear,
                    Referred_By__c = (Id) lead.getPopulatedFieldsAsMap().get(KenNamespaceUtil.qualifyCustom('Referred_By__c'))
                ));
            } else {
                ConstituentRole existing = result.rolesByCompositeKey.get(roleKey);
                Boolean needsUpdate = false;
                ConstituentRole upd = new ConstituentRole(Id = existing.Id);
                if (leadGraduationYear != null && existing.Graduation_Year__c != leadGraduationYear) {
                    upd.Graduation_Year__c = leadGraduationYear;
                    needsUpdate = true;
                }
                if (String.isNotBlank(leadRegistrationNumber) && existing.Registration_Number__c != leadRegistrationNumber) {
                    upd.Registration_Number__c = leadRegistrationNumber;
                    needsUpdate = true;
                }
                if (leadProgramPlan != null && existing.Program_Plan__c != leadProgramPlan) {
                    upd.Program_Plan__c = leadProgramPlan;
                    needsUpdate = true;
                }
                if (leadEnrollmentYear != null && existing.Year_of_Enrollment__c != leadEnrollmentYear) {
                    upd.Year_of_Enrollment__c = leadEnrollmentYear;
                    needsUpdate = true;
                }
                if (String.isNotBlank(a.PersonEmail) && existing.Email__c != a.PersonEmail) {
                    upd.Email__c = a.PersonEmail;
                    needsUpdate = true;
                }
                if (existing.Lead__c != lead.Id) {
                    upd.Lead__c = lead.Id;
                    needsUpdate = true;
                }
                // Read through getPopulatedFieldsAsMap like every other lead field here.
                // Direct access throws SObjectException for callers that pass a partially
                // queried Lead, which is exactly what the trigger and batch paths do.
                Id leadReferredBy = (Id) lead.getPopulatedFieldsAsMap().get(KenNamespaceUtil.qualifyCustom('Referred_By__c'));
                if (existing.Referred_By__c == null && leadReferredBy != null) {
                    upd.Referred_By__c = leadReferredBy;
                    needsUpdate = true;
                }
                if (needsUpdate) {
                    toUpdate.add(upd);
                }
            }
        }
        
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, true, AccessLevel.SYSTEM_MODE);
            for (ConstituentRole cr : toInsert) {
                String key = buildRoleCompositeKey(cr.PersonId, cr.Program_Plan__c, cr.Registration_Number__c);
                result.rolesByCompositeKey.put(key, cr);
                result.newlyCreatedRoleIds.add(cr.Id);
            }
        }
        
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
            for (ConstituentRole cr : [
                SELECT Id, PersonId, Graduation_Year__c, Program_Plan__c, Registration_Number__c, Registration_Status__c, Email__c, Lead__c, Year_of_Enrollment__c
                FROM ConstituentRole
                WHERE Id IN :new Map<Id, ConstituentRole>(toUpdate).keySet()
            WITH SYSTEM_MODE
            ]) {
                String key = buildRoleCompositeKey(cr.PersonId, cr.Program_Plan__c, cr.Registration_Number__c);
                result.rolesByCompositeKey.put(key, cr);
            }
        }

        seedEducationForNewRoles(result, accounts);

        return result;
    }

    /**
     * @description Creates the alumnus's own education row alongside a newly provisioned
     *              ConstituentRole, so the onboarding education step has real data to
     *              display and complete instead of manufacturing a throwaway row in the
     *              browser. Degree/dates/grade are left blank for the alumnus to fill.
     *
     *              Runs AFTER the role insert on purpose: KenPersonEducationTriggerHandler
     *              skips programmes the person already holds a role for, and the role is
     *              visible to its SOQL in this same transaction — so this never raises a
     *              duplicate secondary-role Lead.
     *
     * @param result   Roles created/matched by this provisioning run.
     * @param accounts Person Accounts in scope, needed for PersonContactId.
     */
    private static void seedEducationForNewRoles(ConstituentRoleResult result, List<Account> accounts) {
        if (!seedEducationOnProvision || result == null || result.newlyCreatedRoleIds.isEmpty()) {
            return;
        }

        List<ConstituentRole> roles = [
            SELECT Id, PersonId, Program_Plan__c, Registration_Number__c,
                   Graduation_Year__c, Institution_Name__c
            FROM ConstituentRole
            WHERE Id IN :result.newlyCreatedRoleIds
            AND Program_Plan__c != null
        WITH SYSTEM_MODE
        ];
        if (roles.isEmpty()) {
            return;
        }

        Map<Id, Id> contactByAccount = new Map<Id, Id>();
        for (Account a : accounts) {
            if (a != null && a.Id != null && a.PersonContactId != null) {
                contactByAccount.put(a.Id, a.PersonContactId);
            }
        }

        Set<Id> personIds = new Set<Id>();
        for (ConstituentRole cr : roles) {
            personIds.add(cr.PersonId);
        }

        Set<String> alreadyOnFile = new Set<String>();
        for (PersonEducation pe : [
            SELECT AccountId, Program_Plan__c
            FROM PersonEducation
            WHERE AccountId IN :personIds
            AND Program_Plan__c != null
            AND (Is_Archived__c = false OR Is_Archived__c = null)
        WITH SYSTEM_MODE
        ]) {
            alreadyOnFile.add(pe.AccountId + '|' + pe.Program_Plan__c);
        }

        List<PersonEducation> toInsert = new List<PersonEducation>();
        for (ConstituentRole cr : roles) {
            String key = cr.PersonId + '|' + cr.Program_Plan__c;
            if (alreadyOnFile.contains(key)) {
                continue;
            }
            alreadyOnFile.add(key);
            toInsert.add(new PersonEducation(
                AccountId = cr.PersonId,
                ContactId = contactByAccount.get(cr.PersonId),
                Name = 'Degree',
                Institute_Name__c = cr.Institution_Name__c,
                Institution_Type__c = INST_TYPE_OWN,
                Program_Plan__c = cr.Program_Plan__c,
                Registration_Number__c = cr.Registration_Number__c,
                Year_of_Completion__c = cr.Graduation_Year__c,
                Is_Archived__c = false
            ));
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, true, AccessLevel.SYSTEM_MODE);
        }
    }
    
    private static List<Account> fetchPersonAccountsByIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        
        return [
            SELECT Id, FirstName, LastName, PersonEmail, PersonContactId,
                   PersonMobilePhone, Phone
            FROM Account
            WHERE Id IN :accountIds
        WITH SYSTEM_MODE
        ];
    }
    
    /**
     * The Alumni profile every portal user is provisioned on. Returns null when
     * the org has not had it deployed yet, so the caller skips provisioning
     * instead of throwing a QueryException mid-transaction.
     */
    /**
     * @description Timezone to stamp on new portal users, from the org parameter
     *              so a non-Indian institution is not forced onto IST.
     *
     *              This is a display preference for Salesforce's own screens
     *              only. Stored data is always UTC, and the portal's pages read
     *              the visitor's device instead of this — which is why a user
     *              who travels still sees correct times without anyone touching
     *              their record.
     *
     * @return IANA timezone id; Asia/Kolkata when unset
     */
    @TestVisible
    private static String resolveTimezone() {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        String configured = params == null ? null : params.Default_Timezone__c;
        return String.isBlank(configured) ? DEFAULT_TIMEZONE : configured.trim();
    }

    private static Profile resolveAlumniProfile() {
        List<Profile> profiles = [
            SELECT Id
            FROM Profile
            WHERE Name = :ALUMNI_PROFILE_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return profiles.isEmpty() ? null : profiles[0];
    }

    private static Map<Id, UserLoginInfo> createOrGetUsers(List<Account> accounts, Boolean issuePasswords) {
        Map<Id, UserLoginInfo> result = new Map<Id, UserLoginInfo>();
        
        Set<Id> contactIds = new Set<Id>();
        Map<Id, Id> accountByContact = new Map<Id, Id>();
        for (Account a : accounts) {
            if (a.PersonContactId != null) {
                contactIds.add(a.PersonContactId);
                accountByContact.put(a.PersonContactId, a.Id);
            }
        }
        
        Map<Id, User> userByContact = new Map<Id, User>();
        for (User u : [
            SELECT Id, ContactId, FirstName, LastName, Username
            FROM User
            WHERE ContactId IN :contactIds
        WITH SYSTEM_MODE
        ]) {
            userByContact.put(u.ContactId, u);
        }
        
        Profile p = resolveAlumniProfile();

        
        List<User> toInsert = new List<User>();
        for (Account a : accounts) {
            if (a.PersonContactId == null) {
                continue;
            }
            if (!userByContact.containsKey(a.PersonContactId)) {
                String email = a.PersonEmail.toLowerCase();
                // Stamp the alumnus's mobile onto the User at creation. Salesforce
                // can only SMS a number held on the User record, so without this
                // every new alumnus would have to type it again before they could
                // verify their phone or use SMS OTP login.
                String mobile = KenCommunityOtpLoginController.formatMobileForUser(
                    String.isNotBlank(a.PersonMobilePhone) ? a.PersonMobilePhone : a.Phone
                );
                toInsert.add(new User(
                    Username = email,
                Email = email,
                MobilePhone = mobile,
                FirstName = a.FirstName,
                LastName = String.isBlank(a.LastName) ? 'Alumni' : a.LastName,
                Alias = ((String.isNotBlank(a.FirstName) ? a.FirstName.substring(0, 1) : 'f') +
                    (String.isNotBlank(a.LastName) ? a.LastName.substring(0, 1) : 'l')).toLowerCase(),
                ProfileId = p.Id,
                ContactId = a.PersonContactId,
                TimeZoneSidKey = resolveTimezone(),
                LocaleSidKey = DEFAULT_LOCALE,
                EmailEncodingKey = DEFAULT_EMAIL_ENCODING,
                LanguageLocaleKey = DEFAULT_LANGUAGE,
                IsActive = true
                    ));
            }
        }
        
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, true, AccessLevel.SYSTEM_MODE);
            for (User u : toInsert) {
                userByContact.put(u.ContactId, u);
            }
        }
        
        Set<Id> userIds = new Set<Id>();
        for (User u : userByContact.values()) {
            userIds.add(u.Id);
        }
        assignAlumniPermission(userIds);

        if (issuePasswords) {
            List<User> targetUsers = new List<User>();
            targetUsers.addAll(toInsert);
            
            Map<Id, String> passwords = new Map<Id, String>();
            for (User u : targetUsers) {
                String pwd = generateTempPassword(TEMP_PWD_LEN);
                KenPasswordService.applyNewPassword(u.Id, pwd);
                passwords.put(u.Id, pwd);
                
                Id accountId = accountByContact.get(u.ContactId);
                if (accountId != null) {
                    result.put(accountId, new UserLoginInfo(u, pwd));
                    latestLoginInfoByAccount.put(accountId, new UserLoginInfo(u, pwd));
                }
            }

            Map<String, SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
            Boolean hasTempResetField = KenNamespaceUtil.hasField(accountFields, 'Temp_Password_Reset_Completed__c');
            if (!targetUsers.isEmpty() && hasTempResetField) {
                List<Account> accountsToUpdate = new List<Account>();
                Set<Id> seenAccountIds = new Set<Id>();
                for (User u : targetUsers) {
                    Id accountId = accountByContact.get(u.ContactId);
                    if (accountId != null && !seenAccountIds.contains(accountId)) {
                        Account a = new Account(Id = accountId);
                        a.put(KenNamespaceUtil.qualifyCustom('Temp_Password_Reset_Completed__c'), false);
                        accountsToUpdate.add(a);
                        seenAccountIds.add(accountId);
                    }
                }
                if (!accountsToUpdate.isEmpty()) {
                    Database.update(accountsToUpdate, true, AccessLevel.SYSTEM_MODE);
                }
            }
            
            sendUserPasswordEmail(targetUsers, passwords, accountByContact);
        }
        
        return result;
    }

    @future
    public static void assignAlumniPermission(Set<Id> userIds) {

        if (userIds == null || userIds.isEmpty()) {
            return;
        }

        Set<String> psNames = new Set<String>{
            ALUMNI_PERMISSION_SET_NAME,
            SUPPORT_SERVICES_PERMISSION_SET_NAME
        };
        Map<String, Id> psIdByName = new Map<String, Id>();
        for (PermissionSet ps : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN :psNames
        WITH SYSTEM_MODE
        ]) {
            psIdByName.put(ps.Name, ps.Id);
        }

        if (!psIdByName.containsKey(ALUMNI_PERMISSION_SET_NAME)) {
            return;
        }

        Set<Id> psIdsToAssign = new Set<Id>(psIdByName.values());

        Map<Id, Set<Id>> existingByUser = new Map<Id, Set<Id>>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId IN :userIds
            AND PermissionSetId IN :psIdsToAssign
        WITH SYSTEM_MODE
        ]) {
            if (!existingByUser.containsKey(psa.AssigneeId)) {
                existingByUser.put(psa.AssigneeId, new Set<Id>());
            }
            existingByUser.get(psa.AssigneeId).add(psa.PermissionSetId);
        }

        List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
        for (Id userId : userIds) {
            Set<Id> assigned = existingByUser.containsKey(userId)
                ? existingByUser.get(userId)
                : new Set<Id>();
            for (Id psId : psIdsToAssign) {
                if (!assigned.contains(psId)) {
                    toInsert.add(new PermissionSetAssignment(
                        AssigneeId = userId,
                        PermissionSetId = psId
                    ));
                }
            }
        }

        if (!toInsert.isEmpty()) {
           Database.SaveResult[] results = Database.insert(toInsert, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    System.debug('assignAlumniPermission row ' + i + ' tolerated: ' + results[i].getErrors());
                }
            }
        }
    }

    private static void sendUserPasswordEmail(List<User> users, Map<Id, String> tempPasswords, Map<Id, Id> accountByContact) {
        Ken_Alm_Bypass_Settings__c emailSettings = KenSettings.bypass();
        if (emailSettings != null && emailSettings.Skip_Temporary_Login__c) {
            return;
        }

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        
        Set<Id> accountIds = new Set<Id>();
        for (Id contactId : accountByContact.keySet()) {
            accountIds.add(accountByContact.get(contactId));
        }
        
        Map<Id, ConstituentRole> crByAccount = new Map<Id, ConstituentRole>();
        if (!accountIds.isEmpty()) {
            for (ConstituentRole cr : [
                SELECT Id, PersonId, Email__c
                FROM ConstituentRole
                WHERE PersonId IN :accountIds
                AND RoleType = :ROLETYPE_ALUMNI
            WITH SYSTEM_MODE
            ]) {
                crByAccount.put(cr.PersonId, cr);
            }
        }

        EmailTemplate et = [
            SELECT Id, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = 'Temporary_Password_1704605432867'
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
        
        for (User u : users) {
            Id accountId = u.ContactId != null ? accountByContact.get(u.ContactId) : null;
            String targetEmail = null;
            if (accountId != null && crByAccount.containsKey(accountId) && String.isNotBlank(crByAccount.get(accountId).Email__c)) {
                targetEmail = crByAccount.get(accountId).Email__c;
            } else {
                targetEmail = u.Email;
            }

            Ken_Alm_Org_Parameters__c orgParam = Ken_Alm_Org_Parameters__c.getOrgDefaults();
            String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c) ? orgParam.Institution_Alias__c : '';

            String body = et.HtmlValue;

            // One token map feeds both the Classic template merge and the Marketing Cloud
            // attributes, so a rename can never leave one path merging a stale name.
            Map<String, String> tokens = new Map<String, String>{
                'Name' => (u.FirstName == null ? '' : u.FirstName + ' ') + (u.LastName == null ? '' : u.LastName),
                'Username' => u.Username,
                'Temporary_Password' => tempPasswords.get(u.Id),
                'Institution_Alias' => institutionAlias
            };

            // Every token has to be present or the merge is skipped and the alumnus
            // receives the template's raw {Temporary_Password} text instead of a password,
            // leaving them unable to log in and with nothing to explain why. It happens
            // rarely — FirstName is optional on User — so name exactly which value was
            // missing rather than leaving the cause to be guessed from a complaint.
            List<String> missingFields = new List<String>();
            if (u.FirstName == null) { missingFields.add('FirstName'); }
            if (u.LastName == null) { missingFields.add('LastName'); }
            if (u.Username == null) { missingFields.add('Username'); }
            if (tempPasswords.get(u.Id) == null) { missingFields.add('Temporary_Password'); }

            if (missingFields.isEmpty()) {
                body = KenMessagingService.mergeTokens(body, tokens);
            } else {
                String missingList = String.join(missingFields, ', ');
                System.debug(LoggingLevel.ERROR,
                    'Temporary password email not merged for User ' + u.Id
                    + '. Missing: ' + missingList
                    + '. Fix the User record, then resend the password from the alumni record.');
            }

            KenMessagingService.Request routing =
                new KenMessagingService.Request(KenMessagingService.TYPE_TEMPORARY_LOGIN)
                    .toContact(targetEmail, u.MobilePhone)
                    .attributes(tokens);

            KenMessagingService.sendToPhoneChannels(routing);
            KenMessagingService.Result routed = KenMessagingService.send(routing);
            if (routed.handled) {
                continue;
            }

        
            List<OrgWideEmailAddress> orgIds = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = :ORG_WIDE_NAME
                WITH SYSTEM_MODE
                LIMIT 1
            ];          
            
            String finalBody ='<html><body>' + letterheadHeader + body 
            // + letterheadFooter 
            + '</body></html>';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ targetEmail });
            mail.setOrgWideEmailAddressId(!orgIds.isEmpty() ? orgIds[0].Id : null);
            mail.setHtmlBody(finalBody);
            mail.setSaveAsActivity(true);
            
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        }
        
        if (!mails.isEmpty()) {
            Messaging.sendEmail(mails);
        }
    }
    
    /**
     * @description Processes alumni onboarding based on ConstituentRole updates
     *              by provisioning community users for the given person accounts.
     *
     * @param personAccountIds Set of Person Account Ids to be processed.
     * @return Map of Person Account Id to UserLoginInfo containing
     *         generated user and temporary login credentials.
     */
    /**
     * @description Processes alumni onboarding when ConstituentRole status transitions
     *              to 'Verified'. Creates a community user per account and ensures a
     *              Ken_Alumni_CRM__c record exists that is linked to the ConstituentRole.
     *
     * @param accountToConstituentRoleMap  Map of PersonAccount Id → ConstituentRole Id.
     * @return Map of Person Account Id to UserLoginInfo.
     */
    public static Map<Id, UserLoginInfo> processByConstituentRole(Map<Id, Id> accountToConstituentRoleMap) {
        if (accountToConstituentRoleMap == null || accountToConstituentRoleMap.isEmpty()) {
            return new Map<Id, UserLoginInfo>();
        }

        Set<Id> personAccountIds = new Set<Id>(accountToConstituentRoleMap.keySet());

        // Prevent duplicate processing (e.g., trigger + controller in same transaction)
        personAccountIds.removeAll(processedAccountIdsThisTxn);
        if (personAccountIds.isEmpty()) {
            return latestLoginInfoByAccount;
        }

        List<Account> accounts = [
            SELECT Id, FirstName, LastName, PersonEmail, PersonContactId,
                   PersonMobilePhone, Phone
            FROM Account
            WHERE Id IN :personAccountIds
            AND IsPersonAccount = true
        WITH SYSTEM_MODE
        ];

        if (accounts.isEmpty()) {
            return new Map<Id, UserLoginInfo>();
        }

        Map<Id, UserLoginInfo> info = createOrGetUsers(accounts, true);
        processedAccountIdsThisTxn.addAll(personAccountIds);
        return info;
    }
    /**
     * @description Retrieves the most recent temporary login information
     *              associated with the given person account.
     *
     * @param accountId Id of the person account.
     * @return UserLoginInfo containing user and temporary password, or null.
     */
    public static UserLoginInfo getLatestLoginInfo(Id accountId) {
        return accountId != null ? latestLoginInfoByAccount.get(accountId) : null;
    }

    /**
     * @description Lightweight DTO exposed to Aura/LWC for alumni role selection.
     */
    public class AlumniRoleInfo {
        @AuraEnabled public Id constituentRoleId;
        @AuraEnabled public String programPlanName;
        @AuraEnabled public String batch;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String registrationStatus;
    }

    /**
     * @description Returns alumni ConstituentRole records for the given person
     *              account along with display metadata used by the portal.
     *              Always returns the available roles so the client can decide
     *              whether to show the selection screen or auto-select.
     *
     * @param personId Person Account Id to query against.
     * @return List of AlumniRoleInfo records (can be size 0/1/+).
     */
    @AuraEnabled(cacheable=true)
    public static List<AlumniRoleInfo> getAlumniRolesForPerson(Id personId) {
        if (personId == null) {
            User currentUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
            personId = currentUser.AccountId;
        }

        List<ConstituentRole> roles = [
            SELECT Id,
                   Registration_Status__c,
                   Registration_Number__c,
                   Graduation_Year__c,
                   Program_Plan__r.Name,
                   Program_Plan__r.LearningProgram.Name
            FROM ConstituentRole
            WHERE PersonId = :personId
            AND RoleType = :ROLETYPE_ALUMNI
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];

        if (roles.isEmpty()) {
            return new List<AlumniRoleInfo>();
        }

        List<AlumniRoleInfo> response = new List<AlumniRoleInfo>();
        for (ConstituentRole cr : roles) {
            AlumniRoleInfo info = new AlumniRoleInfo();
            info.constituentRoleId = cr.Id;
            info.batch = cr.Graduation_Year__c != null ? String.valueOf(cr.Graduation_Year__c) : null;
            info.programPlanName = cr.Program_Plan__r != null ?
                (cr.Program_Plan__r.LearningProgram != null ? cr.Program_Plan__r.LearningProgram.Name : cr.Program_Plan__r.Name)
                : null;
            info.registrationNumber = cr.Registration_Number__c;
            info.registrationStatus = cr.Registration_Status__c;
            response.add(info);
        }

        return response;
    }
    
    /**
     * The org's password policy requires a mix of letters and numbers. Drawing every
     * character from one combined pool left roughly 2% of passwords all-letters
     * ((26/36)^12), which System.setPassword rejects with INVALID_NEW_PASSWORD - and
     * because this runs inside the ConstituentRole after-update trigger, that rolled
     * the whole onboarding back. So force one of each, then shuffle.
     */
    @TestVisible
    private static String generateTempPassword(Integer length) {
        final String DIGITS = '0123456789';
        final String LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        Integer target = Math.max(length, 2);

        List<String> chars = new List<String>{ randomChar(DIGITS), randomChar(LETTERS) };
        while (chars.size() < target) {
            chars.add(randomChar(DIGITS + LETTERS));
        }

        // Fisher-Yates, so the guaranteed digit and letter aren't always first.
        for (Integer i = chars.size() - 1; i > 0; i--) {
            Integer j = randomIndex(i + 1);
            String swap = chars[i];
            chars[i] = chars[j];
            chars[j] = swap;
        }
        return String.join(chars, '');
    }

    private static String randomChar(String pool) {
        Integer idx = randomIndex(pool.length());
        return pool.substring(idx, idx + 1);
    }

    /**
     * Crypto.getRandomInteger() can return Integer.MIN_VALUE, whose abs() overflows
     * back to itself, so normalise the sign after the modulo rather than before it.
     */
    private static Integer randomIndex(Integer bound) {
        Integer idx = Math.mod(Crypto.getRandomInteger(), bound);
        return idx < 0 ? idx + bound : idx;
    }

    @TestVisible
    private static String safeLeadString(Lead lead, String fieldApiName) {
        if (lead == null || String.isBlank(fieldApiName)) {
            return null;
        }
        try {
            Object value = lead.get(fieldApiName);
            return value == null ? null : String.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Whether the role has already moved past the pre-onboarding
     *              statuses, which is how a spent magic link is recognised.
     *
     *              A blank or unrecognised status ranks below Unregistered and is
     *              treated as unused, so an org with a picklist value this class
     *              does not know about never locks an alumnus out of onboarding.
     *
     * @param registrationStatus ConstituentRole.Registration_Status__c to judge.
     * @return                   True when the link has already been used.
     */
    @TestVisible
    private static Boolean isLinkAlreadyUsed(String registrationStatus) {
        Integer rank = (registrationStatus != null && REG_STATUS_RANK.containsKey(registrationStatus))
            ? REG_STATUS_RANK.get(registrationStatus)
            : -1;
        return rank > REG_STATUS_RANK.get(CR_STATUS_UNREGISTERED);
    }

    // Returns the further-progressed of two registration statuses; a blank or
    // unknown status ranks below every known one.
    @TestVisible
    private static String higherStatus(String a, String b) {
        Integer ra = (a != null && REG_STATUS_RANK.containsKey(a)) ? REG_STATUS_RANK.get(a) : -1;
        Integer rb = (b != null && REG_STATUS_RANK.containsKey(b)) ? REG_STATUS_RANK.get(b) : -1;
        return ra >= rb ? a : b;
    }

    @TestVisible
    private static String buildRoleCompositeKey(Id accountId, String programPlanId, String registrationNumber) {
        String matcher = String.isNotBlank(programPlanId)
            ? programPlanId.trim().toLowerCase()
            : (String.isNotBlank(registrationNumber) ? registrationNumber.trim().toLowerCase() : 'default');
        return String.valueOf(accountId) + '|' + matcher;
    }

    @TestVisible
    private static ConstituentRole findRoleForLead(Id accountId, Lead lead) {
        if (accountId == null || lead == null) {
            return null;
        }

        List<ConstituentRole> roles = [
            SELECT Id, PersonId, Program_Plan__c, Registration_Number__c, Registration_Status__c
            FROM ConstituentRole
            WHERE PersonId = :accountId
            AND RoleType = :ROLETYPE_ALUMNI
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        if (roles.isEmpty()) {
            return null;
        }

        if (lead.Program_Plan__c != null) {
            for (ConstituentRole cr : roles) {
                if (cr.Program_Plan__c == lead.Program_Plan__c) {
                    return cr;
                }
            }
        }

        if (String.isNotBlank(lead.Registration_Number__c)) {
            for (ConstituentRole cr : roles) {
                if (cr.Registration_Number__c == lead.Registration_Number__c) {
                    return cr;
                }
            }
        }

        return roles[0];
    }

    /**
     * Derives ConstituentRole.Source_Funnel__c from the originating Lead.
     * The registration form sets Lead.LeadSource='Web'; campaign / referral
     * sources should arrive as 'Referral' / 'Partner Referral' / 'Other Campaign'
     * etc. via signup parameters. Defaults to 'Self-Declared Lead' so the
     * source/funnel taxonomy is never null for newly-provisioned alumni.
     */
    @TestVisible
    private static String deriveSourceFunnel(Lead lead) {
        if (lead == null) return 'Self-Declared Lead';
        // LeadSource may not have been queried by the upstream caller — guard with try/catch.
        String src = null;
        try {
            src = (String) lead.get('LeadSource');
        } catch (Exception ignored) {
            src = null;
        }
        if (String.isBlank(src)) return 'Self-Declared Lead';
        String norm = src.toLowerCase();
        if (norm.contains('referral')) return 'Alumni Referral';
        if (norm.contains('campaign')) return 'Campaign Lead';
        // Bulk import passes its Data Source as LeadSource (leads are in-memory only)
        if (norm.contains('portal')) return 'Old Portal Migration';
        if (norm.contains('historic') || norm.contains('import') || norm.contains('upload')) return 'Historical Upload';
        // 'Web', 'Phone Inquiry', 'Other', etc. all bucket to Self-Declared
        return 'Self-Declared Lead';
    }

    @TestVisible
    private static void linkLeadsToConstituentRoles(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        if (!KenNamespaceUtil.hasField(ConstituentRole.SObjectType.getDescribe().fields.getMap(), 'Lead__c')) {
            return;
        }

        Set<String> emails = new Set<String>();
        for (Lead l : leads) {
            String leadEmail = safeLeadString(l, 'Email');
            if (String.isNotBlank(leadEmail)) {
                emails.add(leadEmail.trim().toLowerCase());
            }
        }
        if (emails.isEmpty()) {
            return;
        }

        Map<String, Id> accountIdByEmail = new Map<String, Id>();
        for (Account pa : [
            SELECT Id, PersonEmail
            FROM Account
            WHERE IsPersonAccount = true
            AND PersonEmail IN :emails
        WITH SYSTEM_MODE
        ]) {
            if (String.isNotBlank(pa.PersonEmail)) {
                accountIdByEmail.put(pa.PersonEmail.trim().toLowerCase(), pa.Id);
            }
        }
        if (accountIdByEmail.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        accountIds.addAll(accountIdByEmail.values());

        Map<Id, List<ConstituentRole>> rolesByAccount = new Map<Id, List<ConstituentRole>>();
        for (ConstituentRole cr : [
            SELECT Id, PersonId, Program_Plan__c, Registration_Number__c, Lead__c
            FROM ConstituentRole
            WHERE PersonId IN :accountIds
            AND RoleType = :ROLETYPE_ALUMNI
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {
            if (!rolesByAccount.containsKey(cr.PersonId)) {
                rolesByAccount.put(cr.PersonId, new List<ConstituentRole>());
            }
            rolesByAccount.get(cr.PersonId).add(cr);
        }

        List<ConstituentRole> toUpdate = new List<ConstituentRole>();
        for (Lead l : leads) {
            String leadEmail = safeLeadString(l, 'Email');
            if (l == null || l.Id == null || String.isBlank(leadEmail)) {
                continue;
            }
            Id accountId = accountIdByEmail.get(leadEmail.trim().toLowerCase());
            if (accountId == null || !rolesByAccount.containsKey(accountId)) {
                continue;
            }
            ConstituentRole matched = matchRoleForLead(rolesByAccount.get(accountId), l);
            if (matched == null || matched.Lead__c == l.Id) {
                continue;
            }
            toUpdate.add(new ConstituentRole(
                Id = matched.Id,
                Lead__c = l.Id
            ));
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true, AccessLevel.SYSTEM_MODE);
        }
    }

    @TestVisible
    private static ConstituentRole matchRoleForLead(List<ConstituentRole> roles, Lead lead) {
        if (roles == null || roles.isEmpty() || lead == null) {
            return null;
        }

        String leadProgramPlan = safeLeadString(lead, 'Program_Plan__c');
        String leadRegistrationNumber = safeLeadString(lead, 'Registration_Number__c');

        if (leadProgramPlan != null) {
            for (ConstituentRole cr : roles) {
                if (cr.Program_Plan__c == leadProgramPlan) {
                    return cr;
                }
            }
        }

        if (String.isNotBlank(leadRegistrationNumber)) {
            for (ConstituentRole cr : roles) {
                if (cr.Registration_Number__c == leadRegistrationNumber) {
                    return cr;
                }
            }
        }

        return roles[0];
    }

    @TestVisible
    private static void sendExistingUserNewRoleEmail(List<Account> accounts, ConstituentRoleResult roleResult) {
        if (accounts == null || accounts.isEmpty() || roleResult == null || roleResult.newlyCreatedRoleIds.isEmpty()) {
            return;
        }

        Set<Id> accountIds = new Set<Id>();
        Map<Id, Account> accountById = new Map<Id, Account>();
        for (Account a : accounts) {
            if (a != null && a.Id != null) {
                accountIds.add(a.Id);
                accountById.put(a.Id, a);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }

        Set<Id> accountsWithActiveUser = new Set<Id>();
        for (User u : [
            SELECT Id, AccountId
            FROM User
            WHERE AccountId IN :accountIds
            AND IsActive = true
        WITH SYSTEM_MODE
        ]) {
            if (u.AccountId != null) {
                accountsWithActiveUser.add(u.AccountId);
            }
        }
        if (accountsWithActiveUser.isEmpty()) {
            return;
        }

        Ken_Alm_Org_Parameters__c orgParam = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        String portalUrl = orgParam != null ? orgParam.Portal_URL__c : null;
        String loginUrl = String.isNotBlank(portalUrl)
            ? (portalUrl.endsWith('/') ? portalUrl + 'login' : portalUrl + '/login')
            : '/alumni/login';

        List<OrgWideEmailAddress> orgIds = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :ORG_WIDE_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c)
            ? orgParam.Institution_Alias__c
            : 'Alumni';
        String primaryColor = orgParam != null && String.isNotBlank(orgParam.Portal_Primary_colour__c)
            ? orgParam.Portal_Primary_colour__c
            : '#1f3b8f';

        String letterheadHeader = '';
        try {
            EnhancedLetterhead lh = [
                SELECT LetterheadHeader
                FROM EnhancedLetterhead
                WHERE Name = 'Alumni Letterhead'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            letterheadHeader = lh.LetterheadHeader != null ? lh.LetterheadHeader : '';
        } catch (Exception e) {
            letterheadHeader = '';
        }

        List<EmailTemplate> tpls = [
            SELECT Id, Subject, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = 'Alumni_New_Role_Added' AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        EmailTemplate tpl = tpls.isEmpty() ? null : tpls[0];

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        KenMessagingService.Request roleRouting =
            new KenMessagingService.Request(KenMessagingService.TYPE_NEW_ROLE_ADDED)
                .attribute('Login_Url', loginUrl)
                .attribute('Institution_Alias', institutionAlias);

        for (ConstituentRole cr : [
            SELECT Id, PersonId, Program_Plan__r.Name, Registration_Number__c
            FROM ConstituentRole
            WHERE Id IN :roleResult.newlyCreatedRoleIds
        WITH SYSTEM_MODE
        ]) {
            if (!accountsWithActiveUser.contains(cr.PersonId)) {
                continue;
            }
            Account pa = accountById.get(cr.PersonId);
            if (pa == null || String.isBlank(pa.PersonEmail)) {
                continue;
            }

            String programName = cr.Program_Plan__r != null ? cr.Program_Plan__r.Name : 'your new program';
            String regNo = String.isNotBlank(cr.Registration_Number__c) ? cr.Registration_Number__c : 'N/A';
            String recipientName = (String) pa.getPopulatedFieldsAsMap().get('FirstName');
            if (String.isBlank(recipientName)) {
                recipientName = (String) pa.getPopulatedFieldsAsMap().get('Name');
            }
            if (String.isBlank(recipientName)) {
                recipientName = 'there';
            }

            Map<String, String> tokens = new Map<String, String>{
                'Recipient_Name' => recipientName,
                'Program_Name' => programName,
                'Registration_Number' => regNo,
                'Login_Url' => loginUrl,
                'Primary_Color' => primaryColor,
                'Institution_Alias' => institutionAlias
            };

            roleRouting.recipient(
                pa.PersonEmail,
                String.isNotBlank(pa.PersonMobilePhone) ? pa.PersonMobilePhone : pa.Phone,
                tokens
            );

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ pa.PersonEmail });

            if (tpl != null) {
                String body = KenMessagingService.mergeTokens(tpl.HtmlValue, tokens);
                String finalBody = '<html><body>' + letterheadHeader + body + '</body></html>';
                msg.setSubject(String.isNotBlank(tpl.Subject) ? tpl.Subject : 'A new alumni role has been added to your profile');
                msg.setHtmlBody(finalBody);
            } else {
                msg.setSubject('New Program Registration Added');
                msg.setPlainTextBody(
                    'A new alumni role has been added to your account for ' + programName +
                    ' (Registration No: ' + regNo + '). ' +
                    'Please log in: ' + loginUrl
                );
            }
            msg.setOrgWideEmailAddressId(!orgIds.isEmpty() ? orgIds[0].Id : null);
            msg.setSaveAsActivity(false);
            mails.add(msg);
        }

        KenMessagingService.sendToPhoneChannels(roleRouting);
        if (KenMessagingService.send(roleRouting).handled) {
            return;
        }

        if (!mails.isEmpty()) {
            Messaging.sendEmail(mails);
        }
    }
}