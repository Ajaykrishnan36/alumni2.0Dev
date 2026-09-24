/**
 * @description Survey persistence on the standard Assessment object family.
 *
 *              Ken_Survey__c is the header and Ken_Survey__c.Assessment_Question_Set__c points
 *              at the questions:
 *                survey questions -> AssessmentQuestionSet
 *                one question      -> AssessmentQuestion + AssessmentQuestionVersion
 *                                     (order and required live on the question)
 *                one submission    -> Assessment (carries survey, respondent, category)
 *                one answer        -> AssessmentQuestionResponse
 *
 *              The question id exposed to the client is the AssessmentQuestionVersion id,
 *              because that is what an answer points at.
 *
 *              Choices live in the standard AssessmentQuestionVersion.ResponseValues as a
 *              semicolon-joined list. A linear scale is stored the same way, with each point
 *              carrying its own label as "value:label" - there are no separate scale fields.
 *              AssessmentQstnVerChoice2 is unused: it cannot be referenced from Apex, and
 *              Customer Community Plus Login cannot hold permissions on it.
 *
 *              Runs without sharing deliberately: the Assessment family is Private internally
 *              and externally and community users get no sharing rules, so a portal user cannot
 *              otherwise read the question version their own answer references. Callers are
 *              already-authenticated controllers that scope each request to the caller's own
 *              survey or account.
 */
public without sharing class KenAssessmentSurveyService {

    public static final String MODULE_TAG = 'Alumni';

    /**
     * Headroom under the 50,000 row SOQL ceiling. A survey answered by tens of thousands of
     * people would otherwise take the whole page down rather than degrade.
     */
    public static final Integer MAX_ANSWER_ROWS = 40000;

    private static final String CHOICE_DELIMITER = ';';
    private static final String LABEL_DELIMITER = ':';

    /**
     * @description One selectable choice. For a linear scale the value is the point (1, 2, 3 â€¦)
     *              and the label is that point's wording; for a plain choice the label is the
     *              value.
     */
    public class ChoiceRow {
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String label { get; set; }
    }

    /**
     * @description One question as the portal and admin UIs consume it.
     */
    public class QuestionRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String questionType { get; set; }
        @AuraEnabled public String questionLabel { get; set; }
        @AuraEnabled public List<ChoiceRow> choices { get; set; }
        @AuraEnabled public Decimal displayOrder { get; set; }
        @AuraEnabled public Boolean required { get; set; }
    }

    /**
     * @description One question being saved.
     */
    public class QuestionInput {
        public String text;
        public String questionType;
        public Boolean required;
        public List<ChoiceRow> choices;
    }

    /**
     * @description One answer within a submission.
     */
    public class AnswerInput {
        public Id questionId;
        public String value;
    }

    /**
     * @description Loads the questions of one or more question sets, in display order.
     * @param questionSetIds Question sets to load.
     * @return Map of question set id to its ordered questions.
     */
    public static Map<Id, List<QuestionRow>> questionsBySet(Set<Id> questionSetIds) {
        Map<Id, List<QuestionRow>> result = new Map<Id, List<QuestionRow>>();
        if (questionSetIds == null || questionSetIds.isEmpty()) {
            return result;
        }
        for (AssessmentQuestionVersion v : [
            SELECT Id, QuestionText, ResponseValues, Ken_Question_Type__c,
                   AssessmentQuestion.Ken_Question_Set__c,
                   AssessmentQuestion.Display_Order__c,
                   AssessmentQuestion.Is_Required__c
            FROM AssessmentQuestionVersion
            WHERE AssessmentQuestion.Ken_Question_Set__c IN :questionSetIds
            AND IsActive = true
            WITH SECURITY_ENFORCED
            ORDER BY AssessmentQuestion.Display_Order__c ASC NULLS LAST, CreatedDate ASC
        ]) {
            Id setId = v.AssessmentQuestion.Ken_Question_Set__c;
            if (!result.containsKey(setId)) {
                result.put(setId, new List<QuestionRow>());
            }
            QuestionRow row = new QuestionRow();
            row.id = v.Id;
            row.questionLabel = v.QuestionText;
            row.questionType = v.Ken_Question_Type__c;
            row.choices = parseChoices(v.ResponseValues);
            row.displayOrder = v.AssessmentQuestion.Display_Order__c;
            row.required = v.AssessmentQuestion.Is_Required__c;
            result.get(setId).add(row);
        }
        return result;
    }

    /**
     * @description Loads one question set's questions.
     * @param questionSetId Question set to load.
     * @return Ordered questions, empty when the set has none.
     */
    public static List<QuestionRow> questionsForSet(Id questionSetId) {
        if (questionSetId == null) {
            return new List<QuestionRow>();
        }
        List<QuestionRow> rows = questionsBySet(new Set<Id>{ questionSetId }).get(questionSetId);
        return rows == null ? new List<QuestionRow>() : rows;
    }

    /**
     * @description Writes a question set and its questions, replacing whatever the set held.
     *              Superseded questions are archived rather than deleted, so answers already
     *              given keep resolving to the wording they were answered against.
     * @param existingSetId Set to rewrite, or null to create one.
     * @param title Survey title.
     * @param questions Questions in display order.
     * @return Id of the saved question set.
     */
    public static Id saveQuestionSet(Id existingSetId, String title, List<QuestionInput> questions) {
        String safeTitle = String.isNotBlank(title) ? title.trim() : 'Untitled Survey';
        AssessmentQuestionSet qSet;
        if (existingSetId != null) {
            qSet = [
                SELECT Id, Name
                FROM AssessmentQuestionSet WHERE Id = :existingSetId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            qSet.Name = truncate(safeTitle, 80);
            if (!Schema.sObjectType.AssessmentQuestionSet.isUpdateable()) {
                throw new KenCrudException('AssessmentQuestionSet is not updateable by the current user.');
            }
            update qSet;
            retireQuestions(qSet.Id);
        } else {
            qSet = new AssessmentQuestionSet(
                Name = truncate(safeTitle, 80),
                DeveloperName = buildDeveloperName(safeTitle),
                Ken_Module__c = MODULE_TAG
            );
            if (!Schema.sObjectType.AssessmentQuestionSet.isCreateable()) {
                throw new KenCrudException('AssessmentQuestionSet is not createable by the current user.');
            }
            insert qSet;
        }

        List<QuestionInput> clean = new List<QuestionInput>();
        if (questions != null) {
            for (QuestionInput q : questions) {
                if (q != null) {
                    clean.add(q);
                }
            }
        }
        if (clean.isEmpty()) {
            return qSet.Id;
        }

        List<AssessmentQuestion> newQuestions = new List<AssessmentQuestion>();
        for (Integer i = 0; i < clean.size(); i++) {
            newQuestions.add(new AssessmentQuestion(
                Name = truncate(blankToPlaceholder(clean[i].text), 80),
                DeveloperName = buildDeveloperName(safeTitle + '_q' + i),
                DataType = standardDataType(clean[i].questionType),
                QuestionCategory = 'Demographic',
                Ken_Question_Set__c = qSet.Id,
                Display_Order__c = i + 1,
                Is_Required__c = clean[i].required == true
            ));
        }
        if (!Schema.sObjectType.AssessmentQuestion.isCreateable()) {
            throw new KenCrudException('AssessmentQuestion is not createable by the current user.');
        }
        insert newQuestions;

        List<AssessmentQuestionVersion> versions = new List<AssessmentQuestionVersion>();
        for (Integer i = 0; i < clean.size(); i++) {
            String encoded = encodeChoices(clean[i].choices);
            versions.add(new AssessmentQuestionVersion(
                Name = truncate(blankToPlaceholder(clean[i].text), 80),
                AssessmentQuestionId = newQuestions[i].Id,
                QuestionText = blankToPlaceholder(clean[i].text),
                ResponseValues = encoded,
                IsOptionSourceResponseValue = String.isNotBlank(encoded),
                IsActive = true,
                Ken_Question_Type__c = clean[i].questionType
            ));
        }
        if (!Schema.sObjectType.AssessmentQuestionVersion.isCreateable()) {
            throw new KenCrudException('AssessmentQuestionVersion is not createable by the current user.');
        }
        insert versions;
        return qSet.Id;
    }

    /**
     * @description Records one submission: a header plus one row per answer. A submission with
     *              no answers still records the header, so the portal can show the survey as done.
     * @param surveyId Survey being answered.
     * @param respondentAccountId Person Account of the respondent.
     * @param category Survey, Event or Feedback.
     * @param answers Answers keyed by question version id.
     * @return Id of the submission header.
     */
    public static Id submitResponses(Id surveyId, Id respondentAccountId, String category, List<AnswerInput> answers) {
        Ken_Survey__c survey = [SELECT Id, Name FROM Ken_Survey__c WHERE Id = :surveyId WITH SECURITY_ENFORCED LIMIT 1];

        Assessment header = new Assessment(
            Name = truncate(String.isNotBlank(survey.Name) ? survey.Name : 'Survey Submission', 80),
            AssessmentStatus = 'Completed',
            Ken_Survey__c = survey.Id,
            Respondent__c = respondentAccountId,
            Response_Category__c = category,
            Submitted_Date__c = System.now(),
            Ken_Module__c = MODULE_TAG,
            EffectiveDateTime = System.now()
        );
        if (!Schema.sObjectType.Assessment.isCreateable()) {
            throw new KenCrudException('Assessment is not createable by the current user.');
        }
        insert header;

        if (answers == null || answers.isEmpty()) {
            return header.Id;
        }

        Set<Id> versionIds = new Set<Id>();
        for (AnswerInput a : answers) {
            if (a != null && a.questionId != null) {
                versionIds.add(a.questionId);
            }
        }
        Map<Id, AssessmentQuestionVersion> versionsById = new Map<Id, AssessmentQuestionVersion>([
            SELECT Id, QuestionText FROM AssessmentQuestionVersion WHERE Id IN :versionIds
        WITH SECURITY_ENFORCED
        ]);

        List<AssessmentQuestionResponse> rows = new List<AssessmentQuestionResponse>();
        for (AnswerInput a : answers) {
            if (a == null || a.questionId == null || !versionsById.containsKey(a.questionId)) {
                continue;
            }
            AssessmentQuestionVersion version = versionsById.get(a.questionId);
            rows.add(new AssessmentQuestionResponse(
                Name = truncate(blankToPlaceholder(version.QuestionText), 80),
                AssessmentId = header.Id,
                AssessmentQuestionId = a.questionId,
                ResponseText = a.value,
                Question_Label__c = truncate(version.QuestionText, 255),
                Response_Category__c = category
            ));
        }
        if (!rows.isEmpty()) {
            if (!Schema.sObjectType.AssessmentQuestionResponse.isCreateable()) {
                throw new KenCrudException('AssessmentQuestionResponse is not createable by the current user.');
            }
            insert rows;
        }
        return header.Id;
    }

    /**
     * @description Counts distinct respondents per survey.
     * @param surveyIds Surveys to count.
     * @return Map of survey id to respondent count.
     */
    public static Map<Id, Integer> respondentCountsBySurvey(Set<Id> surveyIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (surveyIds == null || surveyIds.isEmpty()) {
            return result;
        }
        for (AggregateResult ar : [
            SELECT Ken_Survey__c sid, COUNT_DISTINCT(Respondent__c) cnt
            FROM Assessment WHERE Ken_Survey__c IN :surveyIds
            WITH SECURITY_ENFORCED
            GROUP BY Ken_Survey__c
        ]) {
            result.put((Id) ar.get('sid'), (Integer) ar.get('cnt'));
        }
        return result;
    }

    /**
     * @description Counts submissions per survey, including repeat submissions.
     * @param surveyIds Surveys to count.
     * @return Map of survey id to submission count.
     */
    public static Map<Id, Integer> submissionCountsBySurvey(Set<Id> surveyIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (surveyIds == null || surveyIds.isEmpty()) {
            return result;
        }
        for (AggregateResult ar : [
            SELECT Ken_Survey__c sid, COUNT(Id) cnt
            FROM Assessment WHERE Ken_Survey__c IN :surveyIds
            WITH SECURITY_ENFORCED
            GROUP BY Ken_Survey__c
        ]) {
            result.put((Id) ar.get('sid'), (Integer) ar.get('cnt'));
        }
        return result;
    }

    /**
     * @description Reports which of the given surveys a respondent has already submitted.
     * @param surveyIds Surveys to check.
     * @param respondentAccountId Person Account of the respondent.
     * @return Survey ids already answered by that respondent.
     */
    public static Set<Id> surveysAnsweredBy(Set<Id> surveyIds, Id respondentAccountId) {
        Set<Id> answered = new Set<Id>();
        if (surveyIds == null || surveyIds.isEmpty() || respondentAccountId == null) {
            return answered;
        }
        for (Assessment a : [
            SELECT Ken_Survey__c FROM Assessment
            WHERE Ken_Survey__c IN :surveyIds AND Respondent__c = :respondentAccountId
        WITH SECURITY_ENFORCED
        ]) {
            answered.add(a.Ken_Survey__c);
        }
        return answered;
    }

    /**
     * @description Counts questions per question set.
     * @param questionSetIds Question sets to count.
     * @return Map of question set id to question count.
     */
    public static Map<Id, Integer> questionCountsBySet(Set<Id> questionSetIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (questionSetIds == null || questionSetIds.isEmpty()) {
            return result;
        }
        for (AggregateResult ar : [
            SELECT Ken_Question_Set__c sid, COUNT(Id) cnt
            FROM AssessmentQuestion
            WHERE Ken_Question_Set__c IN :questionSetIds
            WITH SECURITY_ENFORCED
            GROUP BY Ken_Question_Set__c
        ]) {
            result.put((Id) ar.get('sid'), (Integer) ar.get('cnt'));
        }
        return result;
    }

    /**
     * @description Loads every submitted answer for a set of surveys, newest submission first.
     * @param surveyIds Surveys whose answers to load.
     * @return Answer rows with their submission header.
     */
    public static List<AssessmentQuestionResponse> answersForSurveys(Set<Id> surveyIds) {
        if (surveyIds == null || surveyIds.isEmpty()) {
            return new List<AssessmentQuestionResponse>();
        }
        return [
            SELECT Id, ResponseText, Question_Label__c, AssessmentQuestionId, CreatedDate,
                   Assessment.Id, Assessment.Ken_Survey__c, Assessment.Respondent__c,
                   Assessment.Respondent__r.Name, Assessment.Submitted_Date__c,
                   Assessment.Response_Category__c
            FROM AssessmentQuestionResponse
            WHERE Assessment.Ken_Survey__c IN :surveyIds
            WITH SECURITY_ENFORCED
            ORDER BY Assessment.Submitted_Date__c DESC, CreatedDate DESC
            LIMIT :MAX_ANSWER_ROWS
        ];
    }

    /**
     * @description One page of submissions, newest first.
     *
     *              Paging walks a cursor rather than using OFFSET, which Salesforce caps at
     *              2,000 rows — so a survey with any number of responses can be paged all the
     *              way through. CreatedDate is the cursor because it is always populated and
     *              strictly ordered, with Id breaking ties between same-instant rows.
     * @param surveyId Survey to read.
     * @param cursorDate CreatedDate of the last row on the previous page, or null to start.
     * @param cursorId Id of the last row on the previous page, or null to start.
     * @param pageSize How many submissions to return.
     * @return Submission headers, newest first.
     */
    public static List<Assessment> submissionsPage(Id surveyId, Datetime cursorDate, Id cursorId, Integer pageSize) {
        if (surveyId == null) {
            return new List<Assessment>();
        }
        Integer cap = (pageSize == null || pageSize <= 0) ? 25 : pageSize;
        if (cursorDate == null || cursorId == null) {
            return [
                SELECT Id, Respondent__c, Respondent__r.Name, Submitted_Date__c, CreatedDate
                FROM Assessment
                WHERE Ken_Survey__c = :surveyId
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC, Id DESC
                LIMIT :cap
            ];
        }
        return [
            SELECT Id, Respondent__c, Respondent__r.Name, Submitted_Date__c, CreatedDate
            FROM Assessment
            WHERE Ken_Survey__c = :surveyId
            AND (CreatedDate < :cursorDate OR (CreatedDate = :cursorDate AND Id < :cursorId))
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT :cap
        ];
    }

    /**
     * @description Answers belonging to a known set of submissions. Bounding the submissions
     *              first keeps the row count predictable however many people have responded.
     * @param assessmentIds Submissions whose answers to load.
     * @return Answer rows for those submissions.
     */
    public static List<AssessmentQuestionResponse> answersForSubmissions(Set<Id> assessmentIds) {
        if (assessmentIds == null || assessmentIds.isEmpty()) {
            return new List<AssessmentQuestionResponse>();
        }
        return [
            SELECT Id, ResponseText, Question_Label__c, AssessmentQuestionId, CreatedDate,
                   Assessment.Id, Assessment.Ken_Survey__c, Assessment.Respondent__c,
                   Assessment.Respondent__r.Name, Assessment.Submitted_Date__c
            FROM AssessmentQuestionResponse
            WHERE AssessmentId IN :assessmentIds
            WITH SECURITY_ENFORCED
            ORDER BY Assessment.Submitted_Date__c DESC, CreatedDate DESC
            LIMIT :MAX_ANSWER_ROWS
        ];
    }

    /**
     * @description Removes a survey's submissions and retires its question set. Question and
     *              version records are archived, not deleted: Salesforce refuses to delete a
     *              version that was ever published.
     * @param questionSetId Question set to retire.
     * @param surveyId Survey whose submissions to remove.
     */
    public static void deleteSurveyData(Id questionSetId, Id surveyId) {
        if (surveyId != null) {
            List<Assessment> headers = [SELECT Id FROM Assessment WHERE Ken_Survey__c = :surveyId WITH SECURITY_ENFORCED];
            if (!headers.isEmpty()) {
                delete [SELECT Id FROM AssessmentQuestionResponse WHERE AssessmentId IN :headers WITH SECURITY_ENFORCED];
                if (!Schema.sObjectType.Assessment.isDeletable()) {
                    throw new KenCrudException('Assessment is not deletable by the current user.');
                }
                delete headers;
            }
        }
        if (questionSetId == null) {
            return;
        }
        retireQuestions(questionSetId);
        delete [SELECT Id FROM AssessmentQuestionSet WHERE Id = :questionSetId WITH SECURITY_ENFORCED];
    }

    /**
     * @description Encodes choices into the semicolon-joined form stored in ResponseValues.
     *              A choice whose label differs from its value is written as "value:label", so a
     *              linear scale keeps a wording per point without needing its own fields.
     * @param choices Choices in display order.
     * @return Encoded string, or null when there are none.
     */
    public static String encodeChoices(List<ChoiceRow> choices) {
        if (choices == null || choices.isEmpty()) {
            return null;
        }
        List<String> parts = new List<String>();
        for (ChoiceRow c : choices) {
            if (c == null || String.isBlank(c.value)) {
                continue;
            }
            String value = c.value.trim().replace(CHOICE_DELIMITER, ',').replace(LABEL_DELIMITER, ' ');
            if (String.isBlank(c.label) || c.label.trim() == value) {
                parts.add(value);
            } else {
                parts.add(value + LABEL_DELIMITER + c.label.trim().replace(CHOICE_DELIMITER, ','));
            }
        }
        return parts.isEmpty() ? null : String.join(parts, CHOICE_DELIMITER);
    }

    /**
     * @description Decodes stored choices. Accepts the historic comma and newline separators as
     *              well, so a set authored before this encoding still renders.
     * @param stored Raw ResponseValues content.
     * @return Choices in display order, never null.
     */
    public static List<ChoiceRow> parseChoices(String stored) {
        List<ChoiceRow> choices = new List<ChoiceRow>();
        if (String.isBlank(stored)) {
            return choices;
        }
        for (String raw : stored.split('[;\\n]+')) {
            if (String.isBlank(raw)) {
                continue;
            }
            String part = raw.trim();
            ChoiceRow c = new ChoiceRow();
            Integer split = part.indexOf(LABEL_DELIMITER);
            if (split > 0 && split < part.length() - 1) {
                c.value = part.substring(0, split).trim();
                c.label = part.substring(split + 1).trim();
            } else {
                c.value = part;
                c.label = part;
            }
            choices.add(c);
        }
        return choices;
    }

    /**
     * @description Retires the questions currently in a set: their versions are archived, and
     *              the questions are unlinked from the set so they stop being rendered. Nothing
     *              is deleted, because Salesforce refuses to delete a published version and
     *              historical answers still point at it.
     * @param questionSetId Question set being rewritten.
     */
    private static void retireQuestions(Id questionSetId) {
        List<AssessmentQuestion> existing = [
            SELECT Id, Ken_Question_Set__c FROM AssessmentQuestion
            WHERE Ken_Question_Set__c = :questionSetId
        WITH SECURITY_ENFORCED
        ];
        if (existing.isEmpty()) {
            return;
        }
        List<AssessmentQuestionVersion> versions = [
            SELECT Id, IsActive FROM AssessmentQuestionVersion
            WHERE AssessmentQuestionId IN :existing AND IsActive = true
        WITH SECURITY_ENFORCED
        ];
        if (!versions.isEmpty()) {
            for (AssessmentQuestionVersion v : versions) {
                v.IsActive = false;
            }
            if (!Schema.sObjectType.AssessmentQuestionVersion.isUpdateable()) {
                throw new KenCrudException('AssessmentQuestionVersion is not updateable by the current user.');
            }
            update versions;
        }
        for (AssessmentQuestion q : existing) {
            q.Ken_Question_Set__c = null;
        }
        if (!Schema.sObjectType.AssessmentQuestion.isUpdateable()) {
            throw new KenCrudException('AssessmentQuestion is not updateable by the current user.');
        }
        update existing;
    }

    private static String standardDataType(String kenType) {
        String t = String.isBlank(kenType) ? '' : kenType.toLowerCase();
        if (t.contains('multiple') || t.contains('checkbox')) {
            return 'Multiselect';
        }
        if (t.contains('dropdown') || t.contains('select')) {
            return 'Select';
        }
        if (t.contains('yes')) {
            return 'Radio';
        }
        if (t.contains('linear') || t.contains('rating')) {
            return 'Integer';
        }
        if (t.contains('file')) {
            return 'File';
        }
        if (t.contains('comment')) {
            return 'TextArea';
        }
        return 'Text';
    }

    private static String buildDeveloperName(String seed) {
        String base = String.isBlank(seed) ? 'Ken_Survey' : seed;
        base = base.replaceAll('[^a-zA-Z0-9]+', '_').replaceAll('^_+|_+$', '');
        if (String.isBlank(base)) {
            base = 'Ken_Survey';
        }
        if (!base.substring(0, 1).isAlpha()) {
            base = 'K' + base;
        }
        String suffix = '_' + String.valueOf(System.currentTimeMillis())
            + '_' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(6);
        Integer room = 80 - suffix.length();
        if (base.length() > room) {
            base = base.substring(0, room);
        }
        return base + suffix;
    }

    private static String blankToPlaceholder(String value) {
        return String.isNotBlank(value) ? value : 'Untitled question';
    }

    private static String truncate(String value, Integer max) {
        if (String.isBlank(value)) {
            return value;
        }
        return value.length() > max ? value.substring(0, max) : value;
    }
}