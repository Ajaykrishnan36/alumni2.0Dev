public with sharing class KenCaseDashboardController {

    private static final Set<String> OPEN_STATUSES      = new Set<String>{ 'New', 'Working', 'In Review' };
    private static final Set<String> CLOSED_STATUSES    = new Set<String>{ 'Closed' };
    private static final Set<String> CANCELLED_STATUSES = new Set<String>{ 'Canceled', 'Rejected' };

    private static final String[] MONTH_NAMES = new String[]{
        'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    };

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

    private static List<String> buildBaseConditions(String year, String status, String origin) {
        List<String> conds = new List<String>();
        if (!isBlankOrAll(year))
            conds.add('CALENDAR_YEAR(CreatedDate) = ' + Integer.valueOf(String.escapeSingleQuotes(year)));
        if (!isBlankOrAll(status))
            conds.add('Status = \'' + String.escapeSingleQuotes(status) + '\'');
        if (!isBlankOrAll(origin))
            conds.add('Origin = \'' + String.escapeSingleQuotes(origin) + '\'');
        return conds;
    }

    private static String buildWhereClause(List<String> conditions) {
        if (conditions == null || conditions.isEmpty()) return '';
        return ' WHERE ' + String.join(conditions, ' AND ');
    }

    // ── getSummaryStats ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static SummaryStats getSummaryStats(String year, String status, String origin) {
        try {
            SummaryStats stats = new SummaryStats();
            List<String> conds = buildBaseConditions(year, status, origin);
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
    public static List<ChartPoint> getCasesByStatus(String year, String origin) {
        try {
            List<String> conds = new List<String>();
            if (!isBlankOrAll(year))
                conds.add('CALENDAR_YEAR(CreatedDate) = ' + Integer.valueOf(String.escapeSingleQuotes(year)));
            if (!isBlankOrAll(origin))
                conds.add('Origin = \'' + String.escapeSingleQuotes(origin) + '\'');
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

    // ── getCasesByOrigin ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getCasesByOrigin(String year, String status) {
        try {
            List<String> conds = new List<String>();
            if (!isBlankOrAll(year))
                conds.add('CALENDAR_YEAR(CreatedDate) = ' + Integer.valueOf(String.escapeSingleQuotes(year)));
            if (!isBlankOrAll(status))
                conds.add('Status = \'' + String.escapeSingleQuotes(status) + '\'');
            String q = 'SELECT Origin o, COUNT(Id) cnt FROM Case'
                + buildWhereClause(conds)
                + ' GROUP BY Origin ORDER BY COUNT(Id) DESC';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : Database.query(q)) {
                String originVal = (String) ar.get('o');
                if (String.isBlank(originVal)) originVal = 'Unknown';
                result.add(new ChartPoint(originVal, (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getTopServices ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopServices(String year, String status, String origin) {
        try {
            List<String> conds = buildBaseConditions(year, status, origin);
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
    public static List<ChartPoint> getTopServiceOfferings(String year, String status, String origin) {
        try {
            List<String> conds = buildBaseConditions(year, status, origin);
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
    public static List<ChartPoint> getCaseTrend(String year, String status, String origin) {
        try {
            List<String> conds = buildBaseConditions(year, status, origin);
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

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopSubmitters(String year, String status, String origin) {
        try {
            List<String> conds = buildBaseConditions(year, status, origin);
            conds.add('Constituent_Role__r.Person.Name != null');
            String q = 'SELECT Constituent_Role__r.Person.Name sub, COUNT(Id) cnt FROM Case'
                + buildWhereClause(conds)
                + ' GROUP BY Constituent_Role__r.Person.Name ORDER BY COUNT(Id) DESC LIMIT 10';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : Database.query(q))
                result.add(new ChartPoint((String) ar.get('sub'), (Integer) ar.get('cnt')));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── getFilterOptions ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getFilterOptions() {
        try {
            Set<String> statusSet = new Set<String>();
            Set<String> originSet = new Set<String>();
            Set<String> yearSet   = new Set<String>();

            for (AggregateResult ar : [
                SELECT Status s FROM Case WHERE Status != null GROUP BY Status
            ]) {
                String v = (String) ar.get('s');
                if (!String.isBlank(v)) statusSet.add(v);
            }

            for (AggregateResult ar : [
                SELECT Origin o FROM Case WHERE Origin != null GROUP BY Origin
            ]) {
                String v = (String) ar.get('o');
                if (!String.isBlank(v)) originSet.add(v);
            }

            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(CreatedDate) yr FROM Case GROUP BY CALENDAR_YEAR(CreatedDate)
            ]) {
                Object v = ar.get('yr');
                if (v != null) yearSet.add(String.valueOf(v));
            }

            List<String> statuses = new List<String>(statusSet);
            List<String> origins  = new List<String>(originSet);
            List<String> years    = new List<String>(yearSet);
            statuses.sort();
            origins.sort();
            years.sort();

            return new Map<String, List<String>>{
                'statuses' => statuses,
                'origins'  => origins,
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
        String status,
        String origin
    ) {
        try {
            List<String> conds = buildBaseConditions(year, status, origin);

            String dv = String.escapeSingleQuotes(dimensionValue == null ? '' : dimensionValue);

            if (dimension == 'status') {
                conds.add('Status = \'' + dv + '\'');
            } else if (dimension == 'origin') {
                conds.add('Origin = \'' + dv + '\'');
            } else if (dimension == 'service') {
                conds.add('Service_Offering__r.Service__r.Name = \'' + dv + '\'');
            } else if (dimension == 'offering') {
                conds.add('Service_Offering__r.Name = \'' + dv + '\'');
            } else if (dimension == 'submitter') {
                conds.add('Constituent_Role__r.Person.Name = \'' + dv + '\'');
            } else if (dimension == 'open') {
                conds.add('Status IN (\'New\',\'Working\',\'In Review\')');
            } else if (dimension == 'closed') {
                conds.add('Status = \'Closed\'');
            } else if (dimension == 'cancelled') {
                conds.add('Status IN (\'Canceled\',\'Rejected\')');
            }

            String q = 'SELECT Id, CaseNumber, Subject, Status, Origin,'
                + ' Service_Offering__r.Name, Service_Offering__r.Service__r.Name,'
                + ' Constituent_Role__r.Person.Name, CreatedDate'
                + ' FROM Case'
                + buildWhereClause(conds)
                + ' ORDER BY CreatedDate DESC LIMIT 500';

            List<CaseListRecord> result = new List<CaseListRecord>();
            for (Case c : Database.query(q)) {
                CaseListRecord rec = new CaseListRecord();
                rec.id              = c.Id;
                rec.caseNumber      = c.CaseNumber;
                rec.subject         = c.Subject;
                rec.status          = c.Status;
                rec.origin          = c.Origin;
                rec.serviceOffering = c.Service_Offering__r != null ? c.Service_Offering__r.Name : null;
                rec.serviceName     = (c.Service_Offering__r != null && c.Service_Offering__r.Service__r != null)
                                        ? c.Service_Offering__r.Service__r.Name : null;
                rec.submitterName   = (c.Constituent_Role__r != null && c.Constituent_Role__r.Person != null)
                                        ? c.Constituent_Role__r.Person.Name : null;
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