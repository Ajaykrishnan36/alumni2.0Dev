/**
 * @description Builds the complete response export for a survey and attaches it to the survey
 *              record as a CSV file.
 *
 *              The synchronous export is bounded by the SOQL row ceiling, so a survey answered
 *              by tens of thousands of people cannot be exported in one transaction. This walks
 *              the submissions in batches instead: each batch reads only its own submissions'
 *              answers, so the row cost per batch is fixed no matter how large the survey is.
 *              One CSV line is produced per submission, which keeps the accumulated file far
 *              smaller than the answer count suggests.
 */
public without sharing class KenSurveyExportBatch implements Database.Batchable<SObject>, Database.Stateful {

    /**
     * Heap ceiling at which the rows gathered so far are written out as their own file. The
     * asynchronous limit is 12MB, and joining the rows and converting them to a blob each hold
     * a second and third copy, so the accumulated text has to stay well under a third of it.
     */
    private static final Integer HEAP_FLUSH_BYTES = 3000000;

    private final Id surveyId;
    private final String surveyName;
    private final Id notifyUserId;
    private final String stamp;
    private final List<Id> questionIds = new List<Id>();
    private final String headerLine;
    private List<String> lines = new List<String>();
    private final List<String> fileNames = new List<String>();
    private final List<Id> fileIds = new List<Id>();
    private Integer partNumber = 1;
    private Integer totalRows = 0;

    public KenSurveyExportBatch(Id surveyId) {
        this.surveyId = surveyId;
        this.notifyUserId = UserInfo.getUserId();
        this.stamp = Datetime.now().format('yyyyMMdd-HHmm');

        Ken_Survey__c survey = [
            SELECT Id, Name, Assessment_Question_Set__c
            FROM Ken_Survey__c WHERE Id = :surveyId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        this.surveyName = survey.Name;

        List<String> header = new List<String>{ 'Respondent', 'Submitted' };
        for (KenAssessmentSurveyService.QuestionRow row
                : KenAssessmentSurveyService.questionsForSet(survey.Assessment_Question_Set__c)) {
            questionIds.add(row.id);
            header.add(row.questionLabel);
        }
        this.headerLine = toCsvLine(header);
        lines.add(headerLine);
    }

    /**
     * @description Selects every submission for the survey, newest first.
     * @param context Batch context.
     * @return Query locator over the survey's submissions.
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        Id target = surveyId;
        return Database.getQueryLocator([
            SELECT Id, Respondent__r.Name, Submitted_Date__c, CreatedDate
            FROM Assessment
            WHERE Ken_Survey__c = :target
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ]);
    }

    /**
     * @description Writes one CSV line per submission in the batch.
     * @param context Batch context.
     * @param scope Submissions in this batch.
     */
    public void execute(Database.BatchableContext context, List<Assessment> scope) {
        Map<Id, Assessment> byId = new Map<Id, Assessment>(scope);
        Map<Id, Map<Id, String>> answersBySubmission = new Map<Id, Map<Id, String>>();
        for (Id submissionId : byId.keySet()) {
            answersBySubmission.put(submissionId, new Map<Id, String>());
        }
        for (AssessmentQuestionResponse answer : [
            SELECT AssessmentId, AssessmentQuestionId, ResponseText
            FROM AssessmentQuestionResponse
            WHERE AssessmentId IN :byId.keySet()
        WITH SECURITY_ENFORCED
        ]) {
            answersBySubmission.get(answer.AssessmentId).put(answer.AssessmentQuestionId, answer.ResponseText);
        }

        for (Assessment submission : scope) {
            List<String> cells = new List<String>();
            cells.add(submission.Respondent__r != null ? submission.Respondent__r.Name : 'Anonymous');
            Datetime submitted = submission.Submitted_Date__c != null
                ? submission.Submitted_Date__c : submission.CreatedDate;
            cells.add(submitted == null ? '' : submitted.format('yyyy-MM-dd'));
            Map<Id, String> answers = answersBySubmission.get(submission.Id);
            for (Id questionId : questionIds) {
                String value = answers.get(questionId);
                cells.add(value == null ? '' : value);
            }
            lines.add(toCsvLine(cells));
            totalRows++;
        }

        // A survey with tens of thousands of responses cannot be held in one file's worth of
        // heap, so the rows gathered so far are written out and the buffer starts again. Every
        // response still reaches a file; the export is split, never trimmed.
        if (Limits.getHeapSize() > HEAP_FLUSH_BYTES) {
            writeFile(true);
        }
    }

    /**
     * @description Saves whatever rows remain and notifies the requester.
     * @param context Batch context.
     */
    public void finish(Database.BatchableContext context) {
        if (lines.size() > 1 || fileNames.isEmpty()) {
            writeFile(false);
        }
        // A lone file numbered "part 1" reads as though the rest is missing, so once the run is
        // over and no second part exists, the numbering comes back off.
        if (fileNames.size() == 1 && fileNames[0].contains('-part-1.csv')) {
            String plainName = fileNames[0].replace('-part-1.csv', '.csv');
            ContentVersion saved = [
                SELECT ContentDocumentId FROM ContentVersion WHERE Id = :fileIds[0]
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            update new ContentDocument(Id = saved.ContentDocumentId, Title = plainName);
            fileNames[0] = plainName;
        }

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(notifyUserId);
        mail.setSaveAsActivity(false);
        mail.setSubject('Survey export ready: ' + surveyName);
        mail.setPlainTextBody(
            'The full response export for "' + surveyName + '" is ready.\n\n'
            + totalRows + ' responses were exported.\n\n'
            + (fileNames.size() == 1
                ? 'The file "' + fileNames[0] + '" is attached to the survey record under Files.'
                : 'The export was split across ' + fileNames.size() + ' files, all attached to the '
                    + 'survey record under Files:\n  ' + String.join(fileNames, '\n  '))
        );
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            // The files are already saved; a blocked email must not fail the export.
            System.debug(LoggingLevel.WARN, 'Export notification not sent: ' + e.getMessage());
        }
    }

    /**
     * @description Writes the buffered rows to a CSV attached to the survey and clears the buffer.
     * @param more True when more rows are still to come, which forces part numbering.
     */
    private void writeFile(Boolean more) {
        Boolean isPart = more || partNumber > 1;
        String fileName = safeFileName(surveyName) + '-responses-' + stamp
            + (isPart ? '-part-' + partNumber : '') + '.csv';

        ContentVersion file = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            // Byte order mark so Excel reads the file as UTF-8.
            VersionData = Blob.valueOf('﻿' + String.join(lines, '\r\n')),
            FirstPublishLocationId = surveyId
        );
        insert file;

        fileNames.add(fileName);
        fileIds.add(file.Id);
        partNumber++;
        lines = new List<String>{ headerLine };
    }

    private static String toCsvLine(List<String> cells) {
        List<String> quoted = new List<String>();
        for (String cell : cells) {
            String text = cell == null ? '' : cell;
            quoted.add('"' + text.replace('"', '""') + '"');
        }
        return String.join(quoted, ',');
    }

    private static String safeFileName(String name) {
        String base = String.isBlank(name) ? 'survey' : name;
        base = base.replaceAll('[^a-zA-Z0-9]+', '-').replaceAll('^-+|-+$', '');
        return String.isBlank(base) ? 'survey' : base.toLowerCase();
    }
}