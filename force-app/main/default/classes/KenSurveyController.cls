/**
 * @description Controller responsible for managing surveys, including
 *              creation, editing, response handling, and export operations.
 */
public without sharing class KenSurveyController {
    /**
     * @description Request wrapper containing survey metadata and
     *              questionnaire details used during survey creation or update.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class SurveySaveRequest {
        @AuraEnabled public String title {get; set;}
        @AuraEnabled public String description {get; set;}
        @AuraEnabled public List<String> targetAudience {get; set;}
        @AuraEnabled public String startDate {get; set;}
        @AuraEnabled public String endDate {get; set;}
        @AuraEnabled public List<QuestionDTO> questions {get; set;}
    }
    /**
     * @description Creates or updates a survey draft without questionnaire data.
     *
     * @param request SurveySaveRequest containing survey details.
     * @param surveyId Optional Id of the survey to update.
     * @return Id of the saved survey. 
     */
    @AuraEnabled
    public static Id saveSurveyDraft(SurveySaveRequest request, Id surveyId, Id constituentRoleId) {
        system.debug('Entering saveSurveyDraft with surveyId: ' + surveyId + ', constituentRoleId: ' + constituentRoleId);
        try {
            if (request == null) {
                throw new AuraHandledException('No data provided.');
            }
            Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
            Boolean isInternal = isInternalUser();
            if (effectiveRoleId == null && !isInternal) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }

            String title = String.isNotBlank(request.title) ? request.title.trim() : 'Untitled Survey';
            String description = String.isNotBlank(request.description) ? request.description.trim() : null;
            String audience = joinAudience(request.targetAudience);

            if (surveyId != null) {
                if (!Schema.sObjectType.Ken_Survey__c.isUpdateable()) {
                    throw new AuraHandledException('You do not have permission to update surveys.');
                }
                Ken_Survey__c existing = [
                    SELECT Id
                    FROM Ken_Survey__c
                    WHERE Id = :surveyId
                    LIMIT 1
                    FOR UPDATE
                ];
                existing.Name = title;
                existing.Section_Name__c = title;
                existing.Description__c = description;
                existing.Target_Audience__c = audience;
                existing.Start_Date__c = parseDate(request.startDate, false);
                existing.End_Date__c = parseDate(request.endDate, true);
                update existing;
                return existing.Id;
            }

            if (!Schema.sObjectType.Ken_Survey__c.isCreateable()) {
                throw new AuraHandledException('You do not have permission to create surveys.');
            }

            Ken_Survey__c survey = new Ken_Survey__c(
                Name = title,
                Section_Name__c = title,
                Description__c = description,
                Target_Audience__c = audience,
                Start_Date__c = parseDate(request.startDate, false),
                End_Date__c = parseDate(request.endDate, true),
                Approval_Status__c = 'Pending Approval',
                Constituent_Role__c = effectiveRoleId
            );
            insert survey;
            return survey.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage() + ' at ' + e.getLineNumber());
        }
    }

    /**
     * @description Creates a junction between survey and segmentation if it does not exist.
     *
     * @param surveyId Id of the survey.
     * @param segmentationId Id of the segmentation.
     * @return Id of the junction record.
     */
    @AuraEnabled
    public static Id createSurveySegmentation(Id surveyId, Id segmentationId) {
        if (surveyId == null || segmentationId == null) {
            throw new AuraHandledException('Survey Id and Segmentation Id are required.');
        }
        if (!Schema.sObjectType.Ken_Survey_Segmentation__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create survey segmentation.');
        }
        if (!Schema.sObjectType.Ken_Survey_Segmentation__c.fields.Survey__c.isCreateable()
            || !Schema.sObjectType.Ken_Survey_Segmentation__c.fields.Segmentation__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to set survey segmentation fields.');
        }

        List<Ken_Survey_Segmentation__c> existing = [
            SELECT Id
            FROM Ken_Survey_Segmentation__c
            WHERE Survey__c = :surveyId
            AND Segmentation__c = :segmentationId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        Ken_Survey_Segmentation__c link = new Ken_Survey_Segmentation__c(
            Survey__c = surveyId,
            Segmentation__c = segmentationId
        );
        insert link;
        return link.Id;
    }
    /**
     * @description Data transfer object representing an individual
     *              survey question definition.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class QuestionDTO {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String text {get; set;}
        @AuraEnabled public String type {get; set;}
        @AuraEnabled public Boolean required {get; set;}
        @AuraEnabled public List<QuestionOptionDTO> options {get; set;}
        @AuraEnabled public Integer scaleMin {get; set;}
        @AuraEnabled public Integer scaleMax {get; set;}
        @AuraEnabled public String scaleMinLabel {get; set;}
        @AuraEnabled public String scaleMaxLabel {get; set;}
    }
    /**
     * @description Wrapper representing a selectable option for
     *              multiple-choice survey questions.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class QuestionOptionDTO {
        @AuraEnabled public String text {get; set;}
    }
    /**
     * @description Wrapper containing survey details, questionnaire data,
     *              status information, and response metadata.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class SurveyData {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public String name {get; set;}
        @AuraEnabled public String sectionName {get; set;}
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
     * @description Wrapper holding questionnaire parameters associated
     *              with a survey.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class QuestionnaireData {
        @AuraEnabled public List<QuestionnaireParameterData> parameters { get; set; }
    }
    /**
     * @description Wrapper representing a single questionnaire parameter
     *              including question metadata and display configuration.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class QuestionnaireParameterData {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String questionType { get; set; }
        @AuraEnabled public String questionLabel { get; set; }
        @AuraEnabled public String mcqOptions { get; set; }
        @AuraEnabled public Decimal minGrade { get; set; }
        @AuraEnabled public Decimal maxGrade { get; set; }
        @AuraEnabled public String minGradeLabel { get; set; }
        @AuraEnabled public String maxGradeLabel { get; set; }
        @AuraEnabled public Decimal displayOrder { get; set; }
        @AuraEnabled public Boolean required { get; set; }
    }
    /**
     * @description Request wrapper containing survey responses submitted
     *              by a respondent.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class SurveyResponseRequest {
        @AuraEnabled public Id surveyId { get; set; }
        @AuraEnabled public Id sessionId { get; set; }
        @AuraEnabled public List<QuestionResponse> responses { get; set; }
    }
    /**
     * @description Wrapper representing a response to a single
     *              survey question.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class QuestionResponse {
        @AuraEnabled public Id questionId { get; set; }
        @AuraEnabled public String responseValue { get; set; }
    }
    /**
     * @description Wrapper returned when loading survey data for
     *              editing purposes.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class SurveyEditResponse {
        @AuraEnabled public SurveySaveRequest data { get; set; }
        @AuraEnabled public Id surveyId { get; set; }
        @AuraEnabled public String segmentationDefinitionJson { get; set; }
    }
    /**
     * @description Wrapper representing survey question metadata
     *              used during survey export.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class SurveyExportQuestion {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Decimal displayOrder { get; set; }
        @AuraEnabled public String questionType { get; set; }
    }
    /**
     * @description Wrapper representing a single respondent's answers
     *              in an exported survey dataset.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class SurveyExportRow {
        @AuraEnabled public Id respondentId { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String respondentName { get; set; }
        @AuraEnabled public Datetime submittedAt { get; set; }
        @AuraEnabled public Map<String, String> answersByQuestionId { get; set; }
    }
    /**
     * @description Wrapper containing exported survey data including
     *              questions and respondent responses.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class SurveyExportResult {
        @AuraEnabled public String surveyName { get; set; }
        @AuraEnabled public List<SurveyExportQuestion> questions { get; set; }
        @AuraEnabled public List<SurveyExportRow> rows { get; set; }
    }
    /**
     * @description Creates a new survey along with its questionnaire
     *              and associated questions.
     *
     * @param request SurveySaveRequest containing survey details and questions.
     * @return Id of the newly created survey.
     */
    @AuraEnabled
    public static Id createSurveyWithQuestions(SurveySaveRequest request, Id constituentRoleId) {
        try {
            if (request == null) {
                throw new AuraHandledException('No data provided.');
            }
            Id effectiveRoleId = resolveConstituentRoleId(constituentRoleId);
            Boolean isInternal = isInternalUser();
            if (effectiveRoleId == null && !isInternal) {
                throw new AuraHandledException('ConstituentRoleId is required.');
            }

            String title = String.isNotBlank(request.title) ? request.title.trim() : 'Untitled Survey';
            String description = String.isNotBlank(request.description) ? request.description.trim() : null;
            String audience = joinAudience(request.targetAudience);
            
            if (request.questions == null || request.questions.isEmpty()) {
                throw new AuraHandledException('No questions received from client.');
            }
            
            Ken_Questionnaire__c questionnaire = new Ken_Questionnaire__c(
                Section_Name__c = title,
            Descripation__c = description,
            Target_Audience__c = audience
                );
            
            List<Ken_Questionnaire_Parameter__c> questions = new List<Ken_Questionnaire_Parameter__c>();
            Integer order = 1;
            for (QuestionDTO dto : request.questions) {
                if (dto == null) {
                    continue;
                }
                Ken_Questionnaire_Parameter__c q = new Ken_Questionnaire_Parameter__c();
                q.Question_Label__c = dto.text;
                q.Question_Type__c = mapQuestionType(dto.type);
                q.Is_Required__c = dto.required == true;
                q.MCQ_Options__c = buildOptions(dto.options);
                q.Order__c = order++;
                q.Min_Grade__c = dto.scaleMin;
                q.Max_Grade__c = dto.scaleMax;
                q.Min_Grade_Label__c = dto.scaleMinLabel;
                q.Max_Grade_Label__c = dto.scaleMaxLabel;
                q.Section_Name__c = title;
                questions.add(q);
            }
            
            questionnaire.Questions_JSON__c = JSON.serialize(questions);
            if (Schema.sObjectType.Ken_Questionnaire__c.isCreateable()) {
                insert questionnaire;
            } else {
                throw new AuraHandledException('You do not have permission to create questionnaires.');
            }
            
            if (!questions.isEmpty()) {
                for (Ken_Questionnaire_Parameter__c q : questions) {
                    q.Questionnaire__c = questionnaire.Id;
                }
                if (Schema.sObjectType.Ken_Questionnaire_Parameter__c.isCreateable()) {
                    insert questions;
                } else {
                    throw new AuraHandledException('You do not have permission to create questionnaire parameters.');
                }
            }
            
            Ken_Survey__c survey = new Ken_Survey__c(
                Name = title,
            Section_Name__c = title,
            Description__c = description,
            Target_Audience__c = audience,
            Start_Date__c = parseDate(request.startDate, false),
            End_Date__c = parseDate(request.endDate, true),
            Approval_Status__c = 'Pending Approval',
            Ken_Questionnaire__c = questionnaire.Id,
            Constituent_Role__c = effectiveRoleId
                );
            
            if (Schema.sObjectType.Ken_Survey__c.isCreateable()) {
                insert survey;
            } else {
                throw new AuraHandledException('You do not have permission to create surveys.');
            }
            
            return survey.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage()+' at '+e.getLineNumber());
        }
    }
    /**
     * @description Returns all active or approved surveys
     *              available to the current user.
     *
     * @return List of SurveyData records.
     */
    
    @AuraEnabled
    public static List<SurveyData> getSurveys(Id constituentRoleId) {
        if (constituentRoleId == null) {
            return new List<SurveyData>();
        }
        
        List<Ken_Survey__c> surveys = [
                SELECT Id,
                        Name,
                        Section_Name__c,
                        Start_Date__c,
                        End_Date__c,
                        Approval_Status__c,
                        Is_Active__c,
                        CreatedDate,
                        CreatedById,
                        Constituent_Role__c,
                        Ken_Questionnaire__c,
                        Ken_Questionnaire__r.Name,
                        Ken_Questionnaire__r.Section_Name__c,
                        LastModifiedDate
                FROM Ken_Survey__c
                WHERE Ken_Questionnaire__c != null
                AND (Approval_Status__c = 'Approved' AND Is_Active__c = true)
                AND (Constituent_Role__c != :constituentRoleId OR Constituent_Role__c = null)
                ORDER BY End_Date__c DESC, CreatedDate DESC
            ];
        
        if (surveys.isEmpty()) {
            return new List<SurveyData>();
        }
        
        Id alumniRoleId = constituentRoleId;
        
        Set<Id> surveyIds = new Set<Id>();
        for (Ken_Survey__c survey : surveys) {
            surveyIds.add(survey.Id);
        }
        
        Map<Id, Id> surveyToRole = mapSurveysToConstituentRole(surveyIds, alumniRoleId);
        if (surveyToRole.isEmpty()) {
            return new List<SurveyData>();
        }
        
        List<Ken_Survey__c> filtered = new List<Ken_Survey__c>();
        for (Ken_Survey__c survey : surveys) {
            if (surveyToRole.containsKey(survey.Id)) {
                filtered.add(survey);
            }
        }
        
        return buildSurveyData(filtered);
    }

    private static Id fetchLatestAlumniConstituentRoleId(Id currentAccountId) {
        if (currentAccountId == null) {
            return null;
        }
        
        List<ConstituentRole> roles = [
            SELECT Id
            FROM ConstituentRole
            WHERE PersonId = :currentAccountId
            AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return roles.isEmpty() ? null : roles[0].Id;
    }

    private static Id resolveConstituentRoleId(Id constituentRoleId) {
        if (constituentRoleId != null) {
            return constituentRoleId;
        }
        Id accountId = fetchCurrentAccountId();
        if (accountId == null) {
            return null;
        }
        return fetchLatestAlumniConstituentRoleId(accountId);
    }

    /**
     * Internal Salesforce users (System Admin, internal staff) have no AccountId and no
     * ConstituentRole. The wizard is also launched for them via the Ken_Survey__c New/Edit
     * action overrides, so we must allow surveys to be saved without a Constituent_Role__c.
     */
    private static Boolean isInternalUser() {
        User u = [SELECT Id, UserType, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        // Standard / internal users have UserType = 'Standard' and a null AccountId.
        return u.AccountId == null || u.UserType == 'Standard';
    }
    
    private static Map<Id, Id> mapSurveysToConstituentRole(Set<Id> surveyIds, Id targetRoleId) {
        Map<Id, Id> surveyToRole = new Map<Id, Id>();
        if (surveyIds == null || surveyIds.isEmpty() || targetRoleId == null) {
            return surveyToRole;
        }
        
        List<Ken_Survey_Segmentation__c> links = [
            SELECT Id,
                   Survey__c,
                   Segmentation__c,
                   Segmentation__r.SOQL__c
            FROM Ken_Survey_Segmentation__c
            WHERE Survey__c IN :surveyIds
        ];
        
        for (Ken_Survey_Segmentation__c link : links) {
            if (link == null || link.Survey__c == null) {
                continue;
            }
            if (surveyToRole.containsKey(link.Survey__c)) {
                continue;
            }
            
            String soql = (link.Segmentation__r != null) ? link.Segmentation__r.SOQL__c : null;
            if (String.isBlank(soql)) {
                continue;
            }
            
            try {
                List<SObject> rows = Database.query(soql);
                if (rows == null || rows.isEmpty()) {
                    continue;
                }
                
                for (SObject row : rows) {
                    Object rowId = row.get('Id');
                    if (rowId != null && ((Id) rowId) == targetRoleId) {
                        surveyToRole.put(link.Survey__c, targetRoleId);
                        break;
                    }
                }
            } catch (Exception e) {
                continue;
            }
        }
        
        return surveyToRole;
    }
    /**
     * @description Retrieves surveys created by the
     *              currently logged-in user.
     *
     * @return List of SurveyData created by the user.
     */
    
    @AuraEnabled
    public static List<SurveyData> getMySurveys(Id constituentRoleId) {
        if (constituentRoleId == null) {
            return new List<SurveyData>();
        }
        
        List<Ken_Survey__c> surveys = [
            SELECT Id,
                    Name,
                    Section_Name__c,
                    Start_Date__c,
                    End_Date__c,
                    Approval_Status__c,
                    Is_Active__c,
                    CreatedDate,
                    CreatedById,
                    Constituent_Role__c,
                    Ken_Questionnaire__c,
                    Ken_Questionnaire__r.Name,
                    Ken_Questionnaire__r.Section_Name__c,
                    LastModifiedDate
            FROM Ken_Survey__c
            WHERE Ken_Questionnaire__c != null
            AND Constituent_Role__c = :constituentRoleId
            ORDER BY End_Date__c DESC, CreatedDate DESC
        ];
        return buildSurveyData(surveys);
    }
    
    private static Id fetchCurrentAccountId() {
        User u = [
            SELECT AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        return u.AccountId;
    }
    
    private static List<SurveyData> buildSurveyData(List<Ken_Survey__c> surveys) {
        if (!Schema.sObjectType.Ken_Questionnaire_Parameter__c.isAccessible()
            || !Schema.sObjectType.Ken_Questionnaire_Parameter_Response__c.isAccessible()
        || !Schema.sObjectType.ProcessInstanceStep.isAccessible()) {
            throw new AuraHandledException('INSUFFICIENT_ACCESS');
        }
        Set<Id> questionnaireIds = new Set<Id>();
        Set<Id> surveyIds = new Set<Id>();
        // Responses reach the survey via Questionnaire_Parameter__r.Questionnaire__c
        // (survey -> Ken_Questionnaire__c is 1:1); map questionnaire back to its survey.
        Map<Id, Id> surveyByQuestionnaire = new Map<Id, Id>();
        for (Ken_Survey__c s : surveys) {
            surveyIds.add(s.Id);
            if (s.Ken_Questionnaire__c != null) {
                questionnaireIds.add(s.Ken_Questionnaire__c);
                surveyByQuestionnaire.put(s.Ken_Questionnaire__c, s.Id);
            }
        }
        
        Map<Id, List<QuestionnaireParameterData>> questionnaireParams = new Map<Id, List<QuestionnaireParameterData>>();
        if (!questionnaireIds.isEmpty()) {
            for (Ken_Questionnaire_Parameter__c qp : [
                SELECT Id,
                       Question_Type__c,
                       Question_Label__c,
                       MCQ_Options__c,
                       Min_Grade__c,
                       Max_Grade__c,
                       Min_Grade_Label__c,
                       Max_Grade_Label__c,
                       Order__c,
                       Questionnaire__c,
                       Is_Required__c
                FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c IN :questionnaireIds
                ORDER BY Order__c
            ]) {
                if (!questionnaireParams.containsKey(qp.Questionnaire__c)) {
                    questionnaireParams.put(qp.Questionnaire__c, new List<QuestionnaireParameterData>());
                }
                QuestionnaireParameterData qd = new QuestionnaireParameterData();
                qd.id = qp.Id;
                qd.questionType = qp.Question_Type__c;
                qd.questionLabel = qp.Question_Label__c;
                qd.mcqOptions = qp.MCQ_Options__c;
                qd.minGrade = qp.Min_Grade__c;
                qd.maxGrade = qp.Max_Grade__c;
                qd.minGradeLabel = qp.Min_Grade_Label__c;
                qd.maxGradeLabel = qp.Max_Grade_Label__c;
                qd.displayOrder = qp.Order__c;
                qd.required = qp.Is_Required__c;
                questionnaireParams.get(qp.Questionnaire__c).add(qd);
            }
        }
        
        Map<Id, Integer> userResponseCounts = new Map<Id, Integer>();
        Map<Id, Integer> totalRespondentCounts = new Map<Id, Integer>();
        Map<Id, ProcessInstanceStep> rejectedSteps = new Map<Id, ProcessInstanceStep>();
        Map<Id, String> segmentationNameBySurveyId = new Map<Id, String>();
        if (!surveyIds.isEmpty()) {
            Id respondentId = fetchCurrentAccountId();
            for (AggregateResult ar : [
                SELECT Questionnaire_Parameter__r.Questionnaire__c qId, COUNT(Id) cnt
                FROM Ken_Questionnaire_Parameter_Response__c
                WHERE Questionnaire_Parameter__r.Questionnaire__c IN :questionnaireIds
                AND Respondent__c = :respondentId
                GROUP BY Questionnaire_Parameter__r.Questionnaire__c
            ]) {
                Id qId = (Id) ar.get('qId');
                if (surveyByQuestionnaire.containsKey(qId)) {
                    userResponseCounts.put(surveyByQuestionnaire.get(qId), (Integer) ar.get('cnt'));
                }
            }
            for (AggregateResult ar : [
                SELECT Questionnaire_Parameter__r.Questionnaire__c qId, COUNT_DISTINCT(Respondent__c) cnt
                FROM Ken_Questionnaire_Parameter_Response__c
                WHERE Questionnaire_Parameter__r.Questionnaire__c IN :questionnaireIds
                GROUP BY Questionnaire_Parameter__r.Questionnaire__c
            ]) {
                Id qId = (Id) ar.get('qId');
                if (surveyByQuestionnaire.containsKey(qId)) {
                    totalRespondentCounts.put(surveyByQuestionnaire.get(qId), (Integer) ar.get('cnt'));
                }
            }
            
            for (ProcessInstanceStep step : [
                SELECT ProcessInstance.TargetObjectId,
                       Comments,
                       CreatedDate
                FROM ProcessInstanceStep
                WHERE ProcessInstance.TargetObjectId IN :surveyIds
                AND StepStatus = 'Rejected'
                ORDER BY CreatedDate DESC
            ]) {
                Id targetId = step.ProcessInstance.TargetObjectId;
                if (targetId != null && !rejectedSteps.containsKey(targetId)) {
                    rejectedSteps.put(targetId, step);
                }
            }

            if (Schema.sObjectType.Ken_Survey_Segmentation__c.isAccessible()
                && Schema.sObjectType.Ken_Segmentation__c.isAccessible()) {
                for (Ken_Survey_Segmentation__c link : [
                    SELECT Survey__c, Segmentation__r.Name
                    FROM Ken_Survey_Segmentation__c
                    WHERE Survey__c IN :surveyIds
                    ORDER BY CreatedDate DESC
                ]) {
                    if (link.Survey__c == null || link.Segmentation__r == null || segmentationNameBySurveyId.containsKey(link.Survey__c)) {
                        continue;
                    }
                    segmentationNameBySurveyId.put(link.Survey__c, link.Segmentation__r.Name);
                }
            }
        }
        
        List<SurveyData> response = new List<SurveyData>();
        for (Ken_Survey__c survey : surveys) {
            SurveyData dto = new SurveyData();
            dto.id = survey.Id;
            dto.name = survey.Name;
            dto.sectionName = survey.Section_Name__c;
            dto.startDate = survey.Start_Date__c;
            dto.endDate = survey.End_Date__c;
            dto.fromDate = survey.Start_Date__c;
            dto.toDate = survey.End_Date__c;
            dto.approvalStatus = survey.Approval_Status__c;
            dto.isActive = survey.Is_Active__c;
            dto.segmentationName = segmentationNameBySurveyId.get(survey.Id);
            dto.questionnaireId = survey.Ken_Questionnaire__c;
            dto.submittedDate = survey.CreatedDate;
            dto.createdById = survey.CreatedById;
            dto.createdByAccountId = survey.Constituent_Role__c;
            dto.hasResponses = userResponseCounts.containsKey(survey.Id) && userResponseCounts.get(survey.Id) > 0;
            if (totalRespondentCounts.containsKey(survey.Id)) {
                dto.responsesCount = totalRespondentCounts.get(survey.Id);
            }
            if (rejectedSteps.containsKey(survey.Id)) {
                ProcessInstanceStep step = rejectedSteps.get(survey.Id);
                dto.rejectedDate = step.CreatedDate;
                dto.rejectionComments = step.Comments;
            }
            
            if (dto.questionnaireId != null && questionnaireParams.containsKey(dto.questionnaireId)) {
                QuestionnaireData qd = new QuestionnaireData();
                qd.parameters = questionnaireParams.get(dto.questionnaireId);
                dto.questionnaire = qd;
            }
            
            response.add(dto);
        }
        return response;
    }
    /**
     * @description Submits responses for a survey
     *              from the current respondent.
     *
     * @param request SurveyResponseRequest containing responses.
     */
    
    @AuraEnabled
    public static void submitSurveyResponses(SurveyResponseRequest request) {
        if (request == null) {
            throw new AuraHandledException('Request is required.');
        }
        if (request.surveyId == null && request.sessionId == null) {
            throw new AuraHandledException('Survey Id or Session Id is required.');
        }
        if (!Schema.sObjectType.Ken_Questionnaire_Parameter_Response__c.isCreateable()) {
            throw new AuraHandledException('Insufficient access to save survey responses.');
        }

        Id respondentAccountId = fetchCurrentAccountId();
        Boolean isEventFeedback = (request.sessionId != null);

        // Everything is keyed off the Survey now (no event/session lookups on the response,
        // so the questionnaire module stays independent of the Alumni objects).
        Id targetSurveyId = request.surveyId;
        if (isEventFeedback) {
            List<Ken_Schedule_Sessions__c> linked = [
                SELECT Id, Survey__c
                FROM Ken_Schedule_Sessions__c
                WHERE Id = :request.sessionId
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
        String category = isEventFeedback ? 'Event' : 'Survey';

        List<Ken_Questionnaire_Parameter_Response__c> inserts = new List<Ken_Questionnaire_Parameter_Response__c>();
        if (request.responses != null) {
            for (QuestionResponse qr : request.responses) {
                if (qr == null || qr.questionId == null || String.isBlank(qr.responseValue)) {
                    continue;
                }
                // The question links to the survey's questionnaire, which is how the
                // response reaches the survey (no direct survey lookup on the response).
                inserts.add(new Ken_Questionnaire_Parameter_Response__c(
                    Questionnaire_Parameter__c = qr.questionId,
                    Respondent__c = respondentAccountId,
                    Response__c = qr.responseValue,
                    Response_Category__c = category
                ));
            }
        }
        if (inserts.isEmpty()) {
            // No answers submitted: stamp a marker against the survey's first question so
            // it still links to the survey through the questionnaire.
            Ken_Questionnaire_Parameter_Response__c marker = new Ken_Questionnaire_Parameter_Response__c(
                Respondent__c = respondentAccountId,
                Response__c = 'Submitted',
                Response_Category__c = category
            );
            Id markerParamId = firstParamForSurvey(targetSurveyId);
            if (markerParamId != null) {
                marker.Questionnaire_Parameter__c = markerParamId;
            }
            inserts.add(marker);
        }
        insert inserts;
    }

    // Responses link to a survey only through Questionnaire_Parameter__r.Questionnaire__c
    // (survey -> Ken_Questionnaire__c is 1:1). These helpers resolve that path.
    private static Id questionnaireIdForSurvey(Id surveyId) {
        if (surveyId == null) {
            return null;
        }
        List<Ken_Survey__c> s = [
            SELECT Ken_Questionnaire__c FROM Ken_Survey__c WHERE Id = :surveyId LIMIT 1
        ];
        return s.isEmpty() ? null : s[0].Ken_Questionnaire__c;
    }

    private static Id firstParamForSurvey(Id surveyId) {
        Id questionnaireId = questionnaireIdForSurvey(surveyId);
        if (questionnaireId == null) {
            return null;
        }
        List<Ken_Questionnaire_Parameter__c> ps = [
            SELECT Id FROM Ken_Questionnaire_Parameter__c
            WHERE Questionnaire__c = :questionnaireId
            ORDER BY Order__c ASC NULLS LAST
            LIMIT 1
        ];
        return ps.isEmpty() ? null : ps[0].Id;
    }

    /**
     * @description Returns event session feedback as a SurveyData wrapper so
     *              the existing kenSurveyForm renderer can drive it.
     * @param sessionId Ken_Schedule_Sessions__c id whose linked questionnaire is rendered.
     * @return SurveyData populated from the session's Questionnaire__c.
     */
    @AuraEnabled(cacheable=true)
    public static SurveyData getEventFeedbackAsSurvey(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('Session id is required.');
        }
        List<Ken_Schedule_Sessions__c> sessions = [
            SELECT Id, Name, Event_Reference__c, Event_Reference__r.Name, Questionnaire__c,
                   Survey__c, Survey__r.Ken_Questionnaire__c
            FROM Ken_Schedule_Sessions__c
            WHERE Id = :sessionId
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            throw new AuraHandledException('Session not found.');
        }
        Ken_Schedule_Sessions__c session = sessions[0];
        // Prefer the survey-linked questionnaire; fall back to the legacy direct lookup.
        Id questionnaireId = (session.Survey__r != null && session.Survey__r.Ken_Questionnaire__c != null)
            ? session.Survey__r.Ken_Questionnaire__c
            : session.Questionnaire__c;
        if (questionnaireId == null) {
            throw new AuraHandledException('No feedback form has been set up for this session.');
        }
        List<Ken_Questionnaire__c> qs = [
            SELECT Id, Section_Name__c, Descripation__c
            FROM Ken_Questionnaire__c
            WHERE Id = :questionnaireId
            LIMIT 1
        ];
        if (qs.isEmpty()) {
            throw new AuraHandledException('Feedback form is missing.');
        }
        List<Ken_Questionnaire_Parameter__c> params = [
            SELECT Id, Question_Label__c, Question_Type__c, MCQ_Options__c,
                   Min_Grade__c, Max_Grade__c, Min_Grade_Label__c, Max_Grade_Label__c,
                   Order__c, Is_Required__c
            FROM Ken_Questionnaire_Parameter__c
            WHERE Questionnaire__c = :questionnaireId
            ORDER BY Order__c ASC NULLS LAST
        ];

        SurveyData data = new SurveyData();
        data.id = session.Id;
        data.name = session.Event_Reference__r != null ? session.Event_Reference__r.Name : session.Name;
        data.sectionName = qs[0].Section_Name__c;
        data.questionnaireId = qs[0].Id;
        data.isActive = true;
        QuestionnaireData qd = new QuestionnaireData();
        qd.parameters = new List<QuestionnaireParameterData>();
        for (Ken_Questionnaire_Parameter__c p : params) {
            QuestionnaireParameterData qp = new QuestionnaireParameterData();
            qp.id = p.Id;
            qp.questionLabel = p.Question_Label__c;
            qp.questionType = p.Question_Type__c;
            qp.mcqOptions = p.MCQ_Options__c;
            qp.minGrade = p.Min_Grade__c;
            qp.maxGrade = p.Max_Grade__c;
            qp.minGradeLabel = p.Min_Grade_Label__c;
            qp.maxGradeLabel = p.Max_Grade_Label__c;
            qp.displayOrder = p.Order__c;
            qp.required = p.Is_Required__c == true;
            qd.parameters.add(qp);
        }
        data.questionnaire = qd;
        return data;
    }
    
    private static String joinAudience(List<String> audience) {
        return (audience == null || audience.isEmpty()) ? null : String.join(audience, ';');
    }
    
    private static String buildOptions(List<QuestionOptionDTO> options) {
        if (options == null || options.isEmpty()) {
            return null;
        }
        List<String> labels = new List<String>();
        for (QuestionOptionDTO opt : options) {
            if (opt != null && String.isNotBlank(opt.text)) {
                labels.add(opt.text);
            }
        }
        return labels.isEmpty() ? null : String.join(labels, ';');
    }
    
    private static String mapQuestionTypeForClient(String typeValue) {
        if (String.isBlank(typeValue)) {
            return 'short';
        }
        String normalized = typeValue.toLowerCase();
        if (normalized.contains('multiple')) {
            return 'multiple';
        }
        if (normalized.contains('checkbox')) {
            return 'checkbox';
        }
        if (normalized.contains('linear') || normalized.contains('rating')) {
            return 'linear';
        }
        return 'short';
    }
    /**
     * @description Loads survey details and questions
     *              for editing purposes.
     *
     * @param surveyId Id of the survey to edit.
     * @return SurveyEditResponse containing editable data.
     */
    
    @AuraEnabled(cacheable=false)
    public static SurveyEditResponse getSurveyForEdit(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        Ken_Survey__c survey = [
            SELECT Id, Name, Section_Name__c, Description__c, Target_Audience__c,
                   Start_Date__c, End_Date__c, Ken_Questionnaire__c
            FROM Ken_Survey__c
            WHERE Id = :surveyId
            LIMIT 1
        ];

        List<Ken_Questionnaire_Parameter__c> params = new List<Ken_Questionnaire_Parameter__c>();
        if (survey.Ken_Questionnaire__c != null) {
            params = [
                SELECT Id, Question_Label__c, Question_Type__c, Is_Required__c,
                       MCQ_Options__c, Min_Grade__c, Max_Grade__c,
                       Min_Grade_Label__c, Max_Grade_Label__c, Order__c
                FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c = :survey.Ken_Questionnaire__c
                ORDER BY Order__c
            ];
        }

        String segmentationJson = null;
        if (Schema.sObjectType.Ken_Survey_Segmentation__c.isAccessible()
            && Schema.sObjectType.Ken_Segmentation__c.isAccessible()) {
            List<Ken_Survey_Segmentation__c> links = [
                SELECT Segmentation__r.Definition_JSON__c
                FROM Ken_Survey_Segmentation__c
                WHERE Survey__c = :surveyId
                ORDER BY CreatedDate ASC
            ];
            List<String> jsonList = new List<String>();
            for (Ken_Survey_Segmentation__c link : links) {
                if (link.Segmentation__r != null && link.Segmentation__r.Definition_JSON__c != null) {
                    jsonList.add(link.Segmentation__r.Definition_JSON__c);
                }
            }
            if (!jsonList.isEmpty()) {
                // Build a JSON array directly — avoids double-encoding that JSON.serialize(List<String>) causes
                segmentationJson = '[' + String.join(jsonList, ',') + ']';
            }
        }
        
        SurveySaveRequest dto = new SurveySaveRequest();
        dto.title = survey.Name;
        dto.description = survey.Description__c;
        dto.targetAudience = String.isNotBlank(survey.Target_Audience__c)
            ? survey.Target_Audience__c.split(';')
            : new List<String>();
        dto.startDate = survey.Start_Date__c != null ? String.valueOf(survey.Start_Date__c.date()) : null;
        dto.endDate = survey.End_Date__c != null ? String.valueOf(survey.End_Date__c.date()) : null;
        dto.questions = new List<QuestionDTO>();
        
        Integer order = 1;
        for (Ken_Questionnaire_Parameter__c qp : params) {
            QuestionDTO qdto = new QuestionDTO();
            qdto.id = qp.Id;
            qdto.text = qp.Question_Label__c;
            qdto.type = mapQuestionTypeForClient(qp.Question_Type__c);
            qdto.required = qp.Is_Required__c;
            qdto.scaleMin = qp.Min_Grade__c != null ? qp.Min_Grade__c.intValue() : null;
            qdto.scaleMax = qp.Max_Grade__c != null ? qp.Max_Grade__c.intValue() : null;
            qdto.scaleMinLabel = qp.Min_Grade_Label__c;
            qdto.scaleMaxLabel = qp.Max_Grade_Label__c;
            qdto.options = new List<QuestionOptionDTO>();
            if (String.isNotBlank(qp.MCQ_Options__c)) {
                // Split on semicolon, comma, or newline to support existing stored formats
                for (String opt : qp.MCQ_Options__c.split('[;,\\n]+')) {
                    if (String.isNotBlank(opt)) {
                        QuestionOptionDTO odto = new QuestionOptionDTO();
                        odto.text = opt.trim();
                        qdto.options.add(odto);
                    }
                }
            }
            dto.questions.add(qdto);
            order++;
        }
        
        SurveyEditResponse resp = new SurveyEditResponse();
        resp.data = dto;
        resp.surveyId = survey.Id;
        resp.segmentationDefinitionJson = segmentationJson;
        return resp;
    }
    /**
     * @description Updates an existing survey along with
     *              its questionnaire and questions.
     *
     * @param request SurveySaveRequest with updated data.
     * @param surveyId Id of the survey to update.
     * @return Id of the updated survey.
     */
    
    @AuraEnabled
    public static Id updateSurveyWithQuestions(SurveySaveRequest request, Id surveyId) {
        checkCrudAccess();
        
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required for update.');
        }
        if (request == null) {
            throw new AuraHandledException('No data provided.');
        }
        
        Ken_Survey__c survey = [
            SELECT Id, Ken_Questionnaire__c
            FROM Ken_Survey__c
            WHERE Id = :surveyId
            LIMIT 1
            FOR UPDATE
        ];
        
        Id questionnaireId = survey.Ken_Questionnaire__c;
        Ken_Questionnaire__c questionnaire;
        if (questionnaireId != null) {
            questionnaire = [
                SELECT Id
                FROM Ken_Questionnaire__c
                WHERE Id = :questionnaireId
                LIMIT 1
                FOR UPDATE
            ];
        } else {
            questionnaire = new Ken_Questionnaire__c();
        }
        
        String title = String.isNotBlank(request.title) ? request.title.trim() : 'Untitled Survey';
        String description = String.isNotBlank(request.description) ? request.description.trim() : null;
        String audience = joinAudience(request.targetAudience);
        
        questionnaire.Section_Name__c = title;
        questionnaire.Descripation__c = description;
        questionnaire.Target_Audience__c = audience;
        if (questionnaire.Id == null) {
            insert questionnaire;
            survey.Ken_Questionnaire__c = questionnaire.Id;
        } else {
            update questionnaire;
        }
        
        if (questionnaire.Id != null) {
            List<Ken_Questionnaire_Parameter__c> existing = [
                SELECT Id FROM Ken_Questionnaire_Parameter__c WHERE Questionnaire__c = :questionnaire.Id
            ];
            if (!existing.isEmpty()) {
                delete existing;
            }
        }
        
        List<Ken_Questionnaire_Parameter__c> newParams = new List<Ken_Questionnaire_Parameter__c>();
        Integer order = 1;
        for (QuestionDTO dto : request.questions) {
            if (dto == null) continue;
            Ken_Questionnaire_Parameter__c q = new Ken_Questionnaire_Parameter__c();
            q.Questionnaire__c = questionnaire.Id;
            q.Question_Label__c = dto.text;
            q.Question_Type__c = mapQuestionType(dto.type);
            q.Is_Required__c = dto.required == true;
            q.MCQ_Options__c = buildOptions(dto.options);
            q.Order__c = order++;
            q.Min_Grade__c = dto.scaleMin;
            q.Max_Grade__c = dto.scaleMax;
            q.Min_Grade_Label__c = dto.scaleMinLabel;
            q.Max_Grade_Label__c = dto.scaleMaxLabel;
            q.Section_Name__c = title;
            newParams.add(q);
        }
        if (!newParams.isEmpty()) {
            insert newParams;
        }
        
        survey.Name = title;
        survey.Section_Name__c = title;
        survey.Description__c = description;
        survey.Target_Audience__c = audience;
        survey.Start_Date__c = parseDate(request.startDate, false);
        survey.End_Date__c = parseDate(request.endDate, true);
        survey.Approval_Status__c = 'Pending Approval';
        update survey;
        
        return survey.Id;
    }
    /**
     * @description Retrieves survey responses formatted
     *              for export and reporting.
     *
     * @param surveyId Id of the survey.
     * @return SurveyExportResult containing response data.
     */
    
    @AuraEnabled(cacheable=true)
    public static SurveyExportResult getSurveyResponsesForExport(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        
        Ken_Survey__c survey = [
            SELECT Id, Name, Section_Name__c, Ken_Questionnaire__c
            FROM Ken_Survey__c
            WHERE Id = :surveyId
            LIMIT 1
        ];
        
        if (survey.Ken_Questionnaire__c == null) {
            throw new AuraHandledException('Survey does not have a questionnaire.');
        }
        
        List<Ken_Questionnaire_Parameter__c> params = [
            SELECT Id, Question_Label__c, Question_Type__c, Order__c
            FROM Ken_Questionnaire_Parameter__c
            WHERE Questionnaire__c = :survey.Ken_Questionnaire__c
            ORDER BY Order__c
        ];
        
        Map<Id, SurveyExportQuestion> questionMap = new Map<Id, SurveyExportQuestion>();
        List<SurveyExportQuestion> questions = new List<SurveyExportQuestion>();
        for (Ken_Questionnaire_Parameter__c param : params) {
            SurveyExportQuestion qdto = new SurveyExportQuestion();
            qdto.id = param.Id;
            qdto.label = param.Question_Label__c;
            qdto.displayOrder = param.Order__c;
            qdto.questionType = param.Question_Type__c;
            questions.add(qdto);
            questionMap.put(param.Id, qdto);
        }
        
        List<Ken_Questionnaire_Parameter_Response__c> responses = [
            SELECT Id,
                   Response__c,
                   CreatedDate,
                   Questionnaire_Parameter__c,
                   Respondent__c,
                   Respondent__r.Name
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__r.Questionnaire__c = :survey.Ken_Questionnaire__c
        ];
        
        Map<String, SurveyExportRow> rowsByKey = new Map<String, SurveyExportRow>();
        for (Ken_Questionnaire_Parameter_Response__c resp : responses) {
            String key;
            if (resp.Respondent__c != null) {
                key = String.valueOf(resp.Respondent__c);
            } else {
                key = resp.Id;
            }
            
            if (!rowsByKey.containsKey(key)) {
                SurveyExportRow row = new SurveyExportRow();
                row.accountId = resp.Respondent__r != null ? resp.Respondent__c : null;
                row.respondentId = resp.Respondent__c;
                row.respondentName = resp.Respondent__r != null ? resp.Respondent__r.Name : null;
                row.submittedAt = resp.CreatedDate;
                row.answersByQuestionId = new Map<String, String>();
                rowsByKey.put(key, row);
            }
            
            SurveyExportRow existing = rowsByKey.get(key);
            if (existing.submittedAt == null || resp.CreatedDate < existing.submittedAt) {
                existing.submittedAt = resp.CreatedDate;
            }
            if (resp.Questionnaire_Parameter__c != null) {
                existing.answersByQuestionId.put(
                    String.valueOf(resp.Questionnaire_Parameter__c),
                resp.Response__c
                    );
            }
        }
        
        SurveyExportResult result = new SurveyExportResult();
        result.surveyName = String.isNotBlank(survey.Name) ? survey.Name : survey.Section_Name__c;
        result.questions = questions;
        result.rows = new List<SurveyExportRow>(rowsByKey.values());
        return result;
    }
    
    private static String mapQuestionType(String typeValue) {
        if (String.isBlank(typeValue)) {
            return null;
        }
        String normalized = typeValue.toLowerCase();
        if (normalized == 'multiple' || normalized == 'checkbox') {
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
    
    private static Datetime parseDate(String dateValue, Boolean endOfDay) {
        if (String.isBlank(dateValue)) {
            return null;
        }
        try {
            if (dateValue.length() > 10) {
                return Datetime.valueOf(dateValue.replace('T', ' '));
            }
            Date d = Date.valueOf(dateValue);
            // Org-local day boundaries. Storing GMT midnight shifted the boundary
            // by the org's UTC offset, so a survey starting "today" read as
            // Upcoming until 05:30 IST and one ending "today" completed at 05:30.
            Time t = endOfDay == true
                ? Time.newInstance(23, 59, 59, 0)
                : Time.newInstance(0, 0, 0, 0);
            return Datetime.newInstance(d, t);
        } catch (Exception e) {
            return null;
        }
    }
    /**
     * @description Deletes a survey along with its
     *              questionnaire and responses.
     *
     * @param surveyId Id of the survey to delete.
     */
    
    @AuraEnabled
    public static void deleteSurvey(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        
        if (!Schema.sObjectType.Ken_Survey__c.isDeletable()
            || !Schema.sObjectType.Ken_Questionnaire__c.isDeletable()
            || !Schema.sObjectType.Ken_Questionnaire_Parameter__c.isDeletable()
        || !Schema.sObjectType.Ken_Questionnaire_Parameter_Response__c.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete survey records.');
        }
        
        Ken_Survey__c survey = [
            SELECT Id, Ken_Questionnaire__c
            FROM Ken_Survey__c
            WHERE Id = :surveyId
            LIMIT 1
        ];
        
        Id questionnaireId = survey.Ken_Questionnaire__c;

        if (questionnaireId != null) {
            List<Ken_Questionnaire_Parameter_Response__c> responses = [
                SELECT Id
                FROM Ken_Questionnaire_Parameter_Response__c
                WHERE Questionnaire_Parameter__r.Questionnaire__c = :questionnaireId
            ];
            if (!responses.isEmpty()) {
                delete responses;
            }
            List<Ken_Questionnaire_Parameter__c> params = [
                SELECT Id
                FROM Ken_Questionnaire_Parameter__c
                WHERE Questionnaire__c = :questionnaireId
            ];
            if (!params.isEmpty()) {
                delete params;
            }
            Ken_Questionnaire__c questionnaire = [
                SELECT Id
                FROM Ken_Questionnaire__c
                WHERE Id = :questionnaireId
                LIMIT 1
            ];
            delete questionnaire;
        }
        
        delete survey;
    }
    /**
     * @description Wrapper representing aggregated statistics
     *              for a single response value.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class ResponseStatDTO {
        @AuraEnabled public String responseValue { get; set; }
        @AuraEnabled public Integer count { get; set; }
        @AuraEnabled public Decimal percent { get; set; }
    }
    /**
     * @description Wrapper representing response statistics
     *              for a single survey question.
     */
    @SuppressWarnings('PMD.ApexDoc')
    public class QuestionStatsDTO {
        @AuraEnabled public Id questionId { get; set; }
        @AuraEnabled public Integer total { get; set; }
        @AuraEnabled public List<ResponseStatDTO> stats { get; set; }
    }
    /**
     * @description Calculates response statistics
     *              for each survey question.
     *
     * @param surveyId Id of the survey.
     * @return List of QuestionStatsDTO records.
     */
    
    @AuraEnabled(cacheable=true)
    public static List<QuestionStatsDTO> getSurveyResponseStats(Id surveyId) {
        if (surveyId == null) {
            throw new AuraHandledException('Survey Id is required.');
        }
        
        Id questionnaireId = questionnaireIdForSurvey(surveyId);
        if (questionnaireId == null) {
            return new List<QuestionStatsDTO>();
        }

        // IMPORTANT:
        // - Do NOT filter on Response__c (long text may not be filterable)
        // - Use CreatedDate DESC to get latest first (so first seen = latest)
        List<Ken_Questionnaire_Parameter_Response__c> rows = [
            SELECT Id, Questionnaire_Parameter__c, Respondent__c, Response__c, CreatedDate
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__r.Questionnaire__c = :questionnaireId
            AND Questionnaire_Parameter__c != null
            AND Respondent__c != null
            ORDER BY CreatedDate DESC
        ];
        
        // questionId -> (respondentId -> latestResponseValue)
        Map<Id, Map<Id, String>> latestByQuestion = new Map<Id, Map<Id, String>>();
        
        for (Ken_Questionnaire_Parameter_Response__c r : rows) {
            Id qId = r.Questionnaire_Parameter__c;
            Id respondentId = r.Respondent__c;
            
            if (!latestByQuestion.containsKey(qId)) {
                latestByQuestion.put(qId, new Map<Id, String>());
            }
            
            Map<Id, String> latestByRespondent = latestByQuestion.get(qId);
            
            // Since list is DESC, first time we see (qId + respondentId) is the latest record
            if (!latestByRespondent.containsKey(respondentId)) {
                latestByRespondent.put(respondentId, r.Response__c);
            }
        }
        
        List<QuestionStatsDTO> result = new List<QuestionStatsDTO>();
        
        for (Id qId : latestByQuestion.keySet()) {
            Map<Id, String> latestByRespondent = latestByQuestion.get(qId);
            
            // responseValue -> count
            Map<String, Integer> counts = new Map<String, Integer>();
            
            for (String raw : latestByRespondent.values()) {
                if (String.isBlank(raw)) continue;
                
                String key = raw.trim();
                counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
            }
            
            Integer total = 0;
            for (Integer c : counts.values()) total += c;
            
            // Build stats list
            List<ResponseStatDTO> stats = new List<ResponseStatDTO>();
            for (String val : counts.keySet()) {
                Integer c = counts.get(val);
                Decimal pct = (total > 0)
                    ? (Decimal.valueOf(c) * 100) / Decimal.valueOf(total)
                    : 0;
                
                ResponseStatDTO dto = new ResponseStatDTO();
                dto.responseValue = val;
                dto.count = c;
                dto.percent = pct.setScale(0); // 0 decimals like "(70%)"
                stats.add(dto);
            }
            
            // OPTIONAL: sort stats by count DESC (manual, no Comparator)
            stats = sortStatsByCountDesc(stats);
            
            QuestionStatsDTO qdto = new QuestionStatsDTO();
            qdto.questionId = qId;
            qdto.total = total;
            qdto.stats = stats;
            result.add(qdto);
        }
        
        return result;
    }
    
    // Manual sort by count DESC (simple bubble sort; stats list is small)
    private static List<ResponseStatDTO> sortStatsByCountDesc(List<ResponseStatDTO> input) {
        if (input == null || input.size() <= 1) return input;
        
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
    private static void checkCrudAccess() {
        if (!Schema.sObjectType.Ken_Survey__c.isAccessible()
            || !Schema.sObjectType.Ken_Survey__c.isUpdateable()
            || !Schema.sObjectType.Ken_Questionnaire__c.isAccessible()
            || !Schema.sObjectType.Ken_Questionnaire__c.isCreateable()
            || !Schema.sObjectType.Ken_Questionnaire__c.isUpdateable()
            || !Schema.sObjectType.Ken_Questionnaire_Parameter__c.isCreateable()
            || !Schema.sObjectType.Ken_Questionnaire_Parameter__c.isDeletable()
        ) {
            throw new AuraHandledException('INSUFFICIENT_ACCESS');
        }
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
    
    @AuraEnabled(cacheable=true)
    public static List<ShortAnswerCountDTO> getShortAnswerQuestionCounts(Id surveyId) {
        
        if (surveyId == null) throw new AuraHandledException('Survey Id is required.');
        Id questionnaireId = questionnaireIdForSurvey(surveyId);
        if (questionnaireId == null) {
            return new List<ShortAnswerCountDTO>();
        }
        List<Ken_Questionnaire_Parameter_Response__c> recs = [
            SELECT Id, Questionnaire_Parameter__c, Respondent__c, Response__c, CreatedDate
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__r.Questionnaire__c = :questionnaireId
            AND Questionnaire_Parameter__c != null
            AND Respondent__c != null
            ORDER BY CreatedDate DESC
        ];
        
        Map<Id, Map<Id, String>> latestByQuestion = new Map<Id, Map<Id, String>>();
        
        for (Ken_Questionnaire_Parameter_Response__c r : recs) {
            Id qId = r.Questionnaire_Parameter__c;
            Id respId = r.Respondent__c;
            
            if (!latestByQuestion.containsKey(qId)) {
                latestByQuestion.put(qId, new Map<Id, String>());
            }
            
            Map<Id, String> latestByRespondent = latestByQuestion.get(qId);
            if (!latestByRespondent.containsKey(respId)) {
                latestByRespondent.put(respId, r.Response__c);
            }
        }
        
        List<ShortAnswerCountDTO> out = new List<ShortAnswerCountDTO>();
        
        for (Id qId : latestByQuestion.keySet()) {
            Integer total = 0;
            for (String v : latestByQuestion.get(qId).values()) {
                if (String.isNotBlank(v)) total++;
            }
            
            ShortAnswerCountDTO dto = new ShortAnswerCountDTO();
            dto.questionId = qId;
            dto.total = total;
            out.add(dto);
        }
        return out;
    }
    
    @AuraEnabled(cacheable=true)
    public static ShortAnswerExportDTO getShortAnswerResponsesForExport(Id surveyId, Id questionId) {
        
        if (surveyId == null) throw new AuraHandledException('Survey Id is required.');
        if (questionId == null) throw new AuraHandledException('Question Id is required.');
        
        List<Ken_Questionnaire_Parameter_Response__c> recs = [
            SELECT Id,
                   Questionnaire_Parameter__c,
                   Respondent__c,
                   Respondent__r.Name,
                   Response__c,
                   CreatedDate
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Questionnaire_Parameter__c = :questionId
            AND Respondent__c != null
            ORDER BY CreatedDate DESC
        ];
        
        Map<Id, Ken_Questionnaire_Parameter_Response__c> latestByRespondent = new Map<Id, Ken_Questionnaire_Parameter_Response__c>();
        for (Ken_Questionnaire_Parameter_Response__c r : recs) {
            if (!latestByRespondent.containsKey(r.Respondent__c)) {
                latestByRespondent.put(r.Respondent__c, r);
            }
        }
        
        List<ShortAnswerRowDTO> rows = new List<ShortAnswerRowDTO>();
        for (Ken_Questionnaire_Parameter_Response__c r : latestByRespondent.values()) {
            if (String.isBlank(r.Response__c)) continue;
            ShortAnswerRowDTO dto = new ShortAnswerRowDTO();
            dto.respondentId = r.Respondent__c;
            dto.respondentName = (r.Respondent__r != null) ? r.Respondent__r.Name : null;
            dto.responseText = r.Response__c;
            rows.add(dto);
        }
        
        ShortAnswerExportDTO out = new ShortAnswerExportDTO();
        out.questionId = questionId;
        out.total = rows.size();
        out.rows = rows;
        return out;
    }
}