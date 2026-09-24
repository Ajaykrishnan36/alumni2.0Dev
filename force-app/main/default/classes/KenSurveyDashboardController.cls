public with sharing class KenSurveyDashboardController {

    // ── Inner classes ────────────────────────────────────────────────────────

    public class ChartPoint {
        @AuraEnabled public String  label;
        @AuraEnabled public Integer value;
        ChartPoint(String l, Integer v) { label = l; value = v; }
    }

    public class SummaryStats {
        @AuraEnabled public Integer total    = 0;
        @AuraEnabled public Integer active   = 0;
        @AuraEnabled public Integer pending  = 0;
        @AuraEnabled public Integer responses = 0;
    }

    public class SurveyListRecord {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  questionnaire;
        @AuraEnabled public String  approvalStatus;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String  targetAudience;
        @AuraEnabled public String  startDate;
        @AuraEnabled public String  endDate;
        @AuraEnabled public Integer responseCount;
    }

    public class ResponseListRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String respondentName;
        @AuraEnabled public String surveyName;
        @AuraEnabled public String questionLabel;
        @AuraEnabled public String response;
        @AuraEnabled public String createdDate;
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private static Boolean isBlankOrAll(String v) {
        return String.isBlank(v) || v.equalsIgnoreCase('All');
    }

    // Filter values travel as bind variables rather than being escaped into the query
    // text. Each bind is added to the map in the same branch that adds the condition
    // referencing it, so a clause can never name a bind the map is missing.
    private static List<String> buildConds(String approvalStatus, String isActive, String year, Map<String, Object> binds) {
        List<String> conds = new List<String>();
        if (!isBlankOrAll(approvalStatus)) {
            binds.put('bApproval', approvalStatus);
            conds.add('Approval_Status__c = :bApproval');
        }
        if (!isBlankOrAll(isActive)) {
            if (isActive.equalsIgnoreCase('true'))
                conds.add('Is_Active__c = true');
            else if (isActive.equalsIgnoreCase('false'))
                conds.add('Is_Active__c = false');
        }
        if (!isBlankOrAll(year)) {
            try {
                Integer y = Integer.valueOf(year);
                binds.put('bYear', y);
                conds.add('CALENDAR_YEAR(CreatedDate) = :bYear');
            } catch (Exception e) { /* ignore invalid year */ }
        }
        return conds;
    }

    private static String toWhere(List<String> conds) {
        if (conds == null || conds.isEmpty()) return '';
        return ' WHERE ' + String.join(conds, ' AND ');
    }

    // Submissions link straight to the survey, so a survey-level filter resolves to the
    // matching survey ids, keeping each survey's name for relabelling.
    private static Map<Id, String> assessmentSurveyNames(List<String> surveyConds, Map<String, Object> binds) {
        Map<Id, String> nameBySurvey = new Map<Id, String>();
        for (Ken_Survey__c s : (List<Ken_Survey__c>) Database.queryWithBinds(
            'SELECT Id, Name, Assessment_Question_Set__c FROM Ken_Survey__c' + toWhere(surveyConds) + ' LIMIT 50000',
            binds, AccessLevel.SYSTEM_MODE
        )) {
            if (s.Assessment_Question_Set__c == null) continue;
            nameBySurvey.put(s.Id, s.Name);
        }
        return nameBySurvey;
    }

    private static Set<Id> assessmentQuestionSetIds(List<String> surveyConds, Map<String, Object> binds) {
        Set<Id> setIds = new Set<Id>();
        for (Ken_Survey__c s : (List<Ken_Survey__c>) Database.queryWithBinds(
            'SELECT Assessment_Question_Set__c FROM Ken_Survey__c' + toWhere(surveyConds) + ' LIMIT 50000',
            binds, AccessLevel.SYSTEM_MODE
        )) {
            if (s.Assessment_Question_Set__c != null) setIds.add(s.Assessment_Question_Set__c);
        }
        return setIds;
    }

    // ── Summary Stats ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static SummaryStats getSummaryStats(String approvalStatus, String isActive, String year) {
        try {
            SummaryStats stats = new SummaryStats();
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(approvalStatus, isActive, year, binds);
            String whereClause = toWhere(conds);

            // total, active, pending via aggregation
            String q = 'SELECT Is_Active__c isAct, Approval_Status__c appSt, COUNT(Id) cnt'
                     + ' FROM Ken_Survey__c'
                     + whereClause
                     + ' GROUP BY Is_Active__c, Approval_Status__c';
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                Integer cnt = (Integer) ar.get('cnt');
                stats.total += cnt;
                if (ar.get('isAct') == true) stats.active += cnt;
                String st = (String) ar.get('appSt');
                if ('Pending Approval'.equalsIgnoreCase(st)) stats.pending += cnt;
            }

            Map<String, Object> nameBinds = new Map<String, Object>();
            Map<Id, String> asmtSurveys = assessmentSurveyNames(buildConds(approvalStatus, isActive, year, nameBinds), nameBinds);
            if (!asmtSurveys.isEmpty()) {
                Set<Id> asmtIds = asmtSurveys.keySet();
                for (AggregateResult ar : [
                    SELECT COUNT(Id) cnt
                    FROM AssessmentQuestionResponse
                    WHERE Response_Category__c = 'Survey'
                      AND Assessment.Ken_Survey__c IN :asmtIds
                WITH USER_MODE
                ]) {
                    stats.responses += (Integer) ar.get('cnt');
                }
            }

            return stats;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Surveys by Approval Status ───────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getSurveysByApprovalStatus(String isActive, String year) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = new List<String>();
            if (!isBlankOrAll(isActive)) {
                if (isActive.equalsIgnoreCase('true'))       conds.add('Is_Active__c = true');
                else if (isActive.equalsIgnoreCase('false')) conds.add('Is_Active__c = false');
            }
            if (!isBlankOrAll(year)) {
                try {
                    Integer y = Integer.valueOf(year);
                    binds.put('bYear', y);
                    conds.add('CALENDAR_YEAR(CreatedDate) = :bYear');
                } catch (Exception e) { /* ignore */ }
            }
            String whereClause = toWhere(conds);
            String q = 'SELECT Approval_Status__c st, COUNT(Id) cnt FROM Ken_Survey__c'
                     + whereClause
                     + ' GROUP BY Approval_Status__c ORDER BY COUNT(Id) DESC';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                String lbl = (String) ar.get('st');
                result.add(new ChartPoint(String.isBlank(lbl) ? 'Unknown' : lbl, (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Surveys by Active Status ─────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getSurveysByActiveStatus(String approvalStatus, String year) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = new List<String>();
            if (!isBlankOrAll(approvalStatus)) {
                binds.put('bApproval', approvalStatus);
                conds.add('Approval_Status__c = :bApproval');
            }
            if (!isBlankOrAll(year)) {
                try {
                    Integer y = Integer.valueOf(year);
                    binds.put('bYear', y);
                    conds.add('CALENDAR_YEAR(CreatedDate) = :bYear');
                } catch (Exception e) { /* ignore */ }
            }
            String whereClause = toWhere(conds);
            String q = 'SELECT Is_Active__c isAct, COUNT(Id) cnt FROM Ken_Survey__c'
                     + whereClause
                     + ' GROUP BY Is_Active__c ORDER BY COUNT(Id) DESC';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE)) {
                Boolean actVal = (Boolean) ar.get('isAct');
                String lbl = (actVal == true) ? 'Active' : 'Inactive';
                result.add(new ChartPoint(lbl, (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Top Surveys by Responses ─────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopSurveysByResponses(String approvalStatus, String isActive, String year) {
        try {
            Map<String, Object> nameBinds = new Map<String, Object>();
            Map<Id, String> asmtSurveys = assessmentSurveyNames(buildConds(approvalStatus, isActive, year, nameBinds), nameBinds);
            List<ChartPoint> result = new List<ChartPoint>();
            if (asmtSurveys.isEmpty()) return result;

            Set<Id> asmtIds = asmtSurveys.keySet();
            for (AggregateResult ar : [
                SELECT Assessment.Ken_Survey__c sid, COUNT(Id) cnt
                FROM AssessmentQuestionResponse
                WHERE Assessment.Ken_Survey__c IN :asmtIds
                  AND Response_Category__c = 'Survey'
                WITH USER_MODE
                GROUP BY Assessment.Ken_Survey__c
                ORDER BY COUNT(Id) DESC
                LIMIT 10
            ]) {
                String lbl = asmtSurveys.get((Id) ar.get('sid'));
                result.add(new ChartPoint(String.isBlank(lbl) ? 'Unknown' : lbl, (Integer) ar.get('cnt')));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Question Type Distribution ───────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getQuestionTypeDistribution(String approvalStatus, String isActive, String year) {
        try {
            Map<String, Object> setBinds = new Map<String, Object>();
            Set<Id> asmtSetIds = assessmentQuestionSetIds(buildConds(approvalStatus, isActive, year, setBinds), setBinds);
            if (asmtSetIds.isEmpty()) return new List<ChartPoint>();

            Map<String, Integer> byType = new Map<String, Integer>();
            for (AggregateResult ar : [
                SELECT Ken_Question_Type__c qtype, COUNT(Id) cnt
                FROM AssessmentQuestionVersion
                WHERE AssessmentQuestion.Ken_Question_Set__c IN :asmtSetIds
                AND IsActive = true
                WITH USER_MODE
                GROUP BY Ken_Question_Type__c
            ]) {
                String lbl = (String) ar.get('qtype');
                String key = String.isBlank(lbl) ? 'Unknown' : lbl;
                byType.put(key, (byType.containsKey(key) ? byType.get(key) : 0) + (Integer) ar.get('cnt'));
            }
            List<ChartPoint> result = new List<ChartPoint>();
            for (String key : byType.keySet()) {
                result.add(new ChartPoint(key, byType.get(key)));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Response Trend (monthly) ─────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getResponseTrend(String approvalStatus, String isActive, String year) {
        try {
            Map<Integer, Integer> monthMap = new Map<Integer, Integer>();
            for (Integer m = 1; m <= 12; m++) monthMap.put(m, 0);

            Map<String, Object> nameBinds = new Map<String, Object>();
            Map<Id, String> asmtSurveys = assessmentSurveyNames(buildConds(approvalStatus, isActive, year, nameBinds), nameBinds);
            if (!asmtSurveys.isEmpty()) {
                Set<Id> asmtIds = asmtSurveys.keySet();
                for (AggregateResult ar : [
                    SELECT CALENDAR_MONTH(CreatedDate) mo, COUNT(Id) cnt
                    FROM AssessmentQuestionResponse
                    WHERE Assessment.Ken_Survey__c IN :asmtIds
                      AND Response_Category__c = 'Survey'
                    WITH USER_MODE
                    GROUP BY CALENDAR_MONTH(CreatedDate)
                ]) {
                    Integer mo  = (Integer) ar.get('mo');
                    Integer cnt = (Integer) ar.get('cnt');
                    if (mo != null) monthMap.put(mo, monthMap.get(mo) + cnt);
                }
            }

            final List<String> MONTH_LABELS = new List<String>{
                'Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'
            };
            List<ChartPoint> result = new List<ChartPoint>();
            for (Integer m = 1; m <= 12; m++)
                result.add(new ChartPoint(MONTH_LABELS[m - 1], monthMap.get(m)));
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Top Questionnaires ───────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ChartPoint> getTopQuestionnaires(String approvalStatus, String isActive, String year) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(approvalStatus, isActive, year, binds);
            conds.add('Assessment_Question_Set__c != null');
            // AutoNumber Name cannot be grouped; group by ID instead, then look up names
            Map<Id, Integer> countMap = new Map<Id, Integer>();
            for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Assessment_Question_Set__c qid, COUNT(Id) cnt FROM Ken_Survey__c'
                + toWhere(conds)
                + ' GROUP BY Assessment_Question_Set__c ORDER BY COUNT(Id) DESC LIMIT 10',
                binds, AccessLevel.SYSTEM_MODE
            )) {
                countMap.put((Id) ar.get('qid'), (Integer) ar.get('cnt'));
            }

            if (countMap.isEmpty()) return new List<ChartPoint>();
            Map<Id, String> nameMap = new Map<Id, String>();
            for (AssessmentQuestionSet qs : [
                SELECT Id, Name FROM AssessmentQuestionSet WHERE Id IN :countMap.keySet()
            WITH USER_MODE
            ]) {
                nameMap.put(qs.Id, qs.Name);
            }
            List<ChartPoint> result = new List<ChartPoint>();
            for (Id qId : countMap.keySet()) {
                String lbl = nameMap.containsKey(qId) ? nameMap.get(qId) : 'Unknown';
                result.add(new ChartPoint(lbl, countMap.get(qId)));
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Filter Options ───────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getFilterOptions() {
        try {
            Map<String, List<Map<String, String>>> opts = new Map<String, List<Map<String, String>>>();

            // Approval Statuses
            List<Map<String, String>> approvalStatuses = new List<Map<String, String>>();
            for (AggregateResult ar : [
                SELECT Approval_Status__c st FROM Ken_Survey__c
                WHERE Approval_Status__c != null
                WITH USER_MODE
                GROUP BY Approval_Status__c
                ORDER BY Approval_Status__c
            ]) {
                String st = (String) ar.get('st');
                Map<String, String> opt = new Map<String, String>{ 'label' => st, 'value' => st };
                approvalStatuses.add(opt);
            }
            opts.put('approvalStatuses', approvalStatuses);

            // Years
            List<Map<String, String>> years = new List<Map<String, String>>();
            Set<String> yearSet = new Set<String>();
            for (AggregateResult ar : [
                SELECT CALENDAR_YEAR(CreatedDate) yr FROM Ken_Survey__c
                WHERE CreatedDate != null
                WITH USER_MODE
                GROUP BY CALENDAR_YEAR(CreatedDate)
                ORDER BY CALENDAR_YEAR(CreatedDate) DESC
            ]) {
                Object yObj = ar.get('yr');
                if (yObj != null) yearSet.add(String.valueOf(yObj));
            }
            List<String> sortedYears = new List<String>(yearSet);
            sortedYears.sort();
            for (Integer i = sortedYears.size() - 1; i >= 0; i--) {
                String yr = sortedYears[i];
                years.add(new Map<String, String>{ 'label' => yr, 'value' => yr });
            }
            opts.put('years', years);

            return opts;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Survey List (drill-down) ─────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<SurveyListRecord> getSurveyList(
        String dimension, String dimensionValue,
        String approvalStatus, String isActive, String year
    ) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> conds = buildConds(approvalStatus, isActive, year, binds);

            // Apply dimension filter
            if (!String.isBlank(dimension) && !String.isBlank(dimensionValue)
                    && !dimensionValue.equalsIgnoreCase('All')) {
                binds.put('bDim', dimensionValue);
                if (dimension == 'approval') {
                    conds.add('Approval_Status__c = :bDim');
                } else if (dimension == 'active') {
                    if (dimensionValue.equalsIgnoreCase('Active'))
                        conds.add('Is_Active__c = true');
                    else
                        conds.add('Is_Active__c = false');
                } else if (dimension == 'questionnaire') {
                    conds.add('Assessment_Question_Set__r.Name = :bDim');
                }
            }

            String whereClause = toWhere(conds);
            String q = 'SELECT Id, Name, Approval_Status__c,'
                     + ' Is_Active__c, Target_Audience__c, Start_Date__c, End_Date__c,'
                     + ' Assessment_Question_Set__c, Assessment_Question_Set__r.Name'
                     + ' FROM Ken_Survey__c'
                     + whereClause
                     + ' ORDER BY CreatedDate DESC LIMIT 500';
            List<Ken_Survey__c> surveys = (List<Ken_Survey__c>) Database.queryWithBinds(q, binds, AccessLevel.SYSTEM_MODE);

            Set<Id> asmtSurveyIds = new Set<Id>();
            for (Ken_Survey__c s : surveys) {
                if (s.Assessment_Question_Set__c != null) asmtSurveyIds.add(s.Id);
            }
            Map<Id, Integer> respCountMap = new Map<Id, Integer>();
            if (!asmtSurveyIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Assessment.Ken_Survey__c sid, COUNT(Id) cnt
                    FROM AssessmentQuestionResponse
                    WHERE Assessment.Ken_Survey__c IN :asmtSurveyIds
                      AND Response_Category__c = 'Survey'
                    WITH USER_MODE
                    GROUP BY Assessment.Ken_Survey__c
                ]) {
                    respCountMap.put((Id) ar.get('sid'), (Integer) ar.get('cnt'));
                }
            }

            List<SurveyListRecord> result = new List<SurveyListRecord>();
            for (Ken_Survey__c s : surveys) {
                SurveyListRecord rec     = new SurveyListRecord();
                rec.id                   = s.Id;
                rec.name                 = s.Name;
                rec.questionnaire        = s.Assessment_Question_Set__r != null
                    ? s.Assessment_Question_Set__r.Name : null;
                rec.approvalStatus       = s.Approval_Status__c;
                rec.isActive             = s.Is_Active__c;
                rec.targetAudience       = s.Target_Audience__c;
                rec.startDate            = s.Start_Date__c != null
                    ? String.valueOf(s.Start_Date__c.date()) : null;
                rec.endDate              = s.End_Date__c != null
                    ? String.valueOf(s.End_Date__c.date()) : null;
                rec.responseCount        = respCountMap.containsKey(s.Id) ? respCountMap.get(s.Id) : 0;
                result.add(rec);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Response List (drill-down) ───────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ResponseListRecord> getResponseList(
        String surveyName,
        String approvalStatus, String isActive, String year
    ) {
        try {
            Map<String, Object> binds = new Map<String, Object>();
            List<String> sConds = buildConds(approvalStatus, isActive, year, binds);
            if (!String.isBlank(surveyName)) {
                binds.put('bSurveyName', surveyName);
                sConds.add('Name = :bSurveyName');
            }
            Map<Id, String> asmtSurveys = assessmentSurveyNames(sConds, binds);
            List<ResponseListRecord> result = new List<ResponseListRecord>();
            if (asmtSurveys.isEmpty()) return result;

            Set<Id> asmtIds = asmtSurveys.keySet();
            for (AssessmentQuestionResponse r : [
                SELECT Id, Assessment.Ken_Survey__c, Assessment.Respondent__r.Name,
                       Question_Label__c, ResponseText, CreatedDate
                FROM AssessmentQuestionResponse
                WHERE Response_Category__c = 'Survey'
                  AND Assessment.Ken_Survey__c IN :asmtIds
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 500
            ]) {
                ResponseListRecord rec = new ResponseListRecord();
                rec.id             = r.Id;
                rec.respondentName = (r.Assessment.Respondent__r != null) ? r.Assessment.Respondent__r.Name : null;
                rec.surveyName     = asmtSurveys.get(r.Assessment.Ken_Survey__c);
                rec.questionLabel  = r.Question_Label__c;
                rec.response       = r.ResponseText;
                rec.createdDate    = r.CreatedDate != null ? String.valueOf(r.CreatedDate.date()) : null;
                result.add(rec);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}