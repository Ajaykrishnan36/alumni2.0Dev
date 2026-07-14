public without sharing class KenPortalEventController {
    
    @AuraEnabled(cacheable=true)
    public static List<EventWrapper> getAllEvents() {
        User currentUser = [SELECT Id, Profile.Name FROM User WHERE Id = :userinfo.getUserId()];
        String profileName = currentUser.Profile.Name;
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        String adminLabel = (orgParam != null && String.isNotBlank(orgParam.Institution_Alias__c))
            ? 'By ' + orgParam.Institution_Alias__c
            : 'By Admin';
        List<EventWrapper> eventWrappers = new List<EventWrapper>();
        for (Ken_Event_Master__c ev : [SELECT Id, Name, End_Date__c, End_Time__c, Event_Type__c, Event_banner__c, Location__c, Start_Date__c, Start_Time__c,Event_Status__c,Target_Audience_Applicable__c, Constituent_Role__c
                                   FROM Ken_Event_Master__c WHERE Is_Active__c = true AND Event_Status__c = 'Approved']) {
                                       eventWrappers.add(new EventWrapper(ev, adminLabel));
                                   }
                             System.debug('eventWrappers -- '+eventWrappers);      
        return eventWrappers;
    }
    
    @AuraEnabled
    public static List<Ken_Event_Master__c> getHostedEvents(Id constituentRoleId) {
        try{
            if (constituentRoleId == null) {
                throw new AuraHandledException('No constituent role found for current user.');
            }
            
            Set<String> approvalStatuses = new Set<String>{'In Review', 'Approved', 'Rejected', 'Cancelled', 'Draft', 'In Progress'};
                
                return [SELECT Id, Name, Start_Date__c, End_Date__c, Event_Type__c, Event_banner__c, Location__c,
                        Reason_For_Rejection__c, Max_Allowed_Participants__c, Event_Status__c,
                        Event_Fee__c, No_Fee__c, Offer_Meals__c, CreatedDate, LastModifiedDate, Rejected_On__c,
                        (SELECT Id, Session_Fee__c, No_Fee__c, Location_Type__c FROM Schedule_Sessions__r)
                        FROM Ken_Event_Master__c
                        WHERE Constituent_Role__c = :constituentRoleId AND Event_Status__c IN :approvalStatuses ORDER By CREATEDDATE DESC];
            
        }catch(Exception e){
            throw new AuraHandledException('Error :'+e.getmessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Ken_Schedule_Sessions__c> getEventSessions(Id EventId) {
        
        List<Ken_Schedule_Sessions__c> sessions = new List<Ken_Schedule_Sessions__c>();
        for (Ken_Schedule_Sessions__c sess : [SELECT Id, Name, End_Date__c, End_Time__c, Start_Date__c, Start_Time__c FROM Ken_Schedule_Sessions__c WHERE Event_Reference__c = :EventId]) {
            sessions.add(sess);
        }
        
        if (sessions.isEmpty()) {
            throw new AuraHandledException('no sessions to register');
        }
        return sessions;
    }
    
    @AuraEnabled(Cacheable=true)
    public static List<Ken_Schedule_Sessions__c> getRegisteredSessions(Id EventId, Id constituentRoleId) {
        try {
            if (constituentRoleId == null) {
                throw new AuraHandledException('No constituent role found for current user.');
            }
            
            return [
                SELECT Id, Name, Start_Date__c, Start_Time__c, End_Time__c, Event_Reference__c
                FROM Ken_Schedule_Sessions__c 
                WHERE Event_Reference__c = :EventId
                AND Id IN (
                    SELECT Schedules_Sessions__c 
                    FROM Ken_Event_Booking__c 
                    WHERE Constituent_Role__c = : constituentRoleId 
                    AND Type__c = 'Registered'
                )
                ORDER BY Start_Date__c ASC, Start_Time__c ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching registered sessions: ' + e.getMessage()+' '+ e.getLineNumber());
        }
    }
    
    @AuraEnabled(Cacheable=true)
    public static EventDetailWrapper getEventDetails(String recordId){
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }
            
            Ken_Event_Master__c event = [
                SELECT Id, Name, Start_Date__c, End_Date__c, Start_Time__c, End_Time__c,
                Description__c, Event_Type__c, Event_banner__c, Language__c,
                Max_Allowed_Participants__c, What_to_Expect_From_Event__c, Event_Broucher__c,
                CreatedDate, Target_Keywords__c, Location__c, Event_Status__c,
                Reason_For_Rejection__c,
                Event_Fee__c, No_Fee__c, Offer_Meals__c
                , Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c, Make_Meals_Paid__c
                , Can_Alumni_Bring_Guests__c, Guest_Count__c
                , Event_Photos_Link__c, Event_Highlights_Link__c, Constituent_Role__c
                FROM Ken_Event_Master__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            
            EventDetailWrapper result = new EventDetailWrapper(event);
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching event details: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<ScheduleWrapper> getEventSchedules(String eventId, Id constituentRoleId) {
        try{
            if (String.isBlank(eventId)) {
                throw new AuraHandledException('Record ID is required');
            }
            // constituentRoleId is optional here: when absent (e.g. the register wire fires
            // before the role loads) we still return the sessions, just without the
            // per-user "registered" flag instead of throwing a masked script exception.

            List<ScheduleWrapper> schedules = new List<ScheduleWrapper>();
            
            List<Ken_Schedule_Sessions__c> eventSchedules = [
                SELECT Id, Name, Start_Date__c, Start_Time__c, End_Time__c, What_to_Expect_From_Event__c,
                Location__c, Location_Type__c, Session_Fee__c, No_Fee__c, Meals__c, Session_Link__c,
                (SELECT Id, Person_Account__c, Person_Account__r.Name, Speaker_Image__c, Description__c,Speaker_Name__c FROM Event_Session_Account_Associations__r)
                FROM Ken_Schedule_Sessions__c
                WHERE Event_Reference__c = :eventId
                //AND Is_Cancelled__c = false
                ORDER BY Start_Date__c, Start_Time__c
            ];
            
            Map<Id,Ken_Schedule_Sessions__c> registeredSessionsMap = new Map<Id,Ken_Schedule_Sessions__c>();
            if (constituentRoleId != null) {
                registeredSessionsMap = new Map<Id,Ken_Schedule_Sessions__c>([SELECT Id FROM Ken_Schedule_Sessions__c WHERE Event_Reference__c = :EventId
                                                                                                 AND Id IN (
                                                                                                     SELECT Schedules_Sessions__c
                                                                                                     FROM Ken_Event_Booking__c
                                                                                                     WHERE Constituent_Role__c = : constituentRoleId
                                                                                                     AND Type__c = 'Registered'
                                                                                                 )]);
            }
            
            for (Ken_Schedule_Sessions__c schedule : eventSchedules) {
                ScheduleWrapper wrapper = new ScheduleWrapper();
                wrapper.id = schedule.Id;
                wrapper.name = schedule.Name;
                wrapper.sessionDate = schedule.Start_Date__c;
                wrapper.startTime = schedule.Start_Time__c;
                wrapper.endTime = schedule.End_Time__c;
                wrapper.title = schedule.Name;
                wrapper.agenda = schedule.What_to_Expect_From_Event__c;
                wrapper.isRegistered = registeredSessionsMap.containsKey(schedule.Id);
                wrapper.meals = schedule.Meals__c;
                wrapper.location = schedule.Location__c;
                wrapper.locationType = schedule.Location_Type__c;
                // Never ship the meeting link to users who haven't registered for
                // the session — otherwise anyone can join the meeting.
                wrapper.sessionLink = wrapper.isRegistered ? schedule.Session_Link__c : null;
                wrapper.price = schedule.Session_Fee__c;
                wrapper.noFee = schedule.No_Fee__c;
                
                // Process speakers
                wrapper.speakers = new List<SpeakerWrapper>();
                List<String> speakerNames = new List<String>();
                
                for (Ken_Events_Sessions_Enrollment__c speakerEnroll : schedule.Event_Session_Account_Associations__r) {
                    SpeakerWrapper speakerWrap = new SpeakerWrapper();
                    speakerWrap.id = speakerEnroll.Person_Account__c;
                    speakerWrap.name = speakerEnroll.Speaker_Name__c;
                    speakerWrap.image = speakerEnroll.Speaker_Image__c;
                    speakerWrap.description = speakerEnroll.Description__c;
                    
                    wrapper.speakers.add(speakerWrap);
                    speakerNames.add(speakerEnroll.Speaker_Name__c);
                }
                
                wrapper.speakerNames = String.join(speakerNames, ', ');
                
                schedules.add(wrapper);
            }
            
            return schedules;
        }catch(Exception e){
            throw new AuraHandledException('Error fetching session details: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String saveRegistrations(List<Id> sessionIds, Id constituentRoleId) {
        try {
            if (sessionIds == null || sessionIds.isEmpty()) {
                throw new AuraHandledException('Please select at least one session.');
            }
            
            if (constituentRoleId == null) {
                throw new AuraHandledException('No constituent role found for current user.');
            }
            
            List<Ken_Event_Booking__c> existingBookings = [Select Id, Constituent_Role__c, Schedules_Sessions__c, Type__c from Ken_Event_Booking__c where Constituent_Role__c= :constituentRoleId AND Schedules_Sessions__c IN :sessionIds];
            Map<Id,Id> sessionBookingMap = new Map<Id,Id>();
            for(Ken_Event_Booking__c booking : existingBookings){
                sessionBookingMap.put(booking.Schedules_Sessions__c,booking.Id);
            }
            
            List<Ken_Event_Booking__c> registrationToUpsert = new List<Ken_Event_Booking__c>();
            for (Id sessionId : sessionIds) {
                registrationToUpsert.add(new Ken_Event_Booking__c(
                    Id = sessionBookingMap.get(sessionId),
                    Constituent_Role__c = constituentRoleId,
                    Schedules_Sessions__c = sessionId,
                    Type__c = 'Registered'
                ));
            }
            
            upsert registrationToUpsert;

            return 'Successfully registered!';

        } catch (Exception e) {
            throw new AuraHandledException('Registration failed: ' + e.getMessage());
        }
    }

    // Participant-aware registration. Persists one booking per participant per session, capturing
    // guest contact details and group lookups so non-alumni attendees are stored on the booking.
    @AuraEnabled
    public static String saveEventRegistrations(String payload, Id constituentRoleId) {
        try {
            if (String.isBlank(payload)) {
                throw new AuraHandledException('Registration payload is required.');
            }
            if (constituentRoleId == null) {
                throw new AuraHandledException('No constituent role found for current user.');
            }

            RegistrationRequest req = (RegistrationRequest) JSON.deserialize(payload, RegistrationRequest.class);
            if (req.sessionIds == null || req.sessionIds.isEmpty()) {
                throw new AuraHandledException('Please select at least one session.');
            }
            if (req.participants == null || req.participants.isEmpty()) {
                throw new AuraHandledException('Please add at least one participant.');
            }

            // The registrant's person account (used for Myself bookings)
            Id registrantPersonId;
            for (ConstituentRole cr : [SELECT Id, PersonId FROM ConstituentRole WHERE Id = :constituentRoleId LIMIT 1]) {
                registrantPersonId = cr.PersonId;
            }

            List<Ken_Event_Booking__c> toInsert = new List<Ken_Event_Booking__c>();
            for (ParticipantData p : req.participants) {
                String personType = String.isBlank(p.type) ? 'Myself' : p.type;
                Integer attendees = (personType == 'Group' && p.memberCount != null && p.memberCount > 0)
                    ? p.memberCount : 1;

                for (Id sessionId : req.sessionIds) {
                    Ken_Event_Booking__c booking = new Ken_Event_Booking__c(
                        Constituent_Role__c = constituentRoleId,
                        Schedules_Sessions__c = sessionId,
                        Type__c = 'Registered',
                        Booking_Person_Type__c = personType,
                        Booked_for_No_of_Attendees__c = attendees,
                        Meals_Opted__c = p.meals == true,
                        Dietary_Preference__c = p.dietaryPref
                    );
                    if (personType == 'Myself') {
                        booking.Person_Account__c = registrantPersonId;
                    } else if (personType == 'Guest') {
                        booking.Guest_Name__c = p.name;
                        booking.Guest_Email__c = p.email;
                        booking.Guest_Phone__c = p.phone;
                    } else if (personType == 'Group') {
                        if (String.isNotBlank(p.groupId)) {
                            booking.Group__c = (Id) p.groupId;
                        }
                        booking.Guest_Name__c = p.name;
                    }
                    toInsert.add(booking);
                }
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            return 'Successfully registered!';
        } catch (Exception e) {
            throw new AuraHandledException('Registration failed: ' + e.getMessage());
        }
    }

    // Registration summary for a single event for the current registrant: participant rows,
    // the registered sessions, and the event header. Payment is computed/hardcoded on the client.
    @AuraEnabled(cacheable=true)
    public static RegistrationSummaryWrapper getRegistrationSummary(String eventId, Id constituentRoleId) {
        try {
            if (String.isBlank(eventId)) {
                throw new AuraHandledException('Event id is required.');
            }
            if (constituentRoleId == null) {
                throw new AuraHandledException('No constituent role found for current user.');
            }

            RegistrationSummaryWrapper result = new RegistrationSummaryWrapper();
            for (Ken_Event_Master__c ev : [
                SELECT Id, Name, Event_banner__c, Start_Date__c, End_Date__c, Location__c,
                       Language__c, Offer_Meals__c
                FROM Ken_Event_Master__c WHERE Id = :eventId LIMIT 1
            ]) {
                result.eventId = ev.Id;
                result.eventName = ev.Name;
                result.eventBanner = ev.Event_banner__c;
                result.startDate = ev.Start_Date__c;
                result.endDate = ev.End_Date__c;
                result.location = ev.Location__c;
                result.language = ev.Language__c;
                result.offerMeals = ev.Offer_Meals__c;
            }

            List<Ken_Event_Booking__c> bookings = [
                SELECT Id, Type__c, Booking_Person_Type__c, Meals_Opted__c, Dietary_Preference__c,
                       Guest_Name__c, Guest_Email__c, Guest_Phone__c,
                       Group__c, Group__r.Name,
                       Person_Account__c, Person_Account__r.Name, Person_Account__r.PersonEmail, Person_Account__r.PersonMobilePhone,
                       Schedules_Sessions__c, Schedules_Sessions__r.Name,
                       Schedules_Sessions__r.Start_Date__c, Schedules_Sessions__r.Start_Time__c,
                       Schedules_Sessions__r.End_Time__c, Schedules_Sessions__r.Session_Fee__c,
                       Schedules_Sessions__r.No_Fee__c
                FROM Ken_Event_Booking__c
                WHERE Schedules_Sessions__r.Event_Reference__c = :eventId
                AND Constituent_Role__c = :constituentRoleId
                AND Type__c = 'Registered'
                ORDER BY Schedules_Sessions__r.Start_Date__c, Schedules_Sessions__r.Start_Time__c
            ];

            Map<String, SummaryParticipant> participantMap = new Map<String, SummaryParticipant>();
            Map<Id, SummarySession> sessionMap = new Map<Id, SummarySession>();

            for (Ken_Event_Booking__c b : bookings) {
                String pType = String.isBlank(b.Booking_Person_Type__c) ? 'Myself' : b.Booking_Person_Type__c;
                String pKey;
                String pName;
                String pEmail;
                String pPhone;
                if (pType == 'Guest') {
                    pName = b.Guest_Name__c;
                    pEmail = b.Guest_Email__c;
                    pPhone = b.Guest_Phone__c;
                    pKey = 'G:' + b.Guest_Email__c + b.Guest_Name__c;
                } else if (pType == 'Group') {
                    pName = b.Group__r != null ? b.Group__r.Name : b.Guest_Name__c;
                    pEmail = '';
                    pPhone = '';
                    pKey = 'GR:' + b.Group__c;
                } else {
                    pName = b.Person_Account__r != null ? b.Person_Account__r.Name : 'Me';
                    pEmail = b.Person_Account__r != null ? b.Person_Account__r.PersonEmail : '';
                    pPhone = b.Person_Account__r != null ? b.Person_Account__r.PersonMobilePhone : '';
                    pKey = 'M:' + b.Person_Account__c;
                }

                if (!participantMap.containsKey(pKey)) {
                    SummaryParticipant sp = new SummaryParticipant();
                    sp.id = pKey;
                    sp.name = pName;
                    sp.email = pEmail;
                    sp.phone = pPhone;
                    sp.type = pType;
                    sp.meals = b.Meals_Opted__c == true;
                    sp.dietaryPref = b.Dietary_Preference__c;
                    participantMap.put(pKey, sp);
                }

                if (!sessionMap.containsKey(b.Schedules_Sessions__c)) {
                    SummarySession ss = new SummarySession();
                    ss.id = b.Schedules_Sessions__c;
                    ss.name = b.Schedules_Sessions__r.Name;
                    ss.sessionDate = b.Schedules_Sessions__r.Start_Date__c;
                    ss.startTime = b.Schedules_Sessions__r.Start_Time__c;
                    ss.endTime = b.Schedules_Sessions__r.End_Time__c;
                    ss.price = (b.Schedules_Sessions__r.No_Fee__c == true) ? 0 : b.Schedules_Sessions__r.Session_Fee__c;
                    sessionMap.put(b.Schedules_Sessions__c, ss);
                }
            }

            result.participants = participantMap.values();
            result.sessions = sessionMap.values();
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading registration summary: ' + e.getMessage());
        }
    }

    // Host view: all participants registered for an event (one row per participant), for the
    // Participants tab — search/paginate/CSV are handled client-side from this list.
    @AuraEnabled(cacheable=true)
    public static List<EventParticipant> getEventParticipants(String eventId) {
        try {
            if (String.isBlank(eventId)) {
                throw new AuraHandledException('Event id is required.');
            }

            // The event's pre-event survey (used to flag "Custom Form" filled). Responses
            // reach the survey via the questionnaire link, so resolve that questionnaire.
            Id eventQuestionnaireId;
            for (Ken_Event_Master__c ev : [SELECT Id, Survey__r.Ken_Questionnaire__c FROM Ken_Event_Master__c WHERE Id = :eventId LIMIT 1]) {
                eventQuestionnaireId = ev.Survey__r != null ? ev.Survey__r.Ken_Questionnaire__c : null;
            }
            Set<Id> respondedAccountIds = new Set<Id>();
            if (eventQuestionnaireId != null) {
                for (Ken_Questionnaire_Parameter_Response__c r : [
                    SELECT Respondent__c FROM Ken_Questionnaire_Parameter_Response__c
                    WHERE Questionnaire_Parameter__r.Questionnaire__c = :eventQuestionnaireId AND Respondent__c != null
                ]) {
                    respondedAccountIds.add(r.Respondent__c);
                }
            }

            List<Ken_Event_Booking__c> bookings = [
                SELECT Id, CreatedDate, Booking_Person_Type__c, Meals_Opted__c, Dietary_Preference__c,
                       Guest_Name__c, Guest_Email__c, Guest_Phone__c,
                       Group__c, Group__r.Name,
                       Person_Account__c, Person_Account__r.Name, Person_Account__r.PersonEmail, Person_Account__r.PersonMobilePhone,
                       Constituent_Role__c, Constituent_Role__r.Graduation_Year__c,
                       Schedules_Sessions__c
                FROM Ken_Event_Booking__c
                WHERE Schedules_Sessions__r.Event_Reference__c = :eventId
                AND Type__c = 'Registered'
                ORDER BY CreatedDate ASC
            ];

            Map<String, EventParticipant> byKey = new Map<String, EventParticipant>();
            Map<String, Set<Id>> sessionsByKey = new Map<String, Set<Id>>();

            for (Ken_Event_Booking__c b : bookings) {
                String pType = String.isBlank(b.Booking_Person_Type__c) ? 'Myself' : b.Booking_Person_Type__c;
                String key;
                if (pType == 'Guest') {
                    key = 'G:' + b.Guest_Email__c + b.Guest_Name__c;
                } else if (pType == 'Group') {
                    key = 'GR:' + b.Group__c;
                } else {
                    key = 'M:' + b.Person_Account__c;
                }

                EventParticipant p = byKey.get(key);
                if (p == null) {
                    p = new EventParticipant();
                    p.id = key;
                    p.type = pType;
                    if (pType == 'Guest') {
                        p.name = b.Guest_Name__c;
                        p.email = b.Guest_Email__c;
                        p.phone = b.Guest_Phone__c;
                    } else if (pType == 'Group') {
                        p.name = b.Group__r != null ? b.Group__r.Name : 'Group';
                    } else {
                        p.name = b.Person_Account__r != null ? b.Person_Account__r.Name : 'Participant';
                        p.email = b.Person_Account__r != null ? b.Person_Account__r.PersonEmail : '';
                        p.phone = b.Person_Account__r != null ? b.Person_Account__r.PersonMobilePhone : '';
                        p.batch = (b.Constituent_Role__r != null && b.Constituent_Role__r.Graduation_Year__c != null)
                            ? String.valueOf(b.Constituent_Role__r.Graduation_Year__c) : '';
                        p.customFormFilled = (b.Person_Account__c != null && respondedAccountIds.contains(b.Person_Account__c));
                    }
                    p.mealsIncluded = false;
                    p.registeredOn = b.CreatedDate;
                    p.paymentMethod = '';
                    p.transactionId = '';
                    byKey.put(key, p);
                    sessionsByKey.put(key, new Set<Id>());
                }
                if (b.Meals_Opted__c == true) p.mealsIncluded = true;
                if (String.isBlank(p.diet) && String.isNotBlank(b.Dietary_Preference__c)) p.diet = b.Dietary_Preference__c;
                if (b.Schedules_Sessions__c != null) sessionsByKey.get(key).add(b.Schedules_Sessions__c);
                if (b.CreatedDate != null && (p.registeredOn == null || b.CreatedDate < p.registeredOn)) {
                    p.registeredOn = b.CreatedDate;
                }
            }

            for (String k : byKey.keySet()) {
                byKey.get(k).sessionsCount = sessionsByKey.get(k).size();
            }
            return byKey.values();
        } catch (Exception e) {
            throw new AuraHandledException('Error loading participants: ' + e.getMessage());
        }
    }

    public class EventParticipant {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String batch;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String type;
        @AuraEnabled public Integer sessionsCount;
        @AuraEnabled public Boolean mealsIncluded;
        @AuraEnabled public String diet;
        @AuraEnabled public Boolean customFormFilled;
        @AuraEnabled public Datetime registeredOn;
        @AuraEnabled public String paymentMethod;
        @AuraEnabled public String transactionId;
    }

    public class RegistrationSummaryWrapper {
        @AuraEnabled public String eventId;
        @AuraEnabled public String eventName;
        @AuraEnabled public String eventBanner;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String location;
        @AuraEnabled public String language;
        @AuraEnabled public Boolean offerMeals;
        @AuraEnabled public List<SummaryParticipant> participants;
        @AuraEnabled public List<SummarySession> sessions;
    }

    public class SummaryParticipant {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean meals;
        @AuraEnabled public String dietaryPref;
    }

    public class SummarySession {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Date sessionDate;
        @AuraEnabled public Time startTime;
        @AuraEnabled public Time endTime;
        @AuraEnabled public Decimal price;
    }

    public class RegistrationRequest {
        public List<Id> sessionIds;
        public List<ParticipantData> participants;
    }

    public class ParticipantData {
        public String type;        // Myself | Guest | Group
        public String name;
        public String email;
        public String phone;
        public String groupId;     // Ken_Group__c Id when type = Group
        public Integer memberCount; // group member count
        public Boolean meals;
        public String dietaryPref;
    }

    @AuraEnabled
    public static String cancelRegistrations(List<Id> sessionIds, Id constituentRoleId) {
        try {
            System.debug(LoggingLevel.INFO, 'cancelRegistrations invoked. sessionIds=' + sessionIds);
            System.debug(LoggingLevel.INFO, 'cancelRegistrations constituentRoleId=' + constituentRoleId);
            if (constituentRoleId == null) {
                throw new AuraHandledException('No constituent role found for current user.');
            }

            // Enforce the cancellation window: cancellations close 72 hours before the event starts.
            if (isCancellationWindowClosed(sessionIds)) {
                throw new AuraHandledException('The cancellation window has closed. Registrations can only be cancelled up to 72 hours before the event starts.');
            }

            List<Ken_Event_Booking__c> registrationsToUpdate = [
                SELECT Id, Type__c
                FROM Ken_Event_Booking__c
                WHERE 	Schedules_Sessions__c IN :sessionIds
                AND Constituent_Role__c = :constituentRoleId
                AND Type__c = 'Registered'
            ];
            System.debug(LoggingLevel.INFO, 'cancelRegistrations registrationsToUpdate.size=' + registrationsToUpdate.size());
            System.debug(LoggingLevel.DEBUG, 'cancelRegistrations registrationsToUpdate=' + registrationsToUpdate);
            
            if (registrationsToUpdate.isEmpty()) {
                throw new AuraHandledException('No active registrations found to cancel');
            }
            
            // Update status to Cancelled
            for (Ken_Event_Booking__c reg : registrationsToUpdate) {
                reg.Type__c = 'Cancelled';
            }
            
            System.debug(LoggingLevel.INFO, 'cancelRegistrations updating registrationsToUpdate size=' + registrationsToUpdate.size());
            update registrationsToUpdate;
            
            return 'Successfully cancelled ' + registrationsToUpdate.size() + ' registration(s)';
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'cancelRegistrations error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'cancelRegistrations line: ' + e.getLineNumber());
            System.debug(LoggingLevel.ERROR, 'cancelRegistrations stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error cancelling registrations: ' + e.getMessage());
        }
    }

    /**
     * Returns true when "now" is within 72 hours of the event start (or the event has already started),
     * meaning registrations for the given sessions can no longer be cancelled. The event start is taken
     * as the earliest event start datetime across the sessions being cancelled.
     */
    @TestVisible
    private static Boolean isCancellationWindowClosed(List<Id> sessionIds) {
        if (sessionIds == null || sessionIds.isEmpty()) {
            return false;
        }
        DateTime eventStart;
        for (Ken_Schedule_Sessions__c s : [
            SELECT Event_Reference__r.Start_Date__c, Event_Reference__r.Start_Time__c
            FROM Ken_Schedule_Sessions__c
            WHERE Id IN :sessionIds
        ]) {
            Date d = s.Event_Reference__r.Start_Date__c;
            if (d == null) {
                continue;
            }
            Time t = s.Event_Reference__r.Start_Time__c != null
                ? s.Event_Reference__r.Start_Time__c
                : Time.newInstance(0, 0, 0, 0);
            DateTime dt = DateTime.newInstance(d, t);
            if (eventStart == null || dt < eventStart) {
                eventStart = dt;
            }
        }
        // No resolvable event start -> don't block (keeps existing behaviour for malformed data).
        if (eventStart == null) {
            return false;
        }
        return System.now().addHours(72) > eventStart;
    }

    @AuraEnabled
    public static List<RegisteredEventWrapper> getContactRegisteredSessions(Id constituentRoleId) {
        try {
            if (constituentRoleId == null) {
                throw new AuraHandledException('No constituent role found for current user.');
            }

            List<Ken_Schedule_Sessions__c> sessions = [
                SELECT Id, Name, Start_Date__c, End_Date__c, Start_Time__c, End_Time__c,
                       Location__c, Location_Type__c, Session_Fee__c, No_Fee__c, Session_Link__c, Survey__c,
                       Questionnaire__c, Survey__r.Ken_Questionnaire__c,
                       Event_Reference__c, Event_Reference__r.Name, Event_Reference__r.Event_banner__c,
                       Event_Reference__r.Event_Fee__c, Event_Reference__r.No_Fee__c, Event_Reference__r.Event_Status__c,
                       (SELECT Id, Type__c, LastModifiedDate FROM Event_Bookings__r
                        WHERE Constituent_Role__c =: constituentRoleId
                        AND Type__c IN ('Registered','Cancelled')
                        ORDER BY LastModifiedDate DESC LIMIT 1)
                FROM Ken_Schedule_Sessions__c
                WHERE Id IN (
                    SELECT Schedules_Sessions__c
                    FROM Ken_Event_Booking__c
                    WHERE Constituent_Role__c =: constituentRoleId
                )
                ORDER BY Start_Date__c ASC, Start_Time__c ASC
            ];

            Set<Id> sessionIds = new Set<Id>();
            for (Ken_Schedule_Sessions__c s : sessions) sessionIds.add(s.Id);

            Map<Id, Integer> participantsBySession = new Map<Id, Integer>();
            if (!sessionIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Schedules_Sessions__c sId, COUNT(Id) cnt
                    FROM Ken_Event_Booking__c
                    WHERE Schedules_Sessions__c IN :sessionIds AND Type__c = 'Registered'
                    GROUP BY Schedules_Sessions__c
                ]) {
                    participantsBySession.put((Id) ar.get('sId'), (Integer) ar.get('cnt'));
                }
            }

            // Feedback completion is tracked via the session's linked Survey; responses
            // reach that survey through its questionnaire (no direct survey lookup).
            Map<Id, Id> questionnaireToSession = new Map<Id, Id>();
            for (Ken_Schedule_Sessions__c s : sessions) {
                if (s.Survey__r != null && s.Survey__r.Ken_Questionnaire__c != null) {
                    questionnaireToSession.put(s.Survey__r.Ken_Questionnaire__c, s.Id);
                }
            }
            Set<Id> feedbackSubmittedSessions = new Set<Id>();
            if (!questionnaireToSession.isEmpty()) {
                Id respondentAccountId = currentRespondentAccountIdSafe();
                if (respondentAccountId != null) {
                    Set<Id> qIds = questionnaireToSession.keySet();
                    for (Ken_Questionnaire_Parameter_Response__c r : [
                        SELECT Questionnaire_Parameter__r.Questionnaire__c
                        FROM Ken_Questionnaire_Parameter_Response__c
                        WHERE Questionnaire_Parameter__r.Questionnaire__c IN :qIds
                        AND Respondent__c = :respondentAccountId
                        AND Response_Category__c = 'Event'
                    ]) {
                        Id qId = (r.Questionnaire_Parameter__r != null)
                            ? r.Questionnaire_Parameter__r.Questionnaire__c : null;
                        if (qId != null && questionnaireToSession.containsKey(qId)) {
                            feedbackSubmittedSessions.add(questionnaireToSession.get(qId));
                        }
                    }
                }
            }

            List<RegisteredEventWrapper> result = new List<RegisteredEventWrapper>();
            for (Ken_Schedule_Sessions__c s : sessions) {
                RegisteredEventWrapper w = new RegisteredEventWrapper();
                w.id = s.Id;
                w.name = s.Name;
                w.startDate = s.Start_Date__c;
                w.endDate = s.End_Date__c;
                w.startTime = timeToMillis(s.Start_Time__c);
                w.endTime = timeToMillis(s.End_Time__c);
                w.location = s.Location__c;
                w.locationType = s.Location_Type__c;
                w.sessionLink = s.Session_Link__c;
                w.eventId = s.Event_Reference__c;
                w.eventName = s.Event_Reference__r != null ? s.Event_Reference__r.Name : null;
                w.eventBanner = s.Event_Reference__r != null ? s.Event_Reference__r.Event_banner__c : null;
                w.eventStatus = s.Event_Reference__r != null ? s.Event_Reference__r.Event_Status__c : null;

                Decimal fee = null;
                Boolean isFree = false;
                if (s.No_Fee__c == true) {
                    isFree = true;
                } else if (s.Session_Fee__c != null) {
                    fee = s.Session_Fee__c;
                    isFree = (fee == 0);
                } else if (s.Event_Reference__r != null && s.Event_Reference__r.No_Fee__c == true) {
                    isFree = true;
                } else if (s.Event_Reference__r != null && s.Event_Reference__r.Event_Fee__c != null) {
                    fee = s.Event_Reference__r.Event_Fee__c;
                    isFree = (fee == 0);
                } else {
                    isFree = true;
                }
                w.amountPaid = fee;
                w.isFree = isFree;

                w.participantsCount = participantsBySession.get(s.Id) != null ? participantsBySession.get(s.Id) : 0;
                w.feedbackSubmitted = feedbackSubmittedSessions.contains(s.Id);
                // A feedback form exists only when the session has a survey-linked
                // questionnaire (or the legacy direct Questionnaire__c) — mirrors
                // getEventFeedbackAsSurvey so the button never points at a blank form.
                w.hasFeedbackForm = (s.Survey__r != null && s.Survey__r.Ken_Questionnaire__c != null)
                                    || s.Questionnaire__c != null;

                if (s.Event_Bookings__r != null && !s.Event_Bookings__r.isEmpty()) {
                    w.bookingType = s.Event_Bookings__r[0].Type__c;
                    w.bookingDate = s.Event_Bookings__r[0].LastModifiedDate;
                }
                result.add(w);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching registered sessions: ' + e.getMessage()+' '+ e.getLineNumber());
        }
    }

    private static Long timeToMillis(Time t) {
        if (t == null) return 0L;
        return (Long)t.hour() * 3600000L + (Long)t.minute() * 60000L + (Long)t.second() * 1000L + (Long)t.millisecond();
    }

    public class RegisteredEventWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Long startTime;
        @AuraEnabled public Long endTime;
        @AuraEnabled public String location;
        @AuraEnabled public String locationType;
        @AuraEnabled public String sessionLink;
        @AuraEnabled public Id eventId;
        @AuraEnabled public String eventName;
        @AuraEnabled public String eventBanner;
        @AuraEnabled public String eventStatus;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public Boolean isFree;
        @AuraEnabled public Integer participantsCount;
        @AuraEnabled public String bookingType;
        @AuraEnabled public DateTime bookingDate;
        @AuraEnabled public Boolean feedbackSubmitted;
        @AuraEnabled public Boolean hasFeedbackForm;
    }

    private static Id currentRespondentAccountIdSafe() {
        try {
            User u = [SELECT Id, ContactId, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (u.AccountId != null) return u.AccountId;
            if (u.ContactId != null) {
                List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :u.ContactId LIMIT 1];
                if (!contacts.isEmpty()) return contacts[0].AccountId;
            }
        } catch (Exception e) {
            // intentionally swallowed — feedback flag is non-critical
        }
        return null;
    }

    public class EventWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String imageUrl { get; set; }
        @AuraEnabled public String eventType { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Time startTime { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public String participantsCount { get; set; }
        @AuraEnabled public Boolean featuredEvents { get; set; }
        @AuraEnabled public Date postedDate { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String expectations { get; set; }
        @AuraEnabled public String categories { get; set; }
        @AuraEnabled public String eventStatus { get; set; }
        @AuraEnabled public String rejectionReason { get; set; }
        // 'By Alumni' when the event was hosted by an alumni (Constituent_Role__c set via the
        // portal Host-an-Event flow); otherwise the admin label ('By {Institution Alias}',
        // or 'By Admin' when no alias is configured) for events created internally by staff.
        @AuraEnabled public String createdBy { get; set; }
        public EventWrapper(Ken_Event_Master__c event) {
            this(event, 'By Admin');
        }
        public EventWrapper(Ken_Event_Master__c event, String adminLabel) {
            this.id = event.Id;
            this.title = event.Name;
            this.imageUrl = event.Event_banner__c;
            this.eventType = (event.Start_Date__c == event.End_Date__c) ? 'One-day' : 'Multi-day';
            this.startDate = event.Start_Date__c;
            this.startTime = event.Start_Time__c;
            this.endDate = event.End_Date__c;
            this.eventStatus = event.Event_Status__c;
            this.featuredEvents = false;
            this.createdBy = (event.Constituent_Role__c != null)
                ? 'By Alumni'
                : (String.isNotBlank(adminLabel) ? adminLabel : 'By Admin');
        }
    }
    
    public class EventDetailWrapper{
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String image { get; set; }
        @AuraEnabled public String eventType { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public String participantsCount { get; set; }
        @AuraEnabled public Date postedDate { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String expectations { get; set; }
        @AuraEnabled public String categories;
        @AuraEnabled public String brochureUrl;
        @AuraEnabled public Boolean hasBrochure;
        @AuraEnabled public String eventStatus;
        @AuraEnabled public String targetKeywords;
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String language { get; set; }
        @AuraEnabled public Decimal eventFee { get; set; }
        @AuraEnabled public Boolean noFee { get; set; }
        @AuraEnabled public Boolean offerMeals { get; set; }
        @AuraEnabled public Boolean collectDietary { get; set; }
        @AuraEnabled public String dietaryPreferences { get; set; }
        @AuraEnabled public Decimal mealFee { get; set; }
        @AuraEnabled public Boolean makeMealsPaid { get; set; }
        @AuraEnabled public Boolean canBringGuests { get; set; }
        @AuraEnabled public Integer guestCount { get; set; }
        @AuraEnabled public String photosLink { get; set; }
        @AuraEnabled public String highlightsLink { get; set; }
        @AuraEnabled public String hostRoleId { get; set; }
        @AuraEnabled public String rejectionReason { get; set; }

        public EventDetailWrapper(Ken_Event_Master__c event) {
            this.id = event.Id;
            this.title = event.Name;
            this.image = event.Event_banner__c;
            this.eventType = (event.Start_Date__c == event.End_Date__c) ? 'One-day' : 'Multi-day';
            this.startDate = event.Start_Date__c;
            this.endDate = event.End_Date__c;
            this.postedDate = event.createddate.date();
            this.description = event.Description__c;
            this.expectations = event.What_to_Expect_From_Event__c;
            this.participantsCount = event.Max_Allowed_Participants__c != null ?
                event.Max_Allowed_Participants__c.toString() : '0';
            this.brochureUrl = event.Event_Broucher__c;
            this.hasBrochure = String.isNotBlank(event.Event_Broucher__c);
            this.eventStatus = event.Event_Status__c;
            this.targetKeywords = event.Target_Keywords__c;
            this.categories = event.Event_Type__c;
            this.location = event.Location__c;
            this.language = event.Language__c;
            this.eventFee = event.Event_Fee__c;
            this.noFee = event.No_Fee__c;
            this.offerMeals = event.Offer_Meals__c;
            this.collectDietary = event.Collect_Dietary_Preferences__c;
            this.dietaryPreferences = event.Dietary_Preferences__c;
            this.mealFee = event.Meal_Fee__c;
            this.makeMealsPaid = event.Make_Meals_Paid__c;
            this.canBringGuests = event.Can_Alumni_Bring_Guests__c;
            this.guestCount = event.Guest_Count__c != null ? Integer.valueOf(event.Guest_Count__c) : 0;
            this.photosLink = event.Event_Photos_Link__c;
            this.highlightsLink = event.Event_Highlights_Link__c;
            this.hostRoleId = event.Constituent_Role__c;
            this.rejectionReason = event.Reason_For_Rejection__c;
        }
    }

    // Host adds/updates the post-event Photos and Highlights links shown on the Event Updates tab.
    @AuraEnabled
    public static void saveEventUpdateLinks(String eventId, String photosLink, String highlightsLink) {
        try {
            if (String.isBlank(eventId)) {
                throw new AuraHandledException('Event id is required.');
            }
            Ken_Event_Master__c ev = new Ken_Event_Master__c(Id = eventId);
            ev.Event_Photos_Link__c = String.isBlank(photosLink) ? null : photosLink;
            ev.Event_Highlights_Link__c = String.isBlank(highlightsLink) ? null : highlightsLink;
            update ev;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving links: ' + e.getMessage());
        }
    }

    // Count of attendees who opted meals, keyed by session date (yyyy-MM-dd) — host/approved view.
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getMealOptedCounts(String eventId) {
        Map<String, Integer> counts = new Map<String, Integer>();
        if (String.isBlank(eventId)) return counts;
        for (AggregateResult ar : [
            SELECT Schedules_Sessions__r.Start_Date__c dt, COUNT(Id) cnt
            FROM Ken_Event_Booking__c
            WHERE Schedules_Sessions__r.Event_Reference__c = :eventId
            AND Type__c = 'Registered' AND Meals_Opted__c = true
            GROUP BY Schedules_Sessions__r.Start_Date__c
        ]) {
            Date d = (Date) ar.get('dt');
            if (d != null) {
                String key = Datetime.newInstance(d.year(), d.month(), d.day(), 0, 0, 0).format('yyyy-MM-dd');
                counts.put(key, (Integer) ar.get('cnt'));
            }
        }
        return counts;
    }
    
    public class ScheduleWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Date sessionDate;
        @AuraEnabled public Time startTime;
        @AuraEnabled public Time endTime;
        @AuraEnabled public String title;
        @AuraEnabled public List<SpeakerWrapper> speakers;
        @AuraEnabled public String speakerNames;
        @AuraEnabled public String agenda;
        @AuraEnabled public Boolean isRegistered;
        @AuraEnabled public String meals;
        @AuraEnabled public String location;
        @AuraEnabled public String locationType;
        @AuraEnabled public String sessionLink;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Boolean noFee;
    }
    
    public class SpeakerWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String image;
        @AuraEnabled public String description;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getCurrentParticipantDetails(Id constituentRoleId) {
        try {
            if (constituentRoleId == null) throw new AuraHandledException('No constituent role');
            ConstituentRole role = [
                SELECT Id, PersonId, Email__c
                FROM ConstituentRole WHERE Id = :constituentRoleId LIMIT 1
            ];
            Map<String, String> details = new Map<String, String>();
            details.put('email', role.Email__c != null ? role.Email__c : '');
            if (role.PersonId != null) {
                Account acc = [SELECT Id, Name, PersonMobilePhone FROM Account WHERE Id = :role.PersonId LIMIT 1];
                details.put('name', acc.Name != null ? acc.Name : '');
                details.put('phone', acc.PersonMobilePhone != null ? acc.PersonMobilePhone : '');
            } else {
                details.put('name', '');
                details.put('phone', '');
            }
            return details;
        } catch (Exception e) {
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteHostedEvent(String eventId) {
        try {
            if (String.isBlank(eventId)) throw new AuraHandledException('Event id required.');
            Ken_Event_Master__c ev = [SELECT Id, Event_Status__c FROM Ken_Event_Master__c WHERE Id = :eventId LIMIT 1];
            delete ev;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting event: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static EventUpdatesWrapper getEventUpdatesData(String eventId) {
        try {
            EventUpdatesWrapper result = new EventUpdatesWrapper();
            result.preEventSurveys = new List<SurveyCardWrapper>();
            result.sessions = new List<SessionFeedbackWrapper>();
            if (String.isBlank(eventId)) return result;

            Ken_Event_Master__c ev = null;
            Set<Id> preEventSurveyIds = new Set<Id>();
            List<Ken_Event_Master__c> events = [SELECT Survey__c, Start_Date__c, End_Date__c FROM Ken_Event_Master__c WHERE Id = :eventId LIMIT 1];
            if (!events.isEmpty()) {
                ev = events[0];
                if (ev.Survey__c != null) preEventSurveyIds.add(ev.Survey__c);
            }

            List<Ken_Schedule_Sessions__c> sessionList = [
                SELECT Id, Name, Start_Date__c, Survey__c
                FROM Ken_Schedule_Sessions__c
                WHERE Event_Reference__c = :eventId
                ORDER BY Start_Date__c ASC, Start_Time__c ASC
            ];

            Set<Id> sessionSurveyIds = new Set<Id>();
            for (Ken_Schedule_Sessions__c s : sessionList) {
                if (s.Survey__c != null) sessionSurveyIds.add(s.Survey__c);
            }

            Set<Id> allSurveyIds = new Set<Id>();
            allSurveyIds.addAll(preEventSurveyIds);
            allSurveyIds.addAll(sessionSurveyIds);

            Map<Id, Ken_Survey__c> surveyMap = new Map<Id, Ken_Survey__c>();
            if (!allSurveyIds.isEmpty()) {
                for (Ken_Survey__c s : [SELECT Id, Name, Start_Date__c, End_Date__c, Type__c, Ken_Questionnaire__c FROM Ken_Survey__c WHERE Id IN :allSurveyIds]) {
                    surveyMap.put(s.Id, s);
                }
            }

            // Responses reach the survey via the questionnaire link; map back to survey id.
            Map<Id, Integer> responseCounts = new Map<Id, Integer>();
            Map<Id, Id> surveyByQuestionnaire = new Map<Id, Id>();
            for (Ken_Survey__c s : surveyMap.values()) {
                if (s.Ken_Questionnaire__c != null) surveyByQuestionnaire.put(s.Ken_Questionnaire__c, s.Id);
            }
            if (!surveyByQuestionnaire.isEmpty()) {
                Set<Id> respQIds = surveyByQuestionnaire.keySet();
                for (AggregateResult ar : [SELECT Questionnaire_Parameter__r.Questionnaire__c qId, COUNT(Id) cnt FROM Ken_Questionnaire_Parameter_Response__c WHERE Questionnaire_Parameter__r.Questionnaire__c IN :respQIds GROUP BY Questionnaire_Parameter__r.Questionnaire__c]) {
                    Id qId = (Id) ar.get('qId');
                    if (surveyByQuestionnaire.containsKey(qId)) responseCounts.put(surveyByQuestionnaire.get(qId), (Integer) ar.get('cnt'));
                }
            }

            Set<Id> questionnaireIds = new Set<Id>();
            for (Ken_Survey__c s : surveyMap.values()) {
                if (s.Ken_Questionnaire__c != null) questionnaireIds.add(s.Ken_Questionnaire__c);
            }
            Map<Id, Integer> qParamCounts = new Map<Id, Integer>();
            if (!questionnaireIds.isEmpty()) {
                for (AggregateResult ar : [SELECT Questionnaire__c qId, COUNT(Id) cnt FROM Ken_Questionnaire_Parameter__c WHERE Questionnaire__c IN :questionnaireIds GROUP BY Questionnaire__c]) {
                    qParamCounts.put((Id) ar.get('qId'), (Integer) ar.get('cnt'));
                }
            }

            DateTime now = DateTime.now();
            Boolean eventEnded = ev != null && ev.End_Date__c != null
                && DateTime.newInstance(ev.End_Date__c, Time.newInstance(23, 59, 59, 0)) < now;

            for (Id sid : preEventSurveyIds) {
                if (surveyMap.containsKey(sid)) {
                    result.preEventSurveys.add(buildSurveyCard(surveyMap.get(sid), responseCounts, qParamCounts, now, eventEnded));
                }
            }

            for (Ken_Schedule_Sessions__c sess : sessionList) {
                SessionFeedbackWrapper sf = new SessionFeedbackWrapper();
                sf.sessionId = sess.Id;
                sf.sessionName = sess.Name;
                sf.sessionDate = sess.Start_Date__c != null ? String.valueOf(sess.Start_Date__c) : null;
                sf.hasSurvey = sess.Survey__c != null && surveyMap.containsKey(sess.Survey__c);
                if (sf.hasSurvey) {
                    Ken_Survey__c s = surveyMap.get(sess.Survey__c);
                    sf.surveyId = s.Id;
                    sf.surveyName = s.Name;
                    sf.responseCount = responseCounts.containsKey(s.Id) ? responseCounts.get(s.Id) : 0;
                    sf.hasQuestionnaire = s.Ken_Questionnaire__c != null;
                    sf.questionCount = (s.Ken_Questionnaire__c != null && qParamCounts.containsKey(s.Ken_Questionnaire__c)) ? qParamCounts.get(s.Ken_Questionnaire__c) : 0;
                    if (eventEnded || (s.End_Date__c != null && s.End_Date__c < now)) {
                        sf.status = 'Completed';
                    } else if (s.Start_Date__c != null && s.Start_Date__c <= now) {
                        sf.status = 'Active';
                    } else {
                        sf.status = 'Upcoming';
                    }
                } else {
                    sf.surveyId = null;
                    sf.surveyName = null;
                    sf.responseCount = 0;
                    sf.hasQuestionnaire = false;
                    sf.questionCount = 0;
                    sf.status = 'No Form';
                }
                result.sessions.add(sf);
            }

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching event updates: ' + e.getMessage());
        }
    }

    private static SurveyCardWrapper buildSurveyCard(Ken_Survey__c s, Map<Id, Integer> responseCounts, Map<Id, Integer> qParamCounts, DateTime now, Boolean eventEnded) {
        SurveyCardWrapper w = new SurveyCardWrapper();
        w.id = s.Id;
        w.name = s.Name;
        w.startDate = s.Start_Date__c != null ? s.Start_Date__c.date() : null;
        w.endDate = s.End_Date__c != null ? s.End_Date__c.date() : null;
        w.surveyType = s.Type__c;
        w.responseCount = responseCounts.containsKey(s.Id) ? responseCounts.get(s.Id) : 0;
        w.questionCount = (s.Ken_Questionnaire__c != null && qParamCounts.containsKey(s.Ken_Questionnaire__c)) ? qParamCounts.get(s.Ken_Questionnaire__c) : 0;
        w.hasQuestionnaire = s.Ken_Questionnaire__c != null;
        if (eventEnded || (s.End_Date__c != null && s.End_Date__c < now)) {
            w.status = 'Completed';
        } else if (s.Start_Date__c != null && s.Start_Date__c <= now) {
            w.status = 'Active';
        } else {
            w.status = 'Upcoming';
        }
        return w;
    }

    public class EventUpdatesWrapper {
        @AuraEnabled public List<SurveyCardWrapper> preEventSurveys { get; set; }
        @AuraEnabled public List<SessionFeedbackWrapper> sessions { get; set; }
    }

    public class SessionFeedbackWrapper {
        @AuraEnabled public String sessionId { get; set; }
        @AuraEnabled public String sessionName { get; set; }
        @AuraEnabled public String sessionDate { get; set; }
        @AuraEnabled public String surveyId { get; set; }
        @AuraEnabled public String surveyName { get; set; }
        @AuraEnabled public Integer responseCount { get; set; }
        @AuraEnabled public Integer questionCount { get; set; }
        @AuraEnabled public Boolean hasQuestionnaire { get; set; }
        @AuraEnabled public Boolean hasSurvey { get; set; }
        @AuraEnabled public String status { get; set; }
    }

    public class SurveyCardWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String surveyType;
        @AuraEnabled public Integer responseCount;
        @AuraEnabled public Integer questionCount;
        @AuraEnabled public Boolean hasQuestionnaire;
        @AuraEnabled public String status;
    }
}