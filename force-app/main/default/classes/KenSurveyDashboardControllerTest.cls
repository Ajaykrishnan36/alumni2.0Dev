@IsTest
private class KenSurveyDashboardControllerTest {

    @TestSetup
    static void makeData() {
        // Respondent account (standard Account â€” no person account needed)
        Account respondent = new Account(Name = 'Test Respondent Account');
        insert respondent;

        Id set1 = KenAssessmentSurveyService.saveQuestionSet(null, 'Test Section 1',
            new List<KenAssessmentSurveyService.QuestionInput>{
                buildQuestion('What is your favourite colour?', 'Multiple Choice', true,
                    new List<String>{ 'Blue', 'Red' }),
                buildQuestion('Rate your experience', 'Linear Scale', false,
                    new List<String>{ '1', '2', '3' })
            }
        );
        Id set2 = KenAssessmentSurveyService.saveQuestionSet(null, 'Test Section 2',
            new List<KenAssessmentSurveyService.QuestionInput>{
                buildQuestion('How was the faculty?', 'Multiple Choice', true,
                    new List<String>{ 'Excellent', 'Good' })
            }
        );

        // Surveys  â€” varied Approval_Status__c and Is_Active__c
        Ken_Survey__c s1 = new Ken_Survey__c(
            Name               = 'Alumni Satisfaction Survey',
            Approval_Status__c = 'Approved',
            Is_Active__c       = true,
            Target_Audience__c = 'Alumni',
            Assessment_Question_Set__c = set1
        );
        Ken_Survey__c s2 = new Ken_Survey__c(
            Name               = 'Faculty Feedback Survey',
            Approval_Status__c = 'Pending Approval',
            Is_Active__c       = false,
            Target_Audience__c = 'Faculty',
            Assessment_Question_Set__c = set2
        );
        Ken_Survey__c s3 = new Ken_Survey__c(
            Name               = 'Rejected Test Survey',
            Approval_Status__c = 'Rejected',
            Is_Active__c       = false,
            Target_Audience__c = 'Students'
            // intentionally no question set linkage
        );
        insert new List<Ken_Survey__c>{ s1, s2, s3 };

        submitEveryQuestion(s1.Id, set1, respondent.Id);
        submitEveryQuestion(s2.Id, set2, respondent.Id);
    }

    private static KenAssessmentSurveyService.QuestionInput buildQuestion(
        String text, String questionType, Boolean required, List<String> choices
    ) {
        KenAssessmentSurveyService.QuestionInput q = new KenAssessmentSurveyService.QuestionInput();
        q.text = text;
        q.questionType = questionType;
        q.required = required;
        q.choices = new List<KenAssessmentSurveyService.ChoiceRow>();
        for (String choice : choices) {
            KenAssessmentSurveyService.ChoiceRow row = new KenAssessmentSurveyService.ChoiceRow();
            row.value = choice;
            row.label = choice;
            q.choices.add(row);
        }
        return q;
    }

    private static void submitEveryQuestion(Id surveyId, Id questionSetId, Id respondentId) {
        List<KenAssessmentSurveyService.AnswerInput> answers = new List<KenAssessmentSurveyService.AnswerInput>();
        for (KenAssessmentSurveyService.QuestionRow row : KenAssessmentSurveyService.questionsForSet(questionSetId)) {
            KenAssessmentSurveyService.AnswerInput answer = new KenAssessmentSurveyService.AnswerInput();
            answer.questionId = row.id;
            answer.value = 'Blue';
            answers.add(answer);
        }
        KenAssessmentSurveyService.submitResponses(surveyId, respondentId, 'Survey', answers);
    }

    // â”€â”€ getSummaryStats â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetSummaryStats_noFilter() {
        Test.startTest();
        KenSurveyDashboardController.SummaryStats s =
            KenSurveyDashboardController.getSummaryStats(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, s, 'Stats should not be null');
        System.assert(s.total >= 3,     'Expected at least 3 surveys');
        System.assert(s.active >= 1,    'Expected at least 1 active survey');
        System.assert(s.pending >= 1,   'Expected at least 1 pending survey');
        System.assert(s.responses >= 3, 'Expected at least 3 responses');
    }

    @IsTest
    static void testGetSummaryStats_withFilters() {
        Test.startTest();
        KenSurveyDashboardController.SummaryStats s =
            KenSurveyDashboardController.getSummaryStats('Approved', 'true', 'All');
        Test.stopTest();
        System.assertNotEquals(null, s);
        System.assert(s.total >= 1,  'Approved active filter should yield surveys');
        System.assert(s.active >= 1, 'Should be active');
    }

    // â”€â”€ getSurveysByApprovalStatus â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetSurveysByApprovalStatus() {
        Test.startTest();
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getSurveysByApprovalStatus('All', 'All');
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assert(pts.size() >= 1, 'Expected approval status breakdown');
        Boolean foundApproved = false;
        for (KenSurveyDashboardController.ChartPoint p : pts) {
            if (p.label == 'Approved') { foundApproved = true; break; }
        }
        System.assert(foundApproved, 'Approved status should appear');
    }

    // â”€â”€ getSurveysByActiveStatus â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetSurveysByActiveStatus() {
        Test.startTest();
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getSurveysByActiveStatus('All', 'All');
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assert(pts.size() >= 1, 'Expected active/inactive breakdown');
    }

    // â”€â”€ getTopSurveysByResponses â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetTopSurveysByResponses() {
        Test.startTest();
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getTopSurveysByResponses(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assert(pts.size() >= 1, 'Expected at least one survey with responses');
        System.assert(pts[0].value >= 1, 'Top survey should have >=1 response');
    }

    @IsTest
    static void testGetTopSurveysByResponses_empty() {
        Test.startTest();
        // Rejected + inactive â†’ no surveys match â†’ early return
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getTopSurveysByResponses('Rejected', 'true', 'All');
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assertEquals(0, pts.size(), 'No responses expected for rejected+active filter');
    }

    // â”€â”€ getQuestionTypeDistribution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetQuestionTypeDistribution() {
        Test.startTest();
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getQuestionTypeDistribution(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assert(pts.size() >= 1, 'Expected question type distribution');
    }

    @IsTest
    static void testGetQuestionTypeDistribution_empty() {
        Test.startTest();
        // Rejected surveys have no question set â†’ nothing to group â†’ early return
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getQuestionTypeDistribution('Rejected', null, null);
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assertEquals(0, pts.size(), 'Expected empty list for Rejected-only surveys without a question set');
    }

    // â”€â”€ getResponseTrend â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetResponseTrend() {
        Test.startTest();
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getResponseTrend(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assertEquals(12, pts.size(), 'Response trend should have 12 months');
    }

    @IsTest
    static void testGetResponseTrend_empty() {
        Test.startTest();
        // Non-existent year â†’ no surveys â†’ 12 zero-filled months still returned
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getResponseTrend(null, null, '1900');
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assertEquals(12, pts.size(), 'Should still return 12 month placeholders');
        for (KenSurveyDashboardController.ChartPoint p : pts) {
            System.assertEquals(0, p.value, 'All months should have 0 responses for year 1900');
        }
    }

    // â”€â”€ getTopQuestionnaires â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetTopQuestionnaires() {
        Test.startTest();
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getTopQuestionnaires(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assert(pts.size() >= 1, 'Expected at least one questionnaire');
    }

    // â”€â”€ getFilterOptions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetFilterOptions() {
        Test.startTest();
        Map<String, List<Map<String, String>>> opts =
            KenSurveyDashboardController.getFilterOptions();
        Test.stopTest();
        System.assertNotEquals(null, opts);
        System.assert(opts.containsKey('approvalStatuses'), 'Should contain approvalStatuses key');
        System.assert(opts.containsKey('years'),            'Should contain years key');
        System.assert(opts.get('approvalStatuses').size() >= 1, 'Should have at least one approval status');
        System.assert(opts.get('years').size() >= 1,            'Should have at least one year');
    }

    // â”€â”€ getSurveyList â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetSurveyList_noFilter() {
        Test.startTest();
        List<KenSurveyDashboardController.SurveyListRecord> recs =
            KenSurveyDashboardController.getSurveyList(null, null, null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, recs);
        System.assert(recs.size() >= 3, 'Expected all 3 surveys with no filter');
        System.assertNotEquals(null, recs[0].id,   'Id should be present');
        System.assertNotEquals(null, recs[0].name, 'Name should be present');
    }

    @IsTest
    static void testGetSurveyList_byApproval() {
        Test.startTest();
        List<KenSurveyDashboardController.SurveyListRecord> recs =
            KenSurveyDashboardController.getSurveyList('approval', 'Approved', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, recs);
        System.assert(recs.size() >= 1, 'Expected approved surveys');
        for (KenSurveyDashboardController.SurveyListRecord r : recs) {
            System.assertEquals('Approved', r.approvalStatus, 'All records should be Approved');
        }
    }

    @IsTest
    static void testGetSurveyList_byActive() {
        Test.startTest();
        List<KenSurveyDashboardController.SurveyListRecord> recs =
            KenSurveyDashboardController.getSurveyList('active', 'Active', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, recs);
        System.assert(recs.size() >= 1, 'Expected active surveys');
        for (KenSurveyDashboardController.SurveyListRecord r : recs) {
            System.assertEquals(true, r.isActive, 'All records should be active');
        }
    }

    @IsTest
    static void testGetSurveyList_byQuestionnaire() {
        AssessmentQuestionSet qSet = [
            SELECT Name FROM AssessmentQuestionSet WHERE Name = 'Test Section 1' LIMIT 1
        ];
        Test.startTest();
        List<KenSurveyDashboardController.SurveyListRecord> recs =
            KenSurveyDashboardController.getSurveyList('questionnaire', qSet.Name, null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, recs);
        System.assert(recs.size() >= 1, 'Expected surveys linked to the question set');
        System.assertEquals('Test Section 1', recs[0].questionnaire,
            'The drill-down label comes from the question set name');
    }

    // â”€â”€ getResponseList â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @IsTest
    static void testGetResponseList_noFilter() {
        Test.startTest();
        List<KenSurveyDashboardController.ResponseListRecord> recs =
            KenSurveyDashboardController.getResponseList(null, null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, recs);
        System.assert(recs.size() >= 3, 'Expected all 3 responses');
        System.assertNotEquals(null, recs[0].id,          'Id should be present');
        System.assertNotEquals(null, recs[0].surveyName,  'Survey name should be present');
    }

    @IsTest
    static void testGetResponseList_bySurvey() {
        Test.startTest();
        List<KenSurveyDashboardController.ResponseListRecord> recs =
            KenSurveyDashboardController.getResponseList('Alumni Satisfaction Survey', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, recs);
        System.assert(recs.size() >= 2, 'Expected responses for Alumni Satisfaction Survey');
        for (KenSurveyDashboardController.ResponseListRecord r : recs) {
            System.assertEquals('Alumni Satisfaction Survey', r.surveyName, 'All should match survey');
        }
    }

    @IsTest
    static void testInactiveFilterBranch() {
        Test.startTest();
        KenSurveyDashboardController.SummaryStats s =
            KenSurveyDashboardController.getSummaryStats(null, 'false', null);
        List<KenSurveyDashboardController.ChartPoint> byApproval =
            KenSurveyDashboardController.getSurveysByApprovalStatus('false', null);
        List<KenSurveyDashboardController.ChartPoint> byActive =
            KenSurveyDashboardController.getSurveysByActiveStatus(null, null);
        List<KenSurveyDashboardController.ChartPoint> topSurveys =
            KenSurveyDashboardController.getTopSurveysByResponses(null, 'false', null);
        List<KenSurveyDashboardController.ChartPoint> qTypeDist =
            KenSurveyDashboardController.getQuestionTypeDistribution(null, 'false', null);
        List<KenSurveyDashboardController.ChartPoint> trend =
            KenSurveyDashboardController.getResponseTrend(null, 'false', null);
        List<KenSurveyDashboardController.SurveyListRecord> surveys =
            KenSurveyDashboardController.getSurveyList(null, null, null, 'false', null);
        Test.stopTest();
        System.assertNotEquals(null, s);
        System.assertNotEquals(null, byApproval);
        System.assertNotEquals(null, byActive);
        System.assertNotEquals(null, surveys);
    }

    @IsTest
    static void testInvalidYearBranch() {
        Test.startTest();
        KenSurveyDashboardController.SummaryStats s =
            KenSurveyDashboardController.getSummaryStats(null, null, 'notAYear');
        List<KenSurveyDashboardController.ChartPoint> trend =
            KenSurveyDashboardController.getResponseTrend(null, null, 'notAYear');
        List<KenSurveyDashboardController.SurveyListRecord> surveys =
            KenSurveyDashboardController.getSurveyList(null, null, null, null, 'notAYear');
        Test.stopTest();
        System.assertNotEquals(null, s);
        System.assertNotEquals(null, trend);
        System.assertNotEquals(null, surveys);
    }
}