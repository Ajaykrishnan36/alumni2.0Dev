@isTest
public class PortalEventControllerTest {
    
    @TestSetup
    static void dataSetup() {
        
        UserRole userRole = [SELECT Id, Name FROM UserRole where Name='Academic Associate' LIMIT 1];
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalAccountOwner = new User(
            Username = 'portalowner' + System.currentTimeMillis() + '@test.com',
            Alias = 'ownr',
            Email = 'portalowner@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Owner',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = [Select Id from Profile where Name='System Administrator' LIMIt 1].Id,
            UserRoleId = userRole.Id
        );
        insert portalAccountOwner;
        
        Account portalAccount;
        Contact contact;
        System.runAs(portalAccountOwner){
            portalAccount = new Account(Name = 'Portal Account');
            insert portalAccount;
            
            contact = new Contact(LastName = 'Portal User', AccountId = portalAccount?.Id);
            insert contact;

            Ken_Event_Master__c eventActiveStudent = new Ken_Event_Master__c(
                Name = 'Active Student Event',
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addDays(2),
                Event_Type__c = 'Seminar',
                Event_Status__c = 'Approved',
                Is_Active__c = true,
                Target_Audience_Applicable__c = 'Student',
                Event_banner__c = 'https://testimg.com/img.png',
                Location__c = 'Room 1'
            );
            insert eventActiveStudent;
            
            Ken_Event_Master__c hostedEvent = new Ken_Event_Master__c(
                Name = 'Hosted Event',
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addDays(1),
                Event_Type__c = 'Workshop',
                Event_Status__c = 'Pending Approval',
                Is_Active__c = true,
                Target_Audience_Applicable__c = 'Student',
              // Contact__c = contact.Id,
                Event_banner__c = 'https://hostedimg.com/img.png',
                Location__c = 'Room 2'
            );
            insert hostedEvent;
            
            	Ken_Schedule_Sessions__c session1 = new Ken_Schedule_Sessions__c(
                Name = 'Morning Session',
                Start_Date__c = Date.today(),
                End_Date__c = Date.today(),
                Start_Time__c = Time.newInstance(9,0,0,0),
                End_Time__c = Time.newInstance(10,0,0,0),
                Event_Reference__c = eventActiveStudent.Id
            );
            insert session1;

            Ken_Schedule_Sessions__c session2 = new Ken_Schedule_Sessions__c(
                Name = 'Evening Session',
                Start_Date__c = Date.today(),
                End_Date__c = Date.today(),
                Start_Time__c = Time.newInstance(17,0,0,0),
                End_Time__c = Time.newInstance(18,0,0,0),
                Event_Reference__c = eventActiveStudent.Id
            );
            insert session2;

            Ken_Events_Sessions_Enrollment__c speaker1 = new Ken_Events_Sessions_Enrollment__c(
                Speaker_Name__c = 'Speaker One',
                Description__c = 'Description One'
               // Ken_Schedule_Sessions__c = session1.Id
            );
            insert speaker1;
            
            Ken_Event_Booking__c booking = new Ken_Event_Booking__c(
                Contact__c = contact.Id,
                Schedules_Sessions__c = session1.Id,
                Type__c = 'Registered'
            );
            insert booking;
        }
    }
    
    @isTest
    static void testGetAllEvents() {
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
           // ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
				Ken_Event_Master__c eventActiveStudent = new Ken_Event_Master__c(
                Name = 'Active Student Event',
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addDays(2),
                Event_Type__c = 'Seminar',
                Event_Status__c = 'Approved',
                Is_Active__c = true,
                Target_Audience_Applicable__c = 'Student',
                Event_banner__c = 'https://testimg.com/img.png',
                Location__c = 'Room 1'
            );
            insert eventActiveStudent;
            List<PortalEventController.EventWrapper> events = PortalEventController.getAllEvents();
            Test.stopTest();
        }
    }
    
    @isTest
    static void testGetHostedEvents() {
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            List<Ken_Event_Master__c> events = PortalEventController.getHostedEvents();
            Test.stopTest();
        }
    }
    
    @isTest
    static void testGetHostedEventsNoContact() {
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            try {
                PortalEventController.getHostedEvents();
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
    
    @isTest
    static void testGetEventSessions() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Active Student Event' LIMIT 1];
        Test.startTest();
        List<Ken_Schedule_Sessions__c> sessions = PortalEventController.getEventSessions(event.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testGetEventSessionsNoSessions() {
        Ken_Event_Master__c event = new Ken_Event_Master__c(
            Name = 'No Session Event',
            Start_Date__c = Date.today(),
            End_Date__c = Date.today(),
            Is_Active__c = true,
            Target_Audience_Applicable__c = 'Student'
        );
        insert event;
        Test.startTest();
        try {
            List<Ken_Schedule_Sessions__c> sessions = PortalEventController.getEventSessions(event.Id);
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetRegisteredSessions() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Active Student Event' LIMIT 1];
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            List<Ken_Schedule_Sessions__c> sessions = PortalEventController.getRegisteredSessions(event.Id);
            Test.stopTest();
        }
    }
    
    @isTest
    static void testGetRegisteredSessionsNoContact() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Active Student Event' LIMIT 1];
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            try {
                PortalEventController.getRegisteredSessions(event.Id);
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
    
    @isTest
    static void testGetEventDetails() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Active Student Event' LIMIT 1];
        Test.startTest();
        PortalEventController.EventDetailWrapper wrapper = PortalEventController.getEventDetails(event.Id);
        Test.stopTest();
    }
    
    @isTest
    static void testGetEventDetailsBlankId() {
        Test.startTest();
        try {
            PortalEventController.getEventDetails('');
        } catch (AuraHandledException e) {
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetEventSchedules() {
        Ken_Event_Master__c event = [SELECT Id FROM Ken_Event_Master__c WHERE Name = 'Active Student Event' LIMIT 1];
        
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();

            Ken_Event_Master__c eventActiveStudent = new Ken_Event_Master__c(
                Name = 'Active Student Event',
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addDays(2),
                Event_Type__c = 'Seminar',
                Event_Status__c = 'Approved',
                Is_Active__c = true,
                Target_Audience_Applicable__c = 'Student',
                Event_banner__c = 'https://testimg.com/img.png',
                Location__c = 'Room 1'
            );
            insert eventActiveStudent;

			Ken_Schedule_Sessions__c session1 = new Ken_Schedule_Sessions__c(
                Name = 'Evening Session',
                Start_Date__c = Date.today(),
                End_Date__c = Date.today(),
                Start_Time__c = Time.newInstance(17,0,0,0),
                End_Time__c = Time.newInstance(18,0,0,0),
                Event_Reference__c = eventActiveStudent.Id
            );
            insert session1;

            Ken_Events_Sessions_Enrollment__c speaker1 = new Ken_Events_Sessions_Enrollment__c(
                Speaker_Name__c = 'Speaker One',
                Description__c = 'Description One'
            );
            insert speaker1;

            List<PortalEventController.ScheduleWrapper> schedules = PortalEventController.getEventSchedules(eventActiveStudent.Id);
            Test.stopTest();
        }
    }
    
    @isTest
    static void testGetEventSchedulesBlankId() {
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            try {
                PortalEventController.getEventSchedules('');
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
    
    @isTest
    static void testSaveRegistrations() {
        Ken_Schedule_Sessions__c session = [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Name = 'Evening Session' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];
        List<Ken_Event_Booking__c> existingBookings = [Select Id, Contact__c, Schedules_Sessions__c, Type__c from Ken_Event_Booking__c where Contact__c= :testContact.Id AND Schedules_Sessions__c  =:session.Id];
        User portalUser;
        User u = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND Alias='ownr' LIMIT 1];
        System.runAs(u) {
            Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
            
            portalUser = new User(
                Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
                Alias = 'puser',
                Email = 'portaluser@test.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Portal',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/New_York',
                ProfileId = portalProfile.Id,
                ContactId = testContact.Id,
                CommunityNickname = 'portalnick'
            );
            insert portalUser;
            
            // Assign permission set in the same runAs block
            PermissionSet ps = [
                SELECT Id 
                FROM PermissionSet 
                WHERE Name = 'Community_Student_Login' 
                LIMIT 1
            ];
            
            insert new PermissionSetAssignment(
                PermissionSetId = ps.Id,
                AssigneeId = portalUser.Id
            );
        }
        
        // Now run the test with the user that has permission set assigned
        System.runAs(portalUser) {
            Test.startTest();
            String result = PortalEventController.saveRegistrations(new List<Id>{session.Id});
            Test.stopTest();
        }
    }
    
    @isTest
    static void testSaveRegistrationsEmpty() {
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            try {
                PortalEventController.saveRegistrations(new List<Id>());
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
    
    @isTest
    static void testSaveRegistrationsNoContact() {
        	Ken_Schedule_Sessions__c session = [SELECT Id FROM Ken_Schedule_Sessions__c LIMIT 1];
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            try {
                PortalEventController.saveRegistrations(new List<Id>{session.Id});
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
    
    @isTest
    static void testCancelRegistrations() {
        Ken_Schedule_Sessions__c session = [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Name = 'Morning Session' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Portal User' LIMIT 1];
        
        User portalUser;
        User u = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND Alias='ownr' LIMIT 1];
        System.runAs(u) {
            Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
            
            portalUser = new User(
                Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
                Alias = 'puser',
                Email = 'portaluser@test.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Portal',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/New_York',
                ProfileId = portalProfile.Id,
                ContactId = testContact.Id,
                CommunityNickname = 'portalnick'
            );
            insert portalUser;
            
            // Assign permission set in the same runAs block
            PermissionSet ps = [
                SELECT Id 
                FROM PermissionSet 
                WHERE Name = 'Community_Student_Login' 
                LIMIT 1
            ];
            
            insert new PermissionSetAssignment(
                PermissionSetId = ps.Id,
                AssigneeId = portalUser.Id
            );
        }
        System.runAs(portalUser) {
            Test.startTest();
            String result = PortalEventController.cancelRegistrations(new List<Id>{session.Id});
            Test.stopTest();
        }
    }
    
    @isTest
    static void testCancelRegistrationsNoActive() {
        Ken_Schedule_Sessions__c session = [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Name = 'Evening Session' LIMIT 1];
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            try {
                PortalEventController.cancelRegistrations(new List<Id>{session.Id});
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
    
    @isTest
    static void testCancelRegistrationsNoContact() {
        Ken_Schedule_Sessions__c session = [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Name = 'Morning Session' LIMIT 1];
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            try {
                PortalEventController.cancelRegistrations(new List<Id>{session.Id});
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
    
    @isTest
    static void testGetContactRegisteredSessions() {
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            List<Ken_Schedule_Sessions__c> sessions = PortalEventController.getContactRegisteredSessions();
            Test.stopTest();
        }
    }
    
    @isTest
    static void testGetContactRegisteredSessionsNoContact() {
        Profile portalProfile = [SELECT Id FROM Profile WHERE Name = 'Student' LIMIT 1];
        
        User portalUser = new User(
            Username = 'portaluser' + System.currentTimeMillis() + '@test.com',
            Alias = 'puser',
            Email = 'portaluser@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Portal',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/New_York',
            ProfileId = portalProfile.Id,
            ContactId = [Select Id from Contact LIMIt 1].Id,
            CommunityNickname = 'portalnick'
        );
        
        System.runAs(portalUser) {
            Test.startTest();
            try {
                PortalEventController.getContactRegisteredSessions();
            } catch (AuraHandledException e) {
            }
            Test.stopTest();
        }
    }
}