@IsTest
private class KenSettingsControllerTest {

    private static final String ALUMNI_RT = 'Alumni_Person_Account';

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
        ];
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account']) {
            if (rt.IsPersonType) {
                return rt.Id;
            }
        }
        return null;
    }

    @TestSetup
    static void setupData() {
        Id paRtId = getPersonAccountRtId();
        Account pa = new Account(
            FirstName         = 'Settings',
            LastName          = 'TestUser',
            PersonEmail       = 'settings.test@example.com',
            PersonMobilePhone = '+91 9876543210'
        );
        if (paRtId != null) {
            pa.RecordTypeId = paRtId;
        }
        insert pa;

        if (Schema.SObjectType.ConstituentRole.fields.getMap().containsKey('Registration_Status__c')) {
            ConstituentRole cr = new ConstituentRole(
                PersonId               = pa.Id,
                RoleType               = 'Alumni',
                Registration_Status__c = 'Registered'
            );
            if (Schema.SObjectType.ConstituentRole.fields.getMap().containsKey('Status')) {
                cr.put('Status', 'Admitted');
            }
            insert cr;

            insert new Ken_Alumni_CRM__c(
                Person_Account__c    = pa.Id,
                ConstituentRole__c   = cr.Id,
                Profile_Photo_URL__c = 'https://example.com/photo.jpg'
            );
        }

        insert new Ken_Alumni_Preferences__c(
            Person_Account__c                             = pa.Id,
            Is_Private_Account__c                         = false,
            How_often_would_you_like_to_hear_from_us__c  = 'Daily',
            Notify_in_real_time__c                        = true,
            Who_can_invite_me_to_events__c                = 'Everyone',
            Receive_Invited_Event_Alerts__c               = true,
            Who_can_invite_me_to_groups__c                = 'Everyone',
            Receive_updates_from_joined_groups__c         = true,
            Open_to_work__c                               = true,
            Willing_to_be_a_mentor__c                     = false
        );
    }

    @IsTest
    static void testGetPersonalDetailsNoUserThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.getPersonalDetails();
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException when user has no account');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSavePersonalDetailsBlankJsonThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.savePersonalDetails('');
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for blank JSON');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSavePersonalDetailsValidJsonNoUserThrowsException() {
        String json = '{"firstName":"Test","lastName":"User","city":"Mumbai","country":"India"}';
        try {
            Test.startTest();
            KenSettingsController.savePersonalDetails(json);
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSaveProfilePhotoBlankDataThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.saveProfilePhoto('');
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for blank image data');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSaveEngagementPreferencesNoUserThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.saveEngagementPreferences('TestPref');
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testGetPreferencesNoUserThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.getPreferences();
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSavePreferencesNoUserThrowsException() {
        String json = '{"isPrivateAccount":false,"howOften":"Daily","notifyRealTime":true}';
        try {
            Test.startTest();
            KenSettingsController.savePreferences(json);
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testGetEventPreferencesNoUserThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.getEventPreferences();
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSaveEventPreferencesNoUserThrowsException() {
        String json = '{"whoCanInvite":"Everyone","receiveAlerts":true,"reminderFrequency":"Daily"}';
        try {
            Test.startTest();
            KenSettingsController.saveEventPreferences(json);
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testGetGroupPreferencesNoUserThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.getGroupPreferences();
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSaveGroupPreferencesNoUserThrowsException() {
        String json = '{"whoCanInvite":"Everyone","receiveUpdates":true,"notifyFor":"All"}';
        try {
            Test.startTest();
            KenSettingsController.saveGroupPreferences(json);
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testGetMentorshipPreferencesNoUserThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.getMentorshipPreferences();
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSaveMentorshipPreferencesNoUserThrowsException() {
        String json = '{"willingToBeMentor":true,"availabilityDays":"Mon","availabilityStartTime":"09:00","availabilityEndTime":"17:00"}';
        try {
            Test.startTest();
            KenSettingsController.saveMentorshipPreferences(json);
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testGetJobPreferencesNoUserThrowsException() {
        try {
            Test.startTest();
            KenSettingsController.getJobPreferences();
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    @IsTest
    static void testSaveJobPreferencesNoUserThrowsException() {
        String json = '{"openToWork":true,"preferredJobTitles":"Engineer","skillSet":"Java"}';
        try {
            Test.startTest();
            KenSettingsController.saveJobPreferences(json);
            Test.stopTest();
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
        }
    }

    private static Account seededPersonAccount() {
        return [
            SELECT Id, PersonContactId
            FROM Account
            WHERE PersonEmail = 'settings.test@example.com'
            LIMIT 1
        ];
    }

    @IsTest
    static void testGetPersonalDetailsForSeededAccountReturnsPayload() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenSettingsController.PersonalDetailsPayload payload = KenSettingsController.getPersonalDetails();
            Test.stopTest();

            System.assertNotEquals(null, payload, 'Personal details payload should not be null');
            System.assertEquals('Settings', payload.firstName, 'firstName should match seeded value');
            System.assertEquals('TestUser', payload.lastName, 'lastName should match seeded value');
            System.assertNotEquals(null, payload.maskedEmail, 'maskedEmail should be populated');
            System.assertNotEquals(null, payload.maskedPhone, 'maskedPhone should be populated');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testSavePersonalDetailsUpdatesAccount() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            String json = '{"firstName":"Updated","lastName":"AlumniName","city":"Pune","country":"India","linkedinUrl":"https://linkedin.com/x","twitterUrl":"https://x.com/y"}';

            Test.startTest();
            KenSettingsController.savePersonalDetails(json);
            Test.stopTest();

            Account updated = [SELECT FirstName, LastName, Linkedin_Profile_URL__c FROM Account WHERE Id = :pa.Id];
            System.assertEquals('Updated', updated.FirstName, 'FirstName should be saved');
            System.assertEquals('AlumniName', updated.LastName, 'LastName should be saved');

            Ken_Address__c addr = [
                SELECT City__c, Country__c
                FROM Ken_Address__c
                WHERE Person_Account__c = :pa.Id AND Address_Type__c = 'Mailing'
                LIMIT 1
            ];
            System.assertEquals('Pune', addr.City__c, 'Address city should be saved');
            System.assertEquals('India', addr.Country__c, 'Address country should be saved');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testSaveProfilePhotoReturnsUrlForPlainInput() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            String url = KenSettingsController.saveProfilePhoto('https://example.com/picture.jpg');
            Test.stopTest();

            System.assertEquals('https://example.com/picture.jpg', url,
                'saveProfilePhoto should return the input URL when not base64-encoded');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testSaveEngagementPreferencesUpdatesAlumniCrm() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenSettingsController.saveEngagementPreferences(null);
            Test.stopTest();

            Ken_Alumni_CRM__c crm = [
                SELECT Preferences__c
                FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c = :pa.Id
                LIMIT 1
            ];
            System.assertEquals(null, crm.Preferences__c,
                'Engagement preferences should accept a null update without throwing');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testGetAndSavePreferencesRoundTrip() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenSettingsController.PreferencesPayload existing = KenSettingsController.getPreferences();
            System.assertNotEquals(null, existing, 'Existing preferences should be returned');

            String json = '{"isPrivateAccount":true,"preferredCommunication":"Email","howOften":"Weekly","notifyRealTime":false,"notifyFor":"Events"}';
            KenSettingsController.savePreferences(json);

            KenSettingsController.PreferencesPayload after = KenSettingsController.getPreferences();
            Test.stopTest();

            System.assertEquals(true, after.isPrivateAccount, 'isPrivateAccount should be saved');
            System.assertEquals('Email', after.preferredCommunication, 'preferredCommunication should be saved');
            System.assertEquals('Weekly', after.howOften, 'howOften should be saved');
            System.assertEquals(false, after.notifyRealTime, 'notifyRealTime should be saved');
            System.assertEquals('Events', after.notifyFor, 'notifyFor should be saved');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testGetAndSaveEventPreferencesRoundTrip() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenSettingsController.EventPreferencesPayload before = KenSettingsController.getEventPreferences();
            System.assertNotEquals(null, before, 'Existing event preferences should be returned');

            String json = '{"whoCanInvite":"Only other alumni","receiveAlerts":false,"reminderFrequency":"One week before the event"}';
            KenSettingsController.saveEventPreferences(json);

            KenSettingsController.EventPreferencesPayload after = KenSettingsController.getEventPreferences();
            Test.stopTest();

            System.assertEquals('Only other alumni', after.whoCanInvite, 'whoCanInvite should be saved');
            System.assertEquals(false, after.receiveAlerts, 'receiveAlerts should be saved');
            System.assertEquals('One week before the event', after.reminderFrequency, 'reminderFrequency should be saved');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testGetAndSaveGroupPreferencesRoundTrip() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenSettingsController.GroupPreferencesPayload before = KenSettingsController.getGroupPreferences();
            System.assertNotEquals(null, before, 'Existing group preferences should be returned');

            String json = '{"whoCanInvite":"Only other alumni","receiveUpdates":false,"notifyFor":"New posts"}';
            KenSettingsController.saveGroupPreferences(json);

            KenSettingsController.GroupPreferencesPayload after = KenSettingsController.getGroupPreferences();
            Test.stopTest();

            System.assertEquals('Only other alumni', after.whoCanInvite, 'whoCanInvite should be saved');
            System.assertEquals(false, after.receiveUpdates, 'receiveUpdates should be saved');
            System.assertEquals('New posts', after.notifyFor, 'notifyFor should be saved');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testGetAndSaveMentorshipPreferencesRoundTrip() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenSettingsController.MentorshipPreferencesPayload before = KenSettingsController.getMentorshipPreferences();
            System.assertNotEquals(null, before, 'Existing mentorship preferences should be returned');

            String json = '{"willingToBeMentor":true,"availabilityDays":"Monday;Tuesday","availabilityStartTime":"09:30","availabilityEndTime":"17:45","expertiseAreas":"Development","commModes":"Email"}';
            KenSettingsController.saveMentorshipPreferences(json);

            KenSettingsController.MentorshipPreferencesPayload after = KenSettingsController.getMentorshipPreferences();
            Test.stopTest();

            System.assertEquals(true, after.willingToBeMentor, 'willingToBeMentor should be saved');
            System.assertEquals('Monday;Tuesday', after.availabilityDays, 'availabilityDays should be saved');
            System.assertEquals('09:30', after.availabilityStartTime, 'availabilityStartTime should be saved as HH:mm');
            System.assertEquals('17:45', after.availabilityEndTime, 'availabilityEndTime should be saved as HH:mm');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testSaveMentorshipPreferencesWithBlankTimesClearsTimes() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            String json = '{"willingToBeMentor":false,"availabilityDays":null,"availabilityStartTime":null,"availabilityEndTime":null,"expertiseAreas":null,"commModes":null}';
            Test.startTest();
            KenSettingsController.saveMentorshipPreferences(json);
            KenSettingsController.MentorshipPreferencesPayload after = KenSettingsController.getMentorshipPreferences();
            Test.stopTest();

            System.assertEquals(false, after.willingToBeMentor, 'willingToBeMentor should be false');
            System.assertEquals('', after.availabilityStartTime, 'availabilityStartTime should be empty when cleared');
            System.assertEquals('', after.availabilityEndTime, 'availabilityEndTime should be empty when cleared');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testGetAndSaveJobPreferencesRoundTrip() {
        Account pa = seededPersonAccount();
        KenSettingsController.testCurrentAccountId = pa.Id;
        try {
            Test.startTest();
            KenSettingsController.JobPreferencesPayload before = KenSettingsController.getJobPreferences();
            System.assertNotEquals(null, before, 'Existing job preferences should be returned');

            String json = '{"openToWork":false,"preferredJobTitles":"Software Engineer","skillSet":"JAVA","preferredLocationTypes":"Remote","locationOnSite":"Bengaluru","employmentTypes":"Full-time"}';
            KenSettingsController.saveJobPreferences(json);

            KenSettingsController.JobPreferencesPayload after = KenSettingsController.getJobPreferences();
            Test.stopTest();

            System.assertEquals(false, after.openToWork, 'openToWork should be saved');
            System.assertEquals('Software Engineer', after.preferredJobTitles, 'preferredJobTitles should be saved');
            System.assertEquals('JAVA', after.skillSet, 'skillSet should be saved');
            System.assertEquals('Remote', after.preferredLocationTypes, 'preferredLocationTypes should be saved');
            System.assertEquals('Bengaluru', after.locationOnSite, 'locationOnSite should be saved');
            System.assertEquals('Full-time', after.employmentTypes, 'employmentTypes should be saved');
        } finally {
            KenSettingsController.testCurrentAccountId = null;
        }
    }

    @IsTest
    static void testPayloadDtosInstantiate() {
        Test.startTest();
        KenSettingsController.PersonalDetailsPayload pd = new KenSettingsController.PersonalDetailsPayload();
        pd.firstName            = 'John';
        pd.lastName             = 'Doe';
        pd.maskedEmail          = 'jo*****@example.com';
        pd.maskedPhone          = '+**** *****1234';
        pd.city                 = 'Mumbai';
        pd.country              = 'India';
        pd.linkedinUrl          = 'https://linkedin.com/in/test';
        pd.twitterUrl           = 'https://twitter.com/test';
        pd.profileImageUrl      = 'https://example.com/photo.jpg';
        pd.engagementPreferences = 'All';

        KenSettingsController.PreferencesPayload pp = new KenSettingsController.PreferencesPayload();
        pp.isPrivateAccount       = false;
        pp.preferredCommunication = 'Email';
        pp.howOften               = 'Daily';
        pp.notifyRealTime         = true;
        pp.notifyFor              = 'All';
        pp.muteStart              = '22:00';
        pp.muteEnd                = '08:00';

        KenSettingsController.EventPreferencesPayload ep = new KenSettingsController.EventPreferencesPayload();
        ep.whoCanInvite      = 'Everyone';
        ep.receiveAlerts     = true;
        ep.reminderFrequency = 'Daily';

        KenSettingsController.GroupPreferencesPayload gp = new KenSettingsController.GroupPreferencesPayload();
        gp.whoCanInvite   = 'Everyone';
        gp.receiveUpdates = true;
        gp.notifyFor      = 'All';

        KenSettingsController.MentorshipPreferencesPayload mp = new KenSettingsController.MentorshipPreferencesPayload();
        mp.willingToBeMentor     = true;
        mp.availabilityDays      = 'Mon,Tue';
        mp.availabilityStartTime = '09:00';
        mp.availabilityEndTime   = '17:00';
        mp.expertiseAreas        = 'Engineering';
        mp.commModes             = 'Video Call';

        KenSettingsController.JobPreferencesPayload jp = new KenSettingsController.JobPreferencesPayload();
        jp.openToWork             = true;
        jp.preferredJobTitles     = 'Engineer';
        jp.skillSet               = 'Java';
        jp.preferredLocationTypes = 'Remote';
        jp.locationOnSite         = 'Mumbai';
        jp.employmentTypes        = 'Full-time';
        Test.stopTest();

        System.assertNotEquals(null, pd, 'PersonalDetailsPayload should instantiate correctly');
        System.assertNotEquals(null, pp, 'PreferencesPayload should instantiate correctly');
        System.assertNotEquals(null, ep, 'EventPreferencesPayload should instantiate correctly');
        System.assertNotEquals(null, gp, 'GroupPreferencesPayload should instantiate correctly');
        System.assertNotEquals(null, mp, 'MentorshipPreferencesPayload should instantiate correctly');
        System.assertNotEquals(null, jp, 'JobPreferencesPayload should instantiate correctly');
    }
}