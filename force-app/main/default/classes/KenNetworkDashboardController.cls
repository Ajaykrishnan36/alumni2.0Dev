public with sharing class KenNetworkDashboardController {

    // ── Inner classes ────────────────────────────────────────────────────────

    public class ChartPoint {
        @AuraEnabled public String  label;
        @AuraEnabled public Integer value;
        public ChartPoint(String l, Integer v) {
            this.label = l;
            this.value = v;
        }
    }

    public class SummaryStats {
        @AuraEnabled public Integer total       = 0;
        @AuraEnabled public Integer accepted    = 0;
        @AuraEnabled public Integer pending     = 0;
        @AuraEnabled public Decimal avgTatDays  = 0;
    }

    public class ConnectionRecord {
        @AuraEnabled public String  id;
        @AuraEnabled public String  connectionName;
        @AuraEnabled public String  initiatorId;
        @AuraEnabled public String  initiatorName;
        @AuraEnabled public String  recipientId;
        @AuraEnabled public String  recipientName;
        @AuraEnabled public String  status;
        @AuraEnabled public String  requestedDate;
        @AuraEnabled public String  acceptedDate;
        @AuraEnabled public Integer tatDays;
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    // Filter values travel as bind variables rather than being escaped into the query
    // text. Each bind is added to the map in the same branch that adds the condition
    // referencing it, so a clause can never name a bind the map is missing.
    private static List<String> buildConds(String statusFilter, String yearFilter, Map<String, Object> binds) {
        List<String> conds = new List<String>();
        if (!String.isBlank(statusFilter) && statusFilter != 'All') {
            binds.put('bStatus', statusFilter);
            conds.add('Status__c = :bStatus');
        }
        if (!String.isBlank(yearFilter) && yearFilter != 'All') {
            try {
                Integer yr = Integer.valueOf(yearFilter);
                binds.put('bYear', yr);
                conds.add('CALENDAR_YEAR(CreatedDate) = :bYear');
            } catch (Exception e) {
                // silently ignore invalid year
            }
        }
        return conds;
    }

    private static String whereClause(List<String> conds) {
        if (conds == null || conds.isEmpty()) return '';
        return ' WHERE ' + String.join(conds, ' AND ');
    }

    private static String andClause(List<String> conds) {
        if (conds == null || conds.isEmpty()) return '';
        return ' AND ' + String.join(conds, ' AND ');
    }

    private static List<ChartPoint> sortedTop(List<ChartPoint> pts, Integer maxCount) {
        Map<String, ChartPoint> sortMap = new Map<String, ChartPoint>();
        for (Integer i = 0; i < pts.size(); i++) {
            ChartPoint p = pts[i];
            String key = String.valueOf(10000000 - p.value).leftPad(10, '0') + String.valueOf(i);
            sortMap.put(key, p);
        }
        List<String> keys = new List<String>(sortMap.keySet());
        keys.sort();
        List<ChartPoint> result = new List<ChartPoint>();
        for (Integer i = 0; i < keys.size() && i < maxCount; i++) {
            result.add(sortMap.get(keys[i]));
        }
        return result;
    }

    // ── Summary Stats ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static SummaryStats getSummaryStats(String statusFilter, String yearFilter) {
        SummaryStats stats = new SummaryStats();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(statusFilter, yearFilter, binds);
            String q = 'SELECT Status__c s, COUNT(Id) cnt FROM Ken_Network_Connection__c'
                + whereClause(conds)
                + ' GROUP BY Status__c';
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                Integer cnt = (Integer) ar.get('cnt');
                String  s   = (String)  ar.get('s');
                stats.total += cnt;
                if (s == 'Accepted')  stats.accepted += cnt;
                if (s == 'Requested') stats.pending  += cnt;
            }

            // Avg TAT
            List<String> yearConds = new List<String>();
            if (!String.isBlank(yearFilter) && yearFilter != 'All') {
                try {
                    Integer yr = Integer.valueOf(yearFilter);
                    binds.put('bYear', yr);
                    yearConds.add('CALENDAR_YEAR(CreatedDate) = :bYear');
                } catch (Exception e) { }
            }
            String tatBase = ' WHERE Status__c = \'Accepted\' AND Requested_Date__c != null AND Accepted_Date__c != null';
            if (!yearConds.isEmpty()) tatBase += ' AND ' + String.join(yearConds, ' AND ');
            List<Ken_Network_Connection__c> tatRecs = Database.queryWithBinds(
                'SELECT Requested_Date__c, Accepted_Date__c FROM Ken_Network_Connection__c'
                + tatBase + ' LIMIT 1000', binds, AccessLevel.SYSTEM_MODE
            );
            if (!tatRecs.isEmpty()) {
                Long totalMs = 0;
                for (Ken_Network_Connection__c r : tatRecs) {
                    totalMs += (r.Accepted_Date__c.getTime() - r.Requested_Date__c.getTime());
                }
                stats.avgTatDays = ((Decimal) totalMs / tatRecs.size() / 86400000).setScale(1);
            }
        } catch (Exception e) {
            return new SummaryStats();
        }
        return stats;
    }

    // ── Connections by Status ────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getConnectionsByStatus(String yearFilter) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(null, yearFilter, binds);
            String q = 'SELECT Status__c s, COUNT(Id) cnt FROM Ken_Network_Connection__c'
                + whereClause(conds)
                + ' GROUP BY Status__c ORDER BY COUNT(Id) DESC';
            List<ChartPoint> pts = new List<ChartPoint>();
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                pts.add(new ChartPoint((String) ar.get('s'), (Integer) ar.get('cnt')));
            }
            return pts;
        } catch (Exception e) {
            return new List<ChartPoint>();
        }
    }

    // ── Monthly Trend ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getMonthlyTrend(String statusFilter, String yearFilter) {
        try {
            Integer targetYear = Date.today().year();
            if (!String.isBlank(yearFilter) && yearFilter != 'All') {
                try { targetYear = Integer.valueOf(yearFilter); } catch (Exception e) { }
            }
            Map<String, Object> binds = new Map<String, Object>{ 'bYear' => targetYear };
            List<String> conds = new List<String>{ 'CALENDAR_YEAR(CreatedDate) = :bYear' };
            if (!String.isBlank(statusFilter) && statusFilter != 'All') {
                binds.put('bStatus', statusFilter);
                conds.add('Status__c = :bStatus');
            }
            String q = 'SELECT CALENDAR_MONTH(CreatedDate) mo, COUNT(Id) cnt FROM Ken_Network_Connection__c'
                + ' WHERE ' + String.join(conds, ' AND ')
                + ' GROUP BY CALENDAR_MONTH(CreatedDate)';
            Map<Integer, Integer> monthMap = new Map<Integer, Integer>();
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                monthMap.put((Integer) ar.get('mo'), (Integer) ar.get('cnt'));
            }
            List<String> monthLabels = new List<String>{
                'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
            };
            List<ChartPoint> pts = new List<ChartPoint>();
            for (Integer m = 1; m <= 12; m++) {
                pts.add(new ChartPoint(monthLabels[m - 1], monthMap.containsKey(m) ? monthMap.get(m) : 0));
            }
            return pts;
        } catch (Exception e) {
            List<String> monthLabels = new List<String>{
                'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
            };
            List<ChartPoint> pts = new List<ChartPoint>();
            for (String lbl : monthLabels) pts.add(new ChartPoint(lbl, 0));
            return pts;
        }
    }

    // ── Avg TAT by Month ─────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getAvgTatByMonth(String yearFilter) {
        try {
            Integer targetYear = Date.today().year();
            if (!String.isBlank(yearFilter) && yearFilter != 'All') {
                try { targetYear = Integer.valueOf(yearFilter); } catch (Exception e) { }
            }
            DateTime startDT = DateTime.newInstance(targetYear,     1, 1, 0, 0, 0);
            DateTime endDT   = DateTime.newInstance(targetYear + 1, 1, 1, 0, 0, 0);
            List<Ken_Network_Connection__c> recs = [
                SELECT Requested_Date__c, Accepted_Date__c
                FROM Ken_Network_Connection__c
                WHERE Status__c = 'Accepted'
                  AND Requested_Date__c != null
                  AND Accepted_Date__c  != null
                  AND Accepted_Date__c  >= :startDT
                  AND Accepted_Date__c  <  :endDT
                WITH USER_MODE
                LIMIT 2000
            ];
            Map<Integer, Long>    totalMsMap = new Map<Integer, Long>();
            Map<Integer, Integer> countMap   = new Map<Integer, Integer>();
            for (Ken_Network_Connection__c r : recs) {
                Integer mo = r.Accepted_Date__c.month();
                Long    ms = r.Accepted_Date__c.getTime() - r.Requested_Date__c.getTime();
                totalMsMap.put(mo, (totalMsMap.containsKey(mo) ? totalMsMap.get(mo) : 0L) + ms);
                countMap.put(mo,   (countMap.containsKey(mo)   ? countMap.get(mo)   : 0)  + 1);
            }
            List<String> monthLabels = new List<String>{
                'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
            };
            List<ChartPoint> pts = new List<ChartPoint>();
            for (Integer m = 1; m <= 12; m++) {
                Integer avgDays = 0;
                if (countMap.containsKey(m) && countMap.get(m) > 0) {
                    avgDays = (Integer) Math.round((Decimal) totalMsMap.get(m) / countMap.get(m) / 86400000);
                }
                pts.add(new ChartPoint(monthLabels[m - 1], avgDays));
            }
            return pts;
        } catch (Exception e) {
            List<String> monthLabels = new List<String>{
                'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
            };
            List<ChartPoint> pts = new List<ChartPoint>();
            for (String lbl : monthLabels) pts.add(new ChartPoint(lbl, 0));
            return pts;
        }
    }

    // ── Top Connectors ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopConnectors(String statusFilter, String yearFilter) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            String ac = andClause(buildConds(statusFilter, yearFilter, binds));
            Map<Id, Integer> countMap = new Map<Id, Integer>();

            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Initiator__c pid, COUNT(Id) cnt FROM Ken_Network_Connection__c'
                + ' WHERE Initiator__c != null' + ac + ' GROUP BY Initiator__c', binds, AccessLevel.SYSTEM_MODE
            )) {
                Id pid = (Id) ar.get('pid');
                countMap.put(pid, (countMap.containsKey(pid) ? countMap.get(pid) : 0) + (Integer) ar.get('cnt'));
            }
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Recipient__c pid, COUNT(Id) cnt FROM Ken_Network_Connection__c'
                + ' WHERE Recipient__c != null' + ac + ' GROUP BY Recipient__c', binds, AccessLevel.SYSTEM_MODE
            )) {
                Id pid = (Id) ar.get('pid');
                countMap.put(pid, (countMap.containsKey(pid) ? countMap.get(pid) : 0) + (Integer) ar.get('cnt'));
            }
            Map<Id, Account> accMap = new Map<Id, Account>([
                SELECT Id, Name FROM Account WHERE Id IN :countMap.keySet()
            WITH USER_MODE
            ]);
            List<ChartPoint> pts = new List<ChartPoint>();
            for (Id pid : countMap.keySet()) {
                String nm = accMap.containsKey(pid) ? accMap.get(pid).Name : String.valueOf(pid);
                pts.add(new ChartPoint(nm, countMap.get(pid)));
            }
            return sortedTop(pts, 10);
        } catch (Exception e) {
            return new List<ChartPoint>();
        }
    }

    // ── Top Senders ──────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopSenders(String statusFilter, String yearFilter) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            String ac = andClause(buildConds(statusFilter, yearFilter, binds));
            Map<Id, Integer> countMap = new Map<Id, Integer>();
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Initiator__c pid, COUNT(Id) cnt FROM Ken_Network_Connection__c'
                + ' WHERE Initiator__c != null' + ac + ' GROUP BY Initiator__c LIMIT 10', binds, AccessLevel.SYSTEM_MODE
            )) {
                Id pid = (Id) ar.get('pid');
                countMap.put(pid, (countMap.containsKey(pid) ? countMap.get(pid) : 0) + (Integer) ar.get('cnt'));
            }
            Map<Id, Account> accMap = new Map<Id, Account>([
                SELECT Id, Name FROM Account WHERE Id IN :countMap.keySet()
            WITH USER_MODE
            ]);
            List<ChartPoint> pts = new List<ChartPoint>();
            for (Id pid : countMap.keySet()) {
                String nm = accMap.containsKey(pid) ? accMap.get(pid).Name : String.valueOf(pid);
                pts.add(new ChartPoint(nm, countMap.get(pid)));
            }
            return sortedTop(pts, 10);
        } catch (Exception e) {
            return new List<ChartPoint>();
        }
    }

    // ── Top Receivers ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopReceivers(String statusFilter, String yearFilter) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            String ac = andClause(buildConds(statusFilter, yearFilter, binds));
            Map<Id, Integer> countMap = new Map<Id, Integer>();
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Recipient__c pid, COUNT(Id) cnt FROM Ken_Network_Connection__c'
                + ' WHERE Recipient__c != null' + ac + ' GROUP BY Recipient__c LIMIT 10', binds, AccessLevel.SYSTEM_MODE
            )) {
                Id pid = (Id) ar.get('pid');
                countMap.put(pid, (countMap.containsKey(pid) ? countMap.get(pid) : 0) + (Integer) ar.get('cnt'));
            }
            Map<Id, Account> accMap = new Map<Id, Account>([
                SELECT Id, Name FROM Account WHERE Id IN :countMap.keySet()
            WITH USER_MODE
            ]);
            List<ChartPoint> pts = new List<ChartPoint>();
            for (Id pid : countMap.keySet()) {
                String nm = accMap.containsKey(pid) ? accMap.get(pid).Name : String.valueOf(pid);
                pts.add(new ChartPoint(nm, countMap.get(pid)));
            }
            return sortedTop(pts, 10);
        } catch (Exception e) {
            return new List<ChartPoint>();
        }
    }

    // ── Yearly Growth ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getYearlyGrowth(String statusFilter) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = new List<String>();
            if (!String.isBlank(statusFilter) && statusFilter != 'All') {
                binds.put('bStatus', statusFilter);
                conds.add('Status__c = :bStatus');
            }
            String q = 'SELECT CALENDAR_YEAR(CreatedDate) yr, COUNT(Id) cnt'
                + ' FROM Ken_Network_Connection__c'
                + whereClause(conds)
                + ' GROUP BY CALENDAR_YEAR(CreatedDate) ORDER BY CALENDAR_YEAR(CreatedDate) ASC';
            List<ChartPoint> pts = new List<ChartPoint>();
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                pts.add(new ChartPoint(String.valueOf(ar.get('yr')), (Integer) ar.get('cnt')));
            }
            return pts;
        } catch (Exception e) {
            return new List<ChartPoint>();
        }
    }

    // ── Filter Options ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static Map<String, List<String>> getFilterOptions() {
        try {
            Map<String, List<String>> opts = new Map<String, List<String>>();
            opts.put('statuses', new List<String>{
                'Requested', 'Accepted', 'Rejected', 'Cancelled', 'Blocked'
            });
            List<Integer> yearInts = new List<Integer>();
            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(CreatedDate) yr
                FROM Ken_Network_Connection__c
                WITH USER_MODE
                GROUP BY CALENDAR_YEAR(CreatedDate)
                ORDER BY CALENDAR_YEAR(CreatedDate) ASC
            ]) {
                yearInts.add((Integer) ar.get('yr'));
            }
            List<String> yearStrs = new List<String>();
            for (Integer yr : yearInts) yearStrs.add(String.valueOf(yr));
            opts.put('years', yearStrs);
            return opts;
        } catch (Exception e) {
            return new Map<String, List<String>>();
        }
    }

    // ── Connection List (drill-down) ─────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ConnectionRecord> getConnectionList(
        String dimension, String value, String statusFilter, String yearFilter
    ) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(statusFilter, yearFilter, binds);
            binds.put('bVal', value == null ? '' : value);

            if (dimension == 'status') {
                conds.add('Status__c = :bVal');
            } else if (dimension == 'accepted') {
                conds.add('Status__c = \'Accepted\'');
            } else if (dimension == 'pending') {
                conds.add('Status__c = \'Requested\'');
            } else if (dimension == 'negative') {
                conds.add('Status__c IN (\'Rejected\',\'Cancelled\',\'Blocked\')');
            } else if (dimension == 'initiator') {
                conds.add('Initiator__r.Name = :bVal');
            } else if (dimension == 'recipient') {
                conds.add('Recipient__r.Name = :bVal');
            } else if (dimension == 'connector') {
                conds.add('(Initiator__r.Name = :bVal OR Recipient__r.Name = :bVal)');
            }

            String q = 'SELECT Id, Name, Initiator__c, Initiator__r.Name, Recipient__c, Recipient__r.Name,'
                + ' Status__c, Requested_Date__c, Accepted_Date__c'
                + ' FROM Ken_Network_Connection__c'
                + whereClause(conds)
                + ' ORDER BY CreatedDate DESC LIMIT 500';

            List<ConnectionRecord> results = new List<ConnectionRecord>();
            for (Ken_Network_Connection__c r : (List<Ken_Network_Connection__c>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                ConnectionRecord rec = new ConnectionRecord();
                rec.id             = r.Id;
                rec.connectionName = r.Name;
                rec.initiatorId    = r.Initiator__c;
                rec.initiatorName  = r.Initiator__r != null ? r.Initiator__r.Name : null;
                rec.recipientId    = r.Recipient__c;
                rec.recipientName  = r.Recipient__r != null ? r.Recipient__r.Name : null;
                rec.status         = r.Status__c;
                rec.requestedDate  = r.Requested_Date__c != null
                    ? r.Requested_Date__c.format('MMM d, yyyy') : null;
                rec.acceptedDate   = r.Accepted_Date__c != null
                    ? r.Accepted_Date__c.format('MMM d, yyyy') : null;
                if (r.Requested_Date__c != null && r.Accepted_Date__c != null) {
                    rec.tatDays = (Integer) Math.round(
                        (Decimal)(r.Accepted_Date__c.getTime() - r.Requested_Date__c.getTime()) / 86400000
                    );
                }
                results.add(rec);
            }
            return results;
        } catch (Exception e) {
            return new List<ConnectionRecord>();
        }
    }
}