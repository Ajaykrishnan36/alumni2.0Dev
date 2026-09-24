public without sharing class KenProfileSettingsController {
  // ── Personal Details ──────────────────────────────────────────────────────

  public class PersonalDetailsPayload {
    // Lets the LWC call getRecordNotifyChange after a save - this save
    // goes through plain Apex DML, not Lightning Data Service, so other
    // components with an LDS wire on this Account (e.g. the LinkedIn
    // Sync card's getRecord wire) never learn the record changed unless
    // told to.
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public String lastName;
    @AuraEnabled
    public String maskedEmail;
    @AuraEnabled
    public String maskedPhone;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String linkedinUrl;
    @AuraEnabled
    public String twitterUrl;
    @AuraEnabled
    public String profileImageUrl;
    @AuraEnabled
    public String engagementPreferences;
    // Personal Details card (portal profile page) - self-editable, unlike
    // Alumna Snapshot's institute-of-record fields (Registration Number,
    // Program, Class of, etc.), which stay read-only.
    @AuraEnabled
    public String dob; // ISO yyyy-MM-dd, matches lightning-input type="date"
    @AuraEnabled
    public String gender;
    @AuraEnabled
    public String bloodGroup;
    @AuraEnabled
    public String nationality;
    @AuraEnabled
    public String languagesKnown;
    @AuraEnabled
    public List<Map<String, String>> genderOptions;
    @AuraEnabled
    public List<Map<String, String>> bloodGroupOptions;
    @AuraEnabled
    public List<Map<String, String>> nationalityOptions;
  }

  @AuraEnabled(cacheable=false)
  public static PersonalDetailsPayload getPersonalDetails() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    List<Account> accounts = [
      SELECT
        FirstName,
        LastName,
        PersonEmail,
        PersonMobilePhone,
        Linkedin_Profile_URL__c,
        Twitter_Profile_URL__c,
        Profile_Photo_URL__c,
        Engagement_Preferences__c,
        PersonBirthdate,
        PersonGenderIdentity,
        Blood_Group__c,
        Nationality__c,
        Languages_Known__c
      FROM Account
      WHERE Id = :accountId AND IsPersonAccount = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (accounts.isEmpty())
      throw new AuraHandledException('Profile not found');
    Account acc = accounts[0];

    List<Ken_Address__c> addresses = [
      SELECT City__c, Country__c, State__c
      FROM Ken_Address__c
      WHERE Person_Account__c = :accountId AND Address_Type__c = 'Mailing'
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    PersonalDetailsPayload p = new PersonalDetailsPayload();
    p.accountId = accountId;
    p.firstName = acc.FirstName;
    p.lastName = acc.LastName;
    p.maskedEmail = maskEmail(acc.PersonEmail);
    p.maskedPhone = maskPhone(acc.PersonMobilePhone);
    p.linkedinUrl = acc.Linkedin_Profile_URL__c;
    p.twitterUrl = acc.Twitter_Profile_URL__c;
    p.profileImageUrl = acc.Profile_Photo_URL__c;
    if (!addresses.isEmpty()) {
      p.city = addresses[0].City__c;
      p.country = addresses[0].Country__c;
      p.state = addresses[0].State__c;
    }
    p.engagementPreferences = acc.Engagement_Preferences__c;
    p.dob = acc.PersonBirthdate != null
      ? String.valueOf(acc.PersonBirthdate)
      : null;
    p.gender = acc.PersonGenderIdentity;
    p.bloodGroup = acc.Blood_Group__c;
    p.nationality = acc.Nationality__c;
    p.languagesKnown = acc.Languages_Known__c;
    // Same three methods the onboarding flow uses (KenPortalOnbordingController),
    // not a separately reinvented picklist lookup - so this menu is always the
    // exact same option set an alumnus already saw at signup. In particular:
    // Gender is deliberately filtered to Male/Female/"Others" there (Others is
    // the real 'Not Listed' picklist value relabelled), and Blood Group falls
    // back to the standard 8 groups for orgs where that field is plain text.
    // Reusing them here means that curation never has to be maintained twice.
    p.genderOptions = toOptionMaps(
      KenPortalOnbordingController.getGenderOptions()
    );
    p.bloodGroupOptions = toOptionMaps(
      KenPortalOnbordingController.getBloodGroupOptions()
    );
    p.nationalityOptions = toOptionMaps(
      KenPortalOnbordingController.getNationalityOptions()
    );
    return p;
  }

  private static List<Map<String, String>> toOptionMaps(
    List<KenPortalOnbordingController.OptionValue> options
  ) {
    List<Map<String, String>> opts = new List<Map<String, String>>();
    if (options == null)
      return opts;
    for (KenPortalOnbordingController.OptionValue opt : options) {
      opts.add(
        new Map<String, String>{ 'label' => opt.label, 'value' => opt.value }
      );
    }
    return opts;
  }

  @AuraEnabled
  public static void savePersonalDetails(String requestJson) {
    if (String.isBlank(requestJson))
      throw new AuraHandledException('Invalid request');
    PersonalDetailsPayload req;
    try {
      req = (PersonalDetailsPayload) JSON.deserialize(
        requestJson,
        PersonalDetailsPayload.class
      );
    } catch (Exception e) {
      throw new AuraHandledException('Invalid format: ' + e.getMessage());
    }

    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Account acc = new Account(
      Id = accountId,
      FirstName = req.firstName,
      LastName = req.lastName
    );
    if (req.linkedinUrl != null)
      acc.Linkedin_Profile_URL__c = req.linkedinUrl;
    if (req.twitterUrl != null)
      acc.Twitter_Profile_URL__c = req.twitterUrl;
    if (String.isNotBlank(req.dob)) {
      try {
        acc.PersonBirthdate = Date.valueOf(req.dob);
      } catch (Exception e) {
        throw new AuraHandledException('Date of birth must be a valid date.');
      }
    }
    if (req.gender != null)
      acc.PersonGenderIdentity = req.gender;
    if (req.bloodGroup != null)
      acc.Blood_Group__c = req.bloodGroup;
    if (req.nationality != null)
      acc.Nationality__c = req.nationality;
    if (req.languagesKnown != null)
      acc.Languages_Known__c = req.languagesKnown;
    if (!Schema.sObjectType.Account.isUpdateable()) {
      throw new KenCrudException('Account is not updateable by the current user.');
    }
    update acc;

    List<Ken_Address__c> existing = [
      SELECT Id
      FROM Ken_Address__c
      WHERE Person_Account__c = :accountId AND Address_Type__c = 'Mailing'
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    Ken_Address__c addr = existing.isEmpty()
      ? new Ken_Address__c()
      : existing[0];
    addr.Person_Account__c = accountId;
    addr.Address_Type__c = 'Mailing';
    addr.City__c = req.city;
    addr.Country__c = req.country;
    addr.State__c = req.state;
    if (addr.Id == null) {
      if (!Schema.sObjectType.Ken_Address__c.isCreateable()) {
        throw new KenCrudException('Ken_Address__c is not createable by the current user.');
      }
      insert addr;
    } else {
      if (!Schema.sObjectType.Ken_Address__c.isUpdateable()) {
        throw new KenCrudException('Ken_Address__c is not updateable by the current user.');
      }
      update addr;
    }
  }

  @AuraEnabled
  public static String saveProfilePhoto(String base64Image) {
    if (String.isBlank(base64Image))
      throw new AuraHandledException('No image data');
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    String imageUrl = base64Image;
    if (base64Image.startsWith('data:') && base64Image.contains('base64,')) {
      String b64 = base64Image.substringAfter('base64,');
      String ext = base64Image.contains('image/png') ? '.png' : '.jpg';
      String title =
        'profile_setting_' +
        String.valueOf(System.now().getTime()) +
        ext;
      imageUrl = KenCreateContentVersion.createContentVersion(title, b64);
    }
    if (!Schema.sObjectType.Account.isUpdateable()) {
      throw new KenCrudException('Account is not updateable by the current user.');
    }

    update new Account(Id = accountId, Profile_Photo_URL__c = imageUrl);
    return imageUrl;
  }

  @AuraEnabled
  public static void saveEngagementPreferences(String preferences) {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');
    String prefText = preferences == null ? '' : preferences;
    if (prefText.length() > 255) {
      prefText = prefText.substring(0, 255);
    }
    if (!Schema.sObjectType.Account.isUpdateable()) {
      throw new KenCrudException('Account is not updateable by the current user.');
    }
    update new Account(Id = accountId, Engagement_Preferences__c = prefText);
  }

  // ── Preferences (Notifications) ───────────────────────────────────────────

  public class PreferencesPayload {
    @AuraEnabled
    public Boolean isPrivateAccount;
    @AuraEnabled
    public String preferredCommunication;
    @AuraEnabled
    public String howOften;
    @AuraEnabled
    public Boolean notifyRealTime;
    @AuraEnabled
    public String notifyFor;
    @AuraEnabled
    public String muteStart;
    @AuraEnabled
    public String muteEnd;
  }

  @AuraEnabled(cacheable=false)
  public static PreferencesPayload getPreferences() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    PreferencesPayload p = new PreferencesPayload();
    p.isPrivateAccount = rec.Is_Restricted_Account__c;
    p.preferredCommunication = rec.Preferred_method_of_Communication__c;
    p.howOften = rec.How_often_would_you_like_to_hear_from_us__c;
    p.notifyRealTime = rec.Notify_in_real_time__c;
    p.notifyFor = rec.Notify_me_for__c;
    // UTC wall clock — see the "UTC wall-clock Time fields" section below.
    // Nothing writes these two today, so they are read-only until a mute UI exists.
    p.muteStart = formatUtcTime(rec.Mute_Notifications_Start_Time__c);
    p.muteEnd = formatUtcTime(rec.Mute_Notifications_End_Time__c);
    return p;
  }

  @AuraEnabled
  public static void savePreferences(String requestJson) {
    PreferencesPayload req = (PreferencesPayload) JSON.deserialize(
      requestJson,
      PreferencesPayload.class
    );
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    rec.Is_Restricted_Account__c = req.isPrivateAccount != null ? req.isPrivateAccount : false;
    rec.Preferred_method_of_Communication__c = req.preferredCommunication;
    rec.How_often_would_you_like_to_hear_from_us__c = req.howOften;
    rec.Notify_in_real_time__c = req.notifyRealTime != null
      ? req.notifyRealTime
      : false;
    rec.Notify_me_for__c = req.notifyFor;
    upsertRecord(rec);
  }

  // ── Event Preferences ─────────────────────────────────────────────────────

  public class EventPreferencesPayload {
    @AuraEnabled
    public String whoCanInvite;
    @AuraEnabled
    public Boolean receiveAlerts;
    @AuraEnabled
    public String reminderFrequency;
  }

  @AuraEnabled(cacheable=false)
  public static EventPreferencesPayload getEventPreferences() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    EventPreferencesPayload p = new EventPreferencesPayload();
    p.whoCanInvite = rec.Who_can_invite_me_to_events__c;
    p.receiveAlerts = rec.Receive_Invited_Event_Alerts__c;
    p.reminderFrequency = rec.Event_Reminder_Frequency__c;
    return p;
  }

  @AuraEnabled
  public static void saveEventPreferences(String requestJson) {
    EventPreferencesPayload req = (EventPreferencesPayload) JSON.deserialize(
      requestJson,
      EventPreferencesPayload.class
    );
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    rec.Who_can_invite_me_to_events__c = req.whoCanInvite;
    rec.Receive_Invited_Event_Alerts__c = req.receiveAlerts != null
      ? req.receiveAlerts
      : false;
    rec.Event_Reminder_Frequency__c = req.reminderFrequency;
    upsertRecord(rec);
  }

  // ── Group Preferences ─────────────────────────────────────────────────────

  public class GroupPreferencesPayload {
    @AuraEnabled
    public String whoCanInvite;
    @AuraEnabled
    public Boolean receiveUpdates;
    @AuraEnabled
    public String notifyFor;
  }

  @AuraEnabled(cacheable=false)
  public static GroupPreferencesPayload getGroupPreferences() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    GroupPreferencesPayload p = new GroupPreferencesPayload();
    p.whoCanInvite = rec.Who_can_invite_me_to_groups__c;
    p.receiveUpdates = rec.Receive_updates_from_joined_groups__c;
    p.notifyFor = rec.Notify_me_for_groups__c;
    return p;
  }

  @AuraEnabled
  public static void saveGroupPreferences(String requestJson) {
    GroupPreferencesPayload req = (GroupPreferencesPayload) JSON.deserialize(
      requestJson,
      GroupPreferencesPayload.class
    );
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    rec.Who_can_invite_me_to_groups__c = req.whoCanInvite;
    rec.Receive_updates_from_joined_groups__c = req.receiveUpdates != null
      ? req.receiveUpdates
      : false;
    rec.Notify_me_for_groups__c = req.notifyFor;
    upsertRecord(rec);
  }

  // ── Mentorship Preferences ────────────────────────────────────────────────

  public class MentorshipPreferencesPayload {
    @AuraEnabled
    public Boolean willingToBeMentor;
    @AuraEnabled
    public String availabilityDays;
    @AuraEnabled
    public String availabilityStartTime;
    @AuraEnabled
    public String availabilityEndTime;
    @AuraEnabled
    public String expertiseAreas;
    @AuraEnabled
    public String commModes;
  }

  @AuraEnabled(cacheable=false)
  public static MentorshipPreferencesPayload getMentorshipPreferences() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    MentorshipPreferencesPayload p = new MentorshipPreferencesPayload();
    p.willingToBeMentor = rec.Willing_to_be_a_mentor__c;
    p.availabilityDays = rec.Mentorship_Availability_Days__c;
    // UTC wall clock — see the "UTC wall-clock Time fields" section below.
    p.availabilityStartTime = formatUtcTime(
      rec.Mentorship_Availability_Start_Time__c
    );
    p.availabilityEndTime = formatUtcTime(
      rec.Mentorship_Availability_End_Time__c
    );
    p.expertiseAreas = rec.Mentorship_Expertise_Areas__c;
    p.commModes = rec.Mentorship_Preferred_Communication_Modes__c;
    return p;
  }

  @AuraEnabled
  public static void saveMentorshipPreferences(String requestJson) {
    MentorshipPreferencesPayload req = (MentorshipPreferencesPayload) JSON.deserialize(
      requestJson,
      MentorshipPreferencesPayload.class
    );
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    rec.Willing_to_be_a_mentor__c = req.willingToBeMentor != null
      ? req.willingToBeMentor
      : false;
    rec.Mentorship_Availability_Days__c = req.availabilityDays;
    rec.Mentorship_Expertise_Areas__c = req.expertiseAreas;
    rec.Mentorship_Preferred_Communication_Modes__c = req.commModes;
    // Blank clears the window; parseUtcTime applies the UTC convention that the
    // old inline split(':') only got right by accident. See the section below.
    rec.Mentorship_Availability_Start_Time__c = parseUtcTime(
      req.availabilityStartTime
    );
    rec.Mentorship_Availability_End_Time__c = parseUtcTime(
      req.availabilityEndTime
    );
    upsertRecord(rec);
  }

  // ── Job Preferences ───────────────────────────────────────────────────────

  public class JobPreferencesPayload {
    @AuraEnabled
    public Boolean openToWork;
    @AuraEnabled
    public String preferredJobTitles;
    @AuraEnabled
    public String skillSet;
    @AuraEnabled
    public String preferredLocationTypes;
    @AuraEnabled
    public String locationOnSite;
    @AuraEnabled
    public String employmentTypes;
  }

  @AuraEnabled(cacheable=false)
  public static JobPreferencesPayload getJobPreferences() {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    JobPreferencesPayload p = new JobPreferencesPayload();
    p.openToWork = rec.Open_to_work__c;
    p.preferredJobTitles = rec.Preferred_job_titles__c;
    p.skillSet = rec.Skill_set__c;
    p.preferredLocationTypes = rec.Preferred_location_types__c;
    p.locationOnSite = rec.Location_on_site__c;
    p.employmentTypes = rec.Employment_types__c;
    return p;
  }

  @AuraEnabled
  public static void saveJobPreferences(String requestJson) {
    JobPreferencesPayload req = (JobPreferencesPayload) JSON.deserialize(
      requestJson,
      JobPreferencesPayload.class
    );
    Id accountId = getCurrentUserAccountId();
    if (accountId == null)
      throw new AuraHandledException('User not found');

    Ken_Alumni_Preferences__c rec = getPrefRecord(accountId);
    rec.Open_to_work__c = req.openToWork != null ? req.openToWork : false;
    rec.Preferred_job_titles__c = req.preferredJobTitles;
    rec.Skill_set__c = req.skillSet;
    rec.Preferred_location_types__c = req.preferredLocationTypes;
    rec.Location_on_site__c = req.locationOnSite;
    rec.Employment_types__c = req.employmentTypes;
    upsertRecord(rec);
  }

  // ── UTC wall-clock Time fields ────────────────────────────────────────────
  //
  // Four fields on Ken_Alumni_Preferences__c stay Salesforce `Time` while the rest
  // of the portal moves to DateTime instants:
  //
  //     Mentorship_Availability_Start_Time__c / Mentorship_Availability_End_Time__c
  //     Mute_Notifications_Start_Time__c      / Mute_Notifications_End_Time__c
  //
  // They describe a recurring daily window — "available 09:00-17:00", "mute
  // 22:00-07:00" — with no calendar date attached. There is no instant to store,
  // so a DateTime would force us to invent a meaningless date, and the window
  // would then move every time the record crossed a daylight-saving boundary.
  //
  // Convention: the stored Time is a UTC wall clock, never a local one. That is
  // already what <lightning-input type="time"> emits ("HH:mm:ss.sssZ"), and it is
  // the only reading under which one alumnus' window means the same thing to a
  // viewer in another timezone. Anything rendering these values must shift them
  // into the viewer's zone first; a bare Time from this object is never local.
  //
  // parseUtcTime / formatUtcTime are where that convention is applied, so the
  // trailing "Z" is honoured deliberately rather than sliced off by luck.

  /**
   * @description Reads a time fragment as a UTC wall clock. The mentorship UI
   *              sends "HH:mm:ss.sssZ" from <lightning-input type="time">, while
   *              hand-built payloads and older callers send plain "HH:mm"; both
   *              are already UTC, so the only job here is to parse them the same.
   *              Minute precision is all the pickers offer, but seconds are read
   *              when present rather than being tripped over.
   *
   * @param value "HH:mm", "HH:mm:ss", "HH:mm:ss.sssZ" or a full ISO instant, or blank
   * @return      the Time, or null when absent or unparseable (which clears the window)
   */
  @TestVisible
  private static Time parseUtcTime(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    String raw = value.trim();
    if (raw.contains('T')) {
      raw = raw.substringAfter('T');
    }
    if (raw.endsWithIgnoreCase('Z')) {
      raw = raw.substring(0, raw.length() - 1);
    }
    List<String> parts = raw.split(':');
    if (parts.size() < 2) {
      return null;
    }
    // Millis would make Integer.valueOf choke on "00.000"; they carry nothing here.
    String seconds = parts.size() > 2 ? parts[2].substringBefore('.') : '0';
    try {
      return Time.newInstance(
        Integer.valueOf(parts[0].trim()),
        Integer.valueOf(parts[1].trim()),
        Integer.valueOf(String.isBlank(seconds) ? '0' : seconds.trim()),
        0
      );
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * @description Renders a stored UTC wall clock as "HH:mm" for the wire.
   *              String.valueOf(Time) gives "HH:mm:ss.SSSZ"; the seconds are always
   *              zero for a picker-sourced window and the components re-attach the
   *              "Z" themselves, so only the hour and minute travel.
   *
   * @param value stored Time, or null
   * @return      "HH:mm", or '' when unset
   */
  @TestVisible
  private static String formatUtcTime(Time value) {
    return value == null ? '' : String.valueOf(value).substring(0, 5);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  private static Ken_Alumni_Preferences__c getPrefRecord(Id accountId) {
    List<Ken_Alumni_Preferences__c> recs = [
      SELECT
        Id,
        Is_Restricted_Account__c,
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
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    if (!recs.isEmpty())
      return recs[0];

    // Fallback shell with defaults (in case onboarding did not run for this user)
    return new Ken_Alumni_Preferences__c(
      Person_Account__c = accountId,
      Is_Restricted_Account__c = true,
      How_often_would_you_like_to_hear_from_us__c = 'Daily',
      Notify_in_real_time__c = true,
      Who_can_invite_me_to_events__c = 'Everyone',
      Receive_Invited_Event_Alerts__c = true,
      Who_can_invite_me_to_groups__c = 'Everyone',
      Receive_updates_from_joined_groups__c = true,
      Open_to_work__c = true,
      Willing_to_be_a_mentor__c = false
    );
  }

  private static void upsertRecord(Ken_Alumni_Preferences__c rec) {
    if (rec.Id == null) {
      if (!Schema.sObjectType.Ken_Alumni_Preferences__c.isCreateable()) {
        throw new KenCrudException('Ken_Alumni_Preferences__c is not createable by the current user.');
      }
      insert rec;
    } else {
      if (!Schema.sObjectType.Ken_Alumni_Preferences__c.isUpdateable()) {
        throw new KenCrudException('Ken_Alumni_Preferences__c is not updateable by the current user.');
      }
      update rec;
    }
  }

  @TestVisible
  private static Id testCurrentAccountId;

  private static Id getCurrentUserAccountId() {
    if (Test.isRunningTest() && testCurrentAccountId != null) {
      return testCurrentAccountId;
    }
    List<User> users = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
    return (users.isEmpty() || users[0].AccountId == null)
      ? null
      : users[0].AccountId;
  }

  private static String maskEmail(String email) {
    if (String.isBlank(email))
      return '';
    Integer atIdx = email.indexOf('@');
    if (atIdx <= 0)
      return email;
    String local = email.substring(0, atIdx);
    String domain = email.substring(atIdx);
    String visible = local.length() > 2
      ? local.substring(0, 2)
      : local.substring(0, 1);
    return visible + '*****' + domain;
  }

  private static String maskPhone(String phone) {
    if (String.isBlank(phone))
      return '';
    String digits = phone.replaceAll('[^0-9]', '');
    if (digits.length() <= 4)
      return phone;
    return '+**** *****' + digits.substring(digits.length() - 4);
  }

  /**
   * @description Effective ConstituentRole of the logged-in user, resolved via
   *              KenConstituentRoleService (role with the latest Last_Login__c wins).
   */
  private static Id getActiveConstituentRoleId(Id accountId) {
    if (accountId == null)
      return null;
    return KenConstituentRoleService.getActiveConstituentRoleId();
  }
}