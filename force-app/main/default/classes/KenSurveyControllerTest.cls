/**
 * @description Covers the survey stack end to end on the standard Assessment objects:
 *              authoring, editing, rendering, submitting, statistics, export, the record page
 *              view and delete. Also exercises KenAssessmentSurveyService directly for the
 *              choice encoding a linear scale relies on.
 */
@IsTest
public class KenSurveyControllerTest {

    @TestSetup
    static void setupData() {
        Account currentAcc = new Account(Name = 'Current Account');
        Account otherAcc = new Account(Name = 'Other Account');
        insert new List<Account>{ currentAcc, otherAcc };

        ConstituentRole currentRole = createConstituentRole(currentAcc.Id, 'current@test.com');
        ConstituentRole otherRole = createConstituentRole(otherAcc.Id, 'other@test.com');

        Id publicSetId = KenAssessmentSurveyService.saveQuestionSet(null, 'Public Survey',
            new List<KenAssessmentSurveyService.QuestionInput>{
                questionInput('Public Q1', 'Short Answer', true, null),
                questionInput('Public Q2', 'Multiple Choice', false, new List<String>{ 'A', 'B', 'C' })
            }
        );

        Ken_Survey__c survey = new Ken_Survey__c(
            Name = 'Public Survey',
            Description__c = 'Public survey description',
            Target_Audience__c = 'Students;Alumni',
            Start_Date__c = System.now().addDays(-2),
            End_Date__c = System.now().addDays(10),
            Approval_Status__c = 'Approved',
            Is_Active__c = true,
            Assessment_Question_Set__c = publicSetId,
            Constituent_Role__c = otherRole.Id
        );
        insert survey;

        Ken_Segmentation__c segmentation = new Ken_Segmentation__c(
            Name = 'Survey Segmentation',
            Active__c = true,
            SOQL__c = 'SELECT Id FROM ConstituentRole WHERE Id = \'' + currentRole.Id + '\'',
            Definition_JSON__c = '{"targetObject":"ConstituentRole","items":[{"id":"' + currentRole.Id + '","type":"INDIVIDUAL"}]}'
        );
        insert segmentation;

        update new Ken_Survey__c(Id = survey.Id, Segmentation__c = segmentation.Id);
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

    private static KenAssessmentSurveyService.QuestionInput questionInput(String text, String type, Boolean required, List<String> choiceValues) {
        KenAssessmentSurveyService.QuestionInput q = new KenAssessmentSurveyService.QuestionInput();
        q.text = text;
        q.questionType = type;
        q.required = required;
        q.choices = new List<KenAssessmentSurveyService.ChoiceRow>();
        if (choiceValues != null) {
            for (String v : choiceValues) {
                KenAssessmentSurveyService.ChoiceRow c = new KenAssessmentSurveyService.ChoiceRow();
                c.value = v;
                c.label = v;
                q.choices.add(c);
            }
        }
        return q;
    }

    private static Id currentRoleId() {
        Account currentAcc = [SELECT Id FROM Account WHERE Name = 'Current Account' LIMIT 1];
        return [SELECT Id FROM ConstituentRole WHERE PersonId = :currentAcc.Id LIMIT 1].Id;
    }

    private static KenSurveyController.SurveySaveRequest buildSampleCreateRequest() {
        KenSurveyController.SurveySaveRequest req = new KenSurveyController.SurveySaveRequest();
        req.title = 'My Survey';
        req.description = 'Survey Description';
        req.targetAudience = new List<String>{ 'Students', 'Alumni' };
        req.startDate = '2026-01-01';
        req.endDate = '2026-01-31';

        KenSurveyController.QuestionDTO q1 = new KenSurveyController.QuestionDTO();
        q1.text = 'What do you like?';
        q1.type = 'short';
        q1.required = true;

        KenSurveyController.QuestionDTO q2 = new KenSurveyController.QuestionDTO();
        q2.text = 'Pick one';
        q2.type = 'multiple';
        q2.required = false;
        q2.options = new List<KenSurveyController.QuestionOptionDTO>();
        for (String o : new List<String>{ 'A', 'B', 'C' }) {
            KenSurveyController.QuestionOptionDTO opt = new KenSurveyController.QuestionOptionDTO();
            opt.value = o;
            opt.text = o;
            q2.options.add(opt);
        }

        KenSurveyController.QuestionDTO q3 = new KenSurveyController.QuestionDTO();
        q3.text = 'Rate us';
        q3.type = 'linear';
        q3.required = true;
        q3.options = new List<KenSurveyController.QuestionOptionDTO>();
        Map<String, String> scalePoints = new Map<String, String>{
            '1' => 'Poor', '2' => 'Fair', '3' => 'Good', '4' => 'Very good', '5' => 'Excellent'
        };
        for (String point : new List<String>{ '1', '2', '3', '4', '5' }) {
            KenSurveyController.QuestionOptionDTO opt = new KenSurveyController.QuestionOptionDTO();
            opt.value = point;
            opt.text = scalePoints.get(point);
            q3.options.add(opt);
        }

        req.questions = new List<KenSurveyController.QuestionDTO>{ q1, q2, q3 };
        return req;
    }

    @IsTest
    static void linearScaleKeepsAPerPointLabel() {
        KenConstituentRoleService.testCurrentRoleId = currentRoleId();

        Test.startTest();
        Id surveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());
        Test.stopTest();

        KenSurveyController.SurveyEditResponse edit = KenSurveyController.getSurveyForEdit(surveyId);
        KenSurveyController.QuestionDTO scale = null;
        for (KenSurveyController.QuestionDTO q : edit.data.questions) {
            if (q.text == 'Rate us') {
                scale = q;
            }
        }
        System.assertNotEquals(null, scale, 'The linear question should round-trip');
        System.assertEquals('linear', scale.type, 'Type should round-trip to the client vocabulary');
        System.assertEquals(5, scale.options.size(), 'Every scale point should round-trip as an option');
        System.assertEquals('1', scale.options[0].value, 'The first point keeps its value');
        System.assertEquals('Poor', scale.options[0].text, 'The first point keeps its own label');
        System.assertEquals('5', scale.options[4].value, 'The last point keeps its value');
        System.assertEquals('Excellent', scale.options[4].text, 'The last point keeps its own label');
    }

    @IsTest
    static void encodesAndParsesChoicesWithLabels() {
        List<KenAssessmentSurveyService.ChoiceRow> choices = new List<KenAssessmentSurveyService.ChoiceRow>();
        KenAssessmentSurveyService.ChoiceRow labelled = new KenAssessmentSurveyService.ChoiceRow();
        labelled.value = '1';
        labelled.label = 'Poor';
        choices.add(labelled);
        KenAssessmentSurveyService.ChoiceRow plain = new KenAssessmentSurveyService.ChoiceRow();
        plain.value = 'Yes';
        plain.label = 'Yes';
        choices.add(plain);

        Test.startTest();
        String encoded = KenAssessmentSurveyService.encodeChoices(choices);
        List<KenAssessmentSurveyService.ChoiceRow> parsed = KenAssessmentSurveyService.parseChoices(encoded);
        Test.stopTest();

        System.assertEquals('1:Poor;Yes', encoded, 'A label equal to its value is not written twice');
        System.assertEquals(2, parsed.size(), 'Both choices should parse back');
        System.assertEquals('1', parsed[0].value, 'Point value survives the round trip');
        System.assertEquals('Poor', parsed[0].label, 'Point label survives the round trip');
        System.assertEquals('Yes', parsed[1].value, 'A plain choice keeps its text as the value');
        System.assertEquals('Yes', parsed[1].label, 'A plain choice labels itself');
        System.assert(KenAssessmentSurveyService.parseChoices(null).isEmpty(), 'No choices parses to an empty list');
    }

    @IsTest
    static void createEditUpdateAndDelete() {
        KenConstituentRoleService.testCurrentRoleId = currentRoleId();

        Test.startTest();
        Id createdSurveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());
        System.assertNotEquals(null, createdSurveyId, 'Survey should be created');

        Ken_Survey__c created = [
            SELECT Assessment_Question_Set__c FROM Ken_Survey__c WHERE Id = :createdSurveyId
        ];
        System.assertNotEquals(null, created.Assessment_Question_Set__c, 'Survey should point at a question set');
        System.assertEquals(3, [
            SELECT COUNT() FROM AssessmentQuestion
            WHERE Ken_Question_Set__c = :created.Assessment_Question_Set__c
        ], 'Every question should be assigned to the set');

        KenSurveyController.SurveyEditResponse editResp = KenSurveyController.getSurveyForEdit(createdSurveyId);
        System.assertEquals('My Survey', editResp.data.title, 'Title should match');
        System.assertEquals(3, editResp.data.questions.size(), 'All questions should come back');

        KenSurveyController.SurveySaveRequest upd = buildSampleCreateRequest();
        upd.title = 'My Survey Updated';
        upd.questions.remove(2);
        Id updatedId = KenSurveyController.updateSurveyWithQuestions(upd, createdSurveyId);
        System.assertEquals(createdSurveyId, updatedId, 'Updated id should match');
        Test.stopTest();

        Ken_Survey__c updated = [
            SELECT Name, Approval_Status__c, Assessment_Question_Set__c
            FROM Ken_Survey__c WHERE Id = :createdSurveyId
        ];
        System.assertEquals('My Survey Updated', updated.Name, 'Title should be updated');
        System.assertEquals(created.Assessment_Question_Set__c, updated.Assessment_Question_Set__c,
            'Editing reuses the same question set rather than orphaning it');
        System.assertEquals(2, [
            SELECT COUNT() FROM AssessmentQuestion
            WHERE Ken_Question_Set__c = :updated.Assessment_Question_Set__c
        ], 'The removed question should no longer be assigned');

        KenSurveyController.deleteSurvey(createdSurveyId);
        System.assertEquals(0, [SELECT COUNT() FROM Ken_Survey__c WHERE Id = :createdSurveyId],
            'Survey should be deleted');
        System.assertEquals(0, [
            SELECT COUNT() FROM AssessmentQuestionSet WHERE Id = :updated.Assessment_Question_Set__c
        ], 'The question set should go with the survey');
    }

    @IsTest
    static void submitStatsAndExport() {
        Id roleId = currentRoleId();
        KenConstituentRoleService.testCurrentRoleId = roleId;
        Id surveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());
        Ken_Survey__c survey = [SELECT Assessment_Question_Set__c FROM Ken_Survey__c WHERE Id = :surveyId];
        List<KenAssessmentSurveyService.QuestionRow> rows =
            KenAssessmentSurveyService.questionsForSet(survey.Assessment_Question_Set__c);

        KenSurveyController.SurveyResponseRequest req = new KenSurveyController.SurveyResponseRequest();
        req.surveyId = surveyId;
        req.responses = new List<KenSurveyController.QuestionResponse>();
        for (KenAssessmentSurveyService.QuestionRow row : rows) {
            KenSurveyController.QuestionResponse answer = new KenSurveyController.QuestionResponse();
            answer.questionId = row.id;
            answer.responseValue = 'A';
            req.responses.add(answer);
        }

        Test.startTest();
        KenSurveyController.submitSurveyResponses(req);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Assessment WHERE Ken_Survey__c = :surveyId],
            'One submission header per submit');
        System.assertEquals(3, [
            SELECT COUNT() FROM AssessmentQuestionResponse WHERE Assessment.Ken_Survey__c = :surveyId
        ], 'One answer row per answered question');

        Assessment header = [
            SELECT Id, AssessmentStatus, Response_Category__c, Submitted_Date__c
            FROM Assessment WHERE Ken_Survey__c = :surveyId LIMIT 1
        ];
        System.assertEquals('Completed', header.AssessmentStatus, 'A submitted survey is Completed');
        System.assertEquals('Survey', header.Response_Category__c, 'Category should be stamped');
        System.assertNotEquals(null, header.Submitted_Date__c, 'Submitted date should be stamped');

        AssessmentQuestionResponse answerRow = [
            SELECT Question_Label__c FROM AssessmentQuestionResponse
            WHERE Assessment.Ken_Survey__c = :surveyId LIMIT 1
        ];
        System.assertNotEquals(null, answerRow.Question_Label__c,
            'The question text is snapshotted so reports survive a reword');

        header.Respondent__c = [SELECT Id FROM Account WHERE Name = 'Current Account' LIMIT 1].Id;
        update header;

        System.assertEquals(3, KenSurveyController.getSurveyResponseStats(surveyId).size(),
            'Statistics should cover every answered question');
        System.assertEquals(3, KenSurveyController.getShortAnswerQuestionCounts(surveyId).size(),
            'Counts should cover every answered question');
        System.assertEquals(1,
            KenSurveyController.getShortAnswerResponsesForExport(surveyId, rows[0].id).total,
            'One respondent answered the first question');

        KenSurveyController.SurveyExportResult exported = KenSurveyController.getSurveyResponsesForExport(surveyId);
        System.assertEquals(3, exported.questions.size(), 'Export lists every question');
        System.assertEquals(1, exported.rows.size(), 'Export has one row per submission');
        System.assertEquals(3, exported.rows[0].answersByQuestionId.size(), 'Export row carries every answer');
    }

    @IsTest
    static void recordPageViewShowsQuestionsAndResponses() {
        Id roleId = currentRoleId();
        KenConstituentRoleService.testCurrentRoleId = roleId;
        Id surveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());
        Ken_Survey__c survey = [SELECT Assessment_Question_Set__c FROM Ken_Survey__c WHERE Id = :surveyId];
        List<KenAssessmentSurveyService.QuestionRow> rows =
            KenAssessmentSurveyService.questionsForSet(survey.Assessment_Question_Set__c);

        List<KenAssessmentSurveyService.AnswerInput> answers = new List<KenAssessmentSurveyService.AnswerInput>();
        KenAssessmentSurveyService.AnswerInput a = new KenAssessmentSurveyService.AnswerInput();
        a.questionId = rows[0].id;
        a.value = 'Loved it';
        answers.add(a);
        Account respondent = [SELECT Id FROM Account WHERE Name = 'Current Account' LIMIT 1];
        KenAssessmentSurveyService.submitResponses(surveyId, respondent.Id, 'Survey', answers);

        Test.startTest();
        KenSurveyController.SurveyRecordView view = KenSurveyController.getSurveyRecordView(surveyId);
        Test.stopTest();

        System.assertEquals('My Survey', view.name, 'The view carries the survey name');
        System.assertEquals(3, view.questionCount, 'The view counts every question');
        System.assertEquals(1, view.respondentCount, 'The view counts distinct respondents');
        System.assertEquals(1, view.submissions.size(), 'The view lists the submission');
        System.assertEquals('Loved it', view.submissions[0].answers[0].answer, 'The answer text comes through');
        System.assertEquals(5, view.questions[2].options.size(), 'A scale question exposes all its points');
    }

    @IsTest
    static void listsSurveysForAuthorAndAudience() {
        Id roleId = currentRoleId();
        KenConstituentRoleService.testCurrentRoleId = roleId;
        Id mine = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());

        Test.startTest();
        List<KenSurveyController.SurveyData> authored = KenSurveyController.getMySurveys();
        List<KenSurveyController.SurveyData> visible = KenSurveyController.getSurveys();
        Test.stopTest();

        System.assertEquals(1, authored.size(), 'Only the survey this role authored is listed');
        System.assertEquals(mine, authored[0].id, 'The authored survey is the one created here');
        System.assertEquals(3, authored[0].questionnaire.parameters.size(),
            'Authored surveys carry their questions');
        System.assertEquals(1, visible.size(), 'The seeded public survey is visible to other roles');
        System.assertEquals('Public Survey', visible[0].name, 'The public survey is the seeded one');
    }

    @IsTest
    static void sessionFeedbackRendersAndSubmits() {
        Id roleId = currentRoleId();
        KenConstituentRoleService.testCurrentRoleId = roleId;

        Id setId = KenAssessmentSurveyService.saveQuestionSet(null, 'Session Feedback',
            new List<KenAssessmentSurveyService.QuestionInput>{
                questionInput('How was it?', 'Short Answer', true, null)
            }
        );
        Ken_Survey__c feedbackSurvey = new Ken_Survey__c(
            Name = 'Session Feedback',
            Approval_Status__c = 'Approved', Is_Active__c = true,
            Type__c = 'Feedback', Assessment_Question_Set__c = setId
        );
        insert feedbackSurvey;

        Ken_Event_Master__c event = new Ken_Event_Master__c(Name = 'Feedback Event');
        insert event;
        Ken_Schedule_Sessions__c session = new Ken_Schedule_Sessions__c(
            Event_Reference__c = event.Id, Survey__c = feedbackSurvey.Id
        );
        insert session;

        Test.startTest();
        KenSurveyController.SurveyData data = KenSurveyController.getEventFeedbackAsSurvey(session.Id);
        System.assertEquals(1, data.questionnaire.parameters.size(), 'The session form renders its question');

        KenSurveyController.SurveyResponseRequest req = new KenSurveyController.SurveyResponseRequest();
        req.sessionId = session.Id;
        req.responses = new List<KenSurveyController.QuestionResponse>();
        KenSurveyController.QuestionResponse answer = new KenSurveyController.QuestionResponse();
        answer.questionId = data.questionnaire.parameters[0].id;
        answer.responseValue = 'Great session';
        req.responses.add(answer);
        KenSurveyController.submitSurveyResponses(req);
        Test.stopTest();

        Assessment header = [
            SELECT Response_Category__c FROM Assessment
            WHERE Ken_Survey__c = :feedbackSurvey.Id LIMIT 1
        ];
        System.assertEquals('Event', header.Response_Category__c, 'Session feedback is categorised as Event');
    }

    @IsTest
    static void draftAndSegmentation() {
        KenConstituentRoleService.testCurrentRoleId = currentRoleId();
        KenSurveyController.SurveySaveRequest req = buildSampleCreateRequest();
        req.startDate = String.valueOf(Date.today());
        req.endDate = String.valueOf(Date.today());

        Test.startTest();
        Id surveyId = KenSurveyController.saveSurveyDraft(req, null);
        Id updatedId = KenSurveyController.saveSurveyDraft(req, surveyId);
        Ken_Segmentation__c seg = [SELECT Id FROM Ken_Segmentation__c LIMIT 1];
        Id linked = KenSurveyController.createSurveySegmentation(surveyId, seg.Id);
        Id sameLinked = KenSurveyController.createSurveySegmentation(surveyId, seg.Id);
        Test.stopTest();

        System.assertEquals(surveyId, updatedId, 'Saving a draft again updates the same survey');
        System.assertEquals(linked, sameLinked, 'Linking the same segmentation twice is idempotent');
        System.assertEquals(seg.Id,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :surveyId].Segmentation__c,
            'The survey must carry the linked audience');

        Ken_Survey__c s = [SELECT Start_Date__c, End_Date__c FROM Ken_Survey__c WHERE Id = :surveyId];
        System.assertEquals(
            Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0)), s.Start_Date__c,
            'Start date is org-local midnight so a survey starting today shows immediately'
        );
        System.assertEquals(
            Datetime.newInstance(Date.today(), Time.newInstance(23, 59, 59, 0)), s.End_Date__c,
            'End date is org-local end of day so a survey ending today stays open'
        );
    }

    @IsTest
    static void rejectsMissingInput() {
        KenConstituentRoleService.testCurrentRoleId = currentRoleId();
        Integer failures = 0;

        Test.startTest();
        try {
            KenSurveyController.createSurveyWithQuestions(null);
        } catch (AuraHandledException e) {
            failures++;
        }
        try {
            KenSurveyController.updateSurveyWithQuestions(buildSampleCreateRequest(), null);
        } catch (AuraHandledException e) {
            failures++;
        }
        try {
            KenSurveyController.submitSurveyResponses(new KenSurveyController.SurveyResponseRequest());
        } catch (AuraHandledException e) {
            failures++;
        }
        try {
            KenSurveyController.deleteSurvey(null);
        } catch (AuraHandledException e) {
            failures++;
        }
        Test.stopTest();

        System.assertEquals(4, failures, 'Every missing-input path should be rejected');
    }

    /**
     * @description Seeds submissions against an existing survey without going through the portal,
     *              so paging and export can be exercised at a size a real survey reaches.
     * @param surveyId Survey to attach the submissions to.
     * @param howMany How many submissions to create.
     * @return The submissions created.
     */
    private static List<Assessment> seedSubmissions(Id surveyId, Integer howMany) {
        Ken_Survey__c survey = [SELECT Assessment_Question_Set__c FROM Ken_Survey__c WHERE Id = :surveyId];
        List<KenAssessmentSurveyService.QuestionRow> rows =
            KenAssessmentSurveyService.questionsForSet(survey.Assessment_Question_Set__c);
        Account respondent = [SELECT Id FROM Account WHERE Name = 'Current Account' LIMIT 1];

        List<Assessment> headers = new List<Assessment>();
        for (Integer i = 0; i < howMany; i++) {
            headers.add(new Assessment(
                Name = 'Seeded ' + i,
                AssessmentStatus = 'Completed',
                Ken_Survey__c = surveyId,
                Respondent__c = respondent.Id,
                Response_Category__c = 'Survey',
                Submitted_Date__c = System.now(),
                Ken_Module__c = 'Alumni',
                EffectiveDateTime = System.now()
            ));
        }
        insert headers;

        List<AssessmentQuestionResponse> answers = new List<AssessmentQuestionResponse>();
        for (Assessment header : headers) {
            for (KenAssessmentSurveyService.QuestionRow row : rows) {
                answers.add(new AssessmentQuestionResponse(
                    Name = 'a',
                    AssessmentId = header.Id,
                    AssessmentQuestionId = row.id,
                    ResponseText = 'Answer from ' + header.Name,
                    Question_Label__c = row.questionLabel,
                    Response_Category__c = 'Survey'
                ));
            }
        }
        insert answers;
        return headers;
    }

    @IsTest
    static void pagingWalksEverySubmissionExactlyOnce() {
        KenConstituentRoleService.testCurrentRoleId = currentRoleId();
        Id surveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());
        Integer seeded = 60;
        seedSubmissions(surveyId, seeded);

        Test.startTest();
        KenSurveyController.SurveyRecordView view = KenSurveyController.getSurveyRecordView(surveyId);
        Set<Id> walked = new Set<Id>();
        Integer rowsReturned = 0;
        for (KenSurveyController.SubmissionView s : view.submissions) {
            walked.add(s.id);
            rowsReturned++;
        }

        KenSurveyController.SubmissionView last = view.submissions[view.submissions.size() - 1];
        Datetime cursorDate = last.cursorDate;
        Id cursorId = last.id;
        Integer guard = 0;
        while (guard < 20) {
            KenSurveyController.SubmissionPage page =
                KenSurveyController.getSubmissionsPage(surveyId, cursorDate, cursorId);
            if (page.submissions.isEmpty()) {
                break;
            }
            for (KenSurveyController.SubmissionView s : page.submissions) {
                walked.add(s.id);
                rowsReturned++;
            }
            cursorDate = page.nextCursorDate;
            cursorId = page.nextCursorId;
            guard++;
            if (page.hasMore != true) {
                break;
            }
        }
        Test.stopTest();

        System.assertNotEquals(null, last.cursorDate,
            'The first page must carry a cursor or Load more repeats it');
        System.assertEquals(seeded, view.totalSubmissions, 'The view counts every submission');
        System.assertEquals(seeded, walked.size(), 'Paging reaches every submission');
        System.assertEquals(seeded, rowsReturned,
            'Paging returns each submission once, with no page repeated');
    }

    @IsTest
    static void smallSurveyExportsInTheBrowser() {
        KenConstituentRoleService.testCurrentRoleId = currentRoleId();
        Id surveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());
        seedSubmissions(surveyId, 3);

        Test.startTest();
        Boolean needsBatch = KenSurveyController.exportNeedsBatch(surveyId);
        KenSurveyController.SurveyExportResult exported =
            KenSurveyController.getSurveyResponsesForExport(surveyId);
        Test.stopTest();

        System.assertEquals(false, needsBatch, 'A small survey downloads directly');
        System.assertEquals(false, exported.truncated, 'A small export is complete');
        System.assertEquals(3, exported.rows.size(), 'Every submission is exported');
    }

    @IsTest
    static void fullExportAttachesACsvToTheSurvey() {
        KenConstituentRoleService.testCurrentRoleId = currentRoleId();
        Id surveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());
        Integer seeded = 5;
        seedSubmissions(surveyId, seeded);

        Test.startTest();
        KenSurveyController.requestFullExport(surveyId);
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :surveyId
        ];
        System.assertEquals(1, links.size(), 'The export attaches one file to the survey');

        ContentVersion file = [
            SELECT Title, VersionData FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId AND IsLatest = true LIMIT 1
        ];
        String body = file.VersionData.toString();
        System.assert(file.Title.endsWith('.csv'), 'The export is a CSV');
        System.assert(!file.Title.contains('-part-'),
            'A single-file export is not numbered as a part');
        System.assertEquals(seeded, body.countMatches('\r\n'),
            'The file holds a header plus one line per submission');
        System.assert(body.contains('What do you like?'), 'The header names every question');
    }

    @IsTest
    static void purgeQueueableRemovesResponsesInChunks() {
        KenConstituentRoleService.testCurrentRoleId = currentRoleId();
        Id surveyId = KenSurveyController.createSurveyWithQuestions(buildSampleCreateRequest());
        Ken_Survey__c survey = [SELECT Assessment_Question_Set__c FROM Ken_Survey__c WHERE Id = :surveyId];
        seedSubmissions(surveyId, 4);

        Test.startTest();
        System.enqueueJob(new KenSurveyPurgeQueueable(surveyId, survey.Assessment_Question_Set__c));
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM AssessmentQuestionResponse WHERE Assessment.Ken_Survey__c = :surveyId],
            'The first chunk clears the answers');
        System.assertEquals(4, [SELECT COUNT() FROM Assessment WHERE Ken_Survey__c = :surveyId],
            'Submissions survive until their answers are gone');

        // The job re-enqueues itself in production but not under test, so the later chunks are
        // driven directly to prove each one hands over to the next.
        KenSurveyPurgeQueueable purge =
            new KenSurveyPurgeQueueable(surveyId, survey.Assessment_Question_Set__c);
        purge.execute(null);
        System.assertEquals(0, [SELECT COUNT() FROM Assessment WHERE Ken_Survey__c = :surveyId],
            'The next chunk clears the submissions');
        System.assertEquals(1, [SELECT COUNT() FROM Ken_Survey__c WHERE Id = :surveyId],
            'The survey is deleted last so a failed chunk stays findable');

        purge.execute(null);
        System.assertEquals(0, [SELECT COUNT() FROM Ken_Survey__c WHERE Id = :surveyId],
            'The final chunk removes the survey itself');
    }
}