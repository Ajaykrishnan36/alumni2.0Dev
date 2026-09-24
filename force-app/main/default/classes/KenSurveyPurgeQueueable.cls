/**
 * @description Removes a survey that has more responses than one transaction can delete.
 *
 *              Deleting a popular survey inline hits the 10,000 DML row ceiling and fails, so
 *              this walks the answers and submissions in chunks, re-enqueueing itself until
 *              they are gone, and only then retires the questions and the survey itself. The
 *              survey record is deleted last so a failed chunk always leaves the work findable
 *              rather than stranding orphaned submissions.
 */
public without sharing class KenSurveyPurgeQueueable implements Queueable {

    /** Comfortably under the 10,000 DML row ceiling, leaving room for the chunk's own queries. */
    private static final Integer CHUNK_SIZE = 5000;

    private final Id surveyId;
    private final Id questionSetId;

    public KenSurveyPurgeQueueable(Id surveyId, Id questionSetId) {
        this.surveyId = surveyId;
        this.questionSetId = questionSetId;
    }

    /**
     * @description Deletes one chunk and re-enqueues while work remains.
     * @param context Queueable context.
     */
    public void execute(QueueableContext context) {
        List<AssessmentQuestionResponse> answers = [
            SELECT Id FROM AssessmentQuestionResponse
            WHERE Assessment.Ken_Survey__c = :surveyId
            WITH SECURITY_ENFORCED
            LIMIT :CHUNK_SIZE
        ];
        if (!answers.isEmpty()) {
            delete answers;
            enqueueNext();
            return;
        }

        List<Assessment> headers = [
            SELECT Id FROM Assessment WHERE Ken_Survey__c = :surveyId
            WITH SECURITY_ENFORCED
            LIMIT :CHUNK_SIZE
        ];
        if (!headers.isEmpty()) {
            delete headers;
            enqueueNext();
            return;
        }

        KenAssessmentSurveyService.deleteSurveyData(questionSetId, surveyId);
        List<Ken_Survey__c> survey = [SELECT Id FROM Ken_Survey__c WHERE Id = :surveyId WITH SECURITY_ENFORCED];
        if (!survey.isEmpty()) {
            delete survey;
        }
    }

    private void enqueueNext() {
        if (Test.isRunningTest()) {
            return;
        }
        System.enqueueJob(new KenSurveyPurgeQueueable(surveyId, questionSetId));
    }
}