public without sharing class KenSettingsController {

    // ── Personal Details ──────────────────────────────────────────────────────

    public class PersonalDetailsPayload {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String maskedEmail;
        @AuraEnabled public String maskedPhone;
        @AuraEnabled public String city;
        @AuraEnabled public String country;
        @AuraEnabled public String linkedinUrl;
        @AuraEnabled public String twitterUrl;
        @AuraEnabled public String profileImageUrl;
        @AuraEnabled public String engagementPreferences;
    }

    @AuraEnabled(cacheable=false)
    public static PersonalDetailsPayload getPersonalDetails() {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        List<Account> accounts = [
            SELECT FirstName, LastName, PersonEmail, PersonMobilePhone,
                   Linkedin_Profile_URL__c, Twitter_Profile_URL__c
            FROM Account
            WHERE Id = :accountId AND IsPersonAccount = true
            LIMIT 1
        ];
        if (accounts.isEmpty()) throw new AuraHandledException('Profile not found');
        Account acc = accounts[0];

        List<Ken_Address__c> addresses = [
            SELECT City__c, Country__c FROM Ken_Address__c
            WHERE Person_Account__c = :accountId AND Address_Type__c = 'Mailing'
            LIMIT 1
        ];

        Id constituentRoleId = getActiveConstituentRoleId(accountId);
        List<Ken_Alumni_CRM__c> crms = constituentRoleId != null
            ? [SELECT Profile_Photo_URL__c, Preferences__c FROM Ken_Alumni_CRM__c
               WHERE ConstituentRole__c = :constituentRoleId LIMIT 1]
            : [SELECT Profile_Photo_URL__c, Preferences__c FROM Ken_Alumni_CRM__c
               WHERE Person_Account__c = :accountId LIMIT 1];

        PersonalDetailsPayload p = new PersonalDetailsPayload();
        p.firstName = acc.FirstName;
        p.lastName  = acc.LastName;
        p.maskedEmail = maskEmail(acc.PersonEmail);
        p.maskedPhone = maskPhone(acc.PersonMobilePhone);
        p.linkedinUrl = acc.Linkedin_Profile_URL__c;
        p.twitterUrl  = acc.Twitter_Profile_URL__c;
        if (!addresses.isEmpty()) { p.city = addresses[0].City__c; p.country = addresses[0].Country__c; }
        if (!crms.isEmpty())      { p.profileImageUrl = crms[0].Profile_Photo_URL__c; p.engagementPreferences = crms[0].Preferences__c; }
        return p;
    }

    @AuraEnabled
    public static void savePersonalDetails(String requestJson) {
        if (String.isBlank(requestJson)) throw new AuraHandledException('Invalid request');
        PersonalDetailsPayload req;
        try { req = (PersonalDetailsPayload) JSON.deserialize(requestJson, PersonalDetailsPayload.class); }
        catch (Exception e) { throw new AuraHandledException('Invalid format: ' + e.getMessage()); }

        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Account acc = new Account(Id = accountId, FirstName = req.firstName, LastName = req.lastName);
        if (req.linkedinUrl != null) acc.Linkedin_Profile_URL__c = req.linkedinUrl;
        if (req.twitterUrl  != null) acc.Twitter_Profile_URL__c  = req.twitterUrl;
        update acc;

        List<Ken_Address__c> existing = [
            SELECT Id FROM Ken_Address__c
            WHERE Person_Account__c = :accountId AND Address_Type__c = 'Mailing'
            LIMIT 1
        ];
        Ken_Address__c addr = existing.isEmpty() ? new Ken_Address__c() : existing[0];
        addr.Person_Account__c = accountId;
        addr.Address_Type__c   = 'Mailing';
        addr.City__c    = req.city;
        addr.Country__c = req.country;
        if (addr.Id == null) insert addr; else update addr;
    }

    @AuraEnabled
    public static String saveProfilePhoto(String base64Image) {
        if (String.isBlank(base64Image)) throw new AuraHandledException('No image data');
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        String imageUrl = base64Image;
        if (base64Image.startsWith('data:') && base64Image.contains('base64,')) {
            String b64 = base64Image.substringAfter('base64,');
            String ext = base64Image.contains('image/png') ? '.png' : '.jpg';
            String title = 'profile_setting_' + String.valueOf(System.now().getTime()) + ext;
            imageUrl = KenCreateContentVersion.createContentVersion(title, b64);
        }

        Id constituentRoleId2 = getActiveConstituentRoleId(accountId);
        List<Ken_Alumni_CRM__c> crms = constituentRoleId2 != null
            ? [SELECT Id FROM Ken_Alumni_CRM__c WHERE ConstituentRole__c = :constituentRoleId2 LIMIT 1]
            : [SELECT Id FROM Ken_Alumni_CRM__c WHERE Person_Account__c = :accountId LIMIT 1];
        if (!crms.isEmpty()) { crms[0].Profile_Photo_URL__c = imageUrl; update crms[0]; }
        return imageUrl;
    }

    @AuraEnabled
    public static void saveEngagementPreferences(String preferences) {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');
        Id constituentRoleId3 = getActiveConstituentRoleId(accountId);
        List<Ken_Alumni_CRM__c> crms = constituentRoleId3 != null
            ? [SELECT Id, Preferences__c FROM Ken_Alumni_CRM__c
               WHERE ConstituentRole__c = :constituentRoleId3 LIMIT 1]
            : [SELECT Id, Preferences__c FROM Ken_Alumni_CRM__c
               WHERE Person_Account__c = :accountId LIMIT 1];
        if (crms.isEmpty()) throw new AuraHandledException('Alumni record not found');
        crms[0].Preferences__c = preferences;
        update crms[0];
    }

    // ── Preferences (Notifications) ───────────────────────────────────────────

    public class PreferencesPayload {
        @AuraEnabled public Boolean isPrivateAccount;
        @AuraEnabled public String  preferredCommunication;
        @AuraEnabled public String  howOften;
        @AuraEnabled public Boolean notifyRealTime;
        @AuraEnabled public String  notifyFor;
        @AuraEnabled public String  muteStart;
        @AuraEnabled public String  muteEnd;
    }

    @AuraEnabled(cacheable=false)
    public static PreferencesPayload getPreferences() {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        PreferencesPayload p = new PreferencesPayload();
        p.isPrivateAccount       = rec.Is_Private_Account__c;
        p.preferredCommunication = rec.Preferred_method_of_Communication__c;
        p.howOften               = rec.How_often_would_you_like_to_hear_from_us__c;
        p.notifyRealTime         = rec.Notify_in_real_time__c;
        p.notifyFor              = rec.Notify_me_for__c;
        p.muteStart              = rec.Mute_Notifications_Start_Time__c != null ? String.valueOf(rec.Mute_Notifications_Start_Time__c) : null;
        p.muteEnd                = rec.Mute_Notifications_End_Time__c   != null ? String.valueOf(rec.Mute_Notifications_End_Time__c)   : null;
        return p;
    }

    @AuraEnabled
    public static void savePreferences(String requestJson) {
        PreferencesPayload req = (PreferencesPayload) JSON.deserialize(requestJson, PreferencesPayload.class);
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        rec.Is_Private_Account__c                       = req.isPrivateAccount != null ? req.isPrivateAccount : false;
        rec.Preferred_method_of_Communication__c        = req.preferredCommunication;
        rec.How_often_would_you_like_to_hear_from_us__c = req.howOften;
        rec.Notify_in_real_time__c                      = req.notifyRealTime != null ? req.notifyRealTime : false;
        rec.Notify_me_for__c                            = req.notifyFor;
        upsertRecord(rec);
    }

    // ── Event Preferences ─────────────────────────────────────────────────────

    public class EventPreferencesPayload {
        @AuraEnabled public String  whoCanInvite;
        @AuraEnabled public Boolean receiveAlerts;
        @AuraEnabled public String  reminderFrequency;
    }

    @AuraEnabled(cacheable=false)
    public static EventPreferencesPayload getEventPreferences() {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        EventPreferencesPayload p = new EventPreferencesPayload();
        p.whoCanInvite      = rec.Who_can_invite_me_to_events__c;
        p.receiveAlerts     = rec.Receive_Invited_Event_Alerts__c;
        p.reminderFrequency = rec.Event_Reminder_Frequency__c;
        return p;
    }

    @AuraEnabled
    public static void saveEventPreferences(String requestJson) {
        EventPreferencesPayload req = (EventPreferencesPayload) JSON.deserialize(requestJson, EventPreferencesPayload.class);
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        rec.Who_can_invite_me_to_events__c  = req.whoCanInvite;
        rec.Receive_Invited_Event_Alerts__c = req.receiveAlerts != null ? req.receiveAlerts : false;
        rec.Event_Reminder_Frequency__c     = req.reminderFrequency;
        upsertRecord(rec);
    }

    // ── Group Preferences ─────────────────────────────────────────────────────

    public class GroupPreferencesPayload {
        @AuraEnabled public String  whoCanInvite;
        @AuraEnabled public Boolean receiveUpdates;
        @AuraEnabled public String  notifyFor;
    }

    @AuraEnabled(cacheable=false)
    public static GroupPreferencesPayload getGroupPreferences() {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        GroupPreferencesPayload p = new GroupPreferencesPayload();
        p.whoCanInvite   = rec.Who_can_invite_me_to_groups__c;
        p.receiveUpdates = rec.Receive_updates_from_joined_groups__c;
        p.notifyFor      = rec.Notify_me_for_groups__c;
        return p;
    }

    @AuraEnabled
    public static void saveGroupPreferences(String requestJson) {
        GroupPreferencesPayload req = (GroupPreferencesPayload) JSON.deserialize(requestJson, GroupPreferencesPayload.class);
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        rec.Who_can_invite_me_to_groups__c        = req.whoCanInvite;
        rec.Receive_updates_from_joined_groups__c = req.receiveUpdates != null ? req.receiveUpdates : false;
        rec.Notify_me_for_groups__c               = req.notifyFor;
        upsertRecord(rec);
    }

    // ── Mentorship Preferences ────────────────────────────────────────────────

    public class MentorshipPreferencesPayload {
        @AuraEnabled public Boolean willingToBeMentor;
        @AuraEnabled public String  availabilityDays;
        @AuraEnabled public String  availabilityStartTime;
        @AuraEnabled public String  availabilityEndTime;
        @AuraEnabled public String  expertiseAreas;
        @AuraEnabled public String  commModes;
    }

    @AuraEnabled(cacheable=false)
    public static MentorshipPreferencesPayload getMentorshipPreferences() {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        MentorshipPreferencesPayload p = new MentorshipPreferencesPayload();
        p.willingToBeMentor      = rec.Willing_to_be_a_mentor__c;
        p.availabilityDays       = rec.Mentorship_Availability_Days__c;
        p.availabilityStartTime  = rec.Mentorship_Availability_Start_Time__c != null
            ? String.valueOf(rec.Mentorship_Availability_Start_Time__c).substring(0, 5) : '';
        p.availabilityEndTime    = rec.Mentorship_Availability_End_Time__c != null
            ? String.valueOf(rec.Mentorship_Availability_End_Time__c).substring(0, 5) : '';
        p.expertiseAreas         = rec.Mentorship_Expertise_Areas__c;
        p.commModes              = rec.Mentorship_Preferred_Communication_Modes__c;
        return p;
    }

    @AuraEnabled
    public static void saveMentorshipPreferences(String requestJson) {
        MentorshipPreferencesPayload req = (MentorshipPreferencesPayload) JSON.deserialize(requestJson, MentorshipPreferencesPayload.class);
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        rec.Willing_to_be_a_mentor__c                   = req.willingToBeMentor != null ? req.willingToBeMentor : false;
        rec.Mentorship_Availability_Days__c             = req.availabilityDays;
        rec.Mentorship_Expertise_Areas__c               = req.expertiseAreas;
        rec.Mentorship_Preferred_Communication_Modes__c = req.commModes;
        if (String.isNotBlank(req.availabilityStartTime)) {
            rec.Mentorship_Availability_Start_Time__c = Time.newInstance(
                Integer.valueOf(req.availabilityStartTime.split(':')[0]),
                Integer.valueOf(req.availabilityStartTime.split(':')[1]), 0, 0);
        } else {
            rec.Mentorship_Availability_Start_Time__c = null;
        }
        if (String.isNotBlank(req.availabilityEndTime)) {
            rec.Mentorship_Availability_End_Time__c = Time.newInstance(
                Integer.valueOf(req.availabilityEndTime.split(':')[0]),
                Integer.valueOf(req.availabilityEndTime.split(':')[1]), 0, 0);
        } else {
            rec.Mentorship_Availability_End_Time__c = null;
        }
        upsertRecord(rec);
    }

    // ── Job Preferences ───────────────────────────────────────────────────────

    public class JobPreferencesPayload {
        @AuraEnabled public Boolean openToWork;
        @AuraEnabled public String  preferredJobTitles;
        @AuraEnabled public String  skillSet;
        @AuraEnabled public String  preferredLocationTypes;
        @AuraEnabled public String  locationOnSite;
        @AuraEnabled public String  employmentTypes;
    }

    @AuraEnabled(cacheable=false)
    public static JobPreferencesPayload getJobPreferences() {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        JobPreferencesPayload p = new JobPreferencesPayload();
        p.openToWork             = rec.Open_to_work__c;
        p.preferredJobTitles     = rec.Preferred_job_titles__c;
        p.skillSet               = rec.Skill_set__c;
        p.preferredLocationTypes = rec.Preferred_location_types__c;
        p.locationOnSite         = rec.Location_on_site__c;
        p.employmentTypes        = rec.Employment_types__c;
        return p;
    }

    @AuraEnabled
    public static void saveJobPreferences(String requestJson) {
        JobPreferencesPayload req = (JobPreferencesPayload) JSON.deserialize(requestJson, JobPreferencesPayload.class);
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) throw new AuraHandledException('User not found');

        Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
        rec.Open_to_work__c             = req.openToWork != null ? req.openToWork : false;
        rec.Preferred_job_titles__c     = req.preferredJobTitles;
        rec.Skill_set__c                = req.skillSet;
        rec.Preferred_location_types__c = req.preferredLocationTypes;
        rec.Location_on_site__c         = req.locationOnSite;
        rec.Employment_types__c         = req.employmentTypes;
        upsertRecord(rec);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Ken_Alumni_Preferences__c getPrefRecord(Id accountId) {
        List<Ken_Alumni_Preferences__c> recs = [
            SELECT Id,
                   Is_Private_Account__c,
                   Preferred_method_of_Communication__c,
                   How_often_would_you_like_to_hear_from_us__c,
                   Notify_in_real_time__c,
                   Notify_me_for__c,
                   Mute_Notifications_Start_Time__c,
                   Mute_Notifications_End_Time__c,
                   Who_can_invite_me_to_events__c,
                   Receive_Invited_Event_Alerts__c,
                   Event_Reminder_Frequency__c,
                   Who_can_invite_me_to_groups__c,
                   Receive_updates_from_joined_groups__c,
                   Notify_me_for_groups__c,
                   Willing_to_be_a_mentor__c,
                   Mentorship_Availability_Days__c,
                   Mentorship_Availability_Start_Time__c,
                   Mentorship_Availability_End_Time__c,
                   Mentorship_Expertise_Areas__c,
                   Mentorship_Preferred_Communication_Modes__c,
                   Open_to_work__c,
                   Preferred_job_titles__c,
                   Skill_set__c,
                   Preferred_location_types__c,
                   Location_on_site__c,
                   Employment_types__c
            FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c = :accountId
            LIMIT 1
        ];

        if (!recs.isEmpty()) return recs[0];

        // Fallback shell with defaults (in case onboarding did not run for this user)
        return new Ken_Alumni_Preferences__c(
            Person_Account__c                           = accountId,
            Is_Private_Account__c                       = false,
            How_often_would_you_like_to_hear_from_us__c = 'Daily',
            Notify_in_real_time__c                      = true,
            Who_can_invite_me_to_events__c              = 'Everyone',
            Receive_Invited_Event_Alerts__c             = true,
            Who_can_invite_me_to_groups__c              = 'Everyone',
            Receive_updates_from_joined_groups__c       = true,
            Open_to_work__c                             = true,
            Willing_to_be_a_mentor__c                   = false
        );
    }

    private static void upsertRecord(Ken_Alumni_Preferences__c rec) {
        if (rec.Id == null) insert rec; else update rec;
    }

    @TestVisible
    private static Id testCurrentAccountId;

    private static Id getCurrentUserAccountId() {
        if (Test.isRunningTest() && testCurrentAccountId != null) {
            return testCurrentAccountId;
        }
        List<User> users = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return (users.isEmpty() || users[0].AccountId == null) ? null : users[0].AccountId;
    }

    private static String maskEmail(String email) {
        if (String.isBlank(email)) return '';
        Integer atIdx = email.indexOf('@');
        if (atIdx <= 0) return email;
        String local = email.substring(0, atIdx);
        String domain = email.substring(atIdx);
        String visible = local.length() > 2 ? local.substring(0, 2) : local.substring(0, 1);
        return visible + '*****' + domain;
    }

    private static String maskPhone(String phone) {
        if (String.isBlank(phone)) return '';
        String digits = phone.replaceAll('[^0-9]', '');
        if (digits.length() <= 4) return phone;
        return '+**** *****' + digits.substring(digits.length() - 4);
    }

    private static Id getActiveConstituentRoleId(Id accountId) {
        if (accountId == null) return null;
        List<ConstituentRole> registered = [
            SELECT Id FROM ConstituentRole
            WHERE PersonId = :accountId AND RoleType = 'Alumni'
              AND Registration_Status__c = 'Registered'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (!registered.isEmpty()) return registered[0].Id;
        List<ConstituentRole> allRoles = [
            SELECT Id FROM ConstituentRole
            WHERE PersonId = :accountId AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return allRoles.isEmpty() ? null : allRoles[0].Id;
    }
}