/**
 * KenAdminAlumniController
 *
 * Backend for the kenAdminAlumni LWC.
 *
 * Source of truth: ConstituentRole (RoleType='Alumni') + Lead (linked via
 * ConstituentRole.Lead__c). Person Account fields are resolved via
 * ConstituentRole.PersonId. Profile/employment fields come from the related
 * Account / PersonEmployment. Ken_Alumni_CRM__c is intentionally NOT used —
 * this matches the canonical data model and keeps tab counts consistent with
 * the dashboard.
 */
public with sharing class KenAdminAlumniController {

    private static final Set<String> LEAD_SOURCES = new Set<String>{
        'Self-Declared Lead', 'Campaign Lead'
    };
    private static final Set<String> OLD_PORTAL_SOURCES = new Set<String>{
        'Old Portal Record', 'Old Portal Migration'
    };
    private static final Set<String> ACTIVE_REG_STATUSES = new Set<String>{
        'Initial Login Done'
    };
    private static final Set<String> REGISTERED_REG_STATUSES = new Set<String>{
        'Registered', 'Initial Login Done'
    };
    private static final Set<String> VERIFIED_REG_STATUSES = new Set<String>{
        'Verified', 'Registered', 'Initial Login Done'
    };

    /* ============================================================
       Wrapper types
       ============================================================ */
    public class AlumniRow {
        @AuraEnabled public Id    alumniId;             // ConstituentRole.Id
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String emailWarning;
        @AuraEnabled public String program;
        @AuraEnabled public String institution;
        @AuraEnabled public String batch;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String location;
        @AuraEnabled public String country;
        @AuraEnabled public String company;
        @AuraEnabled public String role;
        @AuraEnabled public String masterRecordStatus;
        @AuraEnabled public String portalStatus;
        @AuraEnabled public String source;
        @AuraEnabled public String matchMerge;
        @AuraEnabled public Integer completenessPct;
        @AuraEnabled public Datetime lastUpdated;
        @AuraEnabled public String referredByName;
        @AuraEnabled public Id existingAccountId;
        @AuraEnabled public String existingAccountName;
        @AuraEnabled public String roleType;
        @AuraEnabled public Boolean isNewRole;
    }

    public class ContactIssue {
        @AuraEnabled public Id     alumniId;
        @AuraEnabled public String name;
        @AuraEnabled public String program;
        @AuraEnabled public String batch;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String location;
        @AuraEnabled public String country;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public Boolean emailMissing;
        @AuraEnabled public Boolean emailBounced;
        @AuraEnabled public Boolean phoneMissing;
        @AuraEnabled public Integer issuesRemaining;
        @AuraEnabled public String bounceNote;
    }

    public class TimelineEntry {
        @AuraEnabled public String title;
        @AuraEnabled public String actor;
        @AuraEnabled public Datetime occurredAt;
        public TimelineEntry(String t, String a, Datetime ts) { title = t; actor = a; occurredAt = ts; }
    }

    public class FieldUpdate {
        @AuraEnabled public Datetime occurredAt;
        @AuraEnabled public String field;
        @AuraEnabled public String previousValue;
        @AuraEnabled public String newValue;
        @AuraEnabled public String sourceTag;
        @AuraEnabled public String updatedBy;
        public FieldUpdate(Datetime ts, String f, String oldV, String newV, String src, String updater) {
            occurredAt = ts; field = f; previousValue = oldV; newValue = newV;
            sourceTag = src; updatedBy = updater;
        }
    }

    public class SaveResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;
        @AuraEnabled public Integer issuesRemaining;
        public SaveResult(Boolean ok, String msg, Integer remaining) {
            success = ok; message = msg; issuesRemaining = remaining;
        }
    }

    public class AlumniList {
        @AuraEnabled public List<AlumniRow> rows;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
    }

    public class TabCounts {
        @AuraEnabled public Integer all;
        @AuraEnabled public Integer recent;
        @AuraEnabled public Integer registered;
        @AuraEnabled public Integer unregistered;
        @AuraEnabled public Integer oldPortal;
        @AuraEnabled public Integer issues;
        @AuraEnabled public Integer leads;
        @AuraEnabled public Integer referrals;
    }

    public class IssueChipCounts {
        @AuraEnabled public Integer all;
        @AuraEnabled public Integer missingEmail;
        @AuraEnabled public Integer missingPhone;
        @AuraEnabled public Integer invalidEmail;
        @AuraEnabled public Integer bouncedEmail;
        @AuraEnabled public Integer invalidPhone;
    }

    public class ConvertResult {
        @AuraEnabled public Integer converted;
        @AuraEnabled public Integer skipped;
        @AuraEnabled public String  message;
        public ConvertResult(Integer c, Integer s, String m) { converted = c; skipped = s; message = m; }
    }

    public class AlumniDetail {
        @AuraEnabled public Id     alumniId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String linkedinUrl;
        @AuraEnabled public String program;
        @AuraEnabled public String batch;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String company;
        @AuraEnabled public String role;
        @AuraEnabled public String industry;
        @AuraEnabled public String location;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public Boolean hasLoggedInOnce;
        @AuraEnabled public Datetime lastLogin;
        @AuraEnabled public Datetime registrationDate;
        @AuraEnabled public Integer completenessPct;
        @AuraEnabled public String engagementScore;
        @AuraEnabled public String source;
        @AuraEnabled public List<String> interests;
        @AuraEnabled public Boolean hideEmail;
        @AuraEnabled public Boolean hidePhone;
    }

    public class MergeCandidate {
        @AuraEnabled public Id     alumniId;
        @AuraEnabled public String name;
        @AuraEnabled public String initials;
        @AuraEnabled public String batch;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String source;
    }

    public class FilterOptions {
        // Legacy keys retained for backwards compatibility with any other consumer.
        @AuraEnabled public List<String> programs;
        @AuraEnabled public List<String> graduationYears;
        @AuraEnabled public List<String> sources;
        @AuraEnabled public List<String> companies;
        @AuraEnabled public List<String> industries;
        @AuraEnabled public List<String> locations;
        @AuraEnabled public List<String> countries;
        // New Master-records filter set.
        @AuraEnabled public List<String> institutes;   // ConstituentRole.Institution_Name__c
        @AuraEnabled public List<String> roles;        // PersonEmployment.Designation__c
        @AuraEnabled public List<String> domains;      // PersonEmployment.Job_Role__c
        @AuraEnabled public List<String> intakes;      // LearningProgramPlan.Start_Year__c
        @AuraEnabled public List<String> skills;       // Ken_Alumni_Preferences__c.Skill_set__c
        @AuraEnabled public List<String> statuses;     // ConstituentRole.Registration_Status__c
        @AuraEnabled public List<String> preferences;  // Ken_Engagement_Preference__c names
        // Label/value/count triples so the dropdown shows "<value> (<count>)".
        @AuraEnabled public List<FilterOptionPair> programPairs;
        @AuraEnabled public List<FilterOptionPair> graduationYearPairs;
        @AuraEnabled public List<FilterOptionPair> sourcePairs;
        @AuraEnabled public List<FilterOptionPair> companyPairs;
        @AuraEnabled public List<FilterOptionPair> industryPairs;
        @AuraEnabled public List<FilterOptionPair> locationPairs;
        @AuraEnabled public List<FilterOptionPair> countryPairs;
        @AuraEnabled public List<FilterOptionPair> institutePairs;
        @AuraEnabled public List<FilterOptionPair> rolePairs;
        @AuraEnabled public List<FilterOptionPair> domainPairs;
        @AuraEnabled public List<FilterOptionPair> intakePairs;
        @AuraEnabled public List<FilterOptionPair> skillPairs;
        @AuraEnabled public List<FilterOptionPair> statusPairs;
        @AuraEnabled public List<FilterOptionPair> preferencePairs;
    }

    /* ============================================================
       Public API
       ============================================================ */

    @AuraEnabled(cacheable=true)
    public static AlumniList getAlumniRecords(String tabKey, String searchTerm, String issueType, String portalStatus, Integer pageSize, Integer pageNumber, String dashboardFilter, String filtersJson) {
        if (pageSize == null  || pageSize <= 0)  pageSize = 25;
        if (pageNumber == null || pageNumber < 1) pageNumber = 1;
        Integer offset = (pageNumber - 1) * pageSize;

        AlumniList result = new AlumniList();
        result.pageSize = pageSize;
        result.pageNumber = pageNumber;
        result.rows = new List<AlumniRow>();

        // Leads tab is Lead-driven now: show every Lead with Status='New'.
        // No ConstituentRole join, no Source_Funnel__c filter — just the Lead.
        if (tabKey == 'leads') {
            return buildNewLeadsList(result, searchTerm, pageSize, offset, pageNumber, filtersJson);
        }

        // Resolve PersonIds matching contact-issue filter when needed
        Set<Id> issuePersonIds = null;
        if (tabKey == 'issues') {
            issuePersonIds = resolveIssuePersonIds(issueType);
        }
        // Resolve PersonIds matching the free-text search across Account + PersonEmployment fields
        Set<Id> searchPersonIds = String.isNotBlank(searchTerm) ? resolveSearchPersonIds(searchTerm) : null;
        Set<Id> filterPersonIds = resolveFilterPersonIds(filtersJson);

        String whereClause = buildWhereForTab(tabKey, searchTerm, issueType, portalStatus, dashboardFilter, issuePersonIds, searchPersonIds, filtersJson, filterPersonIds);

        String countQuery = 'SELECT COUNT() FROM ConstituentRole ' + whereClause;
        result.totalRecords = Database.countQuery(countQuery);

        String listQuery =
            'SELECT Id, RoleType, Source_Funnel__c, Registration_Status__c, Status, ' +
            '       Graduation_Year__c, Registration_Number__c, Institution_Name__c, ' +
            '       Program_Name__c, Program_Plan__c, Program_Plan__r.Name, ' +
            '       PersonId, Lead__c, Lead__r.Status, Lead__r.Is_Converted__c, ' +
            '       Referred_By__c, Referred_By__r.Name, ' +
            '       LastModifiedDate, CreatedDate ' +
            'FROM ConstituentRole ' + whereClause +
            ' ORDER BY LastModifiedDate DESC LIMIT :pageSize OFFSET :offset';

        List<ConstituentRole> roles = Database.query(listQuery);
        Map<Id, Account> personAccounts = fetchPersonAccounts(roles);
        Map<Id, PersonEmployment> latestEmployment = fetchLatestEmployment(personAccounts.keySet());

        for (ConstituentRole cr : roles) {
            result.rows.add(toAlumniRow(cr, personAccounts.get(cr.PersonId), latestEmployment.get(cr.PersonId)));
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static TabCounts getTabCounts(String dashboardFilter) {
        TabCounts tc = new TabCounts();
        tc.all        = countForTab('all',        dashboardFilter);
        tc.recent     = countForTab('recent',     dashboardFilter);
        tc.registered = countForTab('registered', dashboardFilter);
        tc.unregistered = countForTab('unregistered', dashboardFilter);
        tc.oldPortal  = countForTab('oldportal',  dashboardFilter);
        tc.issues     = countForTab('issues',     dashboardFilter);
        tc.leads      = countForTab('leads',      dashboardFilter);
        tc.referrals  = countForTab('referrals',  dashboardFilter);
        return tc;
    }

    /**
     * Counts per chip on the Data Issues tab, resolved by Person Account state.
     * Returns ConstituentRole counts (RoleType='Alumni') joined to PersonId IN the
     * matching Account set.
     */
    @AuraEnabled(cacheable=true)
    public static IssueChipCounts getIssueChipCounts(String dashboardFilter) {
        IssueChipCounts c = new IssueChipCounts();
        c.all          = countIssueChip('all',      dashboardFilter);
        c.missingEmail = countIssueChip('mail',     dashboardFilter);
        c.missingPhone = countIssueChip('phone',    dashboardFilter);
        c.invalidEmail = countIssueChip('invmail',  dashboardFilter);
        c.bouncedEmail = countIssueChip('bounce',   dashboardFilter);
        c.invalidPhone = countIssueChip('invphone', dashboardFilter);
        return c;
    }

    private static Integer countIssueChip(String chip, String dashboardFilter) {
        Set<Id> issuePersonIds = resolveIssuePersonIds(chip);
        String whereClause = buildWhereForTab('issues', null, chip, null, dashboardFilter, issuePersonIds, null, null, null);
        return Database.countQuery('SELECT COUNT() FROM ConstituentRole ' + whereClause);
    }

    private static Integer countForTab(String tabKey, String dashboardFilter) {
        // Leads tab is Lead-driven (alumni lead, Status='New') — count from Lead directly.
        if (tabKey == 'leads') {
            return Database.countQuery(
                'SELECT COUNT() FROM Lead WHERE Status = \'New\' ' +
                'AND RecordType.DeveloperName = \'Alumni_Lead\''
            );
        }
        Set<Id> issuePersonIds = (tabKey == 'issues') ? resolveIssuePersonIds(null) : null;
        String whereClause = buildWhereForTab(tabKey, null, null, null, dashboardFilter, issuePersonIds, null, null, null);
        String q = 'SELECT COUNT() FROM ConstituentRole ' + whereClause;
        return Database.countQuery(q);
    }

    /**
     * Bulk-convert selected leads. For each ConstituentRole originating from a lead
     * source, flips Registration_Status__c to 'Verified' — the intermediate state the
     * rest of the controller already treats as upload-available / leads-verified.
     * The actual Lead.Convert() happens downstream (admin / approval flow); this
     * button only marks the role as ready for that. Skips rows whose Source_Funnel__c
     * isn't a lead source or whose role is already Verified+ (Registered, Initial Login Done).
     */
    @AuraEnabled
    public static ConvertResult convertLeads(List<Id> alumniIds) {
        if (alumniIds == null || alumniIds.isEmpty()) {
            return new ConvertResult(0, 0, 'No records selected.');
        }
        // The Leads tab now passes Lead Ids (00Q…); the other tabs still pass
        // ConstituentRole Ids. Split by prefix and apply the right transition.
        List<Id> leadIds = new List<Id>();
        List<Id> roleIds = new List<Id>();
        for (Id idVal : alumniIds) {
            if (idVal == null) continue;
            if (String.valueOf(idVal).startsWith('00Q')) {
                leadIds.add(idVal);
            } else {
                roleIds.add(idVal);
            }
        }

        Integer convertedCount = 0;
        Integer skipped = 0;

        // Lead path: Status 'New' → 'Verified'. Anything not in 'New' is skipped.
        if (!leadIds.isEmpty()) {
            List<Lead> leads = [SELECT Id, Status FROM Lead WHERE Id IN :leadIds];
            List<Lead> leadsToUpdate = new List<Lead>();
            for (Lead ld : leads) {
                if (ld.Status == 'New') {
                    ld.Status = 'Verified';
                    leadsToUpdate.add(ld);
                } else {
                    skipped++;
                }
            }
            if (!leadsToUpdate.isEmpty()) update leadsToUpdate;
            convertedCount += leadsToUpdate.size();
        }

        // ConstituentRole path (legacy from other tabs): role Registration_Status__c
        // null/Unregistered/etc → 'Verified'.
        if (!roleIds.isEmpty()) {
            List<ConstituentRole> roles = [
                SELECT Id, Lead__c, Source_Funnel__c, Registration_Status__c
                FROM ConstituentRole
                WHERE Id IN :roleIds
            ];
            List<ConstituentRole> rolesToUpdate = new List<ConstituentRole>();
            Set<String> alreadyAdvanced = new Set<String>{ 'Verified', 'Registered', 'Initial Login Done' };
            for (ConstituentRole cr : roles) {
                Boolean isLead = LEAD_SOURCES.contains(cr.Source_Funnel__c);
                if (!isLead || alreadyAdvanced.contains(cr.Registration_Status__c)) {
                    skipped++;
                    continue;
                }
                cr.Registration_Status__c = 'Verified';
                rolesToUpdate.add(cr);
            }
            if (!rolesToUpdate.isEmpty()) update rolesToUpdate;
            convertedCount += rolesToUpdate.size();
        }

        return new ConvertResult(convertedCount, skipped, null);
    }

    @AuraEnabled(cacheable=true)
    public static AlumniDetail getAlumniDetail(Id alumniId) {
        if (alumniId == null) return null;
        ConstituentRole cr = [
            SELECT Id, RoleType, Source_Funnel__c, Registration_Status__c, Status,
                   Graduation_Year__c, Registration_Number__c,
                   Program_Name__c, Program_Plan__c, Program_Plan__r.Name,
                   PersonId, Lead__c, Lead__r.Status,
                   CreatedDate, LastModifiedDate
            FROM ConstituentRole
            WHERE Id = :alumniId
            LIMIT 1
        ];

        Map<Id, Account> personAccounts = fetchPersonAccounts(new List<ConstituentRole>{ cr });
        Account pa = personAccounts.get(cr.PersonId);
        Map<Id, PersonEmployment> emp = fetchLatestEmployment(personAccounts.keySet());
        PersonEmployment job = emp.get(cr.PersonId);

        AlumniDetail d = new AlumniDetail();
        d.alumniId = cr.Id;
        d.name = pickName(pa);
        d.email = pa != null ? pa.PersonEmail : null;
        d.phone = pa != null ? pa.PersonMobilePhone : null;
        d.linkedinUrl = pa != null ? (String) pa.get('Linkedin_Profile_URL__c') : null;
        d.program = pickProgram(cr);
        d.batch = cr.Graduation_Year__c;
        d.registrationNumber = cr.Registration_Number__c;
        d.company = job != null ? job.Company_Name__c : null;
        d.role = job != null ? job.Designation__c : null;
        d.industry = job != null ? job.Job_Role__c : null;
        d.location = job != null ? job.Location__c : null;
        d.approvalStatus = cr.Registration_Status__c;
        d.hasLoggedInOnce = ACTIVE_REG_STATUSES.contains(cr.Registration_Status__c);
        d.lastLogin = null; // not stored on ConstituentRole; could be derived from a Login_History query
        d.registrationDate = cr.CreatedDate;
        d.completenessPct = completenessOf(cr, pa, job);
        d.engagementScore = scoreOf(cr);
        d.source = cr.Source_Funnel__c;
        d.interests = new List<String>();
        d.hideEmail = false;
        d.hidePhone = false;
        return d;
    }

    @AuraEnabled(cacheable=true)
    public static List<MergeCandidate> getMergeCandidates(String searchTerm, String gradYear) {
        List<MergeCandidate> results = new List<MergeCandidate>();
        if (String.isBlank(searchTerm)) return results;

        String likeVar = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<Account> accts = [
            SELECT Id, Name FROM Account
            WHERE IsPersonAccount = true AND (Name LIKE :likeVar OR PersonEmail LIKE :likeVar)
            LIMIT 20
        ];
        Set<Id> personIds = new Set<Id>();
        Map<Id, Account> acctMap = new Map<Id, Account>();
        for (Account a : accts) { personIds.add(a.Id); acctMap.put(a.Id, a); }

        List<ConstituentRole> roles = new List<ConstituentRole>();
        Set<Id> seenRoleIds = new Set<Id>();
        if (!personIds.isEmpty()) {
            String soql =
                'SELECT Id, PersonId, Graduation_Year__c, Registration_Number__c, Source_Funnel__c ' +
                'FROM ConstituentRole WHERE RoleType = \'Alumni\' AND PersonId IN :personIds';
            soql += ' LIMIT 10';
            for (ConstituentRole cr : Database.query(soql)) {
                roles.add(cr);
                seenRoleIds.add(cr.Id);
            }
        }
        for (ConstituentRole cr : [
            SELECT Id, PersonId, Graduation_Year__c, Registration_Number__c, Source_Funnel__c
            FROM ConstituentRole
            WHERE RoleType = 'Alumni' AND Registration_Number__c LIKE :likeVar
            LIMIT 10
        ]) {
            if (!seenRoleIds.contains(cr.Id)) {
                roles.add(cr);
                seenRoleIds.add(cr.Id);
            }
        }
        if (roles.isEmpty()) return results;

        // Resolve any Person Account names we didn't already fetch (reg-matched roles).
        Set<Id> needAcctIds = new Set<Id>();
        for (ConstituentRole cr : roles) {
            if (cr.PersonId != null && !acctMap.containsKey(cr.PersonId)) needAcctIds.add(cr.PersonId);
        }
        if (!needAcctIds.isEmpty()) {
            for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :needAcctIds]) acctMap.put(a.Id, a);
        }

        for (ConstituentRole cr : roles) {
            Account a = acctMap.get(cr.PersonId);
            MergeCandidate c = new MergeCandidate();
            c.alumniId = cr.Id;
            c.name = a != null ? a.Name : '';
            c.initials = initialsOf(c.name);
            c.batch = cr.Graduation_Year__c;
            c.registrationNumber = cr.Registration_Number__c;
            c.source = cr.Source_Funnel__c;
            results.add(c);
        }
        return results;
    }

    @AuraEnabled
    public static SaveResult rejectLead(Id leadId) {
        if (leadId == null || !String.valueOf(leadId).startsWith('00Q')) {
            return new SaveResult(false, 'Reject is only available for lead records.', null);
        }
        try {
            Lead ld = [SELECT Id, Status FROM Lead WHERE Id = :leadId LIMIT 1];
            ld.Status = 'Rejected';
            update ld;
            return new SaveResult(true, 'Lead rejected.', null);
        } catch (Exception e) {
            return new SaveResult(false, e.getMessage(), null);
        }
    }

    /**
     * Merge an unmerged Lead into an existing master alumni identity (a chosen
     * ConstituentRole). The master record is the source of truth: we only LINK
     * the lead and FILL GAPS on the master from the lead's captured fields — we
     * never overwrite values the master already has.
     *
     * Any other unconverted leads sharing the same email are also absorbed: the
     * master gets their data (gap-fill only) and they are marked Merged too.
     *
     * Is_Converted__c = true bypasses the provisioning trigger so no second
     * Person Account is created for the merged lead.
     */
    @AuraEnabled
    public static SaveResult mergeLeadIntoMaster(Id leadId, Id masterRoleId) {
        if (leadId == null || masterRoleId == null) {
            return new SaveResult(false, 'Pick a master record to merge into.', null);
        }
        if (!String.valueOf(leadId).startsWith('00Q')) {
            return new SaveResult(false, 'Merge is currently supported for lead records only.', null);
        }
        try {
            Lead ld = [
                SELECT Id, Status, FirstName, LastName, Email, Phone,
                       Year_of_Graduation__c, Registration_Number__c,
                       Institution_Name__c, Program_Plan__c, Referred_By__c
                FROM Lead WHERE Id = :leadId LIMIT 1
            ];
            if (ld.Status == 'Converted' || ld.Status == 'Merged') {
                return new SaveResult(false, 'This lead is already merged/converted.', null);
            }

            List<ConstituentRole> masters = [
                SELECT Id, PersonId, Lead__c, Email__c, Registration_Number__c,
                       Graduation_Year__c, Program_Plan__c, Referred_By__c
                FROM ConstituentRole
                WHERE Id = :masterRoleId AND RoleType = 'Alumni' LIMIT 1
            ];
            if (masters.isEmpty()) {
                return new SaveResult(false, 'Selected master record was not found.', null);
            }
            ConstituentRole cr = masters[0];

            // 1) Link + fill gaps on the master ConstituentRole (never overwrite).
            Boolean roleDirty = false;
            if (cr.Lead__c == null)                                       { cr.Lead__c = ld.Id; roleDirty = true; }
            if (String.isBlank(cr.Registration_Number__c) && String.isNotBlank(ld.Registration_Number__c)) { cr.Registration_Number__c = ld.Registration_Number__c; roleDirty = true; }
            if (String.isBlank(cr.Graduation_Year__c)     && String.isNotBlank(ld.Year_of_Graduation__c))   { cr.Graduation_Year__c     = ld.Year_of_Graduation__c;   roleDirty = true; }
            if (cr.Program_Plan__c == null                && ld.Program_Plan__c != null)                     { cr.Program_Plan__c        = ld.Program_Plan__c;          roleDirty = true; }
            if (String.isBlank(cr.Email__c)               && String.isNotBlank(ld.Email))                    { cr.Email__c               = ld.Email;                    roleDirty = true; }
            if (cr.Referred_By__c == null                 && ld.Referred_By__c != null)                      { cr.Referred_By__c         = ld.Referred_By__c;           roleDirty = true; }
            if (roleDirty) update cr;

            // 2) Fill gaps on the master Person Account — never overwrite existing values.
            if (cr.PersonId != null) {
                List<Account> pas = [
                    SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone
                    FROM Account WHERE Id = :cr.PersonId LIMIT 1
                ];
                if (!pas.isEmpty()) {
                    Account pa = pas[0];
                    Boolean paDirty = false;
                    if (String.isBlank(pa.FirstName)          && String.isNotBlank(ld.FirstName)) { pa.FirstName          = ld.FirstName; paDirty = true; }
                    if (String.isBlank(pa.LastName)           && String.isNotBlank(ld.LastName))  { pa.LastName           = ld.LastName;  paDirty = true; }
                    if (String.isBlank(pa.PersonEmail)        && String.isNotBlank(ld.Email))      { pa.PersonEmail        = ld.Email;     paDirty = true; }
                    if (String.isBlank(pa.PersonMobilePhone)  && String.isNotBlank(ld.Phone))      { pa.PersonMobilePhone  = ld.Phone;     paDirty = true; }
                    if (paDirty) update pa;
                }
            }

            // 3) Mark the primary lead as Merged.
            ld.Status = 'Merged';
            ld.Is_Converted__c = true;
            update ld;

            // 4) Absorb any other unconverted leads sharing the same email.
            if (String.isNotBlank(ld.Email)) {
                List<Lead> siblings = [
                    SELECT Id, Status, Phone, Year_of_Graduation__c,
                           Registration_Number__c, Program_Plan__c
                    FROM Lead
                    WHERE Email = :ld.Email
                      AND Id != :ld.Id
                      AND Status NOT IN ('Converted', 'Merged', 'Rejected')
                    LIMIT 50
                ];
                if (!siblings.isEmpty()) {
                    // Re-fetch master ConstituentRole to see gap-fill state after primary lead.
                    cr = [SELECT Id, PersonId, Lead__c, Email__c, Registration_Number__c,
                                 Graduation_Year__c, Program_Plan__c
                          FROM ConstituentRole WHERE Id = :cr.Id LIMIT 1];
                    List<Lead> toMark = new List<Lead>();
                    for (Lead sib : siblings) {
                        Boolean crDirty2 = false;
                        if (String.isBlank(cr.Registration_Number__c) && String.isNotBlank(sib.Registration_Number__c)) { cr.Registration_Number__c = sib.Registration_Number__c; crDirty2 = true; }
                        if (String.isBlank(cr.Graduation_Year__c)     && String.isNotBlank(sib.Year_of_Graduation__c))   { cr.Graduation_Year__c     = sib.Year_of_Graduation__c;   crDirty2 = true; }
                        if (cr.Program_Plan__c == null                && sib.Program_Plan__c != null)                     { cr.Program_Plan__c        = sib.Program_Plan__c;          crDirty2 = true; }
                        if (crDirty2) update cr;
                        sib.Status = 'Merged';
                        sib.Is_Converted__c = true;
                        toMark.add(sib);
                    }
                    update toMark;
                }
            }

            return new SaveResult(true, 'Lead merged with the master record.', null);
        } catch (Exception e) {
            return new SaveResult(false, e.getMessage(), null);
        }
    }

    /* ============================================================
       Helpers — query building
       ============================================================ */

    private static String buildWhereForTab(String tabKey, String searchTerm, String issueType, String portalStatus, String dashboardFilter, Set<Id> issuePersonIds, Set<Id> searchPersonIds, String filtersJson, Set<Id> filterPersonIds) {
        List<String> conditions = new List<String>();
        conditions.add('RoleType = \'Alumni\'');

        if (String.isNotBlank(dashboardFilter)) {
            for (String c : dashboardFilterConditions(dashboardFilter)) {
                conditions.add(c);
            }
        }
        if (tabKey == 'recent') {
            conditions.add('Registration_Status__c IN (\'Registered\', \'Initial Login Done\')');
            conditions.add('CreatedDate = LAST_N_DAYS:30');
        } else if (tabKey == 'registered') {
            conditions.add('Registration_Status__c IN (\'Registered\', \'Initial Login Done\')');
        } else if (tabKey == 'unregistered') {
            // Alumni whose role exists but who haven't completed registration yet.
            conditions.add('RoleType = \'Alumni\'');
            conditions.add('(Registration_Status__c = null OR Registration_Status__c = \'Unregistered\' OR Registration_Status__c = \'Verified\')');
        } else if (tabKey == 'oldportal') {
            conditions.add('Source_Funnel__c IN (\'Old Portal Record\', \'Old Portal Migration\')');
        } else if (tabKey == 'issues') {
            if (issuePersonIds == null || issuePersonIds.isEmpty()) {
                // Force empty result deterministically
                conditions.add('Id = null');
            } else {
                conditions.add('PersonId IN :issuePersonIds');
            }
        } else if (tabKey == 'leads') {
            // Show every lead-sourced row that hasn't been advanced past New yet.
            // Anything still null / blank / pre-Verified counts as a new lead.
            // Once Convert flips it to Verified (or beyond), it drops off the tab.
            conditions.add('Source_Funnel__c IN (\'Self-Declared Lead\', \'Campaign Lead\')');
            conditions.add('(Registration_Status__c = null OR Registration_Status__c NOT IN (\'Verified\', \'Registered\', \'Initial Login Done\'))');
        } else if (tabKey == 'referrals') {
            conditions.add('Source_Funnel__c = \'Alumni Referral\'');
        }
        if (String.isNotBlank(portalStatus)) {
            if (portalStatus == 'active') {
                conditions.add('Registration_Status__c = \'Initial Login Done\'');
            } else if (portalStatus == 'registered') {
                conditions.add('Registration_Status__c = \'Registered\'');
            } else if (portalStatus == 'not') {
                conditions.add('(Registration_Status__c = null OR Registration_Status__c = \'Unregistered\' OR Registration_Status__c = \'Verified\')');
                conditions.add('Source_Funnel__c != \'Old Portal Record\'');
                conditions.add('Source_Funnel__c != \'Old Portal Migration\'');
            } else if (portalStatus == 'old') {
                conditions.add('Source_Funnel__c IN (\'Old Portal Record\', \'Old Portal Migration\')');
            }
        }
        if (String.isNotBlank(searchTerm)) {
            String esc = String.escapeSingleQuotes(searchTerm);
            String pat = '\'%' + esc + '%\'';
            // Match either a direct ConstituentRole field or any PersonId resolved
            // by searching Account/PersonEmployment.
            String personClause = (searchPersonIds != null && !searchPersonIds.isEmpty())
                ? ' OR PersonId IN :searchPersonIds'
                : '';
            conditions.add(
                '(Registration_Number__c LIKE ' + pat +
                ' OR Graduation_Year__c LIKE ' + pat +
                ' OR Program_Name__c LIKE ' + pat +
                personClause + ')'
            );
        }
        // Advanced multi-filter (from the Filters popup). Direct ConstituentRole
        // fields are applied inline; person-based fields (company/industry/
        // location/country) are pre-resolved into filterPersonIds.
        if (String.isNotBlank(filtersJson)) {
            Map<String, Object> f = (Map<String, Object>) JSON.deserializeUntyped(filtersJson);
            // ConstituentRole-direct filters
            String program = filterVal(f, 'program');
            if (String.isNotBlank(program)) {
                // Match Program_Name__c (free-text) OR the related plan's Name
                // (for records where Program_Name__c is null but a plan is linked).
                conditions.add('(Program_Name__c = \'' + String.escapeSingleQuotes(program) +
                    '\' OR Program_Plan__r.Name = \'' + String.escapeSingleQuotes(program) + '\')');
            }
            String gradYear = filterVal(f, 'graduationYear');
            if (String.isNotBlank(gradYear)) {
                conditions.add('Graduation_Year__c = \'' + String.escapeSingleQuotes(gradYear) + '\'');
            }
            String source = filterVal(f, 'source');
            if (String.isNotBlank(source)) {
                conditions.add('Source_Funnel__c = \'' + String.escapeSingleQuotes(source) + '\'');
            }
            // New Master-records filter set — institute / intake / status are direct
            // ConstituentRole columns and apply inline. role / domain / skill are
            // person-based and get folded into filterPersonIds.
            String institute = filterVal(f, 'institute');
            if (String.isNotBlank(institute)) {
                conditions.add('Institution_Name__c = \'' + String.escapeSingleQuotes(institute) + '\'');
            }
            String intake = filterVal(f, 'intake');
            if (String.isNotBlank(intake)) {
                // Intake is the LearningProgramPlan cohort name (e.g. "BBA-DEC-2025").
                conditions.add('Program_Plan__r.Name = \'' + String.escapeSingleQuotes(intake) + '\'');
            }
            String status = filterVal(f, 'status');
            if (String.isNotBlank(status)) {
                if (status == 'Registered') {
                    conditions.add('Registration_Status__c IN (\'Registered\', \'Initial Login Done\')');
                } else if (status == 'Unregistered') {
                    conditions.add('(Registration_Status__c = null OR Registration_Status__c = \'Unregistered\')');
                }
            }
            if (hasPersonFilters(f)) {
                if (filterPersonIds == null || filterPersonIds.isEmpty()) {
                    conditions.add('Id = null');
                } else {
                    conditions.add('PersonId IN :filterPersonIds');
                }
            }
        }
        return 'WHERE ' + String.join(conditions, ' AND ');
    }

    private static String filterVal(Map<String, Object> f, String key) {
        if (f == null || !f.containsKey(key) || f.get(key) == null) return null;
        String v = String.valueOf(f.get(key)).trim();
        return String.isBlank(v) ? null : v;
    }

    private static Boolean hasPersonFilters(Map<String, Object> f) {
        return String.isNotBlank(filterVal(f, 'company'))
            || String.isNotBlank(filterVal(f, 'industry'))
            || String.isNotBlank(filterVal(f, 'location'))
            || String.isNotBlank(filterVal(f, 'country'))
            || String.isNotBlank(filterVal(f, 'role'))
            || String.isNotBlank(filterVal(f, 'domain'))
            || String.isNotBlank(filterVal(f, 'skill'))
            || String.isNotBlank(filterVal(f, 'preference'));
    }

    /**
     * Resolves the Person Account Ids that satisfy ALL person-based filters
     * (company, industry, location, country) via intersection. Returns null when
     * no person-based filter is set (so it is not applied), or an empty set when
     * a filter matches nothing (forcing zero results).
     */
    private static Set<Id> resolveFilterPersonIds(String filtersJson) {
        if (String.isBlank(filtersJson)) return null;
        Map<String, Object> f = (Map<String, Object>) JSON.deserializeUntyped(filtersJson);
        if (!hasPersonFilters(f)) return null;

        Set<Id> result = null;
        String company = filterVal(f, 'company');
        if (String.isNotBlank(company)) result = intersectIds(result, empPersonIds('Company_Name__c', company));
        String industry = filterVal(f, 'industry');
        if (String.isNotBlank(industry)) result = intersectIds(result, empPersonIds('Job_Role__c', industry));
        String location = filterVal(f, 'location');
        if (String.isNotBlank(location)) result = intersectIds(result, empPersonIds('Location__c', location));
        String country = filterVal(f, 'country');
        if (String.isNotBlank(country)) result = intersectIds(result, countryPersonIds(country));
        // New Master-records person-based filters.
        String roleVal = filterVal(f, 'role');
        if (String.isNotBlank(roleVal)) result = intersectIds(result, empPersonIds('Designation__c', roleVal));
        String domain = filterVal(f, 'domain');
        if (String.isNotBlank(domain)) result = intersectIds(result, empPersonIds('Job_Role__c', domain));
        String skill = filterVal(f, 'skill');
        if (String.isNotBlank(skill)) result = intersectIds(result, skillPersonIds(skill));
        String preference = filterVal(f, 'preference');
        if (String.isNotBlank(preference)) result = intersectIds(result, preferencePersonIds(preference));
        return result == null ? new Set<Id>() : result;
    }

    /**
     * Person Account Ids whose Ken_Alumni_Preferences__c.Skill_set__c (multi-picklist)
     * INCLUDES the requested skill. Uses INCLUDES so partial matches in a stored
     * `Java;Python` value still hit.
     */
    private static Set<Id> skillPersonIds(String skill) {
        Set<Id> ids = new Set<Id>();
        for (Ken_Alumni_Preferences__c p : [
            SELECT Person_Account__c
            FROM Ken_Alumni_Preferences__c
            WHERE Skill_set__c INCLUDES (:skill)
              AND Person_Account__c != null
            LIMIT 50000
        ]) {
            if (p.Person_Account__c != null) ids.add(p.Person_Account__c);
        }
        return ids;
    }

    /**
     * Person Account Ids whose engagement preferences include the requested
     * value. Checks the semicolon-separated text field (new save target) and
     * falls back to the legacy Preferences__c multiselect for older records.
     */
    private static Set<Id> preferencePersonIds(String preference) {
        Set<Id> ids = new Set<Id>();
        String likeVal = '%' + preference + '%';
        for (Ken_Alumni_CRM__c r : [
            SELECT Person_Account__c
            FROM Ken_Alumni_CRM__c
            WHERE Engagement_Preferences__c LIKE :likeVal
              AND Person_Account__c != null
            LIMIT 50000
        ]) {
            ids.add(r.Person_Account__c);
        }
        try {
            for (Ken_Alumni_CRM__c r : [
                SELECT Person_Account__c
                FROM Ken_Alumni_CRM__c
                WHERE Preferences__c INCLUDES (:preference)
                  AND Person_Account__c != null
                LIMIT 50000
            ]) {
                ids.add(r.Person_Account__c);
            }
        } catch (Exception e) {
            // Value not in the legacy picklist — text matches above are enough.
        }
        return ids;
    }

    private static Set<Id> intersectIds(Set<Id> current, Set<Id> next) {
        if (current == null) return next;
        current.retainAll(next);
        return current;
    }

    private static Set<Id> empPersonIds(String field, String value) {
        Set<Id> ids = new Set<Id>();
        String soql = 'SELECT AccountId FROM PersonEmployment WHERE AccountId != null AND ' + field + ' = :value LIMIT 50000';
        for (SObject pe : Database.query(soql)) {
            Id a = (Id) pe.get('AccountId');
            if (a != null) ids.add(a);
        }
        return ids;
    }

    private static Set<Id> countryPersonIds(String value) {
        Set<Id> ids = new Set<Id>();
        for (Account a : [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonMailingCountry = :value LIMIT 50000]) {
            ids.add(a.Id);
        }
        return ids;
    }

    /**
     * Distinct values that populate the Filters popup dropdowns.
     */
    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions(String tabKey, String dashboardFilter) {
        // Build a CR-scoped base condition that mirrors the current tab's WHERE.
        List<String> crParts = new List<String>{ 'RoleType = \'Alumni\'' };
        String tabCond = tabConditionForCR(tabKey);
        if (String.isNotBlank(tabCond)) crParts.add(tabCond);
        if (String.isNotBlank(dashboardFilter)) {
            crParts.addAll(dashboardFilterConditions(dashboardFilter));
        }
        String crWhere = String.join(crParts, ' AND ');

        FilterOptions o = new FilterOptions();
        // Legacy (fallback for _pairOptions when pairs list is empty)
        o.programs        = distinctValues('ConstituentRole', 'Program_Name__c', crWhere);
        o.graduationYears = distinctValues('ConstituentRole', 'Graduation_Year__c', crWhere);
        o.sources         = distinctValues('ConstituentRole', 'Source_Funnel__c', crWhere);
        o.companies       = distinctValues('PersonEmployment', 'Company_Name__c', null);
        o.industries      = distinctValues('PersonEmployment', 'Job_Role__c', null);
        o.locations       = distinctValues('PersonEmployment', 'Location__c', null);
        o.countries       = distinctValues('Account', 'PersonMailingCountry', 'IsPersonAccount = true');
        // New Master-records filter set
        o.institutes      = distinctValues('ConstituentRole', 'Institution_Name__c', crWhere);
        o.roles           = distinctValues('PersonEmployment', 'Designation__c', null);
        o.domains         = o.industries;
        // Intake = LearningProgramPlan cohort name (e.g. "BBA-DEC-2025").
        // LearningProgramPlan has no Start_Year__c; use Name which encodes cohort.
        o.intakes         = distinctValues('LearningProgramPlan', 'Name', null);
        o.skills          = distinctSkillValues();
        o.statuses        = new List<String>{ 'Registered', 'Unregistered' };

        // Label/value/count pairs for the popup. Skills + statuses are computed
        // separately because they don't come from a single SOQL field.
        o.programPairs        = programOptionPairs(crWhere);
        o.graduationYearPairs = distinctValuePairs('ConstituentRole', 'Graduation_Year__c', crWhere);
        o.sourcePairs         = distinctValuePairs('ConstituentRole', 'Source_Funnel__c', crWhere);
        o.companyPairs        = distinctValuePairs('PersonEmployment', 'Company_Name__c', null);
        o.industryPairs       = distinctValuePairs('PersonEmployment', 'Job_Role__c', null);
        o.locationPairs       = distinctValuePairs('PersonEmployment', 'Location__c', null);
        o.countryPairs        = distinctValuePairs('Account', 'PersonMailingCountry', 'IsPersonAccount = true');
        o.institutePairs      = distinctValuePairs('ConstituentRole', 'Institution_Name__c', crWhere);
        o.rolePairs           = distinctValuePairs('PersonEmployment', 'Designation__c', null);
        o.domainPairs         = o.industryPairs;
        o.intakePairs         = distinctValuePairs('LearningProgramPlan', 'Name', null);
        o.skillPairs          = skillPairs();
        o.statusPairs         = statusPairs(crWhere);
        o.preferencePairs     = preferencePairs();
        o.preferences         = new List<String>();
        for (FilterOptionPair p : o.preferencePairs) o.preferences.add(p.value);
        return o;
    }

    /** Returns the tab-specific WHERE fragment for ConstituentRole queries (no RoleType prefix). */
    private static String tabConditionForCR(String key) {
        if (key == 'recent')       return 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\') AND CreatedDate = LAST_N_DAYS:30';
        if (key == 'registered')   return 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')';
        if (key == 'unregistered') return '(Registration_Status__c = null OR Registration_Status__c = \'Unregistered\' OR Registration_Status__c = \'Verified\')';
        if (key == 'oldportal')    return 'Source_Funnel__c IN (\'Old Portal Record\', \'Old Portal Migration\')';
        if (key == 'leads')        return 'Source_Funnel__c IN (\'Self-Declared Lead\', \'Campaign Lead\') AND (Registration_Status__c = null OR Registration_Status__c NOT IN (\'Verified\', \'Registered\', \'Initial Login Done\'))';
        if (key == 'referrals')    return 'Source_Funnel__c = \'Alumni Referral\'';
        return '';
    }

    /**
     * Program filter options: merges Program_Name__c (legacy text) and
     * Program_Plan__r.Name (structured plan) so every value visible in the
     * table "Program & Batch" column is selectable in the filter.
     */
    private static List<FilterOptionPair> programOptionPairs(String crWhere) {
        Map<String, Integer> counts = new Map<String, Integer>();
        try {
            String soql = 'SELECT Program_Name__c, Program_Plan__r.Name FROM ConstituentRole'
                + ' WHERE ' + crWhere
                + ' AND (Program_Name__c != null OR Program_Plan__c != null) LIMIT 50000';
            for (ConstituentRole cr : (List<ConstituentRole>) Database.query(soql)) {
                String v = String.isNotBlank(cr.Program_Name__c)
                    ? cr.Program_Name__c
                    : (cr.Program_Plan__r != null ? cr.Program_Plan__r.Name : null);
                if (String.isBlank(v)) continue;
                counts.put(v, (counts.containsKey(v) ? counts.get(v) : 0) + 1);
            }
        } catch (Exception e) { /* swallow — return whatever we collected */ }
        List<String> keys = new List<String>(counts.keySet());
        keys.sort();
        List<FilterOptionPair> out = new List<FilterOptionPair>();
        for (String k : keys) {
            FilterOptionPair p = new FilterOptionPair();
            p.value = k; p.count = counts.get(k); p.label = k + ' (' + p.count + ')';
            out.add(p);
        }
        return out;
    }

    /** Counts of Ken_Alumni_Preferences__c rows that include each skill. */
    private static List<FilterOptionPair> skillPairs() {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (Ken_Alumni_Preferences__c r : [
            SELECT Skill_set__c FROM Ken_Alumni_Preferences__c WHERE Skill_set__c != null LIMIT 50000
        ]) {
            if (String.isBlank(r.Skill_set__c)) continue;
            for (String s : r.Skill_set__c.split(';')) {
                String t = s == null ? '' : s.trim();
                if (String.isBlank(t)) continue;
                counts.put(t, (counts.containsKey(t) ? counts.get(t) : 0) + 1);
            }
        }
        List<String> keys = new List<String>(counts.keySet());
        keys.sort();
        List<FilterOptionPair> out = new List<FilterOptionPair>();
        for (String k : keys) {
            FilterOptionPair p = new FilterOptionPair();
            p.value = k; p.count = counts.get(k); p.label = k + ' (' + p.count + ')';
            out.add(p);
        }
        return out;
    }

    /**
     * Engagement preference filter options. Values come from the configurable
     * Ken_Engagement_Preference__c object (so admin-added preferences are
     * filterable immediately); counts come from the CRM rows that include each
     * value — text field first, legacy Preferences__c multiselect as fallback.
     */
    private static List<FilterOptionPair> preferencePairs() {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (Ken_Engagement_Preference__c p : [
            SELECT Name FROM Ken_Engagement_Preference__c
            WHERE Is_Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC
        ]) {
            counts.put(p.Name, 0);
        }
        for (Ken_Alumni_CRM__c r : [
            SELECT Engagement_Preferences__c, Preferences__c
            FROM Ken_Alumni_CRM__c
            WHERE Engagement_Preferences__c != null OR Preferences__c != null
            LIMIT 50000
        ]) {
            String raw = String.isNotBlank(r.Engagement_Preferences__c)
                ? r.Engagement_Preferences__c
                : r.Preferences__c;
            if (String.isBlank(raw)) continue;
            for (String s : raw.split(';')) {
                String t = s == null ? '' : s.trim();
                if (String.isBlank(t)) continue;
                counts.put(t, (counts.containsKey(t) ? counts.get(t) : 0) + 1);
            }
        }
        List<String> keys = new List<String>(counts.keySet());
        keys.sort();
        List<FilterOptionPair> out = new List<FilterOptionPair>();
        for (String k : keys) {
            FilterOptionPair p = new FilterOptionPair();
            p.value = k; p.count = counts.get(k); p.label = k + ' (' + p.count + ')';
            out.add(p);
        }
        return out;
    }

    /** Registered (Registered + Initial Login Done) vs Unregistered (null + Unregistered), scoped to crWhere. */
    private static List<FilterOptionPair> statusPairs(String crWhere) {
        Integer reg = Database.countQuery(
            'SELECT COUNT() FROM ConstituentRole WHERE ' + crWhere +
            ' AND Registration_Status__c IN (\'Registered\', \'Initial Login Done\')'
        );
        Integer unreg = Database.countQuery(
            'SELECT COUNT() FROM ConstituentRole WHERE ' + crWhere +
            ' AND (Registration_Status__c = null OR Registration_Status__c = \'Unregistered\')'
        );
        FilterOptionPair r = new FilterOptionPair();
        r.value = 'Registered'; r.count = reg; r.label = 'Registered (' + reg + ')';
        FilterOptionPair u = new FilterOptionPair();
        u.value = 'Unregistered'; u.count = unreg; u.label = 'Unregistered (' + unreg + ')';
        return new List<FilterOptionPair>{ r, u };
    }

    /**
     * Skill_set__c is a multi-picklist on Ken_Alumni_Preferences__c. We split each
     * stored value on the standard `;` separator and dedupe.
     */
    private static List<String> distinctSkillValues() {
        Set<String> seen = new Set<String>();
        for (Ken_Alumni_Preferences__c r : [
            SELECT Skill_set__c FROM Ken_Alumni_Preferences__c WHERE Skill_set__c != null LIMIT 5000
        ]) {
            if (String.isBlank(r.Skill_set__c)) continue;
            for (String s : r.Skill_set__c.split(';')) {
                String t = s == null ? '' : s.trim();
                if (String.isNotBlank(t)) seen.add(t);
            }
        }
        List<String> out = new List<String>(seen);
        out.sort();
        return out;
    }

    /**
     * Distinct, sorted, non-blank values for a field. Returns the raw values
     * used by the filter SOQL. The label-with-count variant lives in
     * {@link distinctValuePairs} so the dropdown can render "X (42)" while
     * the underlying filter still binds to the raw "X".
     */
    private static List<String> distinctValues(String objectName, String field, String extraWhere) {
        List<FilterOptionPair> pairs = distinctValuePairs(objectName, field, extraWhere);
        List<String> out = new List<String>();
        for (FilterOptionPair p : pairs) out.add(p.value);
        return out;
    }

    /**
     * label = "<value> (<count>)" / value = "<value>". Counts are total
     * occurrences on the underlying source object — not cascading with the
     * other open filters.
     */
    private static List<FilterOptionPair> distinctValuePairs(String objectName, String field, String extraWhere) {
        Map<String, Integer> counts = new Map<String, Integer>();
        String soql = 'SELECT ' + field + ' FROM ' + objectName + ' WHERE ' + field + ' != null';
        if (String.isNotBlank(extraWhere)) {
            soql += ' AND ' + extraWhere;
        }
        soql += ' LIMIT 50000';
        List<SObject> rows;
        try {
            rows = Database.query(soql);
        } catch (Exception queryEx) {
            return new List<FilterOptionPair>();
        }
        for (SObject r : rows) {
            Object v = r.get(field);
            if (v == null) continue;
            String s = String.valueOf(v);
            if (String.isBlank(s)) continue;
            counts.put(s, (counts.containsKey(s) ? counts.get(s) : 0) + 1);
        }
        List<String> keys = new List<String>(counts.keySet());
        keys.sort();
        List<FilterOptionPair> out = new List<FilterOptionPair>();
        for (String k : keys) {
            FilterOptionPair p = new FilterOptionPair();
            p.value = k;
            p.count = counts.get(k);
            p.label = k + ' (' + p.count + ')';
            out.add(p);
        }
        return out;
    }

    public class FilterOptionPair {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Integer count;
    }

    /**
     * Resolve PersonIds matching the free-text search across Account fields
     * (name, email, city, country, LinkedIn URL) and PersonEmployment fields
     * (company name, location). Returned set is consumed by dynamic SOQL via
     * the :searchPersonIds bind variable.
     */
    private static Set<Id> resolveSearchPersonIds(String searchTerm) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(searchTerm)) return ids;
        String likeVar = '%' + searchTerm + '%';
        for (Account a : [
            SELECT Id FROM Account
            WHERE IsPersonAccount = true
              AND (Name LIKE :likeVar
                   OR FirstName LIKE :likeVar
                   OR LastName LIKE :likeVar
                   OR PersonEmail LIKE :likeVar
                   OR PersonMailingCity LIKE :likeVar
                   OR PersonMailingCountry LIKE :likeVar
                   OR Linkedin_Profile_URL__c LIKE :likeVar)
            LIMIT 2000
        ]) {
            ids.add(a.Id);
        }
        for (PersonEmployment pe : [
            SELECT AccountId FROM PersonEmployment
            WHERE AccountId != null
              AND (Company_Name__c LIKE :likeVar OR Location__c LIKE :likeVar)
            LIMIT 2000
        ]) {
            if (pe.AccountId != null) ids.add(pe.AccountId);
        }
        return ids;
    }

    private static List<String> dashboardFilterConditions(String key) {
        Set<String> leadAndRef = new Set<String>{ 'Self-Declared Lead', 'Campaign Lead', 'Alumni Referral' };
        String leadsClause = '(Source_Funnel__c = \'Self-Declared Lead\' OR Source_Funnel__c = \'Campaign Lead\' OR Source_Funnel__c = \'Alumni Referral\')';
        String transClause = 'Source_Funnel__c = \'Student-to-Alumni Transition\'';
        Map<String, List<String>> m = new Map<String, List<String>>{
            'upload-uploaded'       => new List<String>(),
            'upload-available'      => new List<String>{ 'Registration_Status__c IN (\'Verified\', \'Registered\', \'Initial Login Done\')' },
            'upload-registered'     => new List<String>{ 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')' },
            'upload-active'         => new List<String>{ 'Registration_Status__c = \'Initial Login Done\'' },
            'transition-cohort'     => new List<String>{ transClause },
            'transition-invited'    => new List<String>{ transClause },
            'transition-registered' => new List<String>{ transClause, 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')' },
            'transition-active'     => new List<String>{ transClause, 'Registration_Status__c = \'Initial Login Done\'' },
            'leads-leads'           => new List<String>{ leadsClause },
            'leads-verified'        => new List<String>{ leadsClause, 'Registration_Status__c IN (\'Verified\', \'Registered\', \'Initial Login Done\')' },
            'leads-registered'      => new List<String>{ leadsClause, 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')' },
            'leads-active'          => new List<String>{ leadsClause, 'Registration_Status__c = \'Initial Login Done\'' },
            'kpi-total'             => new List<String>(),
            'kpi-verified'          => new List<String>{ 'Registration_Status__c IN (\'Verified\', \'Registered\', \'Initial Login Done\')' },
            'kpi-registered'        => new List<String>{ 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')' },
            'kpi-pending'           => new List<String>{ 'Registration_Status__c = \'Verified\'' }
        };
        List<String> out = m.get(key);
        return out != null ? out : new List<String>();
    }

    private static Set<Id> resolveIssuePersonIds(String issueType) {
        String chip = String.isBlank(issueType) ? 'all' : issueType;
        List<Account> rows;
        if (chip == 'mail') {
            rows = [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonEmail = null LIMIT 50000];
        } else if (chip == 'phone') {
            rows = [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonMobilePhone = null LIMIT 50000];
        } else if (chip == 'invmail') {
            rows = [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonEmail != null AND (NOT PersonEmail LIKE '%@%.%') LIMIT 50000];
        } else if (chip == 'bounce' || chip == 'invphone') {
            rows = new List<Account>();
        } else {
            rows = [SELECT Id FROM Account WHERE IsPersonAccount = true AND (PersonEmail = null OR PersonMobilePhone = null) LIMIT 50000];
        }
        Set<Id> ids = new Set<Id>();
        for (Account a : rows) ids.add(a.Id);
        return ids;
    }

    /* ============================================================
       Helpers — joining accounts + employment
       ============================================================ */

    private static Map<Id, Account> fetchPersonAccounts(List<ConstituentRole> roles) {
        Set<Id> ids = new Set<Id>();
        for (ConstituentRole cr : roles) if (cr.PersonId != null) ids.add(cr.PersonId);
        Map<Id, Account> out = new Map<Id, Account>();
        if (ids.isEmpty()) return out;
        for (Account a : [
            SELECT Id, Name, FirstName, LastName, IsPersonAccount,
                   PersonEmail, PersonMobilePhone, PersonMailingCountry, PersonMailingCity,
                   Linkedin_Profile_URL__c
            FROM Account
            WHERE Id IN :ids
        ]) {
            out.put(a.Id, a);
        }
        return out;
    }

    private static Map<Id, PersonEmployment> fetchLatestEmployment(Set<Id> personIds) {
        Map<Id, PersonEmployment> out = new Map<Id, PersonEmployment>();
        if (personIds == null || personIds.isEmpty()) return out;
        // Pick the "current" job per person (Currently_Employed true preferred, then most recent StartDate).
        for (PersonEmployment pe : [
            SELECT Id, AccountId, Company_Name__c, Designation__c, Job_Role__c, Location__c,
                   Currently_Employed__c, StartDate, CreatedDate
            FROM PersonEmployment
            WHERE AccountId IN :personIds
              AND (Is_Archived__c = false OR Is_Archived__c = null)
            ORDER BY Currently_Employed__c DESC NULLS LAST, StartDate DESC NULLS LAST, CreatedDate DESC
        ]) {
            if (!out.containsKey(pe.AccountId)) out.put(pe.AccountId, pe);
        }
        return out;
    }

    /**
     * Leads tab: query the Lead object directly for Status='New' rows. We bypass
     * the ConstituentRole join entirely because brand-new leads land here before
     * any role is provisioned. Optional search term matches Name/Email/Company.
     */
    private static AlumniList buildNewLeadsList(AlumniList result, String searchTerm, Integer pageSize, Integer offset, Integer pageNumber, String filtersJson) {
        // Alumni leads only — RecordType.DeveloperName = 'Alumni_Lead'.
        List<String> conds = new List<String>{
            'Status = \'New\'',
            'RecordType.DeveloperName = \'Alumni_Lead\''
        };
        if (String.isNotBlank(searchTerm)) {
            String likeVal = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            conds.add('(Name LIKE \'' + likeVal + '\' OR Email LIKE \'' + likeVal + '\' OR Company LIKE \'' + likeVal + '\')');
        }
        // Lead-tab filters: only the fields a Lead actually has (institute,
        // program plan, intake/graduation year, status). Address/employment
        // filters don't apply pre-conversion.
        if (String.isNotBlank(filtersJson)) {
            try {
                Map<String, Object> f = (Map<String, Object>) JSON.deserializeUntyped(filtersJson);
                Object instV = f.get('institute');
                if (instV != null && String.isNotBlank(String.valueOf(instV))) {
                    conds.add('Institution_Name__c = \'' + String.escapeSingleQuotes(String.valueOf(instV)) + '\'');
                }
                Object planV = f.get('programPlan');
                if (planV == null) planV = f.get('program');
                if (planV != null && String.isNotBlank(String.valueOf(planV))) {
                    String v = String.valueOf(planV);
                    // The combobox passes a LearningProgramPlan Id; fall back to a name match.
                    Boolean isId = (v.length() == 15 || v.length() == 18);
                    if (isId) conds.add('Program_Plan__c = \'' + String.escapeSingleQuotes(v) + '\'');
                    else conds.add('Program_Plan__r.Name = \'' + String.escapeSingleQuotes(v) + '\'');
                }
                Object yrV = f.get('graduationYear');
                if (yrV != null && String.isNotBlank(String.valueOf(yrV))) {
                    conds.add('Year_of_Graduation__c = \'' + String.escapeSingleQuotes(String.valueOf(yrV)) + '\'');
                }
                Object intakeV = f.get('intake');
                if (intakeV != null && String.isNotBlank(String.valueOf(intakeV))) {
                    conds.add('Program_Plan__r.Name = \'' + String.escapeSingleQuotes(String.valueOf(intakeV)) + '\'');
                }
            } catch (Exception fEx) { /* ignore malformed filters */ }
        }
        String whereClause = ' WHERE ' + String.join(conds, ' AND ');

        result.totalRecords = Database.countQuery('SELECT COUNT() FROM Lead' + whereClause);

        List<Lead> leads = Database.query(
            'SELECT Id, Name, FirstName, LastName, Email, Phone, Company, Title, Status, ' +
            'LeadSource, City, Country, CreatedDate, LastModifiedDate, ' +
            'Year_of_Graduation__c, Registration_Number__c, Institution_Name__c, ' +
            'Program_Plan__c, Program_Plan__r.Name, ' +
            'Existing_Account__c, Existing_Account__r.Name, Constituent_Role_Type__c ' +
            'FROM Lead' + whereClause +
            ' ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset'
        );
        Map<Id, String> matchByLead = computeLeadMatchMergeBulk(leads);
        for (Lead ld : leads) {
            result.rows.add(toAlumniRowFromLead(ld, matchByLead.get(ld.Id)));
        }
        return result;
    }

    private static Map<Id, String> computeLeadMatchMergeBulk(List<Lead> leads) {
        Map<Id, String> out = new Map<Id, String>();
        if (leads == null || leads.isEmpty()) return out;

        Set<String> emails = new Set<String>();
        Set<String> regNums = new Set<String>();
        for (Lead ld : leads) {
            if (String.isNotBlank(ld.Email)) emails.add(ld.Email);
            if (String.isNotBlank(ld.Registration_Number__c)) regNums.add(ld.Registration_Number__c);
        }

        Map<String, Set<Id>> emailToPersonIds = new Map<String, Set<Id>>();
        if (!emails.isEmpty()) {
            for (Account a : [
                SELECT Id, PersonEmail FROM Account
                WHERE IsPersonAccount = true AND PersonEmail IN :emails
            ]) {
                String key = a.PersonEmail == null ? '' : a.PersonEmail.toLowerCase();
                if (!emailToPersonIds.containsKey(key)) emailToPersonIds.put(key, new Set<Id>());
                emailToPersonIds.get(key).add(a.Id);
            }
        }
        Set<Id> allPersonIds = new Set<Id>();
        for (Set<Id> ids : emailToPersonIds.values()) allPersonIds.addAll(ids);

        Set<Id> alumniPersonIds = new Set<Id>();
        if (!allPersonIds.isEmpty()) {
            for (ConstituentRole cr : [
                SELECT PersonId FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND PersonId IN :allPersonIds
            ]) {
                if (cr.PersonId != null) alumniPersonIds.add(cr.PersonId);
            }
        }

        Set<String> regsWithAlumni = new Set<String>();
        if (!regNums.isEmpty()) {
            for (ConstituentRole cr : [
                SELECT Registration_Number__c FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Registration_Number__c IN :regNums
            ]) {
                if (String.isNotBlank(cr.Registration_Number__c)) regsWithAlumni.add(cr.Registration_Number__c);
            }
        }

        Map<String, Integer> leadEmailCount = new Map<String, Integer>();
        if (!emails.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Email e, COUNT(Id) c FROM Lead WHERE Email IN :emails GROUP BY Email
            ]) {
                leadEmailCount.put(String.valueOf(ar.get('e')), (Integer) ar.get('c'));
            }
        }

        for (Lead ld : leads) {
            String verdict = 'No Match';
            String emailKey = String.isNotBlank(ld.Email) ? ld.Email.toLowerCase() : null;

            Boolean exactByEmail = false;
            if (emailKey != null && emailToPersonIds.containsKey(emailKey)) {
                for (Id pid : emailToPersonIds.get(emailKey)) {
                    if (alumniPersonIds.contains(pid)) { exactByEmail = true; break; }
                }
            }
            Boolean exactByReg = String.isNotBlank(ld.Registration_Number__c)
                && regsWithAlumni.contains(ld.Registration_Number__c);

            if (exactByEmail || exactByReg) {
                verdict = 'Exact Match';
            } else if (emailKey != null && emailToPersonIds.containsKey(emailKey)) {
                // A Person Account exists with this email but no master alumni role yet.
                verdict = 'Possible Match';
            } else if (String.isNotBlank(ld.Email)
                    && leadEmailCount.get(ld.Email) != null
                    && leadEmailCount.get(ld.Email) > 1) {
                verdict = 'Possible Match';
            }
            out.put(ld.Id, verdict);
        }
        return out;
    }

    private static AlumniRow toAlumniRowFromLead(Lead ld, String matchMerge) {
        AlumniRow r = new AlumniRow();
        r.alumniId = ld.Id;                                 // Lead Id surfaces as the row id
        r.name = String.isNotBlank(ld.Name) ? ld.Name : ((ld.FirstName == null ? '' : ld.FirstName) + ' ' + (ld.LastName == null ? '' : ld.LastName)).trim();
        if (String.isBlank(ld.Email)) {
            r.email = null;
            r.emailWarning = 'missing';
        } else {
            r.email = ld.Email;
        }

        r.program = (ld.Program_Plan__r != null) ? ld.Program_Plan__r.Name : null;
        r.institution = ld.Institution_Name__c;
        r.batch = ld.Year_of_Graduation__c;
        r.registrationNumber = ld.Registration_Number__c;
        r.location = ld.City;
        r.country = ld.Country;
        r.company = ld.Company;
        r.role = ld.Title;
        r.masterRecordStatus = 'New Lead';
        r.portalStatus = 'Not Registered';
        r.source = ld.LeadSource;

        r.matchMerge = String.isNotBlank(matchMerge) ? matchMerge : 'No Match';

        r.existingAccountId = ld.Existing_Account__c;
        r.existingAccountName = ld.Existing_Account__r != null ? ld.Existing_Account__r.Name : null;
        r.roleType = ld.Constituent_Role_Type__c;
        r.isNewRole = (ld.Constituent_Role_Type__c == 'Secondary') || (ld.Existing_Account__c != null);
        if (r.isNewRole) {
            r.masterRecordStatus = 'New Role';
            r.matchMerge = 'Existing Alumnus';
        }

        Integer total = 8;
        Integer filled = 0;
        if (String.isNotBlank(ld.FirstName))            filled++;
        if (String.isNotBlank(ld.LastName))             filled++;
        if (String.isNotBlank(ld.Email))                filled++;
        if (String.isNotBlank(ld.Phone))                filled++;
        if (String.isNotBlank(ld.Year_of_Graduation__c)) filled++;
        if (String.isNotBlank(ld.Registration_Number__c)) filled++;
        if (String.isNotBlank(ld.Institution_Name__c))   filled++;
        if (ld.Program_Plan__c != null)                 filled++;
        r.completenessPct = Integer.valueOf((filled * 100.0) / total);

        r.lastUpdated = ld.LastModifiedDate;
        return r;
    }

    private static AlumniRow toAlumniRow(ConstituentRole cr, Account pa, PersonEmployment job) {
        AlumniRow r = new AlumniRow();
        r.alumniId = cr.Id;
        r.name = pickName(pa);
        String email = (pa != null) ? pa.PersonEmail : null;
        if (String.isBlank(email)) {
            r.email = null;
            r.emailWarning = 'missing';
        } else {
            r.email = email;
        }
        r.program = pickProgram(cr);
        r.institution = cr.Institution_Name__c;
        r.batch = cr.Graduation_Year__c;
        r.registrationNumber = cr.Registration_Number__c;
        r.location = job != null ? job.Location__c : null;
        r.country = pa != null ? pa.PersonMailingCountry : null;
        r.company = job != null ? job.Company_Name__c : null;
        r.role = job != null ? job.Designation__c : null;
        r.masterRecordStatus = mapMasterStatus(cr, pa);
        r.portalStatus = mapPortalStatus(cr);
        r.source = cr.Source_Funnel__c;
        r.matchMerge = mapMatchMerge(cr, pa);
        r.completenessPct = completenessOf(cr, pa, job);
        r.lastUpdated = cr.LastModifiedDate;
        r.referredByName = (cr.Referred_By__r != null) ? cr.Referred_By__r.Name : null;
        return r;
    }

    private static String pickName(Account pa) {
        if (pa == null) return '';
        if (String.isNotBlank(pa.Name)) return pa.Name;
        String f = pa.FirstName, l = pa.LastName;
        return ((f == null ? '' : f) + ' ' + (l == null ? '' : l)).trim();
    }

    private static String pickProgram(ConstituentRole cr) {
        if (String.isNotBlank(cr.Program_Name__c)) return cr.Program_Name__c;
        if (cr.Program_Plan__c != null && cr.Program_Plan__r != null) return cr.Program_Plan__r.Name;
        return null;
    }

    private static String mapMasterStatus(ConstituentRole cr, Account pa) {
        String email = pa != null ? pa.PersonEmail : null;
        String phone = pa != null ? pa.PersonMobilePhone : null;
        if (String.isBlank(email)
            || String.isBlank(phone)
            || String.isBlank(cr.Registration_Number__c)
            || cr.Program_Plan__c == null
            || String.isBlank(cr.Graduation_Year__c)) {
            return 'Data Missing';
        }
        String rs = cr.Registration_Status__c;
        if (rs == 'Initial Login Done' || rs == 'Registered') return 'Complete';
        if (rs == 'Verified') return 'Review Required';
        if (String.isBlank(rs) || rs == 'Unregistered') return 'Data Missing';
        return 'Valid Details';
    }

    private static String mapPortalStatus(ConstituentRole cr) {
        if (cr.Registration_Status__c == 'Initial Login Done') return 'Active';
        if (cr.Registration_Status__c == 'Registered') return 'Registered';
        return 'Unregistered';
    }

    private static String mapMatchMerge(ConstituentRole cr, Account pa) {
        if (OLD_PORTAL_SOURCES.contains(cr.Source_Funnel__c)) return 'Merged';
        String rs = cr.Registration_Status__c;
        Boolean hasPerson = (pa != null);
        if (hasPerson && VERIFIED_REG_STATUSES.contains(rs)) return 'Exact Match';
        if (hasPerson && (String.isBlank(rs) || rs == 'Unregistered')) return 'Strong Match';
        if (!hasPerson && LEAD_SOURCES.contains(cr.Source_Funnel__c)) return 'No Match Found';
        if (!hasPerson && cr.Source_Funnel__c == 'Alumni Referral') return 'No Match Found';
        return 'Review Pending';
    }

    private static Integer completenessOf(ConstituentRole cr, Account pa, PersonEmployment job) {
        Integer filled = 0, total = 6;
        if (String.isNotBlank(pickProgram(cr))) filled++;
        if (String.isNotBlank(cr.Graduation_Year__c)) filled++;
        if (String.isNotBlank(cr.Registration_Number__c)) filled++;
        if (job != null && String.isNotBlank(job.Company_Name__c)) filled++;
        if (job != null && String.isNotBlank(job.Location__c)) filled++;
        if (pa != null && String.isNotBlank(pa.PersonEmail)) filled++;
        return (Integer) Math.round(100.0 * filled / total);
    }

    private static String scoreOf(ConstituentRole cr) {
        if (cr.Registration_Status__c == 'Initial Login Done') return 'High';
        if (cr.Registration_Status__c == 'Registered') return 'Medium';
        return 'Low';
    }

    private static String initialsOf(String name) {
        if (String.isBlank(name)) return '';
        List<String> parts = name.trim().split('\\s+');
        String i = '';
        if (parts.size() >= 1 && !String.isBlank(parts[0])) i += parts[0].substring(0, 1);
        if (parts.size() >= 2 && !String.isBlank(parts[1])) i += parts[1].substring(0, 1);
        return i.toUpperCase();
    }

    /* ============================================================
       Data Issues — fix-in-place panel
       ============================================================ */

    @AuraEnabled(cacheable=true)
    public static ContactIssue getContactIssue(Id alumniId) {
        if (alumniId == null) return null;
        List<ConstituentRole> crs = [
            SELECT Id, PersonId, Source_Funnel__c, Registration_Status__c,
                   Graduation_Year__c, Registration_Number__c, Program_Name__c, Program_Plan__r.Name
            FROM ConstituentRole WHERE Id = :alumniId LIMIT 1
        ];
        if (crs.isEmpty()) return null;
        ConstituentRole cr = crs[0];
        Account pa = null;
        if (cr.PersonId != null) {
            List<Account> accts = [
                SELECT Id, Name, FirstName, LastName, PersonEmail, PersonMobilePhone, PersonMailingCountry
                FROM Account WHERE Id = :cr.PersonId LIMIT 1
            ];
            if (!accts.isEmpty()) pa = accts[0];
        }
        Map<Id, PersonEmployment> emp = fetchLatestEmployment(cr.PersonId == null ? new Set<Id>() : new Set<Id>{ cr.PersonId });
        PersonEmployment job = emp.get(cr.PersonId);

        ContactIssue ci = new ContactIssue();
        ci.alumniId = cr.Id;
        ci.name = pickName(pa);
        ci.program = pickProgram(cr);
        ci.batch = cr.Graduation_Year__c;
        ci.registrationNumber = cr.Registration_Number__c;
        ci.location = job != null ? job.Location__c : null;
        ci.country = pa != null ? pa.PersonMailingCountry : null;
        ci.email = pa != null ? pa.PersonEmail : null;
        ci.phone = pa != null ? pa.PersonMobilePhone : null;
        ci.emailMissing = String.isBlank(ci.email);
        ci.emailBounced = false;
        ci.phoneMissing = String.isBlank(ci.phone);
        Integer remaining = 0;
        if (ci.emailMissing) remaining++;
        if (ci.phoneMissing) remaining++;
        ci.issuesRemaining = remaining;
        ci.bounceNote = null;
        return ci;
    }

    @AuraEnabled
    public static SaveResult saveContactEmail(Id alumniId, String emailValue) {
        if (String.isBlank(emailValue)) {
            return new SaveResult(false, 'Email is required.', null);
        }
        if (!emailValue.contains('@') || !emailValue.contains('.')) {
            return new SaveResult(false, 'Enter a valid email address.', null);
        }
        ConstituentRole cr = [SELECT Id, PersonId FROM ConstituentRole WHERE Id = :alumniId LIMIT 1];
        if (cr.PersonId == null) {
            return new SaveResult(false, 'No linked Person Account on this constituent role.', null);
        }
        Account existing = [SELECT Id, IsPersonAccount FROM Account WHERE Id = :cr.PersonId LIMIT 1];
        if (!existing.IsPersonAccount) {
            return new SaveResult(false, 'Linked Account is a Business Account — email cannot be saved via Person fields. Open the full profile to edit.', null);
        }
        Account acc = new Account(Id = existing.Id, PersonEmail = emailValue);
        update acc;
        ContactIssue ci = getContactIssue(alumniId);
        return new SaveResult(true, 'Email saved.', ci.issuesRemaining);
    }

    @AuraEnabled
    public static SaveResult saveContactPhone(Id alumniId, String phoneValue) {
        if (String.isBlank(phoneValue)) {
            return new SaveResult(false, 'Phone is required.', null);
        }
        ConstituentRole cr = [SELECT Id, PersonId FROM ConstituentRole WHERE Id = :alumniId LIMIT 1];
        if (cr.PersonId == null) {
            return new SaveResult(false, 'No linked Person Account on this constituent role.', null);
        }
        Account existing = [SELECT Id, IsPersonAccount FROM Account WHERE Id = :cr.PersonId LIMIT 1];
        if (!existing.IsPersonAccount) {
            return new SaveResult(false, 'Linked Account is a Business Account — phone cannot be saved via Person fields. Open the full profile to edit.', null);
        }
        Account acc = new Account(Id = existing.Id, PersonMobilePhone = phoneValue);
        update acc;
        ContactIssue ci = getContactIssue(alumniId);
        return new SaveResult(true, 'Phone saved.', ci.issuesRemaining);
    }

    /* ============================================================
       Activity Timeline + Field Update History
       ============================================================ */

    @AuraEnabled(cacheable=true)
    public static List<TimelineEntry> getActivityTimeline(Id alumniId) {
        if (alumniId == null) return new List<TimelineEntry>();
        ConstituentRole cr = [
            SELECT Id, Source_Funnel__c, Registration_Status__c, PersonId,
                   CreatedDate, CreatedBy.Name, LastModifiedDate, LastModifiedBy.Name
            FROM ConstituentRole WHERE Id = :alumniId LIMIT 1
        ];
        List<TimelineEntry> out = new List<TimelineEntry>();
        String src = cr.Source_Funnel__c;
        String createSource = String.isBlank(src) ? 'Manual' : src;
        out.add(new TimelineEntry('Constituent role created via ' + createSource,
            cr.CreatedBy != null ? cr.CreatedBy.Name : 'System', cr.CreatedDate));
        if (cr.LastModifiedDate != null && cr.LastModifiedDate != cr.CreatedDate) {
            out.add(new TimelineEntry('Status: ' + (cr.Registration_Status__c == null ? '—' : cr.Registration_Status__c),
                cr.LastModifiedBy != null ? cr.LastModifiedBy.Name : 'System', cr.LastModifiedDate));
        }
        try {
            for (FeedItem fi : [
                SELECT Id, Title, Body, CreatedDate, CreatedBy.Name, Type
                FROM FeedItem WHERE ParentId = :alumniId
                ORDER BY CreatedDate DESC LIMIT 20
            ]) {
                String title = String.isBlank(fi.Title)
                    ? (String.isBlank(fi.Body) ? fi.Type : fi.Body.left(120))
                    : fi.Title;
                out.add(new TimelineEntry(title,
                    fi.CreatedBy != null ? fi.CreatedBy.Name : 'System', fi.CreatedDate));
            }
        } catch (Exception ignored) { /* feeds may be disabled */ }
        for (Integer i = 1; i < out.size(); i++) {
            TimelineEntry cur = out[i];
            Integer j = i - 1;
            while (j >= 0 && out[j].occurredAt < cur.occurredAt) {
                out[j + 1] = out[j];
                j--;
            }
            out[j + 1] = cur;
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldUpdate> getFieldUpdateHistory(Id alumniId) {
        if (alumniId == null) return new List<FieldUpdate>();
        ConstituentRole cr = [
            SELECT Id, LastModifiedDate, LastModifiedBy.Name, CreatedDate, Registration_Status__c
            FROM ConstituentRole WHERE Id = :alumniId LIMIT 1
        ];
        List<FieldUpdate> out = new List<FieldUpdate>();
        String actor = cr.LastModifiedBy != null ? cr.LastModifiedBy.Name : 'System';
        if (cr.LastModifiedDate != null && cr.LastModifiedDate != cr.CreatedDate) {
            String rs = String.isBlank(cr.Registration_Status__c) ? '—' : cr.Registration_Status__c;
            out.add(new FieldUpdate(cr.LastModifiedDate, 'Registration Status',
                'Previous snapshot', rs, 'System', actor));
        }
        return out;
    }
}