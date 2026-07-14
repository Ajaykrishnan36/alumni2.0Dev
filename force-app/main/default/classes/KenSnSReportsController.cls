public without sharing class KenSnSReportsController {

    // ── Wrapper classes ──────────────────────────────────────────────────────

    public class ReportResult {
        @AuraEnabled public List<ReportRow> rows;
        @AuraEnabled public List<KpiItem>   kpis;
    }

    public class ReportRow {
        @AuraEnabled public String id;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String serviceOffering;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String priority;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountId;
        @AuraEnabled public String createdDate;
        @AuraEnabled public String closedDate;
        @AuraEnabled public String createdMonth;
    }

    public class KpiItem {
        @AuraEnabled public String         label;
        @AuraEnabled public String         value;
        @AuraEnabled public String         sub;
        @AuraEnabled public String         color;
        @AuraEnabled public String         chartType;
        @AuraEnabled public String         dotColor;
        @AuraEnabled public List<String>   chartLabels;
        @AuraEnabled public List<Decimal>  chartValues;
        @AuraEnabled public List<String>   chartColors;
        @AuraEnabled public List<LegendItem> legend;
    }

    public class LegendItem {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String color;
    }

    // ── Main entry point ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Map<String,String>> getServiceOfferings() {
        List<Map<String,String>> options = new List<Map<String,String>>();
        Map<String,String> all = new Map<String,String>{ 'label' => 'All Services', 'value' => '' };
        options.add(all);
        Set<String> seen = new Set<String>();
        for (AggregateResult ar : [
            SELECT Service_Offering__r.Service__r.Name sname
            FROM Case
            WHERE Service_Offering__c != NULL
            AND Service_Offering__r.Service__c != NULL
            GROUP BY Service_Offering__r.Service__r.Name
            ORDER BY Service_Offering__r.Service__r.Name ASC
            LIMIT 200
        ]) {
            String name = (String) ar.get('sname');
            if (String.isNotBlank(name) && !seen.contains(name)) {
                seen.add(name);
                Map<String,String> opt = new Map<String,String>{ 'label' => name, 'value' => name };
                options.add(opt);
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=false)
    public static ReportResult getReportData(
        String  reportType,
        String  statusFilter,
        String  recordTypeFilter,
        String  dateRange,
        String  searchKey,
        Integer limitSize
    ) {
        ReportResult result = new ReportResult();
        result.rows = new List<ReportRow>();
        result.kpis = new List<KpiItem>();

        Integer lim = (limitSize != null && limitSize > 0) ? limitSize : 10000;

        List<String> conditions = new List<String>();

        if (String.isNotBlank(statusFilter)) {
            conditions.add('Status = \'' + String.escapeSingleQuotes(statusFilter) + '\'');
        }
        if (String.isNotBlank(recordTypeFilter)) {
            conditions.add('RecordType.DeveloperName = \'' + String.escapeSingleQuotes(recordTypeFilter) + '\'');
        }
        if (String.isNotBlank(searchKey)) {
            // searchKey is a Service name — filter by parent service
            conditions.add('Service_Offering__r.Service__r.Name = \'' + String.escapeSingleQuotes(searchKey) + '\'');
        }
        Date startDate = resolveStartDate(dateRange);
        if (startDate != null) {
            conditions.add('CreatedDate >= ' + String.valueOf(startDate) + 'T00:00:00Z');
        }

        String whereClause = conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');

        String query = 'SELECT Id, CaseNumber, Subject, Status, Priority,'
            + ' RecordType.Name, RecordType.DeveloperName,'
            + ' Service_Offering__r.Name, Service_Offering__r.Service__r.Name,'
            + ' Owner.Name, Account.Name, AccountId,'
            + ' CreatedDate, ClosedDate'
            + ' FROM Case'
            + whereClause
            + ' ORDER BY CreatedDate DESC LIMIT ' + lim;

        List<Case> cases = Database.query(query);

        Map<String,Integer> statusCount   = new Map<String,Integer>();
        Map<String,Integer> categoryCount = new Map<String,Integer>();
        Map<String,Integer> rtCount       = new Map<String,Integer>();
        Map<String,Integer> priorityCount = new Map<String,Integer>();
        Map<String,Integer> ownerCount    = new Map<String,Integer>();
        Map<String,Integer> monthCount    = new Map<String,Integer>();

        Integer total = cases.size();

        for (Case c : cases) {
            ReportRow row    = new ReportRow();
            row.id           = c.Id;
            row.caseNumber   = c.CaseNumber;
            row.subject      = c.Subject;
            row.status       = c.Status;
            row.priority     = c.Priority != null ? c.Priority : '';
            row.ownerName    = c.Owner    != null ? c.Owner.Name    : '';
            row.accountName  = c.Account  != null ? c.Account.Name  : '';
            row.accountId    = c.AccountId;
            row.recordTypeName  = c.RecordType         != null ? c.RecordType.Name                : '';
            row.serviceOffering = c.Service_Offering__r != null ? c.Service_Offering__r.Name : '';
            row.createdDate  = c.CreatedDate != null ? c.CreatedDate.format() : '';
            row.closedDate   = c.ClosedDate  != null ? c.ClosedDate.format()  : '';
            row.createdMonth = c.CreatedDate != null
                ? String.valueOf(c.CreatedDate.month()) + '/' + String.valueOf(c.CreatedDate.year())
                : '';
            result.rows.add(row);

            tally(statusCount,   String.isBlank(c.Status)  ? KenSnSConstants.CASE_STATUS_NEW : c.Status);
            tally(categoryCount, String.isBlank(row.serviceOffering) ? 'Uncategorized' : row.serviceOffering);
            tally(rtCount,       String.isBlank(row.recordTypeName)  ? 'Standard'      : row.recordTypeName);
            tally(priorityCount, String.isBlank(row.priority)        ? 'None'          : row.priority);
            tally(ownerCount,    String.isBlank(row.ownerName)       ? 'Unassigned'    : row.ownerName);
            if (String.isNotBlank(row.createdMonth)) {
                tally(monthCount, row.createdMonth);
            }
        }

        String rt = reportType != null ? reportType : KenSnSConstants.REPORT_TYPE_STATUS;
        if (rt == KenSnSConstants.REPORT_TYPE_ALL_CASES || rt == KenSnSConstants.REPORT_TYPE_STATUS) {
            result.kpis = buildStatusKpis(total, statusCount);
        } else if (rt == KenSnSConstants.REPORT_TYPE_CATEGORY) {
            result.kpis = buildCategoryKpis(total, categoryCount);
        } else if (rt == KenSnSConstants.REPORT_TYPE_RECORD_TYPE) {
            result.kpis = buildRecordTypeKpis(total, rtCount);
        } else if (rt == KenSnSConstants.REPORT_TYPE_PRIORITY) {
            result.kpis = buildPriorityKpis(total, priorityCount);
        } else if (rt == KenSnSConstants.REPORT_TYPE_OWNER) {
            result.kpis = buildOwnerKpis(total, ownerCount);
        } else if (rt == KenSnSConstants.REPORT_TYPE_TREND) {
            result.kpis = buildTrendKpis(total, monthCount);
        }

        return result;
    }

    // ── KPI builders ──────────────────────────────────────────────────────────

    private static List<KpiItem> buildStatusKpis(Integer total, Map<String,Integer> sc) {
        Integer resolved   = safeGet(sc, KenSnSConstants.CASE_STATUS_RESOLVED) + safeGet(sc, KenSnSConstants.CASE_STATUS_CLOSED);
        Integer newCnt     = safeGet(sc, KenSnSConstants.CASE_STATUS_NEW);
        Integer inProgress = safeGet(sc, KenSnSConstants.CASE_STATUS_IN_PROGRESS)
                           + safeGet(sc, 'In Review')
                           + safeGet(sc, KenSnSConstants.CASE_STATUS_ON_HOLD)
                           + safeGet(sc, KenSnSConstants.CASE_STATUS_WAITING_FOR_STUDENT)
                           + safeGet(sc, 'Response Received');
        Integer canceled   = safeGet(sc, KenSnSConstants.CASE_STATUS_CANCELED) + safeGet(sc, 'Rejected');

        List<String>  allStatuses = new List<String>(sc.keySet());
        List<Decimal> allVals     = getValues(allStatuses, sc);

        List<KpiItem> kpis = new List<KpiItem>();

        kpis.add(makeKpi('Total Cases',  String.valueOf(total),     'All service requests', 'blue',
            'bar',   '#2563EB', allStatuses, allVals, buildColors(allStatuses.size()), null));

        kpis.add(makeKpi('Resolved',     String.valueOf(resolved),  'Resolved + Closed',    'green',
            'donut', '#059669',
            new List<String>{'Resolved','Others'},
            new List<Decimal>{resolved, Math.max(total - resolved, 0)},
            new List<String>{'#059669','#E5E7EB'},
            buildLegend(new List<String>{'Resolved','Others'},
                        new List<Decimal>{resolved, Math.max(total - resolved, 0)},
                        new List<String>{'#059669','#E5E7EB'})));

        kpis.add(makeKpi('Open',         String.valueOf(inProgress + newCnt), 'New + In Progress', 'orange',
            'donut', '#D97706',
            new List<String>{'New','In Progress','On Hold'},
            new List<Decimal>{newCnt, safeGet(sc, KenSnSConstants.CASE_STATUS_IN_PROGRESS), safeGet(sc, KenSnSConstants.CASE_STATUS_ON_HOLD)},
            new List<String>{'#FCD34D','#D97706','#92400E'},
            buildLegend(new List<String>{'New','In Progress','On Hold'},
                        new List<Decimal>{newCnt, safeGet(sc, KenSnSConstants.CASE_STATUS_IN_PROGRESS), safeGet(sc, KenSnSConstants.CASE_STATUS_ON_HOLD)},
                        new List<String>{'#FCD34D','#D97706','#92400E'})));

        kpis.add(makeKpi('Canceled',     String.valueOf(canceled),  'Canceled + Rejected',  'red',
            'donut', '#DC2626',
            new List<String>{'Canceled','Rejected','Active'},
            new List<Decimal>{safeGet(sc, KenSnSConstants.CASE_STATUS_CANCELED), safeGet(sc, 'Rejected'), Math.max(total - canceled, 0)},
            new List<String>{'#DC2626','#F87171','#E5E7EB'},
            buildLegend(new List<String>{'Canceled','Rejected','Active'},
                        new List<Decimal>{safeGet(sc, KenSnSConstants.CASE_STATUS_CANCELED), safeGet(sc, 'Rejected'), Math.max(total - canceled, 0)},
                        new List<String>{'#DC2626','#F87171','#E5E7EB'})));

        return kpis;
    }

    private static List<KpiItem> buildCategoryKpis(Integer total, Map<String,Integer> cc) {
        List<String>  catLabels = new List<String>(cc.keySet());
        List<Decimal> catVals   = getValues(catLabels, cc);
        List<String>  catColors = buildColors(catLabels.size());
        List<KpiItem> kpis = new List<KpiItem>();
        kpis.add(makeKpi('By Service', String.valueOf(total),
            String.valueOf(cc.size()) + ' service offerings', 'blue',
            'bar',   '#2563EB', catLabels, catVals, catColors, null));
        kpis.add(makeKpi('Distribution', String.valueOf(cc.size()),
            'Service categories', 'green',
            'donut', '#059669', catLabels, catVals, catColors, buildLegend(catLabels, catVals, catColors)));
        return kpis;
    }

    private static List<KpiItem> buildRecordTypeKpis(Integer total, Map<String,Integer> rc) {
        List<String>  rtLabels = new List<String>(rc.keySet());
        List<Decimal> rtVals   = getValues(rtLabels, rc);
        List<String>  rtColors = buildColors(rtLabels.size());
        List<KpiItem> kpis = new List<KpiItem>();
        kpis.add(makeKpi('By Record Type', String.valueOf(total),
            String.valueOf(rc.size()) + ' record types', 'blue',
            'donut', '#2563EB', rtLabels, rtVals, rtColors, buildLegend(rtLabels, rtVals, rtColors)));
        return kpis;
    }

    private static List<KpiItem> buildPriorityKpis(Integer total, Map<String,Integer> pc) {
        List<String>  priLabels = new List<String>{'High', 'Medium', 'Low'};
        List<Decimal> priVals   = new List<Decimal>{safeGet(pc,'High'), safeGet(pc,'Medium'), safeGet(pc,'Low')};
        List<KpiItem> kpis = new List<KpiItem>();
        kpis.add(makeKpi('By Priority', String.valueOf(total), 'Cases by priority level', 'orange',
            'bar', '#D97706', priLabels, priVals,
            new List<String>{'#DC2626','#D97706','#2563EB'}, null));
        return kpis;
    }

    private static List<KpiItem> buildOwnerKpis(Integer total, Map<String,Integer> oc) {
        List<String>  topOwners = topN(oc, 10);
        List<Decimal> ownerVals = getValues(topOwners, oc);
        List<KpiItem> kpis = new List<KpiItem>();
        kpis.add(makeKpi('By Agent', String.valueOf(total),
            String.valueOf(oc.size()) + ' agents', 'green',
            'hbar', '#059669', topOwners, ownerVals, buildColors(topOwners.size()), null));
        return kpis;
    }

    private static List<KpiItem> buildTrendKpis(Integer total, Map<String,Integer> mc) {
        List<String>  mLabels = new List<String>(mc.keySet());
        List<Decimal> mVals   = getValues(mLabels, mc);
        List<KpiItem> kpis = new List<KpiItem>();
        kpis.add(makeKpi('Monthly Trend', String.valueOf(total),
            'Cases created per month', 'blue',
            'bar', '#2563EB', mLabels, mVals, buildColors(mLabels.size()), null));
        return kpis;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static KpiItem makeKpi(
        String label, String value, String sub, String color,
        String chartType, String dotColor,
        List<String> chartLabels, List<Decimal> chartValues,
        List<String> chartColors, List<LegendItem> legend
    ) {
        KpiItem k      = new KpiItem();
        k.label        = label;
        k.value        = value;
        k.sub          = sub;
        k.color        = color;
        k.chartType    = chartType;
        k.dotColor     = dotColor;
        k.chartLabels  = chartLabels;
        k.chartValues  = chartValues;
        k.chartColors  = chartColors;
        k.legend       = legend != null ? legend : new List<LegendItem>();
        return k;
    }

    private static Integer safeGet(Map<String,Integer> m, String key) {
        return (m.containsKey(key) && m.get(key) != null) ? m.get(key) : 0;
    }

    private static void tally(Map<String,Integer> m, String key) {
        m.put(key, safeGet(m, key) + 1);
    }

    private static List<Decimal> getValues(List<String> labels, Map<String,Integer> m) {
        List<Decimal> vals = new List<Decimal>();
        for (String l : labels) {
            vals.add(safeGet(m, l));
        }
        return vals;
    }

    private static List<String> buildColors(Integer size) {
        List<String> palette = new List<String>{
            '#2563EB','#059669','#D97706','#DC2626','#8B5CF6',
            '#0D9488','#DB2777','#1D4ED8','#15803D','#B45309'
        };
        List<String> result = new List<String>();
        for (Integer i = 0; i < size; i++) {
            result.add(palette[Math.mod(i, palette.size())]);
        }
        return result;
    }

    private static List<LegendItem> buildLegend(
        List<String> labels, List<Decimal> values, List<String> colors
    ) {
        List<LegendItem> legend = new List<LegendItem>();
        for (Integer i = 0; i < labels.size(); i++) {
            LegendItem li = new LegendItem();
            li.label = labels[i];
            li.value = String.valueOf(values[i].intValue());
            li.color = i < colors.size() ? colors[i] : '#2563EB';
            legend.add(li);
        }
        return legend;
    }

    private static List<String> topN(Map<String,Integer> m, Integer n) {
        List<String> keys = new List<String>(m.keySet());
        for (Integer i = 0; i < keys.size() - 1; i++) {
            for (Integer j = 0; j < keys.size() - i - 1; j++) {
                if (safeGet(m, keys[j]) < safeGet(m, keys[j + 1])) {
                    String tmp = keys[j];
                    keys[j]    = keys[j + 1];
                    keys[j + 1] = tmp;
                }
            }
        }
        if (keys.size() <= n) return keys;
        List<String> capped = new List<String>();
        for (Integer i = 0; i < n; i++) { capped.add(keys[i]); }
        return capped;
    }

    private static Date resolveStartDate(String dateRange) {
        if (String.isBlank(dateRange) || dateRange == 'all') return null;
        Date today = Date.today();
        if (dateRange == 'thisMonth')  return Date.newInstance(today.year(), today.month(), 1);
        if (dateRange == 'lastMonth')  return Date.newInstance(today.year(), today.month(), 1).addMonths(-1);
        if (dateRange == 'thisYear')   return Date.newInstance(today.year(), 1, 1);
        if (dateRange == 'last90')     return today.addDays(-90);
        if (dateRange == 'last30')     return today.addDays(-30);
        return null;
    }
}