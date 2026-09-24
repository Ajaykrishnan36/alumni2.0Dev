public with sharing class KenAlumniAdminDashboardController {

    public class DashboardMetrics {
        @AuraEnabled public Integer totalAlumni;
        @AuraEnabled public Integer institutionVerified;
        @AuraEnabled public Integer portalRegistered;
        @AuraEnabled public Integer pendingActivation;
        @AuraEnabled public Integer unverifiedLeads;
        @AuraEnabled public Integer registeredAlumni;
        @AuraEnabled public Integer activeAlumni;
    }

    public class FunnelStep {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        public FunnelStep(String l, Integer v) { label = l; value = v; }
    }

    public class FunnelData {
        @AuraEnabled public String funnelKey;
        @AuraEnabled public String title;
        @AuraEnabled public List<FunnelStep> steps;
    }

    public class SourceSlice {
        @AuraEnabled public String label;
        @AuraEnabled public Integer value;
        public SourceSlice(String l, Integer v) { label = l; value = v; }
    }

    public class HealthBar {
        @AuraEnabled public String field;
        @AuraEnabled public Integer percent;
        @AuraEnabled public Boolean warning;
        public HealthBar(String f, Integer p, Boolean w) { field = f; percent = p; warning = w; }
    }

    public class TrendPoint {
        @AuraEnabled public String label;
        @AuraEnabled public Integer registered;
        @AuraEnabled public Integer invited;
        @AuraEnabled public Integer active;
        public TrendPoint(String l, Integer r, Integer i, Integer a) { label = l; registered = r; invited = i; active = a; }
    }

    public class EngagementChannel {
        @AuraEnabled public String channel;
        @AuraEnabled public Decimal reachPct;
        @AuraEnabled public Integer engaged;
        @AuraEnabled public Integer active90d;
        @AuraEnabled public Integer repeatRatePct;
        @AuraEnabled public Integer newPerMonth;
        @AuraEnabled public Boolean trendingUp;
        @AuraEnabled public String insight;
        public EngagementChannel(String c, Decimal r, Integer e, Integer a90, Integer rr, Integer nm, Boolean up, String ins) {
            channel = c; reachPct = r; engaged = e; active90d = a90;
            repeatRatePct = rr; newPerMonth = nm; trendingUp = up; insight = ins;
        }
    }

    public class ActivityItem {
        @AuraEnabled public String title;
        @AuraEnabled public String actor;
        @AuraEnabled public Datetime occurredAt;
        public ActivityItem(String t, String a, Datetime ts) { title = t; actor = a; occurredAt = ts; }
    }

    public class ActionItem {
        @AuraEnabled public String message;
        @AuraEnabled public String ctaLabel;
        @AuraEnabled public String ctaKey;
        public ActionItem(String m, String c, String k) { message = m; ctaLabel = c; ctaKey = k; }
    }

    public class CompletenessBucket {
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
        @AuraEnabled public Integer percent;
        public CompletenessBucket(String l, Integer c, Integer p) { label = l; count = c; percent = p; }
    }

    public class AgeBucket {
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
        public AgeBucket(String l, Integer c) { label = l; count = c; }
    }

    public class EmploymentSlice {
        @AuraEnabled public String label;
        @AuraEnabled public Integer count;
        @AuraEnabled public Integer percent;
        public EmploymentSlice(String l, Integer c, Integer p) { label = l; count = c; percent = p; }
    }

    public class RegionRow {
        @AuraEnabled public String city;
        @AuraEnabled public Integer count;
        @AuraEnabled public Integer percent;
        public RegionRow(String c, Integer n, Integer p) { city = c; count = n; percent = p; }
    }

    public class CommsSnapshot {
        @AuraEnabled public Integer messagesSent;
        @AuraEnabled public Integer campaigns;
        @AuraEnabled public Decimal deliveryPct;
        @AuraEnabled public Decimal bouncedPct;
        @AuraEnabled public Decimal openRatePct;
        @AuraEnabled public Decimal clickRatePct;
        @AuraEnabled public Integer emailSent;
        @AuraEnabled public Integer whatsappSent;
        @AuraEnabled public Integer smsSent;
        @AuraEnabled public Integer scheduled;
        @AuraEnabled public Integer awaitingReply;
    }

    /**
     * Source of truth: ConstituentRole (RoleType='Alumni') + Registration_Status__c.
     *   Unregistered     -> in master but no portal action
     *   Verified         -> matched against institute records, invite-ready
     *   Registered       -> claimed portal account
     *   Initial Login Done -> has signed in at least once (counts as registered+active)
     */
    @AuraEnabled(cacheable=true)
    public static DashboardMetrics getDashboardMetrics() {
        DashboardMetrics m = new DashboardMetrics();
        m.totalAlumni        = [SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni' WITH USER_MODE];
        m.institutionVerified = [
            SELECT COUNT() FROM ConstituentRole
            WHERE RoleType = 'Alumni'
            AND Registration_Status__c IN ('Onboarding In Progress', 'Registered', 'Initial Login Done')
        WITH USER_MODE
        ];
        m.portalRegistered = [
            SELECT COUNT() FROM ConstituentRole
            WHERE RoleType = 'Alumni'
            AND Registration_Status__c IN ('Registered', 'Onboarding In Progress', 'Initial Login Done')
        WITH USER_MODE
        ];
        m.pendingActivation = m.institutionVerified - m.portalRegistered;
        if (m.pendingActivation < 0) m.pendingActivation = 0;
        m.unverifiedLeads = KenLeadLifecycleService.countFor('life-leads');
        m.registeredAlumni = m.portalRegistered;
        m.activeAlumni = KenLeadLifecycleService.countFor('life-active');
        return m;
    }

    /**
     * @description Single lifecycle funnel that walks the seven canonical stages
     *              defined in KenLeadLifecycleService (Lead -> Active). Replaces
     *              the previous source-specific funnels on the dashboard.
     */
    @AuraEnabled(cacheable=true)
    public static FunnelData getLifecycleFunnel() {
        FunnelData f = new FunnelData();
        f.funnelKey = 'lifecycle';
        f.title = 'Lead Lifecycle';
        f.steps = new List<FunnelStep>();
        for (KenLeadLifecycleService.StageMeta s : KenLeadLifecycleService.getFunnelSteps()) {
            f.steps.add(new FunnelStep(s.label, KenLeadLifecycleService.countFor(s.filterKey)));
        }
        return f;
    }

    @AuraEnabled(cacheable=true)
    public static FunnelData getFunnelData(String funnelKey) {
        FunnelData f = new FunnelData();
        f.funnelKey = funnelKey;
        f.steps = new List<FunnelStep>();

        if (funnelKey == 'transition') {
            f.title = 'Student-to-Alumni Transition';
            Integer cohort = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Source_Funnel__c = 'Student-to-Alumni Transition'
            WITH USER_MODE
            ];
            Integer invited = cohort;
            Integer registered = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Source_Funnel__c = 'Student-to-Alumni Transition'
                AND Last_Login__c != null
            WITH USER_MODE
            ];
            Integer active = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Source_Funnel__c = 'Student-to-Alumni Transition'
                AND Status != 'Former'
            WITH USER_MODE
            ];
            f.steps.add(new FunnelStep('Graduating Cohort', cohort));
            f.steps.add(new FunnelStep('Invited to Portal', invited));
            f.steps.add(new FunnelStep('Registered', registered));
            f.steps.add(new FunnelStep('Active', active));

        } else if (funnelKey == 'leads') {
            f.title = 'Leads & Referrals';
            Set<String> leadSources = new Set<String>{'Self-Declared Lead', 'Campaign Lead', 'Alumni Referral'};
            Integer leads = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Source_Funnel__c IN :leadSources
            WITH USER_MODE
            ];
            Integer verified = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Source_Funnel__c IN :leadSources
                AND Registration_Status__c != null
            WITH USER_MODE
            ];
            Integer registered = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Source_Funnel__c IN :leadSources
                AND Last_Login__c != null
            WITH USER_MODE
            ];
            Integer active = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Source_Funnel__c IN :leadSources
                AND Status != 'Former'
            WITH USER_MODE
            ];
            f.steps.add(new FunnelStep('Leads', leads));
            f.steps.add(new FunnelStep('Verified', verified));
            f.steps.add(new FunnelStep('Registered', registered));
            f.steps.add(new FunnelStep('Active', active));

        } else {
            f.title = 'All Data Upload';
            Integer uploaded = [SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni' WITH USER_MODE];
            Integer available = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni'
                AND Registration_Status__c IN ('Onboarding In Progress', 'Registered', 'Initial Login Done')
            WITH USER_MODE
            ];
            Integer registered = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni'
                AND Registration_Status__c IN ('Registered', 'Initial Login Done')
            WITH USER_MODE
            ];
            Integer active = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni'
                AND Registration_Status__c = 'Initial Login Done'
            WITH USER_MODE
            ];
            f.steps.add(new FunnelStep('Records Uploaded', uploaded));
            f.steps.add(new FunnelStep('Data Available', available));
            f.steps.add(new FunnelStep('Registered', registered));
            f.steps.add(new FunnelStep('Active', active));
        }
        return f;
    }

    @AuraEnabled(cacheable=true)
    public static List<SourceSlice> getSourceDistribution() {
        List<SourceSlice> slices = new List<SourceSlice>();
        AggregateResult[] rows = [
            SELECT Source_Funnel__c src, COUNT(Id) cnt
            FROM ConstituentRole
            WHERE RoleType = 'Alumni'
            WITH USER_MODE
            GROUP BY Source_Funnel__c
            ORDER BY COUNT(Id) DESC
            LIMIT 10
        ];
        for (AggregateResult r : rows) {
            String label = (String) r.get('src');
            if (String.isBlank(label)) label = 'Unspecified';
            slices.add(new SourceSlice(label, (Integer) r.get('cnt')));
        }
        return slices;
    }

    @AuraEnabled(cacheable=true)
    public static List<HealthBar> getDataHealthBreakdown() {
        List<HealthBar> bars = new List<HealthBar>();
        Integer total = [SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni' WITH USER_MODE];
        if (total == 0) return bars;
        Date twelveMonthsAgo = Date.today().addMonths(-12);
        bars.add(pct('Valid Email', [
            SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni'
            AND PersonId IN (SELECT Id FROM Account WHERE PersonEmail != null)
        WITH USER_MODE
        ], total));
        bars.add(pct('Phone', [
            SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni'
            AND PersonId IN (SELECT Id FROM Account WHERE PersonMobilePhone != null)
        WITH USER_MODE
        ], total));
        bars.add(pct('LinkedIn', [
            SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni'
            AND PersonId IN (SELECT Id FROM Account WHERE Linkedin_Profile_URL__c != null)
        WITH USER_MODE
        ], total));
        bars.add(pct('Location', [
            SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni'
            AND PersonId IN (SELECT Person_Account__c FROM Ken_Address__c WHERE Address_Type__c = 'Mailing')
        WITH USER_MODE
        ], total));
        bars.add(pct('Company', [
            SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni'
            AND PersonId IN (
                SELECT AccountId FROM PersonEmployment
                WHERE Company_Name__c != null AND (Is_Archived__c = false OR Is_Archived__c = null)
            )
        WITH USER_MODE
        ], total));
        bars.add(pct('Program/Batch', [
            SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni' AND Program_Plan__c != null
        WITH USER_MODE
        ], total));
        bars.add(pct('Consent', [
            SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni'
            AND PersonId IN (SELECT Id FROM Account WHERE Agree_to_T_C__c = true)
        WITH USER_MODE
        ], total));
        bars.add(pct('Updated <12mo', [
            SELECT COUNT() FROM ConstituentRole
            WHERE RoleType = 'Alumni' AND LastModifiedDate >= :twelveMonthsAgo
        WITH USER_MODE
        ], total));
        return bars;
    }

    @AuraEnabled(cacheable=true)
    public static List<TrendPoint> getOnboardingTrend() {
        List<TrendPoint> series = new List<TrendPoint>();
        Date today = Date.today();
        for (Integer i = 5; i >= 0; i--) {
            Date monthStart = today.toStartOfMonth().addMonths(-i);
            Date monthEnd = monthStart.addMonths(1).addDays(-1);
            Integer registered = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni'
                AND EffectiveStartDate >= :monthStart AND EffectiveStartDate <= :monthEnd
            WITH USER_MODE
            ];
            Integer active = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni'
                AND EffectiveStartDate >= :monthStart AND EffectiveStartDate <= :monthEnd
                AND Status != 'Former'
            WITH USER_MODE
            ];
            series.add(new TrendPoint(shortMonth(monthStart.month()), registered, registered, active));
        }
        return series;
    }

    @AuraEnabled(cacheable=true)
    public static List<EngagementChannel> getEngagementSummary() {
        Integer totalAlumni = [SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni' WITH USER_MODE];
        List<EngagementChannel> channels = new List<EngagementChannel>();
        channels.add(buildEvents(totalAlumni));
        channels.add(buildMentorship(totalAlumni));
        channels.add(buildDonations(totalAlumni));
        channels.add(buildSurveys(totalAlumni));
        channels.add(buildGroups(totalAlumni));
        return channels;
    }

    private static EngagementChannel buildDonations(Integer baseTotal) {
        return new EngagementChannel('Donations', 0, 0, 0, 0, 0, false,
            'No donation tracking object configured.');
    }

    @AuraEnabled(cacheable=true)
    public static List<ActivityItem> getRecentActivity() {
        List<ActivityItem> items = new List<ActivityItem>();
        Datetime lookback = Datetime.now().addDays(-30);
        Set<Id> alumniAccountIds = new Set<Id>();
        for (ConstituentRole cr : [
            SELECT PersonId, LastModifiedDate, LastModifiedBy.Name,
                   Registration_Status__c, CreatedDate
            FROM ConstituentRole
            WHERE RoleType = 'Alumni'
            AND PersonId != null
            AND LastModifiedDate >= :lookback
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC LIMIT 20
        ]) {
            alumniAccountIds.add(cr.PersonId);
            String actor = cr.LastModifiedBy != null ? cr.LastModifiedBy.Name : 'System';
            String label = cr.LastModifiedDate == cr.CreatedDate
                ? 'Alumni role created (' + cr.Registration_Status__c + ')'
                : 'Status updated → ' + cr.Registration_Status__c;
            items.add(new ActivityItem(label, actor, cr.LastModifiedDate));
        }
        if (!alumniAccountIds.isEmpty()) {
            for (Account acc : [
                SELECT Id, Name, LastModifiedDate, LastModifiedBy.Name
                FROM Account
                WHERE Id IN :alumniAccountIds
                AND LastModifiedDate >= :lookback
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC LIMIT 20
            ]) {
                items.add(new ActivityItem('Profile updated: ' + acc.Name,
                    acc.LastModifiedBy != null ? acc.LastModifiedBy.Name : 'System',
                    acc.LastModifiedDate));
            }
        }
        for (ConstituentRole row : [
            SELECT Id, Name, LastModifiedDate, CreatedDate, LastModifiedBy.Name
            FROM ConstituentRole
            WHERE RoleType = 'Alumni' AND LastModifiedDate >= :lookback
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC LIMIT 10
        ]) {
            String actor = row.LastModifiedBy != null ? row.LastModifiedBy.Name : 'System';
            String label = row.LastModifiedDate == row.CreatedDate
                ? 'Record created: ' + row.Name
                : 'Record updated: ' + row.Name;
            items.add(new ActivityItem(label, actor, row.LastModifiedDate));
        }
        try {
            for (FeedItem fi : [
                SELECT Id, Title, Body, Type, CreatedDate, CreatedBy.Name, ParentId
                FROM FeedItem
                WHERE CreatedDate >= :lookback
                AND Parent.Type = 'ConstituentRole'
                WITH USER_MODE
                ORDER BY CreatedDate DESC LIMIT 10
            ]) {
                String t = String.isBlank(fi.Title)
                    ? (String.isBlank(fi.Body) ? fi.Type : fi.Body.left(80))
                    : fi.Title;
                items.add(new ActivityItem(t,
                    fi.CreatedBy != null ? fi.CreatedBy.Name : 'System', fi.CreatedDate));
            }
        } catch (Exception ignored) { /* feeds may be disabled */ }
        // Sort newest first, return top 5
        for (Integer i = 1; i < items.size(); i++) {
            ActivityItem cur = items[i];
            Integer j = i - 1;
            while (j >= 0 && items[j].occurredAt < cur.occurredAt) {
                items[j + 1] = items[j];
                j--;
            }
            items[j + 1] = cur;
        }
        if (items.size() > 5) {
            List<ActivityItem> top = new List<ActivityItem>();
            for (Integer i = 0; i < 5; i++) top.add(items[i]);
            return top;
        }
        return items;
    }

    @AuraEnabled(cacheable=true)
    public static List<ActionItem> getSuggestedActions() {
        List<ActionItem> actions = new List<ActionItem>();
        Integer pending = [
            SELECT COUNT() FROM ConstituentRole
            WHERE RoleType = 'Alumni' AND Last_Login__c = null AND Registration_Status__c != null
        WITH USER_MODE
        ];
        Integer totalRoles = [SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni' WITH USER_MODE];
        Integer haveCompanyAndLocation = [
            SELECT COUNT() FROM ConstituentRole
            WHERE RoleType = 'Alumni'
            AND PersonId IN (
                SELECT AccountId FROM PersonEmployment
                WHERE Company_Name__c != null AND (Is_Archived__c = false OR Is_Archived__c = null)
            )
            AND PersonId IN (
                SELECT Person_Account__c FROM Ken_Address__c WHERE Address_Type__c = 'Mailing'
            )
        WITH USER_MODE
        ];
        Integer dataMissing = totalRoles - haveCompanyAndLocation;
        if (pending > 0) {
            actions.add(new ActionItem(
                'Invite ' + pending + ' verified alumni who have not activated their portal account',
                'Start Invite', 'invite-verified'
            ));
        }
        if (dataMissing > 0) {
            actions.add(new ActionItem(
                'Send a profile completion request to ' + dataMissing + ' alumni missing company/location',
                'Create Request', 'request-completion'
            ));
        }
        return actions;
    }

    @AuraEnabled(cacheable=true)
    public static List<CompletenessBucket> getProfileCompleteness(String audience) {
        List<ConstituentRole> rows;
        if (isActiveAudience(audience)) {
            Set<Id> personIds = activeAudiencePersonIds();
            rows = [
                SELECT PersonId, Program_Plan__c, Graduation_Year__c, Registration_Number__c
                FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND PersonId IN :personIds
            WITH USER_MODE
            ];
        } else {
            rows = [
                SELECT PersonId, Program_Plan__c, Graduation_Year__c, Registration_Number__c
                FROM ConstituentRole
                WHERE RoleType = 'Alumni'
            WITH USER_MODE
            ];
        }

        Set<Id> rolePersonIds = new Set<Id>();
        for (ConstituentRole r : rows) {
            if (r.PersonId != null) rolePersonIds.add(r.PersonId);
        }
        Set<Id> withEmail = new Set<Id>();
        Set<Id> withCompany = new Set<Id>();
        Set<Id> withLocation = new Set<Id>();
        if (!rolePersonIds.isEmpty()) {
            for (Account a : [
                SELECT Id FROM Account WHERE Id IN :rolePersonIds AND PersonEmail != null
            WITH USER_MODE
            ]) {
                withEmail.add(a.Id);
            }
            for (PersonEmployment pe : [
                SELECT AccountId FROM PersonEmployment
                WHERE AccountId IN :rolePersonIds AND Company_Name__c != null
                  AND (Is_Archived__c = false OR Is_Archived__c = null)
            WITH USER_MODE
            ]) {
                withCompany.add(pe.AccountId);
            }
            for (Ken_Address__c addr : [
                SELECT Person_Account__c FROM Ken_Address__c
                WHERE Person_Account__c IN :rolePersonIds AND Address_Type__c = 'Mailing'
            WITH USER_MODE
            ]) {
                withLocation.add(addr.Person_Account__c);
            }
        }

        Integer total = rows.size();
        Map<String, Integer> buckets = new Map<String, Integer>{
            '90–100%' => 0, '70–89%' => 0, '50–69%' => 0, '30–49%' => 0, '<30%' => 0
        };
        for (ConstituentRole r : rows) {
            Integer filled = 0;
            Integer slots = 6;
            if (r.Program_Plan__c != null) filled++;
            if (String.isNotBlank(r.Graduation_Year__c)) filled++;
            if (String.isNotBlank(r.Registration_Number__c)) filled++;
            if (withCompany.contains(r.PersonId)) filled++;
            if (withLocation.contains(r.PersonId)) filled++;
            if (withEmail.contains(r.PersonId)) filled++;
            Integer pct = (Integer) Math.round(100.0 * filled / slots);
            String key;
            if (pct >= 90) key = '90–100%';
            else if (pct >= 70) key = '70–89%';
            else if (pct >= 50) key = '50–69%';
            else if (pct >= 30) key = '30–49%';
            else key = '<30%';
            buckets.put(key, buckets.get(key) + 1);
        }
        List<CompletenessBucket> out = new List<CompletenessBucket>();
        List<String> order = new List<String>{'90–100%', '70–89%', '50–69%', '30–49%', '<30%'};
        for (String k : order) {
            Integer c = buckets.get(k);
            Integer p = total == 0 ? 0 : (Integer) Math.round(100.0 * c / total);
            out.add(new CompletenessBucket(k, c, p));
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<AgeBucket> getAgeDistribution(String audience) {
        Integer thisYear = Date.today().year();
        List<String> labels = new List<String>{'21-25','26-30','31-35','36-40','41-45','46-50','50+'};
        Map<String, Integer> counts = new Map<String, Integer>();
        for (String l : labels) counts.put(l, 0);

        List<ConstituentRole> rows;
        if (isActiveAudience(audience)) {
            Set<Id> personIds = activeAudiencePersonIds();
            rows = [
                SELECT Graduation_Year__c FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Graduation_Year__c != null AND PersonId IN :personIds
            WITH USER_MODE
            ];
        } else {
            rows = [
                SELECT Graduation_Year__c FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND Graduation_Year__c != null
            WITH USER_MODE
            ];
        }
        for (ConstituentRole r : rows) {
            Integer grad;
            try { grad = Integer.valueOf(r.Graduation_Year__c); } catch (Exception e) { continue; }
            Integer age = (thisYear - grad) + 22;
            String key;
            if (age <= 25)      key = '21-25';
            else if (age <= 30) key = '26-30';
            else if (age <= 35) key = '31-35';
            else if (age <= 40) key = '36-40';
            else if (age <= 45) key = '41-45';
            else if (age <= 50) key = '46-50';
            else                key = '50+';
            counts.put(key, counts.get(key) + 1);
        }
        List<AgeBucket> out = new List<AgeBucket>();
        for (String l : labels) out.add(new AgeBucket(l, counts.get(l)));
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<EmploymentSlice> getEmploymentStatus(String audience) {
        Boolean activeOnly = isActiveAudience(audience);
        Integer total;
        Integer employed;
        if (activeOnly) {
            Set<Id> personIds = activeAudiencePersonIds();
            total    = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND PersonId IN :personIds
            WITH USER_MODE
            ];
            employed = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND PersonId IN :personIds
                AND PersonId IN (
                    SELECT AccountId FROM PersonEmployment
                    WHERE Company_Name__c != null AND (Is_Archived__c = false OR Is_Archived__c = null)
                )
            WITH USER_MODE
            ];
        } else {
            total    = [SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni' WITH USER_MODE];
            employed = [
                SELECT COUNT() FROM ConstituentRole
                WHERE RoleType = 'Alumni'
                AND PersonId IN (
                    SELECT AccountId FROM PersonEmployment
                    WHERE Company_Name__c != null AND (Is_Archived__c = false OR Is_Archived__c = null)
                )
            WITH USER_MODE
            ];
        }
        if (total == 0) return new List<EmploymentSlice>();
        Integer unknown = total - employed;
        List<EmploymentSlice> out = new List<EmploymentSlice>();
        out.add(new EmploymentSlice('Employed', employed,
            (Integer) Math.round(100.0 * employed / total)));
        out.add(new EmploymentSlice('Unknown', unknown,
            (Integer) Math.round(100.0 * unknown / total)));
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<RegionRow> getRegionalDemographics(String audience) {
        // Source of truth: Account.PersonMailingCity (joined to ConstituentRole via PersonId).
        // Falls back to '— Unspecified' when blank.
        AggregateResult[] rows;
        if (isActiveAudience(audience)) {
            Set<Id> personIds = activeAudiencePersonIds();
            rows = [
                SELECT PersonMailingCity city, COUNT(Id) cnt
                FROM Account
                WHERE IsPersonAccount = true
                  AND PersonMailingCity != null
                  AND Id IN :personIds
                WITH USER_MODE
                GROUP BY PersonMailingCity
                ORDER BY COUNT(Id) DESC LIMIT 8
            ];
        } else {
            Set<Id> alumniPersonIds = new Set<Id>();
            for (ConstituentRole cr : [
                SELECT PersonId FROM ConstituentRole
                WHERE RoleType = 'Alumni' AND PersonId != null
                WITH USER_MODE
                LIMIT 50000
            ]) alumniPersonIds.add(cr.PersonId);
            rows = [
                SELECT PersonMailingCity city, COUNT(Id) cnt
                FROM Account
                WHERE IsPersonAccount = true
                  AND PersonMailingCity != null
                  AND Id IN :alumniPersonIds
                WITH USER_MODE
                GROUP BY PersonMailingCity
                ORDER BY COUNT(Id) DESC LIMIT 8
            ];
        }
        Integer max = 0;
        for (AggregateResult r : rows) {
            Integer c = (Integer) r.get('cnt');
            if (c > max) max = c;
        }
        List<RegionRow> out = new List<RegionRow>();
        for (AggregateResult r : rows) {
            Integer c = (Integer) r.get('cnt');
            Integer p = max == 0 ? 0 : (Integer) Math.round(100.0 * c / max);
            out.add(new RegionRow((String) r.get('city'), c, p));
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static CommsSnapshot getCommunicationsSnapshot() {
        CommsSnapshot s = new CommsSnapshot();
        s.messagesSent = 0;
        s.campaigns = 0;
        s.deliveryPct = 0;
        s.bouncedPct = 0;
        s.openRatePct = 0;
        s.clickRatePct = 0;
        s.emailSent = 0;
        s.whatsappSent = 0;
        s.smsSent = 0;
        s.scheduled = 0;
        s.awaitingReply = 0;
        return s;
    }

    private static Boolean isActiveAudience(String audience) {
        return audience != null && audience.equalsIgnoreCase('active');
    }

    /**
     * For audience='active', resolve the matching PersonAccount Ids from
     * ConstituentRole(RoleType='Alumni', Registration_Status__c IN registered/logged-in).
     * Returns null when no filter is needed.
     */
    private static Set<Id> activeAudiencePersonIds() {
        Set<Id> ids = new Set<Id>();
        for (ConstituentRole cr : [
            SELECT PersonId FROM ConstituentRole
            WHERE RoleType = 'Alumni'
            AND PersonId != null
            AND Registration_Status__c IN ('Registered', 'Initial Login Done')
            WITH USER_MODE
            LIMIT 50000
        ]) {
            ids.add(cr.PersonId);
        }
        return ids;
    }

    /**
     * Returns a partial SOQL clause and a bind map for the demographic queries
     * so they can pin to the active audience. When audience is 'all' the clause
     * is empty and the bind map carries no key.
     */
    private static String audienceWhere(String audience) {
        // legacy helper kept for source distribution / health which still use
        // direct queries — empty string means "no extra filter".
        return '';
    }

    private static HealthBar pct(String fieldLabel, Integer numerator, Integer denominator) {
        Integer p = denominator == 0 ? 0 : (Integer) Math.round(100.0 * numerator / denominator);
        return new HealthBar(fieldLabel, p, p < 50);
    }

    private static String shortMonth(Integer m) {
        List<String> months = new List<String>{
            'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
        };
        return months[m - 1];
    }

    private static EngagementChannel buildEvents(Integer baseTotal) {
        Datetime d90  = Datetime.now().addDays(-90);
        Datetime d180 = Datetime.now().addDays(-180);
        Datetime d30  = Datetime.now().addDays(-30);

        Integer engaged   = countDistinctAccounts([SELECT Person_Account__c FROM Ken_Event_Booking__c WHERE Person_Account__c != null WITH USER_MODE]);
        Integer active90  = countDistinctAccounts([SELECT Person_Account__c FROM Ken_Event_Booking__c WHERE Person_Account__c != null AND CreatedDate >= :d90 WITH USER_MODE]);
        Integer prev90    = countDistinctAccounts([SELECT Person_Account__c FROM Ken_Event_Booking__c WHERE Person_Account__c != null AND CreatedDate >= :d180 AND CreatedDate < :d90 WITH USER_MODE]);
        Integer newM      = countDistinctAccounts([SELECT Person_Account__c FROM Ken_Event_Booking__c WHERE Person_Account__c != null AND CreatedDate >= :d30 WITH USER_MODE]);
        Integer repeated  = [SELECT Person_Account__c FROM Ken_Event_Booking__c WHERE Person_Account__c != null WITH USER_MODE GROUP BY Person_Account__c HAVING COUNT(Id) >= 2].size();
        return makeChannel('Events', engaged, active90, prev90, newM, repeated, baseTotal);
    }

    private static EngagementChannel buildMentorship(Integer baseTotal) {
        Datetime d90  = Datetime.now().addDays(-90);
        Datetime d180 = Datetime.now().addDays(-180);
        Datetime d30  = Datetime.now().addDays(-30);

        Set<Id> all = new Set<Id>();
        Set<Id> active = new Set<Id>();
        Set<Id> prev = new Set<Id>();
        Set<Id> news = new Set<Id>();
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (Ken_Mentorship__c m : [SELECT Id, Mentor__c, Mentee__c, CreatedDate FROM Ken_Mentorship__c WITH USER_MODE]) {
            for (Id a : new List<Id>{ m.Mentor__c, m.Mentee__c }) {
                if (a == null) continue;
                all.add(a);
                if (m.CreatedDate >= d90) active.add(a);
                if (m.CreatedDate >= d180 && m.CreatedDate < d90) prev.add(a);
                if (m.CreatedDate >= d30) news.add(a);
                counts.put(a, (counts.get(a) == null ? 0 : counts.get(a)) + 1);
            }
        }
        Integer repeated = 0;
        for (Integer c : counts.values()) if (c >= 2) repeated++;
        return makeChannel('Mentorship', all.size(), active.size(), prev.size(), news.size(), repeated, baseTotal);
    }

    private static EngagementChannel buildGroups(Integer baseTotal) {
        Datetime d90  = Datetime.now().addDays(-90);
        Datetime d180 = Datetime.now().addDays(-180);
        Datetime d30  = Datetime.now().addDays(-30);

        Integer engaged   = countDistinctMembers([SELECT Member__c FROM Ken_Group_Member__c WHERE Member__c != null WITH USER_MODE]);
        Integer active90  = countDistinctMembers([SELECT Member__c FROM Ken_Group_Member__c WHERE Member__c != null AND CreatedDate >= :d90 WITH USER_MODE]);
        Integer prev90    = countDistinctMembers([SELECT Member__c FROM Ken_Group_Member__c WHERE Member__c != null AND CreatedDate >= :d180 AND CreatedDate < :d90 WITH USER_MODE]);
        Integer newM      = countDistinctMembers([SELECT Member__c FROM Ken_Group_Member__c WHERE Member__c != null AND CreatedDate >= :d30 WITH USER_MODE]);
        Integer repeated  = [SELECT Member__c FROM Ken_Group_Member__c WHERE Member__c != null WITH USER_MODE GROUP BY Member__c HAVING COUNT(Id) >= 2].size();
        return makeChannel('Groups & Chapters', engaged, active90, prev90, newM, repeated, baseTotal);
    }

    private static EngagementChannel buildSurveys(Integer baseTotal) {
        Datetime d90  = Datetime.now().addDays(-90);
        Datetime d180 = Datetime.now().addDays(-180);
        Datetime d30  = Datetime.now().addDays(-30);

        // Respondents are de-duplicated by account, so someone who submitted more than once
        // counts as one engaged alumnus.
        Set<Id> engagedIds  = assessmentRespondentIds([SELECT Respondent__c FROM Assessment WHERE Respondent__c != null WITH USER_MODE]);
        Set<Id> active90Ids = assessmentRespondentIds([SELECT Respondent__c FROM Assessment WHERE Respondent__c != null AND CreatedDate >= :d90 WITH USER_MODE]);
        Set<Id> prev90Ids   = assessmentRespondentIds([SELECT Respondent__c FROM Assessment WHERE Respondent__c != null AND CreatedDate >= :d180 AND CreatedDate < :d90 WITH USER_MODE]);
        Set<Id> newIds      = assessmentRespondentIds([SELECT Respondent__c FROM Assessment WHERE Respondent__c != null AND CreatedDate >= :d30 WITH USER_MODE]);

        Set<Id> repeatedIds = new Set<Id>();
        for (AggregateResult ar : [SELECT Respondent__c rid FROM Assessment WHERE Respondent__c != null WITH USER_MODE GROUP BY Respondent__c HAVING COUNT(Id) >= 2]) {
            repeatedIds.add((Id) ar.get('rid'));
        }
        return makeChannel('Surveys', engagedIds.size(), active90Ids.size(), prev90Ids.size(), newIds.size(), repeatedIds.size(), baseTotal);
    }

    private static Integer countDistinctAccounts(List<Ken_Event_Booking__c> rows) {
        Set<Id> s = new Set<Id>();
        for (Ken_Event_Booking__c r : rows) if (r.Person_Account__c != null) s.add(r.Person_Account__c);
        return s.size();
    }
    private static Integer countDistinctMembers(List<Ken_Group_Member__c> rows) {
        Set<Id> s = new Set<Id>();
        for (Ken_Group_Member__c r : rows) if (r.Member__c != null) s.add(r.Member__c);
        return s.size();
    }
    private static Set<Id> assessmentRespondentIds(List<Assessment> rows) {
        Set<Id> s = new Set<Id>();
        for (Assessment r : rows) if (r.Respondent__c != null) s.add(r.Respondent__c);
        return s;
    }

    private static EngagementChannel makeChannel(String name, Integer engaged, Integer active90, Integer prev90, Integer newM, Integer repeated, Integer baseTotal) {
        Decimal reachPct = (baseTotal == null || baseTotal == 0)
            ? 0
            : (Decimal.valueOf(engaged) / Decimal.valueOf(baseTotal) * 100).setScale(1);
        Integer repeatPct = engaged == 0 ? 0 : (Integer) Math.round(100.0 * repeated / engaged);
        Boolean up = active90 >= prev90;
        String insight = buildInsight(name, reachPct, repeatPct, up, engaged);
        return new EngagementChannel(name, reachPct, engaged, active90, repeatPct, newM, up, insight);
    }

    private static String buildInsight(String channel, Decimal reach, Integer repeatPct, Boolean up, Integer engaged) {
        if (engaged == 0) return 'No engagement recorded yet.';
        String dir = up ? 'growing' : 'down vs prior 90 days';
        return 'Reaches ' + reach + '% of base, ' + repeatPct + '% return — ' + dir + '.';
    }
}