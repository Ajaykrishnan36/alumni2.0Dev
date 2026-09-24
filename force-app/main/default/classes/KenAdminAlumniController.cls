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
        'Onboarding In Progress', 'Registered', 'Initial Login Done'
    };

    private static final Integer MAX_FILTER_OPTIONS = 2000;
    private static final Integer MAX_SCAN_ROWS = 5000;
    private static final Integer MAX_MATCH_ROWS = 50000;
    private static final String PROGRAM_GROUP_FIELD = 'Program_Plan__r.LearningProgram.Name';
    private static final String INSTITUTE_GROUP_FIELD = 'Program_Plan__r.Provider.Name';

    /**
     * The Leads tab reads the Lead object, not ConstituentRole. Every query that
     * backs that tab — the row list, the tab count and the filter dropdowns —
     * must share this scope, or the dropdowns advertise counts for records the
     * table can never return.
     */
    private static final String LEAD_TAB_SCOPE =
        'Status = \'New\' AND RecordType.DeveloperName = \'Alumni_Lead\'';

    /**
     * A merge candidate is either a converted alumni identity (a ConstituentRole
     * plus its Person Account) or another lead that has not been converted yet.
     * Both are offered in the same list and either can be the surviving record.
     */
    private static final String CANDIDATE_TYPE_MASTER = 'master';
    private static final String CANDIDATE_TYPE_LEAD   = 'lead';

    /**
     * Lead statuses that take a lead out of play as a merge candidate: it has
     * already become (or been folded into) an identity of its own, or it was
     * dismissed. Kept in one place because the candidate queries and the merge
     * guards must agree on what "still pending" means.
     */
    private static final Set<String> CLOSED_LEAD_STATUSES = new Set<String>{
        'Converted', 'Merged', 'Rejected'
    };

    /**
     * Statuses that disqualify a lead from being OFFERED as a merge candidate.
     * Wider than CLOSED_LEAD_STATUSES by one value: 'Verified'. A lead sits at
     * Verified between convertLeads() approving it and KenAlumniOnboardingService
     * finishing provisioning and stamping 'Converted' — its ConstituentRole
     * usually already exists by then, so offering the lead too would list the
     * same person twice (once as the role, once as the lead) and let an admin
     * write to a record the provisioning trigger is still working on.
     *
     * Candidate eligibility is deliberately triple-guarded, since any one signal
     * can be missing on older data: this status set, Is_Converted__c, and
     * dropLeadsWithAnIdentity() (which drops anything a ConstituentRole links to).
     */
    private static final Set<String> NON_CANDIDATE_LEAD_STATUSES = new Set<String>{
        'Converted', 'Merged', 'Rejected', 'Verified'
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
        // Typed event kind so the workspace can colour each timeline node:
        // system | status | match | communication | owner | note.
        @AuraEnabled public String kind;
        @AuraEnabled public String body;
        public TimelineEntry(String t, String a, Datetime ts) { this(t, a, ts, 'system', null); }
        public TimelineEntry(String t, String a, Datetime ts, String k, String b) {
            title = t; actor = a; occurredAt = ts; kind = k; body = b;
        }
    }

    public class OwnerOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String ownerType;
        @AuraEnabled public String initials;
        public OwnerOption(String i, String n, String s, String t, String ini) {
            id = i; name = n; subtitle = s; ownerType = t; initials = ini;
        }
    }

    public class CommEntry {
        @AuraEnabled public Id       taskId;
        @AuraEnabled public String   channel;
        @AuraEnabled public String   title;
        @AuraEnabled public String   body;
        @AuraEnabled public String   status;
        @AuraEnabled public String   actor;
        @AuraEnabled public Datetime occurredAt;
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
        @AuraEnabled public String institute;
        @AuraEnabled public String yearOfEnrollment;
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
        @AuraEnabled public Id     ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String ownerType;
        @AuraEnabled public String ownerInitials;
    }

    public class MergeCandidate implements Comparable {
        @AuraEnabled public Id     alumniId; // a ConstituentRole Id for 'master' candidates, a Lead Id for 'lead' candidates
        @AuraEnabled public String name;
        @AuraEnabled public String initials;
        @AuraEnabled public String batch;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String source;
        @AuraEnabled public String candidateType; // 'master' (a converted alumni identity) or 'lead' (a still-pending lead)
        @AuraEnabled public String statusLabel;   // lead candidates only — the lead's own Status
        @AuraEnabled public String matchedOn; // every lead field this candidate matched, comma-separated
        @AuraEnabled public Integer matchCount; // how many of the lead's comparable fields matched
        @AuraEnabled public Integer matchPercent; // matchCount over the lead's non-blank comparable fields

        // Highest match first, then converted masters ahead of pending leads at
        // equal scores (a master is the stronger identity to keep), then name so
        // equal scores stay stable.
        public Integer compareTo(Object other) {
            MergeCandidate that = (MergeCandidate) other;
            Integer mine = this.matchPercent == null ? -1 : this.matchPercent;
            Integer theirs = that.matchPercent == null ? -1 : that.matchPercent;
            if (mine != theirs) return theirs - mine;
            Integer myRank = this.candidateType == CANDIDATE_TYPE_LEAD ? 1 : 0;
            Integer theirRank = that.candidateType == CANDIDATE_TYPE_LEAD ? 1 : 0;
            if (myRank != theirRank) return myRank - theirRank;
            String a = this.name == null ? '' : this.name;
            String b = that.name == null ? '' : that.name;
            return a.compareTo(b);
        }
    }

    // One comparable field in the merge-review screen. existingValue/incomingValue
    // are what the admin sees; existingRaw/incomingRaw are what actually gets
    // written back (Ids for lookups, plain text otherwise). defaultSide mirrors
    // the gap-fill rule used when the admin doesn't pick a side explicitly.
    public class MergeFieldRow {
        @AuraEnabled public String fieldKey;
        @AuraEnabled public String label;
        @AuraEnabled public String existingValue;
        @AuraEnabled public String incomingValue;
        @AuraEnabled public String existingRaw;
        @AuraEnabled public String incomingRaw;
        @AuraEnabled public String defaultSide; // 'existing' | 'incoming' | 'none'
    }

    // N-way comparison row for when 2+ candidates are selected at once.
    // existingValues/existingRaws are aligned by index to the masterRoleIds
    // list passed into getMergeFieldComparisonMulti. *Raws carry the literal
    // value mergeCandidatesIntoOne will write (Ids for lookup fields, plain
    // text otherwise) for whichever source the admin picks per field —
    // existingValues/incomingValue are display-only (e.g. a lookup's Name).
    public class MergeFieldRowMulti {
        @AuraEnabled public String fieldKey;
        @AuraEnabled public String label;
        @AuraEnabled public List<String> existingValues;
        @AuraEnabled public List<String> existingRaws;
        @AuraEnabled public String incomingValue;
        @AuraEnabled public String incomingRaw;
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
        @AuraEnabled public List<String> employmentTypes; // PersonEmployment.EmploymentType
        @AuraEnabled public List<String> genders;      // Account.PersonGenderIdentity
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
        @AuraEnabled public List<FilterOptionPair> employmentTypePairs;
        @AuraEnabled public List<FilterOptionPair> genderPairs;
        @AuraEnabled public List<FilterOptionPair> languagePairs;  // Account.Languages_Known__c (comma-separated text)
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

        Map<String, Object> binds = new Map<String, Object>();
        String whereClause = buildWhereForTab(tabKey, searchTerm, issueType, portalStatus, dashboardFilter, issuePersonIds, searchPersonIds, filtersJson, filterPersonIds, binds);

        String countQuery = 'SELECT COUNT() FROM ConstituentRole ' + whereClause;
        result.totalRecords = Database.countQueryWithBinds(countQuery, binds, AccessLevel.SYSTEM_MODE);

        String listQuery =
            'SELECT Id, RoleType, Source_Funnel__c, Registration_Status__c, Status, ' +
            '       Graduation_Year__c, Registration_Number__c, Institution_Name__c, ' +
            '       Program_Name__c, Program_Plan__c, Program_Plan__r.Name, ' +
            '       PersonId, Lead__c, Lead__r.Status, Lead__r.Is_Converted__c, ' +
            '       Referred_By__c, Referred_By__r.Name, ' +
            '       LastModifiedDate, CreatedDate ' +
            'FROM ConstituentRole ' + whereClause +
            ' ORDER BY LastModifiedDate DESC LIMIT :pageSize OFFSET :offset';

        binds.put('pageSize', pageSize);
        binds.put('offset', offset);
        List<ConstituentRole> roles = (List<ConstituentRole>) Database.queryWithBinds(listQuery, binds, AccessLevel.SYSTEM_MODE);
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
        Map<String, Object> binds = new Map<String, Object>();
        String whereClause = buildWhereForTab('issues', null, chip, null, dashboardFilter, issuePersonIds, null, null, null, binds);
        return Database.countQueryWithBinds('SELECT COUNT() FROM ConstituentRole ' + whereClause, binds, AccessLevel.SYSTEM_MODE);
    }

    private static Integer countForTab(String tabKey, String dashboardFilter) {
        // Leads tab is Lead-driven (alumni lead, Status='New') — count from Lead directly.
        if (tabKey == 'leads') {
            return Database.countQueryWithBinds(
                'SELECT COUNT() FROM Lead WHERE ' + LEAD_TAB_SCOPE,
                new Map<String, Object>(),
                AccessLevel.SYSTEM_MODE
            );
        }
        Set<Id> issuePersonIds = (tabKey == 'issues') ? resolveIssuePersonIds(null) : null;
        Map<String, Object> binds = new Map<String, Object>();
        String whereClause = buildWhereForTab(tabKey, null, null, null, dashboardFilter, issuePersonIds, null, null, null, binds);
        String q = 'SELECT COUNT() FROM ConstituentRole ' + whereClause;
        return Database.countQueryWithBinds(q, binds, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Bulk-convert selected leads. For each ConstituentRole originating from a lead
     * source, leaves Registration_Status__c at 'Unregistered' — the magic link is
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
            List<Lead> leads = [SELECT Id, Status FROM Lead WHERE Id IN :leadIds WITH USER_MODE];
            List<Lead> leadsToUpdate = new List<Lead>();
            for (Lead ld : leads) {
                if (ld.Status == 'New') {
                    ld.Status = 'Verified';
                    leadsToUpdate.add(ld);
                } else {
                    skipped++;
                }
            }
            if (!leadsToUpdate.isEmpty()) {
                if (!Schema.sObjectType.Lead.isUpdateable()) {
                    throw new KenCrudException('Lead is not updateable by the current user.');
                }
                update leadsToUpdate;
            }
            convertedCount += leadsToUpdate.size();
        }

        // ConstituentRole path (legacy from other tabs): role Registration_Status__c
        // Approval keeps the role at 'Unregistered' until the alumnus clicks the link.
        if (!roleIds.isEmpty()) {
            List<ConstituentRole> roles = [
                SELECT Id, Lead__c, Source_Funnel__c, Registration_Status__c
                FROM ConstituentRole
                WHERE Id IN :roleIds
            WITH USER_MODE
            ];
            List<ConstituentRole> rolesToUpdate = new List<ConstituentRole>();
            Set<String> alreadyAdvanced = new Set<String>{ 'Onboarding In Progress', 'Registered', 'Initial Login Done' };
            for (ConstituentRole cr : roles) {
                Boolean isLead = LEAD_SOURCES.contains(cr.Source_Funnel__c);
                if (!isLead || alreadyAdvanced.contains(cr.Registration_Status__c)) {
                    skipped++;
                    continue;
                }
                cr.Registration_Status__c = 'Unregistered';
                rolesToUpdate.add(cr);
            }
            if (!rolesToUpdate.isEmpty()) {
                if (!Schema.sObjectType.ConstituentRole.isUpdateable()) {
                    throw new KenCrudException('ConstituentRole is not updateable by the current user.');
                }
                update rolesToUpdate;
            }
            convertedCount += rolesToUpdate.size();
        }

        return new ConvertResult(convertedCount, skipped, null);
    }

    @AuraEnabled(cacheable=true)
    public static AlumniDetail getAlumniDetail(Id alumniId) {
        if (alumniId == null) return null;
        // Leads/Referrals tab rows surface a LEAD Id (see getAlumniRecords —
        // "r.alumniId = ld.Id"), so resolve the detail off the Lead itself.
        if (isLeadId(alumniId)) return leadDetailOf(alumniId);
        ConstituentRole cr = [
            SELECT Id, RoleType, Source_Funnel__c, Registration_Status__c, Status,
                   Graduation_Year__c, Registration_Number__c,
                   Program_Name__c, Program_Plan__c, Program_Plan__r.Name,
                   PersonId, Lead__c, Lead__r.Status, OwnerId,
                   CreatedDate, LastModifiedDate, Last_Login__c
            FROM ConstituentRole
            WHERE Id = :alumniId
            WITH USER_MODE
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
        d.linkedinUrl = pa != null ? (String) pa.get(KenNamespaceUtil.qualifyCustom('Linkedin_Profile_URL__c')) : null;
        d.program = pickProgram(cr);
        d.batch = cr.Graduation_Year__c;
        d.registrationNumber = cr.Registration_Number__c;
        d.company = job != null ? job.Company_Name__c : null;
        d.role = job != null ? job.Designation__c : null;
        d.industry = job != null ? job.Job_Role__c : null;
        d.location = job != null ? job.Location__c : null;
        d.approvalStatus = cr.Registration_Status__c;
        d.hasLoggedInOnce = ACTIVE_REG_STATUSES.contains(cr.Registration_Status__c);
        d.lastLogin = cr.Last_Login__c;
        d.registrationDate = cr.CreatedDate;
        d.completenessPct = completenessOf(cr, pa, job);
        d.engagementScore = scoreOf(cr);
        d.source = cr.Source_Funnel__c;
        d.interests = new List<String>();
        d.hideEmail = false;
        d.hidePhone = false;
        d.ownerId = cr.OwnerId;
        if (cr.OwnerId != null) {
            // Resolve name/type from the Id rather than the polymorphic Owner
            // relationship, which doesn't reliably hydrate Owner.Name here.
            d.ownerType = String.valueOf(cr.OwnerId).startsWith('005') ? 'User' : 'Queue';
            d.ownerName = resolveOwnerName(cr.OwnerId);
            d.ownerInitials = computeInitials(d.ownerName);
        }
        return d;
    }

    // Two-letter initials for an avatar chip; safe on null / single-word names.
    private static String computeInitials(String name) {
        if (String.isBlank(name)) return '';
        List<String> parts = name.trim().split('\\s+');
        String out = '';
        for (String p : parts) {
            if (String.isNotBlank(p)) out += p.substring(0, 1);
            if (out.length() == 2) break;
        }
        return out.toUpperCase();
    }

    // The Leads/Referrals workspace passes a Lead Id (00Q); master records pass a
    // ConstituentRole Id. This lets the shared detail/owner/comm/activity methods
    // resolve the right object.
    private static Boolean isLeadId(Id recordId) {
        return recordId != null && String.valueOf(recordId).startsWith('00Q');
    }

    private static AlumniDetail leadDetailOf(Id leadId) {
        List<Lead> lds = [
            SELECT Id, Name, Email, Phone, Company, Status, OwnerId, CreatedDate,
                   Year_of_Graduation__c, Year_of_Enrollment__c, Registration_Number__c,
                   Institution_Name__c, Program_Plan__r.Name
            FROM Lead WHERE Id = :leadId
            WITH USER_MODE
            LIMIT 1
        ];
        if (lds.isEmpty()) return null;
        Lead ld = lds[0];
        AlumniDetail d = new AlumniDetail();
        d.alumniId = ld.Id;
        d.name = ld.Name;
        d.email = ld.Email;
        d.phone = ld.Phone;
        d.linkedinUrl = null;
        d.batch = ld.Year_of_Graduation__c;
        d.yearOfEnrollment = ld.Year_of_Enrollment__c;
        d.registrationNumber = ld.Registration_Number__c;
        d.institute = ld.Institution_Name__c;
        d.program = (ld.Program_Plan__r != null) ? ld.Program_Plan__r.Name : null;
        d.approvalStatus = String.isBlank(ld.Status) ? 'Unregistered' : ld.Status;
        d.hasLoggedInOnce = false;
        d.registrationDate = ld.CreatedDate;
        d.source = ld.Company;
        d.interests = new List<String>();
        d.hideEmail = false;
        d.hidePhone = false;
        d.ownerId = ld.OwnerId;
        if (ld.OwnerId != null) {
            d.ownerType = String.valueOf(ld.OwnerId).startsWith('005') ? 'User' : 'Queue';
            d.ownerName = resolveOwnerName(ld.OwnerId);
            d.ownerInitials = computeInitials(d.ownerName);
        }
        return d;
    }

    @AuraEnabled(cacheable=true)
    public static List<MergeCandidate> getMergeCandidates(String searchTerm, String gradYear, Id leadId) {
        List<MergeCandidate> results = new List<MergeCandidate>();
        if (String.isBlank(searchTerm)) return results;

        String likeVar = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<Account> accts = [
            SELECT Id, Name, PersonEmail, PersonMobilePhone FROM Account
            WHERE IsPersonAccount = true AND (Name LIKE :likeVar OR PersonEmail LIKE :likeVar)
            WITH USER_MODE
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
            for (ConstituentRole cr : (List<ConstituentRole>) Database.queryWithBinds(
                    soql,
                    new Map<String, Object>{ 'personIds' => personIds },
                    AccessLevel.SYSTEM_MODE)) {
                roles.add(cr);
                seenRoleIds.add(cr.Id);
            }
        }
        for (ConstituentRole cr : [
            SELECT Id, PersonId, Graduation_Year__c, Registration_Number__c, Source_Funnel__c
            FROM ConstituentRole
            WHERE RoleType = 'Alumni' AND Registration_Number__c LIKE :likeVar
            WITH USER_MODE
            LIMIT 10
        ]) {
            if (!seenRoleIds.contains(cr.Id)) {
                roles.add(cr);
                seenRoleIds.add(cr.Id);
            }
        }
        // Resolve any Person Account names we didn't already fetch (reg-matched roles).
        Set<Id> needAcctIds = new Set<Id>();
        for (ConstituentRole cr : roles) {
            if (cr.PersonId != null && !acctMap.containsKey(cr.PersonId)) needAcctIds.add(cr.PersonId);
        }
        if (!needAcctIds.isEmpty()) {
            for (Account a : [SELECT Id, Name, PersonEmail, PersonMobilePhone FROM Account WHERE Id IN :needAcctIds WITH USER_MODE]) acctMap.put(a.Id, a);
        }

        Lead scoringLead = resolveScoringLead(leadId);
        String scoringName = scoringLead == null ? null : fullNameOf(scoringLead);
        Integer comparableFields = scoringLead == null ? 0 : countComparableLeadFields(scoringLead, scoringName);

        for (ConstituentRole cr : roles) {
            Account a = acctMap.get(cr.PersonId);
            MergeCandidate c = new MergeCandidate();
            c.alumniId = cr.Id;
            c.candidateType = CANDIDATE_TYPE_MASTER;
            c.name = a != null ? a.Name : '';
            c.initials = initialsOf(c.name);
            c.batch = cr.Graduation_Year__c;
            c.registrationNumber = cr.Registration_Number__c;
            c.source = cr.Source_Funnel__c;
            if (scoringLead != null) scoreCandidate(c, cr, a, scoringLead, scoringName, comparableFields);
            results.add(c);
        }
        results.addAll(searchPendingLeadCandidates(likeVar, scoringLead, scoringName, comparableFields));
        if (scoringLead != null) results.sort();
        return results;
    }

    /**
     * Free-text search over still-pending leads, so the same box that finds
     * converted masters also finds a duplicate registration that has no identity
     * yet. Matches name, email or registration number.
     */
    private static List<MergeCandidate> searchPendingLeadCandidates(String likeVar, Lead scoringLead, String scoringName, Integer comparableFields) {
        List<MergeCandidate> results = new List<MergeCandidate>();
        Set<String> ineligible = NON_CANDIDATE_LEAD_STATUSES;
        Id selfId = scoringLead != null ? scoringLead.Id : null;

        // Record-type scoping only applies when there is a lead in context to scope
        // against; a bare candidate search (no lead) has nothing to compare against.
        Id recordTypeId = scoringLead != null ? scoringLead.RecordTypeId : null;
        String soql =
            'SELECT Id, Name, FirstName, LastName, Email, Phone, Company, LeadSource, Status, ' +
            '       Year_of_Graduation__c, Registration_Number__c ' +
            'FROM Lead ' +
            'WHERE Status NOT IN :ineligible AND Is_Converted__c != true ' +
            '  AND (Name LIKE :likeVar OR Email LIKE :likeVar OR Registration_Number__c LIKE :likeVar)';
        if (scoringLead != null) soql += ' AND RecordTypeId = :recordTypeId';
        soql += ' LIMIT 20';

        Map<String, Object> binds = new Map<String, Object>{
            'ineligible' => ineligible,
            'likeVar' => likeVar,
            'recordTypeId' => recordTypeId
        };
        Map<Id, Lead> byId = new Map<Id, Lead>();
        for (Lead cand : (List<Lead>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            if (cand.Id != selfId) byId.put(cand.Id, cand);
        }
        dropLeadsWithAnIdentity(byId);

        for (Lead cand : byId.values()) {
            results.add(toLeadCandidate(cand, scoringLead, scoringName, comparableFields));
        }
        return results;
    }

    /**
     * Auto-suggested merge candidates for a lead/referral — computed from the
     * lead's OWN captured fields (registration number, full name, email, phone)
     * instead of requiring the admin to type a search term first. This drives
     * the suggestions list shown as soon as the merge screen opens;
     * getMergeCandidates above still powers the free-text search box for
     * anything these don't catch.
     */
    @AuraEnabled(cacheable=true)
    public static List<MergeCandidate> getMergeSuggestions(Id leadId) {
        List<MergeCandidate> results = new List<MergeCandidate>();
        if (leadId == null) return results;

        List<Lead> leads = [
            SELECT Id, RecordTypeId, FirstName, LastName, Email, Phone, Registration_Number__c
            FROM Lead WHERE Id = :leadId
            WITH USER_MODE
            LIMIT 1
        ];
        if (leads.isEmpty()) return results;
        Lead ld = leads[0];
        String fullName = fullNameOf(ld);

        Map<Id, ConstituentRole> roleById = new Map<Id, ConstituentRole>();

        // 1) Registration number — the most precise identifier captured on self-registration.
        if (String.isNotBlank(ld.Registration_Number__c)) {
            for (ConstituentRole cr : [
                SELECT Id, PersonId, Graduation_Year__c, Registration_Number__c, Source_Funnel__c
                FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Registration_Number__c = :ld.Registration_Number__c
                WITH USER_MODE
                LIMIT 10
            ]) {
                roleById.put(cr.Id, cr);
            }
        }

        // 2) Name / email / phone — resolve matching Person Accounts first, then their roles.
        Set<Id> matchedPersonIds = new Set<Id>();
        if (String.isNotBlank(fullName)) {
            String likeName = '%' + String.escapeSingleQuotes(fullName) + '%';
            for (Account a : [SELECT Id FROM Account WHERE IsPersonAccount = true AND Name LIKE :likeName WITH USER_MODE LIMIT 20]) {
                matchedPersonIds.add(a.Id);
            }
        }
        if (String.isNotBlank(ld.Email)) {
            for (Account a : [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonEmail = :ld.Email WITH USER_MODE LIMIT 20]) {
                matchedPersonIds.add(a.Id);
            }
        }
        if (String.isNotBlank(ld.Phone)) {
            for (Account a : [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonMobilePhone = :ld.Phone WITH USER_MODE LIMIT 20]) {
                matchedPersonIds.add(a.Id);
            }
        }
        if (!matchedPersonIds.isEmpty()) {
            for (ConstituentRole cr : [
                SELECT Id, PersonId, Graduation_Year__c, Registration_Number__c, Source_Funnel__c
                FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND PersonId IN :matchedPersonIds
                WITH USER_MODE
                LIMIT 30
            ]) {
                if (!roleById.containsKey(cr.Id)) roleById.put(cr.Id, cr);
            }
        }
        Set<Id> personIds = new Set<Id>();
        for (ConstituentRole cr : roleById.values()) if (cr.PersonId != null) personIds.add(cr.PersonId);
        Map<Id, Account> acctMap = new Map<Id, Account>();
        if (!personIds.isEmpty()) {
            for (Account a : [SELECT Id, Name, PersonEmail, PersonMobilePhone FROM Account WHERE Id IN :personIds WITH USER_MODE]) acctMap.put(a.Id, a);
        }

        Integer comparableFields = countComparableLeadFields(ld, fullName);
        for (ConstituentRole cr : roleById.values()) {
            Account a = acctMap.get(cr.PersonId);
            MergeCandidate c = new MergeCandidate();
            c.alumniId = cr.Id;
            c.candidateType = CANDIDATE_TYPE_MASTER;
            c.name = a != null ? a.Name : '';
            c.initials = initialsOf(c.name);
            c.batch = cr.Graduation_Year__c;
            c.registrationNumber = cr.Registration_Number__c;
            c.source = cr.Source_Funnel__c;
            scoreCandidate(c, cr, a, ld, fullName, comparableFields);
            results.add(c);
        }
        results.addAll(pendingLeadSuggestions(ld, fullName, comparableFields));
        results.sort();
        return results;
    }

    /**
     * Still-pending leads that look like the same person as the lead being
     * reviewed — the duplicate-registration case, where neither record has an
     * identity yet and there is no master to merge into. Matched on the same
     * four fields as the master suggestions so both halves of the list are
     * scored comparably.
     */
    private static List<MergeCandidate> pendingLeadSuggestions(Lead ld, String fullName, Integer comparableFields) {
        List<MergeCandidate> results = new List<MergeCandidate>();
        Set<String> ineligible = NON_CANDIDATE_LEAD_STATUSES;
        Id selfId = ld.Id;
        // Scoped to the incoming lead's own record type. Several orgs share the
        // Lead object with Admissions, and an admissions enquiry is not an alumni
        // duplicate — offering one as a merge candidate would cross modules.
        Id recordTypeId = ld.RecordTypeId;
        Map<Id, Lead> byId = new Map<Id, Lead>();

        if (String.isNotBlank(ld.Registration_Number__c)) {
            for (Lead cand : [
                SELECT Id, Name, FirstName, LastName, Email, Phone, Company, LeadSource, Status,
                       Year_of_Graduation__c, Registration_Number__c
                FROM Lead
                WHERE Registration_Number__c = :ld.Registration_Number__c
                  AND Id != :selfId AND RecordTypeId = :recordTypeId
                  AND Status NOT IN :ineligible AND Is_Converted__c != true
                WITH USER_MODE
                LIMIT 10
            ]) {
                byId.put(cand.Id, cand);
            }
        }
        if (String.isNotBlank(ld.Email)) {
            for (Lead cand : [
                SELECT Id, Name, FirstName, LastName, Email, Phone, Company, LeadSource, Status,
                       Year_of_Graduation__c, Registration_Number__c
                FROM Lead
                WHERE Email = :ld.Email AND Id != :selfId AND RecordTypeId = :recordTypeId
                  AND Status NOT IN :ineligible AND Is_Converted__c != true
                WITH USER_MODE
                LIMIT 10
            ]) {
                byId.put(cand.Id, cand);
            }
        }
        if (String.isNotBlank(ld.Phone)) {
            for (Lead cand : [
                SELECT Id, Name, FirstName, LastName, Email, Phone, Company, LeadSource, Status,
                       Year_of_Graduation__c, Registration_Number__c
                FROM Lead
                WHERE Phone = :ld.Phone AND Id != :selfId AND RecordTypeId = :recordTypeId
                  AND Status NOT IN :ineligible AND Is_Converted__c != true
                WITH USER_MODE
                LIMIT 10
            ]) {
                byId.put(cand.Id, cand);
            }
        }
        if (String.isNotBlank(fullName)) {
            String likeName = '%' + String.escapeSingleQuotes(fullName) + '%';
            for (Lead cand : [
                SELECT Id, Name, FirstName, LastName, Email, Phone, Company, LeadSource, Status,
                       Year_of_Graduation__c, Registration_Number__c
                FROM Lead
                WHERE Name LIKE :likeName AND Id != :selfId AND RecordTypeId = :recordTypeId
                  AND Status NOT IN :ineligible AND Is_Converted__c != true
                WITH USER_MODE
                LIMIT 10
            ]) {
                byId.put(cand.Id, cand);
            }
        }
        dropLeadsWithAnIdentity(byId);

        for (Lead cand : byId.values()) {
            results.add(toLeadCandidate(cand, ld, fullName, comparableFields));
        }
        return results;
    }

    /**
     * Whether a lead is still an eligible merge partner — the same three-signal
     * test the candidate queries apply, for use once a record is already in hand.
     */
    private static Boolean isLeadStillPending(Lead ld) {
        return ld != null
            && !NON_CANDIDATE_LEAD_STATUSES.contains(ld.Status)
            && ld.Is_Converted__c != true;
    }

    /**
     * Removes leads that already have a ConstituentRole. Those are reachable as
     * master candidates through that role, so listing the lead as well would show
     * the same person twice; and merging into the lead instead would leave the
     * role holding stale values. This is the guard that catches a lead whose
     * Status never advanced past 'Verified' even though provisioning finished.
     */
    private static void dropLeadsWithAnIdentity(Map<Id, Lead> byId) {
        if (byId.isEmpty()) return;
        Set<Id> candidateIds = byId.keySet();
        for (ConstituentRole cr : [
            SELECT Lead__c FROM ConstituentRole WHERE Lead__c IN :candidateIds
        WITH USER_MODE
        ]) {
            byId.remove(cr.Lead__c);
        }
    }

    private static MergeCandidate toLeadCandidate(Lead cand, Lead scoringLead, String scoringName, Integer comparableFields) {
        MergeCandidate c = new MergeCandidate();
        c.alumniId = cand.Id;
        c.candidateType = CANDIDATE_TYPE_LEAD;
        c.name = cand.Name != null ? cand.Name : '';
        c.initials = initialsOf(c.name);
        c.batch = cand.Year_of_Graduation__c;
        c.registrationNumber = cand.Registration_Number__c;
        c.source = String.isNotBlank(cand.LeadSource) ? cand.LeadSource : cand.Company;
        c.statusLabel = cand.Status;
        if (scoringLead != null) scoreLeadCandidate(c, cand, scoringLead, scoringName, comparableFields);
        return c;
    }

    /**
     * The lead-candidate counterpart to scoreCandidate: same four comparable
     * fields, read off the candidate Lead instead of a role and Person Account,
     * so master and lead candidates sort against each other meaningfully.
     */
    private static void scoreLeadCandidate(MergeCandidate c, Lead cand, Lead ld, String fullName, Integer comparableFields) {
        List<String> matched = new List<String>();
        if (String.isNotBlank(ld.Registration_Number__c) && cand.Registration_Number__c != null
            && cand.Registration_Number__c.equalsIgnoreCase(ld.Registration_Number__c)) matched.add('Registration number');
        if (String.isNotBlank(fullName) && cand.Name != null && cand.Name.containsIgnoreCase(fullName)) matched.add('Name');
        if (String.isNotBlank(ld.Email) && cand.Email != null && cand.Email.equalsIgnoreCase(ld.Email)) matched.add('Email');
        if (String.isNotBlank(ld.Phone) && cand.Phone == ld.Phone) matched.add('Phone');
        c.matchCount = matched.size();
        c.matchPercent = comparableFields > 0 ? Math.round((matched.size() * 100.0) / comparableFields) : 0;
        c.matchedOn = matched.isEmpty() ? null : String.join(matched, ', ');
    }

    private static String fullNameOf(Lead ld) {
        return ((String.isNotBlank(ld.FirstName) ? ld.FirstName : '') + ' ' +
                (String.isNotBlank(ld.LastName) ? ld.LastName : '')).trim();
    }

    /**
     * Fetches the lead whose captured fields the merge candidates get scored
     * against; null when no lead context was passed (plain candidate search).
     */
    private static Lead resolveScoringLead(Id leadId) {
        if (leadId == null || !String.valueOf(leadId).startsWith('00Q')) return null;
        List<Lead> leads = [
            SELECT Id, RecordTypeId, FirstName, LastName, Email, Phone, Registration_Number__c
            FROM Lead WHERE Id = :leadId
            WITH USER_MODE
            LIMIT 1
        ];
        return leads.isEmpty() ? null : leads[0];
    }

    /**
     * The lead-side fields a candidate can be compared against: registration
     * number, full name, email, phone. Only fields the lead actually captured
     * count toward the match-percent denominator.
     */
    private static Integer countComparableLeadFields(Lead ld, String fullName) {
        Integer n = 0;
        if (String.isNotBlank(ld.Registration_Number__c)) n++;
        if (String.isNotBlank(fullName)) n++;
        if (String.isNotBlank(ld.Email)) n++;
        if (String.isNotBlank(ld.Phone)) n++;
        return n;
    }

    /**
     * Stamps matchedOn / matchCount / matchPercent on one candidate by comparing
     * the lead's captured fields against the candidate role and its Person Account.
     */
    private static void scoreCandidate(MergeCandidate c, ConstituentRole cr, Account a, Lead ld, String fullName, Integer comparableFields) {
        List<String> matched = new List<String>();
        if (String.isNotBlank(ld.Registration_Number__c) && cr.Registration_Number__c != null
            && cr.Registration_Number__c.equalsIgnoreCase(ld.Registration_Number__c)) matched.add('Registration number');
        if (String.isNotBlank(fullName) && a != null && a.Name != null && a.Name.containsIgnoreCase(fullName)) matched.add('Name');
        if (String.isNotBlank(ld.Email) && a != null && a.PersonEmail != null && a.PersonEmail.equalsIgnoreCase(ld.Email)) matched.add('Email');
        if (String.isNotBlank(ld.Phone) && a != null && a.PersonMobilePhone == ld.Phone) matched.add('Phone');
        c.matchCount = matched.size();
        c.matchPercent = comparableFields > 0 ? Math.round((matched.size() * 100.0) / comparableFields) : 0;
        c.matchedOn = matched.isEmpty() ? null : String.join(matched, ', ');
    }

    @AuraEnabled
    public static SaveResult rejectLead(Id leadId) {
        if (leadId == null || !String.valueOf(leadId).startsWith('00Q')) {
            return new SaveResult(false, 'Reject is only available for lead records.', null);
        }
        try {
            Lead ld = [SELECT Id, Status FROM Lead WHERE Id = :leadId WITH USER_MODE LIMIT 1];
            ld.Status = 'Rejected';
            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new KenCrudException('Lead is not updateable by the current user.');
            }
            update ld;
            return new SaveResult(true, 'Lead rejected.', null);
        } catch (Exception e) {
            return new SaveResult(false, e.getMessage(), null);
        }
    }

    /**
     * Builds the master-vs-lead comparison shown in the merge review screen.
     * existingRaw/incomingRaw are the literal values mergeLeadIntoMaster will
     * write back for whichever side the admin (or the default gap-fill rule)
     * picks — Ids for lookup fields, plain text otherwise.
     */
    // What's comparable in the merge review screen. Most of it is discovered
    // automatically (see autoDiscoveredFields below) — this list only covers the
    // handful of fields that CAN'T be discovered because they don't share an API
    // name across objects, or live on the master's Person Account rather than
    // the ConstituentRole. Email isn't here either — it writes to TWO master
    // fields (ConstituentRole.Email__c and Account.PersonEmail), which doesn't
    // fit this table's one-field-in/one-field-out shape, so it's handled
    // separately in both methods below.
    private class FieldMapping {
        String key;
        String label;
        String leadField;
        String masterField;
        Boolean onAccount; // true => masterField lives on the master's Person Account, not the ConstituentRole
        Boolean isLookup;  // true => resolve/display via the __r relationship, write back as an Id
        FieldMapping(String key, String label, String leadField, String masterField, Boolean onAccount, Boolean isLookup) {
            this.key = key; this.label = label;
            this.leadField = KenNamespaceUtil.qualifyCustom(leadField);
            this.masterField = KenNamespaceUtil.qualifyCustom(masterField);
            this.onAccount = onAccount; this.isLookup = isLookup;
        }
    }

    private static final List<FieldMapping> MERGE_FIELD_EXCEPTIONS = new List<FieldMapping>{
        new FieldMapping('firstName', 'First name', 'FirstName', 'FirstName', true, false),
        new FieldMapping('lastName', 'Last name', 'LastName', 'LastName', true, false),
        new FieldMapping('phone', 'Phone', 'Phone', 'PersonMobilePhone', true, false),
        new FieldMapping('gradYear', 'Graduation year', 'Year_of_Graduation__c', 'Graduation_Year__c', false, false)
    };

    // True auto-discovery: any custom field that exists with the SAME API name
    // on both Lead and ConstituentRole is automatically comparable — no entry
    // needed above. Today that's Registration_Number__c, Program_Plan__c, and
    // Referred_By__c; add a same-named __c field to both objects in Setup
    // tomorrow (e.g. a new "Batch_Code__c") and it appears here with zero code
    // changes. Formula fields (e.g. Institution_Name__c, which mirrors
    // Program_Plan__r.Provider.Name) are skipped since they can't be written to.
    private static List<FieldMapping> autoDiscoveredFields() {
        List<FieldMapping> result = new List<FieldMapping>();
        Map<String, Schema.SObjectField> leadFields = Schema.SObjectType.Lead.fields.getMap();
        Map<String, Schema.SObjectField> crFields = Schema.SObjectType.ConstituentRole.fields.getMap();
        for (String apiName : leadFields.keySet()) {
            if (!apiName.endsWith('__c') || !crFields.containsKey(apiName)) continue;
            Schema.DescribeFieldResult crDescribe = crFields.get(apiName).getDescribe();
            Boolean writeable = crDescribe.isUpdateable() ||
                (crDescribe.isCustom() && !crDescribe.isCalculated() && !crDescribe.isAutoNumber());
            if (!writeable) continue; // e.g. Institution_Name__c is a formula
            String properApiName = crDescribe.getName(); // getMap() keys are lowercased
            Boolean isLookup = crDescribe.getType() == Schema.DisplayType.REFERENCE;
            result.add(new FieldMapping(properApiName, crDescribe.getLabel(), properApiName, properApiName, false, isLookup));
        }
        return result;
    }

    private static List<FieldMapping> allMergeFields() {
        List<FieldMapping> all = new List<FieldMapping>(MERGE_FIELD_EXCEPTIONS);
        all.addAll(autoDiscoveredFields());
        return all;
    }

    // Custom lookups in this org follow the standard <FieldName>__c -> <FieldName>__r
    // convention (already relied on elsewhere in this class for Program_Plan__r /
    // Referred_By__r) — computing it means field mappings only need to name the __c field.
    private static String relationshipName(String lookupField) {
        return lookupField.endsWith('__c') ? lookupField.substring(0, lookupField.length() - 3) + '__r' : lookupField;
    }
    private static String valueOf(Object o) {
        return o != null ? String.valueOf(o) : null;
    }
    // Coerces null to '' — used specifically for List<String> elements headed
    // into an @AuraEnabled response, where a real null in the middle of the
    // list is a risk, not a plain missing value.
    private static String nonNull(String s) {
        return s != null ? s : '';
    }

    /**
     * masterRoleId accepts either kind of candidate: a ConstituentRole Id for a
     * converted master, or a Lead Id for a still-pending lead. The "existing"
     * column is whichever one was picked; the "incoming" column is always the
     * lead being reviewed.
     */
    @AuraEnabled(cacheable=true)
    public static List<MergeFieldRow> getMergeFieldComparison(Id leadId, Id masterRoleId) {
        List<MergeFieldRow> rows = new List<MergeFieldRow>();
        if (leadId == null || masterRoleId == null || leadId == masterRoleId) return rows;

        List<FieldMapping> fields = allMergeFields();
        List<Set<String>> queryFields = mergeQueryFields(fields, true);

        List<Lead> leads = Database.query(
            'SELECT ' + String.join(new List<String>(queryFields[0]), ', ') + ' FROM Lead WHERE Id = :leadId LIMIT 1'
        );
        if (leads.isEmpty()) return rows;
        SObject ld = leads[0];

        MergeTarget target = loadMergeTargets(
            new List<Id>{ masterRoleId }, queryFields[1], queryFields[2], queryFields[0]
        ).get(masterRoleId);
        if (target == null || !target.exists()) return rows;

        String masterEmail = target.emailValue();
        String leadEmail = valueOf(ld.get('Email'));
        rows.add(fieldRow('email', 'Email', masterEmail, leadEmail, masterEmail, leadEmail));

        for (FieldMapping m : fields) {
            rows.add(fieldRow(
                m.key, m.label,
                target.displayFor(m), incomingDisplayFor(ld, m),
                target.rawFor(m), valueOf(ld.get(m.leadField))
            ));
        }
        return rows;
    }

    /**
     * Read-only comparison across 2+ candidates at once, for when the admin
     * checks multiple suggestions before deciding how to reconcile them. The
     * list may mix converted masters (ConstituentRole Ids) and still-pending
     * leads (Lead Ids) freely; mergeCandidatesIntoOne then writes the resolved
     * values onto whichever ONE of them the admin keeps.
     */
    @AuraEnabled(cacheable=true)
    public static List<MergeFieldRowMulti> getMergeFieldComparisonMulti(Id leadId, List<Id> masterRoleIds) {
        List<MergeFieldRowMulti> rows = new List<MergeFieldRowMulti>();
        if (leadId == null || masterRoleIds == null || masterRoleIds.isEmpty()) return rows;

        List<FieldMapping> fieldList = allMergeFields();
        List<Set<String>> queryFields = mergeQueryFields(fieldList, true);

        List<Lead> leads = Database.query(
            'SELECT ' + String.join(new List<String>(queryFields[0]), ', ') + ' FROM Lead WHERE Id = :leadId LIMIT 1'
        );
        if (leads.isEmpty()) return rows;
        SObject ld = leads[0];

        Map<Id, MergeTarget> targetById = loadMergeTargets(
            masterRoleIds, queryFields[1], queryFields[2], queryFields[0]
        );

        // Keep the admin's selection order, not query order.
        List<MergeTarget> orderedTargets = new List<MergeTarget>();
        for (Id mId : masterRoleIds) {
            if (mId == leadId) continue;
            MergeTarget t = targetById.get(mId);
            if (t != null && t.exists()) orderedTargets.add(t);
        }
        if (orderedTargets.isEmpty()) return rows;

        List<String> emailValues = new List<String>();
        for (MergeTarget t : orderedTargets) emailValues.add(nonNull(t.emailValue()));
        String incomingEmail = nonNull(valueOf(ld.get('Email')));
        // Email is plain text either way, so display value and raw value are
        // the same string — unlike lookup fields below, where they differ.
        rows.add(multiRow('email', 'Email', emailValues, emailValues, incomingEmail, incomingEmail));

        for (FieldMapping m : fieldList) {
            // Every entry here MUST be a real (possibly empty) string, never a
            // literal null — a null element inside an @AuraEnabled List<String>
            // risks being dropped during JSON serialization to the LWC, which
            // silently shortens the array and throws off every column after it
            // for that one row. nonNull() is the guard against that.
            List<String> values = new List<String>();
            List<String> rawValues = new List<String>();
            for (MergeTarget t : orderedTargets) {
                rawValues.add(nonNull(t.rawFor(m)));
                values.add(nonNull(t.displayFor(m)));
            }
            rows.add(multiRow(
                m.key, m.label, values, rawValues,
                nonNull(incomingDisplayFor(ld, m)), nonNull(valueOf(ld.get(m.leadField)))
            ));
        }
        return rows;
    }

    private static MergeFieldRowMulti multiRow(String key, String label, List<String> existingValues, List<String> existingRaws, String incomingValue, String incomingRaw) {
        MergeFieldRowMulti r = new MergeFieldRowMulti();
        r.fieldKey = key;
        r.label = label;
        r.existingValues = existingValues;
        r.existingRaws = existingRaws;
        r.incomingValue = incomingValue;
        r.incomingRaw = incomingRaw;
        return r;
    }

    private static MergeFieldRow fieldRow(String key, String label, String existingDisplay, String incomingDisplay, String existingRaw, String incomingRaw) {
        MergeFieldRow r = new MergeFieldRow();
        r.fieldKey = key;
        r.label = label;
        r.existingValue = existingDisplay;
        r.incomingValue = incomingDisplay;
        r.existingRaw = existingRaw;
        r.incomingRaw = incomingRaw;
        // Mirrors the never-overwrite gap-fill rule: existing wins whenever it has a value.
        r.defaultSide = String.isNotBlank(existingRaw) ? 'existing' : (String.isNotBlank(incomingRaw) ? 'incoming' : 'none');
        return r;
    }

    // choice is an explicit 'existing'/'incoming' pick from the merge review screen,
    // or null when the admin didn't touch that field — in which case we fall back to
    // the original never-overwrite gap-fill rule.
    private static String applySide(String choice, String existingRaw, String incomingRaw) {
        if (choice == 'existing') return existingRaw;
        if (choice == 'incoming') return incomingRaw;
        return String.isNotBlank(existingRaw) ? existingRaw : incomingRaw;
    }

    private static Set<String> writeableLeadFieldCache;

    /**
     * Whether a Lead field can actually be written. allMergeFields() only vets
     * the ConstituentRole side of each mapping, so a field that is updateable
     * there but a formula on Lead would blow up a lead-to-lead write at update
     * time — this is the guard for that case.
     *
     * isUpdateable() alone is the wrong test: it is field-level-security aware,
     * and a custom field deployed in the same release carries no FLS for anyone
     * until a profile or permission set grants it. That made a freshly deployed
     * gap-fill field (Registration_Number__c) silently skip every write while the
     * merge still reported success. Apex runs in system mode here, so a custom,
     * non-formula field is always writeable regardless of FLS; standard fields
     * keep the FLS-aware answer, which is what stops writes to read-only system
     * fields such as IsConverted.
     */
    private static Boolean isWriteableLeadField(String apiName) {
        if (writeableLeadFieldCache == null) {
            writeableLeadFieldCache = new Set<String>();
            for (Schema.SObjectField f : Schema.SObjectType.Lead.fields.getMap().values()) {
                Schema.DescribeFieldResult d = f.getDescribe();
                Boolean writeable = d.isUpdateable() ||
                    (d.isCustom() && !d.isCalculated() && !d.isAutoNumber());
                if (writeable) writeableLeadFieldCache.add(d.getName().toLowerCase());
            }
        }
        return String.isNotBlank(apiName) && writeableLeadFieldCache.contains(apiName.toLowerCase());
    }

    /**
     * Read/write adapter over the two kinds of record a lead can be merged into:
     * a converted master identity (a ConstituentRole plus its Person Account) or
     * another lead that is still pending. Every comparison and write path talks
     * to the target through this, so a lead-to-lead merge reuses the same field
     * mapping, the same gap-fill rule and the same write-back logic as a
     * lead-to-master merge instead of forking its own copy.
     */
    private with sharing class MergeTarget {
        Id targetId;
        Boolean isLead = false;
        String displayName;
        Lead leadRec;
        ConstituentRole roleRec;
        Account personRec;
        Boolean leadDirty = false;
        Boolean roleDirty = false;
        Boolean personDirty = false;

        Boolean exists() {
            return isLead ? leadRec != null : roleRec != null;
        }

        /** The mapping's field name on whichever object this target actually is. */
        String apiNameFor(FieldMapping m) {
            return isLead ? m.leadField : m.masterField;
        }

        /** The record holding that field, or null when this target has no such record. */
        SObject holderFor(FieldMapping m) {
            if (isLead) return (SObject) leadRec;
            return m.onAccount ? (SObject) personRec : (SObject) roleRec;
        }

        String rawFor(FieldMapping m) {
            SObject holder = holderFor(m);
            return holder == null ? null : valueOf(holder.get(apiNameFor(m)));
        }

        String displayFor(FieldMapping m) {
            SObject holder = holderFor(m);
            if (holder == null) return null;
            String apiName = apiNameFor(m);
            if (!m.isLookup) return valueOf(holder.get(apiName));
            SObject related = holder.getSObject(relationshipName(apiName));
            return related != null ? (String) related.get('Name') : null;
        }

        void write(FieldMapping m, String value) {
            SObject holder = holderFor(m);
            if (holder == null) return;
            String apiName = apiNameFor(m);
            if (isLead && !isWriteableLeadField(apiName)) return;
            if (valueOf(holder.get(apiName)) == value) return;
            holder.put(apiName, m.isLookup ? (Object) (String.isNotBlank(value) ? (Id) value : null) : (Object) value);
            if (isLead) leadDirty = true;
            else if (m.onAccount) personDirty = true;
            else roleDirty = true;
        }

        /**
         * Email is the one value that lives in two places on a master target
         * (ConstituentRole.Email__c and Account.PersonEmail), which is why it
         * can't be expressed as a FieldMapping. On a lead target it is simply
         * Lead.Email.
         */
        String emailValue() {
            if (isLead) return leadRec == null ? null : leadRec.Email;
            String existing = roleRec != null ? roleRec.Email__c : null;
            if (String.isBlank(existing) && personRec != null) existing = (String) personRec.get('PersonEmail');
            return existing;
        }

        void writeEmail(String value) {
            if (isLead) {
                if (leadRec != null && leadRec.Email != value) { leadRec.Email = value; leadDirty = true; }
                return;
            }
            if (roleRec != null && roleRec.Email__c != value) { roleRec.Email__c = value; roleDirty = true; }
            if (personRec != null && (String) personRec.get('PersonEmail') != value) {
                personRec.put('PersonEmail', value);
                personDirty = true;
            }
        }

        /** Links a master target's role back to the lead being merged, if it isn't linked yet. */
        void linkLead(Id leadId) {
            if (isLead || roleRec == null) return;
            if (roleRec.Lead__c == null) { roleRec.Lead__c = leadId; roleDirty = true; }
        }

        /**
         * The Lead record that represents this target once the merge lands —
         * what a superseded lead's Master_Lead__c points at. For a master target
         * that is the lead now linked to its role; for a lead target it is the
         * target lead itself.
         */
        Id survivingLeadId() {
            if (isLead) return leadRec != null ? leadRec.Id : null;
            return roleRec != null ? roleRec.Lead__c : null;
        }

        /** Flushes whatever was actually changed, then clears the dirty flags so a second call is a no-op. */
        void saveChanges() {
            if (isLead) {
                if (leadDirty && leadRec != null) {
                    if (!Schema.sObjectType.Lead.isUpdateable()) {
                        throw new KenCrudException('Lead is not updateable by the current user.');
                    }
                    update leadRec; leadDirty = false;
                }
                return;
            }
            if (roleDirty && roleRec != null) {
                if (!Schema.sObjectType.ConstituentRole.isUpdateable()) {
                    throw new KenCrudException('ConstituentRole is not updateable by the current user.');
                }
                update roleRec; roleDirty = false;
            }
            if (personDirty && personRec != null) {
                if (!Schema.sObjectType.Account.isUpdateable()) {
                    throw new KenCrudException('Account is not updateable by the current user.');
                }
                update personRec; personDirty = false;
            }
        }
    }

    /**
     * Loads merge targets by Id, choosing the object per Id from its own key
     * prefix: a Lead Id yields a lead target, anything else a master target.
     * Callers keep their own ordering — this returns a lookup, not a list.
     *
     * crFields/acctFields/leadFields are the field sets the caller already
     * built from allMergeFields(); the identity and bookkeeping fields every
     * merge path needs are added here so callers can't forget one.
     */
    private static Map<Id, MergeTarget> loadMergeTargets(List<Id> targetIds, Set<String> crFields, Set<String> acctFields, Set<String> leadFields) {
        Map<Id, MergeTarget> byId = new Map<Id, MergeTarget>();
        if (targetIds == null || targetIds.isEmpty()) return byId;

        Set<Id> leadIds = new Set<Id>();
        Set<Id> roleIds = new Set<Id>();
        for (Id targetId : targetIds) {
            if (targetId == null) continue;
            if (isLeadId(targetId)) leadIds.add(targetId); else roleIds.add(targetId);
        }

        if (!leadIds.isEmpty()) {
            Set<String> fields = new Set<String>(leadFields);
            fields.addAll(new Set<String>{ 'Id', 'Name', 'Email', 'Status', 'Is_Converted__c', 'Master_Lead__c' });
            for (Lead row : Database.query(
                'SELECT ' + String.join(new List<String>(fields), ', ') + ' FROM Lead WHERE Id IN :leadIds'
            )) {
                MergeTarget t = new MergeTarget();
                t.targetId = row.Id;
                t.isLead = true;
                t.leadRec = row;
                t.displayName = row.Name;
                byId.put(row.Id, t);
            }
        }

        if (!roleIds.isEmpty()) {
            Set<String> fields = new Set<String>(crFields);
            fields.addAll(new Set<String>{ 'Id', 'PersonId', 'Lead__c', 'Email__c' });
            Map<Id, List<MergeTarget>> byPersonId = new Map<Id, List<MergeTarget>>();
            for (ConstituentRole row : Database.query(
                'SELECT ' + String.join(new List<String>(fields), ', ') +
                ' FROM ConstituentRole WHERE Id IN :roleIds AND RoleType = \'Alumni\''
            )) {
                MergeTarget t = new MergeTarget();
                t.targetId = row.Id;
                t.roleRec = row;
                byId.put(row.Id, t);
                if (row.PersonId == null) continue;
                if (!byPersonId.containsKey(row.PersonId)) byPersonId.put(row.PersonId, new List<MergeTarget>());
                byPersonId.get(row.PersonId).add(t);
            }
            if (!byPersonId.isEmpty()) {
                Set<String> paFields = new Set<String>(acctFields);
                paFields.addAll(new Set<String>{ 'Id', 'Name' });
                Set<Id> personIds = byPersonId.keySet();
                for (Account row : Database.query(
                    'SELECT ' + String.join(new List<String>(paFields), ', ') + ' FROM Account WHERE Id IN :personIds'
                )) {
                    for (MergeTarget t : byPersonId.get(row.Id)) {
                        t.personRec = row;
                        t.displayName = (String) row.get('Name');
                    }
                }
            }
        }
        return byId;
    }

    /**
     * The field sets a merge path needs to query, derived from the mappings.
     * Index 0 is the Lead set, 1 the ConstituentRole set, 2 the Account set.
     * withRelationships adds the `__r.Name` paths the comparison screens need
     * to show a lookup's label; the write paths don't need them.
     */
    private static List<Set<String>> mergeQueryFields(List<FieldMapping> fields, Boolean withRelationships) {
        Set<String> leadFields = new Set<String>{ 'Id', 'Status', 'Email' };
        Set<String> crFields = new Set<String>{ 'Id', 'PersonId', 'Lead__c', 'Email__c' };
        Set<String> acctFields = new Set<String>{ 'Id', 'PersonEmail' };
        for (FieldMapping m : fields) {
            leadFields.add(m.leadField);
            if (withRelationships && m.isLookup) leadFields.add(relationshipName(m.leadField) + '.Name');
            if (m.onAccount) {
                acctFields.add(m.masterField);
            } else {
                crFields.add(m.masterField);
                if (withRelationships && m.isLookup) crFields.add(relationshipName(m.masterField) + '.Name');
            }
        }
        return new List<Set<String>>{ leadFields, crFields, acctFields };
    }

    /** The incoming lead's display value for a mapping — a lookup's Name, or the plain value. */
    private static String incomingDisplayFor(SObject ld, FieldMapping m) {
        if (!m.isLookup) return valueOf(ld.get(m.leadField));
        SObject related = ld.getSObject(relationshipName(m.leadField));
        return related != null ? (String) related.get('Name') : null;
    }

    /**
     * Merge an unmerged Lead into the candidate the admin picked. masterRoleId
     * takes either kind: a ConstituentRole Id for a converted master identity,
     * or a Lead Id for another still-pending lead (two raw registrations for the
     * same person, neither provisioned yet). Either way the picked record is the
     * survivor and the source of truth: by default we only LINK the lead and
     * FILL GAPS on the survivor from the lead's captured fields — we never
     * overwrite values it already has.
     *
     * fieldChoicesJson (optional) is a JSON map of fieldKey -> 'existing'|'incoming',
     * produced by the merge review screen (see getMergeFieldComparison). For any
     * field with an explicit choice, that side's value is written even if it means
     * overwriting the survivor — the admin has reviewed and approved it. Fields
     * with no choice fall back to the gap-fill rule above.
     *
     * Any other unconverted leads sharing the same email are also absorbed: the
     * survivor gets their data (gap-fill only — field choices only apply to the
     * primary lead being merged) and they are marked Merged too.
     *
     * The merged lead gets Master_Lead__c pointing at the surviving lead, so the
     * trail back is visible from either side. Is_Converted__c = true bypasses the
     * provisioning trigger so no second Person Account is created for it.
     */
    @AuraEnabled
    public static SaveResult mergeLeadIntoMaster(Id leadId, Id masterRoleId, String fieldChoicesJson) {
        if (leadId == null || masterRoleId == null) {
            return new SaveResult(false, 'Pick a record to merge into.', null);
        }
        if (!isLeadId(leadId)) {
            return new SaveResult(false, 'Merge is currently supported for lead records only.', null);
        }
        if (leadId == masterRoleId) {
            return new SaveResult(false, 'A lead cannot be merged into itself.', null);
        }
        try {
            // choices.get(anyUnsetKey) naturally returns null, which applySide()
            // treats as "no explicit pick, fall back to gap-fill" — so an empty or
            // partial map is fine, no need to pre-seed every key.
            Map<String, String> choices = new Map<String, String>();
            if (String.isNotBlank(fieldChoicesJson)) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(fieldChoicesJson);
                for (String key : parsed.keySet()) choices.put(key, String.valueOf(parsed.get(key)));
            }

            // Same dynamic field set as getMergeFieldComparison, built from
            // allMergeFields() — so a field that's auto-discovered or declared as
            // an exception is automatically both comparable AND writeable here
            // with no further code changes.
            List<FieldMapping> fields = allMergeFields();
            List<Set<String>> queryFields = mergeQueryFields(fields, false);

            List<Lead> leadRows = Database.query(
                'SELECT ' + String.join(new List<String>(queryFields[0]), ', ') + ' FROM Lead WHERE Id = :leadId LIMIT 1'
            );
            if (leadRows.isEmpty()) return new SaveResult(false, 'Lead not found.', null);
            Lead ld = leadRows[0];
            if (ld.Status == 'Converted' || ld.Status == 'Merged') {
                return new SaveResult(false, 'This lead is already merged/converted.', null);
            }

            MergeTarget target = loadMergeTargets(
                new List<Id>{ masterRoleId }, queryFields[1], queryFields[2], queryFields[0]
            ).get(masterRoleId);
            if (target == null || !target.exists()) {
                return new SaveResult(false, 'Selected record was not found.', null);
            }
            if (target.isLead && !isLeadStillPending(target.leadRec)) {
                return new SaveResult(false,
                    'That lead is no longer pending — it has been verified, converted, merged or rejected.', null);
            }
            // Name, phone and email all live on the master's Person Account. With no
            // reachable Account those writes would be skipped without complaint, so
            // the merge would silently drop exactly the fields the admin reviewed.
            if (!target.isLead && target.personRec == null) {
                return new SaveResult(false,
                    'That alumni record has no reachable Person Account, so name, phone and email '
                    + 'cannot be written. Fix the record before merging into it.', null);
            }

            target.linkLead(ld.Id);

            // Generic gap-fill/override for every mapped field. Institution Name
            // is never in this list — autoDiscoveredFields() skips it since on
            // ConstituentRole it's a formula (Program_Plan__r.Provider.Name), not
            // writeable, so it just updates on its own once Program Plan is resolved.
            for (FieldMapping m : fields) {
                target.write(m, applySide(choices.get(m.key), target.rawFor(m), valueOf(ld.get(m.leadField))));
            }
            target.writeEmail(applySide(choices.get('email'), target.emailValue(), valueOf(ld.get('Email'))));
            target.saveChanges();

            Id survivingLeadId = target.survivingLeadId();
            ld.Status = 'Merged';
            ld.Is_Converted__c = true;
            if (survivingLeadId != null && survivingLeadId != ld.Id) ld.Master_Lead__c = survivingLeadId;
            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new KenCrudException('Lead is not updateable by the current user.');
            }
            update ld;

            Integer absorbed = absorbSiblingLeads(ld, target, fields);

            notifyMergeSurvivor(target);

            String message = target.isLead
                ? 'Lead merged into the selected lead.'
                : 'Lead merged with the master record.';
            if (absorbed > 0) {
                message += ' ' + absorbed + ' further duplicate'
                    + (absorbed == 1 ? '' : 's') + ' sharing the same email '
                    + (absorbed == 1 ? 'was' : 'were') + ' absorbed.';
            }
            if (absorbed == SIBLING_ABSORB_LIMIT) {
                message += ' That is the per-merge limit — run the merge again to catch any remaining duplicates.';
            }
            return new SaveResult(true, message, null);
        } catch (Exception e) {
            return new SaveResult(false, e.getMessage(), null);
        }
    }

    /**
     * How many same-email duplicates one merge will absorb. Capped rather than
     * unbounded so a shared or malformed email (a generic office address, say)
     * can't turn one merge into a runaway update; the caller reports when the cap
     * is reached so the admin knows to run it again rather than assuming it
     * finished.
     */
    private static final Integer SIBLING_ABSORB_LIMIT = 200;

    /**
     * Folds every other still-pending lead that shares the merged lead's email
     * into the same survivor. These duplicates were never reviewed field by
     * field, so they only ever gap-fill: a value the survivor already has is
     * left alone. The survivor is written once after the loop, not once per
     * sibling, and the survivor itself is never absorbed even when it shares
     * the email.
     *
     * Returns how many duplicates were absorbed, so the merge result can say so
     * instead of leaving the admin to guess.
     */
    private static Integer absorbSiblingLeads(Lead merged, MergeTarget target, List<FieldMapping> fields) {
        if (String.isBlank(merged.Email)) return 0;

        Set<String> siblingFields = new Set<String>{ 'Id', 'Status', 'Email', 'Is_Converted__c', 'Master_Lead__c' };
        for (FieldMapping m : fields) siblingFields.add(m.leadField);

        String email = merged.Email;
        Id mergedId = merged.Id;
        Id targetLeadId = target.isLead ? target.leadRec.Id : null;
        // Same eligibility test as the candidate lists: a verified or converted
        // duplicate is already provisioning and must not be absorbed underneath
        // the trigger that is working on it.
        Set<String> ineligible = NON_CANDIDATE_LEAD_STATUSES;

        Integer absorbLimit = SIBLING_ABSORB_LIMIT;
        List<Lead> siblings = Database.query(
            'SELECT ' + String.join(new List<String>(siblingFields), ', ') +
            ' FROM Lead WHERE Email = :email AND Id != :mergedId' +
            ' AND Id != :targetLeadId AND Status NOT IN :ineligible' +
            ' AND Is_Converted__c != true LIMIT :absorbLimit'
        );
        if (siblings.isEmpty()) return 0;

        Id survivingLeadId = target.survivingLeadId() != null ? target.survivingLeadId() : merged.Id;
        List<Lead> toMark = new List<Lead>();
        for (Lead sib : siblings) {
            for (FieldMapping m : fields) {
                if (String.isBlank(target.rawFor(m))) target.write(m, valueOf(sib.get(m.leadField)));
            }
            sib.Status = 'Merged';
            sib.Is_Converted__c = true;
            if (survivingLeadId != sib.Id) sib.Master_Lead__c = survivingLeadId;
            toMark.add(sib);
        }
        target.saveChanges();
        if (!Schema.sObjectType.Lead.isUpdateable()) {
            throw new KenCrudException('Lead is not updateable by the current user.');
        }
        update toMark;
        return toMark.size();
    }

    /**
     * Commits a merge decided via the N-way compare screen: the admin has
     * already resolved, per field, which of the N candidates (or the incoming
     * lead) should win — this writes those exact resolved values onto the ONE
     * candidate they picked from the "Merge into" list. targetMasterRoleId takes
     * either kind: a ConstituentRole Id for a converted master, or a Lead Id for
     * a still-pending lead.
     *
     * Every other candidate that was compared but not picked is superseded. A
     * master candidate keeps its own records and only its LINKED lead (via that
     * candidate's Lead__c) is marked; a lead candidate is marked directly. Either
     * way the superseded lead's Master_Lead__c points at the surviving lead and
     * its Status flips to Merged, so anyone who opens it later can see exactly
     * what it was folded into.
     *
     * fieldChoicesJson is a map of fieldKey -> raw value string (the literal
     * value to write — an Id for lookup fields, plain text otherwise), taken
     * directly from whichever pill the admin had selected for that field on
     * the compare screen. A field with no entry falls back to the same
     * never-overwrite gap-fill rule as the single-candidate flow.
     *
     * otherCandidateIds is every OTHER candidate that was in the comparison —
     * i.e. all of them except targetMasterRoleId. Pass null/empty if only one
     * candidate was ever being considered (nothing to mark as superseded).
     */
    @AuraEnabled
    public static SaveResult mergeCandidatesIntoOne(Id leadId, Id targetMasterRoleId, String fieldChoicesJson, List<Id> otherCandidateIds) {
        if (leadId == null || targetMasterRoleId == null) {
            return new SaveResult(false, 'Pick which candidate to merge into.', null);
        }
        if (!isLeadId(leadId)) {
            return new SaveResult(false, 'Merge is currently supported for lead records only.', null);
        }
        if (leadId == targetMasterRoleId) {
            return new SaveResult(false, 'A lead cannot be merged into itself.', null);
        }
        try {
            Map<String, String> resolved = new Map<String, String>();
            if (String.isNotBlank(fieldChoicesJson)) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(fieldChoicesJson);
                for (String key : parsed.keySet()) resolved.put(key, String.valueOf(parsed.get(key)));
            }

            List<FieldMapping> fields = allMergeFields();
            List<Set<String>> queryFields = mergeQueryFields(fields, false);

            List<Lead> leadRows = Database.query(
                'SELECT ' + String.join(new List<String>(queryFields[0]), ', ') + ' FROM Lead WHERE Id = :leadId LIMIT 1'
            );
            if (leadRows.isEmpty()) return new SaveResult(false, 'Lead not found.', null);
            Lead ld = leadRows[0];
            if (ld.Status == 'Converted' || ld.Status == 'Merged') {
                return new SaveResult(false, 'This lead is already merged/converted.', null);
            }

            MergeTarget target = loadMergeTargets(
                new List<Id>{ targetMasterRoleId }, queryFields[1], queryFields[2], queryFields[0]
            ).get(targetMasterRoleId);
            if (target == null || !target.exists()) {
                return new SaveResult(false, 'Selected target candidate was not found.', null);
            }
            if (target.isLead && !isLeadStillPending(target.leadRec)) {
                return new SaveResult(false,
                    'That lead is no longer pending — it has been verified, converted, merged or rejected.', null);
            }
            // Name, phone and email all live on the master's Person Account. With no
            // reachable Account those writes would be skipped without complaint, so
            // the merge would silently drop exactly the fields the admin reviewed.
            if (!target.isLead && target.personRec == null) {
                return new SaveResult(false,
                    'That alumni record has no reachable Person Account, so name, phone and email '
                    + 'cannot be written. Fix the record before merging into it.', null);
            }

            // A lead cannot absorb an existing alumni identity: the master owns a
            // Person Account, a portal user and related records that have nowhere to
            // go on a Lead. Keeping the lead would leave that identity stranded
            // while its linked lead got marked Merged — so when a master is on the
            // table at all, the master has to be the survivor.
            if (target.isLead) {
                for (Id candidateId : (otherCandidateIds == null ? new List<Id>() : otherCandidateIds)) {
                    if (candidateId == null || candidateId == targetMasterRoleId || isLeadId(candidateId)) continue;
                    return new SaveResult(false,
                        'This comparison includes an existing alumni record, which cannot be folded into a lead. '
                        + 'Pick that alumni record as the one to merge into.', null);
                }
            }

            target.linkLead(ld.Id);

            for (FieldMapping m : fields) {
                String existingStr = target.rawFor(m);
                String result = resolved.containsKey(m.key)
                    ? resolved.get(m.key)
                    : (String.isNotBlank(existingStr) ? existingStr : valueOf(ld.get(m.leadField)));
                target.write(m, result);
            }

            String existingEmail = target.emailValue();
            target.writeEmail(resolved.containsKey('email')
                ? resolved.get('email')
                : (String.isNotBlank(existingEmail) ? existingEmail : valueOf(ld.get('Email'))));
            target.saveChanges();

            Id survivingLeadId = target.survivingLeadId();
            ld.Status = 'Merged';
            ld.Is_Converted__c = true;
            if (survivingLeadId != null && survivingLeadId != ld.Id) ld.Master_Lead__c = survivingLeadId;
            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new KenCrudException('Lead is not updateable by the current user.');
            }
            update ld;

            markSupersededCandidates(
                otherCandidateIds, targetMasterRoleId,
                survivingLeadId != null ? survivingLeadId : ld.Id
            );

            notifyMergeSurvivor(target);

            return new SaveResult(true, 'Lead merged into the selected candidate.', null);
        } catch (Exception e) {
            return new SaveResult(false, e.getMessage(), null);
        }
    }

    private static final String ALUMNI_LEAD_MERGED_TEMPLATE = 'Alumni_Lead_Merged';

    /**
     * @description Tells the surviving alumnus that the duplicate registrations we held for
     *              them have been folded into one profile.
     *
     *              This lives here rather than in the Lead trigger because only the merge
     *              itself knows which side survived. The absorbed duplicate is the record
     *              that carries Status = 'Merged', but it is the master whose profile
     *              actually changed — and a merge into an existing alumnus leaves the
     *              duplicate with no link back to that master, so the trigger could not
     *              find the right recipient even if it wanted to.
     *
     *              The address is read after saveChanges(), so the notice follows whichever
     *              email the admin chose to keep. An N-way merge folds several duplicates
     *              into one survivor and therefore sends exactly one email.
     *
     *              Never throws: a merge must not fail because an email could not be built.
     *
     * @param target the record the duplicates were merged into
     */
    private static void notifyMergeSurvivor(MergeTarget target) {

        if (target == null) {
            return;
        }

        try {
            String toAddress = target.emailValue();
            if (String.isBlank(toAddress)) {
                return;
            }

            Ken_Alm_Bypass_Settings__c emailSettings = KenSettings.bypass();
            if (emailSettings != null && emailSettings.Skip_Lead_Merged_Email__c) {
                return;
            }

            List<EmailTemplate> templates = [
                SELECT Id, Subject, HtmlValue
                FROM EmailTemplate
                WHERE DeveloperName = :ALUMNI_LEAD_MERGED_TEMPLATE
                AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (templates.isEmpty()) {
                return;
            }
            EmailTemplate template = templates[0];

            Ken_Alm_Org_Parameters__c orgParam = Ken_Alm_Org_Parameters__c.getOrgDefaults();
            String institutionAlias = orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c)
                ? orgParam.Institution_Alias__c : '';
            String institutionEmail = orgParam != null && String.isNotBlank(orgParam.Institution_Email__c)
                ? orgParam.Institution_Email__c : '';

            Map<String, String> tokens = new Map<String, String>{
                'User_Name' => String.isNotBlank(target.displayName) ? target.displayName : 'there',
                'Institution_Alias' => institutionAlias,
                'Institution_Email' => institutionEmail
            };

            KenMessagingService.Request routing =
                new KenMessagingService.Request(KenMessagingService.TYPE_LEAD_MERGED)
                    .attribute('Institution_Alias', institutionAlias)
                    .attribute('Institution_Email', institutionEmail);
            routing.recipient(toAddress, null, tokens);

            List<OrgWideEmailAddress> orgIds = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = :KenMessagingService.orgWideAddressName()
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

            String body = KenMessagingService.mergeTokens(template.HtmlValue, tokens);
            String finalBody = '<html><body>' + letterheadHeader + body + '</body></html>';

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ toAddress });
            msg.setSubject(String.isNotBlank(template.Subject)
                ? template.Subject
                : 'Your Alumni Portal Records Have Been Combined');
            msg.setHtmlBody(finalBody);
            msg.setOrgWideEmailAddressId(!orgIds.isEmpty() ? orgIds[0].Id : null);
            msg.setSaveAsActivity(false);

            List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>{ msg };
            if (KenMessagingService.send(routing.withNativeFallback(messages)).handled) {
                return;
            }
            Messaging.sendEmail(messages);

        } catch (Exception e) {
            // The merge has already been committed and is correct. Losing the notification
            // is recoverable; failing the merge back to the admin is not.
            System.debug(LoggingLevel.WARN, 'Merge notification not sent: ' + e.getMessage());
        }
    }

    /**
     * Marks every candidate that was compared but not kept. A master candidate's
     * own records are left alone — only the lead linked to it is superseded, so
     * no alumni identity is silently rewritten. A lead candidate is superseded
     * directly. Is_Converted__c stops a superseded lead from later provisioning a
     * Person Account of its own, and a lead that is already closed
     * (converted/merged/rejected) keeps the status it has.
     */
    private static void markSupersededCandidates(List<Id> otherCandidateIds, Id targetId, Id survivingLeadId) {
        if (otherCandidateIds == null || otherCandidateIds.isEmpty()) return;

        Set<Id> leadIds = new Set<Id>();
        Set<Id> roleIds = new Set<Id>();
        for (Id candidateId : otherCandidateIds) {
            if (candidateId == null || candidateId == targetId) continue;
            if (isLeadId(candidateId)) leadIds.add(candidateId); else roleIds.add(candidateId);
        }
        if (!roleIds.isEmpty()) {
            for (ConstituentRole other : [SELECT Id, Lead__c FROM ConstituentRole WHERE Id IN :roleIds WITH USER_MODE]) {
                if (other.Lead__c != null) leadIds.add(other.Lead__c);
            }
        }
        leadIds.remove(survivingLeadId);
        if (leadIds.isEmpty()) return;

        List<Lead> toUpdate = new List<Lead>();
        for (Lead other : [
            SELECT Id, Status, Is_Converted__c, Master_Lead__c FROM Lead WHERE Id IN :leadIds
        WITH USER_MODE
        ]) {
            Boolean dirty = false;
            // The trail is always worth recording, whatever state the lead is in.
            if (survivingLeadId != null && other.Master_Lead__c != survivingLeadId) {
                other.Master_Lead__c = survivingLeadId;
                dirty = true;
            }
            // Status and the provisioning block only apply to leads still in play.
            // A verified lead is mid-provisioning and a converted one already has an
            // identity — rewriting either would fight the flow that owns it.
            if (isLeadStillPending(other)) {
                other.Status = 'Merged';
                other.Is_Converted__c = true;
                dirty = true;
            }
            if (dirty) toUpdate.add(other);
        }
        if (!toUpdate.isEmpty()) {
            if (!Schema.sObjectType.Lead.isUpdateable()) {
                throw new KenCrudException('Lead is not updateable by the current user.');
            }
            update toUpdate;
        }
    }

    /* ============================================================
       Helpers — query building
       ============================================================ */

    private static String buildWhereForTab(String tabKey, String searchTerm, String issueType, String portalStatus, String dashboardFilter, Set<Id> issuePersonIds, Set<Id> searchPersonIds, String filtersJson, Set<Id> filterPersonIds, Map<String, Object> binds) {
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
            conditions.add('(Registration_Status__c = null OR Registration_Status__c IN (\'Unregistered\', \'Onboarding In Progress\'))');
        } else if (tabKey == 'oldportal') {
            conditions.add('Source_Funnel__c IN (\'Old Portal Record\', \'Old Portal Migration\')');
        } else if (tabKey == 'issues') {
            if (issuePersonIds == null || issuePersonIds.isEmpty()) {
                // Force empty result deterministically
                conditions.add('Id = null');
            } else {
                binds.put('issuePersonIds', issuePersonIds);
                conditions.add('PersonId IN :issuePersonIds');
            }
        } else if (tabKey == 'leads') {
            // Show every lead-sourced row that hasn't been advanced past New yet.
            // Anything still null / blank / pre-onboarding counts as a new lead.
            // Once the alumnus starts onboarding it drops off the tab.
            conditions.add('Source_Funnel__c IN (\'Self-Declared Lead\', \'Campaign Lead\')');
            conditions.add('(Registration_Status__c = null OR Registration_Status__c NOT IN (\'Onboarding In Progress\', \'Registered\', \'Initial Login Done\'))');
        } else if (tabKey == 'referrals') {
            conditions.add('Source_Funnel__c = \'Alumni Referral\'');
        }
        if (String.isNotBlank(portalStatus)) {
            if (portalStatus == 'active') {
                conditions.add('Registration_Status__c = \'Initial Login Done\'');
            } else if (portalStatus == 'registered') {
                conditions.add('Registration_Status__c = \'Registered\'');
            } else if (portalStatus == 'not') {
                conditions.add('(Registration_Status__c = null OR Registration_Status__c IN (\'Unregistered\', \'Onboarding In Progress\'))');
                conditions.add('Source_Funnel__c != \'Old Portal Record\'');
                conditions.add('Source_Funnel__c != \'Old Portal Migration\'');
            } else if (portalStatus == 'old') {
                conditions.add('Source_Funnel__c IN (\'Old Portal Record\', \'Old Portal Migration\')');
            }
        }
        if (String.isNotBlank(searchTerm)) {
            binds.put('bSearch', '%' + searchTerm + '%');
            // Match either a direct ConstituentRole field or any PersonId resolved
            // by searching Account/PersonEmployment.
            String personClause = '';
            if (searchPersonIds != null && !searchPersonIds.isEmpty()) {
                binds.put('searchPersonIds', searchPersonIds);
                personClause = ' OR PersonId IN :searchPersonIds';
            }
            conditions.add(
                '(Registration_Number__c LIKE :bSearch' +
                ' OR Graduation_Year__c LIKE :bSearch' +
                ' OR Program_Name__c LIKE :bSearch' +
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
                binds.put('bProgram', program);
                conditions.add('(Program_Name__c = :bProgram OR Program_Plan__r.Name = :bProgram)');
            }
            String gradYear = filterVal(f, 'graduationYear');
            if (String.isNotBlank(gradYear)) {
                binds.put('bGradYear', gradYear);
                conditions.add('Graduation_Year__c = :bGradYear');
            }
            String source = filterVal(f, 'source');
            if (String.isNotBlank(source)) {
                binds.put('bSource', source);
                conditions.add('Source_Funnel__c = :bSource');
            }
            // New Master-records filter set — institute / intake / status are direct
            // ConstituentRole columns and apply inline. role / domain / skill are
            // person-based and get folded into filterPersonIds.
            String institute = filterVal(f, 'institute');
            if (String.isNotBlank(institute)) {
                binds.put('bInstitute', institute);
                conditions.add('Institution_Name__c = :bInstitute');
            }
            String intake = filterVal(f, 'intake');
            if (String.isNotBlank(intake)) {
                // Intake is the LearningProgramPlan cohort name (e.g. "BBA-DEC-2025").
                binds.put('bIntake', intake);
                conditions.add('Program_Plan__r.Name = :bIntake');
            }
            String status = filterVal(f, 'status');
            if (String.isNotBlank(status)) {
                if (status == 'Registered') {
                    conditions.add('Registration_Status__c IN (\'Registered\', \'Initial Login Done\')');
                } else if (status == 'Unregistered') {
                    conditions.add('(Registration_Status__c = null OR Registration_Status__c IN (\'Unregistered\', \'Onboarding In Progress\'))');
                }
            }
            if (hasPersonFilters(f)) {
                if (filterPersonIds == null || filterPersonIds.isEmpty()) {
                    conditions.add('Id = null');
                } else {
                    binds.put('filterPersonIds', filterPersonIds);
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

    /** Reads an array-valued filter (e.g. the Language checkbox multi-select). */
    private static List<String> filterValList(Map<String, Object> f, String key) {
        List<String> out = new List<String>();
        if (f == null || !f.containsKey(key) || f.get(key) == null) return out;
        Object raw = f.get(key);
        if (!(raw instanceof List<Object>)) return out;
        for (Object o : (List<Object>) raw) {
            if (o == null) continue;
            String v = String.valueOf(o).trim();
            if (String.isNotBlank(v)) out.add(v);
        }
        return out;
    }

    private static Boolean hasPersonFilters(Map<String, Object> f) {
        return String.isNotBlank(filterVal(f, 'company'))
            || String.isNotBlank(filterVal(f, 'industry'))
            || String.isNotBlank(filterVal(f, 'location'))
            || String.isNotBlank(filterVal(f, 'country'))
            || String.isNotBlank(filterVal(f, 'role'))
            || String.isNotBlank(filterVal(f, 'domain'))
            || String.isNotBlank(filterVal(f, 'skill'))
            || String.isNotBlank(filterVal(f, 'preference'))
            || !filterValList(f, 'language').isEmpty();
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
        if (String.isNotBlank(location)) result = intersectIds(result, locationPersonIds(location));
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
        List<String> languages = filterValList(f, 'language');
        if (!languages.isEmpty()) result = intersectIds(result, languagePersonIds(languages));
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
            WITH USER_MODE
            LIMIT 50000
        ]) {
            if (p.Person_Account__c != null) ids.add(p.Person_Account__c);
        }
        return ids;
    }

    /**
     * Language filter options. Account.Languages_Known__c is free text
     * ("English, Hindi, Tamil"), not a picklist — so distinct values are
     * derived by splitting every non-blank value on comma, trimming, and
     * counting. Same recipe as {@link preferencePairs}, which does the same
     * thing for the semicolon-separated Engagement_Preferences__c field.
     */
    private static List<FilterOptionPair> languagePairs(String crWhere) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (FilterOptionPair combo : groupedPairs('Account', 'Languages_Known__c',
                'IsPersonAccount = true AND ' + alumniPersonScope('Id', crWhere))) {
            for (String s : combo.value.split(',')) {
                String t = normalizeLanguageLabel(s);
                if (String.isBlank(t)) continue;
                counts.put(t, (counts.containsKey(t) ? counts.get(t) : 0) + combo.count);
            }
        }
        return pairsFromCounts(counts);
    }

    /**
     * Free-typed language entries can't be made fully accurate (no picklist
     * behind them), but casing is a fixable, known issue — "Tamil" / "tamil" /
     * "TAMIL" should be one checkbox option, not three. Normalizes to title
     * case per word. Matching against the stored value in languagePersonIds()
     * still works regardless of the DB's original casing — SOQL text
     * comparisons (LIKE included) are case-insensitive on standard text
     * fields, so this only affects how the option list groups/displays.
     */
    private static String normalizeLanguageLabel(String raw) {
        if (raw == null) return null;
        String trimmed = raw.trim();
        if (String.isBlank(trimmed)) return trimmed;
        List<String> out = new List<String>();
        for (String w : trimmed.split('\\s+')) {
            if (String.isBlank(w)) continue;
            String lower = w.toLowerCase();
            out.add(lower.substring(0, 1).toUpperCase() + lower.substring(1));
        }
        return String.join(out, ' ');
    }

    /**
     * Person Account Ids whose Languages_Known__c (free text) contains ANY of
     * the requested languages — OR semantics across a multi-select, so
     * picking "English" + "Hindi" surfaces alumni who know either.
     */
    private static Set<Id> languagePersonIds(List<String> values) {
        Set<Id> ids = new Set<Id>();
        for (String v : values) {
            if (String.isBlank(v)) continue;
            String likeVal = '%' + v + '%';
            for (Account a : [
                SELECT Id
                FROM Account
                WHERE IsPersonAccount = true AND Languages_Known__c LIKE :likeVal
                WITH USER_MODE
                LIMIT 50000
            ]) {
                ids.add(a.Id);
            }
        }
        return ids;
    }

    /**
     * Person Account Ids whose engagement preferences include the requested
     * value, read from the semicolon-separated Account.Engagement_Preferences__c.
     */
    private static Set<Id> preferencePersonIds(String preference) {
        Set<Id> ids = new Set<Id>();
        String likeVal = '%' + preference + '%';
        for (Account a : [
            SELECT Id
            FROM Account
            WHERE Engagement_Preferences__c LIKE :likeVal
              AND IsPersonAccount = true
            WITH USER_MODE
            LIMIT 50000
        ]) {
            ids.add(a.Id);
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
        for (SObject pe : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'value' => value },
                AccessLevel.SYSTEM_MODE)) {
            Id a = (Id) pe.get('AccountId');
            if (a != null) ids.add(a);
        }
        return ids;
    }

    private static Set<Id> countryPersonIds(String value) {
        return accountFieldPersonIds('PersonMailingCountry', value);
    }

    /** Person Accounts whose given field equals value exactly. */
    private static Set<Id> accountFieldPersonIds(String field, String value) {
        Set<Id> ids = new Set<Id>();
        String soql = 'SELECT Id FROM Account WHERE IsPersonAccount = true AND '
            + field + ' = :value LIMIT ' + MAX_MATCH_ROWS;
        for (SObject a : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'value' => value },
                AccessLevel.SYSTEM_MODE)) {
            Id recId = (Id) a.get('Id');
            if (recId != null) ids.add(recId);
        }
        return ids;
    }

    /**
     * "Location / City" spans both the alumnus's own mailing city and the city
     * on their employment record, so the filter matches either. Sourcing it from
     * PersonEmployment alone made the dropdown reflect only the handful of
     * alumni who have an employment row, ignoring every imported mailing city.
     */
    private static Set<Id> locationPersonIds(String value) {
        Set<Id> ids = accountFieldPersonIds('PersonMailingCity', value);
        ids.addAll(empPersonIds('Location__c', value));
        return ids;
    }

    /** Distinct "Location / City" options from mailing city + employment location. */
    private static List<FilterOptionPair> locationOptionPairs(String crWhere) {
        Map<String, Integer> counts = new Map<String, Integer>();
        accumulateGroups(counts, 'Account', 'PersonMailingCity',
            'IsPersonAccount = true AND ' + alumniPersonScope('Id', crWhere));
        accumulateGroups(counts, 'PersonEmployment', 'Location__c',
            alumniPersonScope('AccountId', crWhere));
        return pairsFromCounts(counts);
    }

    /**
     * Distinct values that populate the Filters popup dropdowns.
     */
    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions(String tabKey, String dashboardFilter) {
        // The Leads tab lists Lead records, so its dropdowns have to be grouped
        // from Lead too. Grouping ConstituentRole here (as every other tab does)
        // offered values and counts drawn from a completely different record
        // set: the option said "(7)" and applying it returned nothing, because
        // those 7 were roles, not leads.
        if (tabKey == 'leads') {
            return leadFilterOptions();
        }

        // Build a CR-scoped base condition that mirrors the current tab's WHERE.
        List<String> crParts = new List<String>{ 'RoleType = \'Alumni\'' };
        String tabCond = tabConditionForCR(tabKey);
        if (String.isNotBlank(tabCond)) crParts.add(tabCond);
        if (String.isNotBlank(dashboardFilter)) {
            crParts.addAll(dashboardFilterConditions(dashboardFilter));
        }
        String crWhere = String.join(crParts, ' AND ');

        FilterOptions o = new FilterOptions();

        // Person-side option lists count rows on Account / PersonEmployment /
        // preference objects, which hold non-alumni records too (students,
        // staff, other role types). Scoping each one to the same alumni set the
        // table itself queries keeps the dropdown counts consistent with the
        // results the filter actually returns.
        String personScope = alumniPersonScope('AccountId', crWhere);
        String acctScope   = 'IsPersonAccount = true AND ' + alumniPersonScope('Id', crWhere);

        o.programPairs        = programOptionPairs(crWhere);
        o.graduationYearPairs = groupedPairs('ConstituentRole', 'Graduation_Year__c', crWhere);
        o.sourcePairs         = groupedPairs('ConstituentRole', 'Source_Funnel__c', crWhere);
        o.companyPairs        = groupedPairs('PersonEmployment', 'Company_Name__c', personScope);
        o.industryPairs       = groupedPairs('PersonEmployment', 'Job_Role__c', personScope);
        o.locationPairs       = locationOptionPairs(crWhere);
        o.countryPairs        = groupedPairs('Account', 'PersonMailingCountry', acctScope);
        o.institutePairs      = groupedPairs('ConstituentRole', INSTITUTE_GROUP_FIELD, crWhere);
        o.rolePairs           = groupedPairs('PersonEmployment', 'Designation__c', personScope);
        o.domainPairs         = o.industryPairs;
        // Intake filters on ConstituentRole.Program_Plan__r.Name, so the options
        // must be grouped from the roles too — grouping LearningProgramPlan
        // itself listed every cohort in the org and counted plans, not alumni.
        o.intakePairs         = groupedPairs('ConstituentRole', 'Program_Plan__r.Name', crWhere);
        o.employmentTypePairs = groupedPairs('PersonEmployment', 'EmploymentType', personScope);
        o.genderPairs         = groupedPairs('Account', 'PersonGenderIdentity', acctScope);
        o.skillPairs          = skillPairs(crWhere);
        o.statusPairs         = statusPairs(crWhere);
        o.preferencePairs     = preferencePairs(crWhere);
        o.languagePairs       = languagePairs(crWhere);

        o.programs        = valuesOf(o.programPairs);
        o.graduationYears = valuesOf(o.graduationYearPairs);
        o.sources         = valuesOf(o.sourcePairs);
        o.companies       = valuesOf(o.companyPairs);
        o.industries      = valuesOf(o.industryPairs);
        o.locations       = valuesOf(o.locationPairs);
        o.countries       = valuesOf(o.countryPairs);
        o.institutes      = valuesOf(o.institutePairs);
        o.roles           = valuesOf(o.rolePairs);
        o.domains         = o.industries;
        o.intakes         = valuesOf(o.intakePairs);
        o.employmentTypes = valuesOf(o.employmentTypePairs);
        o.genders         = valuesOf(o.genderPairs);
        o.skills          = valuesOf(o.skillPairs);
        o.statuses        = valuesOf(o.statusPairs);
        o.preferences     = valuesOf(o.preferencePairs);
        return o;
    }

    /**
     * Filter options for the Leads tab, grouped from the same Lead scope
     * buildNewLeadsList() queries so every value offered is reachable and every
     * count matches what applying it returns.
     *
     * Employment type, gender, language, engagement preference, skill and
     * registration status describe a Person Account or a ConstituentRole. A new
     * lead has neither, so those lists stay empty and the popup hides the
     * fields — offering them would only produce filters that silently do
     * nothing.
     */
    private static FilterOptions leadFilterOptions() {
        FilterOptions o = new FilterOptions();

        o.institutePairs      = groupedPairs('Lead', 'Institution_Name__c', LEAD_TAB_SCOPE);
        o.programPairs        = leadProgramOptionPairs();
        o.intakePairs         = groupedPairs('Lead', 'Program_Plan__r.Name', LEAD_TAB_SCOPE);
        o.graduationYearPairs = groupedPairs('Lead', 'Year_of_Graduation__c', LEAD_TAB_SCOPE);
        o.companyPairs        = groupedPairs('Lead', 'Company', LEAD_TAB_SCOPE);
        o.rolePairs           = groupedPairs('Lead', 'Title', LEAD_TAB_SCOPE);
        o.locationPairs       = groupedPairs('Lead', 'City', LEAD_TAB_SCOPE);
        o.countryPairs        = groupedPairs('Lead', 'Country', LEAD_TAB_SCOPE);
        o.sourcePairs         = groupedPairs('Lead', 'LeadSource', LEAD_TAB_SCOPE);

        o.industryPairs       = new List<FilterOptionPair>();
        o.domainPairs         = o.industryPairs;
        o.employmentTypePairs = new List<FilterOptionPair>();
        o.genderPairs         = new List<FilterOptionPair>();
        o.languagePairs       = new List<FilterOptionPair>();
        o.preferencePairs     = new List<FilterOptionPair>();
        o.skillPairs          = new List<FilterOptionPair>();
        o.statusPairs         = new List<FilterOptionPair>();

        o.institutes      = valuesOf(o.institutePairs);
        o.programs        = valuesOf(o.programPairs);
        o.intakes         = valuesOf(o.intakePairs);
        o.graduationYears = valuesOf(o.graduationYearPairs);
        o.companies       = valuesOf(o.companyPairs);
        o.roles           = valuesOf(o.rolePairs);
        o.locations       = valuesOf(o.locationPairs);
        o.countries       = valuesOf(o.countryPairs);
        o.sources         = valuesOf(o.sourcePairs);
        o.industries      = valuesOf(o.industryPairs);
        o.domains         = o.industries;
        o.employmentTypes = valuesOf(o.employmentTypePairs);
        o.genders         = valuesOf(o.genderPairs);
        o.preferences     = valuesOf(o.preferencePairs);
        o.skills          = valuesOf(o.skillPairs);
        o.statuses        = valuesOf(o.statusPairs);
        return o;
    }

    /**
     * Program options for the Leads tab. Mirrors programOptionPairs(): the
     * headline value is the LearningProgram name, with the plan's own name
     * standing in for leads whose plan carries no program.
     */
    private static List<FilterOptionPair> leadProgramOptionPairs() {
        Map<String, Integer> counts = new Map<String, Integer>();
        accumulateGroups(counts, 'Lead', PROGRAM_GROUP_FIELD, LEAD_TAB_SCOPE);
        accumulateGroups(counts, 'Lead', 'Program_Plan__r.Name',
            LEAD_TAB_SCOPE + ' AND ' + PROGRAM_GROUP_FIELD + ' = null');
        return pairsFromCounts(counts);
    }

    /**
     * Semi-join restricting a person-keyed object to the alumni currently in
     * scope. A semi-join (rather than binding a Set<Id> of PersonIds) is
     * deliberate: materialising the Ids costs one query row per alumnus and
     * blows the 50,000-row transaction limit on large orgs, which is
     * uncatchable and empties every dropdown at once.
     */
    private static String alumniPersonScope(String idField, String crWhere) {
        return idField + ' IN (SELECT PersonId FROM ConstituentRole WHERE ' + crWhere + ')';
    }

    /** Returns the tab-specific WHERE fragment for ConstituentRole queries (no RoleType prefix). */
    private static String tabConditionForCR(String key) {
        if (key == 'recent')       return 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\') AND CreatedDate = LAST_N_DAYS:30';
        if (key == 'registered')   return 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')';
        if (key == 'unregistered') return '(Registration_Status__c = null OR Registration_Status__c IN (\'Unregistered\', \'Onboarding In Progress\'))';
        if (key == 'oldportal')    return 'Source_Funnel__c IN (\'Old Portal Record\', \'Old Portal Migration\')';
        if (key == 'leads')        return 'Source_Funnel__c IN (\'Self-Declared Lead\', \'Campaign Lead\') AND (Registration_Status__c = null OR Registration_Status__c NOT IN (\'Onboarding In Progress\', \'Registered\', \'Initial Login Done\'))';
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
        accumulateGroups(counts, 'ConstituentRole', PROGRAM_GROUP_FIELD, crWhere);
        accumulateGroups(counts, 'ConstituentRole', 'Program_Plan__r.Name',
            crWhere + ' AND ' + PROGRAM_GROUP_FIELD + ' = null');
        return pairsFromCounts(counts);
    }

    /**
     * Counts of Ken_Alumni_Preferences__c rows that include each skill.
     * Skill_set__c is a multi-picklist, which is not groupable, so this is the
     * one option list that still reads rows — bounded to MAX_SCAN_ROWS so it
     * cannot exhaust the transaction's query-row limit.
     */
    private static List<FilterOptionPair> skillPairs(String crWhere) {
        Map<String, Integer> counts = new Map<String, Integer>();
        String soql = 'SELECT Skill_set__c FROM Ken_Alumni_Preferences__c'
            + ' WHERE Skill_set__c != null AND ' + alumniPersonScope('Person_Account__c', crWhere)
            + ' LIMIT ' + MAX_SCAN_ROWS;
        List<Ken_Alumni_Preferences__c> prefRows;
        try {
            prefRows = (List<Ken_Alumni_Preferences__c>) Database.queryWithBinds(
                soql,
                new Map<String, Object>(),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception queryEx) {
            return new List<FilterOptionPair>();
        }
        for (Ken_Alumni_Preferences__c r : prefRows) {
            if (String.isBlank(r.Skill_set__c)) continue;
            for (String s : r.Skill_set__c.split(';')) {
                String t = s == null ? '' : s.trim();
                if (String.isBlank(t)) continue;
                counts.put(t, (counts.containsKey(t) ? counts.get(t) : 0) + 1);
            }
        }
        return pairsFromCounts(counts);
    }

    /**
     * Engagement preference filter options. Values come from the configurable
     * Ken_Engagement_Preference__c object (so admin-added preferences are
     * filterable immediately) plus the legacy Preferences__c multiselect's
     * defined picklist entries; counts come from the grouped
     * Engagement_Preferences__c values on the CRM rows.
     */
    private static List<FilterOptionPair> preferencePairs(String crWhere) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (Ken_Engagement_Preference__c p : [
            SELECT Name FROM Ken_Engagement_Preference__c
            WHERE Is_Active__c = true
            WITH USER_MODE
            ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC
        ]) {
            counts.put(p.Name, 0);
        }
        for (FilterOptionPair combo : groupedPairs('Account', 'Engagement_Preferences__c',
                alumniPersonScope('Id', crWhere))) {
            for (String s : combo.value.split(';')) {
                String t = s == null ? '' : s.trim();
                if (String.isBlank(t)) continue;
                counts.put(t, (counts.containsKey(t) ? counts.get(t) : 0) + combo.count);
            }
        }
        return pairsFromCounts(counts);
    }

    /**
     * Registered (Registered + Initial Login Done) vs Unregistered (null +
     * Unregistered), scoped to crWhere. The counts are best-effort: a failure
     * here must not take the rest of the filter options down with it.
     */
    private static List<FilterOptionPair> statusPairs(String crWhere) {
        Integer reg = 0;
        Integer unreg = 0;
        try {
            reg = Database.countQueryWithBinds(
                'SELECT COUNT() FROM ConstituentRole WHERE ' + crWhere +
                ' AND Registration_Status__c IN (\'Registered\', \'Initial Login Done\')',
                new Map<String, Object>(),
                AccessLevel.SYSTEM_MODE
            );
            unreg = Database.countQueryWithBinds(
                'SELECT COUNT() FROM ConstituentRole WHERE ' + crWhere +
                ' AND (Registration_Status__c = null OR Registration_Status__c IN (\'Unregistered\', \'Onboarding In Progress\'))',
                new Map<String, Object>(),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception countEx) {
            reg = 0;
            unreg = 0;
        }
        FilterOptionPair r = new FilterOptionPair();
        r.value = 'Registered'; r.count = reg; r.label = 'Registered (' + reg + ')';
        FilterOptionPair u = new FilterOptionPair();
        u.value = 'Unregistered'; u.count = unreg; u.label = 'Unregistered (' + unreg + ')';
        return new List<FilterOptionPair>{ r, u };
    }

    /**
     * label = "<value> (<count>)" / value = "<value>", one entry per distinct
     * value of groupField. Uses an aggregate GROUP BY so the query returns one
     * row per distinct value rather than every matching record — retrieving the
     * raw rows costs up to 50,000 query rows per field and exhausts the
     * transaction's 50,000-row limit, which is uncatchable and takes the whole
     * method (and therefore every dropdown) down with it.
     *
     * Counts are total occurrences on the source object and do not cascade with
     * the other open filters. groupField may traverse relationships, which is
     * how formula fields are handled: they are not groupable, so callers pass
     * the path the formula itself resolves.
     */
    private static List<FilterOptionPair> groupedPairs(String objectName, String groupField, String extraWhere) {
        String soql = 'SELECT ' + groupField + ' optValue, COUNT(Id) optCount FROM ' + objectName
            + ' WHERE ' + groupField + ' != null';
        if (String.isNotBlank(extraWhere)) {
            soql += ' AND ' + extraWhere;
        }
        soql += ' GROUP BY ' + groupField + ' ORDER BY ' + groupField + ' LIMIT ' + MAX_FILTER_OPTIONS;
        List<AggregateResult> rows;
        try {
            rows = (List<AggregateResult>) Database.queryWithBinds(
                soql,
                new Map<String, Object>(),
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception queryEx) {
            return new List<FilterOptionPair>();
        }
        List<FilterOptionPair> out = new List<FilterOptionPair>();
        for (AggregateResult ar : rows) {
            Object v = ar.get('optValue');
            if (v == null) continue;
            String s = String.valueOf(v);
            if (String.isBlank(s)) continue;
            FilterOptionPair p = new FilterOptionPair();
            p.value = s;
            p.count = (Integer) ar.get('optCount');
            p.label = s + ' (' + p.count + ')';
            out.add(p);
        }
        return out;
    }

    /** Adds a grouped query's counts into an accumulator keyed by option value. */
    private static void accumulateGroups(
        Map<String, Integer> counts, String objectName, String groupField, String extraWhere
    ) {
        for (FilterOptionPair p : groupedPairs(objectName, groupField, extraWhere)) {
            counts.put(p.value, (counts.containsKey(p.value) ? counts.get(p.value) : 0) + p.count);
        }
    }

    /** Alphabetically sorted "<value> (<count>)" pairs from an accumulator. */
    private static List<FilterOptionPair> pairsFromCounts(Map<String, Integer> counts) {
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

    /** Raw filter values behind a pair list, for the legacy plain-list DTO keys. */
    private static List<String> valuesOf(List<FilterOptionPair> pairs) {
        List<String> out = new List<String>();
        for (FilterOptionPair p : pairs) out.add(p.value);
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
            WITH USER_MODE
            LIMIT 2000
        ]) {
            ids.add(a.Id);
        }
        for (PersonEmployment pe : [
            SELECT AccountId FROM PersonEmployment
            WHERE AccountId != null
              AND (Company_Name__c LIKE :likeVar OR Location__c LIKE :likeVar)
            WITH USER_MODE
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
            'upload-available'      => new List<String>{ 'Registration_Status__c IN (\'Onboarding In Progress\', \'Registered\', \'Initial Login Done\')' },
            'upload-registered'     => new List<String>{ 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')' },
            'upload-active'         => new List<String>{ 'Registration_Status__c = \'Initial Login Done\'' },
            'transition-cohort'     => new List<String>{ transClause },
            'transition-invited'    => new List<String>{ transClause },
            'transition-registered' => new List<String>{ transClause, 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')' },
            'transition-active'     => new List<String>{ transClause, 'Registration_Status__c = \'Initial Login Done\'' },
            'leads-leads'           => new List<String>{ leadsClause },
            'leads-verified'        => new List<String>{ leadsClause, 'Registration_Status__c IN (\'Onboarding In Progress\', \'Registered\', \'Initial Login Done\')' },
            'leads-registered'      => new List<String>{ leadsClause, 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')' },
            'leads-active'          => new List<String>{ leadsClause, 'Registration_Status__c = \'Initial Login Done\'' },
            'kpi-total'             => new List<String>(),
            'kpi-verified'          => new List<String>{ 'Registration_Status__c IN (\'Onboarding In Progress\', \'Registered\', \'Initial Login Done\')' },
            'kpi-registered'        => new List<String>{ 'Registration_Status__c IN (\'Registered\', \'Initial Login Done\')' },
            'kpi-pending'           => new List<String>{ 'Registration_Status__c IN (\'Onboarding In Progress\')' },
            'kpi-unverified'        => new List<String>{ '(Registration_Status__c = null OR Registration_Status__c = \'Unregistered\')' },
            'kpi-active'            => new List<String>{ 'Registration_Status__c = \'Initial Login Done\'' }
        };
        for (KenLeadLifecycleService.StageMeta s : KenLeadLifecycleService.getStages()) {
            String pred = KenLeadLifecycleService.predicateFor(s.filterKey);
            if (String.isNotBlank(pred)) m.put(s.filterKey, new List<String>{ pred });
        }
        for (KenLeadLifecycleService.StageMeta s : KenLeadLifecycleService.getFunnelSteps()) {
            String pred = KenLeadLifecycleService.predicateFor(s.filterKey);
            if (String.isNotBlank(pred)) m.put(s.filterKey, new List<String>{ pred });
        }
        List<String> out = m.get(key);
        return out != null ? out : new List<String>();
    }

    private static Set<Id> resolveIssuePersonIds(String issueType) {
        String chip = String.isBlank(issueType) ? 'all' : issueType;
        List<Account> rows;
        if (chip == 'mail') {
            rows = [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonEmail = null WITH USER_MODE LIMIT 50000];
        } else if (chip == 'phone') {
            rows = [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonMobilePhone = null WITH USER_MODE LIMIT 50000];
        } else if (chip == 'invmail') {
            rows = [SELECT Id FROM Account WHERE IsPersonAccount = true AND PersonEmail != null AND (NOT PersonEmail LIKE '%@%.%') WITH USER_MODE LIMIT 50000];
        } else if (chip == 'bounce' || chip == 'invphone') {
            rows = new List<Account>();
        } else {
            rows = [SELECT Id FROM Account WHERE IsPersonAccount = true AND (PersonEmail = null OR PersonMobilePhone = null) WITH USER_MODE LIMIT 50000];
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
        WITH USER_MODE
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
            WITH USER_MODE
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
        List<String> conds = new List<String>{ LEAD_TAB_SCOPE };
        Map<String, Object> binds = new Map<String, Object>();
        if (String.isNotBlank(searchTerm)) {
            binds.put('bLeadSearch', '%' + searchTerm + '%');
            conds.add('(Name LIKE :bLeadSearch OR Email LIKE :bLeadSearch OR Company LIKE :bLeadSearch)');
        }
        // Lead-tab filters: every field the Lead itself carries. These mirror
        // leadFilterOptions() one for one — a dropdown that offers a value the
        // WHERE clause ignores looks broken, since applying it silently returns
        // the unfiltered list. Person-based filters (employment type, gender,
        // language, preference, skill, registration status) have no Lead
        // counterpart and the popup hides them on this tab.
        if (String.isNotBlank(filtersJson)) {
            try {
                Map<String, Object> f = (Map<String, Object>) JSON.deserializeUntyped(filtersJson);
                addLeadEq(conds, binds, 'bLdInstitute', 'Institution_Name__c', filterVal(f, 'institute'));
                addLeadEq(conds, binds, 'bLdGradYear', 'Year_of_Graduation__c', filterVal(f, 'graduationYear'));
                addLeadEq(conds, binds, 'bLdIntake', 'Program_Plan__r.Name', filterVal(f, 'intake'));
                addLeadEq(conds, binds, 'bLdCompany', 'Company', filterVal(f, 'company'));
                addLeadEq(conds, binds, 'bLdRole', 'Title', filterVal(f, 'role'));
                addLeadEq(conds, binds, 'bLdCity', 'City', filterVal(f, 'location'));
                addLeadEq(conds, binds, 'bLdCountry', 'Country', filterVal(f, 'country'));
                addLeadEq(conds, binds, 'bLdSource', 'LeadSource', filterVal(f, 'source'));

                String planV = filterVal(f, 'programPlan');
                if (planV == null) planV = filterVal(f, 'program');
                if (String.isNotBlank(planV)) {
                    if (isRecordId(planV)) {
                        // Older callers pass a LearningProgramPlan Id.
                        binds.put('bLdPlanId', (Id) planV);
                        conds.add('Program_Plan__c = :bLdPlanId');
                    } else {
                        // The dropdown value is the LearningProgram name; match
                        // the plan's own name too, for plans with no program.
                        binds.put('bLdPlan', planV);
                        conds.add('(' + PROGRAM_GROUP_FIELD + ' = :bLdPlan'
                            + ' OR Program_Plan__r.Name = :bLdPlan)');
                    }
                }
            } catch (Exception fEx) { /* ignore malformed filters */ }
        }
        String whereClause = ' WHERE ' + String.join(conds, ' AND ');

        result.totalRecords = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Lead' + whereClause,
            binds,
            AccessLevel.SYSTEM_MODE
        );

        binds.put('pageSize', pageSize);
        binds.put('offset', offset);
        List<Lead> leads = (List<Lead>) Database.queryWithBinds(
            'SELECT Id, Name, FirstName, LastName, Email, Phone, Company, Title, Status, ' +
            'LeadSource, City, Country, CreatedDate, LastModifiedDate, ' +
            'Year_of_Graduation__c, Registration_Number__c, Institution_Name__c, ' +
            'Program_Plan__c, Program_Plan__r.Name, ' +
            'Existing_Account__c, Existing_Account__r.Name, Constituent_Role_Type__c ' +
            'FROM Lead' + whereClause +
            ' ORDER BY CreatedDate DESC LIMIT :pageSize OFFSET :offset',
            binds,
            AccessLevel.SYSTEM_MODE
        );
        Map<Id, String> matchByLead = computeLeadMatchMergeBulk(leads);
        for (Lead ld : leads) {
            result.rows.add(toAlumniRowFromLead(ld, matchByLead.get(ld.Id)));
        }
        return result;
    }

    /** Appends `field = :bindName` to a Lead WHERE list, skipping blank values. */
    private static void addLeadEq(List<String> conds, Map<String, Object> binds, String bindName, String field, String value) {
        if (String.isBlank(value)) return;
        binds.put(bindName, value);
        conds.add(field + ' = :' + bindName);
    }

    /**
     * Whether a filter value is a real record Id. Length alone is not enough:
     * program names such as "B.A.Yogashastra" are exactly 15 characters, and
     * comparing a lookup field against one throws an uncatchable malformed-Id
     * error at query time.
     */
    private static Boolean isRecordId(String value) {
        if (String.isBlank(value)) return false;
        if (value.length() != 15 && value.length() != 18) return false;
        try {
            return Id.valueOf(value) != null;
        } catch (Exception idEx) {
            return false;
        }
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
            WITH USER_MODE
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
            WITH USER_MODE
            ]) {
                if (cr.PersonId != null) alumniPersonIds.add(cr.PersonId);
            }
        }

        Set<String> regsWithAlumni = new Set<String>();
        if (!regNums.isEmpty()) {
            for (ConstituentRole cr : [
                SELECT Registration_Number__c FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Registration_Number__c IN :regNums
            WITH USER_MODE
            ]) {
                if (String.isNotBlank(cr.Registration_Number__c)) regsWithAlumni.add(cr.Registration_Number__c);
            }
        }

        Map<String, Integer> leadEmailCount = new Map<String, Integer>();
        if (!emails.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Email e, COUNT(Id) c FROM Lead WHERE Email IN :emails
                WITH USER_MODE
                GROUP BY Email
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
            FROM ConstituentRole WHERE Id = :alumniId
            WITH USER_MODE
            LIMIT 1
        ];
        if (crs.isEmpty()) return null;
        ConstituentRole cr = crs[0];
        Account pa = null;
        if (cr.PersonId != null) {
            List<Account> accts = [
                SELECT Id, Name, FirstName, LastName, PersonEmail, PersonMobilePhone, PersonMailingCountry
                FROM Account WHERE Id = :cr.PersonId
                WITH USER_MODE
                LIMIT 1
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
        ConstituentRole cr = [SELECT Id, PersonId FROM ConstituentRole WHERE Id = :alumniId WITH USER_MODE LIMIT 1];
        if (cr.PersonId == null) {
            return new SaveResult(false, 'No linked Person Account on this constituent role.', null);
        }
        Account existing = [SELECT Id, IsPersonAccount FROM Account WHERE Id = :cr.PersonId WITH USER_MODE LIMIT 1];
        if (!existing.IsPersonAccount) {
            return new SaveResult(false, 'Linked Account is a Business Account — email cannot be saved via Person fields. Open the full profile to edit.', null);
        }
        Account acc = new Account(Id = existing.Id, PersonEmail = emailValue);
        if (!Schema.sObjectType.Account.isUpdateable()) {
            throw new KenCrudException('Account is not updateable by the current user.');
        }
        update acc;
        ContactIssue ci = getContactIssue(alumniId);
        return new SaveResult(true, 'Email saved.', ci.issuesRemaining);
    }

    @AuraEnabled
    public static SaveResult saveContactPhone(Id alumniId, String phoneValue) {
        if (String.isBlank(phoneValue)) {
            return new SaveResult(false, 'Phone is required.', null);
        }
        ConstituentRole cr = [SELECT Id, PersonId FROM ConstituentRole WHERE Id = :alumniId WITH USER_MODE LIMIT 1];
        if (cr.PersonId == null) {
            return new SaveResult(false, 'No linked Person Account on this constituent role.', null);
        }
        Account existing = [SELECT Id, IsPersonAccount FROM Account WHERE Id = :cr.PersonId WITH USER_MODE LIMIT 1];
        if (!existing.IsPersonAccount) {
            return new SaveResult(false, 'Linked Account is a Business Account — phone cannot be saved via Person fields. Open the full profile to edit.', null);
        }
        Account acc = new Account(Id = existing.Id, PersonMobilePhone = phoneValue);
        if (!Schema.sObjectType.Account.isUpdateable()) {
            throw new KenCrudException('Account is not updateable by the current user.');
        }
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
        if (isLeadId(alumniId)) return leadTimelineOf(alumniId);
        ConstituentRole cr = [
            SELECT Id, Source_Funnel__c, Registration_Status__c, PersonId,
                   CreatedDate, CreatedBy.Name, LastModifiedDate, LastModifiedBy.Name
            FROM ConstituentRole WHERE Id = :alumniId
            WITH USER_MODE
            LIMIT 1
        ];
        List<TimelineEntry> out = new List<TimelineEntry>();
        String src = cr.Source_Funnel__c;
        String createSource = String.isBlank(src) ? 'Manual' : src;
        out.add(new TimelineEntry('Constituent role created via ' + createSource,
            cr.CreatedBy != null ? cr.CreatedBy.Name : 'System', cr.CreatedDate, 'system', null));
        if (cr.LastModifiedDate != null && cr.LastModifiedDate != cr.CreatedDate) {
            out.add(new TimelineEntry('Status: ' + (cr.Registration_Status__c == null ? '—' : cr.Registration_Status__c),
                cr.LastModifiedBy != null ? cr.LastModifiedBy.Name : 'System', cr.LastModifiedDate, 'status', null));
        }
        // Logged communications + owner changes are Tasks on the person account.
        if (cr.PersonId != null) {
            try {
                for (Task t : [
                    SELECT Id, Subject, Description, CreatedDate, CreatedBy.Name
                    FROM Task WHERE WhatId = :cr.PersonId AND Subject LIKE '[%]%'
                    WITH USER_MODE
                    ORDER BY CreatedDate DESC LIMIT 30
                ]) {
                    String ch = channelFromSubject(t.Subject);
                    String rest = subjectRest(t.Subject);
                    String kind = ch == 'Owner' ? 'owner' : (ch == 'Note' ? 'note' : 'communication');
                    String label = ch + (String.isBlank(rest) ? '' : ' — ' + rest);
                    out.add(new TimelineEntry(label,
                        t.CreatedBy != null ? t.CreatedBy.Name : 'System', t.CreatedDate, kind, t.Description));
                }
            } catch (Exception ignored) { /* activities may be disabled */ }
        }
        try {
            for (FeedItem fi : [
                SELECT Id, Title, Body, CreatedDate, CreatedBy.Name, Type
                FROM FeedItem WHERE ParentId = :alumniId
                WITH USER_MODE
                ORDER BY CreatedDate DESC LIMIT 20
            ]) {
                String title = String.isBlank(fi.Title)
                    ? (String.isBlank(fi.Body) ? fi.Type : fi.Body.left(120))
                    : fi.Title;
                out.add(new TimelineEntry(title,
                    fi.CreatedBy != null ? fi.CreatedBy.Name : 'System', fi.CreatedDate, 'note', null));
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
        if (isLeadId(alumniId)) {
            List<FieldUpdate> leadOut = new List<FieldUpdate>();
            List<Lead> lds = [
                SELECT Id, Status, CreatedDate, LastModifiedDate, LastModifiedBy.Name
                FROM Lead WHERE Id = :alumniId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!lds.isEmpty() && lds[0].LastModifiedDate != lds[0].CreatedDate) {
                Lead ld = lds[0];
                leadOut.add(new FieldUpdate(ld.LastModifiedDate, 'Status', 'Previous snapshot',
                    String.isBlank(ld.Status) ? '—' : ld.Status, 'System',
                    ld.LastModifiedBy != null ? ld.LastModifiedBy.Name : 'System'));
            }
            return leadOut;
        }
        ConstituentRole cr = [
            SELECT Id, LastModifiedDate, LastModifiedBy.Name, CreatedDate, Registration_Status__c
            FROM ConstituentRole WHERE Id = :alumniId
            WITH USER_MODE
            LIMIT 1
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

    /* ============================================================
       LEAD OWNER — read via getAlumniDetail; reassign here. Owner is a
       standard ConstituentRole.OwnerId, so users and (supported) queues both
       work. Every change is logged to the activity feed as a Task.
       ============================================================ */
    @AuraEnabled(cacheable=true)
    public static List<OwnerOption> getAssignableOwners(String searchTerm) {
        List<OwnerOption> out = new List<OwnerOption>();
        String term = searchTerm == null ? '' : searchTerm.trim();
        String likeVar = '%' + String.escapeSingleQuotes(term) + '%';
        // Queues that actually accept ConstituentRole ownership.
        try {
            Set<Id> queueIds = new Set<Id>();
            for (QueueSobject qs : [SELECT QueueId FROM QueueSobject WHERE SobjectType = 'ConstituentRole' WITH SYSTEM_MODE]) {
                queueIds.add(qs.QueueId);
            }
            if (!queueIds.isEmpty()) {
                String qsoql = 'SELECT Id, Name FROM Group WHERE Type = \'Queue\' AND Id IN :queueIds';
                if (String.isNotBlank(term)) qsoql += ' AND Name LIKE :likeVar';
                qsoql += ' ORDER BY Name LIMIT 10';
                for (Group g : Database.query(qsoql)) {
                    out.add(new OwnerOption(g.Id, g.Name, 'Queue', 'Queue', computeInitials(g.Name)));
                }
            }
        } catch (Exception ignored) { /* queues may be unsupported for this object */ }
        // Active, real internal users only — UserType='Standard' filters out guest,
        // integration and automated-process users that can't meaningfully own a lead.
        String usoql = 'SELECT Id, Name, Title FROM User WHERE IsActive = true AND UserType = \'Standard\'';
        if (String.isNotBlank(term)) usoql += ' AND Name LIKE :likeVar';
        usoql += ' ORDER BY Name LIMIT 15';
        for (User u : Database.query(usoql)) {
            out.add(new OwnerOption(u.Id, u.Name, String.isBlank(u.Title) ? 'User' : u.Title, 'User', computeInitials(u.Name)));
        }
        return out;
    }

    @AuraEnabled
    public static SaveResult changeLeadOwner(Id alumniId, Id newOwnerId, String reason) {
        if (alumniId == null || newOwnerId == null) {
            return new SaveResult(false, 'Pick a record and a new owner first.', null);
        }
        try {
            if (isLeadId(alumniId)) {
                if (!Schema.sObjectType.Lead.isUpdateable()) {
                    throw new KenCrudException('Lead is not updateable by the current user.');
                }
                update new Lead(Id = alumniId, OwnerId = newOwnerId);
            } else {
                if (!Schema.sObjectType.ConstituentRole.isUpdateable()) {
                    throw new KenCrudException('ConstituentRole is not updateable by the current user.');
                }
                update new ConstituentRole(Id = alumniId, OwnerId = newOwnerId);
            }
            String newName = resolveOwnerName(newOwnerId);
            logTaskFor(alumniId, 'Owner', 'Reassigned to ' + newName, String.isBlank(reason) ? null : reason);
            return new SaveResult(true, 'Owner changed to ' + newName + '.', null);
        } catch (Exception e) {
            return new SaveResult(false, e.getMessage(), null);
        }
    }

    /* ============================================================
       LEAD COMMUNICATION — logged as standard Task/Activity on the person
       account (no new object). Live outbound send (email/SMS) is a later step.
       ============================================================ */
    @AuraEnabled
    public static SaveResult logCommunication(Id alumniId, String channel, String subject, String body, String outcome) {
        if (alumniId == null || String.isBlank(channel)) {
            return new SaveResult(false, 'Pick a record and a channel first.', null);
        }
        String ch = normalizeChannel(channel);
        String descText = body;
        if (String.isNotBlank(outcome)) {
            descText = (String.isBlank(body) ? '' : body + '\n\n') + 'Outcome: ' + outcome;
        }
        try {
            logTaskFor(alumniId, ch, String.isBlank(subject) ? ch : subject, descText);
            return new SaveResult(true, ch + ' logged to activity.', null);
        } catch (Exception e) {
            return new SaveResult(false, e.getMessage(), null);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<CommEntry> getCommunicationLog(Id alumniId) {
        List<CommEntry> out = new List<CommEntry>();
        if (alumniId == null) return out;
        List<Task> tasks;
        if (isLeadId(alumniId)) {
            tasks = [
                SELECT Id, Subject, Description, Status, CreatedDate, CreatedBy.Name
                FROM Task WHERE WhoId = :alumniId AND Subject LIKE '[%]%'
                WITH USER_MODE
                ORDER BY CreatedDate DESC LIMIT 30
            ];
        } else {
            Id personId = personIdFor(alumniId);
            if (personId == null) return out;
            tasks = [
                SELECT Id, Subject, Description, Status, CreatedDate, CreatedBy.Name
                FROM Task WHERE WhatId = :personId AND Subject LIKE '[%]%'
                WITH USER_MODE
                ORDER BY CreatedDate DESC LIMIT 30
            ];
        }
        try {
            for (Task t : tasks) {
                String ch = channelFromSubject(t.Subject);
                if (ch == 'Owner') continue; // owner changes belong to the activity feed
                CommEntry ce = new CommEntry();
                ce.taskId = t.Id;
                ce.channel = ch;
                ce.title = subjectRest(t.Subject);
                ce.body = t.Description;
                ce.status = String.isBlank(t.Status) ? 'Logged' : t.Status;
                ce.actor = t.CreatedBy != null ? t.CreatedBy.Name : 'System';
                ce.occurredAt = t.CreatedDate;
                out.add(ce);
            }
        } catch (Exception ignored) { /* activities may be disabled */ }
        return out;
    }

    /* ---- shared helpers for owner + communication ---- */
    private static void logTaskFor(Id alumniId, String channel, String subject, String body) {
        Task t = new Task(
            Subject = '[' + channel + '] ' + subject,
            Description = body,
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today()
        );
        if (isLeadId(alumniId)) {
            t.WhoId = alumniId;                 // Lead is a "who"
        } else {
            Id personId = personIdFor(alumniId);
            if (personId != null) t.WhatId = personId;
        }
        Database.insert(t, true, AccessLevel.USER_MODE);
    }
    private static Id personIdFor(Id alumniId) {
        List<ConstituentRole> rs = [SELECT PersonId FROM ConstituentRole WHERE Id = :alumniId WITH USER_MODE LIMIT 1];
        return rs.isEmpty() ? null : rs[0].PersonId;
    }

    // Activity timeline for a Lead-backed workspace row: capture + status + any
    // logged communications/owner changes (Tasks with WhoId = the lead).
    private static List<TimelineEntry> leadTimelineOf(Id leadId) {
        List<TimelineEntry> out = new List<TimelineEntry>();
        List<Lead> lds = [
            SELECT Id, Company, Status, CreatedDate, CreatedBy.Name, LastModifiedDate, LastModifiedBy.Name
            FROM Lead WHERE Id = :leadId
            WITH USER_MODE
            LIMIT 1
        ];
        if (lds.isEmpty()) return out;
        Lead ld = lds[0];
        out.add(new TimelineEntry('Lead captured' + (String.isBlank(ld.Company) ? '' : ' via ' + ld.Company),
            ld.CreatedBy != null ? ld.CreatedBy.Name : 'System', ld.CreatedDate, 'system', null));
        if (ld.LastModifiedDate != null && ld.LastModifiedDate != ld.CreatedDate) {
            out.add(new TimelineEntry('Status: ' + (String.isBlank(ld.Status) ? '—' : ld.Status),
                ld.LastModifiedBy != null ? ld.LastModifiedBy.Name : 'System', ld.LastModifiedDate, 'status', null));
        }
        try {
            for (Task t : [
                SELECT Id, Subject, Description, CreatedDate, CreatedBy.Name
                FROM Task WHERE WhoId = :leadId AND Subject LIKE '[%]%'
                WITH USER_MODE
                ORDER BY CreatedDate DESC LIMIT 30
            ]) {
                String ch = channelFromSubject(t.Subject);
                String rest = subjectRest(t.Subject);
                String kind = ch == 'Owner' ? 'owner' : (ch == 'Note' ? 'note' : 'communication');
                String label = ch + (String.isBlank(rest) ? '' : ' — ' + rest);
                out.add(new TimelineEntry(label, t.CreatedBy != null ? t.CreatedBy.Name : 'System', t.CreatedDate, kind, t.Description));
            }
        } catch (Exception ignored) { /* activities may be disabled */ }
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
    private static String resolveOwnerName(Id ownerId) {
        if (String.valueOf(ownerId).substring(0, 3) == '005') {
            List<User> us = [SELECT Name FROM User WHERE Id = :ownerId WITH USER_MODE LIMIT 1];
            return us.isEmpty() ? 'the new owner' : us[0].Name;
        }
        List<Group> gs = [SELECT Name FROM Group WHERE Id = :ownerId WITH SYSTEM_MODE LIMIT 1];
        return gs.isEmpty() ? 'the queue' : gs[0].Name;
    }
    private static String channelFromSubject(String subject) {
        if (String.isBlank(subject)) return 'Note';
        Matcher m = Pattern.compile('^\\[([^\\]]+)\\]').matcher(subject);
        return m.find() ? m.group(1) : 'Note';
    }
    private static String subjectRest(String subject) {
        if (String.isBlank(subject)) return '';
        return subject.replaceFirst('^\\[[^\\]]+\\]\\s*', '');
    }
    private static String normalizeChannel(String channel) {
        String c = channel == null ? '' : channel.toLowerCase();
        if (c == 'email') return 'Email';
        if (c == 'sms')   return 'SMS';
        if (c == 'call')  return 'Call';
        return 'Note';
    }
}