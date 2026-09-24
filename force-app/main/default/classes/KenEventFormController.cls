public with sharing class KenEventFormController {

    private static final String PERSON_ACCOUNT_RT_DEVNAME = 'PersonAccount';
    private static final String STATUS_APPROVED = 'Approved';
    
    @AuraEnabled(cacheable=true)
    public static List<Account> searchContact(String searchKey) {
        String query = '%' + searchKey + '%';
        return [
            SELECT Id, Name
            FROM Account
            WHERE IsPersonAccount = true
            AND Name LIKE :query
            WITH USER_MODE
            LIMIT 10
        ];
    }
    
    @AuraEnabled
    public static Account getContactDetails(Id accountId){
        try {
            return [
                SELECT Id, Name, PersonEmail
                FROM Account
                WHERE Id = :accountId
                AND IsPersonAccount = true
                WITH USER_MODE
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Account createContact(String name) {
        Account newAccount = new Account();
        Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(PERSON_ACCOUNT_RT_DEVNAME);
        if (rtInfo == null) {
            throw new AuraHandledException('Person Account record type is missing.');
        }
        newAccount.RecordTypeId = rtInfo.getRecordTypeId();
        newAccount.LastName = name;
        if (Schema.sObjectType.Account.isCreateable()) {
            insert newAccount;
        }
        return newAccount;
    }
    
    @AuraEnabled
    public static void deleteSpeaker(String recordId) {
        delete [select Id from Ken_Events_Sessions_Enrollment__c WHERE Id=:recordId WITH USER_MODE];
    }
    
    @AuraEnabled
    public static void deleteEventSession(String recordId) {
        try {

            if(String.isBlank(recordId)){
                throw new AuraHandledException('Record Id is required');
            }

            Ken_Schedule_Sessions__c sessionToDelete = [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Id = :recordId WITH USER_MODE LIMIT 1];
            List<Ken_Events_Sessions_Enrollment__c> enrollmentsToDelete = [SELECT Id FROM Ken_Events_Sessions_Enrollment__c WHERE Schedule_Sessions__c = :recordId WITH USER_MODE];

            if (!enrollmentsToDelete.isEmpty()) {
                if (!Schema.sObjectType.Ken_Events_Sessions_Enrollment__c.isDeletable()) {
                    throw new KenCrudException('Ken_Events_Sessions_Enrollment__c is not deletable by the current user.');
                }
                delete enrollmentsToDelete;
            }
            if (!Schema.sObjectType.Ken_Schedule_Sessions__c.isDeletable()) {
                throw new KenCrudException('Ken_Schedule_Sessions__c is not deletable by the current user.');
            }
            delete sessionToDelete;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<EventScheduleWrapper> getEventSchedule(String recordId) {
        try {
            
            List<Ken_Schedule_Sessions__c> eventSchedule = [
                SELECT
                Id,
                What_to_Expect_From_Event__c,
                Name,(SELECT Id, Person_Account__r.Name,Person_Account__c, Description__c,Speaker_Image__c,Schedule_Sessions__c,Speaker_Name__c,Speaker_Email__c,Send_Invite__c FROM Event_Session_Account_Associations__r),
                Session_Broucher__c,
                Event_Reference__c,
                Location_Type__c,
                Session_Link__c,
                Location__c,
                Session_Fee__c,
                No_Fee__c,
                Broucher_Type__c,
                Broucher_Name__c,
                Survey__c,
                Survey__r.Assessment_Question_Set__c,
                Feedback_Trigger_Type__c,
                Feedback_Trigger_When__c,
                Start_DateTime__c,
                End_DateTime__c,
                Feedback_End_DateTime__c,
                Meals__c
                FROM Ken_Schedule_Sessions__c
                WHERE Event_Reference__c = :recordId
            WITH USER_MODE
            ];
            
            Set<Id> questionSetIds = new Set<Id>();
            for (Ken_Schedule_Sessions__c s : eventSchedule) {
                if (s.Survey__r != null && s.Survey__r.Assessment_Question_Set__c != null) {
                    questionSetIds.add(s.Survey__r.Assessment_Question_Set__c);
                }
            }
            Map<Id, List<KenAssessmentSurveyService.QuestionRow>> questionsBySet =
                KenAssessmentSurveyService.questionsBySet(questionSetIds);

            List<EventScheduleWrapper> eventScheduleList = new List<EventScheduleWrapper>();
            if(!eventSchedule.isEmpty()){
                for (Ken_Schedule_Sessions__c eachSchedule : eventSchedule) {
                    EventScheduleWrapper eventSc = new EventScheduleWrapper(eachSchedule);
                    Id setId = eachSchedule.Survey__r != null
                        ? eachSchedule.Survey__r.Assessment_Question_Set__c : null;
                    if (setId != null && questionsBySet.containsKey(setId)) {
                        eventSc.questionnaireParams = questionsBySet.get(setId);
                    }
                    eventScheduleList.add(eventSc);
                }
            }

            return eventScheduleList;
            
        } catch (Exception ex) {
            System.debug('Error in getEventSchedule: ' + ex.getMessage()+'at line '+ex.getLineNumber());
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void saveFeedbackTriggerSettings(Id sessionId, String triggerType, String triggerWhen, String endDate, String endTime) {
        try {
            if (sessionId == null) {
                throw new AuraHandledException('Session Id is required.');
            }

            if (!Schema.sObjectType.Ken_Schedule_Sessions__c.isUpdateable()) {
                throw new AuraHandledException('You do not have permission to update schedule sessions.');
            }

            Ken_Schedule_Sessions__c updateSession = new Ken_Schedule_Sessions__c(Id = sessionId);

            String normalizedType = normalizeFeedbackTriggerType(triggerType);
            String normalizedWhen = normalizeFeedbackTriggerWhen(triggerWhen);

            if (Schema.sObjectType.Ken_Schedule_Sessions__c.fields.Feedback_Trigger_Type__c.isUpdateable()) {
                updateSession.Feedback_Trigger_Type__c = normalizedType;
            }
            if (Schema.sObjectType.Ken_Schedule_Sessions__c.fields.Feedback_Trigger_When__c.isUpdateable()) {
                updateSession.Feedback_Trigger_When__c = normalizedWhen;
            }
            if (Schema.sObjectType.Ken_Schedule_Sessions__c.fields.Feedback_End_DateTime__c.isUpdateable()) {
                // endTime arrives as the UTC wall clock that <lightning-input
                // type="time"> emits, so pairing it with the date as GMT gives
                // the instant directly.
                updateSession.Feedback_End_DateTime__c = resolveInstant(
                    null,
                    String.isNotBlank(endDate) ? Date.valueOf(endDate) : null,
                    parseUtcTime(endTime)
                );
            }

            update updateSession;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static String normalizeFeedbackTriggerType(String triggerType) {
        if (String.isBlank(triggerType)) {
            return null;
        }
        String normalized = triggerType.trim().toLowerCase();
        if (normalized == 'auto' || normalized == 'auto-trigger') {
            return 'Auto-trigger';
        }
        if (normalized == 'manual' || normalized == 'trigger manually after session') {
            return 'Trigger manually after session';
        }
        return triggerType;
    }

    private static String normalizeFeedbackTriggerWhen(String triggerWhen) {
        if (String.isBlank(triggerWhen)) {
            return null;
        }
        String normalized = triggerWhen.trim().toLowerCase();
        if (normalized == 'custom' || normalized == 'custom date & time' || normalized == 'custom date &amp; time') {
            return 'Custom date & time';
        }
        if (normalized == 'session_end' || normalized == 'at session end') {
            return 'At Session end';
        }
        return triggerWhen;
    }

    /**
     * @description Reads an "HH:mm" fragment as a UTC wall clock, without the
     *              legacy +5:30 compensation, which no longer exists.
     *
     * @param value "HH:mm" or "HH:mm:ss.sssZ", or blank
     * @return      the Time, or null
     */
    @TestVisible
    private static Time parseUtcTime(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String raw = value.contains('T') ? value.substringAfter('T') : value;
        raw = raw.replace('Z', '');
        List<String> parts = raw.split(':');
        if (parts.size() < 2) {
            return null;
        }
        try {
            return Time.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 0, 0);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Resolves the instant to store, preferring what the component
     *              sent and falling back to the legacy Date + Time pair for
     *              callers not yet migrated. The fallback reads the Time as a
     *              UTC wall clock, which is what <lightning-input type="time">
     *              produces.
     *
     *              The fallback cannot be exact across midnight, because a bare
     *              Time carries no day — a 00:30 IST session arrives as 19:00
     *              belonging to the previous UTC date, and nothing in the pair
     *              records that. That gap is the whole reason for the instant.
     *
     * @param iso          instant from the component, preferred when present
     * @param fallbackDate legacy Date
     * @param fallbackTime legacy Time, read as UTC
     * @return             the instant to store, or null
     */
    @TestVisible
    private static DateTime resolveInstant(String iso, Date fallbackDate, Time fallbackTime) {
        DateTime parsed = KenDateTimeUtil.parseInstant(iso);
        if (parsed != null) {
            return parsed;
        }
        if (fallbackDate == null || fallbackTime == null) {
            return null;
        }
        return DateTime.newInstanceGmt(fallbackDate, fallbackTime);
    }
    
    @AuraEnabled
    public static void createEventSchedule(String records) {

        try {

            if(String.isBlank(records)){
                throw new AuraHandledException('Records are required');
            }

            // Empty strings ("") for typed fields (Time/Date/Decimal — e.g. an unset
            // end time or feedback end date/time) make JSON.deserialize throw
            // "Invalid format: ''". Treat any empty-string value as null first.
            records = records.replaceAll(':\\s*""', ':null');

            Id speakerRecordType = Schema.SObjectType.Ken_Events_Sessions_Enrollment__c.getRecordTypeInfosByDeveloperName().get('Speaker_Enrollment')?.getRecordTypeId();

            List<EventScheduleWrapper> requestBody = (List<EventScheduleWrapper>) JSON.deserialize(
                records,
                List<EventScheduleWrapper>.class
            );

            if (requestBody.isEmpty()) {
                return;
            }

            String eventId = requestBody[0].eventId;
            if (String.isBlank(eventId)) {
                throw new AuraHandledException('Event ID is required');
            }

            Set<Id> incomingSessionIds = new Set<Id>();
            Set<Id> sessionSpeakerEnrollmentIds = new Set<Id>();

            // Separate new vs existing sessions, tracking their position in requestBody
            List<Ken_Schedule_Sessions__c> newSessions = new List<Ken_Schedule_Sessions__c>();
            List<Ken_Schedule_Sessions__c> existingSessions = new List<Ken_Schedule_Sessions__c>();
            List<Integer> newSessionIndices = new List<Integer>();
            List<Integer> existingSessionIndices = new List<Integer>();

            for (Integer i = 0; i < requestBody.size(); i++) {
                Ken_Schedule_Sessions__c session = requestBody[i].getRecord();
                if (String.isNotBlank(session.Id)) {
                    existingSessions.add(session);
                    existingSessionIndices.add(i);
                    incomingSessionIds.add(session.Id);
                } else {
                    newSessions.add(session);
                    newSessionIndices.add(i);
                }
            }

            // Sessions look up to the event. A portal host editing their own event
            // may lack sharing-level read on that event record, which makes the
            // lookup insert/update throw INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
            // under "with sharing". Persist in system context (mirrors EventReader).
            ScheduleWriter writer = new ScheduleWriter();
            // Insert new sessions first so their IDs are available for child enrollments
            writer.upsertSessions(existingSessions, newSessions);
            if (!newSessions.isEmpty()) {
                for (Ken_Schedule_Sessions__c s : newSessions) {
                    incomingSessionIds.add(s.Id);
                }
            }

            // Build enrollment DML lists
            List<Ken_Events_Sessions_Enrollment__c> enrollmentsToInsert = new List<Ken_Events_Sessions_Enrollment__c>();
            List<Ken_Events_Sessions_Enrollment__c> enrollmentsToUpdate = new List<Ken_Events_Sessions_Enrollment__c>();

            for (Integer i = 0; i < existingSessionIndices.size(); i++) {
                String sessionId = existingSessions[i].Id;
                for (SpeakerWrapper speaker : requestBody[existingSessionIndices[i]].speakers) {
                    Ken_Events_Sessions_Enrollment__c enrollment = speaker.getSessionEnrollmentRecord();
                    if (String.isNotBlank(speakerRecordType)) {
                        enrollment.RecordTypeId = speakerRecordType;
                    }
                    enrollment.Schedule_Sessions__c = sessionId;
                    if (String.isNotBlank(enrollment.Id)) {
                        enrollmentsToUpdate.add(enrollment);
                        sessionSpeakerEnrollmentIds.add(enrollment.Id);
                    } else {
                        enrollmentsToInsert.add(enrollment);
                    }
                }
            }

            for (Integer i = 0; i < newSessionIndices.size(); i++) {
                String sessionId = newSessions[i].Id;
                for (SpeakerWrapper speaker : requestBody[newSessionIndices[i]].speakers) {
                    Ken_Events_Sessions_Enrollment__c enrollment = speaker.getSessionEnrollmentRecord();
                    if (String.isNotBlank(speakerRecordType)) {
                        enrollment.RecordTypeId = speakerRecordType;
                    }
                    enrollment.Schedule_Sessions__c = sessionId;
                    if (String.isNotBlank(enrollment.Id)) {
                        enrollmentsToUpdate.add(enrollment);
                        sessionSpeakerEnrollmentIds.add(enrollment.Id);
                    } else {
                        enrollmentsToInsert.add(enrollment);
                    }
                }
            }

            // Delete stale records (enrollments before sessions to respect FK constraints)
            List<Ken_Events_Sessions_Enrollment__c> enrollmentsToDelete = new List<Ken_Events_Sessions_Enrollment__c>();

            if (!requestBody[0]?.isPortal) {
                List<Ken_Schedule_Sessions__c> sessionsToDelete = [
                    SELECT Id
                    FROM Ken_Schedule_Sessions__c
                    WHERE Event_Reference__c = :eventId
                    AND Id NOT IN :incomingSessionIds
                WITH USER_MODE
                ];
                enrollmentsToDelete = [
                    SELECT Id
                    FROM Ken_Events_Sessions_Enrollment__c
                    WHERE Schedule_Sessions__r.Event_Reference__c = :eventId
                    AND Id NOT IN :sessionSpeakerEnrollmentIds
                WITH USER_MODE
                ];
                if (!enrollmentsToDelete.isEmpty()) {
                    if (!Schema.sObjectType.Ken_Events_Sessions_Enrollment__c.isDeletable()) {
                        throw new KenCrudException('Ken_Events_Sessions_Enrollment__c is not deletable by the current user.');
                    }
                    delete enrollmentsToDelete;
                }
                if (!sessionsToDelete.isEmpty()) {
                    if (!Schema.sObjectType.Ken_Schedule_Sessions__c.isDeletable()) {
                        throw new KenCrudException('Ken_Schedule_Sessions__c is not deletable by the current user.');
                    }
                    delete sessionsToDelete;
                }
            } else if (!incomingSessionIds.isEmpty()) {
                enrollmentsToDelete = [
                    SELECT Id
                    FROM Ken_Events_Sessions_Enrollment__c
                    WHERE Schedule_Sessions__c IN :incomingSessionIds
                    AND Id NOT IN :sessionSpeakerEnrollmentIds
                WITH USER_MODE
                ];
                if (!enrollmentsToDelete.isEmpty()) {
                    if (!Schema.sObjectType.Ken_Events_Sessions_Enrollment__c.isDeletable()) {
                        throw new KenCrudException('Ken_Events_Sessions_Enrollment__c is not deletable by the current user.');
                    }
                    delete enrollmentsToDelete;
                }
            }

            writer.upsertEnrollments(enrollmentsToUpdate, enrollmentsToInsert);

        } catch (Exception e) {
            // Surface the real cause. A bare AuraHandledException(msg) where msg is
            // empty/another AuraHandledException shows the opaque "Script-thrown
            // exception" on the client, so build an explicit detail and setMessage().
            String detail = e.getTypeName() + ': '
                + (String.isBlank(e.getMessage()) ? 'Unexpected error' : e.getMessage())
                + ' (line ' + e.getLineNumber() + ')';
            System.debug(LoggingLevel.ERROR, 'createEventSchedule failed — ' + detail + '\n' + e.getStackTraceString());
            AuraHandledException ex = new AuraHandledException(detail);
            ex.setMessage(detail);
            throw ex;
        }
    }

    // Performs the session + enrollment DML in system context so a portal host can
    // save the schedule for an event they own but don't have sharing-level access to.
    private without sharing class ScheduleWriter {
        void upsertSessions(List<Ken_Schedule_Sessions__c> toUpdate, List<Ken_Schedule_Sessions__c> toInsert) {
            if (toUpdate != null && !toUpdate.isEmpty()) {
                if (!Schema.sObjectType.Ken_Schedule_Sessions__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Schedule_Sessions__c is not updateable by the current user.');
                }
                update toUpdate;
            }
            if (toInsert != null && !toInsert.isEmpty()) {
                if (!Schema.sObjectType.Ken_Schedule_Sessions__c.isCreateable()) {
                    throw new KenCrudException('Ken_Schedule_Sessions__c is not createable by the current user.');
                }
                insert toInsert;
            }
        }
        void upsertEnrollments(List<Ken_Events_Sessions_Enrollment__c> toUpdate, List<Ken_Events_Sessions_Enrollment__c> toInsert) {
            if (toUpdate != null && !toUpdate.isEmpty()) {
                if (!Schema.sObjectType.Ken_Events_Sessions_Enrollment__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Events_Sessions_Enrollment__c is not updateable by the current user.');
                }
                update toUpdate;
            }
            if (toInsert != null && !toInsert.isEmpty()) {
                if (!Schema.sObjectType.Ken_Events_Sessions_Enrollment__c.isCreateable()) {
                    throw new KenCrudException('Ken_Events_Sessions_Enrollment__c is not createable by the current user.');
                }
                insert toInsert;
            }
        }
    }
    
    @AuraEnabled
    public static void insertSpeaker(String records){
        List<Ken_Events_Sessions_Enrollment__c> requestBody = (List<Ken_Events_Sessions_Enrollment__c>) JSON.deserialize(
            records,
            List<Ken_Events_Sessions_Enrollment__c>.class
        );
        if (Schema.sObjectType.Ken_Events_Sessions_Enrollment__c.isCreateable() || 
            Schema.sObjectType.Ken_Events_Sessions_Enrollment__c.isUpdateable()) {
        upsert requestBody;
    }
    
    }
    
    @AuraEnabled(cacheable=true)
    public static EventWrapper getEvent(String recordId){
        if (String.isBlank(recordId)) {
            throw new AuraHandledException('Event id is required.');
        }
        // Portal hosts manage their own events; the hosted list reads without sharing,
        // so the single-record read must be consistent or "continue draft" throws no-rows.
        List<Ken_Event_Master__c> events = new EventReader().fetchEvent(recordId);
        if (events.isEmpty()) {
            throw new AuraHandledException('Event not found or you do not have access to it.');
        }
        return new EventWrapper(events[0]);
    }

    private without sharing class EventReader {
        List<Ken_Event_Master__c> fetchEvent(String recordId) {
            return [SELECT Id, Name,Event_Current_Step__c,Language__c,Event_Status__c, Target_Topics__c,Event_Broucher__c, Broucher_Title__c, Description__c,createdDate,Event_Fee__c,No_Fee__c, Auto_Enroll_Target_Audience__c,RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c,Email_Subject__c,Email_Distribution_List__c,Email_Body__c,Schedule_DateTime__c,Email_Attachment__c,Can_Alumni_Bring_Guests__c,Guest_Count__c,Offer_Meals__c,Make_Meals_Paid__c,Collect_Dietary_Preferences__c,Dietary_Preferences__c,Meal_Fee__c  FROM Ken_Event_Master__c WHERE Id=:recordId WITH SECURITY_ENFORCED];
        }
    }
    
    @AuraEnabled
    public static Id saveEvent(string eventData){
        if (String.isBlank(eventData)) {
            throw new AuraHandledException('Event payload is required.');
        }
        Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
        EventWrapper requestBody = (EventWrapper) JSON.deserialize(
            eventData,
            EventWrapper.class
        );

        if (requestBody == null) {
            throw new AuraHandledException('Unable to parse event payload.');
        }

        Ken_Event_Master__c updateEvent = requestBody.getRecord();

        if (requestBody.isPortal == true && constituentRoleId != null) {
            updateEvent.Constituent_Role__c = constituentRoleId;
        }

        Id eventRecordType = Schema.SObjectType.Ken_Event_Master__c.getRecordTypeInfosByDeveloperName().get('Event')?.getRecordTypeId();
        if(String.isNotBlank(eventRecordType)) {
            updateEvent.RecordTypeId = eventRecordType;
        }

        try {
            // A portal host may not have sharing-level access to the event record
            // (e.g. continuing a draft they didn't personally own), which makes the
            // upsert throw under "with sharing". Persist in system context.
            new EventWriter().upsertEvent(updateEvent);
        } catch (Exception e) {
            String detail = e.getTypeName() + ': '
                + (String.isBlank(e.getMessage()) ? 'Unexpected error' : e.getMessage())
                + ' (line ' + e.getLineNumber() + ')';
            System.debug(LoggingLevel.ERROR, 'saveEvent failed — ' + detail + '\n' + e.getStackTraceString());
            AuraHandledException ex = new AuraHandledException(detail);
            ex.setMessage(detail);
            throw ex;
        }

        return updateEvent.Id;
    }

    // Persists the event in system context so a portal host can save/continue an
    // event they don't have row-level sharing for (mirrors EventReader/ScheduleWriter).
    private without sharing class EventWriter {
        void upsertEvent(Ken_Event_Master__c evt) {
            preserveApproval(evt);
            if (!Schema.sObjectType.Ken_Event_Master__c.isCreateable() || !Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
                throw new KenCrudException('Ken_Event_Master__c is not upsertable by the current user.');
            }
            upsert evt;
        }

        /**
         * @description The wizard stamps Draft on every save and In Review on every
         *              submit, so editing an approved event - even just to swap its
         *              banner - used to send it back through approval, and anything
         *              gated on Approved (the landing page, the public event lists)
         *              dropped it on the spot. An approval is a decision: only the
         *              approval flow reverses it, never an edit.
         *
         *              The read lives here, in the same system context as the write,
         *              because a portal host editing an event they don't own cannot
         *              see it under sharing - and a host who can't see it is exactly
         *              the caller this guard has to hold for.
         */
        void preserveApproval(Ken_Event_Master__c evt) {
            if (evt.Id == null || evt.Event_Status__c == null || evt.Event_Status__c == STATUS_APPROVED) {
                return;
            }
            for (Ken_Event_Master__c current : [
                SELECT Event_Status__c
                FROM Ken_Event_Master__c
                WHERE Id = :evt.Id
                WITH SECURITY_ENFORCED
                LIMIT 1
            ]) {
                if (current.Event_Status__c == STATUS_APPROVED) {
                    evt.Event_Status__c = STATUS_APPROVED;
                }
            }
        }
    }

    /**
     * @description Points an event at a segmentation, replacing whatever audience it had,
     *              and mirrors the change onto the event's wrapper surveys.
     * @param eventId Event to link.
     * @param segmentationId Segmentation to link.
     * @return Id of the event that now carries the audience.
     */
    @AuraEnabled
    public static Id createEventSegmentation(Id eventId, Id segmentationId) {
        if (eventId == null || segmentationId == null) {
            throw new AuraHandledException('Event Id and Segmentation Id are required.');
        }
        if (!Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to set the event audience.');
        }

        List<Ken_Event_Master__c> existing = [
            SELECT Id, Segmentation__c FROM Ken_Event_Master__c WHERE Id = :eventId
            WITH USER_MODE
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            throw new AuraHandledException('Event not found.');
        }
        if (existing[0].Segmentation__c != segmentationId) {
            update new Ken_Event_Master__c(Id = eventId, Segmentation__c = segmentationId);
        }
        syncEventAudienceToWrapperSurveys(eventId);
        return eventId;
    }
    
    @AuraEnabled
    public static void updateFee(Boolean isEventWise, Id eventId, Integer eventFee, Boolean isNoFee, List<Ken_Schedule_Sessions__c> sessionsMap) {
        // If event-wise fee update
        if (isEventWise) {
            // Fetch the event record
            Ken_Event_Master__c eventRecord = [SELECT Id, Event_Fee__c, No_Fee__c, Auto_Enroll_Target_Audience__c FROM Ken_Event_Master__c WHERE Id = :eventId WITH USER_MODE LIMIT 1];
            
            // Set the event-level fee or no-fee values
            eventRecord.Event_Fee__c = eventFee;
            eventRecord.No_Fee__c = isNoFee? isNofee : false;
            
            // Update the event record
            if (Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
            update eventRecord;
            }
        }
        else {
            List<Ken_Schedule_Sessions__c> sessionsToUpdate = new List<Ken_Schedule_Sessions__c>();
            for (Ken_Schedule_Sessions__c eachSession: sessionsMap) {
                Ken_Schedule_Sessions__c session = new Ken_Schedule_Sessions__c(Id=eachSession.Id);
                session.Session_Fee__c = eachSession.Session_Fee__c;
                session.No_Fee__c = eachSession.No_Fee__c? eachSession.No_Fee__c : false;
                sessionsToUpdate.add(session);
            }
            if (!sessionsToUpdate.isEmpty()) {
                if (Schema.sObjectType.Ken_Schedule_Sessions__c.isUpdateable()) {
                update sessionsToUpdate;
                }
            }
        }
    }    
    
    @AuraEnabled
    public static void savePreEventSurveyData(Id eventId, Boolean offerMeals, Boolean makeMealsPaid,
        Boolean collectDietary, String dietaryPreferences, String mealsByDateJson) {
        try {
            Ken_Event_Master__c evt = new Ken_Event_Master__c(Id = eventId);
            evt.Offer_Meals__c = offerMeals == true;
            evt.Make_Meals_Paid__c = (offerMeals == true) && (makeMealsPaid == true);
            evt.Collect_Dietary_Preferences__c = (offerMeals == true) && (collectDietary == true);
            evt.Dietary_Preferences__c = (offerMeals == true && collectDietary == true) ? dietaryPreferences : null;
            if (Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
                update evt;
            }

            Map<String, Object> mealsByDate = new Map<String, Object>();
            if (String.isNotBlank(mealsByDateJson)) {
                mealsByDate = (Map<String, Object>) JSON.deserializeUntyped(mealsByDateJson);
            }

            List<Ken_Schedule_Sessions__c> sessions = [
                SELECT Id, Start_DateTime__c, Meals__c
                FROM Ken_Schedule_Sessions__c
                WHERE Event_Reference__c = :eventId
            WITH USER_MODE
            ];
            List<Ken_Schedule_Sessions__c> toUpdate = new List<Ken_Schedule_Sessions__c>();
            for (Ken_Schedule_Sessions__c s : sessions) {
                String mealsValue = '';
                if (offerMeals == true && s.Start_DateTime__c != null) {
                    Date d = KenDateTimeUtil.localDate(s.Start_DateTime__c);
                    String dateKey = String.valueOf(d.year()) + '-' +
                        (d.month() < 10 ? '0' : '') + String.valueOf(d.month()) + '-' +
                        (d.day() < 10 ? '0' : '') + String.valueOf(d.day());
                    if (mealsByDate.containsKey(dateKey)) {
                        List<Object> mealList = (List<Object>) mealsByDate.get(dateKey);
                        List<String> meals = new List<String>();
                        for (Object m : mealList) {
                            meals.add(String.valueOf(m));
                        }
                        mealsValue = String.join(meals, ';');
                    }
                }
                s.Meals__c = mealsValue;
                toUpdate.add(s);
            }
            if (!toUpdate.isEmpty() && Schema.sObjectType.Ken_Schedule_Sessions__c.isUpdateable()) {
                update toUpdate;
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveMealFee(Id eventId, Decimal mealFee) {
        try {
            Ken_Event_Master__c evt = new Ken_Event_Master__c(Id = eventId);
            evt.Meal_Fee__c = mealFee;
            if (Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
                update evt;
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> searchContacts() {
        return [
            SELECT Id, Name
            FROM Account
            WHERE IsPersonAccount = true
        WITH USER_MODE

        ];
    }
    //GET SESSIONS    
    @AuraEnabled
    public static List<Ken_Schedule_Sessions__c> getEventSessions(string eventId) {
        
        return  [SELECT Id, Name, 
                 Session_Broucher__c,
                 Location_Type__c,Session_Link__c,
                 Event_Reference__c,Event_Reference__r.Event_Broucher__c,
                 Event_Reference__r.Event_banner__c,Event_Reference__r.Name,
                 Event_Reference__r.Event_Fee__c,Event_Reference__r.No_Fee__c,
                 Event_Reference__r.Auto_Enroll_Target_Audience__c,
                 Event_Reference__r.Event_Type__c, 
                 Event_Reference__r.Start_Date__c,
                 Event_Reference__r.End_Date__c,
                 Event_Reference__r.Max_Allowed_Participants__c,
                 Event_Reference__r.Description__c,
                 Event_Reference__r.Event_Status__c,
                 Session_Fee__c,What_to_Expect_From_Event__c, No_Fee__c, Location__c,
                 Start_DateTime__c, End_DateTime__c
                 FROM Ken_Schedule_Sessions__c WHERE Event_Reference__c =:eventId
                 WITH USER_MODE
                 ORDER BY Start_DateTime__c NULLS LAST];
    }
    
    /**
     * @description Type-ahead lookup over Event Group records.
     * @param searchKey       Text typed by the user, matched against Name.
     * @param sObjectApiName  API name of the target sObject. It arrives from the caller, so it is
     *                        resolved through the schema and re-read from the describe before it
     *                        reaches the query; an unresolvable name returns an empty list.
     * @return                List<SObject> with Id and Name populated, at most five rows.
     */
    @AuraEnabled(cacheable=true)
    public static list<sObject> fetchLookupData(string searchKey , string sObjectApiName) {
        List < sObject > returnList = new List < sObject > ();

        Schema.SObjectType resolvedType = KenNamespaceUtil.resolveSObjectType(sObjectApiName);
        if (String.isBlank(sObjectApiName) || resolvedType == null) {
            return returnList;
        }
        String safeObjectApiName = resolvedType.getDescribe().getName();

        string sWildCardText = '%' + searchKey + '%';
        String sQuery = 'SELECT Id, Name ' +
            'FROM ' + safeObjectApiName + ' ' +
            'WHERE Name LIKE :sWildCardText ' +
            'AND RecordType.DeveloperName = \'Event_Group\' ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT 5';
        for (sObject obj : Database.queryWithBinds(
                sQuery,
                new Map<String, Object>{ 'sWildCardText' => sWildCardText },
                AccessLevel.SYSTEM_MODE)) {
            returnList.add(obj);
        }
        return returnList;
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getPicklistValues(String objectName, List<String> fieldNames) {
        Map<String,List<Map<String,String>>> picklictValuesByField = new Map<String,List<Map<String,String>>>();
        try{
            Schema.SObjectType objectType = KenNamespaceUtil.resolveSObjectType(objectName);
            if (objectType == null) {
                throw new AuraHandledException('Object ' + objectName + ' not found');
            }
            
            Schema.DescribeSObjectResult describeObjResult = objectType.getDescribe();
            
            Map<String, Schema.SObjectField> fieldMap = describeObjResult.fields.getMap();
            for(String field : fieldNames){
                String fieldApiName = KenNamespaceUtil.qualifyCustom(field);
                if(!fieldMap.containsKey(fieldApiName)){
                    continue;
                }
                
                Schema.DescribeFieldResult fieldResult = fieldMap.get(fieldApiName).getDescribe();
                List<Map<String,String>> picklistValues = new List<Map<String,String>>();
                for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
                    picklistValues.add(new Map<String,String>{'label' => entry.getLabel(), 'value' => entry.getValue()});
                }
                picklictValuesByField.put(field,picklistValues);
            }
            
            return picklictValuesByField;
        }catch(Exception e){
            throw new AuraHandledException('Error retrieving picklist values: ' + e.getMessage());
        }
    }
    @AuraEnabled
    public static String saveData(String eventData) {
        EventWrapper wrapper = (EventWrapper) JSON.deserialize(eventData, EventWrapper.class);
        Id recordTypeId = Schema.SObjectType.Ken_Event_Master__c.getRecordTypeInfosByName().get('Event Group').getRecordTypeId();
        
        Ken_Event_Master__c record = new Ken_Event_Master__c();
        record.Id =  String.isNotBlank(wrapper.Id) ? wrapper.Id : null;
        record.Name = (wrapper.eventGroupTitle != null && wrapper.eventGroupTitle != '') ? wrapper.eventGroupTitle : wrapper.eventTitle;
        
        if (wrapper.isEventGroup) {
            record.RecordTypeId = recordTypeId;
        }
        if (wrapper.eventGroupId != null && wrapper.eventGroupId != '') {
            record.Evvent_Group__c = wrapper.eventGroupId;
        }
        if (wrapper.startdate != null) {
            record.Start_Date__c = wrapper.startdate;
        }
        if (wrapper.enddate != null) {
            record.End_Date__c = wrapper.enddate;
        }
        
        record.Event_Type__c = wrapper.eventTypes;
        record.Description__c = wrapper.description;
        record.Target_Topics__c = wrapper.agenda;
        record.Event_banner__c = String.isNotBlank(wrapper.image) ? KenCreateContentVersion.createContentVersion(wrapper.imageFileName, wrapper.image) : null;
        record.Max_Allowed_Participants__c = wrapper.maximumNumberOfParticipants;
        if (Schema.sObjectType.Ken_Event_Master__c.isCreateable() || Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
        upsert record;
        }

        
        return record.Id;
    }
    
    @AuraEnabled
    public static void deleteSessionsData(List<Date> selectedDates,String eventId){
        try{
            if(String.isBlank(eventId)){
                throw new AuraHandledException('Event Id is required');
            }

            // The day is derived from the stored instant, so the filter cannot be
            // pushed into SOQL any more — a DateTime column has no "NOT IN a list
            // of dates" form that respects the viewer's zone. Sessions per event
            // are few, so deciding in Apex is cheap and exact.
            //
            // A session with no instant is deliberately treated as unmatched and
            // therefore deleted, which is what the old NOT IN did with a null
            // Start_Date__c.
            Set<Date> keepDays = selectedDates == null ? new Set<Date>() : new Set<Date>(selectedDates);
            Map<Id,Ken_Schedule_Sessions__c> sessionsToDelete = new Map<Id,Ken_Schedule_Sessions__c>();
            for (Ken_Schedule_Sessions__c s : [
                SELECT Id, Start_DateTime__c
                FROM Ken_Schedule_Sessions__c
                WHERE Event_Reference__c = :eventId
            WITH USER_MODE
            ]) {
                Date day = KenDateTimeUtil.localDate(s.Start_DateTime__c);
                if (day == null || !keepDays.contains(day)) {
                    sessionsToDelete.put(s.Id, s);
                }
            }
            List<Ken_Events_Sessions_Enrollment__c> enrollmentsToDelete = [SELECT Id FROM Ken_Events_Sessions_Enrollment__c WHERE Schedule_Sessions__c IN :sessionsToDelete.keySet() WITH USER_MODE];

            if (!enrollmentsToDelete.isEmpty()) {
                if (!Schema.sObjectType.Ken_Events_Sessions_Enrollment__c.isDeletable()) {
                    throw new KenCrudException('Ken_Events_Sessions_Enrollment__c is not deletable by the current user.');
                }
                delete enrollmentsToDelete;
            }
            if (!sessionsToDelete.isEmpty()) {
                delete sessionsToDelete.values();
            }
        }catch(Exception e){
            throw new AuraHandledException('Error Deleting Session Data: ' + e.getMessage());
        }
    }
    
    public class EventWrapper {
        @AuraEnabled
        public String Id { get; set; }
        @AuraEnabled
        public String contentDocumentId { get; set; }
        @AuraEnabled
        public Boolean isEventGroup { get; set; }
        @AuraEnabled
        public String eventTitle { get; set; }
        @AuraEnabled
        public String eventGroupId { get; set; }
        @AuraEnabled
        public String eventGroupTitle { get; set; }
        @AuraEnabled
        public String eventTypes { get; set; }
        @AuraEnabled
        public String eventStatus { get; set; }
        @AuraEnabled
        public String description { get; set; }
        @AuraEnabled
        public String agenda { get; set; }
        @AuraEnabled
        public Date startDate { get; set; }
        @AuraEnabled
        public Date endDate { get; set; }
        @AuraEnabled
        public String image { get; set; }
        @AuraEnabled
        public String imageFileName { get; set; }
        @AuraEnabled
        public Decimal maximumNumberOfParticipants { get; set; }
        @AuraEnabled
        public String targetKeywords { get; set; }
        @AuraEnabled
        public String eventLanguages { get; set; }
        @AuraEnabled
        public String eventExpectations { get; set; }
        @AuraEnabled
        public String targetAudienceApplicable { get; set; }
        @AuraEnabled
        public String broucherFileName { get; set; }
        @AuraEnabled
        public String broucher { get; set; }
        @AuraEnabled
        public Integer currentStep { get; set; }
        @AuraEnabled
        public Boolean isPortal { get; set; }
		@AuraEnabled
        public Boolean noFee { get; set; }
        @AuraEnabled
        public Boolean enrollTargetAudience { get; set; }
        @AuraEnabled
        public Boolean canAlumniBringGuests { get; set; }
        @AuraEnabled
        public decimal guestCount { get; set; }
        @AuraEnabled
        public String emailSubject { get; set; }
        @AuraEnabled
        public String emailDistributionList { get; set; }
        @AuraEnabled 
        public String emailBody { get; set; }
        @AuraEnabled 
        public String scheduleDate  { get; set; }
        @AuraEnabled 
        public String scheduleTime  { get; set; }
        @AuraEnabled
        public String emailAttachment  { get; set; }
        @AuraEnabled
        public Boolean offerMeals { get; set; }
        @AuraEnabled
        public Boolean makeMealsPaid { get; set; }
        @AuraEnabled
        public Boolean collectDietary { get; set; }
        @AuraEnabled
        public String dietaryPreferences { get; set; }
        @AuraEnabled
        public Decimal mealFee { get; set; }

        public EventWrapper(Ken_Event_Master__c event){
            this.Id = event.Id;
            this.eventTitle = event.Name;
            this.eventTypes = event.Event_Type__c;
            this.startDate = event.Start_Date__c;
            this.endDate = event.End_Date__c;
            this.description = event.Description__c;
            this.agenda =event.Target_Topics__c;
            this.eventExpectations = event.What_to_Expect_From_Event__c;
            this.targetKeyWords = event.Target_Topics__c;
            this.maximumNumberOfParticipants = event.Max_Allowed_Participants__c;
            this.image = event.Event_banner__c;
            this.broucher = event.Event_Broucher__c;
            this.broucherFileName = event.Broucher_Title__c;
            this.eventLanguages = event.Language__c;
            this.targetAudienceApplicable = event.Target_Audience_Applicable__c;
            this.currentStep = event.Event_Current_Step__c != null ? Integer.valueOf(event.Event_Current_Step__c) : null;
			this.noFee = event.No_Fee__c? event.No_Fee__c : false;
            this.enrollTargetAudience = event.Auto_Enroll_Target_Audience__c;
            this.canAlumniBringGuests = event.Can_Alumni_Bring_Guests__c;
            this.guestCount = event.Guest_Count__c;
            this.emailSubject = event.Email_Subject__c;
            this.emailDistributionList = event.Email_Distribution_List__c;
            this.emailBody = event.Email_Body__c;
            // The scheduled send is a real moment, so Schedule_DateTime__c is the
            // single source and both halves are derived from it. instantFrom, not
            // a direct read: this wrapper is built from several different SOQL
            // statements and touching an unqueried field throws.
            String scheduleIso = KenDateTimeUtil.instantFrom(event, 'Schedule_DateTime__c');
            this.ScheduleDate = scheduleIso == null ? '' : scheduleIso.substring(0, 10);
            this.ScheduleTime = scheduleIso == null ? '' : scheduleIso.substring(11, 16);
            this.emailAttachment = event.Email_Attachment__c;
            this.offerMeals = event.Offer_Meals__c;
            this.makeMealsPaid = event.Make_Meals_Paid__c;
            this.collectDietary = event.Collect_Dietary_Preferences__c;
            this.dietaryPreferences = event.Dietary_Preferences__c;
            this.mealFee = event.Meal_Fee__c;
        }
        public Ken_Event_Master__c getRecord(){
            Ken_Event_Master__c updateEvent = new Ken_Event_Master__c();
            
            if(this.Id != null && this.Id != ''){
                updateEvent.Id = this.Id;
            } 
            if(this.eventTitle != null && this.eventTitle != ''){
                updateEvent.Name = this.eventTitle;
            }  
            if(this.eventTypes != null && this.eventTypes != ''){
                updateEvent.Event_Type__c = this.eventTypes;
            }  
            if(this.eventStatus != null && this.eventStatus != ''){
                updateEvent.Event_Status__c = this.eventStatus;
            }
            if(this.eventLanguages != null && this.eventLanguages != ''){
                updateEvent.Language__c = this.eventLanguages;
            }
            if(this.startDate != null){
                updateEvent.Start_Date__c = this.startDate;
            }   
            if(this.endDate != null){
                updateEvent.End_Date__c = this.endDate;
            }   
            if(this.description != null && this.description != ''){
                updateEvent.Description__c = this.description;
            }   
            if(this.agenda != null && this.agenda != ''){
                updateEvent.Target_Topics__c = this.agenda;
            } 
            if(this.eventExpectations != null && this.eventExpectations != ''){
                updateEvent.What_to_Expect_From_Event__c = this.eventExpectations;
            } 
            if(this.maximumNumberOfParticipants != null){
                updateEvent.Max_Allowed_Participants__c = this.maximumNumberOfParticipants;
            } 
            
            if(this.targetAudienceApplicable != null && this.targetAudienceApplicable != ''){
                updateEvent.Target_Audience_Applicable__c = this.targetAudienceApplicable;
            }
            if(this.currentStep != null){
                updateEvent.Event_Current_Step__c = this.currentStep;
            }
            if (this.broucher!= null && this.broucher !=''){
                if(!this.broucher.startsWith('http')){
                    Integer Index = this.broucher.indexOf(',');
                    if( Index != -1){
                        String  base64Content= this.broucher.substring(Index + 1);
                        string publicurl = KenCreateContentVersion.createContentVersion(this.broucherFileName, base64Content);
                        updateEvent.Event_Broucher__c = publicurl;
                        updateEvent.Broucher_Title__c = this.broucherFileName;
                    } else{
                        string publicurl = KenCreateContentVersion.createContentVersion(this.broucherFileName, this.broucher);
                        updateEvent.Event_Broucher__c = publicurl;
                        updateEvent.Broucher_Title__c = this.broucherFileName;
                    }
                } else{
                    updateEvent.Event_Broucher__c = this.broucher;
                    updateEvent.Broucher_Title__c = this.broucherFileName;
                }
            }
            
            if (this.image!= null && this.image !=''){
                if(!this.image.startsWith('http')){
                    Integer Index = this.image.indexOf(',');
                    if( Index != -1){
                        String  base64Content= this.image.substring(Index + 1);
                        string publicurl = KenCreateContentVersion.createContentVersion(this.imageFileName, base64Content);
                        updateEvent.Event_banner__c = publicurl;
                    } else{
						string publicurl = KenCreateContentVersion.createContentVersion(this.imageFileName, this.image);
                        updateEvent.Event_banner__c = publicurl;
                    }
                } else{
                    updateEvent.Event_banner__c = this.image;
                }
            }

			if(this.noFee != null){
                updateEvent.No_Fee__c = this.noFee ? this.noFee : false;
            } 
            if(this.enrollTargetAudience != null){
                updateEvent.Auto_Enroll_Target_Audience__c = this.enrollTargetAudience;
            } 
            if(this.canAlumniBringGuests != null){
                updateEvent.Can_Alumni_Bring_Guests__c = this.canAlumniBringGuests;
            }
            if(this.guestCount != null){
                updateEvent.Guest_Count__c = this.guestCount;
            }
             if(this.emailSubject != null && this.emailSubject != ''){
                 updateEvent.Email_Subject__c = this.emailSubject;
             }
            if(this.emailDistributionList != null && this.emailDistributionList != ''){
                updateEvent.Email_Distribution_List__c = this.emailDistributionList;
            }
            if(this.emailBody != null && this.emailBody != ''){
                updateEvent.Email_Body__c = this.emailBody;
            }
            // One field for the scheduled send. The date and time arrive as two
            // separate inputs, but only the combined instant is stored.
            if(this.ScheduleDate != null && this.ScheduleDate != ''
               && this.ScheduleTime != null && this.ScheduleTime != ''){
                List<String> timeParts = this.ScheduleTime.split(':');
                if(timeParts.size() == 2){
                    Integer hours = Integer.valueOf(timeParts[0]);
                    Integer minutes = Integer.valueOf(timeParts[1]);
                    // The send time comes from a plain <input type="time"> in
                    // kenPortalCreateEvent, so it is a local wall clock and the
                    // pair resolves in the running user's timezone.
                    updateEvent.Schedule_DateTime__c = DateTime.newInstance(
                        Date.valueOf(this.ScheduleDate),
                        Time.newInstance(hours, minutes, 0, 0)
                    );
                }
            }
            if(this.emailAttachment != null && this.emailAttachment != ''){
                updateEvent.Email_Attachment__c = KenCreateContentVersion.createContentVersion('EmailAttachment', this.emailAttachment);
            }   
            
            return updateEvent;
        }
    }
   @AuraEnabled
    public static Id uploadFileToRecord(String recordId, String fileName, String base64Data, String contentType) {
        Blob fileBody = EncodingUtil.base64Decode(base64Data);

        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = '/' + fileName;
        cv.VersionData = fileBody;
        cv.IsMajorVersion = true;
        Database.insert(cv, true, AccessLevel.USER_MODE);

        ContentVersion insertedCV = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH SYSTEM_MODE LIMIT 1];

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = insertedCV.ContentDocumentId;
        cdl.LinkedEntityId = recordId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        Database.insert(cdl, true, AccessLevel.USER_MODE);

        return insertedCV.ContentDocumentId;
    }

    
    public class EventScheduleWrapper {
        @AuraEnabled
        public String Id;
        @AuraEnabled
        public String agenda;
        @AuraEnabled
        public Date startDate;
        @AuraEnabled
        public Time startTime;
        @AuraEnabled
        public Time endTime;
        @AuraEnabled
        public Date endDate;
        @AuraEnabled
        public String feedbackTriggerType;
        @AuraEnabled
        public String feedbackTriggerWhen;
        @AuraEnabled
        public Date feedbackEndDate;
        @AuraEnabled
        public Time feedbackEndTime;
        @AuraEnabled
        public String questionnaireId;
        @AuraEnabled
        public String eventId;
        @AuraEnabled
        public String locationType;
        @AuraEnabled
        public String locationAddress;
        @AuraEnabled
        public String sessionLink;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String sessionBroucher;
        @AuraEnabled
        public String broucherFileType;
        @AuraEnabled
        public String sessionBroucherBase64;
        @AuraEnabled
        public String brochureFileName;
        @AuraEnabled
        public List<SpeakerWrapper> speakers;
        @AuraEnabled
        public Boolean isPortal;
        @AuraEnabled
        public Decimal sessionFee;
        @AuraEnabled
        public Boolean noFee;
        @AuraEnabled
        public String meals;
        @AuraEnabled
        public List<KenAssessmentSurveyService.QuestionRow> questionnaireParams;

        // ISO-8601 UTC instants produced by c/kenDateTime.toUtcInstant, e.g.
        // "2026-08-21T06:25:00.000Z". These are the authoritative values. The
        // startDate/startTime pair above is still written so the ~390 readers
        // that expect it keep working, and is retired once they have migrated.
        //
        // Only the instant survives a timezone change: a bare Time cannot say
        // which day it belongs to, which is what let a 00:30 IST session land
        // on the wrong date.
        @AuraEnabled
        public String startDateTime;
        @AuraEnabled
        public String endDateTime;
        @AuraEnabled
        public String feedbackEndDateTime;

        public EventScheduleWrapper() {
            this.speakers = new List<SpeakerWrapper>();
        }
        
        public EventScheduleWrapper(Ken_Schedule_Sessions__c eventSchedule) {
            this.Id = eventSchedule?.Id != null?eventSchedule.Id:'';
            this.agenda = eventSchedule.What_to_Expect_From_Event__c;
            // Derived from the one stored instant rather than a second column.
            this.startDate = KenDateTimeUtil.localDate(eventSchedule.Start_DateTime__c);
            this.eventId = eventSchedule.Event_Reference__c;
            this.sessionBroucher = eventSchedule.Session_Broucher__c;
            this.name = eventSchedule.Name;
            this.feedbackTriggerType = eventSchedule.Feedback_Trigger_Type__c;
            this.feedbackTriggerWhen = eventSchedule.Feedback_Trigger_When__c;
            this.feedbackEndDate = KenDateTimeUtil.localDate(eventSchedule.Feedback_End_DateTime__c);
            // Survey__r is not on every caller's query, and touching an unqueried
            // relationship throws rather than returning null.
            this.questionnaireId = eventSchedule.getPopulatedFieldsAsMap().containsKey(KenNamespaceUtil.qualifyCustom('Survey__r'))
                    && eventSchedule.Survey__r != null
                ? eventSchedule.Survey__r.Assessment_Question_Set__c
                : null;
            this.locationType = eventSchedule.Location_Type__c;
            this.locationAddress = eventSchedule.Location__c;
            this.sessionLink = eventSchedule.Session_Link__c;
            this.broucherFileType = eventSchedule.Broucher_Type__c;
            this.brochureFileName = eventSchedule.Broucher_Name__c;
            this.sessionFee = eventSchedule.Session_Fee__c;
            this.noFee = eventSchedule.No_Fee__c ? eventSchedule.No_Fee__c : false ;
            this.meals = eventSchedule.Meals__c;

            // Hand the LWC the instant when we have one. Rows saved before the
            // migration have only the Date + Time pair, so the field stays null
            // and the component falls back to those.
            this.startDateTime = KenDateTimeUtil.instantFrom(eventSchedule, 'Start_DateTime__c');
            this.endDateTime = KenDateTimeUtil.instantFrom(eventSchedule, 'End_DateTime__c');
            this.feedbackEndDateTime = KenDateTimeUtil.instantFrom(eventSchedule, 'Feedback_End_DateTime__c');
            
            // If there are speaker child records, map them to the SpeakerWrapper
            this.speakers = new List<SpeakerWrapper>();
            if (eventSchedule.Event_Session_Account_Associations__r != null) {
                for (Ken_Events_Sessions_Enrollment__c speakerRecord : eventSchedule.Event_Session_Account_Associations__r) {
                    this.speakers.add(new SpeakerWrapper(speakerRecord));
                }
            }
        }
        
        public Ken_Schedule_Sessions__c getRecord() {
            
            Ken_Schedule_Sessions__c es = new Ken_Schedule_Sessions__c();
            
            if (this.Id != null && this.Id !='') {
                es.Id = this.Id;}
            
            if (this.agenda != null && this.agenda !='') {
                es.What_to_Expect_From_Event__c = this.agenda;}
            
            // Authoritative UTC instants. Written first so that if the legacy
            // pair below is ever wrong, the instant is still right.
            DateTime startInstant = resolveInstant(this.startDateTime, this.startDate, this.startTime);
            if (startInstant != null) {
                es.Start_DateTime__c = startInstant; }

            DateTime endInstant = resolveInstant(this.endDateTime, this.endDate != null ? this.endDate : this.startDate, this.endTime);
            if (endInstant != null) {
                es.End_DateTime__c = endInstant; }


            if (this.feedbackTriggerType != null && this.feedbackTriggerType != '') {
                es.Feedback_Trigger_Type__c = this.feedbackTriggerType;
            }

            if (this.feedbackTriggerWhen != null && this.feedbackTriggerWhen != '') {
                es.Feedback_Trigger_When__c = this.feedbackTriggerWhen;
            }

            if (this.feedbackEndDate != null) {
            }

            DateTime feedbackInstant = resolveInstant(this.feedbackEndDateTime, this.feedbackEndDate, this.feedbackEndTime);
            if (feedbackInstant != null) {
                es.Feedback_End_DateTime__c = feedbackInstant;
            }

            
            if (this.eventId != null && this.eventId !=' ') {
                es.Event_Reference__c = this.eventId; }
            
            if (this.name != null && this.name !='') {
                es.Name = this.name; }
            
            if (this.locationType != null && this.locationType !='') {
                es.Location_Type__c = this.locationType; }
            
            if (this.locationAddress != null && this.locationAddress !='') {
                es.Location__c = this.locationAddress; }
            
            if (this.broucherFileType != null && this.broucherFileType !='') {
                es.Broucher_Type__c = this.broucherFileType; }
            
            if (this.sessionLink != null && this.sessionLink !='') {
                es.Session_Link__c = this.sessionLink; }
            
            if (this.brochureFileName != null && this.brochureFileName !='') {
                es.Broucher_Name__c = this.brochureFileName; }
            
            if (this.sessionBroucher!= null && this.sessionBroucher !=''){
                if(!this.sessionBroucher.startsWith('http')){
                    Integer Index = this.sessionBroucher.indexOf(',');
                    if( Index != -1){
                        String  base64Content= this.sessionBroucher.substring(Index + 1);
                        string publicurl = KenCreateContentVersion.createContentVersion(this.brochureFileName, base64Content);
                        es.Session_Broucher__c = publicurl;
                    }
                }
            }else{
                es.Session_Broucher__c = this.sessionBroucher;
            }

            es.Session_Fee__c = this.sessionFee;
         //   es.No_Fee__c = this.noFee ? this.noFee : false;
            es.No_Fee__c = this.noFee == true;
            return es;
        }
    }
    
    public class SpeakerWrapper {
        @AuraEnabled
        public String Id { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String description { get; set; }
        
        @AuraEnabled
        public String accountId { get; set; }
        @AuraEnabled
        public String speakerImage { get; set; }
        @AuraEnabled
        public String speakerImageBase64 { get; set; }
        @AuraEnabled
        public String email { get; set; }
        @AuraEnabled
        public Boolean sendInvite { get; set; }

        // Default Constructor
        public SpeakerWrapper() {}

        // Constructor to initialize the name and description from the related record
        public SpeakerWrapper(Ken_Events_Sessions_Enrollment__c speakerRecord) {
            this.name = speakerRecord.Person_Account__c != null ? speakerRecord.Person_Account__r.Name : speakerRecord.Speaker_Name__c;
            this.description = speakerRecord.Description__c != null ? speakerRecord.Description__c : '';
            this.Id = speakerRecord.Id != null ? speakerRecord.Id : null;
            this.accountId = speakerRecord.Person_Account__c != null ? speakerRecord.Person_Account__c : null;
            this.speakerImage = speakerRecord.Speaker_Image__c != null ? speakerRecord.Speaker_Image__c : null;
            this.email = speakerRecord.Speaker_Email__c;
            this.sendInvite = speakerRecord.Send_Invite__c == true;
        }
        public Ken_Events_Sessions_Enrollment__c getSessionEnrollmentRecord(){
            Ken_Events_Sessions_Enrollment__c speakerRecord = new Ken_Events_Sessions_Enrollment__c();
            if (this.description != null && this.description != '') {
                speakerRecord.Description__c = this.description;
            }
            if (this.Id != null && this.Id != '') {
                speakerRecord.Id = this.Id;
            }
            if (this.accountId != null && this.accountId!= '') {
                speakerRecord.Person_Account__c = this.accountId;
            }
            if (this.name != null && this.name!= '') {
                speakerRecord.Speaker_Name__c = this.name;
            }
            if (this.speakerImage != null && this.speakerImage!= '') {
                if(!this.speakerImage.startsWith('http')){
                    Integer Index = this.speakerImage.indexOf(',');
                    if( Index != -1){
                        String  base64Content= this.speakerImage.substring(Index + 1);
                        string publicurl = KenCreateContentVersion.createContentVersion('speakerImage.PNG', base64Content);
                        speakerRecord.Speaker_Image__c = publicurl;
                    }
                }
            }else{
                speakerRecord.Speaker_Image__c = this.speakerImage;
            }
            speakerRecord.Speaker_Email__c = this.email;
            speakerRecord.Send_Invite__c = this.sendInvite == true;
            return speakerRecord;
        }
    }

    public class FeeWrapper{
        @AuraEnabled
        public Decimal sessionFee{ get; set; }
        @AuraEnabled
        public Boolean noFee{ get; set; }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Questionnaire methods previously lived in KenQuestionnaireControllerClass,
    // which has moved to the Service & Support module. To keep the alumni event
    // module deployable independently, the event/session-scoped questionnaire
    // logic is owned here (it references Ken_Event_Master__c / Ken_Schedule_Sessions__c
    // which the S&S module doesn't have).
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description A questionnaire and its questions as the event builder consumes them.
     */
    public class QuestionnaireDTO {
        @AuraEnabled public Id questionSetId { get; set; }
        @AuraEnabled public List<KenAssessmentSurveyService.QuestionRow> questions { get; set; }
    }

    /**
     * @description One question being saved from the event builder. A linear scale carries its
     *              points in choices, each with its own label.
     */
    public class QuestionSaveDTO {
        @AuraEnabled public String text { get; set; }
        @AuraEnabled public String questionType { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public List<KenAssessmentSurveyService.ChoiceRow> choices { get; set; }
    }

    /**
     * @description Loads the questionnaire attached to an event's pre-event survey.
     * @param eventId Event to read.
     * @return The questionnaire, or null when the event has none.
     */
    @AuraEnabled(cacheable=true)
    public static QuestionnaireDTO getQuestionnaireByEventId(Id eventId) {
        try {
            if (eventId == null) {
                return null;
            }
            // Read in system context: a community registrant has no sharing access to the
            // event or its survey, so a with-sharing query returns 0 rows.
            List<Ken_Event_Master__c> events = new WosDml().eventForQuestionnaire(eventId);
            if (events.isEmpty() || events[0].Survey__r == null
                || events[0].Survey__r.Assessment_Question_Set__c == null) {
                return null;
            }
            return buildQuestionnaireDTO(events[0].Survey__r.Assessment_Question_Set__c);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Saves an event's pre-event survey questions.
     * @param eventId Event the survey belongs to.
     * @param surveyTitle Optional questionnaire title; defaults to the event name.
     * @param questions Questions in display order.
     * @return Id of the saved question set.
     */
    @AuraEnabled
    public static Id saveQuestionnaireForEvent(Id eventId, String surveyTitle, List<QuestionSaveDTO> questions) {
        try {
            if (eventId == null) {
                throw new AuraHandledException('Event Id is required.');
            }
            Ken_Event_Master__c eventRecord = [
                SELECT Id, Name, Description__c, Survey__c, Survey__r.Assessment_Question_Set__c,
                       Constituent_Role__c, Start_Date__c, End_Date__c
                FROM Ken_Event_Master__c
                WHERE Id = :eventId
                WITH USER_MODE
                LIMIT 1
            ];

            Id existingSetId = eventRecord.Survey__r != null
                ? eventRecord.Survey__r.Assessment_Question_Set__c : null;
            String title = String.isNotBlank(surveyTitle) ? surveyTitle : eventRecord.Name;
            Id questionSetId = KenAssessmentSurveyService.saveQuestionSet(
                existingSetId, title,
                toServiceInputs(questions)
            );

            Id surveyId = upsertWrapperSurvey(
                eventRecord.Survey__c, questionSetId, 'Survey',
                eventRecord.Name, eventRecord.Description__c, eventRecord.Constituent_Role__c,
                eventRecord.Start_Date__c, eventRecord.End_Date__c,
                eventRecord.Id, null
            );

            if (Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
                new WosDml().updateRecord(new Ken_Event_Master__c(
                    Id = eventRecord.Id,
                    Survey__c = surveyId
                ));
            }

            syncWrapperSurveyAudience(eventRecord.Id, new Set<Id>{ surveyId });
            return questionSetId;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Saves a session's feedback questions.
     * @param sessionId Session the feedback belongs to.
     * @param surveyTitle Optional questionnaire title; defaults to the session name.
     * @param questions Questions in display order.
     * @return Id of the saved question set.
     */
    @AuraEnabled
    public static Id saveQuestionnaireForSession(Id sessionId, String surveyTitle, List<QuestionSaveDTO> questions) {
        try {
            if (sessionId == null) {
                throw new AuraHandledException('Session Id is required.');
            }
            Ken_Schedule_Sessions__c sessionRecord = [
                SELECT Id, Name, Survey__c, Survey__r.Assessment_Question_Set__c,
                       What_to_Expect_From_Event__c, Start_DateTime__c, Event_Reference__c,
                       Event_Reference__r.Constituent_Role__c
                FROM Ken_Schedule_Sessions__c
                WHERE Id = :sessionId
                WITH USER_MODE
                LIMIT 1
            ];

            Id existingSetId = sessionRecord.Survey__r != null
                ? sessionRecord.Survey__r.Assessment_Question_Set__c : null;
            String title = String.isNotBlank(surveyTitle) ? surveyTitle : sessionRecord.Name;
            Id questionSetId = KenAssessmentSurveyService.saveQuestionSet(
                existingSetId, title,
                toServiceInputs(questions)
            );

            Id hostRole = sessionRecord.Event_Reference__r != null
                ? sessionRecord.Event_Reference__r.Constituent_Role__c : null;
            Id surveyId = upsertWrapperSurvey(
                sessionRecord.Survey__c, questionSetId, 'Feedback',
                sessionRecord.Name, sessionRecord.What_to_Expect_From_Event__c, hostRole,
                KenDateTimeUtil.localDate(sessionRecord.Start_DateTime__c),
                KenDateTimeUtil.localDate(sessionRecord.Start_DateTime__c),
                sessionRecord.Event_Reference__c, sessionRecord.Id
            );

            if (Schema.sObjectType.Ken_Schedule_Sessions__c.isUpdateable()) {
                new WosDml().updateRecord(new Ken_Schedule_Sessions__c(
                    Id = sessionRecord.Id,
                    Survey__c = surveyId
                ));
            }

            syncWrapperSurveyAudience(sessionRecord.Event_Reference__c, new Set<Id>{ surveyId });
            return questionSetId;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static QuestionnaireDTO buildQuestionnaireDTO(Id questionSetId) {
        List<AssessmentQuestionSet> sets = [
            SELECT Id, Name
            FROM AssessmentQuestionSet WHERE Id = :questionSetId
            WITH USER_MODE
            LIMIT 1
        ];
        if (sets.isEmpty()) {
            return null;
        }
        QuestionnaireDTO dto = new QuestionnaireDTO();
        dto.questionSetId = sets[0].Id;
        dto.questions = KenAssessmentSurveyService.questionsForSet(questionSetId);
        return dto;
    }

    private static List<KenAssessmentSurveyService.QuestionInput> toServiceInputs(List<QuestionSaveDTO> questions) {
        List<KenAssessmentSurveyService.QuestionInput> inputs = new List<KenAssessmentSurveyService.QuestionInput>();
        if (questions == null) {
            return inputs;
        }
        for (QuestionSaveDTO q : questions) {
            if (q == null) {
                continue;
            }
            KenAssessmentSurveyService.QuestionInput input = new KenAssessmentSurveyService.QuestionInput();
            input.text = q.text;
            input.questionType = q.questionType;
            input.required = q.required == true;
            input.choices = q.choices;
            inputs.add(input);
        }
        return inputs;
    }

    /**
     * Upserts the Ken_Survey__c wrapper that links an event/session to its questionnaire.
     * Event/Session point to this survey; the survey points back at them and at the
     * questionnaire, so the link is navigable from either record page.
     */
    private static Id upsertWrapperSurvey(Id existingSurveyId, Id questionnaireId, String surveyType,
        String name, String description, Id constituentRoleId, Date startDate, Date endDate,
        Id eventId, Id sessionId) {
        Ken_Survey__c survey = new Ken_Survey__c();
        if (existingSurveyId != null) survey.Id = existingSurveyId;
        survey.Event__c = eventId;
        survey.Session__c = sessionId;
        survey.Name = String.isBlank(name) ? surveyType : name;
        survey.Description__c = description;
        survey.Type__c = surveyType;
        survey.Assessment_Question_Set__c = questionnaireId;
        survey.Approval_Status__c = 'Approved';
        survey.Module__c = 'Alumni';
        survey.Is_Active__c = true;
        survey.Start_Date__c = startDate;
        survey.End_Date__c = endDate;
        if (constituentRoleId != null) survey.Constituent_Role__c = constituentRoleId;
        // Persist in system context: a portal host may lack sharing access to the
        // event's Constituent_Role (ConstituentRole) cross-reference, which would
        // otherwise throw INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY.
        new WosDml().upsertRecord(survey);
        return survey.Id;
    }

    /**
     * Entry point for the audience picker: pushes an event's saved audience down to every
     * Ken_Survey__c wrapper already created for the event and its sessions.
     *
     * The picker writes Ken_Event_Master__c.Segmentation__c through KenAudienceJunctionController,
     * which can run either before or after the questionnaire step has created those
     * wrappers, so the mirror has to be driven from both sides.
     *
     * @param eventId Event whose audience has just been saved.
     */
    public static void syncEventAudienceToWrapperSurveys(Id eventId) {
        syncWrapperSurveyAudience(eventId, wrapperSurveyIdsForEvent(eventId));
    }

    /**
     * Mirrors an event's audience onto the Ken_Survey__c wrappers that hang off it.
     *
     * The Survey module resolves a survey's target audience only from Ken_Survey__c's own
     * Segmentation__c — both the detail page's Target Audience card and the getSurveys()
     * eligibility filter. Event and session feedback wrappers take their audience from the
     * event, so without this mirror they render an empty audience and are filtered out of
     * every respondent's survey list.
     *
     * A cleared event audience is mirrored too, so a wrapper never keeps an audience the
     * event has dropped.
     *
     * Runs in system context: a portal host rarely holds sharing access to the wrapper
     * survey, which is created on their behalf either way.
     *
     * @param eventId Event whose audience is the source of truth.
     * @param surveyIds Wrapper surveys to bring in line with that audience.
     */
    private static void syncWrapperSurveyAudience(Id eventId, Set<Id> surveyIds) {
        if (eventId == null || surveyIds == null) {
            return;
        }
        surveyIds.remove(null);
        if (surveyIds.isEmpty()) {
            return;
        }

        WosDml dml = new WosDml();
        Id eventSegmentationId = null;
        for (Ken_Event_Master__c evt : dml.eventAudience(eventId)) {
            eventSegmentationId = evt.Segmentation__c;
        }

        List<Ken_Survey__c> toUpdate = new List<Ken_Survey__c>();
        for (Ken_Survey__c srv : dml.surveyAudiences(surveyIds)) {
            if (srv.Segmentation__c != eventSegmentationId) {
                toUpdate.add(new Ken_Survey__c(Id = srv.Id, Segmentation__c = eventSegmentationId));
            }
        }

        if (!toUpdate.isEmpty()) {
            dml.updateRecords(toUpdate);
        }
    }

    /**
     * Collects every Ken_Survey__c wrapper reachable from an event — the event's own
     * survey plus one per session — so an audience change can be pushed to all of them.
     *
     * @param eventId Event to walk.
     * @return Wrapper survey Ids, empty when the event has no questionnaire yet.
     */
    private static Set<Id> wrapperSurveyIdsForEvent(Id eventId) {
        Set<Id> surveyIds = new Set<Id>();
        if (eventId == null) {
            return surveyIds;
        }
        WosDml dml = new WosDml();
        for (Ken_Event_Master__c evt : dml.eventForQuestionnaire(eventId)) {
            if (evt.Survey__c != null) {
                surveyIds.add(evt.Survey__c);
            }
        }
        for (Ken_Schedule_Sessions__c ses : dml.sessionSurveysForEvent(eventId)) {
            if (ses.Survey__c != null) {
                surveyIds.add(ses.Survey__c);
            }
        }
        return surveyIds;
    }

    // System-context DML helper for the questionnaire/survey save path, mirroring
    // EventWriter/ScheduleWriter — portal hosts can't always reach these records or
    // their cross-references under sharing.
    private without sharing class WosDml {
        void upsertRecord(SObject rec) { Database.upsert(rec, true, AccessLevel.SYSTEM_MODE); }
        void updateRecord(SObject rec) { Database.update(rec, true, AccessLevel.SYSTEM_MODE); }
        void updateRecords(List<SObject> recs) { Database.update(recs, true, AccessLevel.SYSTEM_MODE); }
        List<Ken_Event_Master__c> eventAudience(Id eventId) {
            return [
                SELECT Id, Segmentation__c
                FROM Ken_Event_Master__c
                WHERE Id = :eventId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }
        List<Ken_Survey__c> surveyAudiences(Set<Id> surveyIds) {
            return [
                SELECT Id, Segmentation__c
                FROM Ken_Survey__c
                WHERE Id IN :surveyIds
            WITH SECURITY_ENFORCED
            ];
        }
        List<Ken_Schedule_Sessions__c> sessionSurveysForEvent(Id eventId) {
            return [
                SELECT Id, Survey__c
                FROM Ken_Schedule_Sessions__c
                WHERE Event_Reference__c = :eventId AND Survey__c != null
            WITH SECURITY_ENFORCED
            ];
        }
        List<Ken_Event_Master__c> eventForQuestionnaire(Id eventId) {
            return [
                SELECT Id, Survey__c, Survey__r.Assessment_Question_Set__c
                FROM Ken_Event_Master__c WHERE Id = :eventId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }
    }
}