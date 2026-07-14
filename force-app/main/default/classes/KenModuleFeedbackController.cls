public with sharing class KenModuleFeedbackController {

    private static final String TEMPLATE_RECORD_TYPE = 'Default_Feedback_Template';
    private static final String RESPONSE_CATEGORY = 'Feedback';

    public static final String CATEGORY_MENTORSHIP = 'Mentorship';

    public static Id getDefaultTemplateId(String category) {
        if (String.isBlank(category)) {
            return null;
        }
        List<Ken_Survey__c> templates = [
            SELECT Id
            FROM Ken_Survey__c
            WHERE RecordType.DeveloperName = :TEMPLATE_RECORD_TYPE
              AND Category__c = :category
              AND Parent_Template__c = null
              AND Is_Active__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    public static Id createInstanceForCategory(String category) {
        if (String.isBlank(category)) {
            return null;
        }
        return new Wos().createInstance(category, TEMPLATE_RECORD_TYPE);
    }

    private static Id resolveSurveyId(Id recordId) {
        if (recordId == null) {
            return null;
        }
        Schema.DescribeSObjectResult dsr = recordId.getSObjectType().getDescribe();
        if (!dsr.fields.getMap().containsKey('Survey__c')) {
            return null;
        }
        // Read in system context: a community respondent (e.g. an event registrant)
        // typically has no sharing access to the module record, so a with-sharing
        // query returns 0 rows and the form looks "not configured".
        return new Wos().surveyIdForRecord(dsr.getName(), recordId);
    }

    @AuraEnabled(cacheable=true)
    public static SurveyFormData getModuleFeedbackForm(String recordId) {
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Record id is required.');
        }
        Id recId = (Id) recordId;
        Id surveyId = resolveSurveyId(recId);
        if (surveyId == null) {
            throw new AuraHandledException('No feedback form is configured for this record.');
        }
        return buildFormFromSurvey(surveyId, recId);
    }

    private static SurveyFormData buildFormFromSurvey(Id surveyId, Id recordId) {
        // Read in system context: a community respondent (e.g. an event registrant)
        // typically has no sharing access to the host's Ken_Survey__c, which would
        // otherwise make the form load empty.
        Wos wos = new Wos();
        List<Ken_Survey__c> surveys = wos.surveyById(surveyId);
        if (surveys.isEmpty() || surveys[0].Ken_Questionnaire__c == null) {
            throw new AuraHandledException('Feedback form is missing its questionnaire.');
        }
        Id questionnaireId = surveys[0].Ken_Questionnaire__c;
        List<Ken_Questionnaire_Parameter__c> params = wos.paramsByQuestionnaire(questionnaireId);

        SurveyFormData data = new SurveyFormData();
        data.surveyId = surveyId;
        data.recordId = recordId;
        data.name = surveys[0].Name;
        data.sectionName = surveys[0].Section_Name__c;
        data.questions = new List<QuestionData>();
        for (Ken_Questionnaire_Parameter__c p : params) {
            QuestionData q = new QuestionData();
            q.id = p.Id;
            q.label = p.Question_Label__c;
            q.type = p.Question_Type__c;
            q.options = p.MCQ_Options__c;
            q.minGrade = p.Min_Grade__c;
            q.maxGrade = p.Max_Grade__c;
            q.minGradeLabel = p.Min_Grade_Label__c;
            q.maxGradeLabel = p.Max_Grade_Label__c;
            q.required = p.Is_Required__c == true;
            data.questions.add(q);
        }
        return data;
    }

    /**
     * Saves a respondent's answers against the record's per-record instance.
     * Responses link to the instance via Ken_Survey__c only — no record id, no
     * module lookup — keeping the survey layer standalone.
     */
    @AuraEnabled
    public static void submitModuleFeedback(ModuleFeedbackRequest request) {
        if (request == null || String.isBlank(request.recordId)) {
            throw new AuraHandledException('Record id is required.');
        }
        if (!Schema.sObjectType.Ken_Questionnaire_Parameter_Response__c.isCreateable()) {
            throw new AuraHandledException('Insufficient access to save feedback.');
        }
        Id recId = (Id) request.recordId;
        Id surveyId = String.isNotBlank(request.surveyId) ? (Id) request.surveyId : resolveSurveyId(recId);
        if (surveyId == null) {
            throw new AuraHandledException('No feedback form is configured for this record.');
        }

        Id respondentAccountId = fetchCurrentAccountId();
        List<Ken_Questionnaire_Parameter_Response__c> inserts = new List<Ken_Questionnaire_Parameter_Response__c>();
        if (request.responses != null) {
            for (QuestionResponse qr : request.responses) {
                if (qr == null || String.isBlank(qr.questionId) || String.isBlank(qr.responseValue)) {
                    continue;
                }
                // The question links to the instance's own questionnaire, which is how the
                // response reaches the survey instance (no direct survey lookup on the response).
                inserts.add(new Ken_Questionnaire_Parameter_Response__c(
                    Questionnaire_Parameter__c = (Id) qr.questionId,
                    Respondent__c = respondentAccountId,
                    Response__c = qr.responseValue,
                    Response_Category__c = RESPONSE_CATEGORY
                ));
            }
        }
        if (inserts.isEmpty()) {
            throw new AuraHandledException('Please answer at least one question.');
        }
        // Insert in system context: the response references the survey/question, which
        // a community respondent may not have sharing access to.
        new Wos().insertResponses(inserts);
    }

    // System-context reads/writes so community respondents (no sharing on the host's
    // survey) can still load and submit a module feedback/survey form.
    private without sharing class Wos {
        Id surveyIdForRecord(String objApi, Id recordId) {
            List<SObject> recs = Database.query(
                'SELECT Survey__c FROM ' + String.escapeSingleQuotes(objApi) + ' WHERE Id = :recordId LIMIT 1'
            );
            return recs.isEmpty() ? null : (Id) recs[0].get('Survey__c');
        }
        List<Ken_Survey__c> surveyById(Id surveyId) {
            return [
                SELECT Id, Name, Section_Name__c, Ken_Questionnaire__c
                FROM Ken_Survey__c WHERE Id = :surveyId LIMIT 1
            ];
        }
        List<Ken_Questionnaire_Parameter__c> paramsByQuestionnaire(Id questionnaireId) {
            return [
                SELECT Id, Question_Label__c, Question_Type__c, MCQ_Options__c,
                       Min_Grade__c, Max_Grade__c, Min_Grade_Label__c, Max_Grade_Label__c,
                       Order__c, Is_Required__c
                FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c = :questionnaireId
                ORDER BY Order__c ASC NULLS LAST
            ];
        }
        void insertResponses(List<Ken_Questionnaire_Parameter_Response__c> recs) {
            insert recs;
        }
        Id createInstance(String category, String templateRecordType) {
            List<Ken_Survey__c> templates = [
                SELECT Id, Name, Section_Name__c, Ken_Questionnaire__c, Category__c
                FROM Ken_Survey__c
                WHERE RecordType.DeveloperName = :templateRecordType
                  AND Category__c = :category
                  AND Parent_Template__c = null
                  AND Is_Active__c = true
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (templates.isEmpty() || templates[0].Ken_Questionnaire__c == null) {
                return null;
            }
            Ken_Survey__c tpl = templates[0];
            // Each instance gets its OWN cloned questionnaire. Responses link to a survey
            // only through the questionnaire, so sharing the template's questionnaire would
            // make every instance's responses indistinguishable from its siblings'.
            Id instanceQuestionnaireId = cloneQuestionnaire(tpl.Ken_Questionnaire__c);
            Ken_Survey__c instance = new Ken_Survey__c(
                Name = String.isNotBlank(tpl.Name) ? tpl.Name : category + ' Feedback',
                Category__c = category,
                Parent_Template__c = tpl.Id,
                Ken_Questionnaire__c = instanceQuestionnaireId,
                Section_Name__c = tpl.Section_Name__c,
                Is_Active__c = true
            );
            insert instance;
            return instance.Id;
        }

        // Deep-clones a questionnaire and its parameters; returns the new questionnaire id.
        Id cloneQuestionnaire(Id sourceQuestionnaireId) {
            if (sourceQuestionnaireId == null) {
                return null;
            }
            List<Ken_Questionnaire__c> sources = [
                SELECT Id, Section_Name__c, Descripation__c, Target_Audience__c, Questions_JSON__c
                FROM Ken_Questionnaire__c WHERE Id = :sourceQuestionnaireId LIMIT 1
            ];
            if (sources.isEmpty()) {
                return null;
            }
            Ken_Questionnaire__c src = sources[0];
            Ken_Questionnaire__c clone = new Ken_Questionnaire__c(
                Section_Name__c = src.Section_Name__c,
                Descripation__c = src.Descripation__c,
                Target_Audience__c = src.Target_Audience__c,
                Questions_JSON__c = src.Questions_JSON__c
            );
            insert clone;

            List<Ken_Questionnaire_Parameter__c> newParams = new List<Ken_Questionnaire_Parameter__c>();
            for (Ken_Questionnaire_Parameter__c p : [
                SELECT Question_Label__c, Question_Type__c, MCQ_Options__c,
                       Min_Grade__c, Max_Grade__c, Min_Grade_Label__c, Max_Grade_Label__c,
                       Order__c, Is_Required__c, Section_Name__c
                FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c = :sourceQuestionnaireId
                ORDER BY Order__c ASC NULLS LAST
            ]) {
                newParams.add(new Ken_Questionnaire_Parameter__c(
                    Questionnaire__c = clone.Id,
                    Question_Label__c = p.Question_Label__c,
                    Question_Type__c = p.Question_Type__c,
                    MCQ_Options__c = p.MCQ_Options__c,
                    Min_Grade__c = p.Min_Grade__c,
                    Max_Grade__c = p.Max_Grade__c,
                    Min_Grade_Label__c = p.Min_Grade_Label__c,
                    Max_Grade_Label__c = p.Max_Grade_Label__c,
                    Order__c = p.Order__c,
                    Is_Required__c = p.Is_Required__c,
                    Section_Name__c = p.Section_Name__c
                ));
            }
            if (!newParams.isEmpty()) {
                insert newParams;
            }
            return clone.Id;
        }
    }

    /**
     * Has the current user already submitted feedback for this record's
     * instance? Used to hide the prompt after responding.
     */
    @AuraEnabled
    public static Boolean hasCurrentUserResponded(String recordId) {
        if (String.isBlank(recordId)) {
            return false;
        }
        Id surveyId = resolveSurveyId((Id) recordId);
        if (surveyId == null) {
            return false;
        }
        Id acc = fetchCurrentAccountId();
        // Read the questionnaire in system context — a community respondent may have no
        // sharing on the host's survey, which would otherwise hide their own response.
        List<Ken_Survey__c> svy = new Wos().surveyById(surveyId);
        Id questionnaireId = svy.isEmpty() ? null : svy[0].Ken_Questionnaire__c;
        if (questionnaireId == null) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__r.Questionnaire__c = :questionnaireId AND Respondent__c = :acc
        ] > 0;
    }

    // ============================================================
    // The single VIEW-ONLY read API (powers c/kenFeedbackResponses)
    // ============================================================

    /** Responses for ONE record (individual view) — scoped by its instance. */
    @AuraEnabled(cacheable=true)
    public static ResponseView getResponsesForRecord(String recordId) {
        if (String.isBlank(recordId)) {
            return emptyView();
        }
        Id surveyId = resolveSurveyId((Id) recordId);
        if (surveyId == null) {
            return emptyView();
        }
        return buildResponseView(new Set<Id>{ surveyId });
    }

    /** Responses across every instance of a template (bulk view). */
    @AuraEnabled(cacheable=true)
    public static ResponseView getResponsesForTemplate(String templateId) {
        if (String.isBlank(templateId)) {
            return emptyView();
        }
        Set<Id> surveyIds = new Set<Id>();
        for (Ken_Survey__c s : [
            SELECT Id FROM Ken_Survey__c WHERE Parent_Template__c = :templateId
        ]) {
            surveyIds.add(s.Id);
        }
        if (surveyIds.isEmpty()) {
            return emptyView();
        }
        return buildResponseView(surveyIds);
    }

    private static ResponseView emptyView() {
        ResponseView view = new ResponseView();
        view.respondents = new List<RespondentResponses>();
        view.total = 0;
        return view;
    }

    private static ResponseView buildResponseView(Set<Id> surveyIds) {
        ResponseView view = emptyView();
        if (surveyIds == null || surveyIds.isEmpty()) {
            return view;
        }
        if (!Schema.sObjectType.Ken_Questionnaire_Parameter_Response__c.isAccessible()) {
            return view;
        }
        // Responses reach a survey only via the questionnaire link; resolve the surveys'
        // questionnaires (1:1 per instance) and scope the responses through them.
        Set<Id> qIds = new Set<Id>();
        for (Ken_Survey__c s : [
            SELECT Ken_Questionnaire__c FROM Ken_Survey__c
            WHERE Id IN :surveyIds AND Ken_Questionnaire__c != null
        ]) {
            qIds.add(s.Ken_Questionnaire__c);
        }
        if (qIds.isEmpty()) {
            return view;
        }
        List<Ken_Questionnaire_Parameter_Response__c> rows = [
            SELECT Id, Question_Label__c, Response__c, Respondent__c, Respondent__r.Name, CreatedDate,
                   Questionnaire_Parameter__r.Order__c, Questionnaire_Parameter__r.Question_Label__c
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__r.Questionnaire__c IN :qIds
            ORDER BY Respondent__c NULLS LAST, CreatedDate ASC, Questionnaire_Parameter__r.Order__c ASC NULLS LAST
        ];
        Map<Id, RespondentResponses> byRespondent = new Map<Id, RespondentResponses>();
        for (Ken_Questionnaire_Parameter_Response__c r : rows) {
            Id key = r.Respondent__c;
            RespondentResponses rr = byRespondent.get(key);
            if (rr == null) {
                rr = new RespondentResponses();
                rr.respondentId = key;
                rr.respondentName = (r.Respondent__r != null && r.Respondent__r.Name != null)
                    ? r.Respondent__r.Name : 'Anonymous';
                rr.submittedDate = r.CreatedDate;
                rr.answers = new List<AnswerData>();
                byRespondent.put(key, rr);
                view.respondents.add(rr);
            }
            AnswerData a = new AnswerData();
            a.question = String.isNotBlank(r.Question_Label__c)
                ? r.Question_Label__c
                : (r.Questionnaire_Parameter__r != null ? r.Questionnaire_Parameter__r.Question_Label__c : null);
            a.answer = r.Response__c;
            rr.answers.add(a);
        }
        view.total = view.respondents.size();
        return view;
    }

    private static Id fetchCurrentAccountId() {
        List<User> us = [
            SELECT AccountId, Contact.AccountId
            FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        if (us.isEmpty()) {
            return null;
        }
        if (us[0].AccountId != null) {
            return us[0].AccountId;
        }
        return (us[0].Contact != null) ? us[0].Contact.AccountId : null;
    }

    // ===== Wrappers =====
    public class ModuleFeedbackRequest {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String surveyId { get; set; }
        @AuraEnabled public List<QuestionResponse> responses { get; set; }
    }
    public class QuestionResponse {
        @AuraEnabled public String questionId { get; set; }
        @AuraEnabled public String questionLabel { get; set; }
        @AuraEnabled public String responseValue { get; set; }
    }

    public class SurveyFormData {
        @AuraEnabled public Id surveyId;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String sectionName;
        @AuraEnabled public List<QuestionData> questions;
    }
    public class QuestionData {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public String options;
        @AuraEnabled public Decimal minGrade;
        @AuraEnabled public Decimal maxGrade;
        @AuraEnabled public String minGradeLabel;
        @AuraEnabled public String maxGradeLabel;
        @AuraEnabled public Boolean required;
    }
    public class ResponseView {
        @AuraEnabled public Integer total;
        @AuraEnabled public List<RespondentResponses> respondents;
    }
    public class RespondentResponses {
        @AuraEnabled public Id respondentId;
        @AuraEnabled public String respondentName;
        @AuraEnabled public Datetime submittedDate;
        @AuraEnabled public List<AnswerData> answers;
    }
    public class AnswerData {
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
    }
}