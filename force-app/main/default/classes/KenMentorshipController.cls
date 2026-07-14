public without sharing class KenMentorshipController {
    private static final String CALL_REQUEST_RECORD_TYPE = 'Call_Request';
    private static final String CONNECTION_REQUEST_RECORD_TYPE = 'Connection_Request';
    private static final String ACCEPTED_STATUS = 'Accepted';
    private static final String REQUESTED_STATUS = 'Requested';
    private static final String REJECTED_STATUS = 'Rejected';
    private static final String TASK_ASSIGN_TO_MENTOR = 'Mentor';
    private static final String TASK_ASSIGN_TO_MENTEE = 'Mentee';
    private static final String CALL_PARTICIPANT_MENTOR = 'mentor';
    private static final String CALL_PARTICIPANT_MENTEE = 'mentee';

    @TestVisible
    private static Id testCurrentAccountId;

    public class MentorshipConnectionRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id mentorshipId;
        @AuraEnabled public Id personAccountId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String location;
        @AuraEnabled public String currentCity;
        @AuraEnabled public String profileImage;
        @AuraEnabled public Boolean isOnline;
        @AuraEnabled public String company;
        @AuraEnabled public String industry;
        @AuraEnabled public String jobFunction;
        @AuraEnabled public String programLastAttended;
        @AuraEnabled public String specialisation;
        @AuraEnabled public String graduationYear;
        @AuraEnabled public String educationLine;
        @AuraEnabled public String mentorshipStatus;
        @AuraEnabled public String callRequestStatus;
        @AuraEnabled public String recordType;
        @AuraEnabled public String networkStatus;
        @AuraEnabled public Boolean willingToHelp;
        @AuraEnabled public Boolean currentUserIsMentor;
    }

    public class MentorOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
    }

    public class ScheduleEventRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String dateIso;
        @AuraEnabled public String timeLabel;
        @AuraEnabled public String startTime;
        @AuraEnabled public String endTime;
        @AuraEnabled public String title;
        @AuraEnabled public String mentor;
        @AuraEnabled public String counterpartTitle;
        @AuraEnabled public String mentorImage;
        @AuraEnabled public String meetingDescription;
        @AuraEnabled public String meetingDescriptionHtml;
        @AuraEnabled public String meetingType;
        @AuraEnabled public String meetingLink;
        @AuraEnabled public String meetingLocation;
        @AuraEnabled public String callRequestStatus;
        @AuraEnabled public String requesterName;
        @AuraEnabled public String status;
        @AuraEnabled public String topic;
        @AuraEnabled public Boolean canRespond;
        @AuraEnabled public Boolean hasFeedbackForm;
        @AuraEnabled public Boolean feedbackSubmitted;
    }

    public class ScheduleCallRequest {
        @AuraEnabled public String mentorId { get; set; }
        @AuraEnabled public String mentor { get; set; }
        @AuraEnabled public String selectedMentor { get; set; }
        @AuraEnabled public String mentorValue { get; set; }
        @AuraEnabled public String participantType { get; set; }
        @AuraEnabled public String participantId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String meetingDate { get; set; }
        @AuraEnabled public String startTime { get; set; }
        @AuraEnabled public String endTime { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String meetingType { get; set; }
        @AuraEnabled public String meetLink { get; set; }
    }

    public class TaskRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String status;
        @AuraEnabled public String description;
        @AuraEnabled public String descriptionHtml;
        @AuraEnabled public String priority;
        @AuraEnabled public String endDate;
        @AuraEnabled public String assignTo;
        @AuraEnabled public String mentorId;
        @AuraEnabled public String assigneeId;
        @AuraEnabled public String assigneeName;
        @AuraEnabled public String assigneeAvatar;
        @AuraEnabled public Boolean canEdit;
    }

    public class TaskSaveRequest {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String descriptionHtml { get; set; }
        @AuraEnabled public String priority { get; set; }
        @AuraEnabled public String endDate { get; set; }
        @AuraEnabled public String assignTo { get; set; }
        @AuraEnabled public String mentorId { get; set; }
        @AuraEnabled public String assigneeId { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<MentorshipConnectionRow> getMentorshipConnections() {
        try {
            List<MentorshipConnectionRow> rows = new List<MentorshipConnectionRow>();
            if (!Schema.sObjectType.Ken_Mentorship__c.isAccessible() ||
                !Schema.sObjectType.Account.isAccessible()) {
                return rows;
            }

            Id currentAccountId = getCurrentUserAccountId();
            if (currentAccountId == null) {
                return rows;
            }

            List<Ken_Mentorship__c> mentorshipRecords = [
                SELECT Id,
                       Name,
                       Mentor__c,
                       Mentee__c,
                       Mentorship_Status__c,
                       Call_Request_Status__c,
                       Network_Connection__c,
                       Network_Connection__r.Status__c,
                       RecordType.DeveloperName
                FROM Ken_Mentorship__c
                WHERE (Mentor__c = :currentAccountId
                   OR Mentee__c = :currentAccountId)
                  AND RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
                  AND Mentorship_Status__c = :ACCEPTED_STATUS
                ORDER BY LastModifiedDate DESC
                LIMIT 500
            ];

            if (mentorshipRecords.isEmpty()) {
                return rows;
            }

            // Keep only the latest connection row per counterpart account.
            Map<Id, Ken_Mentorship__c> latestConnectionByCounterpart = new Map<Id, Ken_Mentorship__c>();
            List<Id> orderedCounterpartIds = new List<Id>();
            for (Ken_Mentorship__c rec : mentorshipRecords) {
                Id counterpartId = rec.Mentor__c == currentAccountId ? rec.Mentee__c : rec.Mentor__c;
                if (counterpartId != null && !latestConnectionByCounterpart.containsKey(counterpartId)) {
                    latestConnectionByCounterpart.put(counterpartId, rec);
                    orderedCounterpartIds.add(counterpartId);
                }
            }

            Set<Id> counterpartIds = new Set<Id>(orderedCounterpartIds);

            Map<Id, KenNetworkController.ProfileCardSummary> summaryByAccountId =
                KenNetworkController.getProfileCardSummaries(counterpartIds);
            Map<Id, Boolean> mentorPreferenceByAccountId = getMentorPreferenceByAccountIds(counterpartIds);

            for (Id counterpartId : orderedCounterpartIds) {
                Ken_Mentorship__c rec = latestConnectionByCounterpart.get(counterpartId);
                KenNetworkController.ProfileCardSummary summary = summaryByAccountId.get(counterpartId);
                if (rec == null || summary == null) {
                    continue;
                }

                MentorshipConnectionRow row = new MentorshipConnectionRow();
                row.id = rec.Id;
                row.mentorshipId = rec.Id;
                row.personAccountId = counterpartId;
                row.name = summary.name;
                row.title = summary.title;
                row.location = summary.location;
                row.currentCity = summary.currentCity;
                row.profileImage = summary.profileImage;
                row.isOnline = false;
                row.company = summary.company;
                row.industry = summary.industry;
                row.jobFunction = summary.title;
                row.programLastAttended = summary.programLastAttended;
                row.specialisation = null;
                row.graduationYear = summary.graduationYear;
                row.educationLine = summary.educationLine;
                row.mentorshipStatus = rec.Mentorship_Status__c;
                row.callRequestStatus = rec.Call_Request_Status__c;
                row.recordType = rec.RecordType != null ? rec.RecordType.DeveloperName : null;
                row.networkStatus = rec.Network_Connection__r != null ? rec.Network_Connection__r.Status__c : null;
                row.willingToHelp = mentorPreferenceByAccountId.containsKey(counterpartId)
                    ? mentorPreferenceByAccountId.get(counterpartId)
                    : false;
                row.currentUserIsMentor = rec.Mentor__c == currentAccountId;
                rows.add(row);
            }
            return rows;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load mentorship connections: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<MentorOption> getAcceptedMentorsForCurrentMentee() {
        List<MentorOption> options = new List<MentorOption>();
        if (!Schema.sObjectType.Ken_Mentorship__c.isAccessible() || !Schema.sObjectType.Account.isAccessible()) {
            return options;
        }

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            return options;
        }

        Map<Id, String> mentorById = new Map<Id, String>();
        for (Ken_Mentorship__c rec : [
            SELECT Mentor__c, Mentor__r.Name
            FROM Ken_Mentorship__c
            WHERE Mentee__c = :currentAccountId
              AND RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
              AND Mentorship_Status__c = :ACCEPTED_STATUS
              AND Mentor__c != null
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            if (!mentorById.containsKey(rec.Mentor__c)) {
                mentorById.put(rec.Mentor__c, rec.Mentor__r != null ? rec.Mentor__r.Name : null);
            }
        }

        List<Id> mentorIds = new List<Id>(mentorById.keySet());
        mentorIds.sort();
        for (Id mentorId : mentorIds) {
            MentorOption option = new MentorOption();
            option.value = mentorId;
            option.label = mentorById.get(mentorId);
            options.add(option);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<MentorOption> getAcceptedMenteesForCurrentMentor() {
        List<MentorOption> options = new List<MentorOption>();
        if (!Schema.sObjectType.Ken_Mentorship__c.isAccessible() || !Schema.sObjectType.Account.isAccessible()) {
            return options;
        }

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            return options;
        }

        Map<Id, String> menteeById = new Map<Id, String>();
        for (Ken_Mentorship__c rec : [
            SELECT Mentee__c, Mentee__r.Name
            FROM Ken_Mentorship__c
            WHERE Mentor__c = :currentAccountId
              AND RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
              AND Mentorship_Status__c = :ACCEPTED_STATUS
              AND Mentee__c != null
            ORDER BY LastModifiedDate DESC
            LIMIT 500
        ]) {
            if (!menteeById.containsKey(rec.Mentee__c)) {
                menteeById.put(rec.Mentee__c, rec.Mentee__r != null ? rec.Mentee__r.Name : null);
            }
        }

        List<Id> menteeIds = new List<Id>(menteeById.keySet());
        menteeIds.sort();
        for (Id menteeId : menteeIds) {
            MentorOption option = new MentorOption();
            option.value = menteeId;
            option.label = menteeById.get(menteeId);
            options.add(option);
        }
        return options;
    }

    @AuraEnabled(cacheable=false)
    public static List<ScheduleEventRow> getScheduledCallsForCurrentMentee() {
        List<ScheduleEventRow> rows = new List<ScheduleEventRow>();
        if (!Schema.sObjectType.Ken_Mentorship__c.isAccessible() || !Schema.sObjectType.Account.isAccessible()) {
            return rows;
        }

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            return rows;
        }

        Date today = Date.today();
        Time nowTime = Datetime.now().time();
        // call id -> its per-call feedback instance (Survey__c), for the dedupe pass below
        Map<Id, Id> callSurveyById = new Map<Id, Id>();
        for (Ken_Mentorship__c rec : [
            SELECT Id,
                   Meeting_Title__c,
                   Meeting_Description__c,
                   Meet_Date__c,
                   Meet_Start_Time__c,
                   Meet_End_Time__c,
                   Mentor__c,
                   Mentor__r.Name,
                   Mentor__r.PersonTitle,
                   Mentor__r.PhotoUrl,
                   Mentee__c,
                   Mentee__r.Name,
                   Mentee__r.PersonTitle,
                   Mentee__r.PhotoUrl,
                   MeetingRequestedBy__c,
                   MeetingRequestedBy__r.Name,
                   Call_Request_Status__c,
                   Meeting_Mode__c,
                   Meeting_Link__c,
                   Meeting_Location__c,
                   Survey__c
            FROM Ken_Mentorship__c
            WHERE (Mentee__c = :currentAccountId OR Mentor__c = :currentAccountId)
              AND RecordType.DeveloperName = :CALL_REQUEST_RECORD_TYPE
              AND Meet_Date__c != null
            ORDER BY Meet_Date__c ASC, Meet_Start_Time__c ASC, LastModifiedDate DESC
            LIMIT 1000
        ]) {
            if (isHiddenStatus(rec.Call_Request_Status__c)) {
                continue;
            }

            Boolean isViewerMentor = rec.Mentor__c == currentAccountId;
            Boolean isRequestedByViewer = rec.MeetingRequestedBy__c == currentAccountId;

            ScheduleEventRow row = new ScheduleEventRow();
            row.id = rec.Id;
            row.dateIso = rec.Meet_Date__c != null ? String.valueOf(rec.Meet_Date__c) : null;
            row.timeLabel = buildTimeLabel(rec.Meet_Start_Time__c, rec.Meet_End_Time__c);
            row.startTime = formatTimeForInput(rec.Meet_Start_Time__c);
            row.endTime = formatTimeForInput(rec.Meet_End_Time__c);
            row.title = String.isNotBlank(rec.Meeting_Title__c) ? rec.Meeting_Title__c : 'Mentorship Call';
            if (isViewerMentor) {
                row.mentor = rec.Mentee__r != null ? rec.Mentee__r.Name : null;
                row.counterpartTitle = rec.Mentee__r != null ? rec.Mentee__r.PersonTitle : null;
                row.mentorImage = rec.Mentee__r != null && String.isNotBlank(rec.Mentee__r.PhotoUrl)
                    ? URL.getOrgDomainUrl().toExternalForm() + rec.Mentee__r.PhotoUrl
                    : null;
            } else {
                row.mentor = rec.Mentor__r != null ? rec.Mentor__r.Name : null;
                row.counterpartTitle = rec.Mentor__r != null ? rec.Mentor__r.PersonTitle : null;
                row.mentorImage = rec.Mentor__r != null && String.isNotBlank(rec.Mentor__r.PhotoUrl)
                    ? URL.getOrgDomainUrl().toExternalForm() + rec.Mentor__r.PhotoUrl
                    : null;
            }
            row.meetingDescriptionHtml = rec.Meeting_Description__c;
            row.meetingDescription = buildDescriptionText(rec);
            row.meetingType = rec.Meeting_Mode__c;
            row.meetingLink = rec.Meeting_Link__c;
            row.meetingLocation = rec.Meeting_Location__c;
            row.callRequestStatus = rec.Call_Request_Status__c;
            row.requesterName = rec.MeetingRequestedBy__r != null ? rec.MeetingRequestedBy__r.Name : null;
            row.status = mapUiStatus(
                rec.Call_Request_Status__c,
                rec.Meet_Date__c,
                rec.Meet_Start_Time__c,
                rec.Meet_End_Time__c,
                rec.Meeting_Mode__c,
                today,
                nowTime,
                isViewerMentor,
                isRequestedByViewer
            );
            row.topic = buildTopic(rec);
            row.canRespond = rec.Call_Request_Status__c == REQUESTED_STATUS &&
                !isRequestedByViewer;
            row.hasFeedbackForm = rec.Survey__c != null;
            row.feedbackSubmitted = false;
            if (rec.Survey__c != null) {
                callSurveyById.put(rec.Id, rec.Survey__c);
            }
            rows.add(row);
        }

        // Flag calls whose per-call instance the current user already responded to,
        // so the "Leave Feedback" prompt clears (one response per user per call).
        // Fail-soft: a feedback-lookup error must never blank the schedule list.
        try {
        if (!callSurveyById.isEmpty() &&
            Schema.sObjectType.Ken_Questionnaire_Parameter_Response__c.isAccessible()) {
            Set<Id> surveyIds = new Set<Id>(callSurveyById.values());
            // Responses reach the survey via the questionnaire link; map back to survey.
            Map<Id, Id> surveyByQuestionnaire = new Map<Id, Id>();
            for (Ken_Survey__c s : [
                SELECT Id, Ken_Questionnaire__c
                FROM Ken_Survey__c
                WHERE Id IN :surveyIds AND Ken_Questionnaire__c != null
            ]) {
                surveyByQuestionnaire.put(s.Ken_Questionnaire__c, s.Id);
            }
            Set<Id> answeredSurveyIds = new Set<Id>();
            if (!surveyByQuestionnaire.isEmpty()) {
                Set<Id> qIds = surveyByQuestionnaire.keySet();
                for (Ken_Questionnaire_Parameter_Response__c resp : [
                    SELECT Questionnaire_Parameter__r.Questionnaire__c
                    FROM Ken_Questionnaire_Parameter_Response__c
                    WHERE Questionnaire_Parameter__r.Questionnaire__c IN :qIds
                      AND Respondent__c = :currentAccountId
                ]) {
                    Id qId = (resp.Questionnaire_Parameter__r != null)
                        ? resp.Questionnaire_Parameter__r.Questionnaire__c : null;
                    if (qId != null && surveyByQuestionnaire.containsKey(qId)) {
                        answeredSurveyIds.add(surveyByQuestionnaire.get(qId));
                    }
                }
            }
            if (!answeredSurveyIds.isEmpty()) {
                for (ScheduleEventRow r : rows) {
                    Id sId = callSurveyById.get(r.id);
                    if (sId != null && answeredSurveyIds.contains(sId)) {
                        r.feedbackSubmitted = true;
                    }
                }
            }
        }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Feedback flagging skipped: ' + e.getMessage());
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<TaskRow> getTasksForCurrentMentee() {
        List<TaskRow> rows = new List<TaskRow>();

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            return rows;
        }

        for (Task rec : [
            SELECT Id,
                   Subject,
                   Status,
                   Description,
                   Description_Html__c,
                   Priority,
                   ActivityDate,
                   Assign_To__c,
                   CreatedById,
                   Mentor__c,
                   Mentor__r.Name,
                   Mentor__r.PhotoUrl,
                   Mentee__c,
                   Mentee__r.Name,
                   Mentee__r.PhotoUrl
            FROM Task
            WHERE Mentee__c = :currentAccountId
               OR Mentor__c = :currentAccountId
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            rows.add(mapTaskRow(rec));
        }
        return rows;
    }

    @AuraEnabled
    public static TaskRow saveTaskForCurrentMentee(TaskSaveRequest request) {
        if (request == null) {
            throw new AuraHandledException('Task payload is required.');
        }

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            throw new AuraHandledException('Unable to determine the current user account.');
        }

        Id taskId = parseSalesforceId(request.id);
        Boolean isCreate = taskId == null;

        Task taskRec;
        if (isCreate) {
            taskRec = new Task();
        } else {
            // Only the user who created the task may edit it.
            List<Task> existing = [
                SELECT Id, Mentee__c, Mentor__c
                FROM Task
                WHERE Id = :taskId
                  AND CreatedById = :UserInfo.getUserId()
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                throw new AuraHandledException('You can only edit tasks you created.');
            }
            taskRec = existing[0];
        }

        String title = request.title != null ? request.title.trim() : '';
        if (String.isBlank(title)) {
            throw new AuraHandledException('Task title is required.');
        }

        String status = normalizeTaskStatus(request.status);
        if (status == null) {
            throw new AuraHandledException('Please select a valid task status.');
        }

        String priority = normalizeTaskPriority(request.priority);
        if (priority == null) {
            priority = 'Low';
        }

        String assignTo = normalizeTaskAssignTo(request.assignTo);
        Id mentorId = parseSalesforceId(request.mentorId);

        taskRec.Subject = title;
        taskRec.Status = status;
        taskRec.Description = request.description;
        taskRec.Description_Html__c = request.descriptionHtml;
        taskRec.Priority = priority;
        taskRec.ActivityDate = parseDateValue(request.endDate);
        if (taskRec.ActivityDate != null && taskRec.ActivityDate < Date.today()) {
            throw new AuraHandledException('End date cannot be in the past.');
        }
        taskRec.Assign_To__c = assignTo;
        Id selectedAssigneeId = parseSalesforceId(request.assigneeId);
        if (selectedAssigneeId == null) {
            selectedAssigneeId = mentorId;
        }

        if (assignTo == TASK_ASSIGN_TO_MENTOR) {
            if (selectedAssigneeId == null) {
                throw new AuraHandledException('Please choose a mentor.');
            }
            if (!hasAcceptedConnection(currentAccountId, selectedAssigneeId)) {
                throw new AuraHandledException('Selected mentor is not accepted for this account.');
            }
            taskRec.Mentor__c = selectedAssigneeId;
            if (taskRec.Mentee__c == null) {
                taskRec.Mentee__c = currentAccountId;
            }
        } else {
            Id targetMenteeId = selectedAssigneeId != null ? selectedAssigneeId : currentAccountId;
            if (targetMenteeId != currentAccountId && !hasAcceptedConnection(currentAccountId, targetMenteeId)) {
                throw new AuraHandledException('Selected mentee is not accepted for this account.');
            }
            taskRec.Mentee__c = targetMenteeId;
            if (targetMenteeId != currentAccountId) {
                taskRec.Mentor__c = currentAccountId;
            }
        }

        if (isCreate) {
            insert taskRec;
        } else {
            update taskRec;
        }

        Task savedTask = [
            SELECT Id,
                   Subject,
                   Status,
                   Description,
                   Description_Html__c,
                   Priority,
                   ActivityDate,
                   Assign_To__c,
                   CreatedById,
                   Mentor__c,
                   Mentor__r.Name,
                   Mentor__r.PhotoUrl,
                   Mentee__c,
                   Mentee__r.Name,
                   Mentee__r.PhotoUrl
            FROM Task
            WHERE Id = :taskRec.Id
            LIMIT 1
        ];
        return mapTaskRow(savedTask);
    }

    @AuraEnabled
    public static void deleteTaskForCurrentMentee(String taskId) {

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            throw new AuraHandledException('Unable to determine the current user account.');
        }

        Id parsedTaskId = parseSalesforceId(taskId);
        if (parsedTaskId == null) {
            throw new AuraHandledException('Task id is invalid.');
        }

        // Only the user who created the task may delete it.
        List<Task> records = [
            SELECT Id
            FROM Task
            WHERE Id = :parsedTaskId
              AND CreatedById = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (records.isEmpty()) {
            throw new AuraHandledException('You can only delete tasks you created.');
        }

        delete records[0];
    }

    @AuraEnabled
    public static Id scheduleCallForCurrentMentee(ScheduleCallRequest request) {
        validateCreateAccess();
        if (request == null) {
            throw new AuraHandledException('Schedule request payload is required.');
        }

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            throw new AuraHandledException('Unable to determine the current user account.');
        }

        String participantType = normalizeCallParticipantType(request.participantType);
        Id selectedParticipantId = resolveParticipantId(request);

        Date meetDate = parseDateValue(request.meetingDate);
        Time startTime = parseTimeValue(request.startTime);
        Time endTime = parseTimeValue(request.endTime);

        if (meetDate == null) {
            throw new AuraHandledException('Please select a valid date.');
        }
        if (meetDate < Date.today()) {
            throw new AuraHandledException('You cannot schedule a call for a past date.');
        }
        if (startTime == null || endTime == null) {
            throw new AuraHandledException('Please select valid start and end times.');
        }

        String normalizedMeetingType = normalizeMeetingType(request.meetingType);
        if (String.isBlank(normalizedMeetingType)) {
            throw new AuraHandledException('Please select how you would like to meet.');
        }

        Id mentorId;
        Id menteeId;
        Ken_Mentorship__c acceptedMentorship;

        if (participantType == CALL_PARTICIPANT_MENTEE) {
            Id selectedMenteeId = selectedParticipantId;
            if (selectedMenteeId == null) {
                selectedMenteeId = resolveSingleAcceptedMenteeId(currentAccountId);
            }
            if (selectedMenteeId == null) {
                throw new AuraHandledException('Please select a mentee.');
            }

            acceptedMentorship = getAcceptedMentorshipForMentor(currentAccountId, selectedMenteeId);
            if (acceptedMentorship == null) {
                throw new AuraHandledException('Selected mentee is not accepted for this mentor.');
            }

            mentorId = currentAccountId;
            menteeId = selectedMenteeId;
        } else {
            Id requestedMentorId = selectedParticipantId;
            if (requestedMentorId == null) {
                requestedMentorId = resolveSingleAcceptedMentorId(currentAccountId);
            }
            if (requestedMentorId == null) {
                throw new AuraHandledException('Please select a mentor.');
            }

            acceptedMentorship = getAcceptedMentorship(currentAccountId, requestedMentorId);
            if (acceptedMentorship == null) {
                throw new AuraHandledException('Selected mentor is not accepted for this mentee.');
            }

            mentorId = requestedMentorId;
            menteeId = currentAccountId;
        }

        Id callRecordTypeId = getCallRequestRecordTypeId();
        if (callRecordTypeId == null) {
            throw new AuraHandledException('Call Request record type not found.');
        }

        Ken_Mentorship__c callRequest = new Ken_Mentorship__c();
        callRequest.RecordTypeId = callRecordTypeId;
        callRequest.Mentor__c = mentorId;
        callRequest.Mentee__c = menteeId;
        callRequest.MeetingRequestedBy__c = currentAccountId;
        callRequest.Meeting_Title__c = String.isNotBlank(request.title) ? request.title.trim() : 'Mentorship Call';
        callRequest.Meeting_Description__c = request.description;
        callRequest.Meet_Date__c = meetDate;
        callRequest.Meet_Start_Time__c = startTime;
        callRequest.Meet_End_Time__c = endTime;
        callRequest.Meeting_Mode__c = normalizedMeetingType;
        callRequest.Call_Request_Status__c = REQUESTED_STATUS;
        if (acceptedMentorship.Network_Connection__c != null) {
            callRequest.Network_Connection__c = acceptedMentorship.Network_Connection__c;
        }

        // Create a per-call feedback instance from the latest Mentorship template
        // and attach it, so this call's responses stay isolated to this call.
        // Tolerated: a missing/misconfigured template must never block scheduling.
        try {
            Id feedbackInstanceId =
                KenModuleFeedbackController.createInstanceForCategory(KenModuleFeedbackController.CATEGORY_MENTORSHIP);
            if (feedbackInstanceId != null) {
                callRequest.Survey__c = feedbackInstanceId;
            }
        } catch (Exception fbEx) {
            System.debug('Feedback instance creation tolerated — ' + fbEx.getMessage());
        }

        if (normalizedMeetingType == 'Online') {
            callRequest.Meeting_Link__c = request.meetLink;
            callRequest.Meeting_Location__c = null;
        } else {
            callRequest.Meeting_Link__c = null;
            callRequest.Meeting_Location__c = request.meetLink;
        }

        insert callRequest;
        return callRequest.Id;
    }

    /**
     * Accept or reject an initial mentorship request inline from the notification bell.
     * Mirrors respondToCallRequest but targets the Connection_Request record type and
     * the Mentorship_Status__c field. The KenMentorshipTriggerHandler picks up the
     * status transition and fires the Mentorship_Accepted / Mentorship_Rejected
     * notifications back to the mentee.
     */
    @AuraEnabled
    public static void respondToMentorshipRequest(String mentorshipId, String action) {
        if (!Schema.sObjectType.Ken_Mentorship__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update mentorship requests.');
        }

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            throw new AuraHandledException('Unable to determine the current user account.');
        }

        Id parsedId = parseSalesforceId(mentorshipId);
        if (parsedId == null) {
            throw new AuraHandledException('Mentorship request id is invalid.');
        }

        String normalizedAction = String.isBlank(action) ? '' : action.trim().toLowerCase();
        String targetStatus;
        if (normalizedAction == 'accept') {
            targetStatus = ACCEPTED_STATUS;
        } else if (normalizedAction == 'reject') {
            targetStatus = REJECTED_STATUS;
        } else {
            throw new AuraHandledException('Unsupported mentorship action.');
        }

        List<Ken_Mentorship__c> records = [
            SELECT Id, Mentorship_Status__c
            FROM Ken_Mentorship__c
            WHERE Id = :parsedId
              AND RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
              AND Mentor__c = :currentAccountId
            LIMIT 1
        ];

        if (records.isEmpty()) {
            throw new AuraHandledException('Mentorship request not found for this user.');
        }

        Ken_Mentorship__c req = records[0];
        if (req.Mentorship_Status__c != REQUESTED_STATUS) {
            throw new AuraHandledException('Only pending mentorship requests can be updated.');
        }

        req.Mentorship_Status__c = targetStatus;
        update req;

        // Clear the mentor's "requested mentorship" notification for this request.
        KenNotificationFactory.markRelatedAsRead(new Set<Id>{ req.Id }, currentAccountId);
    }

    @AuraEnabled
    public static void respondToCallRequest(String callRequestId, String action) {
        if (!Schema.sObjectType.Ken_Mentorship__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update call requests.');
        }

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            throw new AuraHandledException('Unable to determine the current user account.');
        }

        Id parsedCallRequestId = parseSalesforceId(callRequestId);
        if (parsedCallRequestId == null) {
            throw new AuraHandledException('Call request id is invalid.');
        }

        String normalizedAction = String.isBlank(action) ? '' : action.trim().toLowerCase();
        String targetStatus;
        if (normalizedAction == 'accept') {
            targetStatus = ACCEPTED_STATUS;
        } else if (normalizedAction == 'reject') {
            targetStatus = REJECTED_STATUS;
        } else {
            throw new AuraHandledException('Unsupported call request action.');
        }

        // Either party (mentor OR mentee) on the call can respond, as long as they
        // are not the one who raised the request. The UI surfaces the Accept/Decline
        // actions to whichever party did not initiate it (canRespond), so the backend
        // must accept a response from the mentee too, not only the mentor.
        List<Ken_Mentorship__c> records = [
            SELECT Id, Call_Request_Status__c, Mentorship_Status__c, MeetingRequestedBy__c
            FROM Ken_Mentorship__c
            WHERE Id = :parsedCallRequestId
              AND RecordType.DeveloperName = :CALL_REQUEST_RECORD_TYPE
              AND (Mentor__c = :currentAccountId OR Mentee__c = :currentAccountId)
            LIMIT 1
        ];

        if (records.isEmpty()) {
            throw new AuraHandledException('Call request not found for this user.');
        }

        Ken_Mentorship__c callRequest = records[0];
        if (callRequest.MeetingRequestedBy__c == currentAccountId) {
            throw new AuraHandledException('You cannot respond to a call request you raised.');
        }
        if (callRequest.Call_Request_Status__c != REQUESTED_STATUS) {
            throw new AuraHandledException('Only requested calls can be updated.');
        }

        callRequest.Call_Request_Status__c = targetStatus;
        callRequest.Mentorship_Status__c = targetStatus;
        update callRequest;

        // Clear the responder's "call request" notification for this record.
        KenNotificationFactory.markRelatedAsRead(new Set<Id>{ callRequest.Id }, currentAccountId);
    }

    @AuraEnabled
    public static void rescheduleCallRequest(String callRequestId, String meetingDate, String startTime, String endTime) {
        if (!Schema.sObjectType.Ken_Mentorship__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update call requests.');
        }

        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            throw new AuraHandledException('Unable to determine the current user account.');
        }

        Id parsedCallRequestId = parseSalesforceId(callRequestId);
        if (parsedCallRequestId == null) {
            throw new AuraHandledException('Call request id is invalid.');
        }

        Date targetDate = parseDateValue(meetingDate);
        Time targetStartTime = parseTimeValue(startTime);
        Time targetEndTime = parseTimeValue(endTime);
        if (targetDate == null) {
            throw new AuraHandledException('Please select a valid date.');
        }
        if (targetDate < Date.today()) {
            throw new AuraHandledException('You cannot schedule a call for a past date.');
        }
        if (targetStartTime == null || targetEndTime == null) {
            throw new AuraHandledException('Please select valid start and end times.');
        }
        if (targetStartTime >= targetEndTime) {
            throw new AuraHandledException('End time must be after start time.');
        }

        // Either party (mentor OR mentee) on the call can suggest a new slot, as long
        // as they did not raise the request themselves (mirrors respondToCallRequest).
        List<Ken_Mentorship__c> records = [
            SELECT Id, Call_Request_Status__c, Mentorship_Status__c, MeetingRequestedBy__c
            FROM Ken_Mentorship__c
            WHERE Id = :parsedCallRequestId
              AND RecordType.DeveloperName = :CALL_REQUEST_RECORD_TYPE
              AND (Mentor__c = :currentAccountId OR Mentee__c = :currentAccountId)
            LIMIT 1
        ];
        if (records.isEmpty()) {
            throw new AuraHandledException('Call request not found for this user.');
        }

        Ken_Mentorship__c callRequest = records[0];
        if (callRequest.MeetingRequestedBy__c == currentAccountId) {
            throw new AuraHandledException('You cannot respond to a call request you raised.');
        }
        if (callRequest.Call_Request_Status__c != REQUESTED_STATUS) {
            throw new AuraHandledException('Only requested calls can be rescheduled.');
        }

        callRequest.Meet_Date__c = targetDate;
        callRequest.Meet_Start_Time__c = targetStartTime;
        callRequest.Meet_End_Time__c = targetEndTime;
        callRequest.Call_Request_Status__c = ACCEPTED_STATUS;
        callRequest.Mentorship_Status__c = ACCEPTED_STATUS;
        update callRequest;
    }

    private static Id resolveParticipantId(ScheduleCallRequest request) {
        List<String> candidates = new List<String>{
            request.participantId,
            request.mentorId,
            request.mentor,
            request.selectedMentor,
            request.mentorValue
        };

        for (String rawCandidate : candidates) {
            if (String.isBlank(rawCandidate)) {
                continue;
            }

            String candidate = rawCandidate.trim();
            if (candidate.length() != 15 && candidate.length() != 18) {
                continue;
            }
            if (String.isNotBlank(candidate.replaceAll('[a-zA-Z0-9]', ''))) {
                continue;
            }

            try {
                return (Id) candidate;
            } catch (Exception ex) {
                continue;
            }
        }
        return null;
    }

    private static Id parseSalesforceId(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        String candidate = rawValue.trim();
        if (candidate.length() != 15 && candidate.length() != 18) {
            return null;
        }
        if (String.isNotBlank(candidate.replaceAll('[a-zA-Z0-9]', ''))) {
            return null;
        }
        try {
            return (Id) candidate;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id getCurrentUserAccountId() {
        if (Test.isRunningTest() && testCurrentAccountId != null) {
            return testCurrentAccountId;
        }
        if (!Schema.sObjectType.User.isAccessible()) {
            return null;
        }

        List<User> users = [
            SELECT Id, AccountId, ContactId, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (users.isEmpty()) {
            return null;
        }

        User currentUser = users[0];
        if (currentUser.AccountId != null) {
            return currentUser.AccountId;
        }
        if (currentUser.ContactId != null && currentUser.Contact != null) {
            return currentUser.Contact.AccountId;
        }
        return null;
    }

    public class MentorAvailability {
        @AuraEnabled public String availabilityDays;
        @AuraEnabled public String availabilityStartTime;
        @AuraEnabled public String availabilityEndTime;
    }

    @AuraEnabled(cacheable=true)
    public static MentorAvailability getMentorAvailabilityDays(String mentorId) {
        MentorAvailability result = new MentorAvailability();
        result.availabilityDays      = '';
        result.availabilityStartTime = '';
        result.availabilityEndTime   = '';

        if (String.isBlank(mentorId) || !Schema.sObjectType.Ken_Alumni_Preferences__c.isAccessible()) {
            return result;
        }
        Id mentorAccountId;
        try { mentorAccountId = (Id) mentorId; } catch (Exception e) { return result; }

        List<Ken_Alumni_Preferences__c> prefs = [
            SELECT Mentorship_Availability_Days__c,
                   Mentorship_Availability_Start_Time__c,
                   Mentorship_Availability_End_Time__c
            FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c = :mentorAccountId
              AND Willing_to_be_a_mentor__c = true
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (prefs.isEmpty()) {
            return result;
        }
        Ken_Alumni_Preferences__c pref = prefs[0];
        result.availabilityDays = pref.Mentorship_Availability_Days__c != null
            ? pref.Mentorship_Availability_Days__c : '';
        result.availabilityStartTime = pref.Mentorship_Availability_Start_Time__c != null
            ? String.valueOf(pref.Mentorship_Availability_Start_Time__c).substring(0, 5) : '';
        result.availabilityEndTime = pref.Mentorship_Availability_End_Time__c != null
            ? String.valueOf(pref.Mentorship_Availability_End_Time__c).substring(0, 5) : '';
        return result;
    }

    private static Map<Id, Boolean> getMentorPreferenceByAccountIds(Set<Id> accountIds) {
        Map<Id, Boolean> mentorPreferenceByAccountId = new Map<Id, Boolean>();
        if (accountIds.isEmpty() || !Schema.sObjectType.Ken_Alumni_Preferences__c.isAccessible()) {
            return mentorPreferenceByAccountId;
        }

        for (Ken_Alumni_Preferences__c rec : [
            SELECT Person_Account__c, Willing_to_be_a_mentor__c
            FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c IN :accountIds
            ORDER BY LastModifiedDate DESC
        ]) {
            if (rec.Person_Account__c != null && !mentorPreferenceByAccountId.containsKey(rec.Person_Account__c)) {
                mentorPreferenceByAccountId.put(rec.Person_Account__c, rec.Willing_to_be_a_mentor__c == true);
            }
        }
        return mentorPreferenceByAccountId;
    }

    private static Ken_Mentorship__c getAcceptedMentorshipForMentor(Id mentorId, Id menteeId) {
        List<Ken_Mentorship__c> records = [
            SELECT Id, Network_Connection__c
            FROM Ken_Mentorship__c
            WHERE Mentor__c = :mentorId
              AND Mentee__c = :menteeId
              AND RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
              AND Mentorship_Status__c = :ACCEPTED_STATUS
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    private static Ken_Mentorship__c getAcceptedMentorship(Id menteeId, Id mentorId) {
        List<Ken_Mentorship__c> records = [
            SELECT Id, Network_Connection__c
            FROM Ken_Mentorship__c
            WHERE Mentee__c = :menteeId
              AND Mentor__c = :mentorId
              AND RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
              AND Mentorship_Status__c = :ACCEPTED_STATUS
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    private static Boolean hasAcceptedConnection(Id firstAccountId, Id secondAccountId) {
        if (firstAccountId == null || secondAccountId == null) {
            return false;
        }
        if (firstAccountId == secondAccountId) {
            return true;
        }

        List<Ken_Mentorship__c> records = [
            SELECT Id
            FROM Ken_Mentorship__c
            WHERE RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
              AND Mentorship_Status__c = :ACCEPTED_STATUS
              AND (
                  (Mentor__c = :firstAccountId AND Mentee__c = :secondAccountId)
                  OR
                  (Mentor__c = :secondAccountId AND Mentee__c = :firstAccountId)
              )
            LIMIT 1
        ];
        return !records.isEmpty();
    }

    private static Id resolveSingleAcceptedMentorId(Id menteeId) {
        if (menteeId == null) {
            return null;
        }

        Set<Id> mentorIds = new Set<Id>();
        for (Ken_Mentorship__c rec : [
            SELECT Mentor__c
            FROM Ken_Mentorship__c
            WHERE Mentee__c = :menteeId
              AND RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
              AND Mentorship_Status__c = :ACCEPTED_STATUS
              AND Mentor__c != null
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            mentorIds.add(rec.Mentor__c);
            if (mentorIds.size() > 1) {
                return null;
            }
        }

        return mentorIds.isEmpty() ? null : mentorIds.iterator().next();
    }

    private static Id resolveSingleAcceptedMenteeId(Id mentorId) {
        if (mentorId == null) {
            return null;
        }

        Set<Id> menteeIds = new Set<Id>();
        for (Ken_Mentorship__c rec : [
            SELECT Mentee__c
            FROM Ken_Mentorship__c
            WHERE Mentor__c = :mentorId
              AND RecordType.DeveloperName = :CONNECTION_REQUEST_RECORD_TYPE
              AND Mentorship_Status__c = :ACCEPTED_STATUS
              AND Mentee__c != null
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            menteeIds.add(rec.Mentee__c);
            if (menteeIds.size() > 1) {
                return null;
            }
        }

        return menteeIds.isEmpty() ? null : menteeIds.iterator().next();
    }

    private static Id getCallRequestRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Ken_Mentorship__c'
              AND DeveloperName = :CALL_REQUEST_RECORD_TYPE
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    private static void validateCreateAccess() {
        if (!Schema.sObjectType.Ken_Mentorship__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to schedule a call.');
        }
    }

    private static String normalizeMeetingType(String meetingType) {
        if (String.isBlank(meetingType)) {
            return null;
        }
        String normalized = meetingType.trim();
        return (normalized == 'Online' || normalized == 'In-person') ? normalized : null;
    }

    private static Date parseDateValue(String dateValue) {
        if (String.isBlank(dateValue)) {
            return null;
        }
        String normalizedDateValue = dateValue.trim();
        if (normalizedDateValue.contains('T')) {
            normalizedDateValue = normalizedDateValue.substringBefore('T');
        }
        if (normalizedDateValue.contains(' ')) {
            normalizedDateValue = normalizedDateValue.substringBefore(' ');
        }
        try {
            return Date.valueOf(normalizedDateValue);
        } catch (TypeException ex) {
            return null;
        }
    }

    private static Time parseTimeValue(String timeValue) {
        if (String.isBlank(timeValue)) {
            return null;
        }

        String value = timeValue.trim().replace('Z', '');
        List<String> hourAndRemainder = value.split(':');
        if (hourAndRemainder.size() < 2 || hourAndRemainder.size() > 3) {
            return null;
        }

        if (String.isNotBlank(hourAndRemainder[0].replaceAll('[0-9]', '')) ||
            String.isNotBlank(hourAndRemainder[1].replaceAll('[0-9]', ''))) {
            return null;
        }

        Integer hour;
        Integer minute;
        Integer second = 0;
        try {
            hour = Integer.valueOf(hourAndRemainder[0]);
            minute = Integer.valueOf(hourAndRemainder[1]);
        } catch (Exception ex) {
            return null;
        }

        if (hourAndRemainder.size() == 3) {
            String secondValue = hourAndRemainder[2];
            if (secondValue.contains('.')) {
                secondValue = secondValue.substringBefore('.');
            }
            if (String.isBlank(secondValue) || String.isNotBlank(secondValue.replaceAll('[0-9]', ''))) {
                return null;
            }
            try {
                second = Integer.valueOf(secondValue);
            } catch (Exception ex) {
                return null;
            }
        }

        if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
            return null;
        }
        return Time.newInstance(hour, minute, second, 0);
    }

    private static String buildTimeLabel(Time startTime, Time endTime) {
        if (startTime == null && endTime == null) {
            return '';
        }
        if (startTime != null && endTime != null) {
            return formatTime(startTime) + ' - ' + formatTime(endTime);
        }
        return startTime != null ? formatTime(startTime) : formatTime(endTime);
    }

    private static String formatTime(Time value) {
        if (value == null) {
            return '';
        }

        Integer hour24 = value.hour();
        Integer minute = value.minute();
        Integer hour12 = Math.mod(hour24 + 11, 12) + 1;
        String meridian = hour24 >= 12 ? 'PM' : 'AM';
        return String.valueOf(hour12) + ':' + String.valueOf(minute).leftPad(2, '0') + ' ' + meridian;
    }

    private static String formatTimeForInput(Time value) {
        if (value == null) {
            return null;
        }
        return String.valueOf(value.hour()).leftPad(2, '0') + ':' + String.valueOf(value.minute()).leftPad(2, '0');
    }

    private static String mapUiStatus(
        String callStatus,
        Date meetDate,
        Time startTime,
        Time endTime,
        String meetingMode,
        Date today,
        Time nowTime,
        Boolean isViewerMentor,
        Boolean isRequestedByViewer
    ) {
        if (callStatus == 'Requested') {
            if (isRequestedByViewer != true) {
                return 'request';
            }
            return 'awaiting';
        }
        if (callStatus == 'Accepted') {
            if (meetDate == null) {
                return 'request';
            }
            // Auto-complete: date is past, OR it's today and the end time has passed
            Boolean pastDate = meetDate < today;
            Boolean endedToday = meetDate == today && endTime != null && nowTime > endTime;
            if (pastDate || endedToday) {
                return 'completed';
            }
            if (meetDate == today && startTime != null && endTime != null && nowTime >= startTime && nowTime <= endTime) {
                return 'happening';
            }
            if (meetingMode == 'Online') {
                return 'video';
            }
            return 'request';
        }
        if (callStatus == 'Scheduled') {
            return 'request';
        }
        return 'request';
    }

    private static Boolean isHiddenStatus(String callStatus) {
        return callStatus == 'Rejected' || callStatus == 'Cancelled';
    }

    private static String buildTopic(Ken_Mentorship__c rec) {
        if (String.isBlank(rec.Meeting_Description__c)) {
            return null;
        }
        String stripped = rec.Meeting_Description__c.replaceAll('<[^>]+>', ' ').trim();
        return stripped.length() > 120 ? stripped.substring(0, 120) + '...' : stripped;
    }

    private static String buildDescriptionText(Ken_Mentorship__c rec) {
        if (String.isBlank(rec.Meeting_Description__c)) {
            return null;
        }
        return rec.Meeting_Description__c.replaceAll('<[^>]+>', ' ').trim();
    }

    private static TaskRow mapTaskRow(Task rec) {
        TaskRow row = new TaskRow();
        row.id = rec.Id;
        row.title = rec.Subject;
        row.status = normalizeTaskStatusForLwc(rec.Status);
        row.description = rec.Description;
        row.descriptionHtml = rec.Description_Html__c;
        row.priority = rec.Priority;
        row.endDate = rec.ActivityDate != null ? String.valueOf(rec.ActivityDate) : null;
        row.assignTo = rec.Assign_To__c;
        row.mentorId = rec.Mentor__c;
        row.canEdit = rec.CreatedById == UserInfo.getUserId();
        Boolean isMenteeAssignee = rec.Assign_To__c == TASK_ASSIGN_TO_MENTEE;
        row.assigneeId = isMenteeAssignee ? rec.Mentee__c : rec.Mentor__c;

        if (isMenteeAssignee) {
            row.assigneeName = rec.Mentee__r != null && String.isNotBlank(rec.Mentee__r.Name)
                ? rec.Mentee__r.Name
                : TASK_ASSIGN_TO_MENTEE;
        } else {
            row.assigneeName = rec.Mentor__r != null ? rec.Mentor__r.Name : null;
        }

        String assigneePhoto = isMenteeAssignee
            ? (rec.Mentee__r != null ? rec.Mentee__r.PhotoUrl : null)
            : (rec.Mentor__r != null ? rec.Mentor__r.PhotoUrl : null);
        row.assigneeAvatar = String.isNotBlank(assigneePhoto)
            ? URL.getOrgDomainUrl().toExternalForm() + assigneePhoto
            : null;
        return row;
    }

    private static String normalizeTaskStatus(String status) {
        if (String.isBlank(status)) {
            return null;
        }
        String normalizedStatus = status.trim();
        if (normalizedStatus == 'Active' ||
            normalizedStatus == 'In Progress' ||
            normalizedStatus == 'On-Hold' ||
            normalizedStatus == 'Completed' ||
            normalizedStatus == 'Pending') {
            return normalizedStatus;
        }
        return null;
    }

    // Task.Status uses the LWC values directly (Pending, Active, In Progress, On-Hold,
    // Completed) which were added to the TaskStatus standard picklist. Legacy records that
    // still carry stock standard values are coerced into the LWC vocabulary on read.
    @TestVisible
    private static String normalizeTaskStatusForLwc(String standardStatus) {
        if (String.isBlank(standardStatus)) return 'Pending';
        String s = standardStatus.trim();
        if (s == 'Pending' || s == 'Active' || s == 'In Progress' || s == 'On-Hold' || s == 'Completed') {
            return s;
        }
        if (s == 'Not Started')                       return 'Pending';
        if (s == 'Deferred')                          return 'Active';
        if (s == 'Waiting on someone else')           return 'On-Hold';
        if (s == 'Completed')                         return 'Completed';
        return 'Pending';
    }

    private static String normalizeTaskPriority(String priority) {
        if (String.isBlank(priority)) {
            return null;
        }
        String normalizedPriority = priority.trim();
        if (normalizedPriority == 'High' || normalizedPriority == 'Medium' || normalizedPriority == 'Low') {
            return normalizedPriority;
        }
        return null;
    }

    private static String normalizeTaskAssignTo(String assignTo) {
        if (String.isBlank(assignTo)) {
            return TASK_ASSIGN_TO_MENTEE;
        }
        String normalizedAssignTo = assignTo.trim().toLowerCase();
        if (normalizedAssignTo == 'mentor') {
            return TASK_ASSIGN_TO_MENTOR;
        }
        if (normalizedAssignTo == 'mentee') {
            return TASK_ASSIGN_TO_MENTEE;
        }
        return TASK_ASSIGN_TO_MENTEE;
    }

    private static String normalizeCallParticipantType(String participantType) {
        if (String.isBlank(participantType)) {
            return CALL_PARTICIPANT_MENTOR;
        }
        String normalized = participantType.trim().toLowerCase();
        if (normalized == CALL_PARTICIPANT_MENTEE) {
            return CALL_PARTICIPANT_MENTEE;
        }
        return CALL_PARTICIPANT_MENTOR;
    }

    @AuraEnabled(cacheable=true)
    public static String getCurrentUserCity() {
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) return null;
        KenNetworkController.ProfileCardSummary summary =
            KenNetworkController.getProfileCardSummaries(new Set<Id>{ currentAccountId }).get(currentAccountId);
        return summary != null ? summary.currentCity : null;
    }

    @AuraEnabled(cacheable=true)
    public static Boolean getCurrentUserMentorPreference() {
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null || !Schema.sObjectType.Ken_Alumni_Preferences__c.isAccessible()) {
            return false;
        }
        List<Ken_Alumni_Preferences__c> prefs = [
            SELECT Willing_to_be_a_mentor__c
            FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c = :currentAccountId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return !prefs.isEmpty() && prefs[0].Willing_to_be_a_mentor__c == true;
    }
}