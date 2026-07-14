@IsTest
private class KenMentorshipControllerTest {
    private static final String CONNECTION_RECORD_TYPE = 'Connection_Request';
    private static final String CALL_RECORD_TYPE = 'Call_Request';

    @TestSetup
    static void setupData() {
        Account mentee = new Account(Name = 'Generic Test Mentee');
        Account mentorAccepted = new Account(Name = 'Generic Test Mentor Accepted');
        insert new List<Account>{ mentee, mentorAccepted };

        Ken_Network_Connection__c networkConnection = new Ken_Network_Connection__c(
            Initiator__c = mentee.Id,
            Recipient__c = mentorAccepted.Id,
            Status__c    = 'Accepted'
        );
        insert networkConnection;

        Id connectionRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c'
              AND DeveloperName = :CONNECTION_RECORD_TYPE
            LIMIT 1
        ].Id;

        Id callRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c'
              AND DeveloperName = :CALL_RECORD_TYPE
            LIMIT 1
        ].Id;

        insert new Ken_Mentorship__c(
            RecordTypeId          = connectionRecordTypeId,
            Mentor__c             = mentorAccepted.Id,
            Mentee__c             = mentee.Id,
            Mentorship_Status__c  = 'Accepted',
            Network_Connection__c = networkConnection.Id
        );

        insert new Ken_Mentorship__c(
            RecordTypeId           = callRecordTypeId,
            Mentor__c              = mentorAccepted.Id,
            Mentee__c              = mentee.Id,
            MeetingRequestedBy__c  = mentee.Id,
            Meeting_Title__c       = 'Generic Existing Scheduled Call',
            Meet_Date__c           = Date.today().addDays(1),
            Meet_Start_Time__c     = Time.newInstance(10, 0, 0, 0),
            Meet_End_Time__c       = Time.newInstance(11, 0, 0, 0),
            Meeting_Mode__c        = 'Online',
            Call_Request_Status__c = 'Requested',
            Network_Connection__c  = networkConnection.Id
        );

        insert new Task(
            Subject = 'Generic Existing Task',
            Status = 'Not Started',
            Priority = 'Low',
            Description = 'Generic task description',
            ActivityDate = Date.today().addDays(5),
            Assign_To__c = 'Mentor',
            Mentor__c = mentorAccepted.Id,
            Mentee__c = mentee.Id
        );
    }

    @IsTest
    static void testGetMethodsReturnCollections() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];
        Account mentorAccepted = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentor Accepted'
            LIMIT 1
        ];

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        List<KenMentorshipController.MentorshipConnectionRow> connections =
            KenMentorshipController.getMentorshipConnections();
        List<KenMentorshipController.MentorOption> mentors =
            KenMentorshipController.getAcceptedMentorsForCurrentMentee();
        KenMentorshipController.testCurrentAccountId = mentorAccepted.Id;
        List<KenMentorshipController.MentorOption> mentees =
            KenMentorshipController.getAcceptedMenteesForCurrentMentor();
        List<KenMentorshipController.ScheduleEventRow> mentorCalls =
            KenMentorshipController.getScheduledCallsForCurrentMentee();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        List<KenMentorshipController.ScheduleEventRow> calls =
            KenMentorshipController.getScheduledCallsForCurrentMentee();
        Test.stopTest();

        System.assertEquals(1, connections.size(), 'Connections should include only connection request rows.');
        System.assertEquals(
            CONNECTION_RECORD_TYPE,
            connections[0].recordType,
            'Connections response should exclude call request rows.'
        );
        System.assert(mentors.size() > 0, 'Mentor options response should include accepted mentor.');
        System.assert(mentees.size() > 0, 'Mentee options response should include accepted mentee.');
        System.assert(mentorCalls.size() > 0, 'Mentor-side scheduled calls should include incoming requests.');
        System.assertEquals(true, mentorCalls[0].canRespond, 'Mentor should be able to respond to requested calls.');
        System.assert(calls.size() > 0, 'Scheduled calls response should include records.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallThrowsWhenContextMissing() {
        KenMentorshipController.ScheduleCallRequest request = new KenMentorshipController.ScheduleCallRequest();
        request.mentorId = '001000000000001AAA';
        request.title = 'Controller Wrapper Test';
        request.meetingDate = String.valueOf(Date.today().addDays(1));
        request.startTime = '10:00';
        request.endTime = '10:30';
        request.meetingType = 'Online';
        request.meetLink = 'https://example.com';

        Boolean thrown = false;
        Test.startTest();
        try {
            KenMentorshipController.scheduleCallForCurrentMentee(request);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(String.isNotBlank(ex.getMessage()), 'Expected a handled exception message.');
        }
        Test.stopTest();

        System.assert(thrown, 'Expected schedule call to fail without a current account context.');
    }

    @IsTest
    static void testScheduleCallThrowsForPastDate() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];
        Account mentor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentor Accepted'
            LIMIT 1
        ];

        KenMentorshipController.ScheduleCallRequest request = new KenMentorshipController.ScheduleCallRequest();
        request.mentorId = mentor.Id;
        request.meetingDate = String.valueOf(Date.today().addDays(-1));
        request.startTime = '10:00';
        request.endTime = '10:30';
        request.meetingType = 'Online';
        request.meetLink = 'https://example.com';

        Boolean thrown = false;
        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        try {
            KenMentorshipController.scheduleCallForCurrentMentee(request);
        } catch (AuraHandledException ex) {
            thrown = true;
            System.assert(String.isNotBlank(ex.getMessage()), 'Expected a handled exception message.');
        }
        Test.stopTest();

        System.assert(thrown, 'Expected past date validation exception.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallUsesSingleAcceptedMentorFallback() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];

        KenMentorshipController.ScheduleCallRequest request = new KenMentorshipController.ScheduleCallRequest();
        request.title = 'Fallback Mentor Request';
        request.meetingDate = String.valueOf(Date.today().addDays(2));
        request.startTime = '10:00';
        request.endTime = '10:30';
        request.meetingType = 'Online';
        request.meetLink = 'https://example.com/fallback';

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        Id recordId = KenMentorshipController.scheduleCallForCurrentMentee(request);
        Test.stopTest();

        System.assertNotEquals(null, recordId, 'Expected call request record id.');
        Ken_Mentorship__c insertedCall = [
            SELECT Id, Mentor__c, Mentee__c, RecordType.DeveloperName
            FROM Ken_Mentorship__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        System.assertEquals(CALL_RECORD_TYPE, insertedCall.RecordType.DeveloperName);
        System.assertEquals(mentee.Id, insertedCall.Mentee__c);
        System.assertNotEquals(null, insertedCall.Mentor__c, 'Mentor should be resolved from accepted connection.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallAcceptsDateTimeFormattedMeetingDate() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];
        Account mentor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentor Accepted'
            LIMIT 1
        ];

        Date targetDate = Date.today().addDays(3);
        KenMentorshipController.ScheduleCallRequest request = new KenMentorshipController.ScheduleCallRequest();
        request.mentorId = mentor.Id;
        request.meetingDate = String.valueOf(targetDate) + 'T00:00:00.000Z';
        request.startTime = '09:30';
        request.endTime = '10:00';
        request.meetingType = 'Online';
        request.meetLink = 'https://example.com/date-time-format';

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        Id recordId = KenMentorshipController.scheduleCallForCurrentMentee(request);
        Test.stopTest();

        Ken_Mentorship__c insertedCall = [
            SELECT Id, Meet_Date__c
            FROM Ken_Mentorship__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        System.assertEquals(targetDate, insertedCall.Meet_Date__c, 'Meeting date should parse from datetime format.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallAllowsTodayTimeValue() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];
        Account mentor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentor Accepted'
            LIMIT 1
        ];

        KenMentorshipController.ScheduleCallRequest request = new KenMentorshipController.ScheduleCallRequest();
        request.mentorId = mentor.Id;
        request.meetingDate = String.valueOf(Date.today());
        request.startTime = '00:00';
        request.endTime = '00:30';
        request.meetingType = 'Online';
        request.meetLink = 'https://example.com/today-past-time';

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        Id recordId = KenMentorshipController.scheduleCallForCurrentMentee(request);
        Test.stopTest();

        System.assertNotEquals(null, recordId, 'Expected call request to be created for valid payload.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallAsMentorForMentee() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];
        Account mentor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentor Accepted'
            LIMIT 1
        ];

        KenMentorshipController.ScheduleCallRequest request = new KenMentorshipController.ScheduleCallRequest();
        request.participantType = 'mentee';
        request.participantId = mentee.Id;
        request.title = 'Mentor Created Call';
        request.meetingDate = String.valueOf(Date.today().addDays(2));
        request.startTime = '09:00';
        request.endTime = '09:30';
        request.meetingType = 'Online';
        request.meetLink = 'https://example.com/mentor-created-call';

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentor.Id;
        Id recordId = KenMentorshipController.scheduleCallForCurrentMentee(request);
        Test.stopTest();

        Ken_Mentorship__c insertedCall = [
            SELECT Id, Mentor__c, Mentee__c, MeetingRequestedBy__c, RecordType.DeveloperName
            FROM Ken_Mentorship__c
            WHERE Id = :recordId
            LIMIT 1
        ];
        System.assertEquals(CALL_RECORD_TYPE, insertedCall.RecordType.DeveloperName);
        System.assertEquals(mentor.Id, insertedCall.Mentor__c, 'Current account should be set as mentor.');
        System.assertEquals(mentee.Id, insertedCall.Mentee__c, 'Selected account should be set as mentee.');
        System.assertEquals(mentor.Id, insertedCall.MeetingRequestedBy__c, 'Requester should be current account.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testRespondToCallRequestAcceptAndReject() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];
        Account mentor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentor Accepted'
            LIMIT 1
        ];

        Id callRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c'
              AND DeveloperName = :CALL_RECORD_TYPE
            LIMIT 1
        ].Id;

        Ken_Mentorship__c rejectCandidate = new Ken_Mentorship__c(
            RecordTypeId           = callRecordTypeId,
            Mentor__c              = mentor.Id,
            Mentee__c              = mentee.Id,
            MeetingRequestedBy__c  = mentee.Id,
            Meet_Date__c           = Date.today().addDays(5),
            Meet_Start_Time__c     = Time.newInstance(10, 0, 0, 0),
            Meet_End_Time__c       = Time.newInstance(10, 30, 0, 0),
            Meeting_Mode__c        = 'Online',
            Call_Request_Status__c = 'Requested',
            Mentorship_Status__c   = 'Requested'
        );
        insert rejectCandidate;

        Ken_Mentorship__c acceptCandidate = [
            SELECT Id
            FROM Ken_Mentorship__c
            WHERE RecordType.DeveloperName = :CALL_RECORD_TYPE
              AND Mentor__c = :mentor.Id
              AND Mentee__c = :mentee.Id
              AND Call_Request_Status__c = 'Requested'
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentor.Id;
        KenMentorshipController.respondToCallRequest(String.valueOf(acceptCandidate.Id), 'accept');
        KenMentorshipController.respondToCallRequest(String.valueOf(rejectCandidate.Id), 'reject');
        Test.stopTest();

        Map<Id, Ken_Mentorship__c> updatedCalls = new Map<Id, Ken_Mentorship__c>([
            SELECT Id, Call_Request_Status__c, Mentorship_Status__c
            FROM Ken_Mentorship__c
            WHERE Id IN :new Set<Id>{ acceptCandidate.Id, rejectCandidate.Id }
        ]);
        System.assertEquals('Accepted', updatedCalls.get(acceptCandidate.Id).Call_Request_Status__c);
        System.assertEquals('Accepted', updatedCalls.get(acceptCandidate.Id).Mentorship_Status__c);
        System.assertEquals('Rejected', updatedCalls.get(rejectCandidate.Id).Call_Request_Status__c);
        System.assertEquals('Rejected', updatedCalls.get(rejectCandidate.Id).Mentorship_Status__c);

        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testMenteeCanRespondToMentorInitiatedCall() {
        Account mentee = [SELECT Id FROM Account WHERE Name = 'Generic Test Mentee' LIMIT 1];
        Account mentor = [SELECT Id FROM Account WHERE Name = 'Generic Test Mentor Accepted' LIMIT 1];

        Id callRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c'
              AND DeveloperName = :CALL_RECORD_TYPE
            LIMIT 1
        ].Id;

        // Mentor raises the request, so the mentee is the legitimate responder.
        Ken_Mentorship__c mentorInitiated = new Ken_Mentorship__c(
            RecordTypeId           = callRecordTypeId,
            Mentor__c              = mentor.Id,
            Mentee__c              = mentee.Id,
            MeetingRequestedBy__c  = mentor.Id,
            Meet_Date__c           = Date.today().addDays(3),
            Meet_Start_Time__c     = Time.newInstance(14, 0, 0, 0),
            Meet_End_Time__c       = Time.newInstance(14, 30, 0, 0),
            Meeting_Mode__c        = 'Online',
            Call_Request_Status__c = 'Requested',
            Mentorship_Status__c   = 'Requested'
        );
        insert mentorInitiated;

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        KenMentorshipController.respondToCallRequest(String.valueOf(mentorInitiated.Id), 'accept');
        Test.stopTest();

        Ken_Mentorship__c updated = [
            SELECT Call_Request_Status__c, Mentorship_Status__c
            FROM Ken_Mentorship__c
            WHERE Id = :mentorInitiated.Id
            LIMIT 1
        ];
        System.assertEquals('Accepted', updated.Call_Request_Status__c, 'Mentee should be able to accept a mentor-initiated call.');
        System.assertEquals('Accepted', updated.Mentorship_Status__c, 'Mentorship status should align with acceptance.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testRequesterCannotRespondToOwnCall() {
        Account mentee = [SELECT Id FROM Account WHERE Name = 'Generic Test Mentee' LIMIT 1];
        Account mentor = [SELECT Id FROM Account WHERE Name = 'Generic Test Mentor Accepted' LIMIT 1];

        Id callRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c'
              AND DeveloperName = :CALL_RECORD_TYPE
            LIMIT 1
        ].Id;

        Ken_Mentorship__c ownRequest = new Ken_Mentorship__c(
            RecordTypeId           = callRecordTypeId,
            Mentor__c              = mentor.Id,
            Mentee__c              = mentee.Id,
            MeetingRequestedBy__c  = mentee.Id,
            Meet_Date__c           = Date.today().addDays(4),
            Meet_Start_Time__c     = Time.newInstance(15, 0, 0, 0),
            Meet_End_Time__c       = Time.newInstance(15, 30, 0, 0),
            Meeting_Mode__c        = 'Online',
            Call_Request_Status__c = 'Requested',
            Mentorship_Status__c   = 'Requested'
        );
        insert ownRequest;

        Boolean threw = false;
        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id; // mentee is the requester
        try {
            KenMentorshipController.respondToCallRequest(String.valueOf(ownRequest.Id), 'accept');
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'The requester must not be able to accept their own call request.');
        Ken_Mentorship__c unchanged = [
            SELECT Call_Request_Status__c FROM Ken_Mentorship__c WHERE Id = :ownRequest.Id LIMIT 1
        ];
        System.assertEquals('Requested', unchanged.Call_Request_Status__c, 'Status should remain Requested.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testRespondToMentorshipRequest_AcceptAndReject() {
        Account mentor = [SELECT Id FROM Account WHERE Name = 'Generic Test Mentor Accepted' LIMIT 1];
        Account mentee = [SELECT Id FROM Account WHERE Name = 'Generic Test Mentee' LIMIT 1];
        Id connRtId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c' AND DeveloperName = :CONNECTION_RECORD_TYPE
            LIMIT 1
        ].Id;
        Ken_Mentorship__c acc = new Ken_Mentorship__c(
            RecordTypeId = connRtId,
            Mentor__c = mentor.Id,
            Mentee__c = mentee.Id,
            Mentorship_Status__c = 'Requested'
        );
        Ken_Mentorship__c rej = new Ken_Mentorship__c(
            RecordTypeId = connRtId,
            Mentor__c = mentor.Id,
            Mentee__c = mentee.Id,
            Mentorship_Status__c = 'Requested'
        );
        insert new List<Ken_Mentorship__c>{ acc, rej };

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentor.Id;
        KenMentorshipController.respondToMentorshipRequest(String.valueOf(acc.Id), 'accept');
        KenMentorshipController.respondToMentorshipRequest(String.valueOf(rej.Id), 'reject');
        Test.stopTest();

        Map<Id, Ken_Mentorship__c> updated = new Map<Id, Ken_Mentorship__c>([
            SELECT Id, Mentorship_Status__c
            FROM Ken_Mentorship__c
            WHERE Id IN :new Set<Id>{ acc.Id, rej.Id }
        ]);
        System.assertEquals('Accepted', updated.get(acc.Id).Mentorship_Status__c);
        System.assertEquals('Rejected', updated.get(rej.Id).Mentorship_Status__c);

        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testRescheduleCallRequestAcceptsAndUpdatesSlot() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];
        Account mentor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentor Accepted'
            LIMIT 1
        ];

        Id callRecordTypeId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Ken_Mentorship__c'
              AND DeveloperName = :CALL_RECORD_TYPE
            LIMIT 1
        ].Id;

        Ken_Mentorship__c rescheduleCandidate = new Ken_Mentorship__c(
            RecordTypeId           = callRecordTypeId,
            Mentor__c              = mentor.Id,
            Mentee__c              = mentee.Id,
            MeetingRequestedBy__c  = mentee.Id,
            Meet_Date__c           = Date.today().addDays(7),
            Meet_Start_Time__c     = Time.newInstance(9, 0, 0, 0),
            Meet_End_Time__c       = Time.newInstance(9, 30, 0, 0),
            Meeting_Mode__c        = 'Online',
            Call_Request_Status__c = 'Requested',
            Mentorship_Status__c   = 'Requested'
        );
        insert rescheduleCandidate;

        Date newDate = Date.today().addDays(10);
        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentor.Id;
        KenMentorshipController.rescheduleCallRequest(
            String.valueOf(rescheduleCandidate.Id),
            String.valueOf(newDate),
            '11:00',
            '11:45'
        );
        Test.stopTest();

        Ken_Mentorship__c updated = [
            SELECT Id, Meet_Date__c, Meet_Start_Time__c, Meet_End_Time__c, Call_Request_Status__c, Mentorship_Status__c
            FROM Ken_Mentorship__c
            WHERE Id = :rescheduleCandidate.Id
            LIMIT 1
        ];
        System.assertEquals(newDate, updated.Meet_Date__c, 'Rescheduled date should be saved.');
        System.assertEquals(Time.newInstance(11, 0, 0, 0), updated.Meet_Start_Time__c, 'Rescheduled start time should be saved.');
        System.assertEquals(Time.newInstance(11, 45, 0, 0), updated.Meet_End_Time__c, 'Rescheduled end time should be saved.');
        System.assertEquals('Accepted', updated.Call_Request_Status__c, 'Reschedule flow should accept the request.');
        System.assertEquals('Accepted', updated.Mentorship_Status__c, 'Reschedule flow should align mentorship status.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testTaskCrudForCurrentMentee() {
        Account mentee = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentee'
            LIMIT 1
        ];
        Account mentor = [
            SELECT Id
            FROM Account
            WHERE Name = 'Generic Test Mentor Accepted'
            LIMIT 1
        ];

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        List<KenMentorshipController.TaskRow> existingTasks = KenMentorshipController.getTasksForCurrentMentee();

        KenMentorshipController.TaskSaveRequest createRequest = new KenMentorshipController.TaskSaveRequest();
        createRequest.title = 'Create Task Via Controller';
        createRequest.status = 'In Progress';
        createRequest.priority = 'High';
        createRequest.description = 'Created in test';
        createRequest.descriptionHtml = '<p>Created in test</p>';
        createRequest.endDate = String.valueOf(Date.today().addDays(2));
        createRequest.assignTo = 'mentor';
        createRequest.mentorId = mentor.Id;
        KenMentorshipController.TaskRow createdTask = KenMentorshipController.saveTaskForCurrentMentee(createRequest);

        KenMentorshipController.TaskSaveRequest updateRequest = new KenMentorshipController.TaskSaveRequest();
        updateRequest.id = createdTask.id;
        updateRequest.title = 'Updated Task Via Controller';
        updateRequest.status = 'Completed';
        updateRequest.priority = 'Medium';
        updateRequest.description = 'Updated in test';
        updateRequest.descriptionHtml = '<p>Updated in test</p>';
        updateRequest.endDate = String.valueOf(Date.today().addDays(3));
        updateRequest.assignTo = 'mentor';
        updateRequest.mentorId = mentor.Id;
        KenMentorshipController.TaskRow updatedTask = KenMentorshipController.saveTaskForCurrentMentee(updateRequest);

        KenMentorshipController.deleteTaskForCurrentMentee(String.valueOf(createdTask.id));
        List<KenMentorshipController.TaskRow> finalTasks = KenMentorshipController.getTasksForCurrentMentee();
        Test.stopTest();

        System.assert(existingTasks.size() > 0, 'Expected seeded task to be returned.');
        System.assertNotEquals(null, createdTask.id, 'Created task should return an id.');
        System.assertEquals('Create Task Via Controller', createdTask.title);
        System.assertEquals('Updated Task Via Controller', updatedTask.title);
        System.assertEquals('Completed', updatedTask.status);
        Boolean deletedTaskFound = false;
        for (KenMentorshipController.TaskRow row : finalTasks) {
            if (String.valueOf(row.id) == String.valueOf(createdTask.id)) {
                deletedTaskFound = true;
                break;
            }
        }
        System.assertEquals(false, deletedTaskFound, 'Deleted task should not be returned in final response.');

        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testGetMentorAvailabilityDaysReturnsConfiguredValues() {
        Account mentorAccepted = [
            SELECT Id FROM Account WHERE Name = 'Generic Test Mentor Accepted' LIMIT 1
        ];

        insert new Ken_Alumni_Preferences__c(
            Person_Account__c                       = mentorAccepted.Id,
            Willing_to_be_a_mentor__c               = true,
            Mentorship_Availability_Days__c         = 'Monday;Wednesday',
            Mentorship_Availability_Start_Time__c   = Time.newInstance(9, 30, 0, 0),
            Mentorship_Availability_End_Time__c     = Time.newInstance(17, 0, 0, 0)
        );

        Test.startTest();
        KenMentorshipController.MentorAvailability avail =
            KenMentorshipController.getMentorAvailabilityDays(String.valueOf(mentorAccepted.Id));
        KenMentorshipController.MentorAvailability blank =
            KenMentorshipController.getMentorAvailabilityDays(null);
        KenMentorshipController.MentorAvailability invalid =
            KenMentorshipController.getMentorAvailabilityDays('not-a-real-id');
        Test.stopTest();

        System.assertEquals('Monday;Wednesday', avail.availabilityDays, 'availabilityDays should return configured value');
        System.assertEquals('09:30', avail.availabilityStartTime, 'availabilityStartTime should be HH:mm formatted');
        System.assertEquals('17:00', avail.availabilityEndTime, 'availabilityEndTime should be HH:mm formatted');
        System.assertEquals('', blank.availabilityDays, 'Blank mentorId should yield empty availability');
        System.assertEquals('', invalid.availabilityDays, 'Invalid mentorId should yield empty availability');
    }

    @IsTest
    static void testGetCurrentUserMentorPreference() {
        Test.startTest();
        Boolean defaultPref = KenMentorshipController.getCurrentUserMentorPreference();
        Test.stopTest();

        System.assertEquals(false, defaultPref,
            'getCurrentUserMentorPreference should be false when running user has no associated person account preferences');
    }

    @IsTest
    static void testNullContextReturnsEmptyAndThrows() {
        KenMentorshipController.testCurrentAccountId = null;

        Test.startTest();
        System.assertEquals(0, KenMentorshipController.getMentorshipConnections().size(),
            'Connections should be empty without an account context.');
        System.assertEquals(0, KenMentorshipController.getAcceptedMentorsForCurrentMentee().size(),
            'Mentor options should be empty without an account context.');
        System.assertEquals(0, KenMentorshipController.getAcceptedMenteesForCurrentMentor().size(),
            'Mentee options should be empty without an account context.');
        System.assertEquals(0, KenMentorshipController.getScheduledCallsForCurrentMentee().size(),
            'Scheduled calls should be empty without an account context.');
        System.assertEquals(0, KenMentorshipController.getTasksForCurrentMentee().size(),
            'Tasks should be empty without an account context.');
        System.assertEquals(null, KenMentorshipController.getCurrentUserCity(),
            'City should be null without an account context.');
        System.assert(saveTaskThrows(null), 'Null task payload should throw.');
        System.assert(saveTaskThrows(new KenMentorshipController.TaskSaveRequest()),
            'Task save without an account context should throw.');
        System.assert(deleteTaskThrows('001000000000001AAA'),
            'Task delete without an account context should throw.');
        System.assert(respondMentorshipThrows('001000000000001AAA', 'accept'),
            'Mentorship response without an account context should throw.');
        System.assert(respondCallThrows('001000000000001AAA', 'accept'),
            'Call response without an account context should throw.');
        System.assert(rescheduleThrows('001000000000001AAA', String.valueOf(Date.today().addDays(1)), '10:00', '11:00'),
            'Reschedule without an account context should throw.');
        Test.stopTest();
    }

    @IsTest
    static void testConnectionsEmptyForUnconnectedAccount() {
        Account loner = new Account(Name = 'Generic Lonely Account');
        insert loner;

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = loner.Id;
        List<KenMentorshipController.MentorshipConnectionRow> rows =
            KenMentorshipController.getMentorshipConnections();
        KenMentorshipController.MentorAvailability availability =
            KenMentorshipController.getMentorAvailabilityDays(String.valueOf(loner.Id));
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Account with no accepted mentorships should return no rows.');
        System.assertEquals('', availability.availabilityDays, 'Account without preferences should return empty days.');
        System.assertEquals('', availability.availabilityStartTime, 'Account without preferences should return empty start time.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testConnectionEnrichmentFromCrmPreferencesAndMailingAddress() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Id personRtId = [
            SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1
        ].Id;

        Account mailingMentor = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Mailing',
            LastName = 'Mentor',
            PersonTitle = 'Director',
            PersonMailingCity = 'Mumbai',
            PersonMailingState = 'Maharashtra',
            PersonMailingCountry = 'India'
        );
        Account crmMentor = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Crm',
            LastName = 'Mentor'
        );
        insert new List<Account>{ mailingMentor, crmMentor };

        insert new Ken_Alumni_CRM__c(
            Person_Account__c = crmMentor.Id,
            Profile_Photo_URL__c = 'https://example.com/photo.png',
            Current_Location__c = 'Bangalore, Karnataka',
            Current_Company__c = 'TestCorp',
            Program__c = 'MBA',
            Year_of_Graduation__c = '2018'
        );
        insert new Ken_Alumni_Preferences__c(
            Person_Account__c = crmMentor.Id,
            Willing_to_be_a_mentor__c = true
        );

        Id connRtId = connectionRtId();
        insert new List<Ken_Mentorship__c>{
            new Ken_Mentorship__c(
                RecordTypeId = connRtId,
                Mentor__c = mailingMentor.Id,
                Mentee__c = mentee.Id,
                Mentorship_Status__c = 'Accepted'
            ),
            new Ken_Mentorship__c(
                RecordTypeId = connRtId,
                Mentor__c = crmMentor.Id,
                Mentee__c = mentee.Id,
                Mentorship_Status__c = 'Accepted'
            )
        };

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        List<KenMentorshipController.MentorshipConnectionRow> rows =
            KenMentorshipController.getMentorshipConnections();
        Test.stopTest();

        KenMentorshipController.MentorshipConnectionRow mailingRow;
        KenMentorshipController.MentorshipConnectionRow crmRow;
        for (KenMentorshipController.MentorshipConnectionRow row : rows) {
            if (row.personAccountId == mailingMentor.Id) {
                mailingRow = row;
            } else if (row.personAccountId == crmMentor.Id) {
                crmRow = row;
            }
        }

        System.assertNotEquals(null, mailingRow, 'Mailing address mentor should be returned.');
        System.assertEquals('Mumbai, Maharashtra, India', mailingRow.location,
            'Location should be built from person mailing address parts.');
        System.assertEquals('Mumbai', mailingRow.currentCity, 'City should be extracted from the location.');
        System.assertEquals('Director', mailingRow.title, 'Title should come from PersonTitle.');
        System.assertEquals(false, mailingRow.willingToHelp, 'Mentor without preferences should not be willing to help.');

        System.assertNotEquals(null, crmRow, 'CRM enriched mentor should be returned.');
        System.assertEquals('https://example.com/photo.png', crmRow.profileImage,
            'Profile image should come from the alumni CRM record.');
        System.assertEquals('Bangalore, Karnataka', crmRow.location, 'Location should come from the alumni CRM record.');
        System.assertEquals('TestCorp', crmRow.company, 'Company should come from the alumni CRM record.');
        System.assertEquals('MBA', crmRow.programLastAttended, 'Program should come from the alumni CRM record.');
        System.assertEquals('2018', crmRow.graduationYear, 'Graduation year should come from the alumni CRM record.');
        System.assertEquals(true, crmRow.willingToHelp, 'Mentor preference should flow through to the row.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduledCallStatusMatrixAndHiddenRows() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account mentor = fetchAccount('Generic Test Mentor Accepted');
        Time tenAm = Time.newInstance(10, 0, 0, 0);
        Time elevenAm = Time.newInstance(11, 0, 0, 0);

        Ken_Mentorship__c completedByDate = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(-1), tenAm, elevenAm, 'Online', 'Accepted');
        Ken_Mentorship__c happeningNow = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today(), Time.newInstance(0, 0, 0, 0), Time.newInstance(23, 59, 59, 0), 'Online', 'Accepted');
        Ken_Mentorship__c futureOnline = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(5), tenAm, elevenAm, 'Online', 'Accepted');
        futureOnline.Meeting_Description__c = '<p>' + 'a'.repeat(130) + '</p>';
        Ken_Mentorship__c futureInPerson = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(5), tenAm, elevenAm, 'In-person', 'Accepted');
        Ken_Mentorship__c scheduledStatus = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(5), tenAm, elevenAm, 'Online', 'Scheduled');
        Ken_Mentorship__c completedStatus = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(-5), tenAm, elevenAm, 'Online', 'Completed');
        Ken_Mentorship__c rejectedHidden = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(5), tenAm, elevenAm, 'Online', 'Rejected');
        Ken_Mentorship__c noTimes = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(6), null, null, 'Online', 'Accepted');
        Ken_Mentorship__c startOnly = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(7), tenAm, null, 'Online', 'Accepted');
        insert new List<Ken_Mentorship__c>{
            completedByDate, happeningNow, futureOnline, futureInPerson,
            scheduledStatus, completedStatus, rejectedHidden, noTimes, startOnly
        };

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        List<KenMentorshipController.ScheduleEventRow> rows =
            KenMentorshipController.getScheduledCallsForCurrentMentee();
        Test.stopTest();

        Map<Id, KenMentorshipController.ScheduleEventRow> rowById =
            new Map<Id, KenMentorshipController.ScheduleEventRow>();
        for (KenMentorshipController.ScheduleEventRow row : rows) {
            rowById.put(row.id, row);
        }

        System.assertEquals('completed', rowById.get(completedByDate.Id).status,
            'Accepted call in the past should map to completed.');
        System.assertEquals('happening', rowById.get(happeningNow.Id).status,
            'Accepted call spanning now should map to happening.');
        System.assertEquals('video', rowById.get(futureOnline.Id).status,
            'Accepted future online call should map to video.');
        System.assertEquals('request', rowById.get(futureInPerson.Id).status,
            'Accepted future in-person call should map to request.');
        System.assertEquals('request', rowById.get(scheduledStatus.Id).status,
            'Scheduled status should map to request.');
        System.assertEquals('request', rowById.get(completedStatus.Id).status,
            'Completed status should fall through to request.');
        System.assertEquals(false, rowById.containsKey(rejectedHidden.Id),
            'Rejected calls should be hidden from the schedule.');
        System.assertEquals('', rowById.get(noTimes.Id).timeLabel,
            'Call without times should have an empty time label.');
        System.assertEquals(null, rowById.get(noTimes.Id).startTime,
            'Call without a start time should return null start time.');
        System.assertEquals('10:00 AM', rowById.get(startOnly.Id).timeLabel,
            'Call with only a start time should label just that time.');
        System.assert(rowById.get(futureOnline.Id).topic.endsWith('...'),
            'Long descriptions should be truncated in the topic.');
        System.assert(String.isNotBlank(rowById.get(futureOnline.Id).meetingDescription),
            'Description text should be populated from the rich text field.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduledCallFeedbackSubmittedFlag() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account mentor = fetchAccount('Generic Test Mentor Accepted');

        Ken_Questionnaire__c answeredQnr = new Ken_Questionnaire__c(
            Section_Name__c = 'Mentorship Feedback Answered',
            Descripation__c = 'Answered feedback questionnaire',
            Target_Audience__c = 'Alumni'
        );
        Ken_Questionnaire__c openQnr = new Ken_Questionnaire__c(
            Section_Name__c = 'Mentorship Feedback Open',
            Descripation__c = 'Open feedback questionnaire',
            Target_Audience__c = 'Alumni'
        );
        insert new List<Ken_Questionnaire__c>{ answeredQnr, openQnr };

        Ken_Questionnaire_Parameter__c question = new Ken_Questionnaire_Parameter__c(
            Questionnaire__c = answeredQnr.Id,
            Question_Label__c = 'How was the call?',
            Question_Type__c = 'Short Answer',
            Is_Required__c = false,
            Order__c = 1,
            Section_Name__c = 'Mentorship Feedback Answered'
        );
        insert question;

        Ken_Survey__c answeredSurvey = new Ken_Survey__c(
            Name = 'Answered Call Feedback',
            Type__c = 'Feedback',
            Is_Active__c = true,
            Ken_Questionnaire__c = answeredQnr.Id
        );
        Ken_Survey__c openSurvey = new Ken_Survey__c(
            Name = 'Open Call Feedback',
            Type__c = 'Feedback',
            Is_Active__c = true,
            Ken_Questionnaire__c = openQnr.Id
        );
        insert new List<Ken_Survey__c>{ answeredSurvey, openSurvey };

        Ken_Mentorship__c answeredCall = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(-2), Time.newInstance(10, 0, 0, 0), Time.newInstance(11, 0, 0, 0), 'Online', 'Accepted');
        answeredCall.Survey__c = answeredSurvey.Id;
        Ken_Mentorship__c openCall = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(-3), Time.newInstance(10, 0, 0, 0), Time.newInstance(11, 0, 0, 0), 'Online', 'Accepted');
        openCall.Survey__c = openSurvey.Id;
        insert new List<Ken_Mentorship__c>{ answeredCall, openCall };

        insert new Ken_Questionnaire_Parameter_Response__c(
            Questionnaire_Parameter__c = question.Id,
            Respondent__c = mentee.Id,
            Response__c = 'Great session',
            Response_Category__c = 'Feedback'
        );

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        List<KenMentorshipController.ScheduleEventRow> rows =
            KenMentorshipController.getScheduledCallsForCurrentMentee();
        Test.stopTest();

        Boolean answeredFlag;
        Boolean answeredHasForm;
        Boolean openFlag;
        for (KenMentorshipController.ScheduleEventRow row : rows) {
            if (row.id == answeredCall.Id) {
                answeredFlag = row.feedbackSubmitted;
                answeredHasForm = row.hasFeedbackForm;
            } else if (row.id == openCall.Id) {
                openFlag = row.feedbackSubmitted;
            }
        }

        System.assertEquals(true, answeredHasForm, 'Call with an attached survey should expose the feedback form.');
        System.assertEquals(true, answeredFlag, 'Call whose survey the viewer answered should be flagged submitted.');
        System.assertEquals(false, openFlag, 'Call with an unanswered survey should not be flagged submitted.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallValidationErrors() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account mentor = fetchAccount('Generic Test Mentor Accepted');

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;

        KenMentorshipController.ScheduleCallRequest badDate = buildScheduleRequest(2);
        badDate.mentorId = mentor.Id;
        badDate.meetingDate = 'not-a-date';
        System.assert(scheduleThrows(badDate), 'Unparseable date should throw.');

        KenMentorshipController.ScheduleCallRequest missingDate = buildScheduleRequest(2);
        missingDate.mentorId = mentor.Id;
        missingDate.meetingDate = null;
        System.assert(scheduleThrows(missingDate), 'Missing date should throw.');

        KenMentorshipController.ScheduleCallRequest missingStart = buildScheduleRequest(2);
        missingStart.mentorId = mentor.Id;
        missingStart.startTime = null;
        System.assert(scheduleThrows(missingStart), 'Missing start time should throw.');

        KenMentorshipController.ScheduleCallRequest missingType = buildScheduleRequest(2);
        missingType.mentorId = mentor.Id;
        missingType.meetingType = null;
        System.assert(scheduleThrows(missingType), 'Missing meeting type should throw.');

        KenMentorshipController.ScheduleCallRequest badType = buildScheduleRequest(2);
        badType.mentorId = mentor.Id;
        badType.meetingType = 'Hybrid';
        System.assert(scheduleThrows(badType), 'Unsupported meeting type should throw.');
        Test.stopTest();

        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallParticipantCandidateFiltersAndInPerson() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account mentor = fetchAccount('Generic Test Mentor Accepted');
        Account stranger = new Account(Name = 'Generic Unconnected Mentor');
        insert stranger;

        KenMentorshipController.ScheduleCallRequest request = buildScheduleRequest(5);
        request.participantType = 'mentor';
        request.participantId = 'ab';
        request.mentorId = '001-00000000AAA';
        request.mentor = String.valueOf(mentor.Id);
        request.title = 'In Person Session';
        request.meetingDate = String.valueOf(Date.today().addDays(5)) + ' 08:00';
        request.meetingType = 'In-person';
        request.meetLink = 'Conference Room A';

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        Id callId = KenMentorshipController.scheduleCallForCurrentMentee(request);

        KenMentorshipController.ScheduleCallRequest unaccepted = buildScheduleRequest(5);
        unaccepted.mentorId = String.valueOf(stranger.Id);
        System.assert(scheduleThrows(unaccepted), 'Mentor without an accepted mentorship should throw.');
        Test.stopTest();

        Ken_Mentorship__c saved = [
            SELECT Meet_Date__c, Meeting_Link__c, Meeting_Location__c, Meeting_Mode__c
            FROM Ken_Mentorship__c
            WHERE Id = :callId
            LIMIT 1
        ];
        System.assertEquals(Date.today().addDays(5), saved.Meet_Date__c,
            'Date with a time suffix should parse to the date portion.');
        System.assertEquals('In-person', saved.Meeting_Mode__c, 'Meeting mode should be preserved.');
        System.assertEquals(null, saved.Meeting_Link__c, 'In-person calls should not store a meeting link.');
        System.assertEquals('Conference Room A', saved.Meeting_Location__c,
            'In-person calls should store the location from the link input.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallMenteeFallbackPaths() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account mentor = fetchAccount('Generic Test Mentor Accepted');
        Account stranger = new Account(Name = 'Generic Unconnected Mentee');
        insert stranger;

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentor.Id;

        KenMentorshipController.ScheduleCallRequest fallbackRequest = buildScheduleRequest(2);
        fallbackRequest.participantType = 'mentee';
        Id callId = KenMentorshipController.scheduleCallForCurrentMentee(fallbackRequest);

        KenMentorshipController.ScheduleCallRequest unaccepted = buildScheduleRequest(2);
        unaccepted.participantType = 'mentee';
        unaccepted.participantId = String.valueOf(stranger.Id);
        System.assert(scheduleThrows(unaccepted), 'Mentee without an accepted mentorship should throw.');

        Account secondMentee = new Account(Name = 'Generic Second Mentee');
        insert secondMentee;
        insert new Ken_Mentorship__c(
            RecordTypeId = connectionRtId(),
            Mentor__c = mentor.Id,
            Mentee__c = secondMentee.Id,
            Mentorship_Status__c = 'Accepted'
        );

        KenMentorshipController.ScheduleCallRequest ambiguous = buildScheduleRequest(2);
        ambiguous.participantType = 'mentee';
        System.assert(scheduleThrows(ambiguous), 'Ambiguous mentee fallback should throw.');
        Test.stopTest();

        Ken_Mentorship__c saved = [
            SELECT Mentor__c, Mentee__c, MeetingRequestedBy__c
            FROM Ken_Mentorship__c
            WHERE Id = :callId
            LIMIT 1
        ];
        System.assertEquals(mentor.Id, saved.Mentor__c, 'Mentor should be the current account.');
        System.assertEquals(mentee.Id, saved.Mentee__c, 'Single accepted mentee should be resolved as fallback.');
        System.assertEquals(mentor.Id, saved.MeetingRequestedBy__c, 'Requester should be the current account.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testScheduleCallAmbiguousMentorFallbackThrows() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account secondMentor = new Account(Name = 'Generic Second Mentor');
        insert secondMentor;
        insert new Ken_Mentorship__c(
            RecordTypeId = connectionRtId(),
            Mentor__c = secondMentor.Id,
            Mentee__c = mentee.Id,
            Mentorship_Status__c = 'Accepted'
        );

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        System.assert(scheduleThrows(buildScheduleRequest(2)),
            'Fallback with multiple accepted mentors should throw.');
        Test.stopTest();

        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testRespondValidationErrors() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account mentor = fetchAccount('Generic Test Mentor Accepted');
        Account stranger = new Account(Name = 'Generic Stranger Responder');
        insert stranger;

        Ken_Mentorship__c seededCall = [
            SELECT Id
            FROM Ken_Mentorship__c
            WHERE RecordType.DeveloperName = :CALL_RECORD_TYPE
              AND Call_Request_Status__c = 'Requested'
            LIMIT 1
        ];
        Ken_Mentorship__c acceptedCall = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(9), Time.newInstance(10, 0, 0, 0), Time.newInstance(11, 0, 0, 0), 'Online', 'Accepted');
        insert acceptedCall;

        Ken_Mentorship__c foreignRequest = new Ken_Mentorship__c(
            RecordTypeId = connectionRtId(),
            Mentor__c = mentee.Id,
            Mentee__c = mentor.Id,
            Mentorship_Status__c = 'Requested'
        );
        insert foreignRequest;

        Ken_Mentorship__c acceptedConnection = [
            SELECT Id
            FROM Ken_Mentorship__c
            WHERE RecordType.DeveloperName = :CONNECTION_RECORD_TYPE
              AND Mentor__c = :mentor.Id
              AND Mentorship_Status__c = 'Accepted'
            LIMIT 1
        ];

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentor.Id;
        System.assert(respondCallThrows('abc', 'accept'), 'Short call id should throw.');
        System.assert(respondCallThrows(String.valueOf(seededCall.Id), 'noop'),
            'Unsupported call action should throw.');
        System.assert(respondCallThrows(String.valueOf(acceptedCall.Id), 'accept'),
            'Responding to a non-requested call should throw.');
        System.assert(respondMentorshipThrows('abcdefghijklmn!', 'accept'),
            'Mentorship id with invalid characters should throw.');
        System.assert(respondMentorshipThrows(String.valueOf(acceptedConnection.Id), 'noop'),
            'Unsupported mentorship action should throw.');
        System.assert(respondMentorshipThrows(String.valueOf(foreignRequest.Id), 'accept'),
            'Mentorship request owned by another mentor should not be found.');
        System.assert(respondMentorshipThrows(String.valueOf(acceptedConnection.Id), 'accept'),
            'Non-pending mentorship request should throw.');
        KenMentorshipController.testCurrentAccountId = stranger.Id;
        System.assert(respondCallThrows(String.valueOf(seededCall.Id), 'accept'),
            'Call request should not be found for an unrelated account.');
        Test.stopTest();

        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testRescheduleValidationErrors() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account mentor = fetchAccount('Generic Test Mentor Accepted');
        Account stranger = new Account(Name = 'Generic Stranger Rescheduler');
        insert stranger;

        Ken_Mentorship__c seededCall = [
            SELECT Id
            FROM Ken_Mentorship__c
            WHERE RecordType.DeveloperName = :CALL_RECORD_TYPE
              AND Call_Request_Status__c = 'Requested'
            LIMIT 1
        ];
        Ken_Mentorship__c acceptedCall = buildCall(mentor.Id, mentee.Id, mentee.Id,
            Date.today().addDays(9), Time.newInstance(10, 0, 0, 0), Time.newInstance(11, 0, 0, 0), 'Online', 'Accepted');
        insert acceptedCall;

        String callId = String.valueOf(seededCall.Id);
        String futureDate = String.valueOf(Date.today().addDays(6));

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentor.Id;
        System.assert(rescheduleThrows('zz', futureDate, '10:00', '11:00'), 'Invalid id should throw.');
        System.assert(rescheduleThrows(callId, 'not-a-date', '10:00', '11:00'), 'Invalid date should throw.');
        System.assert(rescheduleThrows(callId, String.valueOf(Date.today().addDays(-3)), '10:00', '11:00'),
            'Past date should throw.');
        System.assert(rescheduleThrows(callId, futureDate, '', '11:00'), 'Blank start time should throw.');
        System.assert(rescheduleThrows(callId, futureDate, '10', '11:00'), 'Time without minutes should throw.');
        System.assert(rescheduleThrows(callId, futureDate, 'aa:bb', '11:00'), 'Non-numeric time should throw.');
        System.assert(rescheduleThrows(callId, futureDate, '99999999999:00', '11:00'),
            'Overflowing hour should throw.');
        System.assert(rescheduleThrows(callId, futureDate, '10:00:xx', '11:00'),
            'Non-numeric seconds should throw.');
        System.assert(rescheduleThrows(callId, futureDate, '10:00:99999999999', '11:00'),
            'Overflowing seconds should throw.');
        System.assert(rescheduleThrows(callId, futureDate, '25:00', '11:00'),
            'Out-of-range hour should throw.');
        System.assert(rescheduleThrows(callId, futureDate, '10:00:30.000', '09:00'),
            'End time before start time should throw.');
        System.assert(rescheduleThrows(String.valueOf(acceptedCall.Id), futureDate, '10:00', '11:00'),
            'Non-requested call should not be reschedulable.');
        KenMentorshipController.testCurrentAccountId = mentee.Id;
        System.assert(rescheduleThrows(callId, futureDate, '10:00', '11:00'),
            'The requester should not be able to reschedule their own call.');
        KenMentorshipController.testCurrentAccountId = stranger.Id;
        System.assert(rescheduleThrows(callId, futureDate, '10:00', '11:00'),
            'Call request should not be found for an unrelated account.');
        Test.stopTest();

        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testSaveTaskValidationAndAssignmentBranches() {
        Account mentee = fetchAccount('Generic Test Mentee');
        Account mentor = fetchAccount('Generic Test Mentor Accepted');
        Account stranger = new Account(Name = 'Generic Unconnected Assignee');
        insert stranger;

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = mentee.Id;

        KenMentorshipController.TaskSaveRequest notOwned = new KenMentorshipController.TaskSaveRequest();
        notOwned.id = '00T000000000001AAA';
        notOwned.title = 'Edit Attempt';
        notOwned.status = 'Active';
        System.assert(saveTaskThrows(notOwned), 'Editing a task the user did not create should throw.');

        KenMentorshipController.TaskSaveRequest blankTitle = new KenMentorshipController.TaskSaveRequest();
        blankTitle.title = '   ';
        blankTitle.status = 'Active';
        System.assert(saveTaskThrows(blankTitle), 'Blank title should throw.');

        KenMentorshipController.TaskSaveRequest badStatus = new KenMentorshipController.TaskSaveRequest();
        badStatus.title = 'Bad Status Task';
        badStatus.status = 'Bogus';
        System.assert(saveTaskThrows(badStatus), 'Invalid status should throw.');

        KenMentorshipController.TaskSaveRequest missingStatus = new KenMentorshipController.TaskSaveRequest();
        missingStatus.title = 'Missing Status Task';
        System.assert(saveTaskThrows(missingStatus), 'Missing status should throw.');

        KenMentorshipController.TaskSaveRequest pastDue = new KenMentorshipController.TaskSaveRequest();
        pastDue.title = 'Past Due Task';
        pastDue.status = 'Active';
        pastDue.endDate = String.valueOf(Date.today().addDays(-1));
        System.assert(saveTaskThrows(pastDue), 'Past end date should throw.');

        KenMentorshipController.TaskSaveRequest mentorMissing = new KenMentorshipController.TaskSaveRequest();
        mentorMissing.title = 'Mentor Missing Task';
        mentorMissing.status = 'Active';
        mentorMissing.assignTo = 'mentor';
        System.assert(saveTaskThrows(mentorMissing), 'Mentor assignment without a mentor should throw.');

        KenMentorshipController.TaskSaveRequest mentorNotAccepted = new KenMentorshipController.TaskSaveRequest();
        mentorNotAccepted.title = 'Mentor Not Accepted Task';
        mentorNotAccepted.status = 'Active';
        mentorNotAccepted.assignTo = 'mentor';
        mentorNotAccepted.mentorId = stranger.Id;
        System.assert(saveTaskThrows(mentorNotAccepted), 'Unaccepted mentor assignee should throw.');

        KenMentorshipController.TaskSaveRequest menteeNotAccepted = new KenMentorshipController.TaskSaveRequest();
        menteeNotAccepted.title = 'Mentee Not Accepted Task';
        menteeNotAccepted.status = 'Active';
        menteeNotAccepted.assignTo = 'mentee';
        menteeNotAccepted.assigneeId = stranger.Id;
        System.assert(saveTaskThrows(menteeNotAccepted), 'Unaccepted mentee assignee should throw.');

        KenMentorshipController.TaskSaveRequest selfRequest = new KenMentorshipController.TaskSaveRequest();
        selfRequest.title = 'Self Task';
        selfRequest.status = 'Pending';
        KenMentorshipController.TaskRow selfRow = KenMentorshipController.saveTaskForCurrentMentee(selfRequest);

        KenMentorshipController.TaskSaveRequest menteeAssignee = new KenMentorshipController.TaskSaveRequest();
        menteeAssignee.title = 'Connected Mentee Task';
        menteeAssignee.status = 'Active';
        menteeAssignee.priority = 'Urgent';
        menteeAssignee.assignTo = 'mentee';
        menteeAssignee.assigneeId = mentor.Id;
        KenMentorshipController.TaskRow menteeRow = KenMentorshipController.saveTaskForCurrentMentee(menteeAssignee);

        KenMentorshipController.TaskSaveRequest fallbackAssignee = new KenMentorshipController.TaskSaveRequest();
        fallbackAssignee.title = 'Fallback Assignment Task';
        fallbackAssignee.status = 'Active';
        fallbackAssignee.assignTo = 'helper';
        KenMentorshipController.TaskRow fallbackRow = KenMentorshipController.saveTaskForCurrentMentee(fallbackAssignee);

        KenMentorshipController.TaskSaveRequest selfMentor = new KenMentorshipController.TaskSaveRequest();
        selfMentor.title = 'Self Mentor Task';
        selfMentor.status = 'Active';
        selfMentor.assignTo = 'mentor';
        selfMentor.mentorId = mentee.Id;
        KenMentorshipController.TaskRow selfMentorRow = KenMentorshipController.saveTaskForCurrentMentee(selfMentor);

        System.assert(deleteTaskThrows('xyz'), 'Invalid delete id should throw.');
        System.assert(deleteTaskThrows('00T000000000001AAA'),
            'Deleting a task the user did not create should throw.');
        Test.stopTest();

        System.assertEquals('Pending', selfRow.status, 'Pending status should be preserved.');
        System.assertEquals('Low', selfRow.priority, 'Missing priority should default to Low.');
        System.assertEquals('Mentee', selfRow.assignTo, 'Missing assignTo should default to Mentee.');
        System.assertEquals(String.valueOf(mentee.Id), String.valueOf(selfRow.assigneeId),
            'Self task should be assigned to the current account.');
        System.assertEquals('Low', menteeRow.priority, 'Unknown priority should default to Low.');
        System.assertEquals(String.valueOf(mentor.Id), String.valueOf(menteeRow.assigneeId),
            'Connected mentee assignment should target the selected account.');
        System.assertEquals('Mentee', fallbackRow.assignTo, 'Unknown assignTo should default to Mentee.');
        System.assertEquals('Mentor', selfMentorRow.assignTo, 'Self-mentor assignment should stay Mentor.');
        System.assertEquals(String.valueOf(mentee.Id), String.valueOf(selfMentorRow.assigneeId),
            'Self-mentor task should be assigned to the current account.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testCurrentUserCityAndMentorPreferenceWithData() {
        Account cityAccount = new Account(Name = 'Generic City Account');
        insert cityAccount;
        insert new Ken_Alumni_CRM__c(
            Person_Account__c = cityAccount.Id,
            Current_Location__c = 'Bangalore, Karnataka'
        );
        insert new Ken_Alumni_Preferences__c(
            Person_Account__c = cityAccount.Id,
            Willing_to_be_a_mentor__c = true
        );

        Test.startTest();
        KenMentorshipController.testCurrentAccountId = cityAccount.Id;
        String city = KenMentorshipController.getCurrentUserCity();
        Boolean pref = KenMentorshipController.getCurrentUserMentorPreference();
        Test.stopTest();

        System.assertEquals('Bangalore', city, 'City should be extracted from the alumni CRM location.');
        System.assertEquals(true, pref, 'Mentor preference should be true when configured.');
        KenMentorshipController.testCurrentAccountId = null;
    }

    @IsTest
    static void testNormalizeTaskStatusForLwcLegacyValues() {
        System.assertEquals('Pending', KenMentorshipController.normalizeTaskStatusForLwc(null),
            'Blank status should normalize to Pending.');
        System.assertEquals('Pending', KenMentorshipController.normalizeTaskStatusForLwc('Not Started'),
            'Not Started should normalize to Pending.');
        System.assertEquals('Active', KenMentorshipController.normalizeTaskStatusForLwc('Deferred'),
            'Deferred should normalize to Active.');
        System.assertEquals('On-Hold', KenMentorshipController.normalizeTaskStatusForLwc('Waiting on someone else'),
            'Waiting on someone else should normalize to On-Hold.');
        System.assertEquals('Completed', KenMentorshipController.normalizeTaskStatusForLwc('Completed'),
            'Completed should stay Completed.');
        System.assertEquals('Pending', KenMentorshipController.normalizeTaskStatusForLwc('Someday'),
            'Unknown status should normalize to Pending.');
    }

    private static Id cachedCallRtId;
    private static Id cachedConnectionRtId;

    private static Account fetchAccount(String accountName) {
        return [SELECT Id, Name FROM Account WHERE Name = :accountName LIMIT 1];
    }

    private static Id callRtId() {
        if (cachedCallRtId == null) {
            cachedCallRtId = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Ken_Mentorship__c' AND DeveloperName = :CALL_RECORD_TYPE
                LIMIT 1
            ].Id;
        }
        return cachedCallRtId;
    }

    private static Id connectionRtId() {
        if (cachedConnectionRtId == null) {
            cachedConnectionRtId = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Ken_Mentorship__c' AND DeveloperName = :CONNECTION_RECORD_TYPE
                LIMIT 1
            ].Id;
        }
        return cachedConnectionRtId;
    }

    private static Ken_Mentorship__c buildCall(
        Id mentorId, Id menteeId, Id requestedById,
        Date meetDate, Time startTime, Time endTime,
        String mode, String callStatus
    ) {
        return new Ken_Mentorship__c(
            RecordTypeId = callRtId(),
            Mentor__c = mentorId,
            Mentee__c = menteeId,
            MeetingRequestedBy__c = requestedById,
            Meeting_Title__c = 'Matrix Call',
            Meet_Date__c = meetDate,
            Meet_Start_Time__c = startTime,
            Meet_End_Time__c = endTime,
            Meeting_Mode__c = mode,
            Call_Request_Status__c = callStatus
        );
    }

    private static KenMentorshipController.ScheduleCallRequest buildScheduleRequest(Integer daysAhead) {
        KenMentorshipController.ScheduleCallRequest request = new KenMentorshipController.ScheduleCallRequest();
        request.title = 'Generic Helper Call';
        request.meetingDate = String.valueOf(Date.today().addDays(daysAhead));
        request.startTime = '10:00';
        request.endTime = '10:30';
        request.meetingType = 'Online';
        request.meetLink = 'https://example.com/helper';
        return request;
    }

    private static Boolean scheduleThrows(KenMentorshipController.ScheduleCallRequest request) {
        try {
            KenMentorshipController.scheduleCallForCurrentMentee(request);
            return false;
        } catch (AuraHandledException ex) {
            return true;
        }
    }

    private static Boolean rescheduleThrows(String callRequestId, String meetingDate, String startTime, String endTime) {
        try {
            KenMentorshipController.rescheduleCallRequest(callRequestId, meetingDate, startTime, endTime);
            return false;
        } catch (AuraHandledException ex) {
            return true;
        }
    }

    private static Boolean respondCallThrows(String callRequestId, String action) {
        try {
            KenMentorshipController.respondToCallRequest(callRequestId, action);
            return false;
        } catch (AuraHandledException ex) {
            return true;
        }
    }

    private static Boolean respondMentorshipThrows(String mentorshipId, String action) {
        try {
            KenMentorshipController.respondToMentorshipRequest(mentorshipId, action);
            return false;
        } catch (AuraHandledException ex) {
            return true;
        }
    }

    private static Boolean saveTaskThrows(KenMentorshipController.TaskSaveRequest request) {
        try {
            KenMentorshipController.saveTaskForCurrentMentee(request);
            return false;
        } catch (AuraHandledException ex) {
            return true;
        }
    }

    private static Boolean deleteTaskThrows(String taskId) {
        try {
            KenMentorshipController.deleteTaskForCurrentMentee(taskId);
            return false;
        } catch (AuraHandledException ex) {
            return true;
        }
    }
}