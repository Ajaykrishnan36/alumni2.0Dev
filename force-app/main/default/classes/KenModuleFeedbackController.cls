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
            WITH USER_MODE
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
        // On the Ken_Survey__c record page the recordId IS the survey instance; there is
        // no Survey__c lookup to follow, so use it directly.
        if (recordId.getSObjectType() == Ken_Survey__c.SObjectType) {
            return recordId;
        }
        Schema.DescribeSObjectResult dsr = recordId.getSObjectType().getDescribe();
        if (!dsr.fields.getMap().containsKey(KenNamespaceUtil.qualifyCustom('Survey__c'))) {
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

    /**
     * @description Builds the form a respondent fills in.
     *
     *              Reads in system context: a community respondent (e.g. an event
     *              registrant) typically has no sharing access to the host's
     *              Ken_Survey__c, which would otherwise make the form load empty.
     * @param surveyId Survey instance to render.
     * @param recordId Host record the form was opened from.
     * @return Form definition for the client.
     */
    private static SurveyFormData buildFormFromSurvey(Id surveyId, Id recordId) {
        List<Ken_Survey__c> surveys = new Wos().surveyById(surveyId);
        if (surveys.isEmpty() || surveys[0].Assessment_Question_Set__c == null) {
            throw new AuraHandledException('Feedback form is missing its questionnaire.');
        }

        SurveyFormData data = new SurveyFormData();
        data.surveyId = surveyId;
        data.recordId = recordId;
        data.name = surveys[0].Name;
        data.questions = new List<QuestionData>();
        for (KenAssessmentSurveyService.QuestionRow row
                : KenAssessmentSurveyService.questionsForSet(surveys[0].Assessment_Question_Set__c)) {
            QuestionData q = new QuestionData();
            q.id = row.id;
            q.label = row.questionLabel;
            q.type = row.questionType;
            q.choices = row.choices;
            q.required = row.required == true;
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
        Id recId = (Id) request.recordId;
        Id surveyId = String.isNotBlank(request.surveyId) ? (Id) request.surveyId : resolveSurveyId(recId);
        if (surveyId == null) {
            throw new AuraHandledException('No feedback form is configured for this record.');
        }

        Id respondentAccountId = fetchCurrentAccountId();

        List<KenAssessmentSurveyService.AnswerInput> answers = new List<KenAssessmentSurveyService.AnswerInput>();
        if (request.responses != null) {
            for (QuestionResponse qr : request.responses) {
                if (qr == null || String.isBlank(qr.questionId) || String.isBlank(qr.responseValue)) {
                    continue;
                }
                KenAssessmentSurveyService.AnswerInput answer = new KenAssessmentSurveyService.AnswerInput();
                answer.questionId = (Id) qr.questionId;
                answer.value = qr.responseValue;
                answers.add(answer);
            }
        }
        if (answers.isEmpty()) {
            throw new AuraHandledException('Please answer at least one question.');
        }
        KenAssessmentSurveyService.submitResponses(
            surveyId, respondentAccountId, RESPONSE_CATEGORY, answers
        );
    }

    // System-context reads so community respondents (no sharing on the host's survey)
    // can still load a module feedback/survey form.
    private without sharing class Wos {
        Id surveyIdForRecord(String objApi, Id recordId) {
            List<SObject> recs = Database.query(
                'SELECT Survey__c FROM ' + String.escapeSingleQuotes(objApi) + ' WHERE Id = :recordId LIMIT 1'
            );
            return recs.isEmpty() ? null : (Id) recs[0].get(KenNamespaceUtil.qualifyCustom('Survey__c'));
        }
        List<Ken_Survey__c> surveyById(Id surveyId) {
            return [
                SELECT Id, Name, Assessment_Question_Set__c
                FROM Ken_Survey__c WHERE Id = :surveyId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }
        Id createInstance(String category, String templateRecordType) {
            List<Ken_Survey__c> templates = [
                SELECT Id, Name, Assessment_Question_Set__c, Category__c
                FROM Ken_Survey__c
                WHERE RecordType.DeveloperName = :templateRecordType
                  AND Category__c = :category
                  AND Parent_Template__c = null
                  AND Is_Active__c = true
                WITH SECURITY_ENFORCED
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (templates.isEmpty() || templates[0].Assessment_Question_Set__c == null) {
                return null;
            }
            Ken_Survey__c tpl = templates[0];
            Ken_Survey__c instance = new Ken_Survey__c(
                Name = String.isNotBlank(tpl.Name) ? tpl.Name : category + ' Feedback',
                Category__c = category,
                Parent_Template__c = tpl.Id,
                Assessment_Question_Set__c = tpl.Assessment_Question_Set__c,
                Module__c = 'Alumni',
                Is_Active__c = true
            );
            if (!Schema.sObjectType.Ken_Survey__c.isCreateable()) {
                throw new KenCrudException('Ken_Survey__c is not createable by the current user.');
            }
            insert instance;
            return instance.Id;
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
        List<Ken_Survey__c> svy = new Wos().surveyById(surveyId);
        if (svy.isEmpty() || svy[0].Assessment_Question_Set__c == null) {
            return false;
        }
        return !KenAssessmentSurveyService.surveysAnsweredBy(new Set<Id>{ surveyId }, acc).isEmpty();
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
        WITH USER_MODE
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
        Map<Id, RespondentResponses> byRespondent = new Map<Id, RespondentResponses>();
        for (AssessmentQuestionResponse answer : KenAssessmentSurveyService.answersForSurveys(surveyIds)) {
            Id key = answer.Assessment.Respondent__c;
            RespondentResponses rr = byRespondent.get(key);
            if (rr == null) {
                rr = new RespondentResponses();
                rr.respondentId = key;
                rr.respondentName = (answer.Assessment.Respondent__r != null && answer.Assessment.Respondent__r.Name != null)
                    ? answer.Assessment.Respondent__r.Name : 'Anonymous';
                rr.submittedDate = answer.Assessment.Submitted_Date__c != null
                    ? answer.Assessment.Submitted_Date__c : answer.CreatedDate;
                rr.answers = new List<AnswerData>();
                byRespondent.put(key, rr);
                view.respondents.add(rr);
            }
            AnswerData a = new AnswerData();
            a.question = answer.Question_Label__c;
            a.answer = answer.ResponseText;
            rr.answers.add(a);
        }
        view.total = view.respondents.size();
        return view;
    }

    @TestVisible private static Id testRespondentAccountId;

    private static Id fetchCurrentAccountId() {
        if (Test.isRunningTest() && testRespondentAccountId != null) {
            return testRespondentAccountId;
        }
        List<User> us = [
            SELECT AccountId, Contact.AccountId
            FROM User WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
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
        @AuraEnabled public List<QuestionData> questions;
    }
    public class QuestionData {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public List<KenAssessmentSurveyService.ChoiceRow> choices;
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