@isTest
private class KenModuleFeedbackControllerTest {

    private static final String RESPONDENT_NAME = 'Module Feedback Respondent';

    @testSetup
    static void setup() {
        insert new Account(Name = RESPONDENT_NAME);

        KenAssessmentSurveyService.QuestionInput scale = new KenAssessmentSurveyService.QuestionInput();
        scale.text = 'How was the call?';
        scale.questionType = 'Linear Scale';
        scale.required = true;
        scale.choices = new List<KenAssessmentSurveyService.ChoiceRow>();
        for (Integer i = 1; i <= 5; i++) {
            KenAssessmentSurveyService.ChoiceRow point = new KenAssessmentSurveyService.ChoiceRow();
            point.value = String.valueOf(i);
            point.label = String.valueOf(i);
            scale.choices.add(point);
        }

        KenAssessmentSurveyService.QuestionInput comments = new KenAssessmentSurveyService.QuestionInput();
        comments.text = 'Any comments?';
        comments.questionType = 'Short Answer';
        comments.required = false;

        Id questionSetId = KenAssessmentSurveyService.saveQuestionSet(null, 'Mentorship Feedback',
            new List<KenAssessmentSurveyService.QuestionInput>{ scale, comments }
        );

        Id tplRt = Schema.SObjectType.Ken_Survey__c
            .getRecordTypeInfosByDeveloperName().get('Default_Feedback_Template').getRecordTypeId();
        insert new Ken_Survey__c(
            Name = 'Mentorship Call Feedback',
            RecordTypeId = tplRt,
            Category__c = 'Mentorship',
            Is_Active__c = true,
            Assessment_Question_Set__c = questionSetId
        );
    }

    private static Id respondentAccountId() {
        return [SELECT Id FROM Account WHERE Name = :RESPONDENT_NAME LIMIT 1].Id;
    }

    private static Ken_Mentorship__c buildCall(Id surveyId) {
        Id callRt = Schema.SObjectType.Ken_Mentorship__c
            .getRecordTypeInfosByDeveloperName().get('Call_Request').getRecordTypeId();
        Ken_Mentorship__c call = new Ken_Mentorship__c(
            RecordTypeId = callRt,
            Call_Request_Status__c = 'Requested',
            Survey__c = surveyId
        );
        insert call;
        return call;
    }

    @isTest
    static void testTemplateAndInstance() {
        Test.startTest();
        Id tplId = KenModuleFeedbackController.getDefaultTemplateId('Mentorship');
        Id instId = KenModuleFeedbackController.createInstanceForCategory('Mentorship');
        Id none = KenModuleFeedbackController.getDefaultTemplateId('Event');
        Test.stopTest();

        System.assertNotEquals(null, tplId, 'Template should resolve');
        System.assertNotEquals(null, instId, 'Instance should be created');
        System.assertNotEquals(tplId, instId, 'Instance is distinct from the template');
        System.assertEquals(null, none, 'No Event template configured');

        Ken_Survey__c tpl = [SELECT Assessment_Question_Set__c FROM Ken_Survey__c WHERE Id = :tplId];
        Ken_Survey__c inst = [
            SELECT Parent_Template__c, Assessment_Question_Set__c, Module__c
            FROM Ken_Survey__c WHERE Id = :instId
        ];
        System.assertEquals(tplId, inst.Parent_Template__c, 'Instance points back to template');
        System.assertEquals(tpl.Assessment_Question_Set__c, inst.Assessment_Question_Set__c,
            'Instance reuses the template question set');
        System.assertEquals('Alumni', inst.Module__c, 'Feedback instances belong to the Alumni module');

        // Template lookup must still return the TEMPLATE, never the instance.
        System.assertEquals(tplId, KenModuleFeedbackController.getDefaultTemplateId('Mentorship'),
            'Instance must not be mistaken for a template');
    }

    @isTest
    static void testFormSubmitAndRead() {
        Id instId = KenModuleFeedbackController.createInstanceForCategory('Mentorship');
        Ken_Mentorship__c call = buildCall(instId);
        KenModuleFeedbackController.testRespondentAccountId = respondentAccountId();

        Test.startTest();
        KenModuleFeedbackController.SurveyFormData form =
            KenModuleFeedbackController.getModuleFeedbackForm(call.Id);
        System.assertEquals(2, form.questions.size(), 'Form exposes both questions');
        System.assertEquals(instId, form.surveyId, 'Form resolves the per-call instance');
        System.assertEquals(5, form.questions[0].choices.size(),
            'Scale points travel to the client as choices');

        KenModuleFeedbackController.ModuleFeedbackRequest req = new KenModuleFeedbackController.ModuleFeedbackRequest();
        req.recordId = call.Id;
        KenModuleFeedbackController.QuestionResponse r1 = new KenModuleFeedbackController.QuestionResponse();
        r1.questionId = form.questions[0].id;
        r1.responseValue = '5';
        KenModuleFeedbackController.QuestionResponse r2 = new KenModuleFeedbackController.QuestionResponse();
        r2.questionId = form.questions[1].id;
        r2.responseValue = 'Great session';
        req.responses = new List<KenModuleFeedbackController.QuestionResponse>{ r1, r2 };
        KenModuleFeedbackController.submitModuleFeedback(req);
        Test.stopTest();

        System.assertEquals(true, KenModuleFeedbackController.hasCurrentUserResponded(call.Id),
            'Current user marked as responded');

        KenModuleFeedbackController.ResponseView view =
            KenModuleFeedbackController.getResponsesForRecord(call.Id);
        System.assertEquals(1, view.total, 'One respondent group');
        System.assertEquals(2, view.respondents[0].answers.size(), 'Two answers stored');

        System.assertEquals(2, [
            SELECT COUNT() FROM AssessmentQuestionResponse WHERE Assessment.Ken_Survey__c = :instId
        ], 'Responses scoped to the per-call instance');
    }

    @isTest
    static void testGetResponsesOnSurveyRecordPage() {
        Id instId = KenModuleFeedbackController.createInstanceForCategory('Mentorship');
        Ken_Mentorship__c call = buildCall(instId);
        KenModuleFeedbackController.testRespondentAccountId = respondentAccountId();

        KenModuleFeedbackController.SurveyFormData form =
            KenModuleFeedbackController.getModuleFeedbackForm(call.Id);
        KenModuleFeedbackController.ModuleFeedbackRequest req = new KenModuleFeedbackController.ModuleFeedbackRequest();
        req.recordId = call.Id;
        KenModuleFeedbackController.QuestionResponse r1 = new KenModuleFeedbackController.QuestionResponse();
        r1.questionId = form.questions[0].id;
        r1.responseValue = '5';
        req.responses = new List<KenModuleFeedbackController.QuestionResponse>{ r1 };
        KenModuleFeedbackController.submitModuleFeedback(req);

        Test.startTest();
        KenModuleFeedbackController.ResponseView view =
            KenModuleFeedbackController.getResponsesForRecord(instId);
        Test.stopTest();

        System.assertEquals(1, view.total,
            'Responses must surface when the viewer sits on the Ken_Survey__c record page (recordId is the survey)');
        System.assertEquals(1, view.respondents[0].answers.size(), 'Answer stored');
    }

    @isTest
    static void testBulkAndEmpty() {
        Id tplId = KenModuleFeedbackController.getDefaultTemplateId('Mentorship');
        Id instId = KenModuleFeedbackController.createInstanceForCategory('Mentorship');
        Ken_Mentorship__c call = buildCall(instId);
        KenModuleFeedbackController.testRespondentAccountId = respondentAccountId();

        KenModuleFeedbackController.SurveyFormData form =
            KenModuleFeedbackController.getModuleFeedbackForm(call.Id);
        KenModuleFeedbackController.ModuleFeedbackRequest req = new KenModuleFeedbackController.ModuleFeedbackRequest();
        req.recordId = call.Id;
        KenModuleFeedbackController.QuestionResponse r1 = new KenModuleFeedbackController.QuestionResponse();
        r1.questionId = form.questions[0].id;
        r1.responseValue = '4';
        req.responses = new List<KenModuleFeedbackController.QuestionResponse>{ r1 };
        KenModuleFeedbackController.submitModuleFeedback(req);

        Test.startTest();
        KenModuleFeedbackController.ResponseView bulkView =
            KenModuleFeedbackController.getResponsesForTemplate(tplId);
        KenModuleFeedbackController.ResponseView blankView =
            KenModuleFeedbackController.getResponsesForRecord(null);
        Test.stopTest();

        System.assertEquals(1, bulkView.total, 'Bulk view aggregates across instances of the template');
        System.assertEquals(0, blankView.total, 'Blank record id yields empty view');
    }

    @isTest
    static void testNoFormConfigured() {
        Ken_Mentorship__c call = buildCall(null);

        Test.startTest();
        Boolean threw = false;
        try {
            KenModuleFeedbackController.getModuleFeedbackForm(call.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        KenModuleFeedbackController.ResponseView v =
            KenModuleFeedbackController.getResponsesForRecord(call.Id);
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected exception when no form configured');
        System.assertEquals(0, v.total, 'No instance -> empty view');
        System.assertEquals(false, KenModuleFeedbackController.hasCurrentUserResponded(call.Id),
            'A record with no survey can never read as responded');
    }
}