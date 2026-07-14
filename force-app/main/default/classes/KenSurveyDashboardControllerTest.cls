@IsTest
private class KenSurveyDashboardControllerTest {

    @TestSetup
    static void makeData() {
        // Questionnaires — one per survey (survey <-> questionnaire is 1:1; responses
        // reach the survey only through Questionnaire_Parameter__r.Questionnaire__c).
        Ken_Questionnaire__c q1 = new Ken_Questionnaire__c(Section_Name__c = 'Test Section 1');
        Ken_Questionnaire__c q2 = new Ken_Questionnaire__c(Section_Name__c = 'Test Section 2');
        insert new List<Ken_Questionnaire__c>{ q1, q2 };

        // Questionnaire parameters
        Ken_Questionnaire_Parameter__c q1p1 = new Ken_Questionnaire_Parameter__c(
            Questionnaire__c = q1.Id, Question_Label__c = 'What is your favourite colour?',
            Question_Type__c = 'Multiple Choice', Is_Required__c = true, Order__c = 1, Weightage__c = 10
        );
        Ken_Questionnaire_Parameter__c q1p2 = new Ken_Questionnaire_Parameter__c(
            Questionnaire__c = q1.Id, Question_Label__c = 'Rate your experience',
            Question_Type__c = 'Linear Scale', Is_Required__c = false, Order__c = 2, Weightage__c = 5
        );
        Ken_Questionnaire_Parameter__c q2p1 = new Ken_Questionnaire_Parameter__c(
            Questionnaire__c = q2.Id, Question_Label__c = 'How was the faculty?',
            Question_Type__c = 'Multiple Choice', Is_Required__c = true, Order__c = 1, Weightage__c = 10
        );
        insert new List<Ken_Questionnaire_Parameter__c>{ q1p1, q1p2, q2p1 };

        // Respondent account (standard Account — no person account needed)
        Account respondent = new Account(Name = 'Test Respondent Account');
        insert respondent;

        // Surveys  — varied Approval_Status__c and Is_Active__c
        Ken_Survey__c s1 = new Ken_Survey__c(
            Name               = 'Alumni Satisfaction Survey',
            Approval_Status__c = 'Approved',
            Is_Active__c       = true,
            Target_Audience__c = 'Alumni',
            Ken_Questionnaire__c = q1.Id
        );
        Ken_Survey__c s2 = new Ken_Survey__c(
            Name               = 'Faculty Feedback Survey',
            Approval_Status__c = 'Pending Approval',
            Is_Active__c       = false,
            Target_Audience__c = 'Faculty',
            Ken_Questionnaire__c = q2.Id
        );
        Ken_Survey__c s3 = new Ken_Survey__c(
            Name               = 'Rejected Test Survey',
            Approval_Status__c = 'Rejected',
            Is_Active__c       = false,
            Target_Audience__c = 'Students'
            // intentionally no questionnaire linkage
        );
        insert new List<Ken_Survey__c>{ s1, s2, s3 };

        // Responses — linked to the survey through its questionnaire's parameters
        insert new List<Ken_Questionnaire_Parameter_Response__c>{
            new Ken_Questionnaire_Parameter_Response__c(
                Questionnaire_Parameter__c  = q1p1.Id,
                Response__c                 = 'Blue',
                Response_Category__c        = 'Survey',
                Respondent__c               = respondent.Id
            ),
            new Ken_Questionnaire_Parameter_Response__c(
                Questionnaire_Parameter__c  = q1p2.Id,
                Response__c                 = '8',
                Response_Category__c        = 'Survey',
                Respondent__c               = respondent.Id
            ),
            new Ken_Questionnaire_Parameter_Response__c(
                Questionnaire_Parameter__c  = q2p1.Id,
                Response__c                 = 'Excellent',
                Response_Category__c        = 'Survey',
                Respondent__c               = respondent.Id
            )
        };
    }

    // ── getSummaryStats ─────────────────────────────────────────────────────

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

    // ── getSurveysByApprovalStatus ──────────────────────────────────────────

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

    // ── getSurveysByActiveStatus ────────────────────────────────────────────

    @IsTest
    static void testGetSurveysByActiveStatus() {
        Test.startTest();
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getSurveysByActiveStatus('All', 'All');
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assert(pts.size() >= 1, 'Expected active/inactive breakdown');
    }

    // ── getTopSurveysByResponses ────────────────────────────────────────────

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
        // Rejected + inactive → no surveys match → early return
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getTopSurveysByResponses('Rejected', 'true', 'All');
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assertEquals(0, pts.size(), 'No responses expected for rejected+active filter');
    }

    // ── getQuestionTypeDistribution ────────────────────────────────────────

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
        // Rejected surveys have no questionnaire linkage → empty qIds → early return
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getQuestionTypeDistribution('Rejected', null, null);
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assertEquals(0, pts.size(), 'Expected empty list for Rejected-only surveys without questionnaire');
    }

    // ── getResponseTrend ────────────────────────────────────────────────────

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
        // Non-existent year → no surveys → 12 zero-filled months still returned
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getResponseTrend(null, null, '1900');
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assertEquals(12, pts.size(), 'Should still return 12 month placeholders');
        for (KenSurveyDashboardController.ChartPoint p : pts) {
            System.assertEquals(0, p.value, 'All months should have 0 responses for year 1900');
        }
    }

    // ── getTopQuestionnaires ────────────────────────────────────────────────

    @IsTest
    static void testGetTopQuestionnaires() {
        Test.startTest();
        List<KenSurveyDashboardController.ChartPoint> pts =
            KenSurveyDashboardController.getTopQuestionnaires(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, pts);
        System.assert(pts.size() >= 1, 'Expected at least one questionnaire');
    }

    // ── getFilterOptions ────────────────────────────────────────────────────

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

    // ── getSurveyList ────────────────────────────────────────────────────────

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
        Ken_Questionnaire__c q = [SELECT Name FROM Ken_Questionnaire__c LIMIT 1];
        Test.startTest();
        List<KenSurveyDashboardController.SurveyListRecord> recs =
            KenSurveyDashboardController.getSurveyList('questionnaire', q.Name, null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, recs);
        System.assert(recs.size() >= 1, 'Expected surveys linked to the questionnaire');
    }

    // ── getResponseList ──────────────────────────────────────────────────────

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