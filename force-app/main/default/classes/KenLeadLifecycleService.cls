/**
 * @description Canonical definition of the alumni lead lifecycle. Holds the
 *              seven primary stages, their derived sub-statuses, display
 *              metadata and the SOQL predicates that select ConstituentRole
 *              rows for each stage. Single source of truth shared by the admin
 *              dashboard KPIs, the lifecycle funnel and the master-records
 *              drill-down so status is reflected consistently everywhere.
 *
 *              Onboarding In Progress is a stored value on
 *              ConstituentRole.Registration_Status__c (stamped by
 *              KenPortalOnbordingController), so every count maps 1:1 to the
 *              field with no derived proxy.
 */
public with sharing class KenLeadLifecycleService {

    public static final String STAGE_LEAD = 'Lead';
    public static final String STAGE_UNVERIFIED = 'Unverified';
    public static final String STAGE_REGISTERED = 'Registered';
    public static final String STAGE_ONBOARDING_IN_PROGRESS = 'Onboarding In Progress';
    public static final String STAGE_ACTIVE = 'Active';

    private static final Set<String> LEAD_SOURCES = new Set<String>{
        'Self-Declared Lead', 'Campaign Lead', 'Alumni Referral'
    };
    private static final Set<String> OLD_PORTAL_SOURCES = new Set<String>{
        'Old Portal Record', 'Old Portal Migration'
    };

    private static final String LEAD_SOURCE_SOQL = '(\'Self-Declared Lead\', \'Campaign Lead\', \'Alumni Referral\')';
    private static final String UNREGISTERED = '(Registration_Status__c = null OR Registration_Status__c = \'Unregistered\')';

    public class StageMeta {
        @AuraEnabled public String stage;
        @AuraEnabled public String label;
        @AuraEnabled public String colorClass;
        @AuraEnabled public String filterKey;
        @AuraEnabled public List<String> subStatuses;
        public StageMeta(String s, String l, String c, String f, List<String> subs) {
            stage = s; label = l; colorClass = c; filterKey = f; subStatuses = subs;
        }
    }

    /**
     * @description Ordered lifecycle stages with display metadata and the set of
     *              sub-statuses each stage can resolve to. Used for the status
     *              configuration and per-stage master-records drill-down.
     */
    public static List<StageMeta> getStages() {
        return new List<StageMeta>{
            new StageMeta(STAGE_LEAD, 'Lead', 'stage-lead', 'life-lead',
                new List<String>{ 'Self-Declared', 'Campaign', 'Referral' }),
            new StageMeta(STAGE_UNVERIFIED, 'Unverified', 'stage-unverified', 'life-unverified',
                new List<String>{ 'Awaiting Verification' }),
            new StageMeta(STAGE_REGISTERED, 'Registered', 'stage-registered', 'life-registered',
                new List<String>{ 'New Registration', 'Old-Portal Migrated' }),
            new StageMeta(STAGE_ONBOARDING_IN_PROGRESS, 'Onboarding In Progress', 'stage-onboarding-inprogress', 'life-onboarding-inprogress',
                new List<String>{ 'In Progress' }),
            new StageMeta(STAGE_ACTIVE, 'Active', 'stage-active', 'life-active',
                new List<String>{ 'Active', 'Dormant' })
        };
    }

    /**
     * @description The five uniform funnel steps (the two pre-verified stages
     *              collapse into "Leads", the two onboarding stages collapse into
     *              "Onboarding") kept in perfect sync with the status field.
     */
    public static List<StageMeta> getFunnelSteps() {
        return new List<StageMeta>{
            new StageMeta('Leads', 'Leads', 'stage-lead', 'life-leads', null),
            new StageMeta(STAGE_REGISTERED, 'Registered', 'stage-registered', 'life-registered', null),
            new StageMeta('Onboarding', 'Onboarding', 'stage-onboarding-inprogress', 'life-onboarding', null),
            new StageMeta(STAGE_ACTIVE, 'Active', 'stage-active', 'life-active', null)
        };
    }

    /**
     * @description SOQL WHERE fragment (on ConstituentRole) selecting the rows for
     *              a stage, grouped funnel step or KPI key. Pure field equality —
     *              every clause maps 1:1 to Registration_Status__c / Source_Funnel__c.
     */
    public static String predicateFor(String key) {
        if (String.isBlank(key)) return null;
        if (key == STAGE_LEAD || key == 'life-lead') {
            return '(Source_Funnel__c IN ' + LEAD_SOURCE_SOQL + ' AND ' + UNREGISTERED + ')';
        }
        if (key == STAGE_UNVERIFIED || key == 'life-unverified') {
            return '((Source_Funnel__c = null OR Source_Funnel__c NOT IN ' + LEAD_SOURCE_SOQL + ') AND ' + UNREGISTERED + ')';
        }
        if (key == 'life-leads') {
            return UNREGISTERED;
        }
        if (key == STAGE_REGISTERED || key == 'life-registered') {
            return '(Registration_Status__c = \'Registered\')';
        }
        if (key == STAGE_ONBOARDING_IN_PROGRESS || key == 'life-onboarding-inprogress') {
            return '(Registration_Status__c = \'Onboarding In Progress\')';
        }
        if (key == 'life-onboarding') {
            return '(Registration_Status__c = \'Onboarding In Progress\')';
        }
        if (key == STAGE_ACTIVE || key == 'life-active') {
            return '(Registration_Status__c = \'Initial Login Done\')';
        }
        return null;
    }

    /**
     * @description Live count of alumni ConstituentRole rows for the given key.
     */
    public static Integer countFor(String key) {
        String pred = predicateFor(key);
        if (pred == null) return 0;
        return Database.countQueryWithBinds(
            'SELECT COUNT() FROM ConstituentRole WHERE RoleType = \'Alumni\' AND ' + pred,
            new Map<String, Object>(),
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * @description Resolves the primary lifecycle stage for one record straight
     *              from the stored Registration_Status__c value.
     */
    public static String resolveStage(ConstituentRole cr) {
        String rs = cr != null ? cr.Registration_Status__c : null;
        String src = cr != null ? cr.Source_Funnel__c : null;
        if (rs == 'Initial Login Done') return STAGE_ACTIVE;
        if (rs == STAGE_ONBOARDING_IN_PROGRESS) return STAGE_ONBOARDING_IN_PROGRESS;
        if (rs == 'Registered') return STAGE_REGISTERED;
        if (LEAD_SOURCES.contains(src)) return STAGE_LEAD;
        return STAGE_UNVERIFIED;
    }

    /**
     * @description Derives the sub-status label for one record from existing
     *              signals (source funnel, old-portal origin).
     */
    public static String resolveSubStatus(ConstituentRole cr) {
        String stage = resolveStage(cr);
        String src = cr != null ? cr.Source_Funnel__c : null;
        if (stage == STAGE_LEAD) {
            if (src == 'Self-Declared Lead') return 'Self-Declared';
            if (src == 'Campaign Lead') return 'Campaign';
            if (src == 'Alumni Referral') return 'Referral';
            return 'Self-Declared';
        }
        if (stage == STAGE_UNVERIFIED) return 'Awaiting Verification';
        if (stage == STAGE_REGISTERED) {
            return OLD_PORTAL_SOURCES.contains(src) ? 'Old-Portal Migrated' : 'New Registration';
        }
        if (stage == STAGE_ONBOARDING_IN_PROGRESS) return 'In Progress';
        if (stage == STAGE_ACTIVE) {
            return 'Active';
        }
        return '';
    }
}