public with sharing class KenMentorshipDashboardController {

    private static final Integer MAX_ROWS  = 2000;
    private static final Integer TOP_COUNT = 10;

    // ── Inner types ───────────────────────────────────────────────────────────
    public class ChartPoint {
        @AuraEnabled public String  label;
        @AuraEnabled public Integer value;
        ChartPoint(String l, Integer v) { label = l; value = v; }
    }

    public class SummaryStats {
        @AuraEnabled public Integer total             = 0;
        @AuraEnabled public Integer activeConnections = 0;
        @AuraEnabled public Integer pendingRequests   = 0;
        @AuraEnabled public Integer callsCompleted    = 0;
        @AuraEnabled public Integer totalCalls        = 0;
        @AuraEnabled public Decimal completionRate    = 0;
    }

    public class MentorshipRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String recordType;
        @AuraEnabled public String mentorId;
        @AuraEnabled public String mentorName;
        @AuraEnabled public String menteeId;
        @AuraEnabled public String menteeName;
        @AuraEnabled public String status;
        @AuraEnabled public String meetingMode;
        @AuraEnabled public String meetDate;
        @AuraEnabled public String meetingTitle;
    }

    // ── WHERE clause helpers ──────────────────────────────────────────────────
    //
    // Filter values travel as bind variables rather than being escaped into the
    // query text. Each bind is added to the map in the same branch that adds the
    // condition referencing it, so a clause can never name a bind the map is
    // missing - Database.*WithBinds throws on that.
    private static List<String> buildConds(String statusFilter, String rtFilter, String yearFilter, Map<String, Object> binds) {
        List<String> conds = new List<String>();

        if (!String.isBlank(rtFilter) && rtFilter != 'All') {
            binds.put('bRt', rtFilter);
            conds.add('RecordType.DeveloperName = :bRt');
        }

        if (!String.isBlank(statusFilter) && statusFilter != 'All') {
            binds.put('bStatus', statusFilter);
            if (rtFilter == 'Call_Request') {
                conds.add('Call_Request_Status__c = :bStatus');
            } else if (rtFilter == 'Connection_Request') {
                conds.add('Mentorship_Status__c = :bStatus');
            } else {
                conds.add('(Mentorship_Status__c = :bStatus OR Call_Request_Status__c = :bStatus)');
            }
        }

        if (!String.isBlank(yearFilter) && yearFilter != 'All') {
            try {
                Integer yr = Integer.valueOf(yearFilter);
                if (yr > 1900) {
                    binds.put('bYear', yr);
                    conds.add('CALENDAR_YEAR(CreatedDate) = :bYear');
                }
            } catch (Exception e) {}
        }
        return conds;
    }

    private static Boolean isValidId(String val) {
        if (String.isBlank(val)) return false;
        if (val.length() != 15 && val.length() != 18) return false;
        try { Id.valueOf(val); return true; } catch (Exception e) { return false; }
    }

    private static String whereClause(List<String> conds) {
        return conds.isEmpty() ? '' : ' WHERE ' + String.join(conds, ' AND ');
    }

    private static String andClause(List<String> conds) {
        return conds.isEmpty() ? '' : ' AND ' + String.join(conds, ' AND ');
    }

    private static List<ChartPoint> sortedTop(List<ChartPoint> pts, Integer maxCount) {
        Map<String, ChartPoint> keyMap = new Map<String, ChartPoint>();
        for (Integer i = 0; i < pts.size(); i++) {
            String key = String.valueOf(10000000 - pts[i].value).leftPad(10, '0') + String.valueOf(i);
            keyMap.put(key, pts[i]);
        }
        List<String> sorted = new List<String>(keyMap.keySet());
        sorted.sort();
        List<ChartPoint> result = new List<ChartPoint>();
        for (String k : sorted) {
            result.add(keyMap.get(k));
            if (result.size() >= maxCount) break;
        }
        return result;
    }

    // ── getSummaryStats ───────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static SummaryStats getSummaryStats(String statusFilter, String rtFilter, String yearFilter) {
        SummaryStats stats = new SummaryStats();
        try {
            Map<String, Object> binds = new Map<String, Object>();

            // Year-only conds (no status / rt filter) for global connection/call counts
            List<String> yearCond = new List<String>();
            if (!String.isBlank(yearFilter) && yearFilter != 'All') {
                try {
                    Integer yr = Integer.valueOf(yearFilter);
                    if (yr > 1900) { binds.put('bYear', yr); yearCond.add('CALENDAR_YEAR(CreatedDate) = :bYear'); }
                } catch(Exception e){}
            }

            // Total respecting all filters
            List<String> allConds = buildConds(statusFilter, rtFilter, yearFilter, binds);
            stats.total = Database.countQueryWithBinds('SELECT COUNT() FROM Ken_Mentorship__c' + whereClause(allConds), binds, AccessLevel.SYSTEM_MODE);

            // Active connections (Connection_Request + Accepted)
            List<String> connConds = new List<String>{'RecordType.DeveloperName = \'Connection_Request\'', 'Mentorship_Status__c = \'Accepted\''};
            connConds.addAll(yearCond);
            stats.activeConnections = Database.countQueryWithBinds('SELECT COUNT() FROM Ken_Mentorship__c' + whereClause(connConds), binds, AccessLevel.SYSTEM_MODE);

            // Pending (Connection_Request + Requested)
            List<String> pendConds = new List<String>{'RecordType.DeveloperName = \'Connection_Request\'', 'Mentorship_Status__c = \'Requested\''};
            pendConds.addAll(yearCond);
            stats.pendingRequests = Database.countQueryWithBinds('SELECT COUNT() FROM Ken_Mentorship__c' + whereClause(pendConds), binds, AccessLevel.SYSTEM_MODE);

            // Call totals
            List<String> callConds = new List<String>{'RecordType.DeveloperName = \'Call_Request\''};
            callConds.addAll(yearCond);
            stats.totalCalls = Database.countQueryWithBinds('SELECT COUNT() FROM Ken_Mentorship__c' + whereClause(callConds), binds, AccessLevel.SYSTEM_MODE);

            List<String> doneConds = new List<String>{'RecordType.DeveloperName = \'Call_Request\'', 'Call_Request_Status__c = \'Completed\''};
            doneConds.addAll(yearCond);
            stats.callsCompleted = Database.countQueryWithBinds('SELECT COUNT() FROM Ken_Mentorship__c' + whereClause(doneConds), binds, AccessLevel.SYSTEM_MODE);

            stats.completionRate = stats.totalCalls > 0
                ? ((Decimal)stats.callsCompleted / stats.totalCalls * 100).setScale(1)
                : 0;
        } catch (Exception e) { System.debug('getSummaryStats: ' + e.getMessage()); }
        return stats;
    }

    // ── getMentorshipByStatus (Connection Requests) ───────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getMentorshipByStatus(String statusFilter, String yearFilter) {
        List<ChartPoint> result = new List<ChartPoint>();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = new List<String>{'RecordType.DeveloperName = \'Connection_Request\''};
            if (!String.isBlank(statusFilter) && statusFilter != 'All') {
                binds.put('bStatus', statusFilter);
                conds.add('Mentorship_Status__c = :bStatus');
            }
            if (!String.isBlank(yearFilter) && yearFilter != 'All') {
                try { Integer yr = Integer.valueOf(yearFilter); if (yr > 1900) { binds.put('bYear', yr); conds.add('CALENDAR_YEAR(CreatedDate) = :bYear'); } } catch(Exception e){}
            }
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                    'SELECT Mentorship_Status__c s, COUNT(Id) cnt FROM Ken_Mentorship__c'
                    + whereClause(conds) + ' GROUP BY Mentorship_Status__c', binds, AccessLevel.SYSTEM_MODE)) {
                String lbl = (String)ar.get('s');
                if (lbl == null) lbl = 'Unknown';
                result.add(new ChartPoint(lbl, (Integer)ar.get('cnt')));
            }
        } catch (Exception e) { System.debug('getMentorshipByStatus: ' + e.getMessage()); }
        return result;
    }

    // ── getCallByStatus (Call Requests) ───────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getCallByStatus(String statusFilter, String yearFilter) {
        List<ChartPoint> result = new List<ChartPoint>();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = new List<String>{'RecordType.DeveloperName = \'Call_Request\''};
            if (!String.isBlank(statusFilter) && statusFilter != 'All') {
                binds.put('bStatus', statusFilter);
                conds.add('Call_Request_Status__c = :bStatus');
            }
            if (!String.isBlank(yearFilter) && yearFilter != 'All') {
                try { Integer yr = Integer.valueOf(yearFilter); if (yr > 1900) { binds.put('bYear', yr); conds.add('CALENDAR_YEAR(CreatedDate) = :bYear'); } } catch(Exception e){}
            }
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                    'SELECT Call_Request_Status__c s, COUNT(Id) cnt FROM Ken_Mentorship__c'
                    + whereClause(conds) + ' GROUP BY Call_Request_Status__c', binds, AccessLevel.SYSTEM_MODE)) {
                String lbl = (String)ar.get('s');
                if (lbl == null) lbl = 'Unknown';
                result.add(new ChartPoint(lbl, (Integer)ar.get('cnt')));
            }
        } catch (Exception e) { System.debug('getCallByStatus: ' + e.getMessage()); }
        return result;
    }

    // ── getMonthlyTrend ───────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getMonthlyTrend(String statusFilter, String rtFilter, String yearFilter) {
        List<ChartPoint> result = new List<ChartPoint>();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(statusFilter, rtFilter, yearFilter, binds);
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                    'SELECT CALENDAR_MONTH(CreatedDate) mo, COUNT(Id) cnt FROM Ken_Mentorship__c'
                    + whereClause(conds) + ' GROUP BY CALENDAR_MONTH(CreatedDate)', binds, AccessLevel.SYSTEM_MODE)) {
                Integer mo = (Integer)ar.get('mo');
                String[] months = new String[]{'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
                result.add(new ChartPoint(months[mo - 1], (Integer)ar.get('cnt')));
            }
        } catch (Exception e) { System.debug('getMonthlyTrend: ' + e.getMessage()); }
        return result;
    }

    // ── getMeetingMode ────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getMeetingMode(String statusFilter, String rtFilter, String yearFilter) {
        List<ChartPoint> result = new List<ChartPoint>();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(statusFilter, rtFilter, yearFilter, binds);
            conds.add('Meeting_Mode__c != null');
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                    'SELECT Meeting_Mode__c s, COUNT(Id) cnt FROM Ken_Mentorship__c'
                    + whereClause(conds) + ' GROUP BY Meeting_Mode__c', binds, AccessLevel.SYSTEM_MODE)) {
                String lbl = (String)ar.get('s');
                if (lbl == null) lbl = 'Not Set';
                result.add(new ChartPoint(lbl, (Integer)ar.get('cnt')));
            }
        } catch (Exception e) { System.debug('getMeetingMode: ' + e.getMessage()); }
        return result;
    }

    // ── getTopMentors ─────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopMentors(String statusFilter, String rtFilter, String yearFilter) {
        List<ChartPoint> result = new List<ChartPoint>();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(statusFilter, rtFilter, yearFilter, binds);
            String ac = andClause(conds);
            List<AggregateResult> rows = (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Mentor__c pid, COUNT(Id) cnt FROM Ken_Mentorship__c'
                + ' WHERE Mentor__c != null' + ac + ' GROUP BY Mentor__c', binds, AccessLevel.SYSTEM_MODE);

            Map<Id, Integer> countMap = new Map<Id, Integer>();
            for (AggregateResult ar : rows) countMap.put((Id)ar.get('pid'), (Integer)ar.get('cnt'));

            Map<Id, String> nameMap = new Map<Id, String>();
            for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :countMap.keySet() WITH USER_MODE LIMIT 200]) {
                nameMap.put(a.Id, a.Name);
            }

            List<ChartPoint> pts = new List<ChartPoint>();
            for (Id pid : countMap.keySet()) {
                String lbl = nameMap.containsKey(pid) ? nameMap.get(pid) : String.valueOf(pid);
                pts.add(new ChartPoint(lbl, countMap.get(pid)));
            }
            result = sortedTop(pts, TOP_COUNT);
        } catch (Exception e) { System.debug('getTopMentors: ' + e.getMessage()); }
        return result;
    }

    // ── getTopMentees ─────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopMentees(String statusFilter, String rtFilter, String yearFilter) {
        List<ChartPoint> result = new List<ChartPoint>();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(statusFilter, rtFilter, yearFilter, binds);
            String ac = andClause(conds);
            List<AggregateResult> rows = (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Mentee__c pid, COUNT(Id) cnt FROM Ken_Mentorship__c'
                + ' WHERE Mentee__c != null' + ac + ' GROUP BY Mentee__c', binds, AccessLevel.SYSTEM_MODE);

            Map<Id, Integer> countMap = new Map<Id, Integer>();
            for (AggregateResult ar : rows) countMap.put((Id)ar.get('pid'), (Integer)ar.get('cnt'));

            Map<Id, String> nameMap = new Map<Id, String>();
            for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :countMap.keySet() WITH USER_MODE LIMIT 200]) {
                nameMap.put(a.Id, a.Name);
            }

            List<ChartPoint> pts = new List<ChartPoint>();
            for (Id pid : countMap.keySet()) {
                String lbl = nameMap.containsKey(pid) ? nameMap.get(pid) : String.valueOf(pid);
                pts.add(new ChartPoint(lbl, countMap.get(pid)));
            }
            result = sortedTop(pts, TOP_COUNT);
        } catch (Exception e) { System.debug('getTopMentees: ' + e.getMessage()); }
        return result;
    }

    // ── getByRecordType ───────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getByRecordType(String statusFilter, String yearFilter) {
        List<ChartPoint> result = new List<ChartPoint>();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = new List<String>();
            if (!String.isBlank(statusFilter) && statusFilter != 'All') {
                binds.put('bStatus', statusFilter);
                conds.add('(Mentorship_Status__c = :bStatus OR Call_Request_Status__c = :bStatus)');
            }
            if (!String.isBlank(yearFilter) && yearFilter != 'All') {
                try { Integer yr = Integer.valueOf(yearFilter); if (yr > 1900) { binds.put('bYear', yr); conds.add('CALENDAR_YEAR(CreatedDate) = :bYear'); } } catch(Exception e){}
            }
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                    'SELECT RecordType.DeveloperName rt, COUNT(Id) cnt FROM Ken_Mentorship__c'
                    + whereClause(conds) + ' GROUP BY RecordType.DeveloperName', binds, AccessLevel.SYSTEM_MODE)) {
                String rt = (String)ar.get('rt');
                String lbl = rt == 'Connection_Request' ? 'Connection Requests' : (rt == 'Call_Request' ? 'Call Requests' : rt);
                result.add(new ChartPoint(lbl, (Integer)ar.get('cnt')));
            }
        } catch (Exception e) { System.debug('getByRecordType: ' + e.getMessage()); }
        return result;
    }

    // ── getYearlyGrowth ───────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getYearlyGrowth() {
        List<ChartPoint> result = new List<ChartPoint>();
        try {
            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(CreatedDate) yr, COUNT(Id) cnt
                FROM Ken_Mentorship__c
                WITH USER_MODE
                GROUP BY CALENDAR_YEAR(CreatedDate)
                ORDER BY CALENDAR_YEAR(CreatedDate) ASC]) {
                result.add(new ChartPoint(String.valueOf((Integer)ar.get('yr')), (Integer)ar.get('cnt')));
            }
        } catch (Exception e) { System.debug('getYearlyGrowth: ' + e.getMessage()); }
        return result;
    }

    // ── getAvailableYears ─────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableYears() {
        List<String> years = new List<String>{'All'};
        try {
            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(CreatedDate) yr FROM Ken_Mentorship__c
                WITH USER_MODE
                GROUP BY CALENDAR_YEAR(CreatedDate)
                ORDER BY CALENDAR_YEAR(CreatedDate) DESC]) {
                years.add(String.valueOf((Integer)ar.get('yr')));
            }
        } catch (Exception e) {}
        return years;
    }

    // ── getMentorshipList (imperative) ────────────────────────────────────────
    @AuraEnabled
    public static List<MentorshipRecord> getMentorshipList(
            String title, String dimension, String value,
            String statusFilter, String rtFilter, String yearFilter) {
        List<MentorshipRecord> result = new List<MentorshipRecord>();
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(statusFilter, rtFilter, yearFilter, binds);

            if (!String.isBlank(dimension) && !String.isBlank(value)) {
                binds.put('bVal', value);
                if (dimension == 'rt_type') {
                    conds.add('RecordType.DeveloperName = :bVal');
                } else if (dimension == 'status') {
                    if (rtFilter == 'Call_Request') {
                        conds.add('Call_Request_Status__c = :bVal');
                    } else if (rtFilter == 'Connection_Request') {
                        conds.add('Mentorship_Status__c = :bVal');
                    } else {
                        conds.add('(Mentorship_Status__c = :bVal OR Call_Request_Status__c = :bVal)');
                    }
                } else if (dimension == 'call_status') {
                    conds.add('RecordType.DeveloperName = \'Call_Request\'');
                    conds.add('Call_Request_Status__c = :bVal');
                } else if (dimension == 'conn_status') {
                    conds.add('RecordType.DeveloperName = \'Connection_Request\'');
                    conds.add('Mentorship_Status__c = :bVal');
                } else if (dimension == 'mentor') {
                    conds.add(isValidId(value) ? 'Mentor__c = :bVal' : 'Mentor__r.Name = :bVal');
                } else if (dimension == 'mentee') {
                    conds.add(isValidId(value) ? 'Mentee__c = :bVal' : 'Mentee__r.Name = :bVal');
                } else if (dimension == 'mode') {
                    conds.add('Meeting_Mode__c = :bVal');
                }
            }

            String q = 'SELECT Id, Name, RecordType.DeveloperName, Mentor__c, Mentor__r.Name,'
                + ' Mentee__c, Mentee__r.Name, Mentorship_Status__c, Call_Request_Status__c,'
                + ' Meeting_Mode__c, Meet_Start_DateTime__c, Meeting_Title__c'
                + ' FROM Ken_Mentorship__c' + whereClause(conds)
                + ' ORDER BY CreatedDate DESC LIMIT ' + MAX_ROWS;

            for (SObject so : Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                MentorshipRecord r = new MentorshipRecord();
                r.id           = String.valueOf(so.get('Id'));
                r.name         = String.valueOf(so.get('Name'));
                r.recordType   = (String)((SObject)so.getSObject('RecordType'))?.get('DeveloperName');
                r.mentorId     = String.valueOf(so.get(KenNamespaceUtil.qualifyCustom('Mentor__c')));
                r.mentorName   = (String)so.getSObject('Mentor__r')?.get('Name');
                r.menteeId     = String.valueOf(so.get(KenNamespaceUtil.qualifyCustom('Mentee__c')));
                r.menteeName   = (String)so.getSObject('Mentee__r')?.get('Name');

                String connStatus = (String)so.get(KenNamespaceUtil.qualifyCustom('Mentorship_Status__c'));
                String callStatus = (String)so.get(KenNamespaceUtil.qualifyCustom('Call_Request_Status__c'));
                r.status = r.recordType == 'Call_Request' ? callStatus : connStatus;

                r.meetingMode  = (String)so.get(KenNamespaceUtil.qualifyCustom('Meeting_Mode__c'));
                // Day derived from the one stored instant.
                Date md = KenDateTimeUtil.localDate((DateTime)so.get(KenNamespaceUtil.qualifyCustom('Meet_Start_DateTime__c')));
                r.meetDate     = md != null ? String.valueOf(md) : null;
                r.meetingTitle = (String)so.get(KenNamespaceUtil.qualifyCustom('Meeting_Title__c'));
                result.add(r);
            }
        } catch (Exception e) { System.debug('getMentorshipList: ' + e.getMessage()); }
        return result;
    }
}