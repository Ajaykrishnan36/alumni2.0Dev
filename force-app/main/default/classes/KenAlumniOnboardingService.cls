/**
 * @description Service class responsible for alumni onboarding workflows,
 *              including lead verification, person account creation,
 *              constituent role management, and post-registration updates.
 *
 * @author
 * @since
 */


public without sharing class KenAlumniOnboardingService {
    
    private static final String PERSON_ACCOUNT_RT_DEVNAME = 'Alumni_Person_Account';
    private static final String ALUMNI_PROFILE_NAME = 'Alumni-Student';
    private static final String DEFAULT_TIMEZONE = 'Asia/Kolkata';
    private static final String DEFAULT_LOCALE = 'en_US';
    private static final String DEFAULT_LANGUAGE = 'en_US';
    private static final String DEFAULT_EMAIL_ENCODING = 'UTF-8';
    private static final String ROLETYPE_ALUMNI = 'Alumni';
    private static final String CR_STATUS_ACTIVE = 'Active';
    private static final String CR_STATUS_UNREGISTERED = 'Unregistered';
    private static final String CR_STATUS_REGISTERED = 'Registered';
    private static final String CR_STATUS_INITIAL_LOGIN_DONE = 'Initial Login Done';
    private static final Integer TEMP_PWD_LEN = 12;
    private static final String ALUMNI_PERMISSION_SET_NAME = 'Alumni';
    private static final String SUPPORT_SERVICES_PERMISSION_SET_NAME = 'Support_And_Services_User_Access';
    @TestVisible private static final String ORG_WIDE_NAME = 'Alumni Management';
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
            
            createOrGetAlumniCrm(new List<Account>{ pa });
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

            if (selectedRole.Registration_Status__c == CR_STATUS_REGISTERED ||
                selectedRole.Registration_Status__c == CR_STATUS_INITIAL_LOGIN_DONE) {
                throw new AuraHandledException('ALREADY_REGISTERED');
            }
            
            return '/alumni/onboarding-form?accountId=' + pa.Id + '&roleId=' + selectedRole.Id + '&token=' + token;
            
        } catch (AuraHandledException e) {
            throw e;
        }
    }
    
    private static Lead fetchLeadByToken(String token) {
        List<Lead> leads = [
            SELECT Id, Email, FirstName, LastName, Phone, Year_of_Graduation__c, Registration_Number__c,
                   Program_Plan__c, Referred_By__c,
                   Verification_Token__c, Token_Expiration_Date__c
            FROM Lead
            WHERE Verification_Token__c = :token
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
            update toUpdate;
        }
    }
    
    private static Account fetchPersonAccountById(Id accountId) {
        return [
            SELECT Id, FirstName, LastName, PersonEmail, PersonContactId
            FROM Account
            WHERE Id = :accountId
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
        
        createOrGetAlumniCrm(accounts);
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
        ]) {
            if (cr.Registration_Status__c != CR_STATUS_REGISTERED) {
                toUpdate.add(new ConstituentRole(
                    Id = cr.Id,
                Registration_Status__c = CR_STATUS_REGISTERED
                    ));
            }
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
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
        if (!Schema.sObjectType.Lead.isUpdateable()) {
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
            update toUpdate;
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
        ]) {
            result.put(a.PersonEmail.toLowerCase(), a);
        }

        Set<Id> explicitAccountIds = new Set<Id>();
        for (Lead l : leads) {
            if (l == null) {
                continue;
            }
            Object existingAcct = l.getPopulatedFieldsAsMap().get('Existing_Account__c');
            if (existingAcct != null) {
                explicitAccountIds.add((Id) existingAcct);
            }
        }
        if (!explicitAccountIds.isEmpty()) {
            for (Account a : [
                SELECT Id, PersonEmail, Phone
                FROM Account
                WHERE Id IN :explicitAccountIds AND IsPersonAccount = true
            ]) {
                if (String.isNotBlank(a.PersonEmail)) {
                    result.put(a.PersonEmail.toLowerCase(), a);
                }
            }
        }

        List<Account> toUpdate = new List<Account>();
        
        if (!Schema.sObjectType.Account.isCreateable()) {
            return result;
        }
        
        Id rtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(PERSON_ACCOUNT_RT_DEVNAME).getRecordTypeId();
        
        List<Account> toInsert = new List<Account>();
        
        for (Lead l : leads) {
            String emailKey = l.Email.toLowerCase();
            if (!result.containsKey(emailKey)) {
                if (Schema.sObjectType.Account.isCreateable()) {
                    toInsert.add(new Account(
                        RecordTypeId = rtId,
                    FirstName = l.FirstName,
                    LastName = String.isBlank(l.LastName) ? 'Alumni' : l.LastName,
                    PersonEmail = l.Email,
                    Phone = l.Phone
                        ));
                }
            } else {
                Account existing = result.get(emailKey);
                if (String.isNotBlank(l.Phone) && existing.Phone != l.Phone &&  Schema.sObjectType.Account.isUpdateable()){
                    toUpdate.add(new Account(
                        Id = existing.Id,
                    Phone = l.Phone
                        ));
                }
            }
        }
        
        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (Account a : toInsert) {
                result.put(a.PersonEmail.toLowerCase(), a);
            }
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        
        return result;
    }
    
    private static Map<Id, Ken_Alumni_CRM__c> createOrGetAlumniCrm(List<Account> accounts) {
        Map<Id, Ken_Alumni_CRM__c> result = new Map<Id, Ken_Alumni_CRM__c>();

        Set<Id> accountIds = new Set<Id>();
        for (Account a : accounts) {
            accountIds.add(a.Id);
        }

        for (Ken_Alumni_CRM__c crm : [
            SELECT Id, Person_Account__c
            FROM Ken_Alumni_CRM__c
            WHERE Person_Account__c IN :accountIds
        ]) {
            result.put(crm.Person_Account__c, crm);
        }

        if (!Schema.sObjectType.Ken_Alumni_CRM__c.isCreateable()) {
            return result;
        }

        List<Ken_Alumni_CRM__c> toInsert = new List<Ken_Alumni_CRM__c>();
        for (Id accountId : accountIds) {
            if (!result.containsKey(accountId)) {
                toInsert.add(new Ken_Alumni_CRM__c(
                    Person_Account__c = accountId
                    ));
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (Ken_Alumni_CRM__c crm : toInsert) {
                result.put(crm.Person_Account__c, crm);
            }
        }

        return result;
    }

    /**
     * @description Ensures exactly one Ken_Alumni_CRM__c record exists per
     *              ConstituentRole. If a record already exists for the role, skips it.
     *              If only an un-linked account-level record exists, links it to the role.
     *              Otherwise creates a new record per role.
     *
     * @param accounts                 Accounts being onboarded.
     * @param accountToConstituentRoleMap  Map of Account Id → ConstituentRole Id.
     */
    private static void createOrGetAlumniCrmByRole(List<Account> accounts, Map<Id, Id> accountToConstituentRoleMap) {
        if (!Schema.sObjectType.Ken_Alumni_CRM__c.isAccessible()) {
            return;
        }

        Set<Id> accountIds   = new Set<Id>();
        Set<Id> constituentRoleIds = new Set<Id>(accountToConstituentRoleMap.values());
        for (Account a : accounts) {
            accountIds.add(a.Id);
        }

        List<Ken_Alumni_CRM__c> existing = [
            SELECT Id, Person_Account__c, ConstituentRole__c
            FROM Ken_Alumni_CRM__c
            WHERE Person_Account__c IN :accountIds
        ];

        // Track which ConstituentRole IDs already have a CRM record
        Set<Id> rolesWithCrm         = new Set<Id>();
        // Track account-level CRM records not yet linked to any role
        Map<Id, Ken_Alumni_CRM__c> unlinkedByAccount = new Map<Id, Ken_Alumni_CRM__c>();

        for (Ken_Alumni_CRM__c crm : existing) {
            if (crm.ConstituentRole__c != null) {
                rolesWithCrm.add(crm.ConstituentRole__c);
            } else {
                // Keep only one unlinked record per account (most recently found)
                unlinkedByAccount.put(crm.Person_Account__c, crm);
            }
        }

        List<Ken_Alumni_CRM__c> toUpdate = new List<Ken_Alumni_CRM__c>();
        List<Ken_Alumni_CRM__c> toInsert = new List<Ken_Alumni_CRM__c>();

        for (Account acc : accounts) {
            Id roleId = accountToConstituentRoleMap.get(acc.Id);
            if (roleId == null || rolesWithCrm.contains(roleId)) {
                continue; // already linked — nothing to do
            }

            Ken_Alumni_CRM__c unlinked = unlinkedByAccount.get(acc.Id);
            if (unlinked != null) {
                // Promote the existing un-linked record to this role
                unlinked.ConstituentRole__c = roleId;
                toUpdate.add(unlinked);
                unlinkedByAccount.remove(acc.Id); // don't reuse for another role
            } else {
                // No existing record — create one for this role
                toInsert.add(new Ken_Alumni_CRM__c(
                    Person_Account__c = acc.Id,
                    ConstituentRole__c = roleId
                ));
            }
        }

        if (!toUpdate.isEmpty() && Schema.sObjectType.Ken_Alumni_CRM__c.isUpdateable()) {
            update toUpdate;
        }
        if (!toInsert.isEmpty() && Schema.sObjectType.Ken_Alumni_CRM__c.isCreateable()) {
            insert toInsert;
        }
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
        ]) {
            existing.add(pref.Person_Account__c);
        }

        List<Ken_Alumni_Preferences__c> toInsert = new List<Ken_Alumni_Preferences__c>();
        for (Id accountId : accountIds) {
            if (!existing.contains(accountId)) {
                toInsert.add(new Ken_Alumni_Preferences__c(
                    Person_Account__c                           = accountId,
                    Is_Private_Account__c                       = false,
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
            insert toInsert;
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
            SELECT Id, PersonId, Graduation_Year__c, Program_Plan__c, Registration_Number__c, Registration_Status__c, Email__c, Lead__c, Referred_By__c
            FROM ConstituentRole
            WHERE PersonId IN :accountIds
            AND RoleType = :ROLETYPE_ALUMNI
        ]) {
            String key = buildRoleCompositeKey(cr.PersonId, cr.Program_Plan__c, cr.Registration_Number__c);
            result.rolesByCompositeKey.put(key, cr);
            String existingStatus = accountToExistingStatus.get(cr.PersonId);
            if ((existingStatus == null || existingStatus == CR_STATUS_UNREGISTERED)
                && String.isNotBlank(cr.Registration_Status__c)) {
                accountToExistingStatus.put(cr.PersonId, cr.Registration_Status__c);
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

            Boolean isSecondaryLead =
                'Secondary'.equals((String) lead.getPopulatedFieldsAsMap().get('Constituent_Role_Type__c'))
                || lead.getPopulatedFieldsAsMap().get('Existing_Account__c') != null;

            String roleKey = buildRoleCompositeKey(a.Id, leadProgramPlan, leadRegistrationNumber);
            if (isSecondaryLead || !result.rolesByCompositeKey.containsKey(roleKey)) {
                if (Schema.sObjectType.ConstituentRole.isCreateable()) {
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
                        Referred_By__c = (Id) lead.getPopulatedFieldsAsMap().get('Referred_By__c')
                    ));
                }
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
                if (String.isNotBlank(a.PersonEmail) && existing.Email__c != a.PersonEmail) {
                    upd.Email__c = a.PersonEmail;
                    needsUpdate = true;
                }
                if (existing.Lead__c != lead.Id) {
                    upd.Lead__c = lead.Id;
                    needsUpdate = true;
                }
                if (existing.Referred_By__c == null && lead.Referred_By__c != null) {
                    upd.Referred_By__c = lead.Referred_By__c;
                    needsUpdate = true;
                }
                if (needsUpdate) {
                    toUpdate.add(upd);
                }
            }
        }
        
        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (ConstituentRole cr : toInsert) {
                String key = buildRoleCompositeKey(cr.PersonId, cr.Program_Plan__c, cr.Registration_Number__c);
                result.rolesByCompositeKey.put(key, cr);
                result.newlyCreatedRoleIds.add(cr.Id);
            }
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
            for (ConstituentRole cr : [
                SELECT Id, PersonId, Graduation_Year__c, Program_Plan__c, Registration_Number__c, Registration_Status__c, Email__c, Lead__c
                FROM ConstituentRole
                WHERE Id IN :new Map<Id, ConstituentRole>(toUpdate).keySet()
            ]) {
                String key = buildRoleCompositeKey(cr.PersonId, cr.Program_Plan__c, cr.Registration_Number__c);
                result.rolesByCompositeKey.put(key, cr);
            }
        }
        
        return result;
    }
    
    private static List<Account> fetchPersonAccountsByIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        
        return [
            SELECT Id, FirstName, LastName, PersonEmail, PersonContactId
            FROM Account
            WHERE Id IN :accountIds
        ];
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
        ]) {
            userByContact.put(u.ContactId, u);
        }
        
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = :ALUMNI_PROFILE_NAME
            LIMIT 1
        ];
        
        if (!Schema.sObjectType.User.isCreateable()) {
            return result;
        }
        
        List<User> toInsert = new List<User>();
        for (Account a : accounts) {
            if (a.PersonContactId == null) {
                continue;
            }
            if (!userByContact.containsKey(a.PersonContactId)) {
                String email = a.PersonEmail.toLowerCase();
                toInsert.add(new User(
                    Username = email,
                Email = email,
                FirstName = a.FirstName,
                LastName = String.isBlank(a.LastName) ? 'Alumni' : a.LastName,
                Alias = ((String.isNotBlank(a.FirstName) ? a.FirstName.substring(0, 1) : 'f') +
                    (String.isNotBlank(a.LastName) ? a.LastName.substring(0, 1) : 'l')).toLowerCase(),
                ProfileId = p.Id,
                ContactId = a.PersonContactId,
                TimeZoneSidKey = DEFAULT_TIMEZONE,
                LocaleSidKey = DEFAULT_LOCALE,
                EmailEncodingKey = DEFAULT_EMAIL_ENCODING,
                LanguageLocaleKey = DEFAULT_LANGUAGE,
                IsActive = true
                    ));
            }
        }
        
        if (!toInsert.isEmpty()) {
            insert toInsert;
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
                System.setPassword(u.Id, pwd);
                passwords.put(u.Id, pwd);
                
                Id accountId = accountByContact.get(u.ContactId);
                if (accountId != null) {
                    result.put(accountId, new UserLoginInfo(u, pwd));
                    latestLoginInfoByAccount.put(accountId, new UserLoginInfo(u, pwd));
                }
            }

            Map<String, SObjectField> accountFields = Account.SObjectType.getDescribe().fields.getMap();
            Boolean hasTempResetField = accountFields.containsKey('Temp_Password_Reset_Completed__c');
            if (!targetUsers.isEmpty() && hasTempResetField && Schema.sObjectType.Account.isUpdateable()) {
                List<Account> accountsToUpdate = new List<Account>();
                Set<Id> seenAccountIds = new Set<Id>();
                for (User u : targetUsers) {
                    Id accountId = accountByContact.get(u.ContactId);
                    if (accountId != null && !seenAccountIds.contains(accountId)) {
                        Account a = new Account(Id = accountId);
                        a.put('Temp_Password_Reset_Completed__c', false);
                        accountsToUpdate.add(a);
                        seenAccountIds.add(accountId);
                    }
                }
                if (!accountsToUpdate.isEmpty()) {
                    update accountsToUpdate;
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
        Alumni_Email_Settings__c emailSettings = Alumni_Email_Settings__c.getOrgDefaults();
        if (emailSettings != null && emailSettings.Bypass_Temporary_Password__c) {
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
            ]) {
                crByAccount.put(cr.PersonId, cr);
            }
        }

        EmailTemplate et = [
            SELECT Id, HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = 'Temporary_Password_1704605432867'
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
        
        for (User u : users) {
            Id accountId = u.ContactId != null ? accountByContact.get(u.ContactId) : null;
            String targetEmail = null;
            if (accountId != null && crByAccount.containsKey(accountId) && String.isNotBlank(crByAccount.get(accountId).Email__c)) {
                targetEmail = crByAccount.get(accountId).Email__c;
            } else {
                targetEmail = u.Email;
            }

            Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
            String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c) ? orgParam.Institution_Alias__c : '';

            String body = et.HtmlValue;
            
            if ( u.FirstName != null && u.LastName != null && tempPasswords.get(u.Id) != null && u.Username!= null) {
                body = body.replace('{Name}', u.FirstName + ' ' + u.LastName);
                body = body.replace('{Username}', u.Username);
                body = body.replace('{Temprorary_Password}', tempPasswords.get(u.Id));
                body = body.replace('{Institution_Alias}', institutionAlias);
            }

        
            List<OrgWideEmailAddress> orgIds = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = :ORG_WIDE_NAME
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
            SELECT Id, FirstName, LastName, PersonEmail, PersonContactId
            FROM Account
            WHERE Id IN :personAccountIds
            AND IsPersonAccount = true
        ];

        if (accounts.isEmpty()) {
            return new Map<Id, UserLoginInfo>();
        }

        // Ensure a Ken_Alumni_CRM__c exists that is linked to this ConstituentRole
        createOrGetAlumniCrmByRole(accounts, accountToConstituentRoleMap);

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
            User currentUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
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
    
    private static String generateTempPassword(Integer length) {
        String chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        String pwd = '';
        for (Integer i = 0; i < length; i++) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length()); pwd += chars.substring(idx, idx + 1);
        }
        return pwd;
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
        // 'Web', 'Phone Inquiry', 'Other', etc. all bucket to Self-Declared
        return 'Self-Declared Lead';
    }

    @TestVisible
    private static void linkLeadsToConstituentRoles(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        if (!ConstituentRole.SObjectType.getDescribe().fields.getMap().containsKey('Lead__c')) {
            return;
        }
        if (!Schema.sObjectType.ConstituentRole.isUpdateable()) {
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
            update toUpdate;
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
        ]) {
            if (u.AccountId != null) {
                accountsWithActiveUser.add(u.AccountId);
            }
        }
        if (accountsWithActiveUser.isEmpty()) {
            return;
        }

        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        String portalUrl = orgParam != null ? orgParam.Portal_URL__c : null;
        String loginUrl = String.isNotBlank(portalUrl)
            ? (portalUrl.endsWith('/') ? portalUrl + 'login' : portalUrl + '/login')
            : '/alumni/login';

        List<OrgWideEmailAddress> orgIds = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :ORG_WIDE_NAME
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
            LIMIT 1
        ];
        EmailTemplate tpl = tpls.isEmpty() ? null : tpls[0];

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        for (ConstituentRole cr : [
            SELECT Id, PersonId, Program_Plan__r.Name, Registration_Number__c
            FROM ConstituentRole
            WHERE Id IN :roleResult.newlyCreatedRoleIds
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

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ pa.PersonEmail });

            if (tpl != null) {
                String body = tpl.HtmlValue;
                body = body.replace('{Recipient_Name}', recipientName)
                           .replace('{Program_Name}', programName)
                           .replace('{Registration_Number}', regNo)
                           .replace('{Login_Url}', loginUrl)
                           .replace('{Primary_Color}', primaryColor)
                           .replace('{Institution_Alias}', institutionAlias);
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

        if (!mails.isEmpty()) {
            Messaging.sendEmail(mails);
        }
    }
}