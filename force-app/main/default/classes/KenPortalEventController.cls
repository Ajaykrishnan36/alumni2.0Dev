public without sharing class KenPortalEventController {
  @AuraEnabled(cacheable=true)
  public static List<EventWrapper> getAllEvents() {
    User currentUser = [
      SELECT Id, Profile.Name
      FROM User
      WHERE Id = :userinfo.getUserId()
    WITH SYSTEM_MODE
    ];
    String profileName = currentUser.Profile.Name;
    Ken_Alm_Org_Parameters__c orgParam = Ken_Alm_Org_Parameters__c.getOrgDefaults();
    String adminLabel = (orgParam != null &&
      String.isNotBlank(orgParam.Institution_Alias__c))
      ? 'By ' + orgParam.Institution_Alias__c
      : 'By Admin';
    List<EventWrapper> eventWrappers = new List<EventWrapper>();
    for (Ken_Event_Master__c ev : [
      SELECT
        Id,
        Name,
        End_Date__c,
        Event_Type__c,
        Event_banner__c,
        Location__c,
        Start_Date__c,
        Event_Status__c,
        Target_Audience_Applicable__c,
        Constituent_Role__c,
        (
          SELECT Id, Start_DateTime__c, End_DateTime__c
          FROM Schedule_Sessions__r
        )
      FROM Ken_Event_Master__c
      WHERE Is_Active__c = TRUE AND Event_Status__c = 'Approved'
    WITH SECURITY_ENFORCED
    ]) {
      eventWrappers.add(new EventWrapper(ev, adminLabel));
    }
    System.debug('eventWrappers -- ' + eventWrappers);
    return eventWrappers;
  }

  @AuraEnabled
  public static List<Ken_Event_Master__c> getHostedEvents() {
    try {
      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
      if (constituentRoleId == null) {
        throw new AuraHandledException(
          'No constituent role found for current user.'
        );
      }

      Set<String> approvalStatuses = new Set<String>{
        'In Review',
        'Approved',
        'Rejected',
        'Cancelled',
        'Draft',
        'In Progress'
      };

      return [
        SELECT
          Id,
          Name,
          Start_Date__c,
          End_Date__c,
          Event_Type__c,
          Event_banner__c,
          Location__c,
          Reason_For_Rejection__c,
          Max_Allowed_Participants__c,
          Event_Status__c,
          Event_Fee__c,
          No_Fee__c,
          Offer_Meals__c,
          CreatedDate,
          LastModifiedDate,
          Rejected_On__c,
          (
            SELECT Id, Session_Fee__c, No_Fee__c, Location_Type__c
            FROM Schedule_Sessions__r
          )
        FROM Ken_Event_Master__c
        WHERE
          Constituent_Role__c = :constituentRoleId
          AND Event_Status__c IN :approvalStatuses
        WITH SECURITY_ENFORCED
        ORDER BY CREATEDDATE DESC
      ];
    } catch (Exception e) {
      throw new AuraHandledException('Error :' + e.getmessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Ken_Schedule_Sessions__c> getEventSessions(Id EventId) {
    List<Ken_Schedule_Sessions__c> sessions = new List<Ken_Schedule_Sessions__c>();
    for (Ken_Schedule_Sessions__c sess : [
      SELECT Id, Name, End_DateTime__c
      FROM Ken_Schedule_Sessions__c
      WHERE Event_Reference__c = :EventId
    WITH SECURITY_ENFORCED
    ]) {
      sessions.add(sess);
    }

    if (sessions.isEmpty()) {
      throw new AuraHandledException('no sessions to register');
    }
    return sessions;
  }

  @AuraEnabled(Cacheable=true)
  public static List<Ken_Schedule_Sessions__c> getRegisteredSessions(
    Id EventId
  ) {
    try {
      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
      if (constituentRoleId == null) {
        throw new AuraHandledException(
          'No constituent role found for current user.'
        );
      }

      return [
        SELECT Id, Name, Start_DateTime__c, Event_Reference__c
        FROM Ken_Schedule_Sessions__c
        WHERE
          Event_Reference__c = :EventId
          AND Id IN (
            SELECT Schedules_Sessions__c
            FROM Ken_Event_Booking__c
            WHERE
              Constituent_Role__c = :constituentRoleId
              AND Type__c = 'Registered'
          )
        WITH SECURITY_ENFORCED
        ORDER BY Start_DateTime__c ASC NULLS LAST
      ];
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching registered sessions: ' +
          e.getMessage() +
          ' ' +
          e.getLineNumber()
      );
    }
  }

  @AuraEnabled(Cacheable=true)
  public static EventDetailWrapper getEventDetails(String recordId) {
    try {
      if (String.isBlank(recordId)) {
        throw new AuraHandledException('Record ID is required');
      }

      Ken_Event_Master__c event = [
        SELECT
          Id,
          Name,
          Start_Date__c,
          End_Date__c,
          Description__c,
          Event_Type__c,
          Event_banner__c,
          Language__c,
          Max_Allowed_Participants__c,
          What_to_Expect_From_Event__c,
          Event_Broucher__c,
          CreatedDate,
          Target_Topics__c,
          Location__c,
          Event_Status__c,
          Reason_For_Rejection__c,
          Event_Fee__c,
          No_Fee__c,
          Offer_Meals__c,
          Collect_Dietary_Preferences__c,
          Dietary_Preferences__c,
          Meal_Fee__c,
          Make_Meals_Paid__c,
          Can_Alumni_Bring_Guests__c,
          Guest_Count__c,
          Event_Photos_Link__c,
          Event_Highlights_Link__c,
          Constituent_Role__c
        FROM Ken_Event_Master__c
        WHERE Id = :recordId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];

      EventDetailWrapper result = new EventDetailWrapper(event);
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching event details: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<ScheduleWrapper> getEventSchedules(String eventId) {
    try {
      if (String.isBlank(eventId)) {
        throw new AuraHandledException('Record ID is required');
      }
      // The resolved role is optional here: internal users have none, so we still
      // return the sessions, just without the per-user "registered" flag.
      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();

      List<ScheduleWrapper> schedules = new List<ScheduleWrapper>();

      List<Ken_Schedule_Sessions__c> eventSchedules = [
        SELECT
          Id,
          Name,
          What_to_Expect_From_Event__c,
          Start_DateTime__c,
          End_DateTime__c,
          Location__c,
          Location_Type__c,
          Session_Fee__c,
          No_Fee__c,
          Meals__c,
          Session_Link__c,
          (
            SELECT
              Id,
              Person_Account__c,
              Person_Account__r.Name,
              Speaker_Image__c,
              Description__c,
              Speaker_Name__c
            FROM Event_Session_Account_Associations__r
          )
        FROM Ken_Schedule_Sessions__c
        WHERE Event_Reference__c = :eventId
        //AND Is_Cancelled__c = false
        WITH SECURITY_ENFORCED
        ORDER BY Start_DateTime__c NULLS LAST
      ];

      Map<Id, Ken_Schedule_Sessions__c> registeredSessionsMap = new Map<Id, Ken_Schedule_Sessions__c>();
      if (constituentRoleId != null) {
        registeredSessionsMap = new Map<Id, Ken_Schedule_Sessions__c>(
          [
            SELECT Id
            FROM Ken_Schedule_Sessions__c
            WHERE
              Event_Reference__c = :EventId
              AND Id IN (
                SELECT Schedules_Sessions__c
                FROM Ken_Event_Booking__c
                WHERE
                  Constituent_Role__c = :constituentRoleId
                  AND Type__c = 'Registered'
              )
          WITH SECURITY_ENFORCED
          ]
        );
      }

      for (Ken_Schedule_Sessions__c schedule : eventSchedules) {
        ScheduleWrapper wrapper = new ScheduleWrapper();
        wrapper.id = schedule.Id;
        wrapper.name = schedule.Name;
        // Date derived from the one stored instant, never duplicated.
        wrapper.sessionDate = KenDateTimeUtil.localDate(
          schedule.Start_DateTime__c
        );
        wrapper.startInstant = KenDateTimeUtil.formatInstant(
          schedule.Start_DateTime__c
        );
        wrapper.endInstant = KenDateTimeUtil.formatInstant(
          schedule.End_DateTime__c
        );
        wrapper.title = schedule.Name;
        wrapper.agenda = schedule.What_to_Expect_From_Event__c;
        wrapper.isRegistered = registeredSessionsMap.containsKey(schedule.Id);
        wrapper.meals = schedule.Meals__c;
        wrapper.location = schedule.Location__c;
        wrapper.locationType = schedule.Location_Type__c;
        // Never ship the meeting link to users who haven't registered for
        // the session — otherwise anyone can join the meeting.
        wrapper.sessionLink = wrapper.isRegistered
          ? schedule.Session_Link__c
          : null;
        wrapper.price = schedule.Session_Fee__c;
        wrapper.noFee = schedule.No_Fee__c;

        // Process speakers
        wrapper.speakers = new List<SpeakerWrapper>();
        List<String> speakerNames = new List<String>();

        for (
          Ken_Events_Sessions_Enrollment__c speakerEnroll : schedule.Event_Session_Account_Associations__r
        ) {
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
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching session details: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static String saveRegistrations(List<Id> sessionIds) {
    try {
      if (sessionIds == null || sessionIds.isEmpty()) {
        throw new AuraHandledException('Please select at least one session.');
      }

      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
      if (constituentRoleId == null) {
        throw new AuraHandledException(
          'No constituent role found for current user.'
        );
      }

      List<Ken_Event_Booking__c> existingBookings = [
        SELECT Id, Constituent_Role__c, Schedules_Sessions__c, Type__c
        FROM Ken_Event_Booking__c
        WHERE
          Constituent_Role__c = :constituentRoleId
          AND Schedules_Sessions__c IN :sessionIds
      WITH SECURITY_ENFORCED
      ];
      Map<Id, Id> sessionBookingMap = new Map<Id, Id>();
      for (Ken_Event_Booking__c booking : existingBookings) {
        sessionBookingMap.put(booking.Schedules_Sessions__c, booking.Id);
      }

      List<Ken_Event_Booking__c> registrationToUpsert = new List<Ken_Event_Booking__c>();
      for (Id sessionId : sessionIds) {
        registrationToUpsert.add(
          new Ken_Event_Booking__c(
            Id = sessionBookingMap.get(sessionId),
            Constituent_Role__c = constituentRoleId,
            Schedules_Sessions__c = sessionId,
            Type__c = 'Registered'
          )
        );
      }

      if (!Schema.sObjectType.Ken_Event_Booking__c.isCreateable() || !Schema.sObjectType.Ken_Event_Booking__c.isUpdateable()) {
          throw new KenCrudException('Ken_Event_Booking__c is not upsertable by the current user.');
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
  public static String saveEventRegistrations(String payload) {
    try {
      if (String.isBlank(payload)) {
        throw new AuraHandledException('Registration payload is required.');
      }
      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
      if (constituentRoleId == null) {
        throw new AuraHandledException(
          'No constituent role found for current user.'
        );
      }

      RegistrationRequest req = (RegistrationRequest) JSON.deserialize(
        payload,
        RegistrationRequest.class
      );
      if (req.sessionIds == null || req.sessionIds.isEmpty()) {
        throw new AuraHandledException('Please select at least one session.');
      }
      if (req.participants == null || req.participants.isEmpty()) {
        throw new AuraHandledException('Please add at least one participant.');
      }

      // The registrant's person account (used for Myself bookings)
      Id registrantPersonId;
      for (ConstituentRole cr : [
        SELECT Id, PersonId
        FROM ConstituentRole
        WHERE Id = :constituentRoleId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ]) {
        registrantPersonId = cr.PersonId;
      }

      List<Ken_Event_Booking__c> toInsert = new List<Ken_Event_Booking__c>();

      for (ParticipantData p : req.participants) {
        String personType = String.isBlank(p.type) ? 'Myself' : p.type;

        // Authoritative gate — the client already checks this on "Add Guest", but that
        // is convenience only; this is what actually can't be bypassed.
        if (personType == 'Guest') {
          GuestInviteCheckResult check = checkGuestInvitePermission(p.email);
          if (!check.allowed) {
            throw new AuraHandledException(check.reason);
          }
        }

        Integer attendees = 1;
        if (personType == 'Group') {
          // Bulk-registering a group is an events-admin-only action, and only the
          // members whose "who can invite me to events" preference allows it are
          // actually counted — the client-supplied member count is never trusted.
          if (!isCurrentUserEventsAdmin()) {
            throw new AuraHandledException(
              'Only an events admin can bulk-register a group for this event.'
            );
          }
          if (String.isBlank(p.groupId)) {
            throw new AuraHandledException(
              'Group ID is required for a group registration.'
            );
          }
          List<Id> memberAccountIds = new List<Id>();
          for (Ken_Group_Member__c m : [
            SELECT Member__c
            FROM Ken_Group_Member__c
            WHERE Group__c = :(Id) p.groupId AND Status__c = 'Approved'
          WITH SECURITY_ENFORCED
          ]) {
            memberAccountIds.add(m.Member__c);
          }
          attendees = allowedGroupMemberAccountIds(memberAccountIds).size();
        }

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
        if (!Schema.sObjectType.Ken_Event_Booking__c.isCreateable()) {
            throw new KenCrudException('Ken_Event_Booking__c is not createable by the current user.');
        }
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
  public static RegistrationSummaryWrapper getRegistrationSummary(
    String eventId
  ) {
    try {
      if (String.isBlank(eventId)) {
        throw new AuraHandledException('Event id is required.');
      }
      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
      if (constituentRoleId == null) {
        throw new AuraHandledException(
          'No constituent role found for current user.'
        );
      }

      RegistrationSummaryWrapper result = new RegistrationSummaryWrapper();
      for (Ken_Event_Master__c ev : [
        SELECT
          Id,
          Name,
          Event_banner__c,
          Start_Date__c,
          End_Date__c,
          Location__c,
          Language__c,
          Offer_Meals__c
        FROM Ken_Event_Master__c
        WHERE Id = :eventId
        WITH SECURITY_ENFORCED
        LIMIT 1
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
        SELECT
          Id,
          Type__c,
          Booking_Person_Type__c,
          Meals_Opted__c,
          Dietary_Preference__c,
          Guest_Name__c,
          Guest_Email__c,
          Guest_Phone__c,
          Group__c,
          Group__r.Name,
          Person_Account__c,
          Person_Account__r.Name,
          Person_Account__r.PersonEmail,
          Person_Account__r.PersonMobilePhone,
          Schedules_Sessions__c,
          Schedules_Sessions__r.Name,
          Schedules_Sessions__r.Session_Fee__c,
          Schedules_Sessions__r.Start_DateTime__c,
          Schedules_Sessions__r.End_DateTime__c,
          Schedules_Sessions__r.No_Fee__c
        FROM Ken_Event_Booking__c
        WHERE
          Schedules_Sessions__r.Event_Reference__c = :eventId
          AND Constituent_Role__c = :constituentRoleId
          AND Type__c = 'Registered'
        WITH SECURITY_ENFORCED
        ORDER BY Schedules_Sessions__r.Start_DateTime__c NULLS LAST
      ];

      Map<String, SummaryParticipant> participantMap = new Map<String, SummaryParticipant>();
      Map<Id, SummarySession> sessionMap = new Map<Id, SummarySession>();

      for (Ken_Event_Booking__c b : bookings) {
        String pType = String.isBlank(b.Booking_Person_Type__c)
          ? 'Myself'
          : b.Booking_Person_Type__c;
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
          pEmail = b.Person_Account__r != null
            ? b.Person_Account__r.PersonEmail
            : '';
          pPhone = b.Person_Account__r != null
            ? b.Person_Account__r.PersonMobilePhone
            : '';
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
          ss.sessionDate = KenDateTimeUtil.localDate(
            b.Schedules_Sessions__r.Start_DateTime__c
          );
          ss.price = (b.Schedules_Sessions__r.No_Fee__c == true)
            ? 0
            : b.Schedules_Sessions__r.Session_Fee__c;
          sessionMap.put(b.Schedules_Sessions__c, ss);
        }
      }

      result.participants = participantMap.values();
      result.sessions = sessionMap.values();
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading registration summary: ' + e.getMessage()
      );
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

      // The event's pre-event survey (used to flag "Custom Form" filled).
      Id eventSurveyId;
      Id eventQuestionSetId;
      for (Ken_Event_Master__c ev : [
        SELECT Id, Survey__c, Survey__r.Assessment_Question_Set__c
        FROM Ken_Event_Master__c
        WHERE Id = :eventId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ]) {
        eventQuestionSetId = ev.Survey__r != null
          ? ev.Survey__r.Assessment_Question_Set__c
          : null;
        eventSurveyId = ev.Survey__c;
      }
      Set<Id> respondedAccountIds = new Set<Id>();
      if (eventQuestionSetId != null && eventSurveyId != null) {
        for (Assessment submission : [
          SELECT Respondent__c
          FROM Assessment
          WHERE Ken_Survey__c = :eventSurveyId AND Respondent__c != NULL
        WITH SECURITY_ENFORCED
        ]) {
          respondedAccountIds.add(submission.Respondent__c);
        }
      }

      List<Ken_Event_Booking__c> bookings = [
        SELECT
          Id,
          CreatedDate,
          Booking_Person_Type__c,
          Meals_Opted__c,
          Dietary_Preference__c,
          Guest_Name__c,
          Guest_Email__c,
          Guest_Phone__c,
          Group__c,
          Group__r.Name,
          Person_Account__c,
          Person_Account__r.Name,
          Person_Account__r.PersonEmail,
          Person_Account__r.PersonMobilePhone,
          Constituent_Role__c,
          Constituent_Role__r.Graduation_Year__c,
          Schedules_Sessions__c
        FROM Ken_Event_Booking__c
        WHERE
          Schedules_Sessions__r.Event_Reference__c = :eventId
          AND Type__c = 'Registered'
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate ASC
      ];

      Map<String, EventParticipant> byKey = new Map<String, EventParticipant>();
      Map<String, Set<Id>> sessionsByKey = new Map<String, Set<Id>>();

      for (Ken_Event_Booking__c b : bookings) {
        String pType = String.isBlank(b.Booking_Person_Type__c)
          ? 'Myself'
          : b.Booking_Person_Type__c;
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
            p.name = b.Person_Account__r != null
              ? b.Person_Account__r.Name
              : 'Participant';
            p.email = b.Person_Account__r != null
              ? b.Person_Account__r.PersonEmail
              : '';
            p.phone = b.Person_Account__r != null
              ? b.Person_Account__r.PersonMobilePhone
              : '';
            p.batch = (b.Constituent_Role__r != null &&
              b.Constituent_Role__r.Graduation_Year__c != null)
              ? String.valueOf(b.Constituent_Role__r.Graduation_Year__c)
              : '';
            p.customFormFilled = (b.Person_Account__c != null &&
            respondedAccountIds.contains(b.Person_Account__c));
          }
          p.mealsIncluded = false;
          p.registeredOn = b.CreatedDate;
          p.paymentMethod = '';
          p.transactionId = '';
          byKey.put(key, p);
          sessionsByKey.put(key, new Set<Id>());
        }
        if (b.Meals_Opted__c == true)
          p.mealsIncluded = true;
        if (
          String.isBlank(p.diet) && String.isNotBlank(b.Dietary_Preference__c)
        )
          p.diet = b.Dietary_Preference__c;
        if (b.Schedules_Sessions__c != null)
          sessionsByKey.get(key).add(b.Schedules_Sessions__c);
        if (
          b.CreatedDate != null &&
          (p.registeredOn == null ||
          b.CreatedDate < p.registeredOn)
        ) {
          p.registeredOn = b.CreatedDate;
        }
      }

      for (String k : byKey.keySet()) {
        byKey.get(k).sessionsCount = sessionsByKey.get(k).size();
      }
      return byKey.values();
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading participants: ' + e.getMessage()
      );
    }
  }

  public class EventParticipant {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String batch;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public Integer sessionsCount;
    @AuraEnabled
    public Boolean mealsIncluded;
    @AuraEnabled
    public String diet;
    @AuraEnabled
    public Boolean customFormFilled;
    @AuraEnabled
    public Datetime registeredOn;
    @AuraEnabled
    public String paymentMethod;
    @AuraEnabled
    public String transactionId;
  }

  public class RegistrationSummaryWrapper {
    @AuraEnabled
    public String eventId;
    @AuraEnabled
    public String eventName;
    @AuraEnabled
    public String eventBanner;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String language;
    @AuraEnabled
    public Boolean offerMeals;
    @AuraEnabled
    public List<SummaryParticipant> participants;
    @AuraEnabled
    public List<SummarySession> sessions;
  }

  public class SummaryParticipant {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public Boolean meals;
    @AuraEnabled
    public String dietaryPref;
  }

  public class SummarySession {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date sessionDate;
    @AuraEnabled
    public Time startTime;
    @AuraEnabled
    public Time endTime;
    @AuraEnabled
    public Decimal price;
  }

  public class RegistrationRequest {
    public List<Id> sessionIds;
    public List<ParticipantData> participants;
  }

  public class ParticipantData {
    public String type; // Myself | Guest | Group
    public String name;
    public String email;
    public String phone;
    public String groupId; // Ken_Group__c Id when type = Group
    public Integer memberCount; // group member count
    public Boolean meals;
    public String dietaryPref;
  }

  // -- Guest-invite preference check ---------------------------------------
  // Ken_Alumni_Preferences__c.Who_can_invite_me_to_events__c only governs a Guest
  // add — one specific person (the registrant) inviting another specific person.
  // It never applies to segmentation/audience matching, which has no inviter to
  // validate against. Resolution is by email only: an unmatched email belongs to
  // someone with no portal identity, so there is no preference to enforce and the
  // add is always allowed.
  public class GuestInviteCheckResult {
    @AuraEnabled
    public Boolean matched;
    @AuraEnabled
    public String matchedName;
    @AuraEnabled
    public Boolean allowed;
    @AuraEnabled
    public String reason;
  }

  @AuraEnabled
  public static GuestInviteCheckResult checkGuestInvitePermission(
    String email
  ) {
    GuestInviteCheckResult result = new GuestInviteCheckResult();
    result.matched = false;
    result.allowed = true;

    String emailVal = email == null ? '' : email.trim();
    if (String.isBlank(emailVal))
      return result;

    List<Account> matches = [
      SELECT Id, Name
      FROM Account
      WHERE PersonEmail = :emailVal
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (matches.isEmpty())
      return result;

    Account matchedAccount = matches[0];
    result.matched = true;
    result.matchedName = matchedAccount.Name;

    String pref = 'Everyone';
    for (Ken_Alumni_Preferences__c p : [
      SELECT Who_can_invite_me_to_events__c
      FROM Ken_Alumni_Preferences__c
      WHERE Person_Account__c = :matchedAccount.Id
      WITH SECURITY_ENFORCED
      LIMIT 1
    ]) {
      if (String.isNotBlank(p.Who_can_invite_me_to_events__c)) {
        pref = p.Who_can_invite_me_to_events__c;
      }
    }

    Boolean inviterIsAdmin = isCurrentUserEventsAdmin();
    if (pref == 'Only other alumni' && inviterIsAdmin) {
      result.allowed = false;
      result.reason =
        matchedAccount.Name + ' only accepts event invites from other alumni.';
    } else if (pref == 'Only admin' && !inviterIsAdmin) {
      result.allowed = false;
      result.reason =
        matchedAccount.Name + ' only accepts event invites from an admin.';
    }
    return result;
  }

  private static Boolean isCurrentUserEventsAdmin() {
    Id userId = UserInfo.getUserId();
    User u = [SELECT Profile.Name FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
    if ('System Administrator'.equalsIgnoreCase(u.Profile.Name))
      return true;
    List<GroupMember> members = [
      SELECT Id
      FROM GroupMember
      WHERE
        Group.Type = 'Queue'
        AND Group.DeveloperName = 'Event_Approvers'
        AND UserOrGroupId = :userId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return !members.isEmpty();
  }

  // -- Bulk (group) registration preference filtering -----------------------
  // Same rule table as checkGuestInvitePermission, applied per group member instead
  // of per typed email: 'Everyone' always allows, 'Only other alumni' blocks an admin
  // inviter, 'Only admin' blocks a non-admin inviter.
  private static List<Id> allowedGroupMemberAccountIds(List<Id> accountIds) {
    List<Id> allowed = new List<Id>();
    if (accountIds == null || accountIds.isEmpty())
      return allowed;

    Boolean inviterIsAdmin = isCurrentUserEventsAdmin();
    Map<Id, String> prefByAccountId = new Map<Id, String>();
    for (Ken_Alumni_Preferences__c p : [
      SELECT Person_Account__c, Who_can_invite_me_to_events__c
      FROM Ken_Alumni_Preferences__c
      WHERE Person_Account__c IN :accountIds
    WITH SECURITY_ENFORCED
    ]) {
      if (String.isNotBlank(p.Who_can_invite_me_to_events__c)) {
        prefByAccountId.put(
          p.Person_Account__c,
          p.Who_can_invite_me_to_events__c
        );
      }
    }

    for (Id accId : accountIds) {
      String pref = prefByAccountId.containsKey(accId)
        ? prefByAccountId.get(accId)
        : 'Everyone';
      Boolean blocked =
        (pref == 'Only other alumni' && inviterIsAdmin) ||
        (pref == 'Only admin' && !inviterIsAdmin);
      if (!blocked)
        allowed.add(accId);
    }
    return allowed;
  }

  // Only an events admin can bulk-register a group at all — gates whether the
  // Bulk Registration option is even offered in the UI.
  @AuraEnabled
  public static Boolean canBulkRegisterGroups() {
    return isCurrentUserEventsAdmin();
  }

  public class GroupRegistrationPreview {
    @AuraEnabled
    public Integer totalMembers;
    @AuraEnabled
    public Integer allowedMembers;
    @AuraEnabled
    public Integer blockedMembers;
  }

  // Lets the UI show "X of Y members will be registered" the moment a group is
  // picked in Bulk Registration, before the final submit re-does this for real.
  @AuraEnabled
  public static GroupRegistrationPreview previewGroupRegistrationForEvent(
    Id groupId
  ) {
    GroupRegistrationPreview preview = new GroupRegistrationPreview();
    preview.totalMembers = 0;
    preview.allowedMembers = 0;
    preview.blockedMembers = 0;
    if (groupId == null)
      return preview;

    List<Id> memberAccountIds = new List<Id>();
    for (Ken_Group_Member__c m : [
      SELECT Member__c
      FROM Ken_Group_Member__c
      WHERE Group__c = :groupId AND Status__c = 'Approved'
    WITH SECURITY_ENFORCED
    ]) {
      memberAccountIds.add(m.Member__c);
    }
    preview.totalMembers = memberAccountIds.size();
    preview.allowedMembers = allowedGroupMemberAccountIds(memberAccountIds)
      .size();
    preview.blockedMembers = preview.totalMembers - preview.allowedMembers;
    return preview;
  }

  @AuraEnabled
  public static String cancelRegistrations(List<Id> sessionIds) {
    try {
      System.debug(
        LoggingLevel.INFO,
        'cancelRegistrations invoked. sessionIds=' + sessionIds
      );
      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
      System.debug(
        LoggingLevel.INFO,
        'cancelRegistrations constituentRoleId=' + constituentRoleId
      );
      if (constituentRoleId == null) {
        throw new AuraHandledException(
          'No constituent role found for current user.'
        );
      }

      // Enforce the cancellation window: cancellations close 72 hours before the event starts.
      if (isCancellationWindowClosed(sessionIds)) {
        throw new AuraHandledException(
          'The cancellation window has closed. Registrations can only be cancelled up to 72 hours before the event starts.'
        );
      }

      List<Ken_Event_Booking__c> registrationsToUpdate = [
        SELECT Id, Type__c
        FROM Ken_Event_Booking__c
        WHERE
          Schedules_Sessions__c IN :sessionIds
          AND Constituent_Role__c = :constituentRoleId
          AND Type__c = 'Registered'
      WITH SECURITY_ENFORCED
      ];
      System.debug(
        LoggingLevel.INFO,
        'cancelRegistrations registrationsToUpdate.size=' +
        registrationsToUpdate.size()
      );
      System.debug(
        LoggingLevel.DEBUG,
        'cancelRegistrations registrationsToUpdate=' + registrationsToUpdate
      );

      if (registrationsToUpdate.isEmpty()) {
        throw new AuraHandledException(
          'No active registrations found to cancel'
        );
      }

      // Update status to Cancelled
      for (Ken_Event_Booking__c reg : registrationsToUpdate) {
        reg.Type__c = 'Cancelled';
      }

      System.debug(
        LoggingLevel.INFO,
        'cancelRegistrations updating registrationsToUpdate size=' +
        registrationsToUpdate.size()
      );
      if (!Schema.sObjectType.Ken_Event_Booking__c.isUpdateable()) {
          throw new KenCrudException('Ken_Event_Booking__c is not updateable by the current user.');
      }
      update registrationsToUpdate;

      return 'Successfully cancelled ' +
        registrationsToUpdate.size() +
        ' registration(s)';
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'cancelRegistrations error: ' + e.getMessage()
      );
      System.debug(
        LoggingLevel.ERROR,
        'cancelRegistrations line: ' + e.getLineNumber()
      );
      System.debug(
        LoggingLevel.ERROR,
        'cancelRegistrations stack: ' + e.getStackTraceString()
      );
      throw new AuraHandledException(
        'Error cancelling registrations: ' + e.getMessage()
      );
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
      SELECT Event_Reference__r.Start_Date__c
      FROM Ken_Schedule_Sessions__c
      WHERE Id IN :sessionIds
    WITH SECURITY_ENFORCED
    ]) {
      Date d = s.Event_Reference__r.Start_Date__c;
      if (d == null) {
        continue;
      }
      // The event is day-granular, so its start is the beginning of its
      // first day. This is already what every event resolved to, since
      // nothing ever wrote a time onto Ken_Event_Master__c.
      DateTime dt = KenDateTimeUtil.dayStart(d);
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
  public static List<RegisteredEventWrapper> getContactRegisteredSessions() {
    try {
      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
      if (constituentRoleId == null) {
        throw new AuraHandledException(
          'No constituent role found for current user.'
        );
      }

      List<Ken_Schedule_Sessions__c> sessions = [
        SELECT
          Id,
          Name,
          Start_DateTime__c,
          End_DateTime__c,
          Location__c,
          Location_Type__c,
          Session_Fee__c,
          No_Fee__c,
          Session_Link__c,
          Survey__c,
          Survey__r.Assessment_Question_Set__c,
          Event_Reference__c,
          Event_Reference__r.Name,
          Event_Reference__r.Event_banner__c,
          Event_Reference__r.Event_Fee__c,
          Event_Reference__r.No_Fee__c,
          Event_Reference__r.Event_Status__c,
          (
            SELECT Id, Type__c, LastModifiedDate
            FROM Event_Bookings__r
            WHERE
              Constituent_Role__c = :constituentRoleId
              AND Type__c IN ('Registered', 'Cancelled')
            ORDER BY LastModifiedDate DESC
            LIMIT 1
          )
        FROM Ken_Schedule_Sessions__c
        WHERE
          Id IN (
            SELECT Schedules_Sessions__c
            FROM Ken_Event_Booking__c
            WHERE Constituent_Role__c = :constituentRoleId
          )
        WITH SECURITY_ENFORCED
        ORDER BY Start_DateTime__c ASC NULLS LAST
      ];

      Set<Id> sessionIds = new Set<Id>();
      for (Ken_Schedule_Sessions__c s : sessions)
        sessionIds.add(s.Id);

      Map<Id, Integer> participantsBySession = new Map<Id, Integer>();
      if (!sessionIds.isEmpty()) {
        for (AggregateResult ar : [
          SELECT Schedules_Sessions__c sId, COUNT(Id) cnt
          FROM Ken_Event_Booking__c
          WHERE Schedules_Sessions__c IN :sessionIds AND Type__c = 'Registered'
          WITH SECURITY_ENFORCED
          GROUP BY Schedules_Sessions__c
        ]) {
          participantsBySession.put(
            (Id) ar.get('sId'),
            (Integer) ar.get('cnt')
          );
        }
      }

      // Feedback completion is tracked via the session's linked Survey.
      Map<Id, Id> surveyToSession = new Map<Id, Id>();
      for (Ken_Schedule_Sessions__c s : sessions) {
        if (
          s.Survey__r != null &&
          s.Survey__r.Assessment_Question_Set__c != null
        ) {
          surveyToSession.put(s.Survey__c, s.Id);
        }
      }
      Set<Id> feedbackSubmittedSessions = new Set<Id>();
      if (!surveyToSession.isEmpty()) {
        Id respondentAccountId = currentRespondentAccountIdSafe();
        if (respondentAccountId != null) {
          for (
            Id answeredSurveyId : KenAssessmentSurveyService.surveysAnsweredBy(
              surveyToSession.keySet(),
              respondentAccountId
            )
          ) {
            feedbackSubmittedSessions.add(
              surveyToSession.get(answeredSurveyId)
            );
          }
        }
      }

      List<RegisteredEventWrapper> result = new List<RegisteredEventWrapper>();
      for (Ken_Schedule_Sessions__c s : sessions) {
        RegisteredEventWrapper w = new RegisteredEventWrapper();
        w.id = s.Id;
        w.name = s.Name;
        w.startDate = KenDateTimeUtil.localDate(s.Start_DateTime__c);
        w.endDate = KenDateTimeUtil.localDate(s.End_DateTime__c);
        w.startInstant = KenDateTimeUtil.formatInstant(s.Start_DateTime__c);
        w.endInstant = KenDateTimeUtil.formatInstant(s.End_DateTime__c);
        w.location = s.Location__c;
        w.locationType = s.Location_Type__c;
        w.sessionLink = s.Session_Link__c;
        w.eventId = s.Event_Reference__c;
        w.eventName = s.Event_Reference__r != null
          ? s.Event_Reference__r.Name
          : null;
        w.eventBanner = s.Event_Reference__r != null
          ? s.Event_Reference__r.Event_banner__c
          : null;
        w.eventStatus = s.Event_Reference__r != null
          ? s.Event_Reference__r.Event_Status__c
          : null;

        Decimal fee = null;
        Boolean isFree = false;
        if (s.No_Fee__c == true) {
          isFree = true;
        } else if (s.Session_Fee__c != null) {
          fee = s.Session_Fee__c;
          isFree = (fee == 0);
        } else if (
          s.Event_Reference__r != null &&
          s.Event_Reference__r.No_Fee__c == true
        ) {
          isFree = true;
        } else if (
          s.Event_Reference__r != null &&
          s.Event_Reference__r.Event_Fee__c != null
        ) {
          fee = s.Event_Reference__r.Event_Fee__c;
          isFree = (fee == 0);
        } else {
          isFree = true;
        }
        w.amountPaid = fee;
        w.isFree = isFree;

        w.participantsCount = participantsBySession.get(s.Id) != null
          ? participantsBySession.get(s.Id)
          : 0;
        w.feedbackSubmitted = feedbackSubmittedSessions.contains(s.Id);
        // A feedback form exists only when the session's survey carries a question
        // set — mirrors getEventFeedbackAsSurvey so the button never points at a
        // blank form.
        w.hasFeedbackForm =
          s.Survey__r != null &&
          s.Survey__r.Assessment_Question_Set__c != null;

        if (s.Event_Bookings__r != null && !s.Event_Bookings__r.isEmpty()) {
          w.bookingType = s.Event_Bookings__r[0].Type__c;
          w.bookingDate = s.Event_Bookings__r[0].LastModifiedDate;
        }
        result.add(w);
      }
      return result;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching registered sessions: ' +
          e.getMessage() +
          ' ' +
          e.getLineNumber()
      );
    }
  }

  private static Long timeToMillis(Time t) {
    if (t == null)
      return 0L;
    return (Long) t.hour() * 3600000L +
      (Long) t.minute() * 60000L +
      (Long) t.second() * 1000L +
      (Long) t.millisecond();
  }

  public class RegisteredEventWrapper {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    // Raw UTC instants; the component formats them in the viewer's own
    // timezone. startDate/startTime above stay for readers not yet moved.
    @AuraEnabled
    public String startInstant;
    @AuraEnabled
    public String endInstant;
    @AuraEnabled
    public Long startTime;
    @AuraEnabled
    public Long endTime;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String locationType;
    @AuraEnabled
    public String sessionLink;
    @AuraEnabled
    public Id eventId;
    @AuraEnabled
    public String eventName;
    @AuraEnabled
    public String eventBanner;
    @AuraEnabled
    public String eventStatus;
    @AuraEnabled
    public Decimal amountPaid;
    @AuraEnabled
    public Boolean isFree;
    @AuraEnabled
    public Integer participantsCount;
    @AuraEnabled
    public String bookingType;
    @AuraEnabled
    public DateTime bookingDate;
    @AuraEnabled
    public Boolean feedbackSubmitted;
    @AuraEnabled
    public Boolean hasFeedbackForm;
  }

  private static Id currentRespondentAccountIdSafe() {
    try {
      User u = [
        SELECT Id, ContactId, AccountId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (u.AccountId != null)
        return u.AccountId;
      if (u.ContactId != null) {
        List<Contact> contacts = [
          SELECT AccountId
          FROM Contact
          WHERE Id = :u.ContactId
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        if (!contacts.isEmpty())
          return contacts[0].AccountId;
      }
    } catch (Exception e) {
      // intentionally swallowed — feedback flag is non-critical
    }
    return null;
  }

  public class EventWrapper {
    // Raw UTC instants; components format them in the viewer's own zone.
    @AuraEnabled
    public String startInstant;
    @AuraEnabled
    public String endInstant;
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String imageUrl { get; set; }
    @AuraEnabled
    public String eventType { get; set; }
    @AuraEnabled
    public Date startDate { get; set; }
    @AuraEnabled
    public Time startTime { get; set; }
    @AuraEnabled
    public Date endDate { get; set; }
    @AuraEnabled
    public String participantsCount { get; set; }
    @AuraEnabled
    public Boolean featuredEvents { get; set; }
    @AuraEnabled
    public Date postedDate { get; set; }
    @AuraEnabled
    public String description { get; set; }
    @AuraEnabled
    public String expectations { get; set; }
    @AuraEnabled
    public String categories { get; set; }
    @AuraEnabled
    public String eventStatus { get; set; }
    @AuraEnabled
    public String rejectionReason { get; set; }
    // 'By Alumni' when the event was hosted by an alumni (Constituent_Role__c set via the
    // portal Host-an-Event flow); otherwise the admin label ('By {Institution Alias}',
    // or 'By Admin' when no alias is configured) for events created internally by staff.
    @AuraEnabled
    public String createdBy { get; set; }
    // Latest end across all sessions, so an event with a session still to come
    // later today stays "upcoming" even after an earlier session has ended.
    @AuraEnabled
    public DateTime effectiveEndDateTime { get; set; }
    public EventWrapper(Ken_Event_Master__c event) {
      this(event, 'By Admin');
    }
    public EventWrapper(Ken_Event_Master__c event, String adminLabel) {
      this.id = event.Id;
      this.title = event.Name;
      this.imageUrl = event.Event_banner__c;
      this.eventType = (event.Start_Date__c == event.End_Date__c)
        ? 'One-day'
        : 'Multi-day';
      this.startDate = event.Start_Date__c;
      // An event owns a date but never a time — nothing has ever written a
      // time onto Ken_Event_Master__c. The real clock lives on the child
      // sessions, so the card's time span is the earliest session start to
      // the latest session end. Events with no sessions simply show no time.
      DateTime earliest = null;
      DateTime latest = null;
      if (event.Schedule_Sessions__r != null) {
        for (Ken_Schedule_Sessions__c sn : event.Schedule_Sessions__r) {
          if (
            sn.Start_DateTime__c != null &&
            (earliest == null ||
            sn.Start_DateTime__c < earliest)
          ) {
            earliest = sn.Start_DateTime__c;
          }
          if (
            sn.End_DateTime__c != null &&
            (latest == null ||
            sn.End_DateTime__c > latest)
          ) {
            latest = sn.End_DateTime__c;
          }
        }
      }
      this.startInstant = KenDateTimeUtil.formatInstant(earliest);
      this.endInstant = KenDateTimeUtil.formatInstant(latest);
      this.endDate = event.End_Date__c;
      this.eventStatus = event.Event_Status__c;
      this.featuredEvents = false;
      this.createdBy = (event.Constituent_Role__c != null)
        ? 'By Alumni'
        : (String.isNotBlank(adminLabel) ? adminLabel : 'By Admin');
      this.effectiveEndDateTime = resolveEffectiveEnd(event);
    }

    private DateTime resolveEffectiveEnd(Ken_Event_Master__c event) {
      DateTime latest = null;
      if (event.Schedule_Sessions__r != null) {
        for (Ken_Schedule_Sessions__c s : event.Schedule_Sessions__r) {
          // Same-day sessions are saved with a start but no end, so they
          // count until the end of the day they start on. The day is
          // derived from the start instant, never stored alongside it.
          // Mirrors KenLandingPageController.sessionEffectiveEnd so the
          // portal and the landing page never disagree about what is over.
          DateTime sessionEnd = s.End_DateTime__c != null
            ? s.End_DateTime__c
            : KenDateTimeUtil.dayAfter(
                KenDateTimeUtil.localDate(s.Start_DateTime__c)
              );
          if (sessionEnd != null && (latest == null || sessionEnd > latest)) {
            latest = sessionEnd;
          }
        }
      }
      // No sessions: the event's own last day decides, and the whole day
      // counts so it does not drop off the list at midnight on that day.
      return latest != null
        ? latest
        : KenDateTimeUtil.dayAfter(event.End_Date__c);
    }
  }

  public class EventDetailWrapper {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String image { get; set; }
    @AuraEnabled
    public String eventType { get; set; }
    @AuraEnabled
    public Date startDate { get; set; }
    @AuraEnabled
    public Date endDate { get; set; }
    @AuraEnabled
    public String participantsCount { get; set; }
    @AuraEnabled
    public Date postedDate { get; set; }
    @AuraEnabled
    public String description { get; set; }
    @AuraEnabled
    public String expectations { get; set; }
    @AuraEnabled
    public String categories;
    @AuraEnabled
    public String brochureUrl;
    @AuraEnabled
    public Boolean hasBrochure;
    @AuraEnabled
    public String eventStatus;
    @AuraEnabled
    public String targetKeywords;
    @AuraEnabled
    public String location { get; set; }
    @AuraEnabled
    public String language { get; set; }
    @AuraEnabled
    public Decimal eventFee { get; set; }
    @AuraEnabled
    public Boolean noFee { get; set; }
    @AuraEnabled
    public Boolean offerMeals { get; set; }
    @AuraEnabled
    public Boolean collectDietary { get; set; }
    @AuraEnabled
    public String dietaryPreferences { get; set; }
    @AuraEnabled
    public Decimal mealFee { get; set; }
    @AuraEnabled
    public Boolean makeMealsPaid { get; set; }
    @AuraEnabled
    public Boolean canBringGuests { get; set; }
    @AuraEnabled
    public Integer guestCount { get; set; }
    @AuraEnabled
    public String photosLink { get; set; }
    @AuraEnabled
    public String highlightsLink { get; set; }
    @AuraEnabled
    public String hostRoleId { get; set; }
    @AuraEnabled
    public String rejectionReason { get; set; }

    public EventDetailWrapper(Ken_Event_Master__c event) {
      this.id = event.Id;
      this.title = event.Name;
      this.image = event.Event_banner__c;
      this.eventType = (event.Start_Date__c == event.End_Date__c)
        ? 'One-day'
        : 'Multi-day';
      this.startDate = event.Start_Date__c;
      this.endDate = event.End_Date__c;
      this.postedDate = event.createddate.date();
      this.description = event.Description__c;
      this.expectations = event.What_to_Expect_From_Event__c;
      this.participantsCount = event.Max_Allowed_Participants__c != null
        ? event.Max_Allowed_Participants__c.toString()
        : '0';
      this.brochureUrl = event.Event_Broucher__c;
      this.hasBrochure =
        String.isNotBlank(event.Event_Broucher__c) &&
        event.Event_Broucher__c.trim().startsWith('http');
      this.eventStatus = event.Event_Status__c;
      this.targetKeywords = event.Target_Topics__c;
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
      this.guestCount = event.Guest_Count__c != null
        ? Integer.valueOf(event.Guest_Count__c)
        : 0;
      this.photosLink = event.Event_Photos_Link__c;
      this.highlightsLink = event.Event_Highlights_Link__c;
      this.hostRoleId = event.Constituent_Role__c;
      this.rejectionReason = event.Reason_For_Rejection__c;
    }
  }

  // Host adds/updates the post-event Photos and Highlights links shown on the Event Updates tab.
  @AuraEnabled
  public static void saveEventUpdateLinks(
    String eventId,
    String photosLink,
    String highlightsLink
  ) {
    try {
      if (String.isBlank(eventId)) {
        throw new AuraHandledException('Event id is required.');
      }
      Ken_Event_Master__c ev = new Ken_Event_Master__c(Id = eventId);
      ev.Event_Photos_Link__c = String.isBlank(photosLink) ? null : photosLink;
      ev.Event_Highlights_Link__c = String.isBlank(highlightsLink)
        ? null
        : highlightsLink;
      if (!Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
          throw new KenCrudException('Ken_Event_Master__c is not updateable by the current user.');
      }
      update ev;
    } catch (Exception e) {
      throw new AuraHandledException('Error saving links: ' + e.getMessage());
    }
  }

  // Count of attendees who opted meals, keyed by session date (yyyy-MM-dd) — host/approved view.
  @AuraEnabled(cacheable=true)
  public static Map<String, Integer> getMealOptedCounts(String eventId) {
    Map<String, Integer> counts = new Map<String, Integer>();
    if (String.isBlank(eventId))
      return counts;
    // Grouped by session rather than by day, then rolled up in Apex. Grouping
    // on the DateTime directly would bucket by exact instant, and DAY_ONLY()
    // would bucket by the UTC day — putting an evening IST session under the
    // previous date. Sessions per event are few, so the roll-up is cheap.
    Map<Id, Integer> countsBySession = new Map<Id, Integer>();
    for (AggregateResult ar : [
      SELECT Schedules_Sessions__c sid, COUNT(Id) cnt
      FROM Ken_Event_Booking__c
      WHERE
        Schedules_Sessions__r.Event_Reference__c = :eventId
        AND Type__c = 'Registered'
        AND Meals_Opted__c = TRUE
      WITH SECURITY_ENFORCED
      GROUP BY Schedules_Sessions__c
    ]) {
      Id sid = (Id) ar.get('sid');
      if (sid != null) {
        countsBySession.put(sid, (Integer) ar.get('cnt'));
      }
    }
    if (countsBySession.isEmpty())
      return counts;

    for (Ken_Schedule_Sessions__c s : [
      SELECT Id, Start_DateTime__c
      FROM Ken_Schedule_Sessions__c
      WHERE Id IN :countsBySession.keySet() AND Start_DateTime__c != NULL
    WITH SECURITY_ENFORCED
    ]) {
      Date d = KenDateTimeUtil.localDate(s.Start_DateTime__c);
      String key = Datetime.newInstance(d.year(), d.month(), d.day(), 0, 0, 0)
        .format('yyyy-MM-dd');
      Integer existing = counts.containsKey(key) ? counts.get(key) : 0;
      counts.put(key, existing + countsBySession.get(s.Id));
    }
    return counts;
  }

  public class ScheduleWrapper {
    // Raw UTC instants; components format them in the viewer's own
    // timezone. startTime/endTime below are bare Time values with no
    // zone attached and stay only until those readers migrate.
    @AuraEnabled
    public String startInstant;
    @AuraEnabled
    public String endInstant;
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date sessionDate;
    @AuraEnabled
    public Time startTime;
    @AuraEnabled
    public Time endTime;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public List<SpeakerWrapper> speakers;
    @AuraEnabled
    public String speakerNames;
    @AuraEnabled
    public String agenda;
    @AuraEnabled
    public Boolean isRegistered;
    @AuraEnabled
    public String meals;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String locationType;
    @AuraEnabled
    public String sessionLink;
    @AuraEnabled
    public Decimal price;
    @AuraEnabled
    public Boolean noFee;
  }

  public class SpeakerWrapper {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String image;
    @AuraEnabled
    public String description;
  }

  @AuraEnabled(cacheable=true)
  public static Map<String, String> getCurrentParticipantDetails() {
    try {
      Id constituentRoleId = KenConstituentRoleService.getActiveConstituentRoleId();
      if (constituentRoleId == null)
        throw new AuraHandledException('No constituent role');
      ConstituentRole role = [
        SELECT Id, PersonId, Email__c
        FROM ConstituentRole
        WHERE Id = :constituentRoleId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      Map<String, String> details = new Map<String, String>();
      details.put('email', role.Email__c != null ? role.Email__c : '');
      if (role.PersonId != null) {
        Account acc = [
          SELECT Id, Name, PersonMobilePhone
          FROM Account
          WHERE Id = :role.PersonId
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        details.put('name', acc.Name != null ? acc.Name : '');
        details.put(
          'phone',
          acc.PersonMobilePhone != null ? acc.PersonMobilePhone : ''
        );
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
      if (String.isBlank(eventId))
        throw new AuraHandledException('Event id required.');
      Ken_Event_Master__c ev = [
        SELECT Id, Event_Status__c
        FROM Ken_Event_Master__c
        WHERE Id = :eventId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!Schema.sObjectType.Ken_Event_Master__c.isDeletable()) {
          throw new KenCrudException('Ken_Event_Master__c is not deletable by the current user.');
      }
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
      if (String.isBlank(eventId))
        return result;

      Ken_Event_Master__c ev = null;
      Set<Id> preEventSurveyIds = new Set<Id>();
      List<Ken_Event_Master__c> events = [
        SELECT Survey__c, Start_Date__c, End_Date__c
        FROM Ken_Event_Master__c
        WHERE Id = :eventId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!events.isEmpty()) {
        ev = events[0];
        if (ev.Survey__c != null)
          preEventSurveyIds.add(ev.Survey__c);
      }

      List<Ken_Schedule_Sessions__c> sessionList = [
        SELECT Id, Name, Start_DateTime__c, Survey__c
        FROM Ken_Schedule_Sessions__c
        WHERE Event_Reference__c = :eventId
        WITH SECURITY_ENFORCED
        ORDER BY Start_DateTime__c ASC NULLS LAST
      ];

      Set<Id> sessionSurveyIds = new Set<Id>();
      for (Ken_Schedule_Sessions__c s : sessionList) {
        if (s.Survey__c != null)
          sessionSurveyIds.add(s.Survey__c);
      }

      Set<Id> allSurveyIds = new Set<Id>();
      allSurveyIds.addAll(preEventSurveyIds);
      allSurveyIds.addAll(sessionSurveyIds);

      Map<Id, Ken_Survey__c> surveyMap = new Map<Id, Ken_Survey__c>();
      if (!allSurveyIds.isEmpty()) {
        for (Ken_Survey__c s : [
          SELECT
            Id,
            Name,
            Start_Date__c,
            End_Date__c,
            Type__c,
            Assessment_Question_Set__c
          FROM Ken_Survey__c
          WHERE Id IN :allSurveyIds
        WITH SECURITY_ENFORCED
        ]) {
          surveyMap.put(s.Id, s);
        }
      }

      Set<Id> assessmentSurveyIds = new Set<Id>();
      Map<Id, Id> questionSetBySurvey = new Map<Id, Id>();
      for (Ken_Survey__c s : surveyMap.values()) {
        if (s.Assessment_Question_Set__c != null) {
          assessmentSurveyIds.add(s.Id);
          questionSetBySurvey.put(s.Id, s.Assessment_Question_Set__c);
        }
      }

      Map<Id, Integer> responseCounts = new Map<Id, Integer>();
      if (!assessmentSurveyIds.isEmpty()) {
        responseCounts.putAll(
          KenAssessmentSurveyService.submissionCountsBySurvey(
            assessmentSurveyIds
          )
        );
      }

      // Per-viewer completion. The card an attendee sees says Pending/Completed for
      // that person; the date-window status below drives the host's view only.
      Set<Id> respondedSurveyIds = new Set<Id>();
      Id respondentAccountId = currentRespondentAccountId();
      if (respondentAccountId != null && !assessmentSurveyIds.isEmpty()) {
        respondedSurveyIds.addAll(
          KenAssessmentSurveyService.surveysAnsweredBy(
            assessmentSurveyIds,
            respondentAccountId
          )
        );
      }

      Map<Id, Integer> qParamCounts = new Map<Id, Integer>();
      if (!questionSetBySurvey.isEmpty()) {
        qParamCounts.putAll(
          KenAssessmentSurveyService.questionCountsBySet(
            new Set<Id>(questionSetBySurvey.values())
          )
        );
      }

      DateTime now = DateTime.now();
      Boolean eventEnded =
        ev != null &&
        ev.End_Date__c != null &&
        DateTime.newInstance(ev.End_Date__c, Time.newInstance(23, 59, 59, 0)) <
        now;

      for (Id sid : preEventSurveyIds) {
        if (surveyMap.containsKey(sid)) {
          result.preEventSurveys.add(
            buildSurveyCard(
              surveyMap.get(sid),
              responseCounts,
              qParamCounts,
              now,
              eventEnded,
              respondedSurveyIds
            )
          );
        }
      }

      for (Ken_Schedule_Sessions__c sess : sessionList) {
        SessionFeedbackWrapper sf = new SessionFeedbackWrapper();
        sf.sessionId = sess.Id;
        sf.sessionName = sess.Name;
        Date sessDay = KenDateTimeUtil.localDate(sess.Start_DateTime__c);
        sf.sessionDate = sessDay == null ? null : String.valueOf(sessDay);
        sf.hasSurvey =
          sess.Survey__c != null && surveyMap.containsKey(sess.Survey__c);
        if (sf.hasSurvey) {
          Ken_Survey__c s = surveyMap.get(sess.Survey__c);
          sf.surveyId = s.Id;
          sf.surveyName = s.Name;
          sf.responseCount = responseCounts.containsKey(s.Id)
            ? responseCounts.get(s.Id)
            : 0;
          Id sfDefinitionId = s.Assessment_Question_Set__c;
          sf.hasQuestionnaire = sfDefinitionId != null;
          sf.questionCount = (sfDefinitionId != null &&
            qParamCounts.containsKey(sfDefinitionId))
            ? qParamCounts.get(sfDefinitionId)
            : 0;
          sf.respondedByMe = respondedSurveyIds.contains(s.Id);
          sf.surveyStartDate = s.Start_Date__c != null
            ? s.Start_Date__c.date()
            : null;
          sf.surveyEndDate = s.End_Date__c != null
            ? s.End_Date__c.date()
            : null;
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
          sf.respondedByMe = false;
          sf.surveyStartDate = null;
          sf.surveyEndDate = null;
          sf.status = 'No Form';
        }
        result.sessions.add(sf);
      }

      return result;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error fetching event updates: ' + e.getMessage()
      );
    }
  }

  /**
   * Account the survey layer stamps on a response (Respondent__c). Mirrors
   * KenModuleFeedbackController so "has this viewer responded" matches what the
   * form actually wrote when they submitted.
   */
  @TestVisible
  private static Id testRespondentAccountId;

  private static Id currentRespondentAccountId() {
    if (Test.isRunningTest() && testRespondentAccountId != null) {
      return testRespondentAccountId;
    }
    List<User> us = [
      SELECT AccountId, Contact.AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (us.isEmpty())
      return null;
    if (us[0].AccountId != null)
      return us[0].AccountId;
    return us[0].Contact != null ? us[0].Contact.AccountId : null;
  }

  private static SurveyCardWrapper buildSurveyCard(
    Ken_Survey__c s,
    Map<Id, Integer> responseCounts,
    Map<Id, Integer> qParamCounts,
    DateTime now,
    Boolean eventEnded,
    Set<Id> respondedSurveyIds
  ) {
    SurveyCardWrapper w = new SurveyCardWrapper();
    w.id = s.Id;
    w.name = s.Name;
    w.startDate = s.Start_Date__c != null ? s.Start_Date__c.date() : null;
    w.endDate = s.End_Date__c != null ? s.End_Date__c.date() : null;
    w.surveyType = s.Type__c;
    w.responseCount = responseCounts.containsKey(s.Id)
      ? responseCounts.get(s.Id)
      : 0;
    Id definitionId = s.Assessment_Question_Set__c;
    w.questionCount = (definitionId != null &&
      qParamCounts.containsKey(definitionId))
      ? qParamCounts.get(definitionId)
      : 0;
    w.hasQuestionnaire = definitionId != null;
    w.respondedByMe =
      respondedSurveyIds != null && respondedSurveyIds.contains(s.Id);
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
    @AuraEnabled
    public List<SurveyCardWrapper> preEventSurveys { get; set; }
    @AuraEnabled
    public List<SessionFeedbackWrapper> sessions { get; set; }
  }

  public class SessionFeedbackWrapper {
    @AuraEnabled
    public String sessionId { get; set; }
    @AuraEnabled
    public String sessionName { get; set; }
    @AuraEnabled
    public String sessionDate { get; set; }
    @AuraEnabled
    public String surveyId { get; set; }
    @AuraEnabled
    public String surveyName { get; set; }
    @AuraEnabled
    public Integer responseCount { get; set; }
    @AuraEnabled
    public Integer questionCount { get; set; }
    @AuraEnabled
    public Boolean hasQuestionnaire { get; set; }
    @AuraEnabled
    public Boolean hasSurvey { get; set; }
    @AuraEnabled
    public Boolean respondedByMe { get; set; }
    @AuraEnabled
    public Date surveyStartDate { get; set; }
    @AuraEnabled
    public Date surveyEndDate { get; set; }
    @AuraEnabled
    public String status { get; set; }
  }

  public class SurveyCardWrapper {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Date startDate;
    @AuraEnabled
    public Date endDate;
    @AuraEnabled
    public String surveyType;
    @AuraEnabled
    public Integer responseCount;
    @AuraEnabled
    public Integer questionCount;
    @AuraEnabled
    public Boolean hasQuestionnaire;
    @AuraEnabled
    public Boolean respondedByMe;
    @AuraEnabled
    public String status;
  }
}