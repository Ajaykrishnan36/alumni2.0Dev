public with sharing class KenAlumniDashboardController {

    private static final Integer MAX_ROWS = 2000;
    private static final Integer MAX_CHART_ITEMS = 15;
    private static final Integer MAX_ALUMNI_LIST = 200;

    // ── Inner classes ────────────────────────────────────────────────────────

    public class ChartItem implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;

        public ChartItem(String lbl, Integer val) {
            this.label = String.isBlank(lbl) ? 'Not Specified' : lbl;
            this.value = val == null ? 0 : val;
        }

        public Integer compareTo(Object other) {
            ChartItem o = (ChartItem) other;
            if (this.value > o.value) return -1;
            if (this.value < o.value) return 1;
            return 0;
        }
    }

    public class AlumniRecord {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String batch;
        @AuraEnabled public String graduationYear;
        @AuraEnabled public String status;
        @AuraEnabled public String country;
    }

    public class SummaryStats {
        @AuraEnabled public Integer totalAlumni;
        @AuraEnabled public Integer activeAlumni;
        @AuraEnabled public Decimal activePercent;
        @AuraEnabled public Integer avgCompleteness;
    }

    public class FilterOptions {
        @AuraEnabled public List<PicklistOption> batches;
        @AuraEnabled public List<PicklistOption> years;
        public FilterOptions() {
            batches = new List<PicklistOption>();
            years   = new List<PicklistOption>();
        }
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String lbl, String val) {
            this.label = lbl;
            this.value = val;
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private static Set<Id> getAlumniIds() {
        Set<Id> ids = new Set<Id>();
        for (ConstituentRole cr : [
            SELECT PersonId FROM ConstituentRole
            WHERE RoleType = 'Alumni' AND PersonId != null
            LIMIT :MAX_ROWS
        ]) {
            ids.add(cr.PersonId);
        }
        return ids;
    }

    private static Set<Id> getFilteredAlumniIds(String fb, String fy, String fs) {
        List<String> conds = new List<String>{ 'RoleType = \'Alumni\'', 'PersonId != null' };
        if (!String.isBlank(fb) && fb != 'All')
            conds.add('Program_Plan__c = \'' + String.escapeSingleQuotes(fb) + '\'');
        if (!String.isBlank(fy) && fy != 'All')
            conds.add('Graduation_Year__c = \'' + String.escapeSingleQuotes(fy) + '\'');
        if (!String.isBlank(fs) && fs != 'All')
            conds.add('Status = \'' + String.escapeSingleQuotes(fs) + '\'');
        String q = 'SELECT PersonId FROM ConstituentRole WHERE '
            + String.join(conds, ' AND ') + ' LIMIT ' + MAX_ROWS;
        Set<Id> ids = new Set<Id>();
        for (SObject so : Database.query(q)) {
            Id pid = (Id) so.get('PersonId');
            if (pid != null) ids.add(pid);
        }
        return ids;
    }

    private static void tallyMultiSelect(Map<String, Integer> tally, String fieldVal) {
        if (String.isBlank(fieldVal)) return;
        for (String s : fieldVal.split(';')) {
            String key = s.trim();
            if (!String.isBlank(key))
                tally.put(key, (tally.containsKey(key) ? tally.get(key) : 0) + 1);
        }
    }

    private static List<AlumniRecord> buildAlumniRecords(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) return new List<AlumniRecord>();

        Map<Id, Account> accMap = new Map<Id, Account>([
            SELECT Id, Name, PersonMobilePhone, Phone, PersonEmail, BillingCountry
            FROM Account WHERE Id IN :ids LIMIT :MAX_ALUMNI_LIST
        ]);

        Map<Id, ConstituentRole> crMap = new Map<Id, ConstituentRole>();
        for (ConstituentRole cr : [
            SELECT PersonId, Program_Plan__r.Name, Graduation_Year__c, Status
            FROM ConstituentRole
            WHERE PersonId IN :ids AND RoleType = 'Alumni'
            LIMIT :MAX_ALUMNI_LIST
        ]) {
            crMap.put(cr.PersonId, cr);
        }

        List<AlumniRecord> results = new List<AlumniRecord>();
        for (Id aId : accMap.keySet()) {
            Account acc = accMap.get(aId);
            AlumniRecord rec = new AlumniRecord();
            rec.id    = aId;
            rec.name  = acc.Name;
            rec.email = acc.PersonEmail;
            rec.phone = String.isBlank(acc.PersonMobilePhone) ? acc.Phone : acc.PersonMobilePhone;
            rec.country = acc.BillingCountry;
            if (crMap.containsKey(aId)) {
                ConstituentRole cr = crMap.get(aId);
                rec.batch          = cr.Program_Plan__r != null ? cr.Program_Plan__r.Name : null;
                rec.graduationYear = cr.Graduation_Year__c;
                rec.status         = cr.Status;
            }
            results.add(rec);
        }
        return results;
    }

    // Profile score based on kenMyProfile fields: max 10 pts
    // 1-PersonEmail 2-PersonMobilePhone 3-Description(about) 4-LinkedIn
    // 5-ProfilePhoto 6-Specialization 7-GradYear(CRM)
    // 8-HasEducation 9-HasExperience 10-Program_Plan__c
    private static Map<Id, Integer> buildProfileScoreMap(Set<Id> alumniIds) {
        Map<Id, Integer> scoreMap = new Map<Id, Integer>();
        for (Id id : alumniIds) scoreMap.put(id, 0);

        for (Account acc : [
            SELECT Id, PersonEmail, PersonMobilePhone, Description, Linkedin_Profile_URL__c
            FROM Account WHERE Id IN :alumniIds LIMIT :MAX_ROWS
        ]) {
            Integer s = 0;
            if (!String.isBlank(acc.PersonEmail))               s++;
            if (!String.isBlank(acc.PersonMobilePhone))         s++;
            if (!String.isBlank(acc.Description))               s++;
            if (!String.isBlank(acc.Linkedin_Profile_URL__c))   s++;
            scoreMap.put(acc.Id, s);
        }

        for (Ken_Alumni_CRM__c crm : [
            SELECT Person_Account__c, Profile_Photo_URL__c, Specialization__c, Year_of_Graduation__c
            FROM Ken_Alumni_CRM__c WHERE Person_Account__c IN :alumniIds LIMIT :MAX_ROWS
        ]) {
            Integer cur = scoreMap.containsKey(crm.Person_Account__c) ? scoreMap.get(crm.Person_Account__c) : 0;
            if (!String.isBlank(crm.Profile_Photo_URL__c))    cur++;
            if (!String.isBlank(crm.Specialization__c))       cur++;
            if (!String.isBlank(crm.Year_of_Graduation__c))   cur++;
            scoreMap.put(crm.Person_Account__c, cur);
        }

        for (AggregateResult ar : [
            SELECT AccountId rid, COUNT(Id) cnt FROM PersonEducation
            WHERE AccountId IN :alumniIds AND (Is_Archived__c = false OR Is_Archived__c = null)
            GROUP BY AccountId
        ]) {
            Id aid = (Id) ar.get('rid');
            if (scoreMap.containsKey(aid) && (Integer) ar.get('cnt') > 0)
                scoreMap.put(aid, scoreMap.get(aid) + 1);
        }

        for (AggregateResult ar : [
            SELECT AccountId rid, COUNT(Id) cnt FROM PersonEmployment
            WHERE AccountId IN :alumniIds AND (Is_Archived__c = false OR Is_Archived__c = null)
            GROUP BY AccountId
        ]) {
            Id aid = (Id) ar.get('rid');
            if (scoreMap.containsKey(aid) && (Integer) ar.get('cnt') > 0)
                scoreMap.put(aid, scoreMap.get(aid) + 1);
        }

        for (ConstituentRole cr : [
            SELECT PersonId FROM ConstituentRole
            WHERE PersonId IN :alumniIds AND RoleType = 'Alumni' AND Program_Plan__c != null
            LIMIT :MAX_ROWS
        ]) {
            if (scoreMap.containsKey(cr.PersonId))
                scoreMap.put(cr.PersonId, scoreMap.get(cr.PersonId) + 1);
        }

        return scoreMap;
    }

    // ── Filter options ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static FilterOptions getFilterOptions() {
        try {
            FilterOptions opts = new FilterOptions();

            // Batches: raw SELECT avoids the 2,000-group aggregate cap.
            // Map.put deduplicates by Program_Plan__c Id automatically.
            Map<Id, String> batchMap = new Map<Id, String>();
            for (ConstituentRole cr : [
                SELECT Program_Plan__c, Program_Plan__r.Name
                FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Program_Plan__c != null
                LIMIT 50000
            ]) {
                batchMap.put(cr.Program_Plan__c, cr.Program_Plan__r.Name);
            }
            Map<String, Id> batchNameToId = new Map<String, Id>();
            for (Id pid : batchMap.keySet()) batchNameToId.put(batchMap.get(pid), pid);
            List<String> sortedBatchNames = new List<String>(batchNameToId.keySet());
            sortedBatchNames.sort();
            for (String name : sortedBatchNames)
                opts.batches.add(new PicklistOption(name, String.valueOf(batchNameToId.get(name))));

            // Years: raw SELECT deduped by Set, sorted in Apex.
            Set<String> yearSet = new Set<String>();
            for (ConstituentRole cr : [
                SELECT Graduation_Year__c
                FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Graduation_Year__c != null
                LIMIT 50000
            ]) {
                yearSet.add(cr.Graduation_Year__c);
            }
            List<String> sortedYears = new List<String>(yearSet);
            sortedYears.sort();
            for (String yr : sortedYears)
                opts.years.add(new PicklistOption(yr, yr));

            return opts;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Summary stats ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static SummaryStats getSummaryStats(String filterBatch, String filterYear, String filterStatus) {
        try {
            SummaryStats stats = new SummaryStats();
            List<String> conds = new List<String>{ 'RoleType = \'Alumni\'' };
            if (!String.isBlank(filterBatch) && filterBatch != 'All')
                conds.add('Program_Plan__c = \'' + String.escapeSingleQuotes(filterBatch) + '\'');
            if (!String.isBlank(filterYear) && filterYear != 'All')
                conds.add('Graduation_Year__c = \'' + String.escapeSingleQuotes(filterYear) + '\'');

            String baseWhere = String.join(conds, ' AND ');
            for (AggregateResult ar : Database.query(
                    'SELECT COUNT(Id) cnt FROM ConstituentRole WHERE ' + baseWhere)) {
                stats.totalAlumni = (Integer) ar.get('cnt');
            }
            for (AggregateResult ar : Database.query(
                    'SELECT COUNT(Id) cnt FROM ConstituentRole WHERE ' + baseWhere + ' AND Status = \'Active\'')) {
                stats.activeAlumni = (Integer) ar.get('cnt');
            }
            stats.activePercent = stats.totalAlumni > 0
                ? ((Decimal) stats.activeAlumni * 100 / stats.totalAlumni).setScale(1) : 0;

            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            if (!alumniIds.isEmpty()) {
                Map<Id, Integer> scoreMap = buildProfileScoreMap(alumniIds);
                Integer totalScore = 0;
                for (Integer sc : scoreMap.values()) totalScore += sc;
                stats.avgCompleteness = scoreMap.isEmpty() ? 0
                    : (Integer) Math.round((totalScore * 100.0) / (scoreMap.size() * 10));
            } else {
                stats.avgCompleteness = 0;
            }
            return stats;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 1. Active Alumni by Batch ────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getActiveAlumniByBatch(String filterBatch, String filterYear, String filterStatus) {
        try {
            List<String> conds = new List<String>{ 'RoleType = \'Alumni\'', 'Status = \'Active\'' };
            if (!String.isBlank(filterBatch) && filterBatch != 'All')
                conds.add('Program_Plan__c = \'' + String.escapeSingleQuotes(filterBatch) + '\'');
            if (!String.isBlank(filterYear) && filterYear != 'All')
                conds.add('Graduation_Year__c = \'' + String.escapeSingleQuotes(filterYear) + '\'');
            String q = 'SELECT Program_Plan__r.Name plan, COUNT(Id) cnt FROM ConstituentRole WHERE '
                + String.join(conds, ' AND ')
                + ' GROUP BY Program_Plan__r.Name ORDER BY COUNT(Id) DESC LIMIT ' + MAX_CHART_ITEMS;
            List<ChartItem> result = new List<ChartItem>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartItem(String.valueOf(ar.get('plan')), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 2. Graduation Year Distribution ─────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getGraduationYearDistribution(String filterBatch, String filterYear, String filterStatus) {
        try {
            List<String> conds = new List<String>{ 'RoleType = \'Alumni\'', 'Graduation_Year__c != null' };
            if (!String.isBlank(filterBatch) && filterBatch != 'All')
                conds.add('Program_Plan__c = \'' + String.escapeSingleQuotes(filterBatch) + '\'');
            if (!String.isBlank(filterStatus) && filterStatus != 'All')
                conds.add('Status = \'' + String.escapeSingleQuotes(filterStatus) + '\'');
            String q = 'SELECT Graduation_Year__c yr, COUNT(Id) cnt FROM ConstituentRole WHERE '
                + String.join(conds, ' AND ')
                + ' GROUP BY Graduation_Year__c ORDER BY Graduation_Year__c ASC LIMIT 20';
            List<ChartItem> result = new List<ChartItem>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartItem(String.valueOf(ar.get('yr')), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 3. Age Distribution ──────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getAgeDistribution(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            if (alumniIds.isEmpty()) return new List<ChartItem>{
                new ChartItem('Under 25', 0), new ChartItem('25–34', 0),
                new ChartItem('35–44', 0),   new ChartItem('45–54', 0),
                new ChartItem('55+', 0)
            };
            Integer under25 = 0, a2534 = 0, a3544 = 0, a4554 = 0, over55 = 0;
            Integer currentYear = Date.today().year();
            for (Account acc : [
                SELECT PersonBirthdate FROM Account
                WHERE Id IN :alumniIds AND PersonBirthdate != null AND IsPersonAccount = true
                LIMIT :MAX_ROWS
            ]) {
                Integer age = currentYear - acc.PersonBirthdate.year();
                if      (age < 25)  under25++;
                else if (age <= 34) a2534++;
                else if (age <= 44) a3544++;
                else if (age <= 54) a4554++;
                else                over55++;
            }
            return new List<ChartItem>{
                new ChartItem('Under 25', under25), new ChartItem('25–34', a2534),
                new ChartItem('35–44', a3544),      new ChartItem('45–54', a4554),
                new ChartItem('55+', over55)
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 4. Employment Status ─────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getEmploymentStatus(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            List<ChartItem> result = new List<ChartItem>();
            if (alumniIds.isEmpty()) return result;
            for (AggregateResult ar : [
                SELECT EmploymentStatus status, COUNT(Id) cnt
                FROM PersonEmployment
                WHERE RelatedPersonId IN :alumniIds AND Is_Archived__c = false
                GROUP BY EmploymentStatus ORDER BY COUNT(Id) DESC LIMIT :MAX_CHART_ITEMS
            ]) {
                result.add(new ChartItem((String) ar.get('status'), (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 5. Top Skills & Interests ────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getTopSkillsAndInterests(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            Map<String, Integer> tally = new Map<String, Integer>();
            if (!alumniIds.isEmpty()) {
                for (Ken_Alumni_Preferences__c pref : [
                    SELECT Skill_set__c, Mentorship_Expertise_Areas__c
                    FROM Ken_Alumni_Preferences__c
                    WHERE Person_Account__c IN :alumniIds
                    AND (Skill_set__c != null OR Mentorship_Expertise_Areas__c != null)
                    LIMIT :MAX_ROWS
                ]) {
                    tallyMultiSelect(tally, pref.Skill_set__c);
                    tallyMultiSelect(tally, pref.Mentorship_Expertise_Areas__c);
                }
            }
            List<ChartItem> result = new List<ChartItem>();
            for (String key : tally.keySet())
                result.add(new ChartItem(key, tally.get(key)));
            result.sort();
            if (result.size() > 12) {
                List<ChartItem> trimmed = new List<ChartItem>();
                for (Integer i = 0; i < 12; i++) trimmed.add(result[i]);
                return trimmed;
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 6. Lifecycle / Persona Stage ─────────────────────────────────────────
    // Stage is COMPUTED from activity + event participation + mentorship role
    // + preferences. No stored field is read (Persona_Stage__pc was removed).

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getLifecycleDistribution(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            if (alumniIds.isEmpty()) return new List<ChartItem>();

            Map<Id, String> stageById = computePersonaStageByAlumniId(alumniIds);
            Map<String, Integer> counts = new Map<String, Integer>();
            for (String stage : stageById.values()) {
                Integer prev = counts.containsKey(stage) ? counts.get(stage) : 0;
                counts.put(stage, prev + 1);
            }

            List<ChartItem> result = new List<ChartItem>();
            for (String stage : counts.keySet()) {
                result.add(new ChartItem(stage, counts.get(stage)));
            }
            result.sort(); // ChartItem.compareTo orders by value DESC
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static Map<Id, String> computePersonaStageByAlumniId(Set<Id> alumniIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (alumniIds == null || alumniIds.isEmpty()) return result;

        Map<Id, Ken_Alumni_CRM__c> crmByPa = new Map<Id, Ken_Alumni_CRM__c>();
        for (Ken_Alumni_CRM__c c : [
            SELECT Person_Account__c, Has_Logged_In_Once__c, Is_Active__c,
                   Last_Login_DateTime__c, Approval_Status__c
            FROM Ken_Alumni_CRM__c
            WHERE Person_Account__c IN :alumniIds
        ]) {
            if (c.Person_Account__c != null) crmByPa.put(c.Person_Account__c, c);
        }

        Set<Id> mentors = new Set<Id>();
        for (Ken_Mentorship__c m : [
            SELECT Mentor__c FROM Ken_Mentorship__c
            WHERE Mentor__c IN :alumniIds
        ]) {
            if (m.Mentor__c != null) mentors.add(m.Mentor__c);
        }

        Map<Id, Integer> eventsByPa = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Person_Account__c pa, COUNT(Id) cnt
            FROM Ken_Event_Booking__c
            WHERE Person_Account__c IN :alumniIds
            GROUP BY Person_Account__c
        ]) {
            Id pa = (Id) ar.get('pa');
            if (pa != null) eventsByPa.put(pa, (Integer) ar.get('cnt'));
        }

        Set<Id> willingMentors = new Set<Id>();
        Set<Id> openToWork = new Set<Id>();
        for (Ken_Alumni_Preferences__c p : [
            SELECT Person_Account__c, Willing_to_be_a_mentor__c, Open_to_work__c
            FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c IN :alumniIds
        ]) {
            if (p.Person_Account__c == null) continue;
            if (p.Willing_to_be_a_mentor__c == true) willingMentors.add(p.Person_Account__c);
            if (p.Open_to_work__c == true) openToWork.add(p.Person_Account__c);
        }

        Datetime ninetyDaysAgo = Datetime.now().addDays(-90);

        for (Id aId : alumniIds) {
            Ken_Alumni_CRM__c crm = crmByPa.get(aId);
            Boolean approved      = crm != null && crm.Approval_Status__c == 'Approved';
            Boolean hasLoggedIn   = crm != null && crm.Has_Logged_In_Once__c == true;
            Boolean isActiveFlag  = crm != null && crm.Is_Active__c == true;
            Boolean recentLogin   = crm != null && crm.Last_Login_DateTime__c != null
                                    && crm.Last_Login_DateTime__c >= ninetyDaysAgo;
            Boolean isMentor      = mentors.contains(aId);
            Integer eventsTotal   = eventsByPa.containsKey(aId) ? eventsByPa.get(aId) : 0;
            Boolean wantsMentor   = willingMentors.contains(aId);
            Boolean openWork      = openToWork.contains(aId);

            String stage;
            if (isMentor && eventsTotal >= 3 && recentLogin) {
                stage = 'Champion';
            } else if (isMentor) {
                stage = 'Mentor';
            } else if (recentLogin && eventsTotal > 0) {
                stage = 'Engaged';
            } else if (recentLogin || isActiveFlag) {
                stage = 'Active';
            } else if (hasLoggedIn) {
                stage = 'Onboarded';
            } else if (approved) {
                stage = 'Unregistered';
            } else if (wantsMentor || openWork) {
                stage = 'Prospect (Intent)';
            } else {
                stage = 'Prospect';
            }
            result.put(aId, stage);
        }
        return result;
    }

    // ── 7. Mobility by Country (world map feed) ──────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getMobilityByCountry(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            List<ChartItem> result = new List<ChartItem>();
            if (alumniIds.isEmpty()) return result;
            for (AggregateResult ar : [
                SELECT Country__c country, COUNT(Id) cnt
                FROM Ken_Address__c
                WHERE Person_Account__c IN :alumniIds AND Country__c != null
                GROUP BY Country__c ORDER BY COUNT(Id) DESC LIMIT :MAX_CHART_ITEMS
            ]) {
                result.add(new ChartItem((String) ar.get('country'), (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 8. India State Distribution (India map feed) ─────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getIndiaStateDistribution(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            List<ChartItem> result = new List<ChartItem>();
            if (alumniIds.isEmpty()) return result;
            for (AggregateResult ar : [
                SELECT State__c state, COUNT(Id) cnt
                FROM Ken_Address__c
                WHERE Person_Account__c IN :alumniIds
                AND Country__c = 'India' AND State__c != null
                GROUP BY State__c ORDER BY COUNT(Id) DESC LIMIT :MAX_CHART_ITEMS
            ]) {
                result.add(new ChartItem((String) ar.get('state'), (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 9. Profile Completeness ──────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getProfileCompleteness(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            if (alumniIds.isEmpty()) return new List<ChartItem>{
                new ChartItem('0–25%', 0), new ChartItem('26–50%', 0),
                new ChartItem('51–75%', 0), new ChartItem('76–100%', 0)
            };
            Map<Id, Integer> scoreMap = buildProfileScoreMap(alumniIds);
            Integer b1 = 0, b2 = 0, b3 = 0, b4 = 0;
            for (Integer score : scoreMap.values()) {
                Decimal pct = (score * 100.0) / 10;
                if      (pct <= 25) b1++;
                else if (pct <= 50) b2++;
                else if (pct <= 75) b3++;
                else                b4++;
            }
            return new List<ChartItem>{
                new ChartItem('0–25%', b1),  new ChartItem('26–50%', b2),
                new ChartItem('51–75%', b3), new ChartItem('76–100%', b4)
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 10. Batch Demographics ───────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getBatchDemographics(String filterBatch, String filterYear, String filterStatus) {
        try {
            List<String> conds = new List<String>{ 'RoleType = \'Alumni\'', 'Program_Plan__c != null' };
            if (!String.isBlank(filterYear) && filterYear != 'All')
                conds.add('Graduation_Year__c = \'' + String.escapeSingleQuotes(filterYear) + '\'');
            if (!String.isBlank(filterStatus) && filterStatus != 'All')
                conds.add('Status = \'' + String.escapeSingleQuotes(filterStatus) + '\'');
            String q = 'SELECT Program_Plan__r.Name plan, COUNT(Id) cnt FROM ConstituentRole WHERE '
                + String.join(conds, ' AND ')
                + ' GROUP BY Program_Plan__r.Name ORDER BY COUNT(Id) DESC LIMIT ' + MAX_CHART_ITEMS;
            List<ChartItem> result = new List<ChartItem>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartItem(String.valueOf(ar.get('plan')), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 11. Gender Distribution ──────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getGenderDistribution(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            List<ChartItem> result = new List<ChartItem>();
            if (alumniIds.isEmpty()) return result;
            for (AggregateResult ar : [
                SELECT PersonGenderIdentity gender, COUNT(Id) cnt
                FROM Account
                WHERE Id IN :alumniIds AND IsPersonAccount = true
                GROUP BY PersonGenderIdentity ORDER BY COUNT(Id) DESC
            ]) {
                result.add(new ChartItem((String) ar.get('gender'), (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 12. Registration Status ──────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getMultiDimensionalInsights(String filterBatch, String filterYear, String filterStatus) {
        try {
            List<String> conds = new List<String>{ 'RoleType = \'Alumni\'' };
            if (!String.isBlank(filterBatch) && filterBatch != 'All')
                conds.add('Program_Plan__c = \'' + String.escapeSingleQuotes(filterBatch) + '\'');
            if (!String.isBlank(filterYear) && filterYear != 'All')
                conds.add('Graduation_Year__c = \'' + String.escapeSingleQuotes(filterYear) + '\'');
            if (!String.isBlank(filterStatus) && filterStatus != 'All')
                conds.add('Status = \'' + String.escapeSingleQuotes(filterStatus) + '\'');
            String q = 'SELECT Registration_Status__c regStatus, COUNT(Id) cnt FROM ConstituentRole WHERE '
                + String.join(conds, ' AND ')
                + ' GROUP BY Registration_Status__c ORDER BY COUNT(Id) DESC LIMIT ' + MAX_CHART_ITEMS;
            List<ChartItem> result = new List<ChartItem>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartItem((String) ar.get('regStatus'), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 13. Professional Distribution ───────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getProfessionalDistribution(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            List<ChartItem> result = new List<ChartItem>();
            if (alumniIds.isEmpty()) return result;
            for (AggregateResult ar : [
                SELECT Occupation industry, COUNT(Id) cnt
                FROM PersonEmployment
                WHERE RelatedPersonId IN :alumniIds AND Is_Archived__c = false
                AND Occupation != null
                GROUP BY Occupation ORDER BY COUNT(Id) DESC LIMIT :MAX_CHART_ITEMS
            ]) {
                result.add(new ChartItem((String) ar.get('industry'), (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── 14. India State Distribution ─────────────────────────────────────────

    // ── 15. World Distribution (non-India) ───────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartItem> getWorldDistribution(String filterBatch, String filterYear, String filterStatus) {
        try {
            Set<Id> alumniIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            List<ChartItem> result = new List<ChartItem>();
            if (alumniIds.isEmpty()) return result;
            for (AggregateResult ar : [
                SELECT Country__c country, State__c state, COUNT(Id) cnt
                FROM Ken_Address__c
                WHERE Person_Account__c IN :alumniIds
                AND Country__c != null AND Country__c != 'India'
                GROUP BY Country__c, State__c ORDER BY COUNT(Id) DESC LIMIT :MAX_CHART_ITEMS
            ]) {
                String lbl = (String) ar.get('country');
                String st  = (String) ar.get('state');
                if (!String.isBlank(st)) lbl += ' / ' + st;
                result.add(new ChartItem(lbl, (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Alumni drill-down list ───────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<AlumniRecord> getAlumniList(
        String dimension, String dimensionValue,
        String filterBatch, String filterYear, String filterStatus
    ) {
        try {
            Set<Id> baseIds = getFilteredAlumniIds(filterBatch, filterYear, filterStatus);
            if (baseIds.isEmpty()) return new List<AlumniRecord>();

            Set<Id> filteredIds = new Set<Id>();
            String dv = String.escapeSingleQuotes(dimensionValue == null ? '' : dimensionValue);

            Boolean isNS = (dimensionValue == null || dimensionValue == 'Not Specified');

            if (dimension == 'batch') {
                if (isNS) {
                    for (ConstituentRole cr : [
                        SELECT PersonId FROM ConstituentRole
                        WHERE PersonId IN :baseIds AND RoleType = 'Alumni'
                        AND Program_Plan__c = null LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(cr.PersonId);
                } else {
                    for (ConstituentRole cr : [
                        SELECT PersonId FROM ConstituentRole
                        WHERE PersonId IN :baseIds AND RoleType = 'Alumni'
                        AND Program_Plan__r.Name = :dimensionValue LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(cr.PersonId);
                }

            } else if (dimension == 'year') {
                if (isNS) {
                    for (ConstituentRole cr : [
                        SELECT PersonId FROM ConstituentRole
                        WHERE PersonId IN :baseIds AND RoleType = 'Alumni'
                        AND Graduation_Year__c = null LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(cr.PersonId);
                } else {
                    for (ConstituentRole cr : [
                        SELECT PersonId FROM ConstituentRole
                        WHERE PersonId IN :baseIds AND RoleType = 'Alumni'
                        AND Graduation_Year__c = :dimensionValue LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(cr.PersonId);
                }

            } else if (dimension == 'gender') {
                if (isNS) {
                    for (Account acc : [
                        SELECT Id FROM Account
                        WHERE Id IN :baseIds AND (PersonGenderIdentity = null OR PersonGenderIdentity = '')
                        LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(acc.Id);
                } else {
                    for (Account acc : [
                        SELECT Id FROM Account
                        WHERE Id IN :baseIds AND PersonGenderIdentity = :dimensionValue
                        LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(acc.Id);
                }

            } else if (dimension == 'country') {
                for (Ken_Address__c addr : [
                    SELECT Person_Account__c FROM Ken_Address__c
                    WHERE Person_Account__c IN :baseIds AND Country__c = :dimensionValue
                    LIMIT :MAX_ALUMNI_LIST
                ]) filteredIds.add(addr.Person_Account__c);

            } else if (dimension == 'region') {
                // dimensionValue format: "Country" or "Country / State"
                List<String> parts = dimensionValue.split(' / ');
                String regionCountry = parts[0].trim();
                String regionState   = parts.size() > 1 ? parts[1].trim() : null;
                if (String.isBlank(regionState)) {
                    for (Ken_Address__c addr : [
                        SELECT Person_Account__c FROM Ken_Address__c
                        WHERE Person_Account__c IN :baseIds AND Country__c = :regionCountry
                        LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(addr.Person_Account__c);
                } else {
                    for (Ken_Address__c addr : [
                        SELECT Person_Account__c FROM Ken_Address__c
                        WHERE Person_Account__c IN :baseIds
                        AND Country__c = :regionCountry AND State__c = :regionState
                        LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(addr.Person_Account__c);
                }

            } else if (dimension == 'state') {
                for (Ken_Address__c addr : [
                    SELECT Person_Account__c FROM Ken_Address__c
                    WHERE Person_Account__c IN :baseIds AND State__c = :dimensionValue
                    LIMIT :MAX_ALUMNI_LIST
                ]) filteredIds.add(addr.Person_Account__c);

            } else if (dimension == 'employment') {
                if (isNS) {
                    for (PersonEmployment pe : [
                        SELECT RelatedPersonId FROM PersonEmployment
                        WHERE RelatedPersonId IN :baseIds
                        AND (EmploymentStatus = null OR EmploymentStatus = '')
                        AND Is_Archived__c = false LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(pe.RelatedPersonId);
                } else {
                    for (PersonEmployment pe : [
                        SELECT RelatedPersonId FROM PersonEmployment
                        WHERE RelatedPersonId IN :baseIds AND EmploymentStatus = :dimensionValue
                        AND Is_Archived__c = false LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(pe.RelatedPersonId);
                }

            } else if (dimension == 'profession') {
                if (isNS) {
                    for (PersonEmployment pe : [
                        SELECT RelatedPersonId FROM PersonEmployment
                        WHERE RelatedPersonId IN :baseIds
                        AND (Occupation = null OR Occupation = '')
                        AND Is_Archived__c = false LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(pe.RelatedPersonId);
                } else {
                    for (PersonEmployment pe : [
                        SELECT RelatedPersonId FROM PersonEmployment
                        WHERE RelatedPersonId IN :baseIds AND Occupation = :dimensionValue
                        AND Is_Archived__c = false LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(pe.RelatedPersonId);
                }

            } else if (dimension == 'lifecycle') {
                // Drilldown by COMPUTED persona stage — derived from activity,
                // events, mentorship, preferences (no stored field).
                Map<Id, String> stageById = computePersonaStageByAlumniId(baseIds);
                for (Id alumniId : stageById.keySet()) {
                    String stage = stageById.get(alumniId);
                    Boolean match = isNS ? String.isBlank(stage) : (stage == dimensionValue);
                    if (match) {
                        filteredIds.add(alumniId);
                        if (filteredIds.size() >= MAX_ALUMNI_LIST) break;
                    }
                }

            } else if (dimension == 'registration') {
                if (isNS) {
                    for (ConstituentRole cr : [
                        SELECT PersonId FROM ConstituentRole
                        WHERE PersonId IN :baseIds AND RoleType = 'Alumni'
                        AND (Registration_Status__c = null OR Registration_Status__c = '') LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(cr.PersonId);
                } else {
                    for (ConstituentRole cr : [
                        SELECT PersonId FROM ConstituentRole
                        WHERE PersonId IN :baseIds AND RoleType = 'Alumni'
                        AND Registration_Status__c = :dimensionValue LIMIT :MAX_ALUMNI_LIST
                    ]) filteredIds.add(cr.PersonId);
                }

            } else if (dimension == 'interests') {
                String safeVal = String.escapeSingleQuotes(dimensionValue);
                String interestsQ = 'SELECT Person_Account__c FROM Ken_Alumni_Preferences__c'
                    + ' WHERE Person_Account__c IN :baseIds'
                    + ' AND (Skill_set__c INCLUDES (\'' + safeVal + '\')'
                    + ' OR Mentorship_Expertise_Areas__c INCLUDES (\'' + safeVal + '\'))'
                    + ' LIMIT ' + MAX_ALUMNI_LIST;
                for (SObject so : Database.query(interestsQ))
                    filteredIds.add((Id) so.get('Person_Account__c'));

            } else if (dimension == 'age') {
                Integer currentYear = Date.today().year();
                Integer minAge = 0, maxAge = 999;
                if (dimensionValue == 'Under 25') { minAge = 0;  maxAge = 24; }
                else if (dimensionValue == '25–34') { minAge = 25; maxAge = 34; }
                else if (dimensionValue == '35–44') { minAge = 35; maxAge = 44; }
                else if (dimensionValue == '45–54') { minAge = 45; maxAge = 54; }
                else if (dimensionValue == '55+')         { minAge = 55; maxAge = 999; }
                for (Account acc : [
                    SELECT Id, PersonBirthdate FROM Account
                    WHERE Id IN :baseIds AND PersonBirthdate != null LIMIT :MAX_ROWS
                ]) {
                    Integer age = currentYear - acc.PersonBirthdate.year();
                    if (age >= minAge && age <= maxAge) filteredIds.add(acc.Id);
                }

            } else if (dimension == 'completeness') {
                // Return top/bottom alumni by completeness bucket
                filteredIds.addAll(baseIds);
            } else {
                filteredIds.addAll(baseIds);
            }

            return buildAlumniRecords(filteredIds);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}