public without sharing class KenMyProfileController {
  private static final String INST_TYPE_OWN = 'Our Institute';
  private static final String INST_TYPE_OTHER = 'Other';

  public class ProfileData {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String company;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String profileImage;
    @AuraEnabled
    public Boolean isOnline;
    @AuraEnabled
    public String batch;
    @AuraEnabled
    public String expertise;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String linkedin;
    @AuraEnabled
    public Boolean willingToHelp;
    @AuraEnabled
    public String about;
    @AuraEnabled
    public String registrationNumber;
    @AuraEnabled
    public List<EducationRow> education;
    @AuraEnabled
    public List<ExperienceRow> experience;
    @AuraEnabled
    public List<AchievementRow> achievements;
    @AuraEnabled
    public String alumniStatus;
    @AuraEnabled
    public String yearOfEnrollment;
    @AuraEnabled
    public String program;
    @AuraEnabled
    public String yearsPostGrad;
    @AuraEnabled
    public String dob;
    @AuraEnabled
    public String gender;
    @AuraEnabled
    public String bloodGroup;
    @AuraEnabled
    public String nationality;
    @AuraEnabled
    public String languagesKnown;
    @AuraEnabled
    public String twitter;
    @AuraEnabled
    public String registeredDate;
    @AuraEnabled
    public String lastLogin;
    @AuraEnabled
    public String mailingCity;
    @AuraEnabled
    public String mailingState;
    @AuraEnabled
    public String mailingCountry;
    // Snapshot values the admin 360 Overview shows as labelled rows. The
    // portal previously surfaced these only inside the hero, so they had
    // no label and could not be read as data.
    @AuraEnabled
    public String classOf;
    @AuraEnabled
    public String currentEmployer;
    @AuraEnabled
    public String currentRole;
    @AuraEnabled
    public String careerSince;
    @AuraEnabled
    public String careerRolesHeld;
    @AuraEnabled
    public String careerLocation;
  }

  public class EventRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String when_x;
    @AuraEnabled
    public String details;
  }

  public class MentorshipRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String sessions;
    @AuraEnabled
    public String since;
    @AuraEnabled
    public String status;
  }

  public class ReferralRow {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String classOf;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String company;
    @AuraEnabled
    public String status;
  }

  /**
   * Mirrors the admin 360 Engagement tab one-for-one, including the counters
   * and lists that have no data source yet (referrals, talks on campus,
   * events hosted). Those come back 0/empty exactly as they do in admin —
   * they are surfaced rather than hidden so the portal and admin show the
   * same shape, and so an empty one reads as "nothing yet" not "missing".
   */
  public class EngagementData {
    @AuraEnabled
    public Integer eventsAttendedCount;
    @AuraEnabled
    public Integer activeMenteesCount;
    @AuraEnabled
    public Integer totalReferralsCount;
    @AuraEnabled
    public Integer talksOnCampusCount;
    // Low / Medium / High - the same tier the admin 360 Engagement
    // snapshot card shows, derived from the two counts above.
    @AuraEnabled
    public String engagementScore;
    @AuraEnabled
    public List<EventRow> eventsAttended;
    @AuraEnabled
    public List<EventRow> eventsHosted;
    @AuraEnabled
    public List<MentorshipRow> mentorship;
    @AuraEnabled
    public List<ReferralRow> hiringReferrals;
  }

  public class TicketRow {
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String subject;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String openedDate;
    @AuraEnabled
    public String priority;
    @AuraEnabled
    public String owner;
    @AuraEnabled
    public String origin;
    @AuraEnabled
    public String closedDate;
  }

  public class SurveyRow {
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String details;
    @AuraEnabled
    public String score;
    @AuraEnabled
    public String sentiment;
  }

  public class SupportData {
    @AuraEnabled
    public Integer ticketsRaisedCount;
    @AuraEnabled
    public Integer currentlyOpenCount;
    @AuraEnabled
    public String avgFirstResponse;
    @AuraEnabled
    public Integer surveysSubmittedCount;
    @AuraEnabled
    public List<TicketRow> tickets;
    @AuraEnabled
    public List<SurveyRow> surveys;
  }

  public class ActivityItem {
    @AuraEnabled
    public String iconKey;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String when_x;
  }

  public class RecordHealthItem {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean ok;
    @AuraEnabled
    public String missingNote;
  }

  public class EducationRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String degree;
    @AuraEnabled
    public String institution;
    @AuraEnabled
    public String duration;
    @AuraEnabled
    public String score;
    @AuraEnabled
    public String startMonth;
    @AuraEnabled
    public String startYear;
    @AuraEnabled
    public String endMonth;
    @AuraEnabled
    public String endYear;
    @AuraEnabled
    public String gradingFormat;
    @AuraEnabled
    public String cgpa;
    @AuraEnabled
    public String programPlan;
    @AuraEnabled
    public String programName;
    @AuraEnabled
    public String registrationNumber;
    @AuraEnabled
    public String institutionType;
  }

  public class ExperienceRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String position;
    @AuraEnabled
    public String company;
    @AuraEnabled
    public String employmentType;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String workType;
    @AuraEnabled
    public String duration;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Boolean isCurrentJob;
    @AuraEnabled
    public String startMonth;
    @AuraEnabled
    public String startYear;
    @AuraEnabled
    public String endMonth;
    @AuraEnabled
    public String endYear;
    @AuraEnabled
    public String jobRole;
  }

  public class AchievementRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String organization;
    @AuraEnabled
    public String meta;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public String dateMonth;
    @AuraEnabled
    public String dateYear;
    @AuraEnabled
    public String patentNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String role;
    @AuraEnabled
    public String referenceUrl;
    @AuraEnabled
    public String paperType;
  }

  public class EducationInput {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String degree { get; set; }
    @AuraEnabled
    public String institution { get; set; }
    @AuraEnabled
    public String startMonth { get; set; }
    @AuraEnabled
    public String startYear { get; set; }
    @AuraEnabled
    public String endMonth { get; set; }
    @AuraEnabled
    public String endYear { get; set; }
    @AuraEnabled
    public String gradingFormat { get; set; }
    @AuraEnabled
    public String cgpa { get; set; }
    @AuraEnabled
    public String institutionType { get; set; }
    @AuraEnabled
    public String programPlan { get; set; }
    @AuraEnabled
    public String registrationNumber { get; set; }
  }

  public class ExperienceInput {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String jobTitle { get; set; }
    @AuraEnabled
    public String organization { get; set; }
    @AuraEnabled
    public String employmentType { get; set; }
    @AuraEnabled
    public String location { get; set; }
    @AuraEnabled
    public String startMonth { get; set; }
    @AuraEnabled
    public String startYear { get; set; }
    @AuraEnabled
    public String endMonth { get; set; }
    @AuraEnabled
    public String endYear { get; set; }
    @AuraEnabled
    public Boolean isCurrentJob { get; set; }
    @AuraEnabled
    public String roleDescription { get; set; }
    @AuraEnabled
    public String workType { get; set; }
    @AuraEnabled
    public String jobRole { get; set; }
  }

  public class AchievementInput {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String type { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String organization { get; set; }
    @AuraEnabled
    public String dateMonth { get; set; }
    @AuraEnabled
    public String dateYear { get; set; }
    @AuraEnabled
    public String description { get; set; }
    @AuraEnabled
    public String patentNumber { get; set; }
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public String role { get; set; }
    @AuraEnabled
    public String referenceUrl { get; set; }
    @AuraEnabled
    public String paperType { get; set; }
  }

  @AuraEnabled(cacheable=false)
  public static ProfileData getMyProfile() {
    return buildProfileData(getCurrentUserAccountId());
  }

  /**
   * Same profile data, for an admin viewing someone else's record through
   * the shared kenMyProfile component (e.g. the Alumni 360 view). Denied
   * unless the running user holds an Alumni admin or coordinator permission set, or the target
   * happens to be their own account.
   */
  @AuraEnabled(cacheable=false)
  public static ProfileData getProfileFor(Id targetAccountId) {
    assertCanView(targetAccountId);
    return buildProfileData(targetAccountId);
  }

  private static ProfileData buildProfileData(Id accountId) {
    if (accountId == null) {
      return buildEmptyProfile();
    }

    List<Account> accountRows = [
      SELECT
        Id,
        Name,
        PersonTitle,
        PersonEmail,
        PersonMobilePhone,
        PersonMailingCity,
        PersonMailingState,
        PersonMailingCountry,
        PhotoUrl,
        Profile_Photo_URL__c,
        Description,
        Linkedin_Profile_URL__c,
        Last_Active__c,
        Twitter_Profile_URL__c,
        Nationality__c,
        Languages_Known__c,
        Blood_Group__c,
        PersonGenderIdentity,
        PersonBirthdate
      FROM Account
      WHERE Id = :accountId AND IsPersonAccount = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (accountRows.isEmpty()) {
      return buildEmptyProfile();
    }

    Account acc = accountRows[0];

    Id constituentRoleId = getActiveConstituentRoleId(accountId);
    List<ConstituentRole> roleRows = constituentRoleId != null
      ? [
          SELECT
            Id,
            Graduation_Year__c,
            Registration_Number__c,
            Year_of_Enrollment__c,
            Registration_Status__c,
            CreatedDate,
            Last_Login__c,
            Program_Plan__r.Name
          FROM ConstituentRole
          WHERE Id = :constituentRoleId
          WITH SECURITY_ENFORCED
          LIMIT 1
        ]
      : [
          SELECT
            Id,
            Graduation_Year__c,
            Registration_Number__c,
            Year_of_Enrollment__c,
            Registration_Status__c,
            CreatedDate,
            Last_Login__c,
            Program_Plan__r.Name
          FROM ConstituentRole
          WHERE PersonId = :accountId AND RoleType = 'Alumni'
          WITH SECURITY_ENFORCED
          ORDER BY CreatedDate DESC
          LIMIT 1
        ];
    ConstituentRole role = roleRows.isEmpty() ? null : roleRows[0];
    String mailingLocation = KenAlumniProfileService.currentLocation(accountId);

    List<EducationRow> educationRows = queryEducationRows(accountId);
    List<ExperienceRow> experienceRows = queryExperienceRows(accountId);
    List<AchievementRow> achievementRows = queryAchievementRows(accountId);

    ExperienceRow latestJob = experienceRows.isEmpty()
      ? null
      : experienceRows[0];

    ProfileData profile = new ProfileData();
    profile.accountId = accountId;
    profile.name = acc.Name;
    profile.title = firstNonBlank(
      latestJob != null ? latestJob.position : null,
      acc.PersonTitle
    );
    profile.company = latestJob != null ? latestJob.company : null;
    profile.location = buildLocation(acc, mailingLocation, latestJob);
    profile.profileImage = resolveProfileImage(acc);
    profile.isOnline = isCurrentlyOnline(acc.Last_Active__c);
    profile.batch = String.isNotBlank(
        role != null ? role.Graduation_Year__c : null
      )
      ? 'Batch ' + role.Graduation_Year__c
      : null;
    profile.expertise = null;
    profile.email = acc.PersonEmail;
    profile.phone = acc.PersonMobilePhone;
    profile.linkedin = acc.Linkedin_Profile_URL__c;
    profile.willingToHelp = true;
    profile.about = acc.Description;
    profile.registrationNumber = role != null
      ? role.Registration_Number__c
      : null;
    profile.education = educationRows;
    profile.experience = experienceRows;
    profile.achievements = achievementRows;
    profile.alumniStatus = role != null ? role.Registration_Status__c : null;
    profile.yearOfEnrollment = role != null ? role.Year_of_Enrollment__c : null;
    profile.program = (role != null &&
      role.Program_Plan__r != null)
      ? role.Program_Plan__r.Name
      : null;
    profile.yearsPostGrad = yearsPostGradLabel(
      role != null ? role.Graduation_Year__c : null
    );
    profile.registeredDate = (role != null &&
      role.CreatedDate != null)
      ? role.CreatedDate.format('dd MMM yyyy')
      : null;
    profile.lastLogin = (role != null &&
      role.Last_Login__c != null)
      ? role.Last_Login__c.format('dd MMM yyyy')
      : null;
    profile.dob = acc.PersonBirthdate != null
      ? Datetime.newInstance(
            acc.PersonBirthdate.year(),
            acc.PersonBirthdate.month(),
            acc.PersonBirthdate.day()
          )
          .format('dd MMM yyyy')
      : null;
    profile.gender = acc.PersonGenderIdentity;
    profile.bloodGroup = acc.Blood_Group__c;
    profile.nationality = acc.Nationality__c;
    profile.languagesKnown = acc.Languages_Known__c;
    profile.twitter = acc.Twitter_Profile_URL__c;

    // Ken_Address__c (Mailing) is where the portal and admin 360 actually source
    // the alumnus's address from (see KenAlumniProfileService.currentLocation and
    // KenAdminAlumni360Controller.kenAddressFallback) — Account.PersonMailing* is
    // rarely populated in this org and is only a last-resort fallback here.
    KenAddressParts address = queryKenAddress(accountId);
    profile.mailingCity = firstNonBlank(address.city, acc.PersonMailingCity);
    profile.mailingState = firstNonBlank(address.state, acc.PersonMailingState);
    profile.mailingCountry = firstNonBlank(
      address.country,
      acc.PersonMailingCountry
    );

    // Snapshot rows. "Class of" and the employment pair were previously
    // only visible inside the hero, so they carried no label; the admin 360
    // Overview lists them explicitly and the Personal tab now matches it.
    profile.classOf = role != null ? role.Graduation_Year__c : null;

    ExperienceRow currentJob = null;
    for (ExperienceRow r : experienceRows) {
      if (r.isCurrentJob == true) {
        currentJob = r;
        break;
      }
    }
    if (currentJob == null)
      currentJob = latestJob;
    if (currentJob != null) {
      profile.currentEmployer = currentJob.company;
      profile.currentRole = firstNonBlank(
        currentJob.position,
        currentJob.jobRole
      );
      profile.careerLocation = currentJob.location;
      profile.careerSince = buildMonthYearLabel(
        currentJob.startMonth,
        currentJob.startYear
      );
    }
    profile.careerRolesHeld = String.valueOf(experienceRows.size());
    return profile;
  }

  private static final List<String> MONTH_ABBR = new List<String>{
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  };

  /**
   * "Mar 2021" from the month/year pair the experience rows carry. The rows
   * store the month two-digit ("03"), so it is mapped to a name here rather
   * than rendered as "03 2021".
   */
  private static String buildMonthYearLabel(
    String monthValue,
    String yearValue
  ) {
    if (String.isBlank(yearValue))
      return null;
    if (String.isBlank(monthValue))
      return yearValue;
    try {
      Integer m = Integer.valueOf(monthValue.trim());
      if (m >= 1 && m <= 12)
        return MONTH_ABBR[m - 1] + ' ' + yearValue;
    } catch (Exception ex) {
      /* fall through to the raw value */
    }
    return monthValue + ' ' + yearValue;
  }

  private class KenAddressParts {
    String city;
    String state;
    String country;
  }

  private static KenAddressParts queryKenAddress(Id accountId) {
    KenAddressParts parts = new KenAddressParts();
    if (accountId == null) {
      return parts;
    }
    for (Ken_Address__c addr : [
      SELECT City__c, State__c, Country__c
      FROM Ken_Address__c
      WHERE Person_Account__c = :accountId AND Address_Type__c = 'Mailing'
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ]) {
      parts.city = addr.City__c;
      parts.state = addr.State__c;
      parts.country = addr.Country__c;
    }
    return parts;
  }

  private static String yearsPostGradLabel(String graduationYear) {
    if (String.isBlank(graduationYear)) {
      return null;
    }
    Integer gradYear;
    try {
      gradYear = Integer.valueOf(graduationYear);
    } catch (Exception e) {
      return null;
    }
    Integer years = Date.today().year() - gradYear;
    if (years < 0) {
      return null;
    }
    return String.valueOf(years) + (years == 1 ? ' year' : ' years');
  }

  /**
   * Engagement tab data. Lazily loaded on tab select rather than folded into
   * getMyProfile(), since Ken_Event_Booking__c/Ken_Mentorship__c are separate
   * queries the About Me tab never needs.
   */
  @AuraEnabled(cacheable=true)
  public static EngagementData getMyEngagement() {
    return buildEngagementData(getCurrentUserAccountId());
  }

  @AuraEnabled(cacheable=true)
  public static EngagementData getEngagementFor(Id targetAccountId) {
    assertCanView(targetAccountId);
    return buildEngagementData(targetAccountId);
  }

  private static EngagementData buildEngagementData(Id accountId) {
    EngagementData data = new EngagementData();
    data.eventsAttendedCount = 0;
    data.activeMenteesCount = 0;
    // No source objects for these yet — admin 360 hardcodes them to 0 /
    // empty too, so the portal mirrors that rather than inventing values.
    data.totalReferralsCount = 0;
    data.talksOnCampusCount = 0;
    data.eventsAttended = new List<EventRow>();
    data.eventsHosted = new List<EventRow>();
    data.mentorship = new List<MentorshipRow>();
    data.hiringReferrals = new List<ReferralRow>();

    if (accountId == null) {
      return data;
    }

    try {
      List<Ken_Event_Booking__c> bookings = [
        SELECT
          Id,
          CreatedDate,
          Type__c,
          Schedules_Sessions__c,
          Schedules_Sessions__r.Name,
          Schedules_Sessions__r.Event_Reference__c
        FROM Ken_Event_Booking__c
        WHERE Person_Account__c = :accountId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
        LIMIT 50
      ];
      data.eventsAttendedCount = bookings.size();

      Set<Id> eventIds = new Set<Id>();
      for (Ken_Event_Booking__c b : bookings) {
        if (
          b.Schedules_Sessions__c != null &&
          b.Schedules_Sessions__r.Event_Reference__c != null
        ) {
          eventIds.add(b.Schedules_Sessions__r.Event_Reference__c);
        }
      }
      Map<Id, Ken_Event_Master__c> eventById = new Map<Id, Ken_Event_Master__c>();
      if (!eventIds.isEmpty()) {
        eventById = new Map<Id, Ken_Event_Master__c>(
          [
            SELECT Id, Name, Start_Date__c
            FROM Ken_Event_Master__c
            WHERE Id IN :eventIds
            WITH SECURITY_ENFORCED
          ]
        );
      }
      for (Ken_Event_Booking__c b : bookings) {
        Ken_Event_Master__c ev;
        if (
          b.Schedules_Sessions__c != null &&
          b.Schedules_Sessions__r.Event_Reference__c != null
        ) {
          ev = eventById.get(b.Schedules_Sessions__r.Event_Reference__c);
        }
        EventRow row = new EventRow();
        row.id = b.Id;
        row.title = (ev != null &&
          ev.Name != null)
          ? ev.Name
          : (b.Schedules_Sessions__r != null
              ? b.Schedules_Sessions__r.Name
              : 'Event');
        Date whenDate = (ev != null &&
          ev.Start_Date__c != null)
          ? ev.Start_Date__c
          : (b.CreatedDate != null ? b.CreatedDate.date() : null);
        row.when_x = whenDate != null
          ? Datetime.newInstance(
                whenDate.year(),
                whenDate.month(),
                whenDate.day()
              )
              .format('MMM yyyy')
          : null;
        row.details = b.Type__c;
        data.eventsAttended.add(row);
      }
    } catch (Exception ex) {
      /* leave empty */
    }

    try {
      List<Ken_Mentorship__c> sessions = [
        SELECT
          Id,
          Mentee__c,
          Mentee__r.Name,
          Mentorship_Status__c,
          Meet_Start_DateTime__c
        FROM Ken_Mentorship__c
        WHERE Mentor__c = :accountId
        WITH SECURITY_ENFORCED
        ORDER BY Meet_Start_DateTime__c DESC NULLS LAST
        LIMIT 50
      ];
      Map<Id, List<Ken_Mentorship__c>> byMentee = new Map<Id, List<Ken_Mentorship__c>>();
      for (Ken_Mentorship__c m : sessions) {
        if (m.Mentee__c == null)
          continue;
        if (!byMentee.containsKey(m.Mentee__c))
          byMentee.put(m.Mentee__c, new List<Ken_Mentorship__c>());
        byMentee.get(m.Mentee__c).add(m);
      }
      Integer activeCount = 0;
      for (Id menteeId : byMentee.keySet()) {
        List<Ken_Mentorship__c> sess = byMentee.get(menteeId);
        MentorshipRow row = new MentorshipRow();
        row.id = menteeId;
        row.name = (sess[0].Mentee__r != null) ? sess[0].Mentee__r.Name : '—';
        row.sessions =
          sess.size() + (sess.size() == 1 ? ' session' : ' sessions');
        Date earliest;
        Boolean isActive = false;
        for (Ken_Mentorship__c m : sess) {
          if (m.Meet_Start_DateTime__c != null) {
            Date d = m.Meet_Start_DateTime__c.date();
            if (earliest == null || d < earliest)
              earliest = d;
          }
          if (
            m.Mentorship_Status__c == 'Accepted' ||
            m.Mentorship_Status__c == 'Scheduled'
          )
            isActive = true;
        }
        row.since = earliest != null
          ? Datetime.newInstance(
                earliest.year(),
                earliest.month(),
                earliest.day()
              )
              .format('MMM yyyy')
          : null;
        row.status = isActive ? 'Active' : 'Concluded';
        if (isActive)
          activeCount++;
        data.mentorship.add(row);
      }
      data.activeMenteesCount = activeCount;
    } catch (Exception ex) {
      /* leave empty */
    }

    // Same tier rule as the admin 360 Engagement snapshot card.
    if (data.eventsAttendedCount >= 6 || data.activeMenteesCount >= 3) {
      data.engagementScore = 'High';
    } else if (data.eventsAttendedCount >= 3 || data.activeMenteesCount >= 1) {
      data.engagementScore = 'Medium';
    } else {
      data.engagementScore = 'Low';
    }

    return data;
  }

  /**
   * Support tab data. Service & Support (Case) is not part of the product,
   * so this returns the same empty shape the admin 360 "Support" tab does.
   */
  @AuraEnabled(cacheable=true)
  public static SupportData getMySupport() {
    return buildSupportData();
  }

  @AuraEnabled(cacheable=true)
  public static SupportData getSupportFor(Id targetAccountId) {
    assertCanView(targetAccountId);
    return buildSupportData();
  }

  private static SupportData buildSupportData() {
    SupportData data = new SupportData();
    data.ticketsRaisedCount = 0;
    data.currentlyOpenCount = 0;
    data.avgFirstResponse = null;
    data.surveysSubmittedCount = 0;
    data.tickets = new List<TicketRow>();
    data.surveys = new List<SurveyRow>();
    return data;
  }

  /**
   * The alumnus's own "Recent activity" rail — the same real signals the
   * admin 360 right rail shows (profile update, event booking, mentor
   * session), each the single most recent row of its kind,
   * sorted newest-first. Deliberately NOT the staff Task/Chatter timeline
   * (KenAdminAlumniController.getActivityTimeline) — that one can carry
   * internal admin notes about the alum and stays admin-only.
   */
  @AuraEnabled(cacheable=true)
  public static List<ActivityItem> getMyRecentActivity() {
    return buildRecentActivity(getCurrentUserAccountId());
  }

  @AuraEnabled(cacheable=true)
  public static List<ActivityItem> getRecentActivityFor(Id targetAccountId) {
    assertCanView(targetAccountId);
    return buildRecentActivity(targetAccountId);
  }

  private static List<ActivityItem> buildRecentActivity(Id accountId) {
    List<ActivityItem> items = new List<ActivityItem>();
    if (accountId == null) {
      return items;
    }

    List<Map<String, Object>> signals = new List<Map<String, Object>>();

    for (ConstituentRole cr : [
      SELECT LastModifiedDate
      FROM ConstituentRole
      WHERE PersonId = :accountId AND RoleType = 'Alumni'
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ]) {
      if (cr.LastModifiedDate != null) {
        signals.add(
          new Map<String, Object>{
            'icon' => 'star',
            'title' => 'Profile updated',
            'date' => cr.LastModifiedDate
          }
        );
      }
    }

    try {
      List<Ken_Event_Booking__c> evb = [
        SELECT CreatedDate
        FROM Ken_Event_Booking__c
        WHERE Person_Account__c = :accountId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!evb.isEmpty()) {
        signals.add(
          new Map<String, Object>{
            'icon' => 'heart',
            'title' => 'Event booking',
            'date' => evb[0].CreatedDate
          }
        );
      }
    } catch (Exception ex) {
      /* leave out */
    }

    try {
      List<Ken_Mentorship__c> mn = [
        SELECT CreatedDate
        FROM Ken_Mentorship__c
        WHERE Mentor__c = :accountId
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!mn.isEmpty()) {
        signals.add(
          new Map<String, Object>{
            'icon' => 'mentor',
            'title' => 'Mentor session logged',
            'date' => mn[0].CreatedDate
          }
        );
      }
    } catch (Exception ex) {
      /* leave out */
    }

    for (Integer i = 0; i < signals.size(); i++) {
      for (Integer j = i + 1; j < signals.size(); j++) {
        Datetime di = (Datetime) signals[i].get('date');
        Datetime dj = (Datetime) signals[j].get('date');
        if (dj != null && (di == null || dj > di)) {
          Map<String, Object> tmp = signals[i];
          signals[i] = signals[j];
          signals[j] = tmp;
        }
      }
    }

    for (Map<String, Object> s : signals) {
      ActivityItem item = new ActivityItem();
      item.iconKey = (String) s.get('icon');
      item.title = (String) s.get('title');
      item.when_x = relativeWhen((Datetime) s.get('date'));
      items.add(item);
    }
    return items;
  }

  private static String relativeWhen(Datetime dt) {
    if (dt == null)
      return null;
    Long diffMs = Datetime.now().getTime() - dt.getTime();
    Long mins = diffMs / 60000;
    if (mins < 1)
      return 'just now';
    if (mins < 60)
      return mins + ' min ago';
    Long hours = mins / 60;
    if (hours < 24)
      return hours + ' hr ago';
    Long days = hours / 24;
    if (days == 1)
      return 'Yesterday';
    if (days < 7)
      return days + ' days ago';
    if (days < 30)
      return (days / 7) + ' weeks ago';
    if (days < 365)
      return (days / 30) + ' months ago';
    return (days / 365) + ' years ago';
  }

  /**
   * Profile-completeness checklist — the same 5 real checks the admin 360
   * "Record health" panel runs, scoped to the current user.
   */
  @AuraEnabled(cacheable=true)
  public static List<RecordHealthItem> getMyRecordHealth() {
    return buildRecordHealth(getCurrentUserAccountId());
  }

  @AuraEnabled(cacheable=true)
  public static List<RecordHealthItem> getRecordHealthFor(Id targetAccountId) {
    assertCanView(targetAccountId);
    return buildRecordHealth(targetAccountId);
  }

  private static List<RecordHealthItem> buildRecordHealth(Id accountId) {
    List<RecordHealthItem> items = new List<RecordHealthItem>();
    if (accountId == null) {
      return items;
    }

    Boolean emailOk = false;
    Boolean photoOk = false;
    Boolean linkedinOk = false;
    try {
      Boolean hasBounceField = Account.SObjectType.getDescribe()
        .fields.getMap()
        .containsKey('personemailbounceddate');
      String emailSoql = hasBounceField
        ? 'SELECT PersonEmail, PersonEmailBouncedDate, Profile_Photo_URL__c, Linkedin_Profile_URL__c FROM Account WHERE Id = :accountId LIMIT 1'
        : 'SELECT PersonEmail, Profile_Photo_URL__c, Linkedin_Profile_URL__c FROM Account WHERE Id = :accountId LIMIT 1';
      List<Account> accts = Database.query(emailSoql);
      if (!accts.isEmpty()) {
        emailOk =
          accts[0].get('PersonEmail') != null &&
          (!hasBounceField || accts[0].get('PersonEmailBouncedDate') == null);
        photoOk = String.isNotBlank(
          (String) accts[0].get('Profile_Photo_URL__c')
        );
        linkedinOk = String.isNotBlank(
          (String) accts[0].get('Linkedin_Profile_URL__c')
        );
      }
    } catch (Exception ex) {
      /* leave defaults */
    }

    Boolean employerOk = false;
    try {
      Integer cnt = [
        SELECT COUNT()
        FROM PersonEmployment
        WHERE
          AccountId = :accountId
          AND Currently_Employed__c = TRUE
          AND Is_Archived__c = FALSE
          WITH SECURITY_ENFORCED
      ];
      employerOk = (cnt > 0);
    } catch (Exception ex) {
      /* leave false */
    }

    Boolean mentorOk = false;
    try {
      Integer cnt = [
        SELECT COUNT()
        FROM Ken_Alumni_Preferences__c
        WHERE
          Person_Account__c = :accountId
          AND Willing_to_be_a_mentor__c = TRUE
          WITH SECURITY_ENFORCED
      ];
      mentorOk = (cnt > 0);
    } catch (Exception ex) {
      /* leave false */
    }

    items.add(
      healthItem(
        'Alumni email active',
        emailOk,
        emailOk ? null : 'Missing or bounced'
      )
    );
    items.add(
      healthItem(
        'Employer current and verified',
        employerOk,
        employerOk ? null : 'No current employment'
      )
    );
    items.add(
      healthItem('Profile photo added', photoOk, photoOk ? null : 'Missing')
    );
    items.add(
      healthItem(
        'LinkedIn profile linked',
        linkedinOk,
        linkedinOk ? null : 'Not linked'
      )
    );
    items.add(
      healthItem(
        'Mentor profile complete',
        mentorOk,
        mentorOk ? null : 'Not opted-in'
      )
    );
    return items;
  }

  private static RecordHealthItem healthItem(
    String label,
    Boolean ok,
    String missingNote
  ) {
    RecordHealthItem item = new RecordHealthItem();
    item.label = label;
    item.ok = ok;
    item.missingNote = missingNote;
    return item;
  }

  /**
   * Creates or updates one education row for the current user. A payload with
   * no id that matches a row already on file for the same institute, degree
   * and completion year updates that row rather than inserting a duplicate.
   * ContactId is mirrored on every save because only that side of
   * PersonEducation is related-list enabled on the Person Account page.
   */
  @AuraEnabled
  public static Id saveEducation(EducationInput input) {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }
    if (input == null) {
      throw new AuraHandledException('Education payload was empty.');
    }

    String institutionName = sanitize(input.institution);
    String degreeName = sanitize(input.degree);
    String completionYear = sanitize(input.endYear);

    PersonEducation recordRow;
    if (input.id != null) {
      List<PersonEducation> existingRows = [
        SELECT Id
        FROM PersonEducation
        WHERE Id = :input.id AND AccountId = :accountId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (existingRows.isEmpty()) {
        throw new AuraHandledException('Education record not found.');
      }
      recordRow = existingRows[0];
    } else {
      recordRow = findDuplicateEducation(
        accountId,
        institutionName,
        degreeName,
        completionYear
      );
      if (recordRow == null) {
        recordRow = new PersonEducation();
        recordRow.AccountId = accountId;
      }
    }

    Id personContactId = resolvePersonContactId(accountId);
    if (personContactId != null)
      recordRow.ContactId = personContactId;

    // PersonEducation.Name has the standard label "Degree" and is required. Mirror it
    // into Degree_Name__c (matches KjsUat pattern); reads use Degree_Name__c.
    recordRow.Name = String.isNotBlank(degreeName) ? degreeName : 'Degree';
    recordRow.Degree_Name__c = degreeName;
    recordRow.Institute_Name__c = institutionName;
    recordRow.StartDate = buildDate(input.startYear, input.startMonth);
    recordRow.EndDate = buildDate(input.endYear, input.endMonth);
    recordRow.Year_of_Completion__c = completionYear;
    recordRow.Grade_Type__c = normalizeGradeType(input.gradingFormat);
    recordRow.Grade__c = sanitize(input.cgpa);
    recordRow.Is_Archived__c = false;
    if (String.isNotBlank(input.institutionType)) {
      recordRow.Institution_Type__c = (input.institutionType == 'other')
        ? INST_TYPE_OTHER
        : INST_TYPE_OWN;
    }

    Id planId = null;
    if (String.isNotBlank(input.programPlan)) {
      try {
        planId = (Id) input.programPlan;
      } catch (Exception e) {
        planId = null;
      }
    }
    recordRow.Program_Plan__c = planId;
    recordRow.Registration_Number__c = sanitize(input.registrationNumber);
    if (!Schema.sObjectType.PersonEducation.isCreateable() || !Schema.sObjectType.PersonEducation.isUpdateable()) {
      throw new KenCrudException('PersonEducation is not upsertable by the current user.');
    }

    upsert recordRow;
    return recordRow.Id;
  }

  /** Person Account's contact id, used to keep child records related-list visible. */
  private static Id resolvePersonContactId(Id accountId) {
    if (accountId == null)
      return null;
    for (Account a : [SELECT PersonContactId FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1]) {
      return a.PersonContactId;
    }
    return null;
  }

  /**
   * Returns the unarchived education row already on file for the same
   * institute, degree and completion year, or null when there is none.
   * Rows with neither an institute nor a degree are never matched so the
   * partially-filled onboarding seed can still be completed on its own.
   */
  private static PersonEducation findDuplicateEducation(
    Id accountId,
    String institution,
    String degree,
    String completionYear
  ) {
    if (
      accountId == null ||
      (String.isBlank(institution) && String.isBlank(degree))
    ) {
      return null;
    }
    String wantInstitute = (institution == null)
      ? ''
      : institution.toLowerCase();
    String wantDegree = (degree == null) ? '' : degree.toLowerCase();
    String wantYear = (completionYear == null) ? '' : completionYear;

    for (PersonEducation pe : [
      SELECT Id, Institute_Name__c, Degree_Name__c, Year_of_Completion__c
      FROM PersonEducation
      WHERE
        AccountId = :accountId
        AND (Is_Archived__c = FALSE
        OR Is_Archived__c = NULL)
      WITH SECURITY_ENFORCED
      LIMIT 200
    ]) {
      String haveInstitute = (pe.Institute_Name__c == null)
        ? ''
        : pe.Institute_Name__c.toLowerCase();
      String haveDegree = (pe.Degree_Name__c == null)
        ? ''
        : pe.Degree_Name__c.toLowerCase();
      String haveYear = (pe.Year_of_Completion__c == null)
        ? ''
        : pe.Year_of_Completion__c;
      if (
        haveInstitute == wantInstitute &&
        haveDegree == wantDegree &&
        haveYear == wantYear
      ) {
        return pe;
      }
    }
    return null;
  }
  @AuraEnabled
  public static void archiveEducation(Id recordId) {
    if (recordId == null) {
      throw new AuraHandledException('Education record id is required.');
    }
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }

    List<PersonEducation> rows = [
      SELECT Id, Is_Archived__c
      FROM PersonEducation
      WHERE Id = :recordId AND AccountId = :accountId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return;
    }
    delete rows[0];
  }

  @AuraEnabled
  public static Id saveExperience(ExperienceInput input) {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }
    if (input == null) {
      throw new AuraHandledException('Experience payload was empty.');
    }

    PersonEmployment row;
    if (input != null && input.id != null) {
      List<PersonEmployment> existingRows = [
        SELECT Id
        FROM PersonEmployment
        WHERE Id = :input.id AND AccountId = :accountId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (existingRows.isEmpty()) {
        throw new AuraHandledException('Experience record not found.');
      }
      row = existingRows[0];
    } else {
      row = new PersonEmployment();
      row.AccountId = accountId;
      // PersonEmployment.RelatedPersonId is required in this org and points to the
      // Person's Contact (PersonContactId on the underlying PersonAccount).
      List<Account> personAccts = [
        SELECT PersonContactId FROM Account WHERE Id = :accountId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!personAccts.isEmpty() && personAccts[0].PersonContactId != null) {
        row.RelatedPersonId = personAccts[0].PersonContactId;
      }
    }

    String companyName = sanitize(input != null ? input.organization : null);
    String jobTitle = sanitize(input != null ? input.jobTitle : null);
    Boolean isCurrent = input != null && input.isCurrentJob == true;

    // PersonEmployment.Name has the standard label "Employer" and is required. Mirror it
    // into Company_Name__c (matches KjsUat pattern); reads use Company_Name__c.
    row.Name = String.isNotBlank(companyName) ? companyName : 'Employer';
    row.Designation__c = jobTitle;
    row.Company_Name__c = companyName;
    row.EmploymentType = normalizeEmploymentType(
      input != null ? input.employmentType : null
    );
    row.Job_Role__c = normalizeJobRole(input != null ? input.jobRole : null);
    row.Location__c = sanitize(input != null ? input.location : null);
    row.EmploymentSite = normalizeLocationType(
      input != null ? input.workType : null
    );
    row.StartDate = buildDate(
      input != null ? input.startYear : null,
      input != null ? input.startMonth : null
    );
    row.Currently_Employed__c = isCurrent;
    row.EndDate = isCurrent
      ? null
      : buildDate(
          input != null ? input.endYear : null,
          input != null ? input.endMonth : null
        );
    row.Description__c = input != null ? input.roleDescription : null;
    row.Is_Archived__c = false;

    if (!Schema.sObjectType.PersonEmployment.isCreateable() || !Schema.sObjectType.PersonEmployment.isUpdateable()) {
      throw new KenCrudException('PersonEmployment is not upsertable by the current user.');
    }
    upsert row;
    return row.Id;
  }

  @AuraEnabled
  public static void archiveExperience(Id recordId) {
    if (recordId == null) {
      throw new AuraHandledException('Experience record id is required.');
    }
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }

    List<PersonEmployment> rows = [
      SELECT Id, Is_Archived__c
      FROM PersonEmployment
      WHERE Id = :recordId AND AccountId = :accountId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return;
    }
    delete rows[0];
  }

  @AuraEnabled
  public static Id saveAchievement(AchievementInput input) {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }
    if (input == null) {
      throw new AuraHandledException('Achievement payload was empty.');
    }

    Ken_Achievement__c row;
    if (input != null && input.id != null) {
      List<Ken_Achievement__c> existingRows = [
        SELECT Id
        FROM Ken_Achievement__c
        WHERE Id = :input.id AND Person_Account__c = :accountId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (existingRows.isEmpty()) {
        throw new AuraHandledException('Achievement record not found.');
      }
      row = existingRows[0];
    } else {
      row = new Ken_Achievement__c();
      row.Person_Account__c = accountId;
    }

    row.Achievement_Type__c = normalizeAchievementType(
      input != null ? input.type : null
    );
    row.Title__c = sanitize(input != null ? input.title : null);
    row.Issuing_Organisation__c = sanitize(
      input != null ? input.organization : null
    );
    row.Date__c = buildDate(
      input != null ? input.dateYear : null,
      input != null ? input.dateMonth : null
    );
    row.Description__c = sanitize(input != null ? input.description : null);
    row.Application_or_Patent_Number__c = keepOnlyDigits(
      input != null ? input.patentNumber : null
    );
    row.Achievement_Status__c = normalizeAchievementStatus(
      input != null ? input.status : null
    );
    row.Role__c = normalizeAchievementRole(input != null ? input.role : null);
    row.Reference_URL__c = sanitize(input != null ? input.referenceUrl : null);
    row.Paper_Type__c = normalizePaperType(
      input != null ? input.paperType : null
    );
    row.Is_Archived__c = false;

    if (!Schema.sObjectType.Ken_Achievement__c.isCreateable() || !Schema.sObjectType.Ken_Achievement__c.isUpdateable()) {
      throw new KenCrudException('Ken_Achievement__c is not upsertable by the current user.');
    }
    upsert row;
    return row.Id;
  }

  @AuraEnabled
  public static void archiveAchievement(Id recordId) {
    if (recordId == null) {
      throw new AuraHandledException('Achievement record id is required.');
    }
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }

    List<Ken_Achievement__c> rows = [
      SELECT Id, Is_Archived__c
      FROM Ken_Achievement__c
      WHERE Id = :recordId AND Person_Account__c = :accountId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      return;
    }
    delete rows[0];
  }

  @AuraEnabled
  public static void saveAbout(String aboutText) {
    Id accountId = getCurrentUserAccountId();
    if (accountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }

    List<Account> rows = [
      SELECT Id, Description
      FROM Account
      WHERE Id = :accountId AND IsPersonAccount = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (rows.isEmpty()) {
      throw new AuraHandledException('Account not found.');
    }

    Account pa = rows[0];
    pa.Description = sanitize(aboutText);
    new AccountUpdater().doUpdate(pa);
  }

  private without sharing class AccountUpdater {
    void doUpdate(Account record) {
      if (!Schema.sObjectType.Account.isUpdateable()) {
        throw new KenCrudException('Account is not updateable by the current user.');
      }
      update record;
    }
  }

  private static ProfileData buildEmptyProfile() {
    ProfileData profile = new ProfileData();
    profile.education = new List<EducationRow>();
    profile.experience = new List<ExperienceRow>();
    profile.achievements = new List<AchievementRow>();
    profile.willingToHelp = true;
    profile.isOnline = false;
    return profile;
  }

  private static List<EducationRow> queryEducationRows(Id accountId) {
    List<EducationRow> rows = new List<EducationRow>();
    if (accountId == null) {
      return rows;
    }

    // Start year for rows that hold a year but no month. StartDate needs both, so the
    // onboarding pre-fill cannot store one; the enrolment year lives on the alumnus's
    // ConstituentRole, which is where the pre-fill sourced it from in the first place.
    Map<Id, String> enrolYearByPlan = new Map<Id, String>();
    String soleRoleEnrolYear = null;
    Integer alumniRoleCount = 0;
    for (ConstituentRole cr : [
      SELECT Program_Plan__c, Year_of_Enrollment__c
      FROM ConstituentRole
      WHERE PersonId = :accountId AND RoleType = 'Alumni'
    WITH SECURITY_ENFORCED
    ]) {
      alumniRoleCount++;
      soleRoleEnrolYear = cr.Year_of_Enrollment__c;
      if (
        cr.Program_Plan__c != null &&
        String.isNotBlank(cr.Year_of_Enrollment__c)
      ) {
        enrolYearByPlan.put(cr.Program_Plan__c, cr.Year_of_Enrollment__c);
      }
    }

    for (PersonEducation rec : [
      SELECT
        Id,
        Degree_Name__c,
        Institute_Name__c,
        Institution_Type__c,
        Program_Plan__c,
        Program_Plan__r.Name,
        Registration_Number__c,
        StartDate,
        EndDate,
        Year_of_Completion__c,
        Grade__c,
        Grade_Type__c
      FROM PersonEducation
      WHERE
        AccountId = :accountId
        AND (Is_Archived__c = FALSE
        OR Is_Archived__c = NULL)
      WITH SECURITY_ENFORCED
      ORDER BY
        EndDate DESC NULLS LAST,
        StartDate DESC NULLS LAST,
        CreatedDate DESC
    ]) {
      EducationRow row = new EducationRow();
      row.id = rec.Id;
      row.degree = rec.Degree_Name__c;
      row.institution = rec.Institute_Name__c;
      row.duration = buildEducationDuration(
        rec.StartDate != null ? rec.StartDate.date() : null,
        rec.EndDate,
        rec.Year_of_Completion__c
      );
      row.score = buildScore(rec.Grade__c, rec.Grade_Type__c);
      row.startMonth = rec.StartDate != null
        ? twoDigit(rec.StartDate.month())
        : null;
      if (rec.StartDate != null) {
        row.startYear = String.valueOf(rec.StartDate.year());
      } else if (
        rec.Program_Plan__c != null &&
        enrolYearByPlan.containsKey(rec.Program_Plan__c)
      ) {
        row.startYear = enrolYearByPlan.get(rec.Program_Plan__c);
      } else if (
        alumniRoleCount == 1 &&
        rec.Institution_Type__c == INST_TYPE_OWN
      ) {
        // Only an own-institute row describes the alumnus's own programme. Without
        // this guard an external education with no start date would inherit the
        // Ken enrolment year, which is simply the wrong year for that school.
        row.startYear = soleRoleEnrolYear;
      }
      row.endMonth = rec.EndDate != null ? twoDigit(rec.EndDate.month()) : null;
      row.endYear = rec.EndDate != null
        ? String.valueOf(rec.EndDate.year())
        : rec.Year_of_Completion__c;
      row.gradingFormat = normalizeGradeTypeOutput(rec.Grade_Type__c);
      row.cgpa = rec.Grade__c;
      row.programPlan = rec.Program_Plan__c != null
        ? String.valueOf(rec.Program_Plan__c)
        : null;
      row.programName = rec.Program_Plan__r != null
        ? rec.Program_Plan__r.Name
        : null;
      row.registrationNumber = rec.Registration_Number__c;
      row.institutionType = rec.Institution_Type__c;
      rows.add(row);
    }

    return rows;
  }

  private static List<ExperienceRow> queryExperienceRows(Id accountId) {
    List<ExperienceRow> rows = new List<ExperienceRow>();
    if (accountId == null) {
      return rows;
    }

    for (PersonEmployment rec : [
      SELECT
        Id,
        Designation__c,
        Company_Name__c,
        EmploymentType,
        Job_Role__c,
        Location__c,
        EmploymentSite,
        Description__c,
        StartDate,
        EndDate,
        Currently_Employed__c
      FROM PersonEmployment
      WHERE
        AccountId = :accountId
        AND (Is_Archived__c = FALSE
        OR Is_Archived__c = NULL)
      WITH SECURITY_ENFORCED
      ORDER BY
        Currently_Employed__c DESC NULLS LAST,
        StartDate DESC NULLS LAST,
        CreatedDate DESC
    ]) {
      ExperienceRow row = new ExperienceRow();
      row.id = rec.Id;
      row.position = rec.Designation__c;
      row.company = rec.Company_Name__c;
      row.employmentType = rec.EmploymentType;
      row.jobRole = rec.Job_Role__c;
      row.location = rec.Location__c;
      row.workType = rec.EmploymentSite;
      row.description = rec.Description__c;
      row.isCurrentJob = rec.Currently_Employed__c == true;
      row.duration = buildEmploymentDuration(
        rec.StartDate,
        rec.EndDate,
        row.isCurrentJob
      );
      row.startMonth = rec.StartDate != null
        ? twoDigit(rec.StartDate.month())
        : null;
      row.startYear = rec.StartDate != null
        ? String.valueOf(rec.StartDate.year())
        : null;
      row.endMonth = rec.EndDate != null ? twoDigit(rec.EndDate.month()) : null;
      row.endYear = rec.EndDate != null
        ? String.valueOf(rec.EndDate.year())
        : null;
      rows.add(row);
    }

    return rows;
  }
  private static List<AchievementRow> queryAchievementRows(Id accountId) {
    List<AchievementRow> rows = new List<AchievementRow>();
    if (accountId == null) {
      return rows;
    }

    for (Ken_Achievement__c rec : [
      SELECT
        Id,
        Achievement_Type__c,
        Title__c,
        Issuing_Organisation__c,
        Date__c,
        Description__c,
        Application_or_Patent_Number__c,
        Achievement_Status__c,
        Role__c,
        Reference_URL__c,
        Paper_Type__c
      FROM Ken_Achievement__c
      WHERE
        Person_Account__c = :accountId
        AND (Is_Archived__c = FALSE
        OR Is_Archived__c = NULL)
      WITH SECURITY_ENFORCED
      ORDER BY Date__c DESC NULLS LAST, CreatedDate DESC
    ]) {
      AchievementRow row = new AchievementRow();
      row.id = rec.Id;
      row.type = normalizeAchievementTypeOutput(rec.Achievement_Type__c);
      row.title = rec.Title__c;
      row.organization = rec.Issuing_Organisation__c;
      row.description = rec.Description__c;
      row.dateMonth = rec.Date__c != null
        ? twoDigit(rec.Date__c.month())
        : null;
      row.dateYear = rec.Date__c != null
        ? String.valueOf(rec.Date__c.year())
        : null;
      row.patentNumber = rec.Application_or_Patent_Number__c;
      row.status = rec.Achievement_Status__c;
      row.role = rec.Role__c;
      row.referenceUrl = rec.Reference_URL__c;
      row.paperType = rec.Paper_Type__c;

      List<String> metaParts = new List<String>();
      if (String.isNotBlank(rec.Issuing_Organisation__c)) {
        metaParts.add(rec.Issuing_Organisation__c);
      }
      if (rec.Date__c != null) {
        metaParts.add(String.valueOf(rec.Date__c.year()));
      }
      row.meta = metaParts.isEmpty() ? null : String.join(metaParts, ' | ');
      rows.add(row);
    }

    return rows;
  }

  @TestVisible
  private static Id testCurrentAccountId;

  private static Id getCurrentUserAccountId() {
    if (Test.isRunningTest() && testCurrentAccountId != null) {
      return testCurrentAccountId;
    }
    List<User> users = [SELECT Id, AccountId, ContactId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
    if (users.isEmpty())
      return null;
    User currentUser = users[0];
    if (currentUser.AccountId != null)
      return currentUser.AccountId;
    if (currentUser.ContactId != null) {
      List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :currentUser.ContactId WITH SECURITY_ENFORCED LIMIT 1];
      if (!contacts.isEmpty() && contacts[0].AccountId != null)
        return contacts[0].AccountId;
    }
    return null;
  }

  /**
   * Denies unless targetAccountId is the running user's own account, or the
   * running user holds the Alumni_Admin or Alumni_Institute_Coordinator
   * permission set. Every *For(targetAccountId) entry point calls this
   * first — it is the sole security boundary for viewing someone else's
   * profile through this shared component.
   */
  private static void assertCanView(Id targetAccountId) {
    if (targetAccountId == null) {
      throw new AuraHandledException('A profile to view is required.');
    }
    Id ownAccountId = getCurrentUserAccountId();
    if (targetAccountId == ownAccountId) {
      return;
    }
    Boolean canViewAny = Test.isRunningTest()
      ? testCanViewAnyProfile
      : ![
          SELECT Id
          FROM PermissionSetAssignment
          WHERE
            AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name IN ('Alumni_Admin', 'Alumni_Institute_Coordinator')
          WITH SYSTEM_MODE
          LIMIT 1
        ]
          .isEmpty();
    if (!canViewAny) {
      throw new AuraHandledException(
        'You do not have permission to view this profile.'
      );
    }
  }

  @TestVisible
  private static Boolean testCanViewAnyProfile = false;

  private static String resolveProfileImage(Account acc) {
    if (acc != null && String.isNotBlank(acc.Profile_Photo_URL__c)) {
      return acc.Profile_Photo_URL__c;
    }
    return null;
  }

  private static String buildLocation(
    Account acc,
    String mailingLocation,
    ExperienceRow latestJob
  ) {
    if (String.isNotBlank(mailingLocation)) {
      return mailingLocation;
    }
    if (latestJob != null && String.isNotBlank(latestJob.location)) {
      return latestJob.location;
    }

    List<String> parts = new List<String>();
    if (acc != null) {
      if (String.isNotBlank(acc.PersonMailingCity))
        parts.add(acc.PersonMailingCity);
      if (String.isNotBlank(acc.PersonMailingState))
        parts.add(acc.PersonMailingState);
      if (String.isNotBlank(acc.PersonMailingCountry))
        parts.add(acc.PersonMailingCountry);
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  /**
   * @description Treats an alumnus as online when the heartbeat stamped
   *              Account.Last_Active__c within the last five minutes.
   *
   * @param lastActive Heartbeat time, or null when never seen.
   * @return True when the alumnus counts as online.
   */
  private static Boolean isCurrentlyOnline(Datetime lastActive) {
    if (lastActive == null) {
      return false;
    }
    return lastActive.getTime() >= System.now().addMinutes(-5).getTime();
  }

  private static String buildEducationDuration(
    Date startDate,
    Date endDate,
    String yearOfGraduation
  ) {
    String startY = startDate != null ? String.valueOf(startDate.year()) : null;
    String endY = endDate != null
      ? String.valueOf(endDate.year())
      : sanitize(yearOfGraduation);
    if (String.isBlank(startY) && String.isBlank(endY))
      return null;
    if (String.isBlank(startY))
      return endY;
    if (String.isBlank(endY))
      return startY;
    return startY + ' - ' + endY;
  }

  private static String buildEmploymentDuration(
    Date startDate,
    Date endDate,
    Boolean isCurrent
  ) {
    if (startDate == null) {
      return null;
    }

    String startLabel =
      shortMonthName(startDate.month()) +
      ' ' +
      String.valueOf(startDate.year());
    String endLabel;
    if (isCurrent == true) {
      endLabel = 'Present';
    } else if (endDate != null) {
      endLabel =
        shortMonthName(endDate.month()) +
        ' ' +
        String.valueOf(endDate.year());
    } else {
      endLabel = null;
    }

    if (String.isBlank(endLabel)) {
      return startLabel;
    }
    return startLabel + ' - ' + endLabel;
  }

  private static String buildScore(String grade, String gradeType) {
    if (String.isBlank(grade)) {
      return null;
    }
    String normalizedType = normalizeGradeTypeOutput(gradeType);
    if (normalizedType == 'Percentage') {
      return grade + '%';
    }
    return grade;
  }

  private static Date buildDate(String yearStr, String monthStr) {
    if (String.isBlank(yearStr) || String.isBlank(monthStr)) {
      return null;
    }
    Integer y;
    Integer m;
    try {
      y = Integer.valueOf(yearStr);
      m = Integer.valueOf(monthStr);
    } catch (Exception e) {
      return null;
    }
    if (y < 1900 || y > 2600 || m < 1 || m > 12) {
      return null;
    }
    return Date.newInstance(y, m, 1);
  }

  private static String normalizeEmploymentType(String inputValue) {
    return normalizePicklistValue(
      PersonEmployment.EmploymentType.getDescribe(),
      inputValue
    );
  }

  private static String normalizeJobRole(String inputValue) {
    return normalizePicklistValue(
      PersonEmployment.Job_Role__c.getDescribe(),
      inputValue
    );
  }

  private static String normalizeLocationType(String inputValue) {
    String normalized = normalizePicklistValue(
      PersonEmployment.EmploymentSite.getDescribe(),
      inputValue
    );
    return String.isNotBlank(normalized) ? normalized : 'Onsite';
  }

  private static String normalizeGradeType(String inputValue) {
    if (String.isBlank(inputValue)) {
      return null;
    }

    String trimmed = inputValue.trim();
    String normalized = normalizePicklistValue(
      PersonEducation.Grade_Type__c.getDescribe(),
      trimmed
    );
    if (String.isNotBlank(normalized)) {
      return normalized;
    }

    if (trimmed.toLowerCase().contains('percent')) {
      String alt = normalizePicklistValue(
        PersonEducation.Grade_Type__c.getDescribe(),
        'PERCENTAGE'
      );
      return String.isNotBlank(alt) ? alt : null;
    }
    if (trimmed.equalsIgnoreCase('cgpa')) {
      return normalizePicklistValue(
        PersonEducation.Grade_Type__c.getDescribe(),
        'CGPA'
      );
    }
    return null;
  }

  private static String normalizeGradeTypeOutput(String value) {
    if (String.isBlank(value)) {
      return 'CGPA';
    }
    return value.equalsIgnoreCase('PERCENTAGE') ||
      value.equalsIgnoreCase('Percentage')
      ? 'Percentage'
      : value;
  }

  private static String normalizeAchievementType(String inputValue) {
    String normalized = normalizePicklistValue(
      Ken_Achievement__c.Achievement_Type__c.getDescribe(),
      inputValue
    );
    if (String.isNotBlank(normalized)) {
      return normalized;
    }

    if (String.isBlank(inputValue)) {
      return null;
    }

    String trimmed = inputValue.trim();
    if (trimmed.equalsIgnoreCase('Honour / Award'))
      return normalizePicklistValue(
        Ken_Achievement__c.Achievement_Type__c.getDescribe(),
        'Honors & Awards'
      );
    if (trimmed.equalsIgnoreCase('Certification'))
      return normalizePicklistValue(
        Ken_Achievement__c.Achievement_Type__c.getDescribe(),
        'Certifications'
      );
    if (trimmed.equalsIgnoreCase('Publication'))
      return normalizePicklistValue(
        Ken_Achievement__c.Achievement_Type__c.getDescribe(),
        'Publications'
      );
    if (trimmed.equalsIgnoreCase('Patent'))
      return normalizePicklistValue(
        Ken_Achievement__c.Achievement_Type__c.getDescribe(),
        'Patents'
      );
    return trimmed;
  }

  private static String normalizeAchievementTypeOutput(String value) {
    if (String.isBlank(value)) {
      return 'Honors & Awards';
    }

    if (value.equalsIgnoreCase('Honour / Award'))
      return 'Honors & Awards';
    if (value.equalsIgnoreCase('Certification'))
      return 'Certifications';
    if (value.equalsIgnoreCase('Publication'))
      return 'Publications';
    if (value.equalsIgnoreCase('Patent'))
      return 'Patents';
    return value;
  }

  private static String normalizeAchievementStatus(String inputValue) {
    return normalizePicklistValue(
      Ken_Achievement__c.Achievement_Status__c.getDescribe(),
      inputValue
    );
  }

  private static String normalizeAchievementRole(String inputValue) {
    return normalizePicklistValue(
      Ken_Achievement__c.Role__c.getDescribe(),
      inputValue
    );
  }

  private static String normalizePaperType(String inputValue) {
    return normalizePicklistValue(
      Ken_Achievement__c.Paper_Type__c.getDescribe(),
      inputValue
    );
  }

  private static String normalizePicklistValue(
    Schema.DescribeFieldResult describeResult,
    String inputValue
  ) {
    if (describeResult == null || String.isBlank(inputValue)) {
      return null;
    }

    String input = inputValue.trim();
    if (String.isBlank(input)) {
      return null;
    }

    Map<String, String> valueByLower = new Map<String, String>();
    for (Schema.PicklistEntry entry : describeResult.getPicklistValues()) {
      if (!entry.isActive()) {
        continue;
      }
      String value = entry.getValue();
      if (String.isNotBlank(value)) {
        valueByLower.put(value.toLowerCase(), value);
      }
      String label = entry.getLabel();
      if (String.isNotBlank(label)) {
        valueByLower.put(label.toLowerCase(), value);
      }
    }

    String direct = valueByLower.get(input.toLowerCase());
    if (String.isNotBlank(direct)) {
      return direct;
    }

    String normalized = input.toLowerCase().replace('-', ' ');
    return valueByLower.get(normalized);
  }

  private static Id resolveOrCreateOrganizationAccountId(String accountName) {
    String normalized = sanitize(accountName);
    if (String.isBlank(normalized)) {
      return null;
    }

    List<Account> existing = [
      SELECT Id
      FROM Account
      WHERE Name = :normalized AND IsPersonAccount = FALSE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0].Id;
    }

    Account organization = new Account(Name = normalized);
    if (!Schema.sObjectType.Account.isCreateable()) {
      throw new KenCrudException('Account is not createable by the current user.');
    }
    insert organization;
    return organization.Id;
  }

  private static String sanitize(String value) {
    if (value == null) {
      return null;
    }
    String cleaned = value.replaceAll('\\s+', ' ').trim();
    return cleaned == '' ? null : cleaned;
  }

  private static String keepOnlyDigits(String value) {
    String cleaned = sanitize(value);
    if (String.isBlank(cleaned)) {
      return null;
    }
    cleaned = cleaned.replaceAll('[^0-9]', '');
    return cleaned == '' ? null : cleaned;
  }

  private static String shortMonthName(Integer monthNumber) {
    List<String> names = new List<String>{
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    };
    if (monthNumber == null || monthNumber < 1 || monthNumber > 12) {
      return '';
    }
    return names[monthNumber - 1];
  }

  private static String twoDigit(Integer value) {
    if (value == null) {
      return null;
    }
    return value < 10 ? '0' + String.valueOf(value) : String.valueOf(value);
  }

  private static String firstNonBlank(String firstValue, String secondValue) {
    return String.isNotBlank(firstValue) ? firstValue : secondValue;
  }

  /**
   * @description Effective ConstituentRole of the logged-in user, resolved via
   *              KenConstituentRoleService (role with the latest Last_Login__c wins).
   *
   * @param accountId  PersonAccount Id of the logged-in user.
   * @return           ConstituentRole Id, or null.
   */
  private static Id getActiveConstituentRoleId(Id accountId) {
    if (accountId == null) {
      return null;
    }
    return KenConstituentRoleService.getActiveConstituentRoleId();
  }
}