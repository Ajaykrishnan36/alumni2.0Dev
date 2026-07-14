@IsTest
private class KenPortalEventControllerTest {
    private static final String RUN_AS_ALIAS = 'peusr';
    private static final String MAIN_EVENT_NAME = 'Portal Event Main';
    private static final String NO_SESSION_EVENT_NAME = 'Portal Event No Session';
    private static final String SESSION_ONE_NAME = 'Portal Session One';
    private static final String SESSION_TWO_NAME = 'Portal Session Two';

    @TestSetup
    static void setupData() {
        Id profileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;
        User runAsUser = new User(
            FirstName = 'Portal',
            LastName = 'EventRunner',
            Email = 'portal.event.runner@example.com',
            Username = 'portal.event.runner.' + DateTime.now().getTime() + '@example.com',
            Alias = RUN_AS_ALIAS,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
        insert runAsUser;

        RecordType personRt = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        Account personAccount = new Account(
            RecordTypeId = personRt.Id,
            LastName = 'Portal Event Person',
            PersonEmail = 'portal.event.person@example.com'
        );
        insert personAccount;

        ConstituentRole constituentRole = new ConstituentRole(
            PersonId = personAccount.Id,
            RoleType = 'Alumni',
            Registration_Status__c = 'Registered',
            Email__c = 'portal.event.person@example.com'
        );
        constituentRole.put('Status', 'Admitted');
        insert constituentRole;

        List<Ken_Event_Master__c> events = new List<Ken_Event_Master__c>{
            new Ken_Event_Master__c(
                Name = MAIN_EVENT_NAME,
                Start_Date__c = Date.today().addDays(1),
                End_Date__c = Date.today().addDays(1),
                Start_Time__c = Time.newInstance(10, 0, 0, 0),
                End_Time__c = Time.newInstance(12, 0, 0, 0),
                Event_Type__c = 'Workshop',
                Event_banner__c = 'https://example.com/banner-main.png',
                Location__c = 'Main Hall',
                Event_Status__c = 'Approved',
                Is_Active__c = true,
                Description__c = 'Primary event description',
                What_to_Expect_From_Event__c = 'Primary agenda',
                Max_Allowed_Participants__c = 100,
                Event_Broucher__c = 'https://example.com/brochure.pdf',
                Target_Keywords__c = 'alumni,events',
                Constituent_Role__c = constituentRole.Id
            ),
            new Ken_Event_Master__c(
                Name = 'Portal Event Pending',
                Start_Date__c = Date.today().addDays(2),
                End_Date__c = Date.today().addDays(2),
                Event_Type__c = 'Webinar',
                Event_Status__c = 'In Review',
                Is_Active__c = true,
                Constituent_Role__c = constituentRole.Id
            ),
            new Ken_Event_Master__c(
                Name = NO_SESSION_EVENT_NAME,
                Start_Date__c = Date.today().addDays(3),
                End_Date__c = Date.today().addDays(3),
                Event_Type__c = 'Conference',
                Event_Status__c = 'Approved',
                Is_Active__c = true,
                Constituent_Role__c = constituentRole.Id
            ),
            new Ken_Event_Master__c(
                Name = 'Portal Event Inactive',
                Start_Date__c = Date.today().addDays(4),
                End_Date__c = Date.today().addDays(4),
                Event_Type__c = 'Workshop',
                Event_Status__c = 'Approved',
                Is_Active__c = false,
                Constituent_Role__c = constituentRole.Id
            )
        };
        insert events;

        Id mainEventId = [SELECT Id FROM Ken_Event_Master__c WHERE Name = :MAIN_EVENT_NAME LIMIT 1].Id;

        List<Ken_Schedule_Sessions__c> sessions = new List<Ken_Schedule_Sessions__c>{
            new Ken_Schedule_Sessions__c(
                Name = SESSION_ONE_NAME,
                Event_Reference__c = mainEventId,
                Start_Date__c = Date.today().addDays(1),
                End_Date__c = Date.today().addDays(1),
                Start_Time__c = Time.newInstance(10, 0, 0, 0),
                End_Time__c = Time.newInstance(11, 0, 0, 0),
                Location__c = 'Room A',
                Location_Type__c = 'Offline',
                What_to_Expect_From_Event__c = 'Session one agenda',
                Session_Link__c = 'https://example.com/session-one'
            ),
            new Ken_Schedule_Sessions__c(
                Name = SESSION_TWO_NAME,
                Event_Reference__c = mainEventId,
                Start_Date__c = Date.today().addDays(1),
                End_Date__c = Date.today().addDays(1),
                Start_Time__c = Time.newInstance(11, 30, 0, 0),
                End_Time__c = Time.newInstance(12, 30, 0, 0),
                Location__c = 'Room B',
                Location_Type__c = 'Online',
                What_to_Expect_From_Event__c = 'Session two agenda',
                Session_Link__c = 'https://example.com/session-two'
            )
        };
        insert sessions;

        Account speakerAccount = [SELECT Id FROM Account WHERE Id = :personAccount.Id LIMIT 1];
        Id sessionOneId = [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Name = :SESSION_ONE_NAME LIMIT 1].Id;

        insert new Ken_Events_Sessions_Enrollment__c(
            Schedule_Sessions__c = sessionOneId,
            Person_Account__c = speakerAccount.Id,
            Speaker_Name__c = 'Speaker One',
            Speaker_Image__c = 'https://example.com/speaker.png',
            Description__c = 'Speaker biography'
        );

        insert new Ken_Event_Booking__c(
            Constituent_Role__c = constituentRole.Id,
            Schedules_Sessions__c = sessionOneId,
            Type__c = 'Registered'
        );
    }

    @IsTest
    static void getAllEventsReturnsOnlyApprovedActiveEvents() {
        User runAsUser = getRunAsUser();
        System.runAs(runAsUser) {
            Test.startTest();
            List<KenPortalEventController.EventWrapper> events = KenPortalEventController.getAllEvents();
            Test.stopTest();

            System.assert(events.size() > 0, 'At least one approved active event should be returned.');
            List<String> titles = new List<String>();
            for (KenPortalEventController.EventWrapper wrapper : events) {
                titles.add(wrapper.title);
                // The main event is hosted by an alumni (Constituent_Role__c set in @TestSetup).
                if (wrapper.title == MAIN_EVENT_NAME) {
                    System.assertEquals('By Alumni', wrapper.createdBy,
                        'Event with a Constituent Role should be classified as created By Alumni.');
                }
            }
            System.assert(titles.contains(MAIN_EVENT_NAME), 'Main approved active event should be included.');
            System.assert(!titles.contains('Portal Event Inactive'), 'Inactive event should not be included.');
        }
    }

    @IsTest
    static void getAllEventsUsesInstitutionAliasForAdminEvents() {
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        if (orgParam == null || orgParam.Id == null) {
            orgParam = new Alumni_Org_Parameters__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        orgParam.Institution_Alias__c = 'KVI';
        upsert orgParam;

        Ken_Event_Master__c adminEvent = new Ken_Event_Master__c(
            Name = 'Portal Admin Event',
            Start_Date__c = Date.today().addDays(5),
            End_Date__c = Date.today().addDays(5),
            Event_Type__c = 'Workshop',
            Event_Status__c = 'Approved',
            Is_Active__c = true
        );
        insert adminEvent;

        User runAsUser = getRunAsUser();
        System.runAs(runAsUser) {
            Test.startTest();
            List<KenPortalEventController.EventWrapper> events = KenPortalEventController.getAllEvents();
            Test.stopTest();

            Boolean found = false;
            for (KenPortalEventController.EventWrapper wrapper : events) {
                if (wrapper.title == 'Portal Admin Event') {
                    found = true;
                    System.assertEquals('By KVI', wrapper.createdBy,
                        'Admin-created event should be badged with the institution alias.');
                }
            }
            System.assert(found, 'Admin-created event should be returned by getAllEvents.');
        }
    }

    @IsTest
    static void getAllEventsFallsBackToByAdminWhenAliasBlank() {
        Alumni_Org_Parameters__c orgParam = Alumni_Org_Parameters__c.getOrgDefaults();
        if (orgParam == null || orgParam.Id == null) {
            orgParam = new Alumni_Org_Parameters__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        orgParam.Institution_Alias__c = '';
        upsert orgParam;

        Ken_Event_Master__c adminEvent = new Ken_Event_Master__c(
            Name = 'Portal Admin Event No Alias',
            Start_Date__c = Date.today().addDays(6),
            End_Date__c = Date.today().addDays(6),
            Event_Type__c = 'Workshop',
            Event_Status__c = 'Approved',
            Is_Active__c = true
        );
        insert adminEvent;

        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<KenPortalEventController.EventWrapper> events = KenPortalEventController.getAllEvents();
            Test.stopTest();

            Boolean found = false;
            for (KenPortalEventController.EventWrapper wrapper : events) {
                if (wrapper.title == 'Portal Admin Event No Alias') {
                    found = true;
                    System.assertEquals('By Admin', wrapper.createdBy,
                        'Admin event should fall back to "By Admin" when no alias is configured.');
                }
            }
            System.assert(found, 'Admin-created event should be returned by getAllEvents.');
        }
    }

    @IsTest
    static void getHostedEventsReturnsMatchingRoleEvents() {
        User runAsUser = getRunAsUser();
        Id roleId = getConstituentRoleId();

        System.runAs(runAsUser) {
            Test.startTest();
            List<Ken_Event_Master__c> hosted = KenPortalEventController.getHostedEvents(roleId);
            Test.stopTest();

            System.assert(hosted.size() >= 2, 'Hosted events should include role-owned statuses from approval set.');
            // Verify new fields are returned in the query
            Ken_Event_Master__c mainEvent = null;
            for (Ken_Event_Master__c ev : hosted) {
                if (ev.Name == MAIN_EVENT_NAME) { mainEvent = ev; break; }
            }
            System.assertNotEquals(null, mainEvent, 'Main event must be in hosted list.');
            System.assertNotEquals(null, mainEvent.CreatedDate, 'CreatedDate must be populated in hosted events query.');
        }
    }

    @IsTest
    static void getHostedEventsThrowsWhenRoleMissing() {
        User runAsUser = getRunAsUser();

        System.runAs(runAsUser) {
            Test.startTest();
            try {
                KenPortalEventController.getHostedEvents(null);
                System.assert(false, 'Expected AuraHandledException for null constituent role.');
            } catch (AuraHandledException ex) {
                System.assertEquals(
                    'Script-thrown exception',
                    ex.getMessage(),
                    'Aura exception should be thrown for missing role id.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void getEventSessionsReturnsSessionsForEvent() {
        User runAsUser = getRunAsUser();
        Id eventId = getMainEventId();

        System.runAs(runAsUser) {
            Test.startTest();
            List<Ken_Schedule_Sessions__c> sessions = KenPortalEventController.getEventSessions(eventId);
            Test.stopTest();

            System.assertEquals(2, sessions.size(), 'Main event should return both seeded sessions.');
        }
    }

    @IsTest
    static void getEventSessionsThrowsWhenNoSessionsExist() {
        User runAsUser = getRunAsUser();
        Id eventId = getNoSessionEventId();

        System.runAs(runAsUser) {
            Test.startTest();
            try {
                KenPortalEventController.getEventSessions(eventId);
                System.assert(false, 'Expected AuraHandledException for an event without sessions.');
            } catch (AuraHandledException ex) {
                System.assertEquals('Script-thrown exception', ex.getMessage(), 'Aura exception should be thrown for empty sessions.');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void getRegisteredSessionsReturnsRegisteredOnly() {
        User runAsUser = getRunAsUser();
        Id eventId = getMainEventId();
        Id roleId = getConstituentRoleId();
        Id expectedSessionId = getSessionIdByName(SESSION_ONE_NAME);

        System.runAs(runAsUser) {
            Test.startTest();
            List<Ken_Schedule_Sessions__c> registered = KenPortalEventController.getRegisteredSessions(eventId, roleId);
            Test.stopTest();

            System.assertEquals(1, registered.size(), 'Exactly one session should be marked registered from setup data.');
            System.assertEquals(expectedSessionId, registered[0].Id, 'Registered session should match booking association.');
        }
    }

    @IsTest
    static void getRegisteredSessionsThrowsWhenRoleMissing() {
        User runAsUser = getRunAsUser();
        Id eventId = getMainEventId();

        System.runAs(runAsUser) {
            Test.startTest();
            try {
                KenPortalEventController.getRegisteredSessions(eventId, null);
                System.assert(false, 'Expected AuraHandledException when role id is null.');
            } catch (AuraHandledException ex) {
                System.assertEquals(
                    'Script-thrown exception',
                    ex.getMessage(),
                    'Aura exception should be thrown for missing role id.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void getEventDetailsReturnsWrapperForValidRecord() {
        User runAsUser = getRunAsUser();
        Id eventId = getMainEventId();

        System.runAs(runAsUser) {
            Test.startTest();
            KenPortalEventController.EventDetailWrapper details = KenPortalEventController.getEventDetails(String.valueOf(eventId));
            Test.stopTest();

            System.assertEquals(MAIN_EVENT_NAME, details.title, 'Event detail wrapper should map the event title.');
            System.assertEquals('Workshop', details.categories, 'Event category should map from event type.');
        }
    }

    @IsTest
    static void getEventDetailsThrowsWhenRecordIdBlank() {
        User runAsUser = getRunAsUser();

        System.runAs(runAsUser) {
            Test.startTest();
            try {
                KenPortalEventController.getEventDetails('');
                System.assert(false, 'Expected AuraHandledException when record id is blank.');
            } catch (AuraHandledException ex) {
                System.assertEquals('Script-thrown exception', ex.getMessage(), 'Blank record id should throw Aura exception.');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void getEventSchedulesBuildsSpeakerAndRegistrationFlags() {
        User runAsUser = getRunAsUser();
        Id eventId = getMainEventId();
        Id roleId = getConstituentRoleId();
        Id registeredSessionId = getSessionIdByName(SESSION_ONE_NAME);

        System.runAs(runAsUser) {
            Test.startTest();
            List<KenPortalEventController.ScheduleWrapper> schedules =
                KenPortalEventController.getEventSchedules(String.valueOf(eventId), roleId);
            Test.stopTest();

            System.assertEquals(2, schedules.size(), 'Both sessions should be returned in schedule wrapper list.');
            Boolean foundRegistered = false;
            for (KenPortalEventController.ScheduleWrapper schedule : schedules) {
                if (schedule.id == String.valueOf(registeredSessionId)) {
                    foundRegistered = true;
                    System.assertEquals(true, schedule.isRegistered, 'Booked session should be marked as registered.');
                    System.assert(
                        schedule.speakerNames.contains('Speaker One'),
                        'Speaker names should be joined into a readable string.'
                    );
                }
            }
            System.assert(foundRegistered, 'Registered schedule entry should be discoverable in result list.');
        }
    }

    @IsTest
    static void saveAndCancelRegistrationsUpdateBookingState() {
        User runAsUser = getRunAsUser();
        Id roleId = getConstituentRoleId();
        Id sessionTwoId = getSessionIdByName(SESSION_TWO_NAME);

        System.runAs(runAsUser) {
            Test.startTest();
            String saveMsg = KenPortalEventController.saveRegistrations(new List<Id>{ sessionTwoId }, roleId);
            Test.stopTest();
            System.assertEquals('Successfully registered!', saveMsg, 'Registration should return success confirmation.');

            Ken_Event_Booking__c booking = [
                SELECT Id, Type__c
                FROM Ken_Event_Booking__c
                WHERE Constituent_Role__c = :roleId
                AND Schedules_Sessions__c = :sessionTwoId
                LIMIT 1
            ];
            System.assertEquals('Registered', booking.Type__c, 'Saved registration should persist as Registered.');

            // Push the event well outside the 72-hour cancellation window so the cancel is allowed.
            Id mainEventId = [SELECT Id FROM Ken_Event_Master__c WHERE Name = :MAIN_EVENT_NAME LIMIT 1].Id;
            update new Ken_Event_Master__c(Id = mainEventId, Start_Date__c = Date.today().addDays(10), End_Date__c = Date.today().addDays(10));

            String cancelMsg = KenPortalEventController.cancelRegistrations(new List<Id>{ sessionTwoId }, roleId);
            System.assert(
                cancelMsg.contains('Successfully cancelled'),
                'Cancellation should return a success message with count.'
            );

            booking = [SELECT Type__c FROM Ken_Event_Booking__c WHERE Id = :booking.Id LIMIT 1];
            System.assertEquals('Cancelled', booking.Type__c, 'Cancellation should convert booking type to Cancelled.');
        }
    }

    @IsTest
    static void cancelRegistrationsThrowsWhenNoActiveRecords() {
        User runAsUser = getRunAsUser();
        Id roleId = getConstituentRoleId();
        Id sessionTwoId = getSessionIdByName(SESSION_TWO_NAME);

        // Push the event outside the 72-hour cancellation window so we exercise the
        // "no active registrations" path rather than the cancellation-window guard.
        Id mainEventId = [SELECT Id FROM Ken_Event_Master__c WHERE Name = :MAIN_EVENT_NAME LIMIT 1].Id;
        update new Ken_Event_Master__c(Id = mainEventId, Start_Date__c = Date.today().addDays(10), End_Date__c = Date.today().addDays(10));

        System.runAs(runAsUser) {
            Test.startTest();
            try {
                KenPortalEventController.cancelRegistrations(new List<Id>{ sessionTwoId }, roleId);
                System.assert(false, 'Expected AuraHandledException when no active registration exists.');
            } catch (AuraHandledException ex) {
                System.assertEquals(
                    'Script-thrown exception',
                    ex.getMessage(),
                    'Aura exception should be thrown when there are no active registrations.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void cancelRegistrationsBlockedWithin72Hours() {
        User runAsUser = getRunAsUser();
        Id roleId = getConstituentRoleId();
        // SESSION_ONE belongs to MAIN_EVENT, which starts tomorrow (well inside the 72-hour window)
        // and already has a 'Registered' booking from @TestSetup.
        Id sessionOneId = getSessionIdByName(SESSION_ONE_NAME);

        System.runAs(runAsUser) {
            Test.startTest();
            Boolean blocked = false;
            try {
                KenPortalEventController.cancelRegistrations(new List<Id>{ sessionOneId }, roleId);
            } catch (AuraHandledException ex) {
                blocked = true;
            }
            Test.stopTest();

            System.assert(blocked, 'Cancellation within 72 hours of the event start should be blocked.');

            Ken_Event_Booking__c booking = [
                SELECT Type__c FROM Ken_Event_Booking__c
                WHERE Constituent_Role__c = :roleId AND Schedules_Sessions__c = :sessionOneId
                LIMIT 1
            ];
            System.assertEquals('Registered', booking.Type__c, 'Booking should remain Registered when cancellation is blocked.');
        }
    }

    @IsTest
    static void getContactRegisteredSessionsReturnsCurrentRoleBookings() {
        User runAsUser = getRunAsUser();
        Id roleId = getConstituentRoleId();

        System.runAs(runAsUser) {
            Test.startTest();
            List<KenPortalEventController.RegisteredEventWrapper> sessions =
                KenPortalEventController.getContactRegisteredSessions(roleId);
            Test.stopTest();

            System.assertEquals(1, sessions.size(), 'Only seeded registered session should be returned initially.');
            KenPortalEventController.RegisteredEventWrapper w = sessions[0];
            System.assertEquals(SESSION_ONE_NAME, w.name, 'Returned wrapper name should match setup registration.');
            System.assertEquals(MAIN_EVENT_NAME, w.eventName, 'Wrapper should expose parent event name.');
            System.assertEquals('Registered', w.bookingType, 'Booking type should be Registered for the seeded booking.');
            System.assertEquals(1, w.participantsCount, 'Participants count should reflect the single seeded registration.');
            System.assertEquals(true, w.isFree, 'Session without fee should be flagged as free.');
            System.assertNotEquals(null, w.bookingDate, 'Booking date should be populated from the booking record.');
            System.assertEquals(false, w.feedbackSubmitted == true, 'Without prior feedback responses the wrapper should report no submission.');
        }
    }

    @IsTest
    static void getContactRegisteredSessionsThrowsWhenRoleMissing() {
        User runAsUser = getRunAsUser();

        System.runAs(runAsUser) {
            Test.startTest();
            try {
                KenPortalEventController.getContactRegisteredSessions(null);
                System.assert(false, 'Expected AuraHandledException when role id is null.');
            } catch (AuraHandledException ex) {
                System.assertEquals(
                    'Script-thrown exception',
                    ex.getMessage(),
                    'Aura exception should be thrown for missing role id.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void saveRegistrationsThrowsWhenNoSessionSelected() {
        User runAsUser = getRunAsUser();
        Id roleId = getConstituentRoleId();

        System.runAs(runAsUser) {
            Test.startTest();
            try {
                KenPortalEventController.saveRegistrations(new List<Id>(), roleId);
                System.assert(false, 'Expected AuraHandledException when no sessions are provided.');
            } catch (AuraHandledException ex) {
                System.assertEquals(
                    'Script-thrown exception',
                    ex.getMessage(),
                    'Aura exception should be thrown when no sessions are selected.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void getEventSchedulesReturnsWithoutRole() {
        User runAsUser = getRunAsUser();
        Id eventId = getMainEventId();

        System.runAs(runAsUser) {
            Test.startTest();
            // A null constituent role is allowed: schedules are returned without the
            // per-user "registered" flag rather than throwing a masked script exception.
            List<KenPortalEventController.ScheduleWrapper> schedules =
                KenPortalEventController.getEventSchedules(String.valueOf(eventId), null);
            System.assertNotEquals(null, schedules, 'Schedules should be returned even without a role id.');
            Test.stopTest();
        }
    }

    @IsTest
    static void testDeleteHostedEvent() {
        User u = getRunAsUser();
        System.runAs(u) {
            Id eventId = getMainEventId();
            Test.startTest();
            KenPortalEventController.deleteHostedEvent(eventId);
            Test.stopTest();
            List<Ken_Event_Master__c> remaining = [SELECT Id FROM Ken_Event_Master__c WHERE Id = :eventId];
            System.assertEquals(0, remaining.size(), 'Event should be deleted.');
        }
    }

    @IsTest
    static void testGetEventSurveysForUpdates() {
        User u = getRunAsUser();
        System.runAs(u) {
            Id eventId = getMainEventId();
            Test.startTest();
            KenPortalEventController.EventUpdatesWrapper result =
                KenPortalEventController.getEventUpdatesData(eventId);
            Test.stopTest();
            System.assertNotEquals(null, result, 'Should return event updates wrapper.');
            System.assertNotEquals(null, result.preEventSurveys, 'Should return a list (empty if no surveys).');
        }
    }

    @IsTest
    static void saveEventRegistrationsCoversAllParticipantTypes() {
        Id roleId = getConstituentRoleId();
        Id s1 = getSessionIdByName(SESSION_ONE_NAME);
        Id s2 = getSessionIdByName(SESSION_TWO_NAME);

        String payload = JSON.serialize(new Map<String, Object>{
            'sessionIds' => new List<Id>{ s1, s2 },
            'participants' => new List<Object>{
                new Map<String, Object>{ 'type' => 'Myself', 'meals' => true, 'dietaryPref' => 'Vegetarian' },
                new Map<String, Object>{ 'type' => 'Guest', 'name' => 'Guest A', 'email' => 'guest.a@example.com', 'phone' => '9990001111' },
                new Map<String, Object>{ 'type' => 'Group', 'name' => 'Alumni Group', 'memberCount' => 4 }
            }
        });

        System.runAs(getRunAsUser()) {
            Test.startTest();
            String result = KenPortalEventController.saveEventRegistrations(payload, roleId);
            Test.stopTest();
            System.assertEquals('Successfully registered!', result, 'Registration should succeed');
        }
        Integer registered = [
            SELECT COUNT() FROM Ken_Event_Booking__c
            WHERE Constituent_Role__c = :roleId AND Type__c = 'Registered'
        ];
        System.assert(registered >= 6, 'Expected >=6 registered bookings (3 participants x 2 sessions), got ' + registered);
    }

    @IsTest
    static void saveEventRegistrationsValidationErrors() {
        Id roleId = getConstituentRoleId();
        System.runAs(getRunAsUser()) {
            Integer thrown = 0;
            try { KenPortalEventController.saveEventRegistrations('', roleId); } catch (AuraHandledException e) { thrown++; }
            try { KenPortalEventController.saveEventRegistrations('{"sessionIds":[],"participants":[]}', null); } catch (AuraHandledException e) { thrown++; }
            try { KenPortalEventController.saveEventRegistrations('{"sessionIds":[],"participants":[]}', roleId); } catch (AuraHandledException e) { thrown++; }
            System.assert(thrown >= 3, 'Validation branches should throw; got ' + thrown);
        }
    }

    @IsTest
    static void getRegistrationSummaryReturnsParticipantsAndSessions() {
        Id roleId = getConstituentRoleId();
        Id eventId = getMainEventId();
        System.runAs(getRunAsUser()) {
            Test.startTest();
            KenPortalEventController.RegistrationSummaryWrapper summary =
                KenPortalEventController.getRegistrationSummary(eventId, roleId);
            Test.stopTest();
            System.assertNotEquals(null, summary, 'Summary should not be null');
            System.assertEquals(eventId, summary.eventId, 'Summary should be for the requested event');
            System.assertNotEquals(null, summary.participants, 'Participants list initialised');
            System.assertNotEquals(null, summary.sessions, 'Sessions list initialised');
        }
    }

    @IsTest
    static void getRegistrationSummaryValidation() {
        System.runAs(getRunAsUser()) {
            Integer thrown = 0;
            try { KenPortalEventController.getRegistrationSummary('', getConstituentRoleId()); } catch (AuraHandledException e) { thrown++; }
            try { KenPortalEventController.getRegistrationSummary(getMainEventId(), null); } catch (AuraHandledException e) { thrown++; }
            System.assertEquals(2, thrown, 'Both validation branches should throw');
        }
    }

    @IsTest
    static void getEventParticipantsReturnsRegistrants() {
        Id eventId = getMainEventId();
        System.runAs(getRunAsUser()) {
            Test.startTest();
            List<KenPortalEventController.EventParticipant> parts =
                KenPortalEventController.getEventParticipants(eventId);
            Test.stopTest();
            System.assertNotEquals(null, parts, 'Participants list should not be null');
        }
        Boolean threw = false;
        try { KenPortalEventController.getEventParticipants(''); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Blank event id should throw');
    }

    private static User getRunAsUser() {
        return [SELECT Id FROM User WHERE Alias = :RUN_AS_ALIAS LIMIT 1];
    }

    private static Id getConstituentRoleId() {
        return [SELECT Id FROM ConstituentRole LIMIT 1].Id;
    }

    private static Id getMainEventId() {
        return [SELECT Id FROM Ken_Event_Master__c WHERE Name = :MAIN_EVENT_NAME LIMIT 1].Id;
    }

    private static Id getNoSessionEventId() {
        return [SELECT Id FROM Ken_Event_Master__c WHERE Name = :NO_SESSION_EVENT_NAME LIMIT 1].Id;
    }

    private static Id getSessionIdByName(String nameValue) {
        return [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Name = :nameValue LIMIT 1].Id;
    }

    @IsTest
    static void getEventSchedulesHidesLinkFromUnregisteredSessions() {
        User runAsUser = getRunAsUser();
        Id eventId = getMainEventId();
        Id roleId = getConstituentRoleId();
        Id registeredSessionId = getSessionIdByName(SESSION_ONE_NAME);

        // Give every session a meeting link so the gating is observable.
        List<Ken_Schedule_Sessions__c> sessions = [
            SELECT Id FROM Ken_Schedule_Sessions__c WHERE Event_Reference__c = :eventId
        ];
        for (Ken_Schedule_Sessions__c s : sessions) {
            s.Session_Link__c = 'https://meet.example.com/x';
        }
        update sessions;

        System.runAs(runAsUser) {
            Test.startTest();
            List<KenPortalEventController.ScheduleWrapper> schedules =
                KenPortalEventController.getEventSchedules(String.valueOf(eventId), roleId);
            Test.stopTest();

            for (KenPortalEventController.ScheduleWrapper schedule : schedules) {
                if (schedule.id == String.valueOf(registeredSessionId)) {
                    System.assertEquals('https://meet.example.com/x', schedule.sessionLink,
                        'Registered session keeps its meeting link.');
                } else {
                    System.assertEquals(null, schedule.sessionLink,
                        'Unregistered sessions must not expose the meeting link.');
                }
            }
        }
    }
}