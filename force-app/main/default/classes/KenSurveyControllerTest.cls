@IsTest
@SuppressWarnings('PMD.ApexAssertionsShouldIncludeMessage,PMD.MethodNamingConventions,PMD.ApexUnitTestClassShouldHaveRunAs,PMD.AnnotationsNamingConventions,PMD.NcssCount,PMD.NcssMethodCount')
public class KenSurveyControllerTest {

    @TestSetup
    static void setupData() {
        // Accounts used for Constituent_Role__c filtering
        Account currentAcc = new Account(Name = 'Current Account');
        Account otherAcc   = new Account(Name = 'Other Account');
        insert new List<Account>{ currentAcc, otherAcc };
        
        ConstituentRole currentRole = createConstituentRole(currentAcc.Id, 'current@test.com');
        ConstituentRole otherRole = createConstituentRole(otherAcc.Id, 'other@test.com');

        // Seed an approved/active survey for getSurveys() coverage
        Ken_Questionnaire__c qnr = new Ken_Questionnaire__c(
            Section_Name__c = 'Public Survey',
            Descripation__c = 'Public survey description',
            Target_Audience__c = 'Students;Alumni'
        );
        insert qnr;

        Ken_Questionnaire_Parameter__c p1 = new Ken_Questionnaire_Parameter__c(
            Questionnaire__c = qnr.Id,
            Question_Label__c = 'Public Q1',
            Question_Type__c = 'Short Answer',
            Is_Required__c = true,
            Order__c = 1,
            Section_Name__c = 'Public Survey'
        );
        Ken_Questionnaire_Parameter__c p2 = new Ken_Questionnaire_Parameter__c(
            Questionnaire__c = qnr.Id,
            Question_Label__c = 'Public Q2',
            Question_Type__c = 'Multiple Choice',
            Is_Required__c = false,
            // include comma + newline so getSurveyForEdit() split('[;,\n]+') is covered
            MCQ_Options__c = 'A;B,C\nD',
            Order__c = 2,
            Section_Name__c = 'Public Survey'
        );
        insert new List<Ken_Questionnaire_Parameter__c>{ p1, p2 };

        Ken_Survey__c survey = new Ken_Survey__c(
            Name = 'Public Survey',
            Section_Name__c = 'Public Survey',
            Description__c = 'Public survey description',
            Target_Audience__c = 'Students;Alumni',
            Start_Date__c = System.now().addDays(-2),
            End_Date__c = System.now().addDays(10),
            Approval_Status__c = 'Approved',
            Is_Active__c = true,
            Ken_Questionnaire__c = qnr.Id,
            // Not equal to the "current role" we will set in tests
            Constituent_Role__c = otherRole.Id
        );
        insert survey;

        Ken_Segmentation__c segmentation = new Ken_Segmentation__c(
            Name = 'Survey Segmentation',
            Active__c = true,
            SOQL__c = 'SELECT Id FROM ConstituentRole WHERE Id = \'' + currentRole.Id + '\''
        );
        insert segmentation;

        insert new Ken_Survey_Segmentation__c(
            Survey__c = survey.Id,
            Segmentation__c = segmentation.Id
        );
    }

    @IsTest
    static void testCreate_edit_update_list_submit_export_delete_and_negative() {
        // Set test "current role id" used by KenSurveyController filters
        Account currentAcc = [SELECT Id FROM Account WHERE Name = 'Current Account' LIMIT 1];
        Id currentRoleId = [SELECT Id FROM ConstituentRole WHERE PersonId = :currentAcc.Id LIMIT 1].Id;

        Test.startTest();

        // ---------------- CREATE ----------------
        KenSurveyController.SurveySaveRequest req = buildSampleCreateRequest();
        Id createdSurveyId = KenSurveyController.createSurveyWithQuestions(req, currentRoleId);
        System.assertNotEquals(null, createdSurveyId, 'Survey should be created');

        // ---------------- EDIT ----------------
        KenSurveyController.SurveyEditResponse editResp = KenSurveyController.getSurveyForEdit(createdSurveyId);
        System.assertNotEquals(null, editResp, 'Edit response should not be null');
        System.assertEquals(createdSurveyId, editResp.surveyId, 'Survey id should match');
        System.assertNotEquals(null, editResp.data, 'Edit DTO should not be null');
        System.assertEquals('My Survey', editResp.data.title, 'Title should match');
        System.assert(editResp.data.questions != null && editResp.data.questions.size() > 0, 'Questions should exist');

        // ---------------- UPDATE (covers parseDate > 10 length) ----------------
        KenSurveyController.SurveySaveRequest upd = buildSampleCreateRequest();
        upd.title = 'My Survey Updated';
        upd.description = 'Updated description';
        upd.startDate = '2026-02-01 00:00:00';
        upd.endDate   = '2026-02-28 00:00:00';

        Id updatedId = KenSurveyController.updateSurveyWithQuestions(upd, createdSurveyId);
        System.assertEquals(createdSurveyId, updatedId, 'Updated id should match');

        Ken_Survey__c updatedSurvey = [
            SELECT Name, Approval_Status__c
            FROM Ken_Survey__c
            WHERE Id = :createdSurveyId
            LIMIT 1
        ];
        System.assertEquals('My Survey Updated', updatedSurvey.Name);
        System.assertEquals('Pending Approval', updatedSurvey.Approval_Status__c);

        // ---------------- LIST ----------------
        List<KenSurveyController.SurveyData> surveys = KenSurveyController.getSurveys(currentRoleId);
        System.assert(surveys != null && surveys.size() >= 1, 'getSurveys should return records');

        // ---------------- SUBMIT RESPONSES (both branches) ----------------
        Ken_Survey__c createdSurvey = [
            SELECT Id, Ken_Questionnaire__c
            FROM Ken_Survey__c
            WHERE Id = :createdSurveyId
            LIMIT 1
        ];
        Ken_Questionnaire_Parameter__c qp = [
            SELECT Id
            FROM Ken_Questionnaire_Parameter__c
            WHERE Questionnaire__c = :createdSurvey.Ken_Questionnaire__c
            ORDER BY Order__c
            LIMIT 1
        ];

        // Branch 1: with responses
        KenSurveyController.SurveyResponseRequest submit1 = new KenSurveyController.SurveyResponseRequest();
        submit1.surveyId = createdSurveyId;

        KenSurveyController.QuestionResponse qr = new KenSurveyController.QuestionResponse();
        qr.questionId = qp.Id;
        qr.responseValue = 'Answer 1';
        submit1.responses = new List<KenSurveyController.QuestionResponse>{ qr };
        KenSurveyController.submitSurveyResponses(submit1);

        // Branch 2: empty list -> insert "Submitted"
        KenSurveyController.SurveyResponseRequest submit2 = new KenSurveyController.SurveyResponseRequest();
        submit2.surveyId = createdSurveyId;
        submit2.responses = new List<KenSurveyController.QuestionResponse>();
        KenSurveyController.submitSurveyResponses(submit2);

        // ---------------- EXPORT ----------------
        KenSurveyController.SurveyExportResult exportRes = KenSurveyController.getSurveyResponsesForExport(createdSurveyId);
        System.assertNotEquals(null, exportRes, 'Export result should not be null');
        System.assert(exportRes.questions != null && exportRes.questions.size() >= 1, 'Export questions should exist');
        System.assert(exportRes.rows != null && exportRes.rows.size() >= 1, 'Export rows should exist');

        // ---------------- DELETE ----------------
        KenSurveyController.deleteSurvey(createdSurveyId);
        System.assertEquals(0, [SELECT COUNT() FROM Ken_Survey__c WHERE Id = :createdSurveyId], 'Survey should be deleted');

        // ---------------- NEGATIVE CASES (robust) ----------------
        Boolean thrown;

        thrown = false;
        try { KenSurveyController.createSurveyWithQuestions(null, currentRoleId); } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown, 'Expected exception for createSurveyWithQuestions(null)');

        thrown = false;
        try { KenSurveyController.submitSurveyResponses(null); } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown, 'Expected exception for submitSurveyResponses(null)');

        thrown = false;
        try { KenSurveyController.getSurveyForEdit(null); } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown, 'Expected exception for getSurveyForEdit(null)');

        thrown = false;
        try { KenSurveyController.updateSurveyWithQuestions(buildSampleCreateRequest(), null); } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown, 'Expected exception for updateSurveyWithQuestions(..., null)');

        thrown = false;
        try { KenSurveyController.getSurveyResponsesForExport(null); } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown, 'Expected exception for getSurveyResponsesForExport(null)');

        thrown = false;
        try { KenSurveyController.deleteSurvey(null); } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown, 'Expected exception for deleteSurvey(null)');

        Test.stopTest();
    }

    @IsTest
    static void testDraftSegmentationAndMySurveys() {
        Account currentAcc = [SELECT Id FROM Account WHERE Name = 'Current Account' LIMIT 1];
        Id currentRoleId = [SELECT Id FROM ConstituentRole WHERE PersonId = :currentAcc.Id LIMIT 1].Id;

        KenSurveyController.SurveySaveRequest draftRequest = new KenSurveyController.SurveySaveRequest();
        draftRequest.title = 'Draft Survey';
        draftRequest.description = 'Draft description';
        draftRequest.targetAudience = new List<String>{ 'Alumni' };
        draftRequest.startDate = '2026-03-01';
        draftRequest.endDate = '2026-03-30';

        Test.startTest();
        Id draftId = KenSurveyController.saveSurveyDraft(draftRequest, null, currentRoleId);
        System.assertNotEquals(null, draftId, 'Draft survey should be created.');

        draftRequest.title = 'Draft Survey Updated';
        draftRequest.startDate = '2026-03-01 00:00:00';
        draftRequest.endDate = '2026-03-30 00:00:00';
        Id updatedDraftId = KenSurveyController.saveSurveyDraft(draftRequest, draftId, currentRoleId);
        System.assertEquals(draftId, updatedDraftId, 'Draft survey update should keep same Id.');

        Ken_Segmentation__c segmentation = new Ken_Segmentation__c(
            Name = 'Draft Segmentation',
            Active__c = true,
            SOQL__c = 'SELECT Id FROM ConstituentRole WHERE Id = \'' + currentRoleId + '\''
        );
        insert segmentation;

        Id firstLinkId = KenSurveyController.createSurveySegmentation(draftId, segmentation.Id);
        Id secondLinkId = KenSurveyController.createSurveySegmentation(draftId, segmentation.Id);
        System.assertEquals(firstLinkId, secondLinkId, 'Second segmentation call should return existing link Id.');

        Id mySurveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest(), currentRoleId);
        System.assertNotEquals(null, mySurveyId, 'A survey with questionnaire should be created for getMySurveys.');

        List<KenSurveyController.SurveyData> mySurveys = KenSurveyController.getMySurveys(currentRoleId);
        System.assert(mySurveys.size() > 0, 'getMySurveys should include user-created surveys with questionnaire.');

        List<KenSurveyController.SurveyData> emptyForNullRole = KenSurveyController.getMySurveys(null);
        System.assertEquals(0, emptyForNullRole.size(), 'Null role should return empty list.');

        List<KenSurveyController.SurveyData> emptyForNullGetSurveys = KenSurveyController.getSurveys(null);
        System.assertEquals(0, emptyForNullGetSurveys.size(), 'Null role should return empty list from getSurveys.');
        Test.stopTest();
    }

    /**
     * Internal (System Admin) users invoke createSurveyWithQuestions / saveSurveyDraft from the
     * Ken_Survey__c New + Edit action overrides without a ConstituentRoleId. The controller
     * should accept null and save the survey with Constituent_Role__c = null.
     */
    @IsTest
    static void testAdminContext_NullConstituentRole_AllowedForInternalUser() {
        // The test runner is a System Admin (UserType = 'Standard', AccountId = null),
        // so isInternalUser() returns true and the null role should be tolerated.
        Test.startTest();
        Id draftId = KenSurveyController.saveSurveyDraft(buildSampleCreateRequest(), null, null);
        System.assertNotEquals(null, draftId, 'Admin-context draft save should succeed with null role.');

        Id createdId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest(), null);
        System.assertNotEquals(null, createdId, 'Admin-context create should succeed with null role.');

        Ken_Survey__c created = [SELECT Id, Constituent_Role__c FROM Ken_Survey__c WHERE Id = :createdId LIMIT 1];
        System.assertEquals(null, created.Constituent_Role__c, 'Internal-user surveys should have no Constituent_Role__c.');
        Test.stopTest();
    }

    @IsTest
    static void testSurveyStatsAndShortAnswerExports() {
        Account currentAcc = [SELECT Id FROM Account WHERE Name = 'Current Account' LIMIT 1];
        Id currentRoleId = [SELECT Id FROM ConstituentRole WHERE PersonId = :currentAcc.Id LIMIT 1].Id;

        Id surveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest(), currentRoleId);
        Id questionnaireId = [
            SELECT Ken_Questionnaire__c
            FROM Ken_Survey__c
            WHERE Id = :surveyId
            LIMIT 1
        ].Ken_Questionnaire__c;
        Id firstQuestionId = [
            SELECT Id
            FROM Ken_Questionnaire_Parameter__c
            WHERE Questionnaire__c = :questionnaireId
            ORDER BY Order__c
            LIMIT 1
        ].Id;

        Account respondentOne = new Account(Name = 'Respondent One');
        Account respondentTwo = new Account(Name = 'Respondent Two');
        insert new List<Account>{ respondentOne, respondentTwo };

        Ken_Questionnaire_Parameter_Response__c olderResponse = new Ken_Questionnaire_Parameter_Response__c(
            Questionnaire_Parameter__c = firstQuestionId,
            Respondent__c = respondentOne.Id,
            Response__c = 'Old',
            Response_Category__c = 'Survey'
        );
        insert olderResponse;
        Test.setCreatedDate(olderResponse.Id, System.now().addMinutes(-2));

        Ken_Questionnaire_Parameter_Response__c latestResponse = new Ken_Questionnaire_Parameter_Response__c(
            Questionnaire_Parameter__c = firstQuestionId,
            Respondent__c = respondentOne.Id,
            Response__c = 'New',
            Response_Category__c = 'Survey'
        );
        insert latestResponse;

        insert new Ken_Questionnaire_Parameter_Response__c(
            Questionnaire_Parameter__c = firstQuestionId,
            Respondent__c = respondentTwo.Id,
            Response__c = 'New',
            Response_Category__c = 'Survey'
        );

        Test.startTest();
        List<KenSurveyController.QuestionStatsDTO> stats = KenSurveyController.getSurveyResponseStats(surveyId);
        List<KenSurveyController.ShortAnswerCountDTO> shortCounts = KenSurveyController.getShortAnswerQuestionCounts(surveyId);
        KenSurveyController.ShortAnswerExportDTO shortExport =
            KenSurveyController.getShortAnswerResponsesForExport(surveyId, firstQuestionId);
        Test.stopTest();

        System.assert(stats.size() > 0, 'Survey response stats should return at least one question.');
        System.assert(shortCounts.size() > 0, 'Short-answer counts should return at least one question.');
        System.assertEquals(firstQuestionId, shortExport.questionId, 'Export should match requested question id.');
        System.assertEquals(2, shortExport.total, 'Latest non-blank responses should be returned for two respondents.');

        Boolean didThrow = false;
        try {
            KenSurveyController.getShortAnswerResponsesForExport(surveyId, null);
        } catch (AuraHandledException ex) {
            didThrow = true;
        }
        System.assertEquals(true, didThrow, 'Null question id should throw AuraHandledException.');
    }

    // ---------------- Helpers ----------------

    private static KenSurveyController.SurveySaveRequest buildSampleCreateRequest() {
        KenSurveyController.SurveySaveRequest req = new KenSurveyController.SurveySaveRequest();
        req.title = 'My Survey';
        req.description = 'Survey Description';
        req.targetAudience = new List<String>{ 'Students', 'Alumni' };
        req.startDate = '2026-01-01';
        req.endDate   = '2026-01-31';

        // Q1: short
        KenSurveyController.QuestionDTO q1 = new KenSurveyController.QuestionDTO();
        q1.text = 'What do you like?';
        q1.type = 'short';
        q1.required = true;

        // Q2: multiple
        KenSurveyController.QuestionDTO q2 = new KenSurveyController.QuestionDTO();
        q2.text = 'Pick one';
        q2.type = 'multiple';
        q2.required = false;
        q2.options = new List<KenSurveyController.QuestionOptionDTO>();
        for (String o : new List<String>{ 'A', 'B', 'C' }) {
            KenSurveyController.QuestionOptionDTO opt = new KenSurveyController.QuestionOptionDTO();
            opt.text = o;
            q2.options.add(opt);
        }

        // Q3: linear
        KenSurveyController.QuestionDTO q3 = new KenSurveyController.QuestionDTO();
        q3.text = 'Rate us';
        q3.type = 'linear';
        q3.required = true;
        q3.scaleMin = 1;
        q3.scaleMax = 5;
        q3.scaleMinLabel = 'Bad';
        q3.scaleMaxLabel = 'Great';

        req.questions = new List<KenSurveyController.QuestionDTO>{ q1, q2, q3 };
        return req;
    }

    @IsTest
    static void testEventFeedbackAsSurveyAndSubmit() {
        Ken_Questionnaire__c qnr = [SELECT Id FROM Ken_Questionnaire__c WHERE Section_Name__c = 'Public Survey' LIMIT 1];
        Id paramId = [SELECT Id FROM Ken_Questionnaire_Parameter__c WHERE Questionnaire__c = :qnr.Id ORDER BY Order__c ASC LIMIT 1].Id;

        Ken_Event_Master__c ev = new Ken_Event_Master__c(
            Name = 'Feedback Test Event',
            Start_Date__c = Date.today().addDays(-2),
            End_Date__c = Date.today().addDays(-1),
            Event_Type__c = 'Workshop',
            Event_Status__c = 'Approved',
            Is_Active__c = true
        );
        insert ev;

        // Feedback now flows through a Ken_Survey__c wrapper linked on the session.
        Ken_Survey__c feedbackSurvey = new Ken_Survey__c(
            Name = 'Feedback Test Session',
            Type__c = 'Feedback',
            Approval_Status__c = 'Approved',
            Is_Active__c = true,
            Ken_Questionnaire__c = qnr.Id
        );
        insert feedbackSurvey;

        Ken_Schedule_Sessions__c session = new Ken_Schedule_Sessions__c(
            Name = 'Feedback Test Session',
            Event_Reference__c = ev.Id,
            Start_Date__c = Date.today().addDays(-2),
            End_Date__c = Date.today().addDays(-2),
            Location_Type__c = 'Online',
            Questionnaire__c = qnr.Id,
            Survey__c = feedbackSurvey.Id
        );
        insert session;

        Ken_Schedule_Sessions__c sessionWithoutQ = new Ken_Schedule_Sessions__c(
            Name = 'Session Without Questionnaire',
            Event_Reference__c = ev.Id,
            Start_Date__c = Date.today().addDays(-2),
            End_Date__c = Date.today().addDays(-2),
            Location_Type__c = 'Online'
        );
        insert sessionWithoutQ;

        Test.startTest();

        KenSurveyController.SurveyData feedback = KenSurveyController.getEventFeedbackAsSurvey(session.Id);
        System.assertEquals(session.Id, feedback.id, 'Returned id should be the session id.');
        System.assertEquals(ev.Name, feedback.name, 'Name should fall back to the parent event name.');
        System.assertNotEquals(null, feedback.questionnaire, 'Questionnaire data should be populated.');
        System.assertEquals(2, feedback.questionnaire.parameters.size(), 'Both seeded questions should map across.');

        KenSurveyController.SurveyResponseRequest request = new KenSurveyController.SurveyResponseRequest();
        request.sessionId = session.Id;
        KenSurveyController.QuestionResponse qr = new KenSurveyController.QuestionResponse();
        qr.questionId = paramId;
        qr.responseValue = 'Great event';
        request.responses = new List<KenSurveyController.QuestionResponse>{ qr };
        KenSurveyController.submitSurveyResponses(request);

        List<Ken_Questionnaire_Parameter_Response__c> saved = [
            SELECT Id, Response_Category__c, Questionnaire_Parameter__r.Questionnaire__c
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__r.Questionnaire__c = :qnr.Id
        ];
        System.assertEquals(1, saved.size(), 'Exactly one event-feedback response should be saved.');
        System.assertEquals('Event', saved[0].Response_Category__c, 'Response category should be Event.');
        System.assertEquals(qnr.Id, saved[0].Questionnaire_Parameter__r.Questionnaire__c, 'Event feedback should link to the session survey questionnaire.');

        Boolean thrown = false;
        try {
            KenSurveyController.getEventFeedbackAsSurvey(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null session id should throw.');

        thrown = false;
        try {
            KenSurveyController.getEventFeedbackAsSurvey(sessionWithoutQ.Id);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Session without questionnaire should throw.');

        Test.stopTest();
    }

    private static ConstituentRole createConstituentRole(Id accountId, String email) {
        ConstituentRole cr = new ConstituentRole(
            PersonId = accountId,
            RoleType = 'Alumni',
            Registration_Status__c = 'Registered',
            Email__c = email
        );
        cr.put('Status', 'Admitted');
        insert cr;
        return cr;
    }

    @IsTest
    static void saveSurveyDraftStoresLocalDayBoundaries() {
        // A survey starting today must be live all day and one ending today must
        // stay open until midnight — dates are stored at ORG-LOCAL day boundaries,
        // not GMT midnight (which shifted the boundary by the org's UTC offset).
        KenSurveyController.SurveySaveRequest req = buildSampleCreateRequest();
        req.startDate = String.valueOf(Date.today());
        req.endDate = String.valueOf(Date.today());

        Test.startTest();
        Id surveyId = KenSurveyController.saveSurveyDraft(req, null, null);
        Test.stopTest();

        Ken_Survey__c s = [SELECT Start_Date__c, End_Date__c FROM Ken_Survey__c WHERE Id = :surveyId];
        System.assertEquals(
            Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0)),
            s.Start_Date__c,
            'Start date should be org-local midnight so a survey starting today shows immediately.'
        );
        System.assertEquals(
            Datetime.newInstance(Date.today(), Time.newInstance(23, 59, 59, 0)),
            s.End_Date__c,
            'End date should be org-local end-of-day so a survey ending today stays open through today.'
        );
    }
}