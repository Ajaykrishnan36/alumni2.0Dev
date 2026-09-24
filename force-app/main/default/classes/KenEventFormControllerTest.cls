@isTest
public class KenEventFormControllerTest {
    // Fixture day for the UTC instants that replaced the old Date+Time pairs.
    private static final Date TZ_TEST_DAY = Date.today();

    @TestSetup
    static void setup() {
        insert new Ken_Alm_Org_Parameters__c();
        
        Id paRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('PersonAccount')
            .getRecordTypeId();
        Account testAccount = new Account(
            RecordTypeId = paRtId,
            LastName = 'Test Contact',
            PersonEmail = 'test@example.com'
        );
        insert testAccount;
        
        ConstituentRole cr = new ConstituentRole(
            PersonId = testAccount.Id,
            RoleType = 'Alumni',
            Registration_Status__c = 'Registered',
            Email__c = 'test@example.com'
        );
        cr.put('Status', 'Admitted');
        insert cr;
        
        Ken_Event_Master__c testEvent = new Ken_Event_Master__c(
            Name = 'Test Event',
            Event_Type__c = 'Workshop',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today().addDays(1),
            Description__c = 'Test Description',
            Target_Topics__c = 'Test Keywords',
            Max_Allowed_Participants__c = 100,
            Event_Current_Step__c = 1,
            Event_Fee__c = 500,
            No_Fee__c = false,
            Language__c = 'English',
            Auto_Enroll_Target_Audience__c = false,
            Email_Body__c = 'test body',
            Email_Subject__c = 'test subject',
            Schedule_DateTime__c = System.now(),
            Email_Attachment__c = 'Test Attahement',
            What_to_Expect_From_Event__c = 'Great learning',
            Constituent_Role__c = cr.Id
        );
        insert testEvent;
        
        Ken_Schedule_Sessions__c testSession = new Ken_Schedule_Sessions__c(
            Name = 'Test Session',
            Event_Reference__c = testEvent.Id,
            Start_DateTime__c = DateTime.newInstanceGmt(TZ_TEST_DAY, Time.newInstance(10, 0, 0, 0)),
            End_DateTime__c = DateTime.newInstanceGmt(TZ_TEST_DAY, Time.newInstance(11, 0, 0, 0)),
            Location_Type__c = 'Online',
            Session_Link__c = 'https://test.com',
            Location__c = 'Virtual',
            Session_Fee__c = 100,
            No_Fee__c = false,
            What_to_Expect_From_Event__c = 'Session expectations'
        );
        insert testSession;
        
        Ken_Events_Sessions_Enrollment__c testEnrollment = new Ken_Events_Sessions_Enrollment__c(
            Schedule_Sessions__c = testSession.Id,
            Person_Account__c = testAccount.Id,
            Speaker_Name__c = 'Test Speaker',
            Description__c = 'Test Speaker Description',
            Speaker_Email__c = 'test.speaker@example.com',
            Send_Invite__c = true,
            Invite_Email_Sent__c = false
        );
        insert testEnrollment;
    }
    
    @isTest
    static void testSearchContact() {
        Test.startTest();
        List<Account> accounts = KenEventFormController.searchContact('Test');
        Test.stopTest();
    }
    
    @isTest
    static void testGetContactDetails() {
        Account testAccount = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        
        Test.startTest();
        Account account = KenEventFormController.getContactDetails(testAccount.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testGetContactDetailsException() {
        Test.startTest();
        try {
            KenEventFormController.getContactDetails(null);
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreateContact() {
        Test.startTest();
        Account newAccount = KenEventFormController.createContact('New Contact');
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteSpeaker() {
        Ken_Events_Sessions_Enrollment__c enrollment = [SELECT Id FROM Ken_Events_Sessions_Enrollment__c LIMIT 1];
        
        Test.startTest();
        KenEventFormController.deleteSpeaker(enrollment.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteEventSession() {
        Ken_Schedule_Sessions__c session = [SELECT Id FROM Ken_Schedule_Sessions__c LIMIT 1];
        
        Test.startTest();
        KenEventFormController.deleteEventSession(session.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteEventSessionBlankId() {
        Test.startTest();
        try {
            KenEventFormController.deleteEventSession('');
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetEventSchedule() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];

        Test.startTest();
        List<KenEventFormController.EventScheduleWrapper> schedules = KenEventFormController.getEventSchedule(event.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testCreateEventScheduleNew() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        
        KenEventFormController.EventScheduleWrapper wrapper = new KenEventFormController.EventScheduleWrapper();
        wrapper.eventId = event.Id;
        wrapper.name = 'New Session';
        wrapper.startDate = Date.today();
        wrapper.startTime = Time.newInstance(9, 0, 0, 0);
        wrapper.endTime = Time.newInstance(10, 0, 0, 0);
        wrapper.locationType = 'Online';
        wrapper.sessionLink = 'https://test.com';
        wrapper.agenda = 'Test Agenda';
        wrapper.isPortal = false;
        
        KenEventFormController.SpeakerWrapper speaker = new KenEventFormController.SpeakerWrapper();
        speaker.name = 'Test Speaker';
        speaker.description = 'Speaker Description';
        wrapper.speakers.add(speaker);
        
        List<KenEventFormController.EventScheduleWrapper> wrappers = new List<KenEventFormController.EventScheduleWrapper>{wrapper};
        String jsonData = JSON.serialize(wrappers);
        
        Test.startTest();
        KenEventFormController.createEventSchedule(jsonData);
        Test.stopTest();
    }
    
    @isTest
    static void testCreateEventScheduleUpdate() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        Ken_Schedule_Sessions__c session = [SELECT Id FROM Ken_Schedule_Sessions__c LIMIT 1];
        Ken_Events_Sessions_Enrollment__c enrollment = [SELECT Id FROM Ken_Events_Sessions_Enrollment__c LIMIT 1];
        Account account = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        
        KenEventFormController.EventScheduleWrapper wrapper = new KenEventFormController.EventScheduleWrapper();
        wrapper.Id = session.Id;
        wrapper.eventId = event.Id;
        wrapper.name = 'Updated Session';
        wrapper.startDate = Date.today();
        wrapper.startTime = Time.newInstance(9, 0, 0, 0);
        wrapper.endTime = Time.newInstance(10, 0, 0, 0);
        wrapper.locationType = 'Online';
        wrapper.sessionLink = 'https://test.com';
        wrapper.agenda = 'Updated Agenda';
        wrapper.isPortal = true;
        
        KenEventFormController.SpeakerWrapper speaker = new KenEventFormController.SpeakerWrapper();
        speaker.Id = enrollment.Id;
        speaker.name = 'Updated Speaker';
        speaker.description = 'Updated Description';
        speaker.accountId = account.Id;
        wrapper.speakers.add(speaker);
        
        List<KenEventFormController.EventScheduleWrapper> wrappers = new List<KenEventFormController.EventScheduleWrapper>{wrapper};
        String jsonData = JSON.serialize(wrappers);
        
        Test.startTest();
        KenEventFormController.createEventSchedule(jsonData);
        Test.stopTest();
    }
    
    @isTest
    static void testCreateEventScheduleBlankRecords() {
        Test.startTest();
        try {
            KenEventFormController.createEventSchedule('');
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
    
    @isTest
    static void testCreateEventScheduleEmptyList() {
        List<KenEventFormController.EventScheduleWrapper> wrappers = new List<KenEventFormController.EventScheduleWrapper>();
        String jsonData = JSON.serialize(wrappers);
        
        Test.startTest();
        KenEventFormController.createEventSchedule(jsonData);
        Test.stopTest();
    }
    
    @isTest
    static void testCreateEventScheduleBlankEventId() {
        KenEventFormController.EventScheduleWrapper wrapper = new KenEventFormController.EventScheduleWrapper();
        wrapper.eventId = '';
        
        List<KenEventFormController.EventScheduleWrapper> wrappers = new List<KenEventFormController.EventScheduleWrapper>{wrapper};
        String jsonData = JSON.serialize(wrappers);
        
        Test.startTest();
        try {
            KenEventFormController.createEventSchedule(jsonData);
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
    
    @isTest
    static void testInsertSpeaker() {
        Account account = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        
        Ken_Events_Sessions_Enrollment__c enrollment = new Ken_Events_Sessions_Enrollment__c();
        enrollment.Person_Account__c = account.Id;
        enrollment.Speaker_Name__c = 'New Speaker';
        enrollment.Description__c = 'New Description';
        
        List<Ken_Events_Sessions_Enrollment__c> enrollments = new List<Ken_Events_Sessions_Enrollment__c>{enrollment};
        String jsonData = JSON.serialize(enrollments);
        
        Test.startTest();
        KenEventFormController.insertSpeaker(jsonData);
        Test.stopTest();
    }
    
    @isTest
    static void testGetEvent() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        
        Test.startTest();
        KenEventFormController.EventWrapper wrapper = KenEventFormController.getEvent(event.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testSaveEventNew() {
        Ken_Event_Master__c existingEvent = [SELECT Id, Name, Event_Current_Step__c, Language__c, Event_Status__c, Target_Topics__c, Event_Broucher__c, Broucher_Title__c, Description__c, createdDate, Event_Fee__c, No_Fee__c, RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Auto_Enroll_Target_Audience__c, Email_Subject__c, Email_Distribution_List__c, Email_Body__c, Schedule_DateTime__c, Email_Attachment__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c, Can_Alumni_Bring_Guests__c, Guest_Count__c, Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        
        KenEventFormController.EventWrapper wrapper = new KenEventFormController.EventWrapper(existingEvent);
        wrapper.Id = null;
        wrapper.eventTitle = 'New Event';
        wrapper.eventTypes = 'Workshop';
        wrapper.startDate = Date.today();
        wrapper.endDate = Date.today().addDays(1);
        wrapper.description = 'New Description';
        wrapper.agenda = 'New Agenda';
        wrapper.maximumNumberOfParticipants = 50;
        wrapper.currentStep = 1;
        wrapper.isPortal = false;
        
        String jsonData = JSON.serialize(wrapper);
        
        Test.startTest();
        Id eventId = KenEventFormController.saveEvent(jsonData);
        Test.stopTest();
    }
    
    @isTest
    static void testSaveEventPortalUserNoContact() {
        User portalUser = new User(
            FirstName = 'Portal',
            LastName = 'User',
            Email = 'portaluser2@test.com',
            Username = 'portaluser2@test.com',
            Alias = 'puser2',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id
        );
        insert portalUser;
        
        System.runAs(portalUser) {
            Ken_Event_Master__c existingEvent = [SELECT Id, Name, Event_Current_Step__c, Language__c, Event_Status__c, Target_Topics__c, Event_Broucher__c, Broucher_Title__c, Description__c, createdDate, Event_Fee__c, No_Fee__c, RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Auto_Enroll_Target_Audience__c, Email_Subject__c, Email_Distribution_List__c, Email_Body__c, Schedule_DateTime__c, Email_Attachment__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c, Can_Alumni_Bring_Guests__c, Guest_Count__c, Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
            
            KenEventFormController.EventWrapper wrapper = new KenEventFormController.EventWrapper(existingEvent);
            wrapper.eventTitle = 'Portal Event';
            wrapper.isPortal = true;
            
            String jsonData = JSON.serialize(wrapper);
            
            Test.startTest();
            try {
                KenEventFormController.saveEvent(jsonData);
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
    
    @isTest
    static void testUpdateFeeEventWise() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];

        Test.startTest();
        KenEventFormController.updateFee(true, event.Id, 1000, true, null);
        Test.stopTest();
    }
    
    @isTest
    static void testUpdateFeeSessionWise() {
        Ken_Schedule_Sessions__c session = [SELECT Id FROM Ken_Schedule_Sessions__c LIMIT 1];
        session.Session_Fee__c = 200;
        session.No_Fee__c = false;
        
        List<Ken_Schedule_Sessions__c> sessions = new List<Ken_Schedule_Sessions__c>{session};
        
        Test.startTest();
        KenEventFormController.updateFee(false, null, null, null, sessions);
        Test.stopTest();
    }
    
    @isTest
    static void testSearchContacts() {
        Test.startTest();
        List<Account> accounts = KenEventFormController.searchContacts();
        Test.stopTest();
    }
    
    @isTest
    static void testGetEventSessions() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];

        Test.startTest();
        List<Ken_Schedule_Sessions__c> sessions = KenEventFormController.getEventSessions(event.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testFetchLookupData() {
        Test.startTest();
        List<sObject> results = KenEventFormController.fetchLookupData('Test', 'Ken_Event_Master__c');
        Test.stopTest();
    }
    
    @isTest
    static void testGetPicklistValues() {
        List<String> fieldNames = new List<String>{'Event_Type__c', 'Event_Status__c'};
        
        Test.startTest();
        Map<String, List<Map<String, String>>> picklistValues = KenEventFormController.getPicklistValues('Ken_Event_Master__c', fieldNames);
        Test.stopTest();
    }
    
    @isTest
    static void testGetPicklistValuesInvalidObject() {
        List<String> fieldNames = new List<String>{'Test_Field__c'};
        
        Test.startTest();
        try {
            KenEventFormController.getPicklistValues('Invalid_Object__c', fieldNames);
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
    
    @isTest
    static void testSaveDataEventGroup() {
        Ken_Event_Master__c existingEvent = [SELECT Id, Name, Event_Current_Step__c, Language__c, Event_Status__c, Target_Topics__c, Event_Broucher__c, Broucher_Title__c, Description__c, createdDate, Event_Fee__c, No_Fee__c, RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c , Auto_Enroll_Target_Audience__c, Email_Subject__c, Email_Distribution_List__c, Email_Body__c, Schedule_DateTime__c, Email_Attachment__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c, Can_Alumni_Bring_Guests__c, Guest_Count__c, Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        
        KenEventFormController.EventWrapper wrapper = new KenEventFormController.EventWrapper(existingEvent);
        wrapper.Id = null;
        wrapper.eventGroupTitle = 'New Event Group';
        wrapper.isEventGroup = true;
        wrapper.startdate = Date.today();
        wrapper.enddate = Date.today().addDays(5);
        wrapper.eventTypes = 'Conference';
        wrapper.description = 'Group Description';
        wrapper.agenda = 'Group Agenda';
        wrapper.maximumNumberOfParticipants = 200;
        wrapper.image = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
        wrapper.imageFileName = 'test.png';
        
        String jsonData = JSON.serialize(wrapper);
        
        Test.startTest();
        String eventId = KenEventFormController.saveData(jsonData);
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteSessionsData() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        List<Date> selectedDates = new List<Date>{Date.today().addDays(1)};
        
        Test.startTest();
        KenEventFormController.deleteSessionsData(selectedDates, event.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteSessionsDataBlankEventId() {
        List<Date> selectedDates = new List<Date>{Date.today()};
        
        Test.startTest();
        try {
            KenEventFormController.deleteSessionsData(selectedDates, '');
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
    
    @isTest
    static void testEventWrapperConstructor() {
        Ken_Event_Master__c event = [SELECT Id, Name, Event_Current_Step__c, Language__c, Event_Status__c, Target_Topics__c, Event_Broucher__c, Broucher_Title__c, Description__c, createdDate, Event_Fee__c, No_Fee__c, RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Auto_Enroll_Target_Audience__c, Email_Subject__c, Email_Distribution_List__c, Email_Body__c, Schedule_DateTime__c, Email_Attachment__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c, Can_Alumni_Bring_Guests__c, Guest_Count__c, Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        
        Test.startTest();
        KenEventFormController.EventWrapper wrapper = new KenEventFormController.EventWrapper(event);
        Test.stopTest();
    }
    
    @isTest
    static void testEventWrapperGetRecord() {
        Ken_Event_Master__c existingEvent = [SELECT Id, Name, Event_Current_Step__c, Language__c, Event_Status__c, Target_Topics__c, Event_Broucher__c, Broucher_Title__c, Description__c, createdDate, Event_Fee__c, No_Fee__c, RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Auto_Enroll_Target_Audience__c, Email_Subject__c, Email_Distribution_List__c, Email_Body__c, Schedule_DateTime__c, Email_Attachment__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c, Can_Alumni_Bring_Guests__c, Guest_Count__c, Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        
        KenEventFormController.EventWrapper wrapper = new KenEventFormController.EventWrapper(existingEvent);
        wrapper.Id = existingEvent.Id;
        wrapper.eventTitle = 'Test Title';
        wrapper.eventTypes = 'Workshop';
        wrapper.eventStatus = 'Active';
        wrapper.eventLanguages = 'English';
        wrapper.startDate = Date.today();
        wrapper.endDate = Date.today().addDays(1);
        wrapper.description = 'Test Description';
        wrapper.agenda = 'Test Agenda';
        wrapper.eventExpectations = 'Test Expectations';
        wrapper.maximumNumberOfParticipants = 100;
        wrapper.targetAudienceApplicable = 'Students';
        wrapper.currentStep = 2;
        wrapper.broucher = 'data:application/pdf;base64,JVBERi0xLjQKJcfs';
        wrapper.broucherFileName = 'test.pdf';
        wrapper.image = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
        wrapper.imageFileName = 'test.png';
        wrapper.noFee = true;
        
        Test.startTest();
        Ken_Event_Master__c event = wrapper.getRecord();
        Test.stopTest();
    }
    
    @isTest
    static void testEventWrapperGetRecordWithUrlBroucher() {
        Ken_Event_Master__c existingEvent = [SELECT Id, Name, Event_Current_Step__c, Language__c, Event_Status__c, Target_Topics__c, Event_Broucher__c, Broucher_Title__c, Description__c, createdDate, Event_Fee__c, No_Fee__c, RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Auto_Enroll_Target_Audience__c, Email_Subject__c, Email_Distribution_List__c, Email_Body__c, Schedule_DateTime__c, Email_Attachment__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c, Can_Alumni_Bring_Guests__c, Guest_Count__c, Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        
        KenEventFormController.EventWrapper wrapper = new KenEventFormController.EventWrapper(existingEvent);
        wrapper.broucher = 'https://example.com/broucher.pdf';
        wrapper.broucherFileName = 'test.pdf';
        wrapper.image = 'https://example.com/image.png';
        
        Test.startTest();
        Ken_Event_Master__c event = wrapper.getRecord();
        Test.stopTest();
    }
    
    @isTest
    static void testEventWrapperGetRecordBase64WithoutComma() {
        Ken_Event_Master__c existingEvent = [SELECT Id, Name, Event_Current_Step__c, Language__c, Event_Status__c, Target_Topics__c, Event_Broucher__c, Broucher_Title__c, Description__c, createdDate, Event_Fee__c, No_Fee__c, RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Auto_Enroll_Target_Audience__c, Email_Subject__c, Email_Distribution_List__c, Email_Body__c, Schedule_DateTime__c, Email_Attachment__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c, Can_Alumni_Bring_Guests__c, Guest_Count__c, Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        
        KenEventFormController.EventWrapper wrapper = new KenEventFormController.EventWrapper(existingEvent);
        wrapper.broucher = 'JVBERi0xLjQKJcfs';
        wrapper.broucherFileName = 'test.pdf';
        wrapper.image = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==';
        wrapper.imageFileName = 'test.png';
        
        Test.startTest();
        Ken_Event_Master__c event = wrapper.getRecord();
        Test.stopTest();
    }
    
    @isTest
    static void testEventScheduleWrapperConstructor() {
        Ken_Schedule_Sessions__c session = [SELECT Id, What_to_Expect_From_Event__c, Name, Session_Broucher__c, Event_Reference__c, Start_DateTime__c, End_DateTime__c, Location_Type__c, Session_Link__c, Location__c, Session_Fee__c, No_Fee__c, Feedback_Trigger_Type__c, Feedback_Trigger_When__c, Feedback_End_DateTime__c, Broucher_Type__c, Broucher_Name__c, Meals__c, (SELECT Id, Person_Account__r.Name, Person_Account__c, Description__c, Speaker_Image__c, Schedule_Sessions__c, Speaker_Name__c, Speaker_Email__c, Send_Invite__c, Invite_Email_Sent__c FROM Event_Session_Account_Associations__r) FROM Ken_Schedule_Sessions__c LIMIT 1];

        Test.startTest();
        KenEventFormController.EventScheduleWrapper wrapper = new KenEventFormController.EventScheduleWrapper(session);
        Test.stopTest();

        System.assertEquals(session.Name, wrapper.name, 'Wrapper should carry the session name');
        System.assertEquals(1, wrapper.speakers.size(), 'Wrapper should map the speaker child record');
        System.assertEquals('test.speaker@example.com', wrapper.speakers[0].email, 'Speaker email should be mapped from Speaker_Email__c');
        System.assertEquals(true, wrapper.speakers[0].sendInvite, 'Send invite flag should be mapped from Send_Invite__c');
    }

    @isTest
    static void testSpeakerWrapperConstructor() {
        Ken_Events_Sessions_Enrollment__c enrollment = [SELECT Id, Person_Account__r.Name, Person_Account__c, Description__c, Speaker_Image__c, Schedule_Sessions__c, Speaker_Name__c, Speaker_Email__c, Send_Invite__c, Invite_Email_Sent__c FROM Ken_Events_Sessions_Enrollment__c LIMIT 1];

        Test.startTest();
        KenEventFormController.SpeakerWrapper wrapper = new KenEventFormController.SpeakerWrapper(enrollment);
        Test.stopTest();

        System.assertEquals(enrollment.Person_Account__r.Name, wrapper.name, 'Wrapper name should prefer the person account name');
        System.assertEquals('Test Speaker Description', wrapper.description, 'Wrapper should carry the speaker description');
        System.assertEquals('test.speaker@example.com', wrapper.email, 'Speaker email should be mapped from Speaker_Email__c');
        System.assertEquals(true, wrapper.sendInvite, 'Send invite flag should be mapped from Send_Invite__c');
    }
    
    @isTest
    static void testSpeakerWrapperGetSessionEnrollmentRecordUrlImage() {
        KenEventFormController.SpeakerWrapper wrapper = new KenEventFormController.SpeakerWrapper();
        wrapper.speakerImage = 'https://example.com/image.png';

        Test.startTest();
        Ken_Events_Sessions_Enrollment__c enrollment = wrapper.getSessionEnrollmentRecord();
        Test.stopTest();
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Questionnaire methods migrated from KenQuestionnaireControllerClass
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    @isTest
    static void testGetQuestionnaireByEventIdReturnsNullWhenNoQuestionnaire() {
        Ken_Event_Master__c eventRec = [SELECT Id FROM Ken_Event_Master__c LIMIT 1];

        Test.startTest();
        KenEventFormController.QuestionnaireDTO result = KenEventFormController.getQuestionnaireByEventId(eventRec.Id);
        Test.stopTest();

        System.assertEquals(null, result, 'No questionnaire linked yet â€” should return null');
    }

    @isTest
    static void testGetQuestionnaireByEventIdNullEventReturnsNull() {
        Test.startTest();
        KenEventFormController.QuestionnaireDTO result = KenEventFormController.getQuestionnaireByEventId(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Null event id should short-circuit to null');
    }

    @isTest
    static void testSaveQuestionnaireForEventCreatesAndLinks() {
        Ken_Event_Master__c eventRec = [SELECT Id, Name FROM Ken_Event_Master__c LIMIT 1];

        Test.startTest();
        Id questionSetId = KenEventFormController.saveQuestionnaireForEvent(
            eventRec.Id, 'Pre-event', qDtos('What did you expect?', 'Short Answer', true)
        );
        Test.stopTest();

        System.assertNotEquals(null, questionSetId);
        Ken_Event_Master__c reloaded = [
            SELECT Survey__c, Survey__r.Assessment_Question_Set__c
            FROM Ken_Event_Master__c WHERE Id = :eventRec.Id
        ];
        System.assertEquals(questionSetId, reloaded.Survey__r.Assessment_Question_Set__c,
            'Event survey should point at the newly-created question set');

        System.assertEquals(1, [
            SELECT COUNT() FROM AssessmentQuestion WHERE Ken_Question_Set__c = :questionSetId
        ], 'One question should be persisted');
    }

    @isTest
    static void testSaveQuestionnaireForEventNullEventThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenEventFormController.saveQuestionnaireForEvent(
                null, null, new List<KenEventFormController.QuestionSaveDTO>()
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Null event id must raise AuraHandledException');
    }

    @isTest
    static void testGetQuestionnaireByEventIdReturnsAfterSave() {
        Ken_Event_Master__c eventRec = [SELECT Id FROM Ken_Event_Master__c LIMIT 1];
        KenEventFormController.saveQuestionnaireForEvent(
            eventRec.Id, 'Read-back', qDtos('Anything to add?', 'Short Answer', false)
        );

        Test.startTest();
        KenEventFormController.QuestionnaireDTO result = KenEventFormController.getQuestionnaireByEventId(eventRec.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return the linked questionnaire after save');
    }

    @isTest
    static void testSaveQuestionnaireForSessionCreatesAndLinks() {
        Ken_Schedule_Sessions__c sessionRec = [SELECT Id, Name FROM Ken_Schedule_Sessions__c LIMIT 1];

        Test.startTest();
        Id questionSetId = KenEventFormController.saveQuestionnaireForSession(
            sessionRec.Id, null, qDtos('How was the session?', 'Rating', false)
        );
        Test.stopTest();

        System.assertNotEquals(null, questionSetId);
        Ken_Schedule_Sessions__c reloaded = [
            SELECT Survey__c, Survey__r.Assessment_Question_Set__c
            FROM Ken_Schedule_Sessions__c WHERE Id = :sessionRec.Id
        ];
        System.assertEquals(questionSetId, reloaded.Survey__r.Assessment_Question_Set__c,
            'Session survey should point at the newly-created question set');
    }

    @isTest
    static void wrapperSurveyPointsBackAtItsEventAndSession() {
        Ken_Schedule_Sessions__c sessionRec = [
            SELECT Id, Event_Reference__c FROM Ken_Schedule_Sessions__c WHERE Event_Reference__c != null LIMIT 1
        ];

        Test.startTest();
        KenEventFormController.saveQuestionnaireForEvent(
            sessionRec.Event_Reference__c, 'Event level',
            qDtos('Q1', 'Short Answer', false)
        );
        KenEventFormController.saveQuestionnaireForSession(
            sessionRec.Id, 'Session level',
            qDtos('Q2', 'Short Answer', false)
        );
        Test.stopTest();

        Ken_Event_Master__c ev = [SELECT Survey__c FROM Ken_Event_Master__c WHERE Id = :sessionRec.Event_Reference__c];
        Ken_Schedule_Sessions__c sess = [SELECT Survey__c FROM Ken_Schedule_Sessions__c WHERE Id = :sessionRec.Id];
        System.assertNotEquals(null, ev.Survey__c, 'Event should own a wrapper survey.');
        System.assertNotEquals(null, sess.Survey__c, 'Session should own a wrapper survey.');

        Ken_Survey__c eventSurvey = [SELECT Event__c, Session__c FROM Ken_Survey__c WHERE Id = :ev.Survey__c];
        System.assertEquals(sessionRec.Event_Reference__c, eventSurvey.Event__c,
            'Event survey must link back to its event so the record page shows it.');
        System.assertEquals(null, eventSurvey.Session__c,
            'An event-level survey belongs to no session.');

        Ken_Survey__c sessionSurvey = [SELECT Event__c, Session__c FROM Ken_Survey__c WHERE Id = :sess.Survey__c];
        System.assertEquals(sessionRec.Id, sessionSurvey.Session__c,
            'Session feedback survey must link back to its session.');
        System.assertEquals(sessionRec.Event_Reference__c, sessionSurvey.Event__c,
            'Session feedback survey must also link back to the parent event.');
    }

    @isTest
    static void testSaveQuestionnaireForSessionNullSessionThrows() {
        Boolean threw = false;
        Test.startTest();
        try {
            KenEventFormController.saveQuestionnaireForSession(
                null, null, new List<KenEventFormController.QuestionSaveDTO>()
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Null session id must raise AuraHandledException');
    }

    @isTest
    static void testSaveQuestionnaireForEventReconcilesQuestions() {
        Ken_Event_Master__c eventRec = [SELECT Id FROM Ken_Event_Master__c LIMIT 1];

        List<KenEventFormController.QuestionSaveDTO> initial = qDtos('Q1', 'Short Answer', false);
        initial.addAll(qDtos('Q2', 'Short Answer', false));
        Id qId = KenEventFormController.saveQuestionnaireForEvent(eventRec.Id, 'Initial', initial);
        System.assertEquals(2, [
            SELECT COUNT() FROM AssessmentQuestion WHERE Ken_Question_Set__c = :qId
        ], 'Both questions should be persisted on the first save');

        Test.startTest();
        Id sameSetId = KenEventFormController.saveQuestionnaireForEvent(
            eventRec.Id, 'Initial', qDtos('Q1', 'Short Answer', false)
        );
        Test.stopTest();

        System.assertEquals(qId, sameSetId, 'Re-saving reuses the same question set');
        System.assertEquals(1, [
            SELECT COUNT() FROM AssessmentQuestion WHERE Ken_Question_Set__c = :qId
        ], 'The dropped question should no longer be assigned');
    }

    @isTest
    static void testSavePreEventSurveyData() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];
        Ken_Schedule_Sessions__c session = [SELECT Id, Start_DateTime__c FROM Ken_Schedule_Sessions__c LIMIT 1];
        // Day derived from the session's single stored instant.
        Date d = session.Start_DateTime__c.date();
        String dateKey = String.valueOf(d.year()) + '-' +
            (d.month() < 10 ? '0' : '') + String.valueOf(d.month()) + '-' +
            (d.day() < 10 ? '0' : '') + String.valueOf(d.day());
        Map<String, List<String>> mealsByDate = new Map<String, List<String>>{
            dateKey => new List<String>{ 'Breakfast', 'Lunch' }
        };

        Test.startTest();
        KenEventFormController.savePreEventSurveyData(
            event.Id, true, true, true, 'Vegetarian;Vegan', JSON.serialize(mealsByDate)
        );
        Test.stopTest();

        Ken_Event_Master__c reloaded = [
            SELECT Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c
            FROM Ken_Event_Master__c WHERE Id = :event.Id
        ];
        System.assertEquals(true, reloaded.Offer_Meals__c, 'Offer meals should be enabled');
        System.assertEquals(true, reloaded.Make_Meals_Paid__c, 'Meals paid should be enabled');
        System.assertEquals('Vegetarian;Vegan', reloaded.Dietary_Preferences__c, 'Dietary prefs should be saved');

        Ken_Schedule_Sessions__c reloadedSession = [SELECT Meals__c FROM Ken_Schedule_Sessions__c WHERE Id = :session.Id];
        System.assert(reloadedSession.Meals__c != null && reloadedSession.Meals__c.contains('Breakfast'),
            'Meals should be set on the session for its date');
    }

    @isTest
    static void testSavePreEventSurveyDataNoMeals() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];

        Test.startTest();
        KenEventFormController.savePreEventSurveyData(event.Id, false, false, false, null, null);
        Test.stopTest();

        Ken_Event_Master__c reloaded = [SELECT Offer_Meals__c, Make_Meals_Paid__c FROM Ken_Event_Master__c WHERE Id = :event.Id];
        System.assertEquals(false, reloaded.Offer_Meals__c, 'Offer meals should be disabled');
        System.assertEquals(false, reloaded.Make_Meals_Paid__c, 'Meals paid should be disabled');
    }

    @isTest
    static void testSaveMealFee() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];

        Test.startTest();
        KenEventFormController.saveMealFee(event.Id, 250);
        Test.stopTest();

        Ken_Event_Master__c reloaded = [SELECT Meal_Fee__c FROM Ken_Event_Master__c WHERE Id = :event.Id];
        System.assertEquals(250, reloaded.Meal_Fee__c, 'Meal fee should be saved on the event');
    }

    @isTest
    static void testSaveEventPortalStampsConstituentRole() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];
        Ken_Event_Master__c existingEvent = [SELECT Id, Name, Event_Current_Step__c, Language__c, Event_Status__c, Target_Topics__c, Event_Broucher__c, Broucher_Title__c, Description__c, createdDate, Event_Fee__c, No_Fee__c, RecordTypeId, End_Date__c, Event_Type__c, Event_banner__c, Evvent_Group__c, Is_Active__c, Location__c, Max_Allowed_Participants__c, Auto_Enroll_Target_Audience__c, Email_Subject__c, Email_Distribution_List__c, Email_Body__c, Schedule_DateTime__c, Email_Attachment__c, Target_Audience_Applicable__c, Start_Date__c, What_to_Expect_From_Event__c, Can_Alumni_Bring_Guests__c, Guest_Count__c, Offer_Meals__c, Make_Meals_Paid__c, Collect_Dietary_Preferences__c, Dietary_Preferences__c, Meal_Fee__c FROM Ken_Event_Master__c WHERE Name = 'Test Event' LIMIT 1];

        KenEventFormController.EventWrapper wrapper = new KenEventFormController.EventWrapper(existingEvent);
        wrapper.Id = null;
        wrapper.eventTitle = 'Portal Role Test Event';
        wrapper.eventTypes = 'Workshop';
        wrapper.startDate = Date.today();
        wrapper.endDate = Date.today().addDays(1);
        wrapper.description = 'Test portal event';
        wrapper.maximumNumberOfParticipants = 50;
        wrapper.currentStep = 1;
        wrapper.isPortal = true;

        String jsonData = JSON.serialize(wrapper);

        KenConstituentRoleService.testCurrentRoleId = cr.Id;
        Test.startTest();
        Id eventId = KenEventFormController.saveEvent(jsonData);
        Test.stopTest();

        Ken_Event_Master__c created = [SELECT Constituent_Role__c FROM Ken_Event_Master__c WHERE Id = :eventId];
        System.assertEquals(cr.Id, created.Constituent_Role__c, 'Constituent_Role__c must be stamped when isPortal=true');
    }

    @isTest
    static void testSaveQuestionnaireForEventMirrorsAudienceOntoWrapperSurvey() {
        Ken_Event_Master__c eventRec = [SELECT Id FROM Ken_Event_Master__c LIMIT 1];
        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Event Audience');
        insert seg;
        update new Ken_Event_Master__c(Id = eventRec.Id, Segmentation__c = seg.Id);

        Test.startTest();
        KenEventFormController.saveQuestionnaireForEvent(
            eventRec.Id,
            'Audience mirror', qDtos('Q1', 'Short Answer', false)
        );
        Test.stopTest();

        Ken_Event_Master__c reloaded = [SELECT Survey__c FROM Ken_Event_Master__c WHERE Id = :eventRec.Id];
        System.assertNotEquals(null, reloaded.Survey__c, 'Wrapper survey should be created');
        System.assertEquals(seg.Id,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :reloaded.Survey__c].Segmentation__c,
            'Event audience must be mirrored onto the wrapper survey');
    }

    @isTest
    static void testSaveQuestionnaireForSessionMirrorsAudienceOntoWrapperSurvey() {
        Ken_Schedule_Sessions__c sessionRec = [
            SELECT Id, Event_Reference__c
            FROM Ken_Schedule_Sessions__c
            WHERE Event_Reference__c != null
            LIMIT 1
        ];
        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Session Audience');
        insert seg;
        update new Ken_Event_Master__c(
            Id = sessionRec.Event_Reference__c,
            Segmentation__c = seg.Id
        );

        Test.startTest();
        KenEventFormController.saveQuestionnaireForSession(
            sessionRec.Id,
            null, qDtos('Rate it', 'Rating', false)
        );
        Test.stopTest();

        Ken_Schedule_Sessions__c reloaded = [
            SELECT Survey__c FROM Ken_Schedule_Sessions__c WHERE Id = :sessionRec.Id
        ];
        System.assertNotEquals(null, reloaded.Survey__c, 'Feedback wrapper survey should be created');
        System.assertEquals(seg.Id,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :reloaded.Survey__c].Segmentation__c,
            'Parent event audience must be mirrored onto the feedback survey');
    }

    @isTest
    static void testCreateEventSegmentationBackfillsExistingWrapperSurvey() {
        Ken_Event_Master__c eventRec = [SELECT Id FROM Ken_Event_Master__c LIMIT 1];
        KenEventFormController.saveQuestionnaireForEvent(
            eventRec.Id,
            'Backfill', qDtos('Q1', 'Short Answer', false)
        );
        Ken_Event_Master__c withSurvey = [SELECT Survey__c FROM Ken_Event_Master__c WHERE Id = :eventRec.Id];
        System.assertEquals(null,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :withSurvey.Survey__c].Segmentation__c,
            'Nothing to mirror before an audience is chosen');

        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Late Audience');
        insert seg;

        Test.startTest();
        KenEventFormController.createEventSegmentation(eventRec.Id, seg.Id);
        Test.stopTest();

        System.assertEquals(seg.Id,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :withSurvey.Survey__c].Segmentation__c,
            'Choosing an audience later must backfill the wrapper survey');
    }

    @isTest
    static void testCreateEventSegmentationRepointsWrapperSurveyAudience() {
        Ken_Event_Master__c eventRec = [SELECT Id FROM Ken_Event_Master__c LIMIT 1];
        Ken_Segmentation__c first = new Ken_Segmentation__c(Name = 'First Audience');
        Ken_Segmentation__c second = new Ken_Segmentation__c(Name = 'Second Audience');
        insert new List<Ken_Segmentation__c>{ first, second };

        KenEventFormController.createEventSegmentation(eventRec.Id, first.Id);
        KenEventFormController.saveQuestionnaireForEvent(
            eventRec.Id,
            'Repoint', qDtos('Q1', 'Short Answer', false)
        );
        Ken_Event_Master__c withSurvey = [SELECT Survey__c FROM Ken_Event_Master__c WHERE Id = :eventRec.Id];

        Test.startTest();
        KenEventFormController.createEventSegmentation(eventRec.Id, second.Id);
        Test.stopTest();

        System.assertEquals(second.Id,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :withSurvey.Survey__c].Segmentation__c,
            'Wrapper survey must follow the new audience, not keep the old one');
    }

    /**
     * @description Clearing an event's audience must reach its wrapper surveys too, or a
     *              feedback form keeps targeting people the event has dropped.
     */
    @isTest
    static void testClearedEventAudienceClearsWrapperSurvey() {
        Ken_Event_Master__c eventRec = [SELECT Id FROM Ken_Event_Master__c LIMIT 1];
        Ken_Segmentation__c seg = new Ken_Segmentation__c(Name = 'Dropped Audience');
        insert seg;

        KenEventFormController.createEventSegmentation(eventRec.Id, seg.Id);
        KenEventFormController.saveQuestionnaireForEvent(
            eventRec.Id,
            'Clearing', qDtos('Q1', 'Short Answer', false)
        );
        Ken_Event_Master__c withSurvey = [SELECT Survey__c FROM Ken_Event_Master__c WHERE Id = :eventRec.Id];
        System.assertEquals(seg.Id,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :withSurvey.Survey__c].Segmentation__c,
            'Wrapper should start out carrying the event audience');

        Test.startTest();
        update new Ken_Event_Master__c(Id = eventRec.Id, Segmentation__c = null);
        KenEventFormController.syncEventAudienceToWrapperSurveys(eventRec.Id);
        Test.stopTest();

        System.assertEquals(null,
            [SELECT Segmentation__c FROM Ken_Survey__c WHERE Id = :withSurvey.Survey__c].Segmentation__c,
            'A cleared event audience must be cleared on the wrapper survey');
    }

    private static List<KenEventFormController.QuestionSaveDTO> qDtos(String text, String type, Boolean required) {
        KenEventFormController.QuestionSaveDTO q = new KenEventFormController.QuestionSaveDTO();
        q.text = text;
        q.questionType = type;
        q.required = required;
        q.choices = new List<KenAssessmentSurveyService.ChoiceRow>();
        return new List<KenEventFormController.QuestionSaveDTO>{ q };
    }

    // The wizard stamps Draft/In Review on every save, so an edit must not be
    // allowed to walk an approved event back out of Approved - everything public
    // is gated on that value.
    @isTest
    static void testSaveEventKeepsApprovalOnEdit() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];
        Ken_Event_Master__c approved = new Ken_Event_Master__c(
            Name = 'Approved Event',
            Event_Type__c = 'Workshop',
            Start_Date__c = Date.today().addDays(10),
            End_Date__c = Date.today().addDays(10),
            Event_Status__c = 'Approved',
            Is_Active__c = true,
            Constituent_Role__c = cr.Id
        );
        insert approved;

        String payload = JSON.serialize(new Map<String, Object>{
            'Id' => approved.Id,
            'eventTitle' => 'Approved Event',
            'image' => 'https://example.com/new-banner.png',
            'imageFileName' => 'NewBanner.png',
            'eventStatus' => 'Draft',
            'isPortal' => false
        });

        Test.startTest();
        KenEventFormController.saveEvent(payload);
        Test.stopTest();

        System.assertEquals('Approved',
            [SELECT Event_Status__c FROM Ken_Event_Master__c WHERE Id = :approved.Id].Event_Status__c,
            'Editing an approved event must not send it back through approval');
    }

    // The guard is about approved events only: a draft the host submits still has
    // to move to In Review, or nothing would ever reach an approver.
    @isTest
    static void testSaveEventStillAdvancesUnapprovedStatus() {
        ConstituentRole cr = [SELECT Id FROM ConstituentRole LIMIT 1];
        Ken_Event_Master__c draft = new Ken_Event_Master__c(
            Name = 'Draft Event',
            Event_Type__c = 'Workshop',
            Start_Date__c = Date.today().addDays(10),
            End_Date__c = Date.today().addDays(10),
            Event_Status__c = 'Draft',
            Constituent_Role__c = cr.Id
        );
        insert draft;

        String payload = JSON.serialize(new Map<String, Object>{
            'Id' => draft.Id,
            'eventTitle' => 'Draft Event',
            'eventStatus' => 'In Review',
            'isPortal' => false
        });

        Test.startTest();
        KenEventFormController.saveEvent(payload);
        Test.stopTest();

        System.assertEquals('In Review',
            [SELECT Event_Status__c FROM Ken_Event_Master__c WHERE Id = :draft.Id].Event_Status__c,
            'Submitting a draft must still move it into review');
    }
}