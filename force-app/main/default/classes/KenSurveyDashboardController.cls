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

    private static List<String> buildConds(String approvalStatus, String isActive, String year) {
        List<String> conds = new List<String>();
        if (!isBlankOrAll(approvalStatus))
            conds.add('Approval_Status__c = \'' + String.escapeSingleQuotes(approvalStatus) + '\'');
        if (!isBlankOrAll(isActive)) {
            if (isActive.equalsIgnoreCase('true'))
                conds.add('Is_Active__c = true');
            else if (isActive.equalsIgnoreCase('false'))
                conds.add('Is_Active__c = false');
        }
        if (!isBlankOrAll(year)) {
            try {
                Integer y = Integer.valueOf(year);
                conds.add('CALENDAR_YEAR(CreatedDate) = ' + y);
            } catch (Exception e) { /* ignore invalid year */ }
        }
        return conds;
    }

    private static String toWhere(List<String> conds) {
        if (conds == null || conds.isEmpty()) return '';
        return ' WHERE ' + String.join(conds, ' AND ');
    }

    // Responses no longer link to a survey directly; they reach it through
    // Questionnaire_Parameter__r.Questionnaire__c, and survey -> Ken_Questionnaire__c
    // is 1:1. Resolve the survey-level filter to its matching questionnaire ids,
    // optionally capturing each questionnaire's survey name for relabelling.
    private static Set<Id> questionnaireIdsForSurveys(List<String> surveyConds, Map<Id, String> nameByQuestionnaireOut) {
        Set<Id> qIds = new Set<Id>();
        for (Ken_Survey__c s : Database.query(
            'SELECT Name, Ken_Questionnaire__c FROM Ken_Survey__c' + toWhere(surveyConds) + ' LIMIT 50000'
        )) {
            if (s.Ken_Questionnaire__c == null) continue;
            qIds.add(s.Ken_Questionnaire__c);
            if (nameByQuestionnaireOut != null) nameByQuestionnaireOut.put(s.Ken_Questionnaire__c, s.Name);
        }
        return qIds;
    }

    // ── Summary Stats ────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static SummaryStats getSummaryStats(String approvalStatus, String isActive, String year) {
        try {
            SummaryStats stats = new SummaryStats();
            List<String> conds = buildConds(approvalStatus, isActive, year);
            String whereClause = toWhere(conds);

            // total, active, pending via aggregation
            String q = 'SELECT Is_Active__c isAct, Approval_Status__c appSt, COUNT(Id) cnt'
                     + ' FROM Ken_Survey__c'
                     + whereClause
                     + ' GROUP BY Is_Active__c, Approval_Status__c';
            for (AggregateResult ar : Database.query(q)) {
                Integer cnt = (Integer) ar.get('cnt');
                stats.total += cnt;
                if (ar.get('isAct') == true) stats.active += cnt;
                String st = (String) ar.get('appSt');
                if ('Pending Approval'.equalsIgnoreCase(st)) stats.pending += cnt;
            }

            // response count — responses reach the survey via the questionnaire link
            Set<Id> qIds = questionnaireIdsForSurveys(buildConds(approvalStatus, isActive, year), null);
            if (!qIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT COUNT(Id) cnt
                    FROM Ken_Questionnaire_Parameter_Response__c
                    WHERE Response_Category__c = 'Survey'
                      AND Questionnaire_Parameter__r.Questionnaire__c IN :qIds
                ]) {
                    stats.responses = (Integer) ar.get('cnt');
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
            List<String> conds = new List<String>();
            if (!isBlankOrAll(isActive)) {
                if (isActive.equalsIgnoreCase('true'))       conds.add('Is_Active__c = true');
                else if (isActive.equalsIgnoreCase('false')) conds.add('Is_Active__c = false');
            }
            if (!isBlankOrAll(year)) {
                try {
                    Integer y = Integer.valueOf(year);
                    conds.add('CALENDAR_YEAR(CreatedDate) = ' + y);
                } catch (Exception e) { /* ignore */ }
            }
            String whereClause = toWhere(conds);
            String q = 'SELECT Approval_Status__c st, COUNT(Id) cnt FROM Ken_Survey__c'
                     + whereClause
                     + ' GROUP BY Approval_Status__c ORDER BY COUNT(Id) DESC';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : Database.query(q)) {
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
            List<String> conds = new List<String>();
            if (!isBlankOrAll(approvalStatus))
                conds.add('Approval_Status__c = \'' + String.escapeSingleQuotes(approvalStatus) + '\'');
            if (!isBlankOrAll(year)) {
                try {
                    Integer y = Integer.valueOf(year);
                    conds.add('CALENDAR_YEAR(CreatedDate) = ' + y);
                } catch (Exception e) { /* ignore */ }
            }
            String whereClause = toWhere(conds);
            String q = 'SELECT Is_Active__c isAct, COUNT(Id) cnt FROM Ken_Survey__c'
                     + whereClause
                     + ' GROUP BY Is_Active__c ORDER BY COUNT(Id) DESC';
            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : Database.query(q)) {
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
            Map<Id, String> nameByQ = new Map<Id, String>();
            Set<Id> qIds = questionnaireIdsForSurveys(buildConds(approvalStatus, isActive, year), nameByQ);
            if (qIds.isEmpty()) return new List<ChartPoint>();

            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : [
                SELECT Questionnaire_Parameter__r.Questionnaire__c qId, COUNT(Id) cnt
                FROM Ken_Questionnaire_Parameter_Response__c
                WHERE Questionnaire_Parameter__r.Questionnaire__c IN :qIds
                  AND Response_Category__c = 'Survey'
                GROUP BY Questionnaire_Parameter__r.Questionnaire__c
                ORDER BY COUNT(Id) DESC
                LIMIT 10
            ]) {
                String lbl = nameByQ.get((Id) ar.get('qId'));
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
            List<String> conds = buildConds(approvalStatus, isActive, year);
            conds.add('Ken_Questionnaire__c != null');
            String whereClause = toWhere(conds);
            String surveyQ = 'SELECT Ken_Questionnaire__c FROM Ken_Survey__c' + whereClause + ' LIMIT 500';
            Set<Id> qIds = new Set<Id>();
            for (SObject so : Database.query(surveyQ)) {
                Id qId = (Id) so.get('Ken_Questionnaire__c');
                if (qId != null) qIds.add(qId);
            }
            if (qIds.isEmpty()) return new List<ChartPoint>();

            List<ChartPoint> result = new List<ChartPoint>();
            for (AggregateResult ar : [
                SELECT Question_Type__c qtype, COUNT(Id) cnt
                FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c IN :qIds
                GROUP BY Question_Type__c
                ORDER BY COUNT(Id) DESC
            ]) {
                String lbl = (String) ar.get('qtype');
                result.add(new ChartPoint(String.isBlank(lbl) ? 'Unknown' : lbl, (Integer) ar.get('cnt')));
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
            Set<Id> qIds = questionnaireIdsForSurveys(buildConds(approvalStatus, isActive, year), null);

            Map<Integer, Integer> monthMap = new Map<Integer, Integer>();
            for (Integer m = 1; m <= 12; m++) monthMap.put(m, 0);

            if (!qIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT CALENDAR_MONTH(CreatedDate) mo, COUNT(Id) cnt
                    FROM Ken_Questionnaire_Parameter_Response__c
                    WHERE Questionnaire_Parameter__r.Questionnaire__c IN :qIds
                      AND Response_Category__c = 'Survey'
                    GROUP BY CALENDAR_MONTH(CreatedDate)
                ]) {
                    Integer mo  = (Integer) ar.get('mo');
                    Integer cnt = (Integer) ar.get('cnt');
                    if (mo != null) monthMap.put(mo, cnt);
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
            List<String> conds = buildConds(approvalStatus, isActive, year);
            conds.add('Ken_Questionnaire__c != null');
            String whereClause = toWhere(conds);
            // AutoNumber Name cannot be grouped; group by ID instead, then look up names
            Map<Id, Integer> countMap = new Map<Id, Integer>();
            for (AggregateResult ar : Database.query(
                'SELECT Ken_Questionnaire__c qid, COUNT(Id) cnt FROM Ken_Survey__c'
                + whereClause
                + ' GROUP BY Ken_Questionnaire__c ORDER BY COUNT(Id) DESC LIMIT 10'
            )) {
                countMap.put((Id) ar.get('qid'), (Integer) ar.get('cnt'));
            }
            if (countMap.isEmpty()) return new List<ChartPoint>();
            Map<Id, String> nameMap = new Map<Id, String>();
            for (Ken_Questionnaire__c q : [SELECT Id, Name FROM Ken_Questionnaire__c WHERE Id IN :countMap.keySet()]) {
                nameMap.put(q.Id, q.Name);
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
            List<String> conds = buildConds(approvalStatus, isActive, year);

            // Apply dimension filter
            if (!String.isBlank(dimension) && !String.isBlank(dimensionValue)
                    && !dimensionValue.equalsIgnoreCase('All')) {
                String dv = String.escapeSingleQuotes(dimensionValue);
                if (dimension == 'approval') {
                    conds.add('Approval_Status__c = \'' + dv + '\'');
                } else if (dimension == 'active') {
                    if (dimensionValue.equalsIgnoreCase('Active'))
                        conds.add('Is_Active__c = true');
                    else
                        conds.add('Is_Active__c = false');
                } else if (dimension == 'questionnaire') {
                    conds.add('Ken_Questionnaire__r.Name = \'' + dv + '\'');
                }
            }

            String whereClause = toWhere(conds);
            String q = 'SELECT Id, Name, Ken_Questionnaire__c, Ken_Questionnaire__r.Name, Approval_Status__c,'
                     + ' Is_Active__c, Target_Audience__c, Start_Date__c, End_Date__c'
                     + ' FROM Ken_Survey__c'
                     + whereClause
                     + ' ORDER BY CreatedDate DESC LIMIT 500';
            List<Ken_Survey__c> surveys = Database.query(q);

            // Build response count map — responses reach the survey via the questionnaire link
            Map<Id, Id> surveyByQ = new Map<Id, Id>();
            for (Ken_Survey__c s : surveys) {
                if (s.Ken_Questionnaire__c != null) surveyByQ.put(s.Ken_Questionnaire__c, s.Id);
            }
            Map<Id, Integer> respCountMap = new Map<Id, Integer>();
            if (!surveyByQ.isEmpty()) {
                Set<Id> qIds = surveyByQ.keySet();
                for (AggregateResult ar : [
                    SELECT Questionnaire_Parameter__r.Questionnaire__c qId, COUNT(Id) cnt
                    FROM Ken_Questionnaire_Parameter_Response__c
                    WHERE Questionnaire_Parameter__r.Questionnaire__c IN :qIds
                      AND Response_Category__c = 'Survey'
                    GROUP BY Questionnaire_Parameter__r.Questionnaire__c
                ]) {
                    Id qId = (Id) ar.get('qId');
                    if (surveyByQ.containsKey(qId)) respCountMap.put(surveyByQ.get(qId), (Integer) ar.get('cnt'));
                }
            }

            List<SurveyListRecord> result = new List<SurveyListRecord>();
            for (Ken_Survey__c s : surveys) {
                SurveyListRecord rec     = new SurveyListRecord();
                rec.id                   = s.Id;
                rec.name                 = s.Name;
                rec.questionnaire        = s.Ken_Questionnaire__r != null ? s.Ken_Questionnaire__r.Name : null;
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
            // Survey-level filter (responses reach the survey via the questionnaire link)
            List<String> sConds = buildConds(approvalStatus, isActive, year);
            if (!String.isBlank(surveyName))
                sConds.add('Name = \'' + String.escapeSingleQuotes(surveyName) + '\'');
            Map<Id, String> nameByQ = new Map<Id, String>();
            Set<Id> qIds = questionnaireIdsForSurveys(sConds, nameByQ);
            if (qIds.isEmpty()) return new List<ResponseListRecord>();

            List<ResponseListRecord> result = new List<ResponseListRecord>();
            for (Ken_Questionnaire_Parameter_Response__c r : [
                SELECT Id, Respondent__r.Name, Questionnaire_Parameter__r.Questionnaire__c,
                       Question_Label__c, Response__c, CreatedDate
                FROM Ken_Questionnaire_Parameter_Response__c
                WHERE Response_Category__c = 'Survey'
                  AND Questionnaire_Parameter__r.Questionnaire__c IN :qIds
                ORDER BY CreatedDate DESC
                LIMIT 500
            ]) {
                ResponseListRecord rec = new ResponseListRecord();
                rec.id            = r.Id;
                rec.respondentName = r.Respondent__r != null ? r.Respondent__r.Name : null;
                rec.surveyName     = (r.Questionnaire_Parameter__r != null)
                    ? nameByQ.get(r.Questionnaire_Parameter__r.Questionnaire__c) : null;
                rec.questionLabel  = r.Question_Label__c;
                rec.response       = r.Response__c;
                rec.createdDate    = r.CreatedDate != null ? String.valueOf(r.CreatedDate.date()) : null;
                result.add(rec);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}