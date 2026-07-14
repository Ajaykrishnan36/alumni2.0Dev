@isTest
private class KenModuleFeedbackControllerTest {

    @testSetup
    static void setup() {
        Ken_Questionnaire__c qnr = new Ken_Questionnaire__c(
            Section_Name__c = 'Mentorship Feedback',
            Descripation__c = 'How was the call',
            Target_Audience__c = 'Alumni'
        );
        insert qnr;

        insert new List<Ken_Questionnaire_Parameter__c>{
            new Ken_Questionnaire_Parameter__c(
                Questionnaire__c = qnr.Id, Question_Label__c = 'How was the call?',
                Question_Type__c = 'Linear Scale', Is_Required__c = true,
                Min_Grade__c = 1, Max_Grade__c = 5, Order__c = 1, Section_Name__c = 'Mentorship Feedback'
            ),
            new Ken_Questionnaire_Parameter__c(
                Questionnaire__c = qnr.Id, Question_Label__c = 'Any comments?',
                Question_Type__c = 'Short Answer', Is_Required__c = false,
                Order__c = 2, Section_Name__c = 'Mentorship Feedback'
            )
        };

        Id tplRt = Schema.SObjectType.Ken_Survey__c
            .getRecordTypeInfosByDeveloperName().get('Default_Feedback_Template').getRecordTypeId();
        insert new Ken_Survey__c(
            Name = 'Mentorship Call Feedback',
            RecordTypeId = tplRt,
            Category__c = 'Mentorship',
            Section_Name__c = 'Mentorship Feedback',
            Is_Active__c = true,
            Ken_Questionnaire__c = qnr.Id
        );
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

        Ken_Survey__c inst = [
            SELECT Parent_Template__c, Ken_Questionnaire__c FROM Ken_Survey__c WHERE Id = :instId
        ];
        System.assertEquals(tplId, inst.Parent_Template__c, 'Instance points back to template');
        System.assertNotEquals(null, inst.Ken_Questionnaire__c, 'Instance reuses the questionnaire');

        // Template lookup must still return the TEMPLATE, never the instance.
        System.assertEquals(tplId, KenModuleFeedbackController.getDefaultTemplateId('Mentorship'),
            'Instance must not be mistaken for a template');
    }

    @isTest
    static void testFormSubmitAndRead() {
        Id instId = KenModuleFeedbackController.createInstanceForCategory('Mentorship');
        Id callRt = Schema.SObjectType.Ken_Mentorship__c
            .getRecordTypeInfosByDeveloperName().get('Call_Request').getRecordTypeId();
        Ken_Mentorship__c call = new Ken_Mentorship__c(
            RecordTypeId = callRt,
            Call_Request_Status__c = 'Requested',
            Survey__c = instId
        );
        insert call;

        Test.startTest();
        KenModuleFeedbackController.SurveyFormData form =
            KenModuleFeedbackController.getModuleFeedbackForm(call.Id);
        System.assertEquals(2, form.questions.size(), 'Form exposes both questions');
        System.assertEquals(instId, form.surveyId, 'Form resolves the per-call instance');

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

        Id instQ = [SELECT Ken_Questionnaire__c FROM Ken_Survey__c WHERE Id = :instId LIMIT 1].Ken_Questionnaire__c;
        Integer cnt = [
            SELECT COUNT() FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__r.Questionnaire__c = :instQ
        ];
        System.assertEquals(2, cnt, 'Responses scoped to the per-call instance');
    }

    @isTest
    static void testBulkAndEmpty() {
        Id tplId = KenModuleFeedbackController.getDefaultTemplateId('Mentorship');
        Id instId = KenModuleFeedbackController.createInstanceForCategory('Mentorship');
        Id callRt = Schema.SObjectType.Ken_Mentorship__c
            .getRecordTypeInfosByDeveloperName().get('Call_Request').getRecordTypeId();
        Ken_Mentorship__c call = new Ken_Mentorship__c(
            RecordTypeId = callRt, Call_Request_Status__c = 'Requested', Survey__c = instId
        );
        insert call;
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
        Id callRt = Schema.SObjectType.Ken_Mentorship__c
            .getRecordTypeInfosByDeveloperName().get('Call_Request').getRecordTypeId();
        Ken_Mentorship__c call = new Ken_Mentorship__c(
            RecordTypeId = callRt, Call_Request_Status__c = 'Requested'
        );
        insert call;

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
    }
}