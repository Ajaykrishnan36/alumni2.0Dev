/**
 * @description
 * KenServiceSupportController handles FAQs, service and support cases,
 * questionnaires, and attachments for the Experience Cloud portal.
 *
 * @reason PMD class-level cyclomatic complexity is aggregate-based.
 * Individual methods are within acceptable limits.
 */
@SuppressWarnings('PMD.CyclomaticComplexity')
public without sharing class KenServiceSupportController {
    /**
     * @description Wrapper for FAQ question data
     */
    public class FAQQuestionWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public Integer likeCount;
        @AuraEnabled public Integer dislikeCount;
    }
    
    
    /**
     * @description Wrapper for FAQ category data
     */
    public class FAQCategoryWrapper {
        @AuraEnabled public String category;
        @AuraEnabled public List<FAQQuestionWrapper> questions;
    }
    
    /**
     * @description Wrapper for case history item
     */
    public class HistoryItem {
        @AuraEnabled public String id;
        @AuraEnabled public String caseId;
        @AuraEnabled public String title;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String description;
        @AuraEnabled public String attachment;
        @AuraEnabled public String attachmentName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime closedDate;
        @AuraEnabled public Datetime rejectedDate;
        @AuraEnabled public Datetime canceledDate;
        @AuraEnabled public String recordType;
        @AuraEnabled public String serviceOfferingName;
        @AuraEnabled public Boolean hasFeedbackSubmitted;
        @AuraEnabled public String rating;
        @AuraEnabled public String feedback;
        
    }
    
    /**
     * @description Wrapper for service, support and gate pass case history
     */
    public class HistoryResponse {
        @AuraEnabled public List<HistoryItem> serviceHistory;
        @AuraEnabled public List<HistoryItem> supportHistory;
        @AuraEnabled public List<HistoryItem> gatePassHistory;

        /**
         * @description Constructor initializes empty lists
         */
        public HistoryResponse() {
            serviceHistory  = new List<HistoryItem>();
            supportHistory  = new List<HistoryItem>();
            gatePassHistory = new List<HistoryItem>();
        }
    }
    
    /**
     * @description Wrapper for detailed case response
     */
    public class CaseDetailResponse {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String description;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String recordType;
        @AuraEnabled public Id serviceOfferingId;
        @AuraEnabled public String serviceOfferingName;
        @AuraEnabled public List<Ken_Questionnaire_Parameter_Response__c> responses;
        @AuraEnabled public String attachmentUrl;
        @AuraEnabled public String attachmentName;
        @AuraEnabled public List<CaseCommentWrapper> comments;
        @AuraEnabled public Boolean hasFeedbackSubmitted;
    }
    
    /**
     * @description Wrapper for questionnaire parameter
     */
    public class QuestionnaireWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String options;
        @AuraEnabled public Boolean isRequired;
        @AuraEnabled public Decimal order;
        @AuraEnabled public String type;
        @AuraEnabled public Id questionnaireId;
    }
    
    /**
     * @description Wrapper for service offering details
     */
    public class ServiceDetailWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String service;
        @AuraEnabled public String serviceName;
        @AuraEnabled public String serviceCategory;
        @AuraEnabled public Boolean isGatePass;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public List<QuestionnaireWrapper> questionnaire;
    }
    
    /**
     * @description LWC questionnaire request payload
     */
    public class LwcQuestionnaireRequest {
        public Case caseRecord;
        public List<LwcQuestionResponse> responses;
        public Id constituentRoleId;
    }
    
    /**
     * @description Internal holder for file uploads tied to questionnaire responses
     */
    private class QuestionnaireFileWork {
        public Ken_Questionnaire_Parameter_Response__c response;
        public String fileName;
        public String fileData;
    }
    
    /**
     * @description LWC questionnaire response payload
     */
    public class LwcQuestionResponse {
        public Id questionId;
        public String value;
        public String fileData;
        public String fileName;
        public String fileType;
    }
    
    /**
     * @description Wrapper for Case Comment
     */
    public class CaseCommentWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String author;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String body;
        @AuraEnabled public Boolean isCurrentUser;
    }

    public class QuestionResponseWrapper {
        @AuraEnabled public String question;
        @AuraEnabled public String response;
        @AuraEnabled public String questionType;
        @AuraEnabled public String questionnaireName;
        @AuraEnabled public String fileVersionId;
        @AuraEnabled public String contentDocumentId;
    }

    /**
     * @description Option for the Get Help "issue type" dropdown. Each option is a
     *              Service Offering: the label is shown in the dropdown (and stored as
     *              text in the Case description) and serviceOfferingId is set on the
     *              created Case so it auto-routes to the owner configured on that
     *              offering via routeCaseOwnerByService.
     */
    public class IssueTypeOption {
        @AuraEnabled public Id serviceId;
        @AuraEnabled public String label;
        @AuraEnabled public Id serviceOfferingId;
    }

    /**
     * @description Fetch the configurable "issue type" options for the Get Help modal.
     *              Returns the Service Offerings that belong to Student-targeted
     *              Ken_Service__c records — one option per offering. Selecting one
     *              links the Case to that offering (Service_Offering__c) so it
     *              auto-routes to an owner. Admins drive the dropdown by adding/removing
     *              offerings under Student-targeted services — no code change required.
     * @return List of IssueTypeOption (one per offering), ordered by offering Name.
     */
    @AuraEnabled(cacheable = true)
    public static List<IssueTypeOption> getIssueTypes() {
        if (!Schema.sObjectType.Ken_Service__c.isAccessible()
            || !Schema.sObjectType.Ken_Service_Offering__c.isAccessible()) {
            return new List<IssueTypeOption>();
        }
        String student = KenSnSConstants.TARGET_AUDIENCE_STUDENT;

        List<Ken_Service__c> services = [
            SELECT Id
            FROM Ken_Service__c
            WHERE Target_Audience__c INCLUDES (:student)
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];
        if (services.isEmpty()) {
            return new List<IssueTypeOption>();
        }
        Set<Id> serviceIds = (new Map<Id, Ken_Service__c>(services)).keySet();

        List<IssueTypeOption> result = new List<IssueTypeOption>();
        for (Ken_Service_Offering__c o : [
            SELECT Id, Name, Service__c
            FROM Ken_Service_Offering__c
            WHERE Service__c IN :serviceIds
            WITH SECURITY_ENFORCED
            ORDER BY Name
            LIMIT 200
        ]) {
            IssueTypeOption opt = new IssueTypeOption();
            opt.serviceId = o.Service__c;
            opt.label = o.Name;
            opt.serviceOfferingId = o.Id;
            result.add(opt);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<QuestionResponseWrapper> getCaseQuestionnaireResponses(Id caseId) {
        if (String.isBlank(caseId)) return new List<QuestionResponseWrapper>();
        if (!Schema.sObjectType.Ken_Questionnaire_Parameter_Response__c.isAccessible()) {
            return new List<QuestionResponseWrapper>();
        }
        List<Ken_Questionnaire_Parameter_Response__c> responses = [
            SELECT Id, Response__c,
                Questionnaire_Parameter__r.Question_Label__c,
                Questionnaire_Parameter__r.Question_Type__c,
                Questionnaire_Parameter__r.Questionnaire__r.Name
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Case__c = :caseId
            WITH SECURITY_ENFORCED
            ORDER BY Questionnaire_Parameter__r.Questionnaire__r.Name NULLS LAST,
                     Questionnaire_Parameter__r.Order__c NULLS LAST
            LIMIT 200
        ];

        List<QuestionResponseWrapper> result = new List<QuestionResponseWrapper>();
        Map<Id, QuestionResponseWrapper> fileResponseMap = new Map<Id, QuestionResponseWrapper>();

        for (Ken_Questionnaire_Parameter_Response__c r : responses) {
            QuestionResponseWrapper w = new QuestionResponseWrapper();
            w.question = r.Questionnaire_Parameter__r.Question_Label__c;
            w.response = r.Response__c;
            w.questionType = r.Questionnaire_Parameter__r.Question_Type__c;
            w.questionnaireName = r.Questionnaire_Parameter__r.Questionnaire__r.Name;
            result.add(w);
            if (w.questionType != null && w.questionType.toLowerCase() == 'file upload') {
                fileResponseMap.put(r.Id, w);
            }
        }

        if (!fileResponseMap.isEmpty()) {
            Map<Id, Id> entityToDoc = new Map<Id, Id>();
            for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :fileResponseMap.keySet()
            ]) {
                entityToDoc.put(cdl.LinkedEntityId, cdl.ContentDocumentId);
            }
            if (!entityToDoc.isEmpty()) {
                Map<Id, Id> docToVersion = new Map<Id, Id>();
                for (ContentVersion cv : [
                    SELECT Id, ContentDocumentId
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :entityToDoc.values()
                    AND IsLatest = true
                ]) {
                    docToVersion.put(cv.ContentDocumentId, cv.Id);
                }
                for (Id responseId : entityToDoc.keySet()) {
                    Id docId = entityToDoc.get(responseId);
                    if (docToVersion.containsKey(docId) && fileResponseMap.containsKey(responseId)) {
                        fileResponseMap.get(responseId).fileVersionId = docToVersion.get(docId);
                        fileResponseMap.get(responseId).contentDocumentId = docId;
                    }
                }
            }
        }

        return result;
    }

    /**
     * @description Fetch FAQs grouped by category
     * @return List of FAQCategoryWrapper records
     */
    @AuraEnabled(cacheable=true)
    public static List<FAQCategoryWrapper> getFAQs() {
        if (!Schema.sObjectType.Ken_FAQ__c.isAccessible()) {
            return new List<FAQCategoryWrapper>();
        }
        
        List<Ken_FAQ__c> faqs = [
            SELECT Id, Question_Label__c, Answer__c, Category__c,
                   Like_Count__c, Dislike_Count__c
            FROM Ken_FAQ__c
            WITH SECURITY_ENFORCED
            ORDER BY Category__c
            LIMIT 200
        ];
        
        
        return buildFaqResponse(faqs);
    }
    
    
    @AuraEnabled
    public static VoteResult updateFaqVote(Id faqId, String oldReaction, String newReaction) {
        if (!Schema.sObjectType.Ken_FAQ__c.isUpdateable()) {
            throw new AuraHandledException('No permission to update FAQs.');
        }
        
        // Lock row to avoid race conditions
        Ken_FAQ__c faq = [
                SELECT Id, Like_Count__c, Dislike_Count__c
                FROM Ken_FAQ__c
                WHERE Id = :faqId
                FOR UPDATE
            ];
        
        Integer likeDelta = 0;
        Integer dislikeDelta = 0;
        
        // normalize
        oldReaction = String.isBlank(oldReaction) ? null : oldReaction;
        newReaction = String.isBlank(newReaction) ? null : newReaction;
        
        // Compute deltas
        // old -> new
        if (oldReaction == 'up') likeDelta -= 1;
        if (oldReaction == 'down') dislikeDelta -= 1;
        
        if (newReaction == 'up') likeDelta += 1;
        if (newReaction == 'down') dislikeDelta += 1;
        
        Integer currentLikes = (faq.Like_Count__c == null) ? 0 : Integer.valueOf(faq.Like_Count__c);
        Integer currentDislikes = (faq.Dislike_Count__c == null) ? 0 : Integer.valueOf(faq.Dislike_Count__c);
        
        Integer nextLikes = Math.max(0, currentLikes + likeDelta);
        Integer nextDislikes = Math.max(0, currentDislikes + dislikeDelta);
        
        faq.Like_Count__c = nextLikes;
        faq.Dislike_Count__c = nextDislikes;
        
        update faq;
        
        VoteResult res = new VoteResult();
        res.likeCount = nextLikes;
        res.dislikeCount = nextDislikes;
        return res;
    }
    
    public class VoteResult {
        @AuraEnabled public Integer likeCount;
        @AuraEnabled public Integer dislikeCount;
    }
    
    /**
     * @description Retrieves the full name of the currently logged-in user
     *              from the Salesforce user context.
     *
     * @return Full name of the current user.
     */
    @AuraEnabled(cacheable = true)
    public static String getCurrentUserFullName() {
        return UserInfo.getName();
    }
    
    @AuraEnabled(cacheable=true)
    public static Boolean isNeedHelpVisible() {
        return KenSnSConstants.isNeedHelpVisible();
    }

    private static List<FAQCategoryWrapper> buildFaqResponse(List<Ken_FAQ__c> faqs) {
        Map<String, FAQCategoryWrapper> grouped = new Map<String, FAQCategoryWrapper>();
        
        for (Ken_FAQ__c faq : faqs) {
            if (!grouped.containsKey(faq.Category__c)) {
                FAQCategoryWrapper cat = new FAQCategoryWrapper();
                cat.category = faq.Category__c;
                cat.questions = new List<FAQQuestionWrapper>();
                grouped.put(faq.Category__c, cat);
            }
            
            FAQQuestionWrapper q = new FAQQuestionWrapper();
            q.id = faq.Id;
            q.question = faq.Question_Label__c;
            q.answer = faq.Answer__c;
            q.likeCount = (faq.Like_Count__c == null) ? 0 : Integer.valueOf(faq.Like_Count__c);
            q.dislikeCount = (faq.Dislike_Count__c == null) ? 0 : Integer.valueOf(faq.Dislike_Count__c);
            grouped.get(faq.Category__c).questions.add(q);
        }
        
        return grouped.values();
    }
    
    /**
     * @description Fetch logged-in user's service and support case history
     * @return HistoryResponse containing case history
     */
    @AuraEnabled(cacheable = false)
    public static HistoryResponse getUserHistory(Id constituentRoleId) {
        HistoryResponse response = new HistoryResponse();

        if (!Schema.sObjectType.Case.isAccessible()) {
            return response;
        }

        List<Case> cases = fetchUserCases();
        Map<Id, ContentVersion> files = getLatestFilesByCase(cases);
        Map<Id, ContentVersion> responseFiles = getLatestFilesFromResponses(cases);
        populateHistory(response, cases, files, responseFiles);

        return response;
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static List<Case> fetchUserCases() {
        Id currentUserId = UserInfo.getUserId();
        return [
            SELECT Id, Subject, CaseNumber, Description,
                Status, CreatedDate, ClosedDate,
                RecordType.Name, RecordType.DeveloperName,
                Service_Category__c,
                Service_Offering__r.Name, Rating__c, Feedback__c
            FROM Case
            WHERE CreatedById = :currentUserId
            AND RecordType.DeveloperName IN (
                :KenSnSConstants.CASE_RECORD_TYPE_SERVICE,
                :KenSnSConstants.CASE_RECORD_TYPE_SUPPORT,
                :KenSnSConstants.CASE_RECORD_TYPE_GATE_PASS
            )
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }
    
    private static void populateHistory(
        HistoryResponse response,
        List<Case> cases,
        Map<Id, ContentVersion> files,
        Map<Id, ContentVersion> responseFiles
    ) {
        Map<Id, StatusDateInfo> statusDates = getStatusDates(cases);
        
        for (Case c : cases) {
            HistoryItem item = new HistoryItem();
            item.id = c.CaseNumber;
            item.caseId = String.valueOf(c.Id);
            item.title = c.Subject;
            item.subject = c.Subject;
            item.status = c.Status;
            item.description = c.Description;
            item.createdDate = c.CreatedDate;
            item.closedDate = c.ClosedDate;
            item.serviceOfferingName = c.Service_Offering__r != null ? c.Service_Offering__r.Name : null;
            item.recordType = c.RecordType.Name;
            item.hasFeedbackSubmitted = (c.Rating__c != null || String.isNotBlank(c.Feedback__c));
            item.rating = c.Rating__c;
            item.feedback = c.Feedback__c;
            
            
            if (statusDates.containsKey(c.Id)) {
                StatusDateInfo dates = statusDates.get(c.Id);
                item.rejectedDate = dates.rejectedDate;
                if (item.closedDate == null && dates.closedDate != null) {
                    item.closedDate = dates.closedDate;
                }
                if (item.canceledDate == null && dates.canceledDate != null) {
                    item.canceledDate = dates.canceledDate;
                }
            }
            
            if (files.containsKey(c.Id)) {
                ContentVersion cv = files.get(c.Id);
                item.attachmentName = cv.Title;
                item.attachment = buildFileUrl(cv.Id);
            } else if (responseFiles.containsKey(c.Id)) {
                ContentVersion cv = responseFiles.get(c.Id);
                item.attachmentName = cv.Title;
                item.attachment = buildFileUrl(cv.Id);
            }
            
            if (c.RecordType.DeveloperName == KenSnSConstants.CASE_RECORD_TYPE_SERVICE
                || KenSnSConstants.SERVICE_CATEGORY_GATE_PASS.equalsIgnoreCase(c.Service_Category__c)) {
                response.serviceHistory.add(item);
            } else {
                response.supportHistory.add(item);
            }
        }
    }
    
    /**
     * @description Fetch detailed information for a single case
     * @param caseId Case Id
     * @return CaseDetailResponse
     */
    @AuraEnabled(cacheable = false)
    public static CaseDetailResponse getCaseDetail(Id caseId) {
        if (caseId == null || !Schema.sObjectType.Case.isAccessible()) {
            return null;
        }
        
        Case c = fetchCase(caseId);
        if (c == null) {
            return null;
        }
        List<Ken_Questionnaire_Parameter_Response__c> responses = fetchCaseResponses(caseId);
        ContentVersion latest = getLatestContentVersion(caseId);

        // If no case attachment, try questionnaire file upload
        if (latest == null) {
            latest = getLatestFileFromResponses(responses);
        }
        List<CaseCommentWrapper> comments = fetchCaseComments(caseId);
        
        return buildCaseDetailResponse(c, responses, latest, comments);
    }

    /**
     * @description Create a public case comment from the Experience Cloud portal.
     * @param caseId Case Id on which to create the comment.
     * @param commentBody Free-text comment entered by the portal user.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    @AuraEnabled
    public static void addCaseComment(Id caseId, String commentBody) {
        if (caseId == null || String.isBlank(commentBody)) {
            throw new AuraHandledException('Comment text is required.');
        }

        if (!isCurrentUserCase(caseId)) {
            throw new AuraHandledException('You do not have access to this case.');
        }

        String normalizedBody = commentBody.trim();
        if (normalizedBody.length() > 4000) {
            throw new AuraHandledException('Comment can be up to 4000 characters only.');
        }

        CaseComment newComment = new CaseComment(
            ParentId = caseId,
            IsPublished = true
        );
        newComment.CommentBody = normalizedBody;
        if (hasCaseCommentRichTextField()) {
            newComment.put('CommentBodyRichtext', normalizedBody);
        }
        insert newComment;
    }
    
    /**
     * @description Mark a case as Closed
     * @param caseId Case Id to close
     */
    @AuraEnabled
    public static void closeCase(Id caseId) {
        if (caseId == null) {
            return;
        }
        
        
        if (!Schema.sObjectType.Case.isAccessible()) {
            throw new AuraHandledException('INSUFFICIENT_ACCESS');
        }
        
        if (!isCurrentUserCase(caseId)) {
            throw new AuraHandledException('INSUFFICIENT_ACCESS');
        }

        Case c = [
            SELECT Id, Status
            FROM Case
            WHERE Id = :caseId
            AND CreatedById = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!Schema.sObjectType.Case.isUpdateable()) {
            throw new AuraHandledException('INSUFFICIENT_UPDATE_ACCESS');
        }
        c.Status = KenSnSConstants.CASE_STATUS_CANCELLED;
        update c;
    }
    
    private static Case fetchCase(Id caseId) {
        List<Case> matchingCases = [
            SELECT Id, CaseNumber, Subject, Description, Status,
            CreatedDate, RecordType.Name,
            Service_Offering__c, Service_Offering__r.Name,
            Rating__c, Feedback__c
            FROM Case
            WHERE Id = :caseId
            AND CreatedById = :UserInfo.getUserId()
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return matchingCases.isEmpty() ? null : matchingCases[0];
    }
    
    private static List<Ken_Questionnaire_Parameter_Response__c> fetchCaseResponses(Id caseId) {
        if (!Schema.sObjectType.Ken_Questionnaire_Parameter_Response__c.isAccessible()) {
            return new List<Ken_Questionnaire_Parameter_Response__c>();
        }
        
        return [
            SELECT Id, Response__c,
                Questionnaire_Parameter__r.Question_Label__c,
                Questionnaire_Parameter__r.Question_Type__c
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Case__c = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];
    }
    
    private static CaseDetailResponse buildCaseDetailResponse(
        Case c,
    List<Ken_Questionnaire_Parameter_Response__c> responses,
    ContentVersion latest,
    List<CaseCommentWrapper> comments
    ) {
        CaseDetailResponse resp = new CaseDetailResponse();
        resp.caseId = c.Id;
        resp.caseNumber = c.CaseNumber;
        resp.subject = c.Subject;
        resp.description = c.Description;
        resp.status = c.Status;
        resp.createdDate = c.CreatedDate;
        resp.recordType = c.RecordType.Name;
        resp.serviceOfferingId = c.Service_Offering__c;
        resp.serviceOfferingName = c.Service_Offering__r != null ? c.Service_Offering__r.Name : null;
        resp.responses = responses;
        resp.comments = comments;
        resp.hasFeedbackSubmitted = (c.Rating__c != null || String.isNotBlank(c.Feedback__c));
        
        if (latest != null) {
            resp.attachmentName = latest.Title;
            resp.attachmentUrl = buildFileUrl(latest.Id);
        }
        
        return resp;
    }
    
    /**
     * @description Retrieves case comments for the specified case and maps
     *              them into wrapper objects for UI consumption.
     *
     * @param caseId Id of the Case whose comments need to be fetched.
     * @return List of CaseCommentWrapper records ordered by creation date.
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static List<CaseCommentWrapper> fetchCaseComments(Id caseId) {
        List<CaseCommentWrapper> result = new List<CaseCommentWrapper>();
        
        if (!Schema.sObjectType.CaseComment.isAccessible()) {
            return result;
        }

        String queryString =
            'SELECT Id, CreatedDate, CreatedById, CreatedBy.Name, IsPublished, CommentBody' +
            (hasCaseCommentRichTextField() ? ', CommentBodyRichtext' : '') +
            ' FROM CaseComment' +
            ' WHERE ParentId = :caseId' +
            ' AND IsPublished = true' +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY CreatedDate ASC' +
            ' LIMIT 200';

        for (SObject row : Database.query(queryString)) {
            result.add(buildCaseCommentWrapper(row));
        }
        
        return result;
    }

    private static CaseCommentWrapper buildCaseCommentWrapper(SObject row) {
        CaseCommentWrapper wrap = new CaseCommentWrapper();
        SObject createdBy = row.getSObject('CreatedBy');

        wrap.id = (Id) row.get('Id');
        wrap.author = createdBy != null ? (String) createdBy.get('Name') : 'Support Team';
        wrap.createdDate = (Datetime) row.get('CreatedDate');
        wrap.body = getCaseCommentDisplayBody(row);
        wrap.isCurrentUser = (Id) row.get('CreatedById') == UserInfo.getUserId();
        return wrap;
    }

    private static String getCaseCommentDisplayBody(SObject row) {
        if (hasCaseCommentRichTextField()) {
            String richTextBody = (String) row.get('CommentBodyRichtext');
            if (String.isNotBlank(richTextBody)) {
                return richTextBody;
            }
        }

        return (String) row.get('CommentBody');
    }

    private static Boolean hasCaseCommentRichTextField() {
        return Schema.SObjectType.CaseComment.fields.getMap().containsKey('CommentBodyRichtext');
    }

    private static Boolean isCurrentUserCase(Id caseId) {
        if (caseId == null) {
            return false;
        }

        return [
            SELECT COUNT()
            FROM Case
            WHERE Id = :caseId
            AND CreatedById = :UserInfo.getUserId()
        ] > 0;
    }
    
    private class StatusDateInfo {
        public Datetime closedDate;
        public Datetime rejectedDate;
        public Datetime canceledDate;
    }
   @testvisible 
    private static Map<Id, StatusDateInfo> getStatusDates(List<Case> cases) {
        Map<Id, StatusDateInfo> result = new Map<Id, StatusDateInfo>();
        
        if (cases.isEmpty()) {
            return result;
        }

        if (!Schema.sObjectType.CaseHistory.isAccessible()) {
            return result;
        }

        Set<Id> caseIds = new Set<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }
        
        for (CaseHistory ch : [
            SELECT CaseId, CreatedDate, Field, NewValue
            FROM CaseHistory
            WHERE CaseId IN :caseIds
            AND Field = 'Status'
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            if (ch.NewValue == null) {
                continue;
            }
            
            String newStatus = String.valueOf(ch.NewValue).toLowerCase();
            if (!result.containsKey(ch.CaseId)) {
                result.put(ch.CaseId, new StatusDateInfo());
            }
            
            StatusDateInfo info = result.get(ch.CaseId);
            
            if (newStatus.contains('rejected') && info.rejectedDate == null) {
                info.rejectedDate = ch.CreatedDate;
            }
            
            if (newStatus.contains('closed') && info.closedDate == null) {
                info.closedDate = ch.CreatedDate;
            }

            if (newStatus.contains('cancel')) {
                info.canceledDate = ch.CreatedDate;
            }
        }
        
        return result;
    }
    
    /**
     * @description Fetch unique services filtered by the constituent's role target audience.
     *              Returns Ken_Service__c records directly — one per service, no duplicates.
     */
    @AuraEnabled(cacheable=true)
    public static String getGatePassCategoryValue() {
        return KenSnSConstants.SERVICE_CATEGORY_GATE_PASS;
    }

    @AuraEnabled(cacheable=true)
    public static List<Ken_Service__c> getServices(String constituentRoleId) {
        if (!Schema.sObjectType.Ken_Service__c.isAccessible()) {
            return new List<Ken_Service__c>();
        }

        String audienceType = resolveUserAudienceType();

        if (String.isNotBlank(audienceType)) {
            String all = KenSnSConstants.TARGET_AUDIENCE_ALL;
            return [
                SELECT Id, Name, Description__c, Service_Category__c
                FROM Ken_Service__c
                WHERE Target_Audience__c INCLUDES (:audienceType)
                   OR Target_Audience__c INCLUDES (:all)
                ORDER BY Name
                LIMIT 200
            ];
        }
        return [
            SELECT Id, Name, Description__c, Service_Category__c
            FROM Ken_Service__c
            ORDER BY Name
            LIMIT 200
        ];
    }

    /**
     * @description Resolve the first service Id matching the given service Name.
     *              Used by external portal pages (e.g. Hostel residence allocation) to
     *              deep-link "Get Help" into the SnS Request-Service detail page without
     *              hardcoding a service Id across orgs.
     * @param category Service name to match on Ken_Service__c.Name
     * @return The Id of the first matching service, or null when none exists / not accessible
     */
    @AuraEnabled(cacheable = true)
    public static Id getServiceIdByCategory(String category) {
        if (String.isBlank(category) || !Schema.sObjectType.Ken_Service__c.isAccessible()) {
            return null;
        }
        List<Ken_Service__c> services = [
            SELECT Id
            FROM Ken_Service__c
            WHERE Service_Category__c = :category
            WITH SECURITY_ENFORCED
            ORDER BY Name
            LIMIT 1
        ];
        return services.isEmpty() ? null : services[0].Id;
    }

    /**
     * @description Fetch service offerings filtered by the running user's target audience.
     *              Offerings with no Target_Audience__c are visible to all. Filtering is
     *              based on the offering's own Target_Audience__c (independent of the
     *              parent service's Target_Audience__c).
     * @param constituentRoleId ConstituentRole record Id from the portal session
     * @return List of service offerings matching the user's audience
     */
    @AuraEnabled(cacheable = true)
    public static List<Ken_Service_Offering__c> getServiceOfferings(String constituentRoleId) {
        if (!Schema.sObjectType.Ken_Service_Offering__c.isAccessible()) {
            return new List<Ken_Service_Offering__c>();
        }

        String audienceType = resolveUserAudienceType();

        if (String.isNotBlank(audienceType)) {
            String all = KenSnSConstants.TARGET_AUDIENCE_ALL;
            return [
                SELECT Id, Service__c, Service__r.Name, Service__r.Description__c,
                       Name, Questionnaire__c
                FROM Ken_Service_Offering__c
                WHERE Target_Audience__c INCLUDES (:audienceType)
                   OR Target_Audience__c INCLUDES (:all)
                WITH SECURITY_ENFORCED
                ORDER BY Name
                LIMIT 200
            ];
        }
        return [
            SELECT Id, Service__c, Service__r.Name, Service__r.Description__c,
                   Name, Questionnaire__c
            FROM Ken_Service_Offering__c
            WITH SECURITY_ENFORCED
            ORDER BY Name
            LIMIT 200
        ];
    }

    /**
     * @description Determines the Target Audience type for the running user by combining
     *              their Experience Site network (matched against custom setting network IDs)
     *              and ConstituentRole.RoleType.
     *
     *              Student/Faculty/Alumni portal: returns the user's RoleType ('Student',
     *              'Faculty', or 'Alumni') which maps directly to Target_Audience__c values.
     *
     *              Admission portal + no constituent role: returns 'Admission'.
     *
     *              Internal users and unrecognised portals: returns null (show all, no filter).
     *              Network IDs are configured in Ken_Support_Services_Parameters__c — no
     *              hardcoding of site names or role values in this method.
     */
    private static String resolveUserAudienceType() {
        try {
            Id networkId = Network.getNetworkId();
            if (networkId == null) return null;
            List<Network> nets = [SELECT Name FROM Network WHERE Id = :networkId LIMIT 1];
            if (nets.isEmpty()) return null;
            String currentSiteName = nets[0].Name;
            if (String.isBlank(currentSiteName)) return null;
            Ken_Support_Services_Parameters__c s = Ken_Support_Services_Parameters__c.getOrgDefaults();
            if (s == null) return null;
            if (String.isNotBlank(s.Student_Faculty_Portal_Network_Id__c) &&
                currentSiteName.equalsIgnoreCase(s.Student_Faculty_Portal_Network_Id__c)) {
                String roleType = resolveConstituentRoleType();
                if (KenSnSConstants.ROLE_TYPE_STUDENT.equalsIgnoreCase(roleType) ||
                    KenSnSConstants.ROLE_TYPE_FACULTY.equalsIgnoreCase(roleType) ||
                    KenSnSConstants.ROLE_TYPE_ALUMNI.equalsIgnoreCase(roleType) ||
                    KenSnSConstants.ROLE_TYPE_SECURITY.equalsIgnoreCase(roleType)) {
                    return roleType;
                }
                return null;
            }
            if (String.isNotBlank(s.Admission_Portal_Network_Id__c) &&
                currentSiteName.equalsIgnoreCase(s.Admission_Portal_Network_Id__c)) {
                String roleType = resolveConstituentRoleType();
                return String.isBlank(roleType) ? KenSnSConstants.TARGET_AUDIENCE_ADMISSION : null;
            }
        } catch (Exception ignored) {}
        return null;
    }

    /**
     * @description Looks up the ConstituentRole.RoleType for the running user by checking
     *              their AccountId, ContactId, and PersonContactId. Returns null when no
     *              constituent role is found (e.g., admission applicants with no role yet).
     */
    private static String resolveConstituentRoleType() {
        try {
            Set<Id> personIds = new Set<Id>();
            List<User> users = [
                SELECT AccountId, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
            ];
            if (!users.isEmpty()) {
                if (users[0].AccountId != null) personIds.add(users[0].AccountId);
                if (users[0].ContactId != null) personIds.add(users[0].ContactId);
                if (users[0].AccountId != null) {
                    List<Account> accs = [
                        SELECT PersonContactId FROM Account WHERE Id = :users[0].AccountId LIMIT 1
                    ];
                    if (!accs.isEmpty() && accs[0].PersonContactId != null) {
                        personIds.add(accs[0].PersonContactId);
                    }
                }
            }
            if (!personIds.isEmpty()) {
                List<ConstituentRole> roles = [
                    SELECT RoleType FROM ConstituentRole
                    WHERE PersonId IN :personIds
                    ORDER BY CreatedDate DESC LIMIT 1
                ];
                if (!roles.isEmpty()) return roles[0].RoleType;
            }
        } catch (Exception ignored) {}
        return null;
    }

    
    /**
     * @description Fetch service offering details with questionnaire
     * @param serviceId Service Id
     * @return List of ServiceDetailWrapper
     */
    @AuraEnabled(cacheable = true)
    public static List<ServiceDetailWrapper> getServiceOfferingDetail(String serviceId) {
        if (String.isBlank(serviceId)) {
            return new List<ServiceDetailWrapper>();
        }

        String audienceType = resolveUserAudienceType();
        List<Ken_Service_Offering__c> offerings;
        if (String.isNotBlank(audienceType)) {
            String all = KenSnSConstants.TARGET_AUDIENCE_ALL;
            offerings = [
                SELECT Id, Name, Service__c, Service__r.Name,
                Service__r.Description__c, Service__r.Service_Category__c, Questionnaire__c
                FROM Ken_Service_Offering__c
                WHERE Service__c = :serviceId
                  AND (Target_Audience__c INCLUDES (:audienceType)
                    OR Target_Audience__c INCLUDES (:all))
                WITH SECURITY_ENFORCED
                ORDER BY Name
                LIMIT 200
            ];
        } else {
            offerings = [
                SELECT Id, Name, Service__c, Service__r.Name,
                Service__r.Description__c, Service__r.Service_Category__c, Questionnaire__c
                FROM Ken_Service_Offering__c
                WHERE Service__c = :serviceId
                WITH SECURITY_ENFORCED
                ORDER BY Name
                LIMIT 200
            ];
        }
        
        if (offerings.isEmpty()) {
            return new List<ServiceDetailWrapper>();
        }
        
        Map<Id, List<QuestionnaireWrapper>> questionnaireMap = buildQuestionnaireMap(offerings);
        
        return buildServiceDetailWrappers(offerings, questionnaireMap);
    }
    
    private static List<ServiceDetailWrapper> buildServiceDetailWrappers(List<Ken_Service_Offering__c> offerings, Map<Id, List<QuestionnaireWrapper>> questionnaireMap) {
        List<ServiceDetailWrapper> result = new List<ServiceDetailWrapper>();
        
        for (Ken_Service_Offering__c offering : offerings) {
            ServiceDetailWrapper detail = new ServiceDetailWrapper();
            detail.id = offering.Id;
            detail.service = offering.Service__c;
            detail.serviceName = offering.Service__r.Name;
            detail.serviceCategory = offering.Service__r.Service_Category__c;
            detail.isGatePass = KenSnSConstants.SERVICE_CATEGORY_GATE_PASS.equals(offering.Service__r.Service_Category__c);
            detail.name = offering.Name;
            detail.description = offering.Service__r.Description__c;
            
            if (offering.Questionnaire__c != null &&
            questionnaireMap.containsKey(offering.Questionnaire__c)) {
                detail.questionnaire = questionnaireMap.get(offering.Questionnaire__c);
            } else {
                detail.questionnaire = new List<QuestionnaireWrapper>();
            }
            
            result.add(detail);
        }
        
        return result;
    }
    
    private static Map<Id, List<QuestionnaireWrapper>> buildQuestionnaireMap(List<Ken_Service_Offering__c> offerings) {
        Set<Id> questionnaireIds = new Set<Id>();
        
        for (Ken_Service_Offering__c offering : offerings) {
            if (offering.Questionnaire__c != null) {
                questionnaireIds.add(offering.Questionnaire__c);
            }
        }
        
        Map<Id, List<QuestionnaireWrapper>> questionnaireMap = new Map<Id, List<QuestionnaireWrapper>>();
        
        if (questionnaireIds.isEmpty()) {
            return questionnaireMap;
        }
        
        for (Ken_Questionnaire_Parameter__c qp : [
            SELECT Id, Question_Label__c, MCQ_Options__c,
            Is_Required__c, Order__c, Question_Type__c, Questionnaire__c
            FROM Ken_Questionnaire_Parameter__c
            WHERE Questionnaire__c IN :questionnaireIds WITH SECURITY_ENFORCED
            ORDER BY Order__c
        ]) {
            if (!questionnaireMap.containsKey(qp.Questionnaire__c)) {
                questionnaireMap.put(qp.Questionnaire__c, new List<QuestionnaireWrapper>());
            }
            
            QuestionnaireWrapper qWrap = new QuestionnaireWrapper();
            qWrap.id = qp.Id;
            qWrap.label = qp.Question_Label__c;
            qWrap.options = qp.MCQ_Options__c;
            qWrap.isRequired = qp.Is_Required__c;
            qWrap.order = qp.Order__c;
            qWrap.type = qp.Question_Type__c;
            qWrap.questionnaireId = qp.Questionnaire__c;
            
            questionnaireMap.get(qp.Questionnaire__c).add(qWrap);
        }
        
        return questionnaireMap;
    }
    
    /**
     * @description Save questionnaire parameter responses and attachments
     * @param payload LWC questionnaire request
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    @testvisible
    private static void saveQuestionnaireResponses(LwcQuestionnaireRequest payload) {
        if (payload.responses == null || payload.responses.isEmpty()) {
            return;
        }
        
        List<Ken_Questionnaire_Parameter_Response__c> paramResponses = new List<Ken_Questionnaire_Parameter_Response__c>();
        List<QuestionnaireFileWork> pendingFiles = new List<QuestionnaireFileWork>();
        
        User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        
        for (LwcQuestionResponse q : payload.responses) {
            String responseValue = q.value;
            String fileName;
            
            if (String.isNotBlank(q.fileData)) {
                String ext = String.isNotBlank(q.fileType) ? q.fileType.toLowerCase() : 'pdf';
                fileName = String.isNotBlank(q.fileName) ? q.fileName : 'Questionnaire Attachment.' + ext;
                responseValue = 'Attachment uploaded: ' + fileName;
            }
            
            Ken_Questionnaire_Parameter_Response__c resp = new Ken_Questionnaire_Parameter_Response__c(
                Case__c = payload.caseRecord.Id,
            Questionnaire_Parameter__c = q.questionId,
            Response_Category__c = 'Case',
            Response__c = responseValue,
            Respondent__c = currentUser.AccountId
                );
            paramResponses.add(resp);
            
            if (String.isNotBlank(q.fileData)) {
                QuestionnaireFileWork work = new QuestionnaireFileWork();
                work.response = resp;
                work.fileName = fileName;
                work.fileData = q.fileData;
                pendingFiles.add(work);
            }
        }
        
        if (!paramResponses.isEmpty()) {
            insert paramResponses;
        }
        
        if (!pendingFiles.isEmpty()) {
            List<ContentVersion> files = new List<ContentVersion>();
            for (QuestionnaireFileWork work : pendingFiles) {
                if (work.response != null && work.response.Id != null && String.isNotBlank(work.fileData)) {
                    files.add(new ContentVersion(
                        Title = work.fileName,
                        PathOnClient = work.fileName,
                        VersionData = EncodingUtil.base64Decode(work.fileData),
                        FirstPublishLocationId = work.response.Id
                    ));
                }
            }
            if (!files.isEmpty()) {
                insert files;
                if (payload.caseRecord != null && payload.caseRecord.Id != null) {
                    List<Id> insertedDocIds = new List<Id>();
                    for (ContentVersion cv : [
                        SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :files
                    ]) {
                        insertedDocIds.add(cv.ContentDocumentId);
                    }
                    List<ContentDocumentLink> caseLinks = new List<ContentDocumentLink>();
                    for (Id docId : insertedDocIds) {
                        caseLinks.add(new ContentDocumentLink(
                            ContentDocumentId = docId,
                            LinkedEntityId = payload.caseRecord.Id,
                            ShareType = 'V',
                            Visibility = 'AllUsers'
                        ));
                    }
                    if (!caseLinks.isEmpty()) {
                        insert caseLinks;
                    }
                }
            }
        }
    }
    
    
    /**
     * @description Save questionnaire responses from LWC
     * @param requestPayloadJson JSON payload
     */
    @AuraEnabled
    public static void saveQuestionnaireFromLwc(String requestPayloadJson) {
        LwcQuestionnaireRequest payload = (LwcQuestionnaireRequest) JSON.deserialize(
            String.isNotBlank(requestPayloadJson) ? requestPayloadJson : '{}',
            LwcQuestionnaireRequest.class
        );

        if (payload == null || payload.caseRecord == null) {
            throw new AuraHandledException('Invalid request data');
        }

        createCaseFromPayload(payload);
        saveQuestionnaireResponses(payload);
        // Gate pass is created when staff sets Status = Resolved (not at submission time).
    }

    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static void createGatePassFromCase(LwcQuestionnaireRequest payload) {
        if (payload.caseRecord == null || payload.caseRecord.Id == null) return;

        // Re-query the case to get ContactId and AccountId reliably
        // (applyUserContext only sets AccountId on the in-memory object,
        //  ContactId is auto-populated by Salesforce on insert for Person Accounts)
        Case freshCase = [
            SELECT Id, ContactId, AccountId,
                   Account.PersonContactId
            FROM Case
            WHERE Id = :payload.caseRecord.Id
            LIMIT 1
        ];

        // Resolve contact: use ContactId first, fall back to PersonContactId
        Id resolvedContactId = freshCase.ContactId;
        if (resolvedContactId == null
            && freshCase.Account != null
            && freshCase.Account.PersonContactId != null) {
            resolvedContactId = freshCase.Account.PersonContactId;
        }

        if (resolvedContactId == null) return; // Cannot create gate pass without a contact

        // Read questionnaire responses to find exit/entry time answers
        List<Ken_Questionnaire_Parameter_Response__c> responses = [
            SELECT Response__c, Questionnaire_Parameter__r.Question_Label__c
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Case__c = :payload.caseRecord.Id
        ];

        Datetime exitTime  = null;
        Datetime entryTime = null;
        for (Ken_Questionnaire_Parameter_Response__c r : responses) {
            String label = r.Questionnaire_Parameter__r.Question_Label__c;
            if (String.isBlank(label) || String.isBlank(r.Response__c)) continue;
            if (label.containsIgnoreCase(KenSnSConstants.GATE_PASS_EXIT_LABEL_KEYWORD)) {
                exitTime = parseGatePassDateTime(r.Response__c);
            } else if (label.containsIgnoreCase(KenSnSConstants.GATE_PASS_ENTRY_LABEL_KEYWORD)) {
                entryTime = parseGatePassDateTime(r.Response__c);
            }
        }

        Ken_Gate_Pass__c gp = new Ken_Gate_Pass__c(
            GatePass_Request__c = payload.caseRecord.Id,
            Contact__c          = resolvedContactId,
            Account__c          = freshCase.AccountId,
            Exit_Time__c        = exitTime,
            Entry_Time__c       = entryTime,
            Email_Sent__c       = false
        );
        insert gp;

    }

    // Parses a Date-type questionnaire response.
    // Handles ISO format (YYYY-MM-DD) and DD/MM/YYYY or DD-MM-YYYY.
    public static Date parseGatePassDate(String value) {
        if (String.isBlank(value)) return null;
        try {
            String v = value.trim().replaceAll('/', '-');
            List<String> parts = v.split('-');
            if (parts.size() == 3) {
                Integer p0 = Integer.valueOf(parts[0].trim());
                Integer p1 = Integer.valueOf(parts[1].trim());
                Integer p2 = Integer.valueOf(parts[2].trim());
                // YYYY-MM-DD (ISO): first part is 4 digits
                if (p0 > 999) {
                    return Date.newInstance(p0, p1, p2);
                }
                // DD-MM-YYYY: last part is 4 digits
                return Date.newInstance(p2, p1, p0);
            }
        } catch (Exception ignored) {}
        return null;
    }

    // Parses time string from a Time-type questionnaire response.
    // Handles formats: "HH:MM", "HH:MM:SS", "HH:MM:SS.SSSZ", "HH:MM AM/PM"
    public static Time parseGatePassTime(String value) {
        if (String.isBlank(value)) return null;
        try {
            String cleaned = value.trim()
                .removeEnd('Z')
                .replaceAll('\\.\\d+$', ''); // strip milliseconds
            Boolean isPm = cleaned.toUpperCase().contains('PM');
            cleaned = cleaned.replaceAll('[AaPp][Mm]\\s*$', '').trim();
            List<String> parts = cleaned.split(':');
            if (parts.size() < 2) return null;
            Integer h = Integer.valueOf(parts[0].trim());
            Integer m = Integer.valueOf(parts[1].trim());
            if (isPm && h < 12) h += 12;
            if (!isPm && h == 12) h = 0;
            return Time.newInstance(h, m, 0, 0);
        } catch (Exception ignored) {}
        return null;
    }

    public static Datetime parseGatePassDateTime(String value) {
        if (String.isBlank(value)) return null;
        try {
            String trimmed = value.trim();
            List<String> parts = trimmed.split(' ');
            if (parts.size() < 2) return null;
            List<String> dateParts = parts[0].split('-');
            List<String> timeParts = parts[1].split(':');
            if (dateParts.size() < 3 || timeParts.size() < 2) return null;
            Integer day    = Integer.valueOf(dateParts[0]);
            Integer month  = Integer.valueOf(dateParts[1]);
            Integer year   = Integer.valueOf(dateParts[2]);
            Integer hour   = Integer.valueOf(timeParts[0]);
            Integer minute = Integer.valueOf(timeParts[1]);
            return Datetime.newInstance(Date.newInstance(year, month, day),
                                        Time.newInstance(hour, minute, 0, 0));
        } catch (Exception ignored) {
            return null;
        }
    }
    @testvisible
    private static void createCaseFromPayload(LwcQuestionnaireRequest payload) {
        if (!Schema.sObjectType.Case.isCreateable()) {
            throw new AuraHandledException('Insufficient access to create Case');
        }
        payload.caseRecord.RecordTypeId = resolveServiceCaseRecordTypeId(payload.caseRecord.Service_Offering__c);
        applyUserContext(payload.caseRecord, payload.constituentRoleId);

        // OwnerId is set by the before-insert trigger via routeCaseOwnerByService.
        // Assignment rule is not used — no useDefaultRule needed.
        Database.DMLOptions dmlOpts = new Database.DMLOptions();
        Database.SaveResult saveResult = Database.insert(payload.caseRecord, dmlOpts);
        if (!saveResult.isSuccess()) {
            throw new AuraHandledException(saveResult.getErrors()[0].getMessage());
        }
    }

    @testVisible
    private static Id getDefaultPortalAccountId() {
        // -----------------------------------------------------------------
        // The Alumni_Org_Parameters__c custom-setting fallback is removed
        // so the Support & Services module has zero dependency on the
        // Alumni module. Cases created without any natural Account context
        // (no constituent role, no User.AccountId, no User.Contact.AccountId)
        // will simply be saved without an AccountId — which is acceptable
        // for the S&S flow.
        //
        // To restore the fallback, uncomment the block below and add
        // Alumni_Org_Parameters__c back to package.xml.
        // -----------------------------------------------------------------
        // Alumni_Org_Parameters__c orgParameters = Alumni_Org_Parameters__c.getOrgDefaults();
        // if (orgParameters == null || String.isBlank(orgParameters.Account_Id__c)) {
        //     return null;
        // }
        // return (Id) orgParameters.Account_Id__c;
        return null;
    }

    // Resolves the best available Person Account and ConstituentRole for a case.
    // Prefer the explicit role passed from the portal session, then fall back to
    // the current user's Account/Contact context, and finally the org default account.
    private static void applyUserContext(Case c, Id passedConstituentRoleId) {
        Id resolvedRoleId = passedConstituentRoleId;
        Id personAccountId = getPersonAccountIdByConstituentRoleId(resolvedRoleId);

        User currentUser = [
            SELECT AccountId, ContactId, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (personAccountId == null) {
            personAccountId = currentUser.AccountId;
        }
        if (personAccountId == null && currentUser.ContactId != null && currentUser.Contact != null) {
            personAccountId = currentUser.Contact.AccountId;
        }

        if (personAccountId == null) {
            personAccountId = getDefaultPortalAccountId();
        }

        if (personAccountId != null) {
            c.AccountId = personAccountId;
        }

        if (resolvedRoleId == null && personAccountId != null) {
            resolvedRoleId = getActiveConstituentRoleId(personAccountId);
        }
        c.Constituent_Role__c = resolvedRoleId;
    }

    @testVisible
    private static Id getPersonAccountIdByConstituentRoleId(Id constituentRoleId) {
        if (constituentRoleId == null) {
            return null;
        }

        try {
            List<ConstituentRole> roles = [
                SELECT PersonId
                FROM ConstituentRole
                WHERE Id = :constituentRoleId
                LIMIT 1
            ];
            return roles.isEmpty() ? null : roles[0].PersonId;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'ConstituentRole account lookup failed for id=' + constituentRoleId + ': ' + e.getMessage());
            return null;
        }
    }

    @testVisible
    private static Id getActiveConstituentRoleId(Id personAccountId) {
        if (personAccountId == null) {
            return null;
        }

        // ConstituentRole.PersonId is polymorphic — in this org it points to
        // Contact (PersonContactId of the Person Account) for most rows and to
        // Account for some. Try every candidate Id derived from the account.
        Set<Id> possiblePersonIds = collectPossiblePersonIds(personAccountId);
        if (possiblePersonIds.isEmpty()) {
            return null;
        }

        try {
            // Prefer rows with Registration_Status__c = 'Registered'
            List<ConstituentRole> registeredRoles = [
                SELECT Id FROM ConstituentRole
                WHERE PersonId IN :possiblePersonIds
                AND Registration_Status__c = 'Registered'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!registeredRoles.isEmpty()) {
                return registeredRoles[0].Id;
            }

            // Fall back to the most recent role regardless of status
            List<ConstituentRole> anyRoles = [
                SELECT Id FROM ConstituentRole
                WHERE PersonId IN :possiblePersonIds
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!anyRoles.isEmpty()) {
                return anyRoles[0].Id;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ConstituentRole lookup failed: ' + e.getMessage());
        }

        return null;
    }

    /**
     * @description For a Person Account Id, return every Id that could appear
     *              on ConstituentRole.PersonId (the Account itself and its
     *              auto-generated PersonContactId). Used both by the single-
     *              record helper above and by the bulk handler called from
     *              the Case before-insert trigger.
     */
    @TestVisible
    private static Set<Id> collectPossiblePersonIds(Id accountId) {
        Set<Id> ids = new Set<Id>();
        if (accountId == null) return ids;
        ids.add(accountId);
        try {
            for (Account a : [SELECT PersonContactId FROM Account WHERE Id = :accountId LIMIT 1]) {
                if (a.PersonContactId != null) ids.add(a.PersonContactId);
            }
        } catch (Exception ignored) {}
        return ids;
    }

    /**
     * @description Create support "Need Help" case
     * @param serviceOfferingId Service Offering Id
     * @param subject Case subject
     * @param description Case description
     * @param fileName Attachment name
     * @param fileData Base64 file data
     * @return Case Id
     */
    @SuppressWarnings('PMD.ExcessiveParameterList')
    @AuraEnabled
    public static Id createNeedHelpCase(String serviceOfferingId, String subject, String description, String fileName, String fileData, Id constituentRoleId) {
        if (!Schema.sObjectType.Case.isCreateable()) {
            throw new AuraHandledException('Insufficient access to create Case');
        }

        Case c = new Case(
            Subject = String.isNotBlank(subject) ? subject : 'Need Help',
            Description = description,
            Origin = 'Web',
            Status = 'New',
            RecordTypeId = getCaseRecordTypeId(KenSnSConstants.CASE_RECORD_TYPE_SUPPORT),
            Service_Offering__c = serviceOfferingId
        );
        applyUserContext(c, constituentRoleId);

        // OwnerId is set by the before-insert trigger via routeCaseOwnerByService.
        // Assignment rule is not used — no useDefaultRule needed.
        Database.DMLOptions dmlOpts = new Database.DMLOptions();
        Database.SaveResult saveResult = Database.insert(c, dmlOpts);
        if (!saveResult.isSuccess()) {
            throw new AuraHandledException(saveResult.getErrors()[0].getMessage());
        }

        attachFileIfPresent(c.Id, fileName, fileData);
        return c.Id;
    }
    
    @SuppressWarnings('PMD.ApexCRUDViolation')
    @testvisible
    private static Map<Id, ContentVersion> getLatestFilesByCase(List<Case> cases) {
        Map<Id, ContentVersion> result = new Map<Id, ContentVersion>();
        Set<Id> caseIds = new Set<Id>();
        Map<Id, Id> docIdToCaseId = new Map<Id, Id>();

        for (Case c : cases) {
            caseIds.add(c.Id);
        }
        if (caseIds.isEmpty()) return result;

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :caseIds
            LIMIT 200
        ];
        
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) {
            docIds.add(l.ContentDocumentId);
            docIdToCaseId.put(l.ContentDocumentId, l.LinkedEntityId);
        }
        
        if (docIds.isEmpty()) {
            return result;
        }
        
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
        
        for (ContentVersion v : versions) {
            Id caseId = docIdToCaseId.get(v.ContentDocumentId);
            if (caseId != null && !result.containsKey(caseId)) {
                result.put(caseId, v);
            }
        }
        
        return result;
    }
    
    @SuppressWarnings('PMD.ApexCRUDViolation')
    @testvisible
    private static Map<Id, ContentVersion> getLatestFilesFromResponses(List<Case> cases) {
        Map<Id, ContentVersion> result = new Map<Id, ContentVersion>();
        if (cases.isEmpty()) {
            return result;
        }

        Set<Id> caseIds = new Set<Id>();
        for (Case c : cases) {
            caseIds.add(c.Id);
        }

        // Get response records for these cases
        List<Ken_Questionnaire_Parameter_Response__c> responses = [
            SELECT Id, Case__c
            FROM Ken_Questionnaire_Parameter_Response__c
            WHERE Case__c IN :caseIds
            WITH SECURITY_ENFORCED
            LIMIT 500
        ];

        if (responses.isEmpty()) {
            return result;
        }

        Map<Id, Id> responseToCase = new Map<Id, Id>();
        for (Ken_Questionnaire_Parameter_Response__c r : responses) {
            responseToCase.put(r.Id, r.Case__c);
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :responseToCase.keySet()
            ORDER BY SystemModstamp DESC
            LIMIT 500
        ];

        if (links.isEmpty()) {
            return result;
        }

        Map<Id, Id> docToCase = new Map<Id, Id>();
        for (ContentDocumentLink l : links) {
            Id caseId = responseToCase.get(l.LinkedEntityId);
            if (caseId != null) {
                docToCase.put(l.ContentDocumentId, caseId);
            }
        }

        if (docToCase.isEmpty()) {
            return result;
        }

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :docToCase.keySet()
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];

        for (ContentVersion v : versions) {
            Id caseId = docToCase.get(v.ContentDocumentId);
            if (caseId != null && !result.containsKey(caseId)) {
                result.put(caseId, v);
            }
        }

        return result;
    }
    
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static ContentVersion getLatestContentVersion(Id caseId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :caseId
            LIMIT 1
        ];
        
        if (links.isEmpty()) {
            return null;
        }
        
        List<ContentVersion> versions = [
            SELECT Id, Title, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
            ORDER BY CreatedDate DESC
            LIMIT 1
            ];
        
        return versions.isEmpty() ? null : versions[0];
    }
    @testvisible
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static ContentVersion getLatestFileFromResponses(
        List<Ken_Questionnaire_Parameter_Response__c> responses
    ) {
        if (responses.isEmpty()) {
            return null;
        }

        Set<Id> responseIds = new Set<Id>();
        for (Ken_Questionnaire_Parameter_Response__c r : responses) {
            responseIds.add(r.Id);
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :responseIds
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];

        if (links.isEmpty()) {
            return null;
        }

        return [
            SELECT Id, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
    }
    @testvisible
    private static String buildFileUrl(Id versionId) {
        return URL.getOrgDomainUrl().toExternalForm() + '/sfc/servlet.shepherd/version/download/' + versionId;
    }
    
    /**
     * @description Attach file to Case if data is present
     * @param caseId Case Id
     * @param fileName File name
     * @param fileData Base64 file data
     */
    @SuppressWarnings('PMD.ApexCRUDViolation')
    @testvisible
    private static void attachFileIfPresent(Id caseId, String fileName, String fileData) {
        if (String.isBlank(fileName) || String.isBlank(fileData)) {
            return;
        }
        
        ContentVersion cv = new ContentVersion(
            Title = fileName,
        PathOnClient = fileName,
        VersionData = EncodingUtil.base64Decode(fileData),
        FirstPublishLocationId = caseId
            );
        insert cv;
    }
    
    
    /**
     * @description Resolves the correct Case record type for a service-based case.
     *              Returns Gate_Pass_Request when the offering belongs to a Gate Pass
     *              service (Service_Category__c = SERVICE_CATEGORY_GATE_PASS),
     *              otherwise returns the standard Service record type.
     *              No hardcoding — all values come from KenSnSConstants.
     */
    @testvisible
    private static Id resolveServiceCaseRecordTypeId(Id serviceOfferingId) {
        if (serviceOfferingId != null) {
            try {
                List<Ken_Service_Offering__c> offerings = [
                    SELECT Service__r.Service_Category__c
                    FROM Ken_Service_Offering__c
                    WHERE Id = :serviceOfferingId
                    LIMIT 1
                ];
                if (!offerings.isEmpty()
                    && KenSnSConstants.SERVICE_CATEGORY_GATE_PASS.equalsIgnoreCase(
                           offerings[0].Service__r.Service_Category__c)) {
                    return getCaseRecordTypeId(KenSnSConstants.CASE_RECORD_TYPE_SERVICE);
                }
            } catch (Exception ignored) {}
        }
        return getCaseRecordTypeId(KenSnSConstants.CASE_RECORD_TYPE_SERVICE);
    }

    /**
     * @description Get Case RecordType Id by name
     * @param recordTypeName Record type name
     * @return RecordType Id
     */
    @testvisible
    public static Id getCaseRecordTypeId(String developerName) {
        Map<String, Schema.RecordTypeInfo> infos =
            Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName();
        if (infos.containsKey(developerName)) {
            return infos.get(developerName).getRecordTypeId();
        }
        return null;
    }
    
    @AuraEnabled
    public static void submitCaseFeedback(Id caseId, String rating, String feedback) {
        if (caseId == null) {
            throw new AuraHandledException('caseId is required');
        }
        
        // Validate rating: must be 1..5 if provided
        if (String.isNotBlank(rating)) {
            Integer r;
            try {
                r = Integer.valueOf(rating);
            } catch (Exception e) {
                throw new AuraHandledException('Invalid rating value');
            }
            if (r < 1 || r > 5) {
                throw new AuraHandledException('Rating must be between 1 and 5');
            }
        }
        
        // Update the case
        Case c = new Case(
            Id = caseId,
        Rating__c = rating,        // picklist values as String: "1".."5"
        Feedback__c = feedback     // long text area
            );

        update c;
    }

    // ── Approval History ─────────────────────────────────────────────────────

    public class ApprovalHistoryEntry {
        @AuraEnabled public String stepStatus;
        @AuraEnabled public String decisionLabel;
        @AuraEnabled public String decisionClass;
        @AuraEnabled public String commentsDisplay;
        @AuraEnabled public String actorName;
        @AuraEnabled public String processName;
        @AuraEnabled public String createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<ApprovalHistoryEntry> getApprovalHistory(Id caseId) {
        List<ApprovalHistoryEntry> result = new List<ApprovalHistoryEntry>();
        if (caseId == null) return result;
        String excludedStatus = KenSnSConstants.APPROVAL_STEP_STATUS_STARTED;
        try {
            List<ProcessInstanceStep> steps = [
                SELECT Id, StepStatus, StepNodeId, Comments, CreatedDate,
                       Actor.Name, ProcessInstance.ProcessDefinition.Name
                FROM ProcessInstanceStep
                WHERE ProcessInstance.TargetObjectId = :caseId
                AND   StepStatus != :excludedStatus
                ORDER BY CreatedDate ASC
            ];
            Set<Id> nodeIds = new Set<Id>();
            for (ProcessInstanceStep s : steps) {
                if (s.StepNodeId != null) nodeIds.add(s.StepNodeId);
            }
            Map<Id, ProcessNode> nodeMap = new Map<Id, ProcessNode>();
            if (!nodeIds.isEmpty()) {
                nodeMap = new Map<Id, ProcessNode>([SELECT Id, Name FROM ProcessNode WHERE Id IN :nodeIds]);
            }
            for (ProcessInstanceStep step : steps) {
                ApprovalHistoryEntry entry = new ApprovalHistoryEntry();
                entry.stepStatus      = step.StepStatus;
                String stepLabel = (step.StepNodeId != null && nodeMap.containsKey(step.StepNodeId))
                    ? nodeMap.get(step.StepNodeId).Name : null;
                entry.actorName       = String.isNotBlank(stepLabel) ? stepLabel.replace('_', ' ') : (step.Actor != null ? step.Actor.Name : '—');
                entry.processName     = step.ProcessInstance != null && step.ProcessInstance.ProcessDefinition != null
                                        ? step.ProcessInstance.ProcessDefinition.Name : '—';
                entry.createdDate     = step.CreatedDate != null
                    ? step.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                    : null;
                entry.commentsDisplay = String.isNotBlank(step.Comments) ? step.Comments : '—';

                if (KenSnSConstants.APPROVAL_STEP_STATUS_APPROVED.equals(step.StepStatus)) {
                    entry.decisionLabel = KenSnSConstants.APPROVAL_STEP_STATUS_APPROVED;
                    entry.decisionClass = KenSnSConstants.APPROVAL_DECISION_CLASS_APPROVED;
                } else if (KenSnSConstants.APPROVAL_STEP_STATUS_REJECTED.equals(step.StepStatus)) {
                    entry.decisionLabel = KenSnSConstants.APPROVAL_STEP_STATUS_REJECTED;
                    entry.decisionClass = KenSnSConstants.APPROVAL_DECISION_CLASS_REJECTED;
                } else {
                    entry.decisionLabel = step.StepStatus != null ? step.StepStatus : '—';
                    entry.decisionClass = KenSnSConstants.APPROVAL_DECISION_CLASS_DEFAULT;
                }
                result.add(entry);
            }
        } catch (Exception ignored) {}
        return result;
    }

}