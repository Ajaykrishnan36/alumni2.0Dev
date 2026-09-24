/**
 * @description Controller for surveys: creation, editing, response capture, statistics and
 *              export. Ken_Survey__c is the header; its questions and answers live on the
 *              standard Assessment objects, reached through
 *              Ken_Survey__c.Assessment_Question_Set__c. All persistence goes through
 *              KenAssessmentSurveyService.
 */
public without sharing class KenSurveyController {
    private static final String MODULE_ALUMNI = 'Alumni';

    /** How many submissions the record page shows before pointing the reader at the export. */
    private static final Integer SUBMISSION_PAGE_SIZE = 25;

    /** Above this many answer rows a survey is purged asynchronously rather than inline. */
    private static final Integer INLINE_DELETE_LIMIT = 4000;

    /**
     * @description Request wrapper containing survey metadata and its questions.
     */
    public class SurveySaveRequest {
        @AuraEnabled public String title {get; set;}
        @AuraEnabled public String description {get; set;}
        @AuraEnabled public List<String> targetAudience {get; set;}
        @AuraEnabled public String startDate {get; set;}
        @AuraEnabled public String endDate {get; set;}
        @AuraEnabled public List<QuestionDTO> questions {get; set;}
    }

    /**
     * @description One question definition. Choice questions and linear scales both carry their
     *              points in options; a scale point's label is the wording shown under it.
     */
    public class QuestionDTO {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String text {get; set;}
        @AuraEnabled public String type {get; set;}
        @AuraEnabled public Boolean required {get; set;}
        @AuraEnabled public List<QuestionOptionDTO> options {get; set;}
    }

    /**
     * @description One selectable option. For a linear scale, value is the point and text is
     *              that point's label.
     */
    public class QuestionOptionDTO {
        @AuraEnabled public String value {get; set;}
        @AuraEnabled public String text {get; set;}
    }

    /**
     * @description Survey summary returned to the portal and admin lists.
     */
    public class SurveyData {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String name {get; set;}
        @AuraEnabled public Datetime startDate {get; set;}
        @AuraEnabled public Datetime endDate {get; set;}
        @AuraEnabled public String approvalStatus {get; set;}
        @AuraEnabled public Boolean isActive {get; set;}
        @AuraEnabled public String segmentationName {get; set;}
        @AuraEnabled public Id questionnaireId {get; set;}
        @AuraEnabled public Datetime submittedDate {get; set;}
        @AuraEnabled public Id createdById {get; set;}
        @AuraEnabled public Id createdByAccountId {get; set;}
        @AuraEnabled public Datetime rejectedDate {get; set;}
        @AuraEnabled public String rejectionReason {get; set;}
        @AuraEnabled public String rejectionComments {get; set;}
        @AuraEnabled public Datetime fromDate {get; set;}
        @AuraEnabled public Datetime toDate {get; set;}
        @AuraEnabled public QuestionnaireData questionnaire {get; set;}
        @AuraEnabled public Boolean hasResponses {get; set;}
        @AuraEnabled public Integer responsesCount {get; set;}
    }

    /**
     * @description The question list attached to a survey.
     */
    public class QuestionnaireData {
        @AuraEnabled public List<QuestionnaireParameterData> parameters {get; set;}
    }

    /**
     * @description One question as rendered by the portal.
     */
    public class QuestionnaireParameterData {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String questionType {get; set;}
        @AuraEnabled public String questionLabel {get; set;}
        @AuraEnabled public List<QuestionOptionDTO> options {get; set;}
        @AuraEnabled public Decimal displayOrder {get; set;}
        @AuraEnabled public Boolean required {get; set;}
    }

    /**
     * @description Answers submitted by one respondent.
     */
    public class SurveyResponseRequest {
        @AuraEnabled public Id surveyId {get; set;}
        @AuraEnabled public Id sessionId {get; set;}
        @AuraEnabled public List<QuestionResponse> responses {get; set;}
    }

    /**
     * @description One answer.
     */
    public class QuestionResponse {
        @AuraEnabled public Id questionId {get; set;}
        @AuraEnabled public String responseValue {get; set;}
    }

    /**
     * @description Editable survey plus its saved segmentation.
     */
    public class SurveyEditResponse {
        @AuraEnabled public SurveySaveRequest data {get; set;}
        @AuraEnabled public Id surveyId {get; set;}
        @AuraEnabled public String segmentationDefinitionJson {get; set;}
    }

    public class SurveyExportQuestion {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String label {get; set;}
        @AuraEnabled public Decimal displayOrder {get; set;}
        @AuraEnabled public String questionType {get; set;}
    }

    public class SurveyExportRow {
        @AuraEnabled public Id respondentId {get; set;}
        @AuraEnabled public Id accountId {get; set;}
        @AuraEnabled public String respondentName {get; set;}
        @AuraEnabled public Datetime submittedAt {get; set;}
        @AuraEnabled public Map<String, String> answersByQuestionId {get; set;}
    }

    public class SurveyExportResult {
        @AuraEnabled public String surveyName {get; set;}
        @AuraEnabled public List<SurveyExportQuestion> questions {get; set;}
        @AuraEnabled public List<SurveyExportRow> rows {get; set;}
        @AuraEnabled public Boolean truncated {get; set;}
    }

    public class ResponseStatDTO {
        @AuraEnabled public String responseValue { get; set; }
        @AuraEnabled public Integer count { get; set; }
        @AuraEnabled public Decimal percent { get; set; }
    }

    public class QuestionStatsDTO {
        @AuraEnabled public Id questionId { get; set; }
        @AuraEnabled public Integer total { get; set; }
        @AuraEnabled public List<ResponseStatDTO> stats { get; set; }
    }

    public class ShortAnswerCountDTO {
        @AuraEnabled public Id questionId { get; set; }
        @AuraEnabled public Integer total { get; set; }
    }

    public class ShortAnswerRowDTO {
        @AuraEnabled public Id respondentId { get; set; }
        @AuraEnabled public String respondentName { get; set; }
        @AuraEnabled public String responseText { get; set; }
    }

    public class ShortAnswerExportDTO {
        @AuraEnabled public Id questionId { get; set; }
        @AuraEnabled public Integer total { get; set; }
        @AuraEnabled public List<ShortAnswerRowDTO> rows { get; set; }
    }

    /**
     * @description Everything the survey record page shows: the header, its questions and the
     *              submissions received so far.
     */
    public class SurveyRecordView {
        @AuraEnabled public Id surveyId {get; set;}
        @AuraEnabled public String name {get; set;}
        @AuraEnabled public String description {get; set;}
        @AuraEnabled public String approvalStatus {get; set;}
        @AuraEnabled public Boolean isActive {get; set;}
        @AuraEnabled public String targetAudience {get; set;}
        @AuraEnabled public Datetime startDate {get; set;}
        @AuraEnabled public Datetime endDate {get; set;}
        @AuraEnabled public Id questionSetId {get; set;}
        @AuraEnabled public Integer questionCount {get; set;}
        @AuraEnabled public Integer respondentCount {get; set;}
        @AuraEnabled public Integer totalSubmissions {get; set;}
        @AuraEnabled public Integer shownSubmissions {get; set;}
        @AuraEnabled public List<QuestionnaireParameterData> questions {get; set;}
        @AuraEnabled public List<SubmissionView> submissions {get; set;}
    }

    public class SubmissionView {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public Id respondentId {get; set;}
        @AuraEnabled public String respondentName {get; set;}
        @AuraEnabled public Datetime submittedDate {get; set;}
        @AuraEnabled public Datetime cursorDate {get; set;}
        @AuraEnabled public List<AnswerView> answers {get; set;}
    }

    public class AnswerView {
        @AuraEnabled public String question {get; set;}
        @AuraEnabled public String answer {get; set;}
    }

    /**
     * @description One page of submissions plus the cursor needed to fetch the next.
     */
    public class SubmissionPage {
        @AuraEnabled public List<SubmissionView> submissions {get; set;}
        @AuraEnabled public Datetime nextCursorDate {get; set;}
        @AuraEnabled public Id nextCursorId {get; set;}
        @AuraEnabled public Boolean hasMore {get; set;}
    }

    /**
     * @description Fetches the next page of responses. The client passes back the cursor from
     *              the previous page, so paging works however many responses exist.
     * @param surveyId Survey to read.
     * @param cursorDate Cursor from the previous page, or null for the first page.
     * @param cursorId Cursor from the previous page, or null for the first page.
     * @return The page and its onward cursor.
     */
    @AuraEnabled
    public static SubmissionPage getSubmissionsPage(Id surveyId, Datetime cursorDate, Id cursorId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        SubmissionPage page = new SubmissionPage();
        page.submissions = buildSubmissionViews(surveyId, cursorDate, cursorId);
        page.hasMore = page.submissions.size() == SUBMISSION_PAGE_SIZE;
        if (!page.submissions.isEmpty()) {
            SubmissionView last = page.submissions[page.submissions.size() - 1];
            page.nextCursorDate = last.cursorDate;
            page.nextCursorId = last.id;
        }
        return page;
    }

    /**
     * @description Builds the submission views for one page, loading answers only for the
     *              submissions on that page.
     * @param surveyId Survey to read.
     * @param cursorDate Paging cursor.
     * @param cursorId Paging cursor.
     * @return Submission views, newest first.
     */
    private static List<SubmissionView> buildSubmissionViews(Id surveyId, Datetime cursorDate, Id cursorId) {
        List<SubmissionView> views = new List<SubmissionView>();
        Map<Id, SubmissionView> byAssessment = new Map<Id, SubmissionView>();
        for (Assessment header : KenAssessmentSurveyService.submissionsPage(
                surveyId, cursorDate, cursorId, SUBMISSION_PAGE_SIZE)) {
            SubmissionView submission = new SubmissionView();
            submission.id = header.Id;
            submission.respondentId = header.Respondent__c;
            submission.respondentName = header.Respondent__r != null
                ? header.Respondent__r.Name : 'Anonymous';
            submission.submittedDate = header.Submitted_Date__c != null
                ? header.Submitted_Date__c : header.CreatedDate;
            submission.cursorDate = header.CreatedDate;
            submission.answers = new List<AnswerView>();
            byAssessment.put(submission.id, submission);
            views.add(submission);
        }
        if (byAssessment.isEmpty()) {
            return views;
        }
        for (AssessmentQuestionResponse answer
                : KenAssessmentSurveyService.answersForSubmissions(byAssessment.keySet())) {
            SubmissionView submission = byAssessment.get(answer.Assessment.Id);
            if (submission == null) {
                continue;
            }
            AnswerView answerView = new AnswerView();
            answerView.question = answer.Question_Label__c;
            answerView.answer = answer.ResponseText;
            submission.answers.add(answerView);
        }
        return views;
    }

    /**
     * @description Loads a survey with its questions and submissions for the record page.
     * @param recordId Survey to load.
     * @return The survey view, never null for a valid survey id.
     */
    @AuraEnabled(cacheable=true)
    public static SurveyRecordView getSurveyRecordView(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        Ken_Survey__c survey = [
            SELECT Id, Name, Description__c, Approval_Status__c, Is_Active__c,
                   Target_Audience__c, Start_Date__c, End_Date__c, Assessment_Question_Set__c
            FROM Ken_Survey__c WHERE Id = :recordId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        SurveyRecordView view = new SurveyRecordView();
        view.surveyId = survey.Id;
        view.name = survey.Name;
        view.description = survey.Description__c;
        view.approvalStatus = survey.Approval_Status__c;
        view.isActive = survey.Is_Active__c;
        view.targetAudience = survey.Target_Audience__c;
        view.startDate = survey.Start_Date__c;
        view.endDate = survey.End_Date__c;
        view.questionSetId = survey.Assessment_Question_Set__c;
        view.questions = new List<QuestionnaireParameterData>();
        view.submissions = new List<SubmissionView>();

        for (KenAssessmentSurveyService.QuestionRow row :
                KenAssessmentSurveyService.questionsForSet(survey.Assessment_Question_Set__c)) {
            view.questions.add(toParameterData(row));
        }
        view.questionCount = view.questions.size();

        // Only the first page of submissions is loaded, through the same builder the Load more
        // endpoint uses, so the cursor the client pages from is always populated.
        view.submissions = buildSubmissionViews(survey.Id, null, null);

        Map<Id, Integer> respondentCounts = KenAssessmentSurveyService.respondentCountsBySurvey(new Set<Id>{ survey.Id });
        Map<Id, Integer> submissionCounts = KenAssessmentSurveyService.submissionCountsBySurvey(new Set<Id>{ survey.Id });
        view.respondentCount = respondentCounts.containsKey(survey.Id) ? respondentCounts.get(survey.Id) : 0;
        view.totalSubmissions = submissionCounts.containsKey(survey.Id) ? submissionCounts.get(survey.Id) : 0;
        view.shownSubmissions = view.submissions.size();
        return view;
    }

    /**
     * @description Creates or updates a survey without touching its questions.
     * @param request Survey details.
     * @param surveyId Optional id of the survey to update.
     * @return Id of the saved survey.
     */
    @AuraEnabled
    public static Id saveSurveyDraft(SurveySaveRequest request, Id surveyId) {
        try {
            if (request == null) {
                throw new AuraHandledException('No data provided.');
            }
            Id effectiveRoleId = resolveConstituentRoleId();
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }

            String title = String.isNotBlank(request.title) ? request.title.trim() : 'Untitled Survey';
            String description = String.isNotBlank(request.description) ? request.description.trim() : null;
            String audience = joinAudience(request.targetAudience);

            if (surveyId != null) {
                Ken_Survey__c existing = [
                    SELECT Id FROM Ken_Survey__c WHERE Id = :surveyId
                    WITH SECURITY_ENFORCED
                    LIMIT 1 FOR UPDATE
                ];
                existing.Name = title;
                existing.Description__c = description;
                existing.Target_Audience__c = audience;
                existing.Start_Date__c = parseDate(request.startDate, false);
                existing.End_Date__c = parseDate(request.endDate, true);
                if (!Schema.sObjectType.Ken_Survey__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Survey__c is not updateable by the current user.');
                }
                update existing;
                return existing.Id;
            }

            Ken_Survey__c survey = new Ken_Survey__c(
                Name = title,
                Description__c = description,
                Target_Audience__c = audience,
                Start_Date__c = parseDate(request.startDate, false),
                End_Date__c = parseDate(request.endDate, true),
                Approval_Status__c = 'Pending Approval',
                Module__c = MODULE_ALUMNI,
                Constituent_Role__c = effectiveRoleId
            );
            if (!Schema.sObjectType.Ken_Survey__c.isCreateable()) {
                throw new KenCrudException('Ken_Survey__c is not createable by the current user.');
            }
            insert survey;
            return survey.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at ' + e.getLineNumber());
        }
    }

    /**
     * @description Points a survey at a segmentation, replacing whatever audience it had.
     * @param surveyId Survey to link.
     * @param segmentationId Segmentation to link.
     * @return Id of the survey that now carries the audience.
     */
    @AuraEnabled
    public static Id createSurveySegmentation(Id surveyId, Id segmentationId) {
        if (surveyId == null || segmentationId == null) {
            throw new AuraHandledException('Survey Id and Segmentation Id are required.');
        }
        List<Ken_Survey__c> existing = [
            SELECT Id, Segmentation__c FROM Ken_Survey__c WHERE Id = :surveyId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            throw new AuraHandledException('Survey not found.');
        }
        if (existing[0].Segmentation__c != segmentationId) {
            if (!Schema.sObjectType.Ken_Survey__c.isUpdateable()) {
                throw new KenCrudException('Ken_Survey__c is not updateable by the current user.');
            }
            update new Ken_Survey__c(Id = surveyId, Segmentation__c = segmentationId);
        }
        return surveyId;
    }

    /**
     * @description Creates a survey together with its questions.
     * @param request Survey details and questions.
     * @return Id of the new survey.
     */
    @AuraEnabled
    public static Id createSurveyWithQuestions(SurveySaveRequest request) {
        try {
            if (request == null) {
                throw new AuraHandledException('No data provided.');
            }
            Id effectiveRoleId = resolveConstituentRoleId();
            if (effectiveRoleId == null && !isInternalUser()) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }
            if (request.questions == null || request.questions.isEmpty()) {
                throw new AuraHandledException('No questions received from client.');
            }

            String title = String.isNotBlank(request.title) ? request.title.trim() : 'Untitled Survey';
            String description = String.isNotBlank(request.description) ? request.description.trim() : null;
            String audience = joinAudience(request.targetAudience);

            Id questionSetId = KenAssessmentSurveyService.saveQuestionSet(null, title, toQuestionInputs(request.questions)
            );

            Ken_Survey__c survey = new Ken_Survey__c(
                Name = title,
                Description__c = description,
                Target_Audience__c = audience,
                Start_Date__c = parseDate(request.startDate, false),
                End_Date__c = parseDate(request.endDate, true),
                Approval_Status__c = 'Pending Approval',
                Module__c = MODULE_ALUMNI,
                Assessment_Question_Set__c = questionSetId,
                Constituent_Role__c = effectiveRoleId
            );
            if (!Schema.sObjectType.Ken_Survey__c.isCreateable()) {
                throw new KenCrudException('Ken_Survey__c is not createable by the current user.');
            }
            insert survey;
            return survey.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at ' + e.getLineNumber());
        }
    }

    /**
     * @description Updates a survey and replaces its questions.
     * @param request Updated survey details and questions.
     * @param surveyId Survey to update.
     * @return Id of the updated survey.
     */
    @AuraEnabled
    public static Id updateSurveyWithQuestions(SurveySaveRequest request, Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required for update.');
        }
        if (request == null) {
            throw new AuraHandledException('No data provided.');
        }
        Ken_Survey__c survey = [
            SELECT Id, Assessment_Question_Set__c FROM Ken_Survey__c
            WHERE Id = :surveyId
            WITH SECURITY_ENFORCED
            LIMIT 1 FOR UPDATE
        ];

        String title = String.isNotBlank(request.title) ? request.title.trim() : 'Untitled Survey';
        String description = String.isNotBlank(request.description) ? request.description.trim() : null;
        String audience = joinAudience(request.targetAudience);

        survey.Assessment_Question_Set__c = KenAssessmentSurveyService.saveQuestionSet(survey.Assessment_Question_Set__c, title,
            toQuestionInputs(request.questions)
        );
        survey.Name = title;
        survey.Description__c = description;
        survey.Target_Audience__c = audience;
        survey.Start_Date__c = parseDate(request.startDate, false);
        survey.End_Date__c = parseDate(request.endDate, true);
        survey.Approval_Status__c = 'Pending Approval';
        if (!Schema.sObjectType.Ken_Survey__c.isUpdateable()) {
            throw new KenCrudException('Ken_Survey__c is not updateable by the current user.');
        }
        update survey;
        return survey.Id;
    }

    /**
     * @description Approved, active surveys the current user has not authored.
     * @return Survey summaries with their questions.
     */
    @AuraEnabled
    public static List<SurveyData> getSurveys() {
        Id constituentRoleId = resolveConstituentRoleId();
        if (constituentRoleId == null) {
            return new List<SurveyData>();
        }
        return buildSurveyData([
            SELECT Id, Name, Start_Date__c, End_Date__c, Approval_Status__c,
                   Is_Active__c, CreatedDate, CreatedById, Constituent_Role__c,
                   Assessment_Question_Set__c, LastModifiedDate
            FROM Ken_Survey__c
            WHERE Assessment_Question_Set__c != null
            AND Approval_Status__c = 'Approved' AND Is_Active__c = true
            AND (Constituent_Role__c != :constituentRoleId OR Constituent_Role__c = null)
            WITH SECURITY_ENFORCED
            ORDER BY End_Date__c DESC, CreatedDate DESC
        ]);
    }

    /**
     * @description Surveys authored by the current user.
     * @return Survey summaries with their questions.
     */
    @AuraEnabled
    public static List<SurveyData> getMySurveys() {
        Id constituentRoleId = resolveConstituentRoleId();
        if (constituentRoleId == null) {
            return new List<SurveyData>();
        }
        return buildSurveyData([
            SELECT Id, Name, Start_Date__c, End_Date__c, Approval_Status__c,
                   Is_Active__c, CreatedDate, CreatedById, Constituent_Role__c,
                   Assessment_Question_Set__c, LastModifiedDate
            FROM Ken_Survey__c
            WHERE Assessment_Question_Set__c != null
            AND Constituent_Role__c = :constituentRoleId
            WITH SECURITY_ENFORCED
            ORDER BY End_Date__c DESC, CreatedDate DESC
        ]);
    }

    /**
     * @description Records the current user's answers to a survey, or to the survey linked to a
     *              session when answering session feedback.
     * @param request Survey or session id plus the answers.
     */
    @AuraEnabled
    public static void submitSurveyResponses(SurveyResponseRequest request) {
        if (request == null) {
            throw new AuraHandledException('Request is required.');
        }
        if (request.surveyId == null && request.sessionId == null) {
            throw new AuraHandledException('Survey Id or Session Id is required.');
        }

        Id respondentAccountId = fetchCurrentAccountId();
        Boolean isEventFeedback = (request.sessionId != null);
        Id targetSurveyId = request.surveyId;
        if (isEventFeedback) {
            List<Ken_Schedule_Sessions__c> linked = [
                SELECT Id, Survey__c FROM Ken_Schedule_Sessions__c WHERE Id = :request.sessionId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (linked.isEmpty()) {
                throw new AuraHandledException('Session not found.');
            }
            targetSurveyId = linked[0].Survey__c;
            if (targetSurveyId == null) {
                throw new AuraHandledException('No feedback survey is linked to this session.');
            }
        }

        List<KenAssessmentSurveyService.AnswerInput> answers = new List<KenAssessmentSurveyService.AnswerInput>();
        if (request.responses != null) {
            for (QuestionResponse qr : request.responses) {
                if (qr == null || qr.questionId == null || String.isBlank(qr.responseValue)) {
                    continue;
                }
                KenAssessmentSurveyService.AnswerInput answer = new KenAssessmentSurveyService.AnswerInput();
                answer.questionId = qr.questionId;
                answer.value = qr.responseValue;
                answers.add(answer);
            }
        }
        KenAssessmentSurveyService.submitResponses(
            targetSurveyId, respondentAccountId, isEventFeedback ? 'Event' : 'Survey',
            answers
        );
    }

    /**
     * @description Renders a session's feedback survey through the same wrapper the portal uses
     *              for standalone surveys.
     * @param sessionId Session whose linked survey is rendered.
     * @return Survey data for the session.
     */
    @AuraEnabled(cacheable=true)
    public static SurveyData getEventFeedbackAsSurvey(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('Session id is required.');
        }
        List<Ken_Schedule_Sessions__c> sessions = [
            SELECT Id, Name, Event_Reference__c, Event_Reference__r.Name, Survey__c,
                   Survey__r.Assessment_Question_Set__c
            FROM Ken_Schedule_Sessions__c WHERE Id = :sessionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            throw new AuraHandledException('Session not found.');
        }
        Ken_Schedule_Sessions__c session = sessions[0];
        Id setId = session.Survey__r != null ? session.Survey__r.Assessment_Question_Set__c : null;
        if (setId == null) {
            throw new AuraHandledException('No feedback form has been set up for this session.');
        }

        SurveyData data = new SurveyData();
        data.id = session.Id;
        data.name = session.Event_Reference__r != null ? session.Event_Reference__r.Name : session.Name;
        data.questionnaireId = setId;
        data.isActive = true;
        QuestionnaireData qd = new QuestionnaireData();
        qd.parameters = new List<QuestionnaireParameterData>();
        for (KenAssessmentSurveyService.QuestionRow row : KenAssessmentSurveyService.questionsForSet(setId)) {
            qd.parameters.add(toParameterData(row));
        }
        data.questionnaire = qd;
        return data;
    }

    /**
     * @description Loads a survey and its questions for editing.
     * @param surveyId Survey to edit.
     * @return Editable survey data plus its segmentation definition.
     */
    @AuraEnabled(cacheable=false)
    public static SurveyEditResponse getSurveyForEdit(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        Ken_Survey__c survey = [
            SELECT Id, Name, Description__c, Target_Audience__c,
                   Start_Date__c, End_Date__c, Assessment_Question_Set__c
            FROM Ken_Survey__c WHERE Id = :surveyId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        // Stays a JSON array even though a survey now carries at most one audience: the
        // picker still reads a list of definitions.
        String segmentationJson = null;
        if (Schema.sObjectType.Ken_Segmentation__c.isAccessible()) {
            List<String> jsonList = new List<String>();
            for (Ken_Survey__c linked : [
                SELECT Segmentation__r.Definition_JSON__c FROM Ken_Survey__c
                WHERE Id = :surveyId AND Segmentation__c != null
                WITH SECURITY_ENFORCED
                LIMIT 1
            ]) {
                if (linked.Segmentation__r != null && linked.Segmentation__r.Definition_JSON__c != null) {
                    jsonList.add(linked.Segmentation__r.Definition_JSON__c);
                }
            }
            if (!jsonList.isEmpty()) {
                segmentationJson = '[' + String.join(jsonList, ',') + ']';
            }
        }

        SurveySaveRequest dto = new SurveySaveRequest();
        dto.title = survey.Name;
        dto.description = survey.Description__c;
        dto.targetAudience = String.isNotBlank(survey.Target_Audience__c)
            ? survey.Target_Audience__c.split(';') : new List<String>();
        dto.startDate = survey.Start_Date__c != null ? String.valueOf(survey.Start_Date__c.date()) : null;
        dto.endDate = survey.End_Date__c != null ? String.valueOf(survey.End_Date__c.date()) : null;
        dto.questions = new List<QuestionDTO>();

        for (KenAssessmentSurveyService.QuestionRow row :
                KenAssessmentSurveyService.questionsForSet(survey.Assessment_Question_Set__c)) {
            QuestionDTO qdto = new QuestionDTO();
            qdto.id = row.id;
            qdto.text = row.questionLabel;
            qdto.type = mapQuestionTypeForClient(row.questionType);
            qdto.required = row.required;
            qdto.options = toOptionDTOs(row.choices);
            dto.questions.add(qdto);
        }

        SurveyEditResponse resp = new SurveyEditResponse();
        resp.data = dto;
        resp.surveyId = survey.Id;
        resp.segmentationDefinitionJson = segmentationJson;
        return resp;
    }

    /**
     * @description Survey answers pivoted one row per submission, for export.
     * @param surveyId Survey to export.
     * @return Questions and answer rows.
     */
    @AuraEnabled(cacheable=false)
    public static SurveyExportResult getSurveyResponsesForExport(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        Ken_Survey__c survey = [
            SELECT Id, Name, Assessment_Question_Set__c
            FROM Ken_Survey__c WHERE Id = :surveyId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        List<SurveyExportQuestion> questions = new List<SurveyExportQuestion>();
        for (KenAssessmentSurveyService.QuestionRow row :
                KenAssessmentSurveyService.questionsForSet(survey.Assessment_Question_Set__c)) {
            SurveyExportQuestion qdto = new SurveyExportQuestion();
            qdto.id = row.id;
            qdto.label = row.questionLabel;
            qdto.displayOrder = row.displayOrder;
            qdto.questionType = row.questionType;
            questions.add(qdto);
        }

        List<AssessmentQuestionResponse> allAnswers =
            KenAssessmentSurveyService.answersForSurveys(new Set<Id>{ survey.Id });
        Boolean hitRowCap = allAnswers.size() >= KenAssessmentSurveyService.MAX_ANSWER_ROWS;

        Map<Id, SurveyExportRow> rowsByAssessment = new Map<Id, SurveyExportRow>();
        for (AssessmentQuestionResponse answer : allAnswers) {
            Id headerId = answer.Assessment.Id;
            if (!rowsByAssessment.containsKey(headerId)) {
                SurveyExportRow exportRow = new SurveyExportRow();
                exportRow.accountId = answer.Assessment.Respondent__c;
                exportRow.respondentId = answer.Assessment.Respondent__c;
                exportRow.respondentName = answer.Assessment.Respondent__r != null
                    ? answer.Assessment.Respondent__r.Name : null;
                exportRow.submittedAt = answer.Assessment.Submitted_Date__c != null
                    ? answer.Assessment.Submitted_Date__c : answer.CreatedDate;
                exportRow.answersByQuestionId = new Map<String, String>();
                rowsByAssessment.put(headerId, exportRow);
            }
            rowsByAssessment.get(headerId).answersByQuestionId.put(
                String.valueOf(answer.AssessmentQuestionId), answer.ResponseText
            );
        }

        SurveyExportResult result = new SurveyExportResult();
        result.truncated = hitRowCap;
        result.surveyName = survey.Name;
        result.questions = questions;
        result.rows = new List<SurveyExportRow>(rowsByAssessment.values());
        return result;
    }

    /**
     * @description Starts a full export for surveys too large to download in the browser. The
     *              finished CSV is attached to the survey record and the requester is emailed.
     * @param surveyId Survey to export.
     * @return The batch job id.
     */
    @AuraEnabled
    public static Id requestFullExport(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        return Database.executeBatch(new KenSurveyExportBatch(surveyId), 200);
    }

    /**
     * @description Whether a survey's export must be built asynchronously.
     * @param surveyId Survey to check.
     * @return True when the browser export would be incomplete.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean exportNeedsBatch(Id surveyId) {
        if (surveyId == null) {
            return false;
        }
        return [
            SELECT COUNT() FROM AssessmentQuestionResponse WHERE Assessment.Ken_Survey__c = :surveyId
        WITH SECURITY_ENFORCED
        ] >= KenAssessmentSurveyService.MAX_ANSWER_ROWS;
    }

    /**
     * @description Deletes a survey with its questions and submissions.
     * @param surveyId Survey to delete.
     */
    @AuraEnabled
    public static void deleteSurvey(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        if (!Schema.sObjectType.Ken_Survey__c.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete survey records.');
        }
        Ken_Survey__c survey = [
            SELECT Id, Assessment_Question_Set__c FROM Ken_Survey__c WHERE Id = :surveyId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        // A heavily answered survey has more rows than one transaction may delete, so it is
        // purged in chunks instead of failing outright.
        Integer answerRows = [
            SELECT COUNT() FROM AssessmentQuestionResponse WHERE Assessment.Ken_Survey__c = :surveyId
        WITH SECURITY_ENFORCED
        ];
        if (answerRows > INLINE_DELETE_LIMIT && !Test.isRunningTest()) {
            System.enqueueJob(new KenSurveyPurgeQueueable(survey.Id, survey.Assessment_Question_Set__c));
            return;
        }

        KenAssessmentSurveyService.deleteSurveyData(survey.Assessment_Question_Set__c, survey.Id);
        delete survey;
    }

    /**
     * @description Answer distribution per question, counting each respondent's most recent
     *              submission once.
     * @param surveyId Survey to summarise.
     * @return Statistics per question.
     */
    @AuraEnabled(cacheable=true)
    public static List<QuestionStatsDTO> getSurveyResponseStats(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        Map<Id, Map<Id, String>> latestByQuestion = latestAnswersByQuestion(surveyId);

        List<QuestionStatsDTO> result = new List<QuestionStatsDTO>();
        for (Id questionId : latestByQuestion.keySet()) {
            Map<String, Integer> counts = new Map<String, Integer>();
            for (String raw : latestByQuestion.get(questionId).values()) {
                if (String.isBlank(raw)) {
                    continue;
                }
                String key = raw.trim();
                counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
            }
            Integer total = 0;
            for (Integer c : counts.values()) {
                total += c;
            }
            List<ResponseStatDTO> stats = new List<ResponseStatDTO>();
            for (String val : counts.keySet()) {
                Integer c = counts.get(val);
                Decimal pct = (total > 0) ? (Decimal.valueOf(c) * 100) / Decimal.valueOf(total) : 0;
                ResponseStatDTO dto = new ResponseStatDTO();
                dto.responseValue = val;
                dto.count = c;
                dto.percent = pct.setScale(0);
                stats.add(dto);
            }
            QuestionStatsDTO qdto = new QuestionStatsDTO();
            qdto.questionId = questionId;
            qdto.total = total;
            qdto.stats = sortStatsByCountDesc(stats);
            result.add(qdto);
        }
        return result;
    }

    /**
     * @description Number of respondents who answered each question.
     * @param surveyId Survey to summarise.
     * @return Counts per question.
     */
    @AuraEnabled(cacheable=true)
    public static List<ShortAnswerCountDTO> getShortAnswerQuestionCounts(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        List<ShortAnswerCountDTO> out = new List<ShortAnswerCountDTO>();
        Map<Id, Map<Id, String>> latestByQuestion = latestAnswersByQuestion(surveyId);
        for (Id questionId : latestByQuestion.keySet()) {
            Integer total = 0;
            for (String v : latestByQuestion.get(questionId).values()) {
                if (String.isNotBlank(v)) {
                    total++;
                }
            }
            ShortAnswerCountDTO dto = new ShortAnswerCountDTO();
            dto.questionId = questionId;
            dto.total = total;
            out.add(dto);
        }
        return out;
    }

    /**
     * @description Every respondent's latest answer to one question.
     * @param surveyId Survey the question belongs to.
     * @param questionId Question to export.
     * @return Answer rows for that question.
     */
    @AuraEnabled(cacheable=true)
    public static ShortAnswerExportDTO getShortAnswerResponsesForExport(Id surveyId, Id questionId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        if (questionId == null) {
            throw new AuraHandledException('Question Id is required.');
        }
        Map<Id, ShortAnswerRowDTO> latestByRespondent = new Map<Id, ShortAnswerRowDTO>();
        for (AssessmentQuestionResponse answer : KenAssessmentSurveyService.answersForSurveys(new Set<Id>{ surveyId })) {
            if (answer.AssessmentQuestionId != questionId
                || answer.Assessment.Respondent__c == null
                || String.isBlank(answer.ResponseText)
                || latestByRespondent.containsKey(answer.Assessment.Respondent__c)) {
                continue;
            }
            ShortAnswerRowDTO dto = new ShortAnswerRowDTO();
            dto.respondentId = answer.Assessment.Respondent__c;
            dto.respondentName = answer.Assessment.Respondent__r != null
                ? answer.Assessment.Respondent__r.Name : null;
            dto.responseText = answer.ResponseText;
            latestByRespondent.put(dto.respondentId, dto);
        }
        ShortAnswerExportDTO out = new ShortAnswerExportDTO();
        out.questionId = questionId;
        out.rows = new List<ShortAnswerRowDTO>(latestByRespondent.values());
        out.total = out.rows.size();
        return out;
    }

    private static Map<Id, Map<Id, String>> latestAnswersByQuestion(Id surveyId) {
        Map<Id, Map<Id, String>> latestByQuestion = new Map<Id, Map<Id, String>>();
        for (AssessmentQuestionResponse answer : KenAssessmentSurveyService.answersForSurveys(new Set<Id>{ surveyId })) {
            Id questionId = answer.AssessmentQuestionId;
            Id respondentId = answer.Assessment.Respondent__c;
            if (questionId == null || respondentId == null) {
                continue;
            }
            if (!latestByQuestion.containsKey(questionId)) {
                latestByQuestion.put(questionId, new Map<Id, String>());
            }
            Map<Id, String> byRespondent = latestByQuestion.get(questionId);
            if (!byRespondent.containsKey(respondentId)) {
                byRespondent.put(respondentId, answer.ResponseText);
            }
        }
        return latestByQuestion;
    }

    private static List<SurveyData> buildSurveyData(List<Ken_Survey__c> surveys) {
        Set<Id> surveyIds = new Set<Id>();
        Map<Id, Id> questionSetBySurvey = new Map<Id, Id>();
        for (Ken_Survey__c s : surveys) {
            surveyIds.add(s.Id);
            if (s.Assessment_Question_Set__c != null) {
                questionSetBySurvey.put(s.Id, s.Assessment_Question_Set__c);
            }
        }

        Map<Id, List<QuestionnaireParameterData>> paramsBySurvey = new Map<Id, List<QuestionnaireParameterData>>();
        if (!questionSetBySurvey.isEmpty()) {
            Map<Id, List<KenAssessmentSurveyService.QuestionRow>> bySet =
                KenAssessmentSurveyService.questionsBySet(new Set<Id>(questionSetBySurvey.values()));
            for (Id sid : questionSetBySurvey.keySet()) {
                List<KenAssessmentSurveyService.QuestionRow> rows = bySet.get(questionSetBySurvey.get(sid));
                if (rows == null) {
                    continue;
                }
                List<QuestionnaireParameterData> converted = new List<QuestionnaireParameterData>();
                for (KenAssessmentSurveyService.QuestionRow row : rows) {
                    converted.add(toParameterData(row));
                }
                paramsBySurvey.put(sid, converted);
            }
        }

        Map<Id, Integer> totalRespondentCounts = new Map<Id, Integer>();
        Set<Id> answeredByMe = new Set<Id>();
        Map<Id, ProcessInstanceStep> rejectedSteps = new Map<Id, ProcessInstanceStep>();
        Map<Id, String> segmentationNameBySurveyId = new Map<Id, String>();
        if (!surveyIds.isEmpty()) {
            totalRespondentCounts = KenAssessmentSurveyService.respondentCountsBySurvey(surveyIds);
            answeredByMe = KenAssessmentSurveyService.surveysAnsweredBy(surveyIds, fetchCurrentAccountId());

            for (ProcessInstanceStep step : [
                SELECT ProcessInstance.TargetObjectId, Comments, CreatedDate
                FROM ProcessInstanceStep
                WHERE ProcessInstance.TargetObjectId IN :surveyIds AND StepStatus = 'Rejected'
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
            ]) {
                Id targetId = step.ProcessInstance.TargetObjectId;
                if (targetId != null && !rejectedSteps.containsKey(targetId)) {
                    rejectedSteps.put(targetId, step);
                }
            }

            if (Schema.sObjectType.Ken_Segmentation__c.isAccessible()) {
                for (Ken_Survey__c linked : [
                    SELECT Id, Segmentation__r.Name FROM Ken_Survey__c
                    WHERE Id IN :surveyIds AND Segmentation__c != null
                WITH SECURITY_ENFORCED
                ]) {
                    if (linked.Segmentation__r == null) {
                        continue;
                    }
                    segmentationNameBySurveyId.put(linked.Id, linked.Segmentation__r.Name);
                }
            }
        }

        List<SurveyData> response = new List<SurveyData>();
        for (Ken_Survey__c survey : surveys) {
            SurveyData dto = new SurveyData();
            dto.id = survey.Id;
            dto.name = survey.Name;
            dto.startDate = survey.Start_Date__c;
            dto.endDate = survey.End_Date__c;
            dto.fromDate = survey.Start_Date__c;
            dto.toDate = survey.End_Date__c;
            dto.approvalStatus = survey.Approval_Status__c;
            dto.isActive = survey.Is_Active__c;
            dto.segmentationName = segmentationNameBySurveyId.get(survey.Id);
            dto.questionnaireId = survey.Assessment_Question_Set__c;
            dto.submittedDate = survey.CreatedDate;
            dto.createdById = survey.CreatedById;
            dto.createdByAccountId = survey.Constituent_Role__c;
            dto.hasResponses = answeredByMe.contains(survey.Id);
            if (totalRespondentCounts.containsKey(survey.Id)) {
                dto.responsesCount = totalRespondentCounts.get(survey.Id);
            }
            if (rejectedSteps.containsKey(survey.Id)) {
                ProcessInstanceStep step = rejectedSteps.get(survey.Id);
                dto.rejectedDate = step.CreatedDate;
                dto.rejectionComments = step.Comments;
            }
            if (paramsBySurvey.containsKey(survey.Id)) {
                QuestionnaireData qd = new QuestionnaireData();
                qd.parameters = paramsBySurvey.get(survey.Id);
                dto.questionnaire = qd;
            }
            response.add(dto);
        }
        return response;
    }

    private static QuestionnaireParameterData toParameterData(KenAssessmentSurveyService.QuestionRow row) {
        QuestionnaireParameterData qd = new QuestionnaireParameterData();
        qd.id = row.id;
        qd.questionType = row.questionType;
        qd.questionLabel = row.questionLabel;
        qd.options = toOptionDTOs(row.choices);
        qd.displayOrder = row.displayOrder;
        qd.required = row.required;
        return qd;
    }

    private static List<QuestionOptionDTO> toOptionDTOs(List<KenAssessmentSurveyService.ChoiceRow> choices) {
        List<QuestionOptionDTO> options = new List<QuestionOptionDTO>();
        if (choices == null) {
            return options;
        }
        for (KenAssessmentSurveyService.ChoiceRow c : choices) {
            QuestionOptionDTO o = new QuestionOptionDTO();
            o.value = c.value;
            o.text = String.isNotBlank(c.label) ? c.label : c.value;
            options.add(o);
        }
        return options;
    }

    private static List<KenAssessmentSurveyService.QuestionInput> toQuestionInputs(List<QuestionDTO> dtos) {
        List<KenAssessmentSurveyService.QuestionInput> inputs = new List<KenAssessmentSurveyService.QuestionInput>();
        if (dtos == null) {
            return inputs;
        }
        for (QuestionDTO dto : dtos) {
            if (dto == null) {
                continue;
            }
            KenAssessmentSurveyService.QuestionInput input = new KenAssessmentSurveyService.QuestionInput();
            input.text = dto.text;
            input.questionType = mapQuestionType(dto.type);
            input.required = dto.required == true;
            input.choices = new List<KenAssessmentSurveyService.ChoiceRow>();
            if (dto.options != null) {
                for (QuestionOptionDTO o : dto.options) {
                    if (o == null || (String.isBlank(o.value) && String.isBlank(o.text))) {
                        continue;
                    }
                    KenAssessmentSurveyService.ChoiceRow c = new KenAssessmentSurveyService.ChoiceRow();
                    c.value = String.isNotBlank(o.value) ? o.value : o.text;
                    c.label = String.isNotBlank(o.text) ? o.text : o.value;
                    input.choices.add(c);
                }
            }
            inputs.add(input);
        }
        return inputs;
    }

    private static List<ResponseStatDTO> sortStatsByCountDesc(List<ResponseStatDTO> input) {
        if (input == null || input.size() <= 1) {
            return input;
        }
        List<ResponseStatDTO> a = new List<ResponseStatDTO>();
        a.addAll(input);
        for (Integer i = 0; i < a.size(); i++) {
            for (Integer j = i + 1; j < a.size(); j++) {
                Integer ci = a[i].count == null ? 0 : a[i].count;
                Integer cj = a[j].count == null ? 0 : a[j].count;
                if (cj > ci) {
                    ResponseStatDTO tmp = a[i];
                    a[i] = a[j];
                    a[j] = tmp;
                }
            }
        }
        return a;
    }

    private static Id resolveConstituentRoleId() {
        return KenConstituentRoleService.getActiveConstituentRoleId();
    }

    private static Boolean isInternalUser() {
        User u = [SELECT Id, UserType, AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        // Standard / internal users have UserType = 'Standard' and a null AccountId.
        return u.AccountId == null || u.UserType == 'Standard';
    }

    private static Id fetchCurrentAccountId() {
        User u = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        return u.AccountId;
    }

    private static String joinAudience(List<String> audience) {
        return (audience == null || audience.isEmpty()) ? null : String.join(audience, ';');
    }

    private static String mapQuestionType(String typeValue) {
        if (String.isBlank(typeValue)) {
            return null;
        }
        String normalized = typeValue.toLowerCase();
        // Single Select stores as Dropdown (pick exactly one) and Checkbox as Multiple Choice
        // (multi-select); this mapping is the only place that distinction lives.
        if (normalized == 'multiple') {
            return 'Dropdown';
        }
        if (normalized == 'checkbox') {
            return 'Multiple Choice';
        }
        if (normalized == 'linear') {
            return 'Linear Scale';
        }
        if (normalized == 'short' || normalized == 'text') {
            return 'Short Answer';
        }
        return typeValue;
    }

    private static String mapQuestionTypeForClient(String typeValue) {
        if (String.isBlank(typeValue)) {
            return 'short';
        }
        String normalized = typeValue.toLowerCase();
        if (normalized == 'dropdown') {
            return 'multiple';
        }
        if (normalized.contains('multiple') || normalized.contains('checkbox')) {
            return 'checkbox';
        }
        if (normalized.contains('linear') || normalized.contains('rating')) {
            return 'linear';
        }
        return 'short';
    }

    private static Datetime parseDate(String dateValue, Boolean endOfDay) {
        if (String.isBlank(dateValue)) {
            return null;
        }
        try {
            if (dateValue.length() > 10) {
                return Datetime.valueOf(dateValue.replace('T', ' '));
            }
            Date d = Date.valueOf(dateValue);
            // Org-local day boundaries: storing GMT midnight shifted the boundary by the org's
            // UTC offset, so a survey starting today read as Upcoming until 05:30 IST.
            Time t = endOfDay == true
                ? Time.newInstance(23, 59, 59, 0)
                : Time.newInstance(0, 0, 0, 0);
            return Datetime.newInstance(d, t);
        } catch (Exception e) {
            return null;
        }
    }
}