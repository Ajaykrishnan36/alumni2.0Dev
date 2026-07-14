public with sharing class KenEventFormController {

    private static final String PERSON_ACCOUNT_RT_DEVNAME = 'Alumni_Person_Account';
    
    @AuraEnabled(cacheable=true)
    public static List<Account> searchContact(String searchKey) {
        String query = '%' + searchKey + '%';
        return [
            SELECT Id, Name
            FROM Account
            WHERE IsPersonAccount = true
            AND Name LIKE :query
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
        delete [select Id from Ken_Events_Sessions_Enrollment__c WHERE Id=:recordId];
    }
    
    @AuraEnabled
    public static void deleteEventSession(String recordId) {
        try {

            if(String.isBlank(recordId)){
                throw new AuraHandledException('Record Id is required');
            }

            Ken_Schedule_Sessions__c sessionToDelete = [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Id = :recordId LIMIT 1];
            List<Ken_Events_Sessions_Enrollment__c> enrollmentsToDelete = [SELECT Id FROM Ken_Events_Sessions_Enrollment__c WHERE Schedule_Sessions__c = :recordId];

            if (!enrollmentsToDelete.isEmpty()) {
                delete enrollmentsToDelete;
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
                Start_Date__c,
                Start_Time__c,
                End_Time__c,
                Location_Type__c,
                Session_Link__c,
                Location__c,
                End_Date__c,
                Session_Fee__c,
                No_Fee__c,
                Broucher_Type__c,
                Broucher_Name__c,
                Questionnaire__c,
                Feedback_Trigger_Type__c,
                Feedback_Trigger_When__c,
                Feedback_End_Date__c,
                Feedback_End_Time__c,
                Meals__c
                FROM Ken_Schedule_Sessions__c
                WHERE Event_Reference__c = :recordId
            ];
            
            Set<Id> questionnaireIds = new Set<Id>();
            for (Ken_Schedule_Sessions__c s : eventSchedule) {
                if (s.Questionnaire__c != null) {
                    questionnaireIds.add(s.Questionnaire__c);
                }
            }
            Map<Id, List<Ken_Questionnaire_Parameter__c>> paramsByQuestionnaire = new Map<Id, List<Ken_Questionnaire_Parameter__c>>();
            if (!questionnaireIds.isEmpty()) {
                for (Ken_Questionnaire_Parameter__c param : [
                    SELECT Id, Question_Label__c, Question_Type__c, Is_Required__c, MCQ_Options__c, Questionnaire__c
                    FROM Ken_Questionnaire_Parameter__c
                    WHERE Questionnaire__c IN :questionnaireIds
                    ORDER BY CreatedDate ASC
                ]) {
                    if (!paramsByQuestionnaire.containsKey(param.Questionnaire__c)) {
                        paramsByQuestionnaire.put(param.Questionnaire__c, new List<Ken_Questionnaire_Parameter__c>());
                    }
                    paramsByQuestionnaire.get(param.Questionnaire__c).add(param);
                }
            }

            List<EventScheduleWrapper> eventScheduleList = new List<EventScheduleWrapper>();
            if(!eventSchedule.isEmpty()){
                for (Ken_Schedule_Sessions__c eachSchedule : eventSchedule) {
                    EventScheduleWrapper eventSc = new EventScheduleWrapper(eachSchedule);
                    if (eachSchedule.Questionnaire__c != null && paramsByQuestionnaire.containsKey(eachSchedule.Questionnaire__c)) {
                        eventSc.questionnaireParams = paramsByQuestionnaire.get(eachSchedule.Questionnaire__c);
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
            if (Schema.sObjectType.Ken_Schedule_Sessions__c.fields.Feedback_End_Date__c.isUpdateable()) {
                updateSession.Feedback_End_Date__c = String.isNotBlank(endDate) ? Date.valueOf(endDate) : null;
            }
            if (Schema.sObjectType.Ken_Schedule_Sessions__c.fields.Feedback_End_Time__c.isUpdateable()) {
                updateSession.Feedback_End_Time__c = normalizeFeedbackEndTime(endTime);
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

    private static Time normalizeFeedbackEndTime(String endTime) {
        if (String.isBlank(endTime)) {
            return null;
        }
        List<String> parts = endTime.split(':');
        if (parts.size() < 2) {
            return null;
        }
        Integer hours = Integer.valueOf(parts[0]);
        Integer minutes = Integer.valueOf(parts[1]);
        Time localTime = Time.newInstance(hours, minutes, 0, 0);
        return localTime.addHours(5).addMinutes(30);
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

            Id speakerRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Ken_Events_Sessions_Enrollment__c' AND DeveloperName = 'Speaker_Enrollment']?.Id;

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
                ];
                enrollmentsToDelete = [
                    SELECT Id
                    FROM Ken_Events_Sessions_Enrollment__c
                    WHERE Schedule_Sessions__r.Event_Reference__c = :eventId
                    AND Id NOT IN :sessionSpeakerEnrollmentIds
                ];
                if (!enrollmentsToDelete.isEmpty()) {
                    delete enrollmentsToDelete;
                }
                if (!sessionsToDelete.isEmpty()) {
                    delete sessionsToDelete;
                }
            } else if (!incomingSessionIds.isEmpty()) {
                enrollmentsToDelete = [
                    SELECT Id
                    FROM Ken_Events_Sessions_Enrollment__c
                    WHERE Schedule_Sessions__c IN :incomingSessionIds
                    AND Id NOT IN :sessionSpeakerEnrollmentIds
                ];
                if (!enrollmentsToDelete.isEmpty()) {
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
            if (toUpdate != null && !toUpdate.isEmpty()) update toUpdate;
            if (toInsert != null && !toInsert.isEmpty()) insert toInsert;
        }
        void upsertEnrollments(List<Ken_Events_Sessions_Enrollment__c> toUpdate, List<Ken_Events_Sessions_Enrollment__c> toInsert) {
            if (toUpdate != null && !toUpdate.isEmpty()) update toUpdate;
            if (toInsert != null && !toInsert.isEmpty()) insert toInsert;
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
            return [SELECT Id, Name,Event_Current_Step__c,Language__c,Event_Status__c, Target_Keywords__c,Event_Broucher__c, Broucher_Title__c, Description__c,createdDate,Event_Fee__c,No_Fee__c, Auto_Enroll_Target_Audience__c,RecordTypeId, End_Date__c, End_Time__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Target_Audience_Applicable__c, Start_Date__c, Start_Time__c, What_to_Expect_From_Event__c,Email_Subject__c,Email_Distribution_List__c,Email_Body__c,Schedule_Date__c,Schedule_Time__c,Email_Attachment__c,Can_Alumni_Bring_Guests__c,Guest_Count__c,Offer_Meals__c,Make_Meals_Paid__c,Collect_Dietary_Preferences__c,Dietary_Preferences__c,Meal_Fee__c  FROM Ken_Event_Master__c WHERE Id=:recordId];
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String,String> getFileUploadSettings(String allowedFileTypes, String maxFileSize){
        
        Map<String,String> eventFileUploadSettings = new Map<String,String>();
        Alumni_Org_Parameters__c orgSettings = Alumni_Org_Parameters__c.getInstance();
        
        
        if(orgSettings != null){
            eventFileUploadSettings.put('allowedFileTypes',String.valueOf(orgSettings.get(allowedFileTypes)));
            eventFileUploadSettings.put('maxFileSize',String.valueOf(orgSettings.get(maxFileSize)));
        }
        
        return eventFileUploadSettings;
    }
    
    @AuraEnabled
    public static Id saveEvent(string eventData, Id constituentRoleId){
        if (String.isBlank(eventData)) {
            throw new AuraHandledException('Event payload is required.');
        }
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

        Id eventRecordType = [SELECT Id FROM RecordType WHERE SObjectType = 'Ken_Event_Master__c' AND DeveloperName = 'Event']?.Id;
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
            upsert evt;
        }
    }

    @AuraEnabled
    public static Id createEventSegmentation(Id eventId, Id segmentationId) {
        if (eventId == null || segmentationId == null) {
            throw new AuraHandledException('Event Id and Segmentation Id are required.');
        }
        System.debug(LoggingLevel.INFO, 'createEventSegmentation: eventId=' + eventId + ', segmentationId=' + segmentationId);
        if (!Schema.sObjectType.Ken_Event_Segmentation__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create event segmentation.');
        }
        if (!Schema.sObjectType.Ken_Event_Segmentation__c.fields.Event_Master__c.isCreateable()
            || !Schema.sObjectType.Ken_Event_Segmentation__c.fields.Segmentation__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to set event segmentation fields.');
        }

        List<Ken_Event_Segmentation__c> staleLinks = [
            SELECT Id
            FROM Ken_Event_Segmentation__c
            WHERE Event_Master__c = :eventId
            AND Segmentation__c != :segmentationId
        ];
        if (!staleLinks.isEmpty()) {
            delete staleLinks;
        }

        List<Ken_Event_Segmentation__c> existing = [
            SELECT Id
            FROM Ken_Event_Segmentation__c
            WHERE Event_Master__c = :eventId
            AND Segmentation__c = :segmentationId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'createEventSegmentation: link already exists Id=' + existing[0].Id);
            return existing[0].Id;
        }

        Ken_Event_Segmentation__c link = new Ken_Event_Segmentation__c(
            Event_Master__c = eventId,
            Segmentation__c = segmentationId
        );
        insert link;
        System.debug(LoggingLevel.INFO, 'createEventSegmentation: created link Id=' + link.Id);
        return link.Id;
    }
    
    @AuraEnabled
    public static void updateFee(Boolean isEventWise, Id eventId, Integer eventFee, Boolean isNoFee, List<Ken_Schedule_Sessions__c> sessionsMap) {
        // If event-wise fee update
        if (isEventWise) {
            // Fetch the event record
            Ken_Event_Master__c eventRecord = [SELECT Id, Event_Fee__c, No_Fee__c, Auto_Enroll_Target_Audience__c FROM Ken_Event_Master__c WHERE Id = :eventId LIMIT 1];
            
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
                SELECT Id, Start_Date__c, Meals__c
                FROM Ken_Schedule_Sessions__c
                WHERE Event_Reference__c = :eventId
            ];
            List<Ken_Schedule_Sessions__c> toUpdate = new List<Ken_Schedule_Sessions__c>();
            for (Ken_Schedule_Sessions__c s : sessions) {
                String mealsValue = '';
                if (offerMeals == true && s.Start_Date__c != null) {
                    Date d = s.Start_Date__c;
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

        ];
    }
    //GET SESSIONS    
    @AuraEnabled
    public static List<Ken_Schedule_Sessions__c> getEventSessions(string eventId) {
        
        return  [SELECT Id, Name, 
                 Session_Broucher__c,End_Time__c,
                 Start_Date__c,Location_Type__c,Session_Link__c,
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
                 Start_Time__c, Session_Fee__c,What_to_Expect_From_Event__c, No_Fee__c, Location__c
                 FROM Ken_Schedule_Sessions__c WHERE Event_Reference__c =:eventId ORDER BY Start_Date__c];
    }
    
    @AuraEnabled(cacheable=true)
    public static list<sObject> fetchLookupData(string searchKey , string sObjectApiName) {    
        List < sObject > returnList = new List < sObject > ();
        string sWildCardText = '%' + searchKey + '%';
        String sQuery = 'SELECT Id, Name ' +
            'FROM ' + sObjectApiName + ' ' +
            'WHERE Name LIKE :sWildCardText ' +
            'AND RecordType.DeveloperName = \'Event_Group\' ' +
            'ORDER BY CreatedDate DESC ' +
            'LIMIT 5';
        for (sObject obj: database.query(sQuery)) {
            returnList.add(obj);
        }
        return returnList;
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getPicklistValues(String objectName, List<String> fieldNames) {
        Map<String,List<Map<String,String>>> picklictValuesByField = new Map<String,List<Map<String,String>>>();
        try{
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            if (objectType == null) {
                throw new AuraHandledException('Object ' + objectName + ' not found');
            }
            
            Schema.DescribeSObjectResult describeObjResult = objectType.getDescribe();
            
            Map<String, Schema.SObjectField> fieldMap = describeObjResult.fields.getMap();
            for(String field : fieldNames){
                if(!fieldMap.containsKey(field)){
                    continue;
                }
                
                Schema.DescribeFieldResult fieldResult = fieldMap.get(field).getDescribe();
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
        record.Target_Keywords__c = wrapper.agenda;
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

            Map<Id,Ken_Schedule_Sessions__c> sessionsToDelete = new Map<Id,Ken_Schedule_Sessions__c>([SELECT Id FROM Ken_Schedule_Sessions__c WHERE Start_Date__c NOT IN :selectedDates AND Event_Reference__c = :eventId]);
            List<Ken_Events_Sessions_Enrollment__c> enrollmentsToDelete = [SELECT Id FROM Ken_Events_Sessions_Enrollment__c WHERE Schedule_Sessions__c IN :sessionsToDelete.keySet()];

            if (!enrollmentsToDelete.isEmpty()) {
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
            this.agenda =event.Target_Keywords__c;
            this.eventExpectations = event.What_to_Expect_From_Event__c;
            this.targetKeyWords = event.Target_Keywords__c;
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
            this.ScheduleDate = (event.Schedule_Date__c != null) ? String.valueOf(event.Schedule_Date__c) : '';
            this.ScheduleTime = (event.Schedule_Time__c != null) ? String.valueOf(event.Schedule_Time__c.hour()) + ':' + String.valueOf(event.Schedule_Time__c.minute()) : '';
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
                updateEvent.Target_Keywords__c = this.agenda;
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
            if(this.ScheduleDate != null && this.ScheduleDate != ''){
                updateEvent.Schedule_Date__c = Date.valueOf(this.ScheduleDate);
            }
            if(this.ScheduleTime != null && this.ScheduleTime != ''){
                List<String> timeParts = this.ScheduleTime.split(':');
                if(timeParts.size() == 2){
                    Integer hours = Integer.valueOf(timeParts[0]);
                    Integer minutes = Integer.valueOf(timeParts[1]);
                    Time ScheduleTime = Time.newInstance(hours, minutes, 0, 0);
                    updateEvent.Schedule_Time__c = ScheduleTime;
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
        insert cv;

        ContentVersion insertedCV = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = insertedCV.ContentDocumentId;
        cdl.LinkedEntityId = recordId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;

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
        public List<Ken_Questionnaire_Parameter__c> questionnaireParams;

        public EventScheduleWrapper() {
            this.speakers = new List<SpeakerWrapper>();
        }
        
        public EventScheduleWrapper(Ken_Schedule_Sessions__c eventSchedule) {
            this.Id = eventSchedule?.Id != null?eventSchedule.Id:'';
            this.agenda = eventSchedule.What_to_Expect_From_Event__c;
            this.startTime = eventSchedule.Start_Time__c;
            this.endTime = eventSchedule.End_Time__c;
            this.startDate = eventSchedule.Start_Date__c!=null?eventSchedule.Start_Date__c:null;
            this.eventId = eventSchedule.Event_Reference__c;
            this.sessionBroucher = eventSchedule.Session_Broucher__c;
            this.name = eventSchedule.Name;
            this.feedbackTriggerType = eventSchedule.Feedback_Trigger_Type__c;
            this.feedbackTriggerWhen = eventSchedule.Feedback_Trigger_When__c;
            this.feedbackEndDate = eventSchedule.Feedback_End_Date__c;
            this.feedbackEndTime = eventSchedule.Feedback_End_Time__c;
            this.questionnaireId = eventSchedule.Questionnaire__c;
            this.locationType = eventSchedule.Location_Type__c;
            this.locationAddress = eventSchedule.Location__c;
            this.sessionLink = eventSchedule.Session_Link__c;
            this.broucherFileType = eventSchedule.Broucher_Type__c;
            this.brochureFileName = eventSchedule.Broucher_Name__c;
            this.sessionFee = eventSchedule.Session_Fee__c;
            this.noFee = eventSchedule.No_Fee__c ? eventSchedule.No_Fee__c : false ;
            this.meals = eventSchedule.Meals__c;
            
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
            
            if (this.startDate != null) {
                es.Start_Date__c = this.startDate; }
            
            if (this.startTime != null) {
                es.Start_Time__c = this.startTime.addHours(5).addMinutes(30); }
            
            if (this.endTime != null) {
                es.End_Time__c = this.endTime.addHours(5).addMinutes(30); }

            if (this.feedbackTriggerType != null && this.feedbackTriggerType != '') {
                es.Feedback_Trigger_Type__c = this.feedbackTriggerType;
            }

            if (this.feedbackTriggerWhen != null && this.feedbackTriggerWhen != '') {
                es.Feedback_Trigger_When__c = this.feedbackTriggerWhen;
            }

            if (this.feedbackEndDate != null) {
                es.Feedback_End_Date__c = this.feedbackEndDate;
            }

            if (this.feedbackEndTime != null) {
                es.Feedback_End_Time__c = this.feedbackEndTime.addHours(5).addMinutes(30);
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

    @AuraEnabled(cacheable=true)
    public static Ken_Questionnaire__c getQuestionnaireByEventId(Id eventId) {
        try {
            if (eventId == null) return null;
            // Read in system context: a community registrant has no sharing access to
            // the event/survey/questionnaire, so a with-sharing query returns 0 rows
            // ("List has no rows for assignment to SObject").
            WosDml wos = new WosDml();
            List<Ken_Event_Master__c> events = wos.eventForQuestionnaire(eventId);
            if (events.isEmpty()) {
                return null;
            }
            Ken_Event_Master__c eventRecord = events[0];
            // Prefer the survey-linked questionnaire; fall back to the legacy direct lookup.
            Id questionnaireId = (eventRecord.Survey__r != null && eventRecord.Survey__r.Ken_Questionnaire__c != null)
                ? eventRecord.Survey__r.Ken_Questionnaire__c
                : eventRecord.Questionnaire__c;
            if (questionnaireId == null) {
                return null;
            }
            List<Ken_Questionnaire__c> qs = wos.questionnaireWithParams(questionnaireId);
            return qs.isEmpty() ? null : qs[0];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id saveQuestionnaireForEvent(Id eventId, Ken_Questionnaire__c questionnaire, List<Ken_Questionnaire_Parameter__c> questions) {
        try {
            if (eventId == null) {
                throw new AuraHandledException('Event Id is required.');
            }
            Ken_Event_Master__c eventRecord = [
                SELECT Id, Name, Description__c, Questionnaire__c, Survey__c, Constituent_Role__c,
                       Start_Date__c, End_Date__c
                FROM Ken_Event_Master__c
                WHERE Id = :eventId                LIMIT 1
            ];

            if (questionnaire == null) {
                questionnaire = new Ken_Questionnaire__c();
            }
            if (questionnaire.Id == null && eventRecord.Questionnaire__c != null) {
                questionnaire.Id = eventRecord.Questionnaire__c;
            }
            questionnaire.Section_Name__c = eventRecord.Name;

            questionnaire.Questions_JSON__c = JSON.serialize(questions);

            if (Schema.sObjectType.Ken_Questionnaire__c.isCreateable() &&
                Schema.sObjectType.Ken_Questionnaire__c.isUpdateable()) {
                upsert questionnaire;
            }

            reconcileQuestions(questionnaire.Id, questions);

            // Wrap the questionnaire in a Ken_Survey__c so it surfaces in the Survey module
            // and responses can be tracked against the survey. Event -> Survey -> Questionnaire.
            Id surveyId = upsertWrapperSurvey(
                eventRecord.Survey__c, questionnaire.Id, 'Survey',
                eventRecord.Name, eventRecord.Description__c, eventRecord.Constituent_Role__c,
                eventRecord.Start_Date__c, eventRecord.End_Date__c
            );

            if (Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
                new WosDml().updateRecord(new Ken_Event_Master__c(
                    Id = eventRecord.Id,
                    Survey__c = surveyId,
                    Questionnaire__c = questionnaire.Id
                ));
            }
            return questionnaire.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Id saveQuestionnaireForSession(Id sessionId, Ken_Questionnaire__c questionnaire, List<Ken_Questionnaire_Parameter__c> questions) {
        try {
            if (sessionId == null) {
                throw new AuraHandledException('Session Id is required.');
            }
            Ken_Schedule_Sessions__c sessionRecord = [
                SELECT Id, Name, Questionnaire__c, Survey__c, What_to_Expect_From_Event__c,
                       Start_Date__c, Event_Reference__r.Constituent_Role__c
                FROM Ken_Schedule_Sessions__c
                WHERE Id = :sessionId                LIMIT 1
            ];

            if (questionnaire == null) {
                questionnaire = new Ken_Questionnaire__c();
            }
            if (questionnaire.Id == null && sessionRecord.Questionnaire__c != null) {
                questionnaire.Id = sessionRecord.Questionnaire__c;
            }
            if (String.isBlank(questionnaire.Section_Name__c)) {
                questionnaire.Section_Name__c = sessionRecord.Name;
            }

            questionnaire.Questions_JSON__c = JSON.serialize(questions);

            if (Schema.sObjectType.Ken_Questionnaire__c.isCreateable() &&
                Schema.sObjectType.Ken_Questionnaire__c.isUpdateable()) {
                upsert questionnaire;
            }

            reconcileQuestions(questionnaire.Id, questions);

            // Wrap the feedback questionnaire in a Ken_Survey__c (Type Feedback). Session -> Survey -> Questionnaire.
            Id hostRole = sessionRecord.Event_Reference__r != null ? sessionRecord.Event_Reference__r.Constituent_Role__c : null;
            Id surveyId = upsertWrapperSurvey(
                sessionRecord.Survey__c, questionnaire.Id, 'Feedback',
                sessionRecord.Name, sessionRecord.What_to_Expect_From_Event__c, hostRole,
                sessionRecord.Start_Date__c, sessionRecord.Start_Date__c
            );

            if (Schema.sObjectType.Ken_Schedule_Sessions__c.isUpdateable()) {
                new WosDml().updateRecord(new Ken_Schedule_Sessions__c(
                    Id = sessionRecord.Id,
                    Survey__c = surveyId,
                    Questionnaire__c = questionnaire.Id
                ));
            }
            return questionnaire.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Upserts the Ken_Survey__c wrapper that links an event/session to its questionnaire.
     * Event/Session point to this survey; the survey points to the questionnaire.
     */
    private static Id upsertWrapperSurvey(Id existingSurveyId, Id questionnaireId, String surveyType,
        String name, String description, Id constituentRoleId, Date startDate, Date endDate) {
        Ken_Survey__c survey = new Ken_Survey__c();
        if (existingSurveyId != null) survey.Id = existingSurveyId;
        survey.Name = String.isBlank(name) ? surveyType : name;
        survey.Section_Name__c = name;
        survey.Description__c = description;
        survey.Type__c = surveyType;
        survey.Ken_Questionnaire__c = questionnaireId;
        survey.Approval_Status__c = 'Approved';
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

    // System-context DML helper for the questionnaire/survey save path, mirroring
    // EventWriter/ScheduleWriter — portal hosts can't always reach these records or
    // their cross-references under sharing.
    private without sharing class WosDml {
        void upsertRecord(SObject rec) { upsert rec; }
        void updateRecord(SObject rec) { update rec; }
        List<Ken_Event_Master__c> eventForQuestionnaire(Id eventId) {
            return [
                SELECT Id, Questionnaire__c, Survey__c, Survey__r.Ken_Questionnaire__c
                FROM Ken_Event_Master__c WHERE Id = :eventId LIMIT 1
            ];
        }
        List<Ken_Questionnaire__c> questionnaireWithParams(Id questionnaireId) {
            return [
                SELECT Id, Section_Name__c, Descripation__c, Target_Audience__c,
                       (SELECT Id, Question_Label__c, Question_Type__c, Is_Required__c, MCQ_Options__c,
                               Section_Name__c, Section_Header__c
                        FROM Ken_Questionnaire_Parameters__r
                        ORDER BY CreatedDate ASC)
                FROM Ken_Questionnaire__c WHERE Id = :questionnaireId LIMIT 1
            ];
        }
    }

    /**
     * Shared helper: deletes orphaned existing questions, then upserts the
     * incoming ones with the parent questionnaire id wired up.
     */
    private static void reconcileQuestions(Id questionnaireId, List<Ken_Questionnaire_Parameter__c> questions) {
        List<Ken_Questionnaire_Parameter__c> existing = [
            SELECT Id FROM Ken_Questionnaire_Parameter__c
            WHERE Questionnaire__c = :questionnaireId        ];

        Set<Id> incomingIds = new Set<Id>();
        if (questions != null) {
            for (Ken_Questionnaire_Parameter__c q : questions) {
                if (q.Id != null) incomingIds.add(q.Id);
            }
        }

        List<Ken_Questionnaire_Parameter__c> toDelete = new List<Ken_Questionnaire_Parameter__c>();
        for (Ken_Questionnaire_Parameter__c q : existing) {
            if (!incomingIds.contains(q.Id)) toDelete.add(q);
        }
        if (!toDelete.isEmpty() && Schema.sObjectType.Ken_Questionnaire_Parameter__c.isDeletable()) {
            delete toDelete;
        }

        if (questions != null) {
            for (Ken_Questionnaire_Parameter__c q : questions) {
                if (q.Id == null) q.Questionnaire__c = questionnaireId;
            }
            if (!questions.isEmpty() &&
                Schema.sObjectType.Ken_Questionnaire_Parameter__c.isCreateable() &&
                Schema.sObjectType.Ken_Questionnaire_Parameter__c.isUpdateable()) {
                upsert questions;
            }
        }
    }
}