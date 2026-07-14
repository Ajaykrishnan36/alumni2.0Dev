public with sharing class KenCaseDashboardController {

    // SMU Case status picklist values — must match Service / Support Business Processes.
    // Open = anything not Closed / Canceled / Merged.
    private static final Set<String> OPEN_STATUSES      = new Set<String>{
        'New', 'In Progress', 'Waiting for Student', 'Response Received', 'On Hold', 'Escalated'
    };
    private static final Set<String> CLOSED_STATUSES    = new Set<String>{ 'Closed' };
    private static final Set<String> CANCELLED_STATUSES = new Set<String>{ 'Canceled', 'Merged' };

    private static final String[] MONTH_NAMES = new String[]{
        'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    };

    // Milestone health bucket labels — kept in a constant so the chart, drilldown
    // and getCaseList branches stay aligned.
    private static final String MS_HEALTH_BREACHED     = 'Breached';
    private static final String MS_HEALTH_ON_TRACK     = 'On Track';
    private static final String MS_HEALTH_MET          = 'Met';
    private static final String MS_HEALTH_NO_MILESTONE = 'No Milestone';

    // ── Inner classes ────────────────────────────────────────────────────────

    public class ChartPoint {
        @AuraEnabled public String  label;
        @AuraEnabled public Integer value;
        ChartPoint(String l, Integer v) { label = l; value = v; }
    }

    public class SummaryStats {
        @AuraEnabled public Integer total       = 0;
        @AuraEnabled public Integer openCases   = 0;
        @AuraEnabled public Integer closedCases = 0;
        @AuraEnabled public Integer cancelled   = 0;
    }

    public class CaseListRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String serviceOffering;
        @AuraEnabled public String serviceName;
        @AuraEnabled public String origin;
        @AuraEnabled public String submitterName;
        @AuraEnabled public String createdDate;
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private static Boolean isBlankOrAll(String val) {
        return String.isBlank(val) || val == 'All';
    }

    private static List<String> buildBaseConditions(String year, String status) {
        List<String> conds = new List<String>();
        if (!isBlankOrAll(year))
            conds.add('CALENDAR_YEAR(CreatedDate) = ' + Integer.valueOf(String.escapeSingleQuotes(year)));
        if (!isBlankOrAll(status))
            conds.add('Status = \'' + String.escapeSingleQuotes(status) + '\'');
        return conds;
    }

    private static String buildWhereClause(List<String> conditions) {
        if (conditions == null || conditions.isEmpty()) return '';
        return ' WHERE ' + String.join(conditions, ' AND ');
    }

    /**
     * Build a case-id -> milestone-health bucket map for the given set of case ids.
     * Buckets:
     *   - Breached     : any CaseMilestone has IsViolated = true
     *   - On Track     : has open milestone (IsCompleted = false) and none violated
     *   - Met          : has milestones, all IsCompleted = true, none violated
     *   - No Milestone : has no CaseMilestone records (e.g. no entitlement)
     */
    private static Map<Id, String> computeMilestoneHealth(Set<Id> caseIds) {
        Map<Id, String> healthByCase = new Map<Id, String>();
        if (caseIds == null || caseIds.isEmpty()) {
            return healthByCase;
        }
        for (Id cId : caseIds) {
            healthByCase.put(cId, MS_HEALTH_NO_MILESTONE);
        }

        Map<Id, Boolean> hasViolation     = new Map<Id, Boolean>();
        Map<Id, Boolean> hasOpenMilestone = new Map<Id, Boolean>();
        Map<Id, Boolean> hasAnyMilestone  = new Map<Id, Boolean>();

        for (CaseMilestone m : [
            SELECT CaseId, IsCompleted, IsViolated
            FROM CaseMilestone
            WHERE CaseId IN :caseIds
        ]) {
            hasAnyMilestone.put(m.CaseId, true);
            if (m.IsViolated)   hasViolation.put(m.CaseId, true);
            if (!m.IsCompleted) hasOpenMilestone.put(m.CaseId, true);
        }

        for (Id cId : caseIds) {
            if (!hasAnyMilestone.containsKey(cId)) {
                healthByCase.put(cId, MS_HEALTH_NO_MILESTONE);
            } else if (hasViolation.containsKey(cId)) {
                healthByCase.put(cId, MS_HEALTH_BREACHED);
            } else if (hasOpenMilestone.containsKey(cId)) {
                healthByCase.put(cId, MS_HEALTH_ON_TRACK);
            } else {
                healthByCase.put(cId, MS_HEALTH_MET);
            }
        }
        return healthByCase;
    }

    // ── getSummaryStats ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static SummaryStats getSummaryStats(String year, String status) {
        try {
            SummaryStats stats = new SummaryStats();
            List<String> conds = buildBaseConditions(year, status);
            String q = 'SELECT Status s, COUNT(Id) cnt FROM Case'
                + buildWhereClause(conds)
                + ' GROUP BY Status';
            for (AggregateResult ar : Database.query(q)) {
                String st  = (String) ar.get('s');
                Integer cnt = (Integer) ar.get('cnt');
                stats.total += cnt;
                if (OPEN_STATUSES.contains(st))      stats.openCases   += cnt;
                if (CLOSED_STATUSES.contains(st))    stats.closedCases += cnt;
                if (CANCELLED_STATUSES.contains(st)) stats.cancelled   += cnt;
            }
            return stats;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getCasesByStatus ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getCasesByStatus(String year) {
        try {
            List<String> conds = new List<String>();
            if (!isBlankOrAll(year))
                conds.add('CALENDAR_YEAR(CreatedDate) = ' + Integer.valueOf(String.escapeSingleQuotes(year)));
            String q = 'SELECT Status s, COUNT(Id) cnt FROM Case'
                + buildWhereClause(conds)
                + ' GROUP BY Status ORDER BY COUNT(Id) DESC';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartPoint((String) ar.get('s'), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getCasesByTargetAudience ─────────────────────────────────────────────
    // Cases broken down by the Target Audience of the linked service.

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getCasesByTargetAudience(String year, String status) {
        try {
            List<String> conds = buildBaseConditions(year, status);
            String q = 'SELECT Service_Offering__r.Service__r.Target_Audience__c FROM Case'
                + buildWhereClause(conds)
                + ' LIMIT 50000';

            Map<String, Integer> counts = new Map<String, Integer>();
            for (SObject c : Database.query(q)) {
                SObject offering = c.getSObject('Service_Offering__r');
                if (offering == null) continue;
                SObject service = offering.getSObject('Service__r');
                if (service == null) continue;
                String taVal = (String) service.get('Target_Audience__c');
                if (String.isBlank(taVal)) continue;
                for (String ta : taVal.split(';')) {
                    ta = ta.trim();
                    if (String.isBlank(ta)) continue;
                    counts.put(ta, (counts.containsKey(ta) ? counts.get(ta) : 0) + 1);
                }
            }

            List<ChartPoint> result = new List<ChartPoint>();
            for (String ta : counts.keySet()) {
                result.add(new ChartPoint(ta, counts.get(ta)));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getCasesByMilestoneHealth ───────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getCasesByMilestoneHealth(String year, String status) {
        try {
            List<String> conds = buildBaseConditions(year, status);
            String q = 'SELECT Id FROM Case' + buildWhereClause(conds) + ' LIMIT 50000';
            Set<Id> caseIds = (new Map<Id, SObject>(Database.query(q))).keySet();
            if (caseIds.isEmpty()) {
                return new List<ChartPoint>();
            }

            Map<Id, String> healthByCase = computeMilestoneHealth(caseIds);

            Map<String, Integer> bucketCounts = new Map<String, Integer>{
                MS_HEALTH_BREACHED     => 0,
                MS_HEALTH_ON_TRACK     => 0,
                MS_HEALTH_MET          => 0,
                MS_HEALTH_NO_MILESTONE => 0
            };
            for (String h : healthByCase.values()) {
                bucketCounts.put(h, bucketCounts.get(h) + 1);
            }

            // Fixed display order: Breached → On Track → Met → No Milestone.
            // Zero-count buckets are omitted so the chart isn't cluttered.
            List<ChartPoint> result = new List<ChartPoint>();
            for (String bucket : new List<String>{
                MS_HEALTH_BREACHED, MS_HEALTH_ON_TRACK, MS_HEALTH_MET, MS_HEALTH_NO_MILESTONE
            }) {
                if (bucketCounts.get(bucket) > 0) {
                    result.add(new ChartPoint(bucket, bucketCounts.get(bucket)));
                }
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getTopServices ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopServices(String year, String status) {
        try {
            List<String> conds = buildBaseConditions(year, status);
            conds.add('Service_Offering__r.Service__r.Name != null');
            String q = 'SELECT Service_Offering__r.Service__r.Name svc, COUNT(Id) cnt FROM Case'
                + buildWhereClause(conds)
                + ' GROUP BY Service_Offering__r.Service__r.Name ORDER BY COUNT(Id) DESC LIMIT 10';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartPoint((String) ar.get('svc'), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getTopServiceOfferings ───────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopServiceOfferings(String year, String status) {
        try {
            List<String> conds = buildBaseConditions(year, status);
            conds.add('Service_Offering__r.Name != null');
            String q = 'SELECT Service_Offering__r.Name ofr, COUNT(Id) cnt FROM Case'
                + buildWhereClause(conds)
                + ' GROUP BY Service_Offering__r.Name ORDER BY COUNT(Id) DESC LIMIT 10';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartPoint((String) ar.get('ofr'), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getCaseTrend ─────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getCaseTrend(String year, String status) {
        try {
            List<String> conds = buildBaseConditions(year, status);
            String q = 'SELECT CALENDAR_MONTH(CreatedDate) mo, COUNT(Id) cnt FROM Case'
                + buildWhereClause(conds)
                + ' GROUP BY CALENDAR_MONTH(CreatedDate) ORDER BY CALENDAR_MONTH(CreatedDate) ASC';
            Map<Integer, Integer> monthMap = new Map<Integer, Integer>();
            for (AggregateResult ar : Database.query(q))
                monthMap.put((Integer) ar.get('mo'), (Integer) ar.get('cnt'));
            List<ChartPoint> result = new List<ChartPoint>();
            for (Integer m = 1; m <= 12; m++)
                result.add(new ChartPoint(MONTH_NAMES[m - 1], monthMap.containsKey(m) ? monthMap.get(m) : 0));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getTopSubmitters ─────────────────────────────────────────────────────
    // SMU uses Person Accounts — Account.Name is the student's full name.

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopSubmitters(String year, String status) {
        try {
            List<String> conds = buildBaseConditions(year, status);
            conds.add('Account.Name != null');
            String q = 'SELECT Account.Name sub, COUNT(Id) cnt FROM Case'
                + buildWhereClause(conds)
                + ' GROUP BY Account.Name ORDER BY COUNT(Id) DESC LIMIT 10';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartPoint((String) ar.get('sub'), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getFilterOptions ─────────────────────────────────────────────────────
    // Origins block kept (harmless, in case the LWC ever exposes it again).
    // The dashboard LWC no longer renders the Origin dropdown.

    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getFilterOptions() {
        try {
            Set<String> statusSet = new Set<String>();
            Set<String> yearSet   = new Set<String>();

            for (AggregateResult ar : [
                SELECT Status s FROM Case WHERE Status != null GROUP BY Status
            ]) {
                String v = (String) ar.get('s');
                if (!String.isBlank(v)) statusSet.add(v);
            }

            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(CreatedDate) yr FROM Case GROUP BY CALENDAR_YEAR(CreatedDate)
            ]) {
                Object v = ar.get('yr');
                if (v != null) yearSet.add(String.valueOf(v));
            }

            List<String> statuses = new List<String>(statusSet);
            List<String> years    = new List<String>(yearSet);
            statuses.sort();
            years.sort();

            return new Map<String, List<String>>{
                'statuses' => statuses,
                'years'    => years
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getCaseList ──────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<CaseListRecord> getCaseList(
        String dimension,
        String dimensionValue,
        String year,
        String status
    ) {
        try {
            List<String> conds = buildBaseConditions(year, status);

            String dv = String.escapeSingleQuotes(dimensionValue == null ? '' : dimensionValue);

            // Some dimensions filter via SOQL WHERE; 'milestone' filters in memory
            // after the rows are loaded (the milestone-health bucket isn't a column).
            Boolean milestoneFilter = false;
            String  milestoneBucket = null;

            if (dimension == 'status') {
                conds.add('Status = \'' + dv + '\'');
            } else if (dimension == 'service') {
                conds.add('Service_Offering__r.Service__r.Name = \'' + dv + '\'');
            } else if (dimension == 'offering') {
                conds.add('Service_Offering__r.Name = \'' + dv + '\'');
            } else if (dimension == 'submitter') {
                conds.add('Account.Name = \'' + dv + '\'');
            } else if (dimension == 'targetAudience') {
                conds.add('Service_Offering__r.Service__r.Target_Audience__c INCLUDES (\'' + String.escapeSingleQuotes(dv) + '\')');
            } else if (dimension == 'milestone') {
                milestoneFilter = true;
                milestoneBucket = dimensionValue;
            } else if (dimension == 'open') {
                conds.add('Status IN (\'New\',\'In Progress\',\'Waiting for Student\',\'Response Received\',\'On Hold\',\'Escalated\')');
            } else if (dimension == 'closed') {
                conds.add('Status = \'Closed\'');
            } else if (dimension == 'cancelled') {
                conds.add('Status IN (\'Canceled\',\'Merged\')');
            }

            String q = 'SELECT Id, CaseNumber, Subject, Status, Origin,'
                + ' Service_Offering__r.Name, Service_Offering__r.Service__r.Name,'
                + ' Account.Name, CreatedDate'
                + ' FROM Case'
                + buildWhereClause(conds)
                + ' ORDER BY CreatedDate DESC LIMIT 500';

            List<Case> rawCases = Database.query(q);

            // Apply milestone-bucket post-filter if needed
            Map<Id, String> healthByCase = null;
            if (milestoneFilter) {
                Set<Id> caseIds = new Set<Id>();
                for (Case c : rawCases) caseIds.add(c.Id);
                healthByCase = computeMilestoneHealth(caseIds);
            }

            List<CaseListRecord> result = new List<CaseListRecord>();
            for (Case c : rawCases) {
                if (milestoneFilter && healthByCase.get(c.Id) != milestoneBucket) {
                    continue;
                }
                CaseListRecord rec = new CaseListRecord();
                rec.id              = c.Id;
                rec.caseNumber      = c.CaseNumber;
                rec.subject         = c.Subject;
                rec.status          = c.Status;
                rec.origin          = c.Origin;
                rec.serviceOffering = c.Service_Offering__r != null ? c.Service_Offering__r.Name : null;
                rec.serviceName     = (c.Service_Offering__r != null && c.Service_Offering__r.Service__r != null)
                                        ? c.Service_Offering__r.Service__r.Name : null;
                rec.submitterName   = c.Account != null ? c.Account.Name : null;
                rec.createdDate     = c.CreatedDate != null
                                        ? c.CreatedDate.format('MMM d, yyyy') : null;
                result.add(rec);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}