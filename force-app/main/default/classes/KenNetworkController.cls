public without sharing class KenNetworkController {
  private static final String CONSTITUENT_ROLE_TYPE_ALUMNI = 'Alumni';
  private static final String CONSTITUENT_ROLE_STATUS_ACTIVE = 'Active';
  private static final String CONSTITUENT_ROLE_STATUS_UNREGISTERED = 'Unregistered';
  private static final String STATUS_ACCEPTED = 'Accepted';
  private static final String STATUS_REQUESTED = 'Requested';
  private static final String STATUS_REJECTED = 'Rejected';

  @TestVisible
  private static Id testCurrentAccountId;

  public class AlumniRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String company;
    @AuraEnabled
    public String industry;
    @AuraEnabled
    public String jobFunction;
    @AuraEnabled
    public String programLastAttended;
    @AuraEnabled
    public String specialisation;
    @AuraEnabled
    public String currentCity;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String batch;
    @AuraEnabled
    public String graduationYear;
    @AuraEnabled
    public String institute;
    @AuraEnabled
    public String program;
    @AuraEnabled
    public String intake;
    @AuraEnabled
    public String domain;
    @AuraEnabled
    public String skills;
    @AuraEnabled
    public String employmentType;
    @AuraEnabled
    public String gender;
    @AuraEnabled
    public String language; // Account.Languages_Known__c (comma-separated text)
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String profileImage;
    @AuraEnabled
    public Datetime lastActive;
    @AuraEnabled
    public Boolean willingToHelp;
    @AuraEnabled
    public Boolean isMentor;
    // True only when this person is the VIEWER'S accepted mentor — drives the
    // "Mentor" badge (willingToHelp/isMentor drive the "Willing to help" badge).
    @AuraEnabled
    public Boolean isMyMentor;
    @AuraEnabled
    public Boolean isOnline;
  }

  public class ConnectionRequestRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id personAccountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String requestDateTime;
    @AuraEnabled
    public String profileImage;
    @AuraEnabled
    public Boolean isOnline;
  }

  public class NetworkDataResponse {
    @AuraEnabled
    public List<AlumniRow> allAlumni;
    @AuraEnabled
    public List<AlumniRow> yourConnections;
    @AuraEnabled
    public List<ConnectionRequestRow> connectionRequests;
    @AuraEnabled
    public String currentUserCity;
    @AuraEnabled
    public String currentUserState;
  }

  public class AlumniProfileDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String company;
    @AuraEnabled
    public String industry;
    @AuraEnabled
    public String programLastAttended;
    @AuraEnabled
    public String specialisation;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String profileImage;
    @AuraEnabled
    public Boolean isOnline;
    @AuraEnabled
    public String graduationYear;
    @AuraEnabled
    public String batch;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String linkedin;
    @AuraEnabled
    public String about;
    @AuraEnabled
    public Boolean willingToHelp;
    @AuraEnabled
    public Boolean isMentor;
    // True only when this person is the VIEWER'S accepted mentor. Kept
    // separate from isMentor (which now means "offers mentorship") so the
    // "Request Mentorship" button still hides for an existing mentor.
    @AuraEnabled
    public Boolean isMyMentor;
    @AuraEnabled
    public String connectionStatus;
    @AuraEnabled
    public Id connectionId;
    @AuraEnabled
    public String mentorshipStatus;
    @AuraEnabled
    public Id mentorshipId;
    @AuraEnabled
    public List<EducationRow> education;
    @AuraEnabled
    public List<EmploymentRow> experience;
    @AuraEnabled
    public List<AchievementRow> achievements;
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
  }

  public class AchievementRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String meta;
    @AuraEnabled
    public String description;
  }

  public class EmploymentRow {
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
    public Boolean isCurrent;
  }

  @AuraEnabled
  public static NetworkDataResponse getNetworkData() {
    NetworkDataResponse response = new NetworkDataResponse();
    response.allAlumni = new List<AlumniRow>();
    response.yourConnections = new List<AlumniRow>();
    response.connectionRequests = new List<ConnectionRequestRow>();

    Id currentAccountId = getCurrentUserAccountId();
    Set<Id> eligibleAccountIds = getEligibleAlumniAccountIds(currentAccountId);

    // Query all non-cancelled connections involving the current user
    List<Ken_Network_Connection__c> connectionRows = currentAccountId == null
      ? new List<Ken_Network_Connection__c>()
      : [
          SELECT Id, Initiator__c, Recipient__c, Status__c, LastModifiedDate
          FROM Ken_Network_Connection__c
          WHERE
            (Initiator__c = :currentAccountId
            OR Recipient__c = :currentAccountId)
            AND Status__c != 'Cancelled'
          WITH SECURITY_ENFORCED
          ORDER BY LastModifiedDate DESC
          LIMIT 500
        ];

    // Separate accepted connections and incoming pending requests
    Set<Id> processedCounterparts = new Set<Id>();
    List<Id> orderedAcceptedCounterpartIds = new List<Id>();
    Set<Id> acceptedConnectionCounterpartIds = new Set<Id>();
    List<Ken_Network_Connection__c> incomingRequests = new List<Ken_Network_Connection__c>();

    for (Ken_Network_Connection__c conn : connectionRows) {
      Id counterpartId = conn.Initiator__c == currentAccountId
        ? conn.Recipient__c
        : conn.Initiator__c;
      if (
        counterpartId == null || !eligibleAccountIds.contains(counterpartId)
      ) {
        continue;
      }
      // Only process the most recent record per counterpart
      if (processedCounterparts.contains(counterpartId)) {
        continue;
      }
      processedCounterparts.add(counterpartId);

      if (conn.Status__c == STATUS_ACCEPTED) {
        acceptedConnectionCounterpartIds.add(counterpartId);
        orderedAcceptedCounterpartIds.add(counterpartId);
      } else if (
        conn.Status__c == STATUS_REQUESTED &&
        conn.Recipient__c == currentAccountId
      ) {
        incomingRequests.add(conn);
      }
    }

    Set<Id> visibleAccountIds = new Set<Id>();
    visibleAccountIds.addAll(eligibleAccountIds);
    visibleAccountIds.addAll(acceptedConnectionCounterpartIds);
    for (Ken_Network_Connection__c req : incomingRequests) {
      if (req.Initiator__c != null) {
        visibleAccountIds.add(req.Initiator__c);
      }
    }

    List<Account> accountRows = visibleAccountIds.isEmpty()
      ? new List<Account>()
      : [
          SELECT
            Id,
            Name,
            PersonTitle,
            PersonGenderIdentity,
            Languages_Known__c,
            PersonMailingCity,
            PersonMailingState,
            PersonMailingCountry,
            PhotoUrl,
            Profile_Photo_URL__c,
            Last_Active__c
          FROM Account
          WHERE Id IN :visibleAccountIds
          WITH SECURITY_ENFORCED
          ORDER BY Name
        ];
    Map<Id, Account> accountById = new Map<Id, Account>(accountRows);

    Map<Id, PersonEmployment> employmentByAccountId = getCurrentEmployment(
      visibleAccountIds
    );
    Map<Id, Boolean> mentorPreferenceByAccountId = getMentorPreferenceByAccountIds(
      visibleAccountIds
    );
    // Who among the visible people is the VIEWER'S accepted mentor (drives the
    // "Mentor" badge; willing-to-help alone must NOT show as "Mentor").
    Map<Id, Boolean> myMentorByAccountId = getIsMentorByCounterpart(
      currentAccountId,
      visibleAccountIds
    );

    // Include current user in address query so their location is resolved too
    Set<Id> addressQueryIds = new Set<Id>(visibleAccountIds);
    if (currentAccountId != null)
      addressQueryIds.add(currentAccountId);
    Map<Id, Ken_Address__c> addressByAccountId = getAddressByAccountId(
      addressQueryIds
    );
    Map<Id, ConstituentRole> constituentRoleByAccountId = getConstituentRoleByAccountId(
      visibleAccountIds
    );
    Map<Id, String> skillsByAccountId = getSkillsByAccountId(visibleAccountIds);

    // Build allAlumni — eligible alumni who are not yet accepted connections
    for (Account accountRow : accountRows) {
      if (
        currentAccountId != null &&
        acceptedConnectionCounterpartIds.contains(accountRow.Id)
      ) {
        continue;
      }
      Boolean offersMentorship =
        mentorPreferenceByAccountId.containsKey(accountRow.Id) &&
        mentorPreferenceByAccountId.get(accountRow.Id) == true;
      AlumniRow row = mapAlumniRow(
        accountRow,
        employmentByAccountId.get(accountRow.Id),
        offersMentorship,
        // Badge reflects "offers mentorship", consistent with the detail
        // view — not merely an accepted-mentor relationship.
        offersMentorship,
        addressByAccountId.get(accountRow.Id),
        constituentRoleByAccountId.get(accountRow.Id),
        skillsByAccountId.get(accountRow.Id)
      );
      row.isMyMentor = myMentorByAccountId.get(accountRow.Id) == true;
      if (!isValidNetworkCardRow(row)) {
        continue;
      }
      response.allAlumni.add(row);
    }

    // Build yourConnections — accepted network connections
    for (Id counterpartId : orderedAcceptedCounterpartIds) {
      Account accountRow = accountById.get(counterpartId);
      if (accountRow == null) {
        continue;
      }
      Boolean offersMentorship =
        mentorPreferenceByAccountId.containsKey(counterpartId) &&
        mentorPreferenceByAccountId.get(counterpartId) == true;
      AlumniRow row = mapAlumniRow(
        accountRow,
        employmentByAccountId.get(counterpartId),
        offersMentorship,
        offersMentorship,
        addressByAccountId.get(counterpartId),
        constituentRoleByAccountId.get(counterpartId),
        skillsByAccountId.get(counterpartId)
      );
      row.isMyMentor = myMentorByAccountId.get(counterpartId) == true;
      if (!isValidNetworkCardRow(row)) {
        continue;
      }
      response.yourConnections.add(row);
    }

    // Build connectionRequests — incoming pending connection requests
    for (Ken_Network_Connection__c requestConn : incomingRequests) {
      Id requesterId = requestConn.Initiator__c;
      Account requester = requesterId != null
        ? accountById.get(requesterId)
        : null;
      if (requester == null) {
        continue;
      }

      ConnectionRequestRow requestDto = new ConnectionRequestRow();
      requestDto.id = requestConn.Id;
      requestDto.personAccountId = requester.Id;
      requestDto.name = requester.Name;
      requestDto.requestDateTime = formatDateTime(requestConn.LastModifiedDate);
      requestDto.profileImage = resolveProfileImage(requester);
      requestDto.isOnline = false;
      response.connectionRequests.add(requestDto);
    }

    // Resolve current user's city and state for nearby filter
    // Priority: Ken_Address__c → Account.PersonMailingCity/State
    if (currentAccountId != null) {
      Ken_Address__c myAddr = addressByAccountId.get(currentAccountId);
      if (
        myAddr != null &&
        (String.isNotBlank(myAddr.City__c) ||
        String.isNotBlank(myAddr.State__c))
      ) {
        response.currentUserCity = myAddr.City__c;
        response.currentUserState = myAddr.State__c;
      } else {
        String myLocation = null;
        {
          List<Account> myAccList = [
            SELECT PersonMailingCity, PersonMailingState
            FROM Account
            WHERE Id = :currentAccountId
            WITH SECURITY_ENFORCED
            LIMIT 1
          ];
          if (!myAccList.isEmpty()) {
            response.currentUserCity = myAccList[0].PersonMailingCity;
            response.currentUserState = myAccList[0].PersonMailingState;
          }
        }
        if (String.isNotBlank(myLocation)) {
          response.currentUserCity = extractCity(myLocation);
          response.currentUserState = extractState(myLocation);
        }
      }
    }

    return response;
  }

  // Filter dropdown options must reflect every eligible alumnus in the org,
  // not just who the current viewer happens to see (their own record is
  // normally excluded from their own list, and Network's "All Alumni" tab
  // also excludes existing accepted connections) — a value should be
  // selectable if ANY alumnus has it, regardless of who's logged in.
  @AuraEnabled(cacheable=true)
  public static List<AlumniRow> getAllAlumniForFilterOptions() {
    Set<Id> eligibleAccountIds = getEligibleAlumniAccountIds(null);
    if (eligibleAccountIds.isEmpty()) {
      return new List<AlumniRow>();
    }

    List<Account> accountRows = [
      SELECT
        Id,
        Name,
        PersonTitle,
        PersonGenderIdentity,
        Languages_Known__c,
        PersonMailingCity,
        PersonMailingState,
        PersonMailingCountry,
        PhotoUrl,
        Profile_Photo_URL__c,
        Last_Active__c
      FROM Account
      WHERE Id IN :eligibleAccountIds
    WITH SECURITY_ENFORCED
    ];

    Map<Id, PersonEmployment> employmentByAccountId = getCurrentEmployment(
      eligibleAccountIds
    );
    Map<Id, Ken_Address__c> addressByAccountId = getAddressByAccountId(
      eligibleAccountIds
    );
    Map<Id, ConstituentRole> constituentRoleByAccountId = getConstituentRoleByAccountId(
      eligibleAccountIds
    );
    Map<Id, String> skillsByAccountId = getSkillsByAccountId(
      eligibleAccountIds
    );

    List<AlumniRow> rows = new List<AlumniRow>();
    for (Account accountRow : accountRows) {
      rows.add(
        mapAlumniRow(
          accountRow,
          employmentByAccountId.get(accountRow.Id),
          false,
          false,
          addressByAccountId.get(accountRow.Id),
          constituentRoleByAccountId.get(accountRow.Id),
          skillsByAccountId.get(accountRow.Id)
        )
      );
    }
    return rows;
  }

  @AuraEnabled
  public static List<Id> respondToConnectionRequests(
    List<Id> requestIds,
    String action
  ) {
    if (requestIds == null || requestIds.isEmpty()) {
      return new List<Id>();
    }
    if (!Schema.sObjectType.Ken_Network_Connection__c.isUpdateable()) {
      throw new AuraHandledException(
        'You do not have permission to update connection requests.'
      );
    }

    String normalizedAction = normalizeAction(action);
    if (normalizedAction == null) {
      throw new AuraHandledException(
        'Unsupported action. Use "accept" or "reject".'
      );
    }

    Id currentAccountId = getCurrentUserAccountId();
    if (currentAccountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }

    List<Ken_Network_Connection__c> records = [
      SELECT Id, Initiator__c, Recipient__c, Status__c
      FROM Ken_Network_Connection__c
      WHERE
        Id IN :requestIds
        AND Recipient__c = :currentAccountId
        AND Status__c = :STATUS_REQUESTED
    WITH SECURITY_ENFORCED
    ];

    if (records.isEmpty()) {
      return new List<Id>();
    }

    List<Id> processedIds = new List<Id>();
    List<Ken_Network_Connection__c> acceptedRecords = new List<Ken_Network_Connection__c>();
    for (Ken_Network_Connection__c conn : records) {
      conn.Status__c = normalizedAction;
      processedIds.add(conn.Id);
      if (normalizedAction == STATUS_ACCEPTED) {
        acceptedRecords.add(conn);
      }
    }
    update records;

    // Clear the actor's "sent you a connection request" notifications now
    // that the requests are actioned — regardless of which UI surface
    // (bell, Network page) performed the accept/reject.
    KenNotificationFactory.markRelatedAsRead(
      new Set<Id>(processedIds),
      currentAccountId
    );

    if (!acceptedRecords.isEmpty()) {
      createConnectionAcceptedNotifications(acceptedRecords, currentAccountId);
    }

    return processedIds;
  }

  private static void createConnectionAcceptedNotifications(
    List<Ken_Network_Connection__c> connections,
    Id acceptingAccountId
  ) {
    List<KenNotificationFactory.Context> ctxs = new List<KenNotificationFactory.Context>();
    for (Ken_Network_Connection__c c : connections) {
      if (c.Initiator__c == null)
        continue;
      ctxs.add(
        new KenNotificationFactory.Context(
          c.Initiator__c, // recipient = original requester
          acceptingAccountId, // sender = the user accepting
          acceptingAccountId // sourceRecordId → {!Id} resolves to accepter's profile id
        )
      );
    }
    if (!ctxs.isEmpty()) {
      KenNotificationFactory.create(
        'Network_Connection_Request_Accepted',
        ctxs
      );
    }
  }

  private static String normalizeAction(String action) {
    if (String.isBlank(action)) {
      return null;
    }

    String normalized = action.trim().toLowerCase();
    if (normalized == 'accept') {
      return STATUS_ACCEPTED;
    }
    if (normalized == 'reject' || normalized == 'decline') {
      return STATUS_REJECTED;
    }
    return null;
  }

  private static AlumniRow mapAlumniRow(
    Account accountRow,
    PersonEmployment employment,
    Boolean willingToHelp,
    Boolean isMentor,
    Ken_Address__c address,
    ConstituentRole constituentRole,
    String skills
  ) {
    AlumniRow row = new AlumniRow();
    row.id = accountRow.Id;
    row.name = accountRow.Name;
    row.title = firstNonBlank(
      employment != null ? employment.Designation__c : null,
      accountRow.PersonTitle
    );
    row.company = employment != null ? employment.Company_Name__c : null;
    row.industry = firstNonBlank(
      employment != null ? employment.EmploymentIndustry : null,
      employment != null ? employment.Industry__c : null
    );
    row.jobFunction = row.title;
    row.programLastAttended = constituentRole != null
      ? sanitizeProgramName(constituentRole.Program_Name__c)
      : null;
    row.specialisation = null;
    row.location = buildLocation(accountRow, employment, address);
    row.currentCity = extractCity(row.location);
    row.graduationYear = constituentRole != null
      ? constituentRole.Graduation_Year__c
      : null;
    row.batch = String.isNotBlank(row.graduationYear)
      ? 'Batch ' + row.graduationYear
      : null;
    row.institute = constituentRole != null
      ? constituentRole.Institution_Name__c
      : null;
    String constituentRolePlanName = (constituentRole != null &&
      constituentRole.Program_Plan__r != null)
      ? constituentRole.Program_Plan__r.Name
      : null;
    row.program = constituentRole != null
      ? firstNonBlank(constituentRole.Program_Name__c, constituentRolePlanName)
      : null;
    row.intake = constituentRole != null
      ? constituentRole.Year_of_Enrollment__c
      : null;
    row.domain = employment != null ? employment.Job_Role__c : null;
    row.skills = skills;
    row.employmentType = employment != null ? employment.EmploymentType : null;
    row.gender = accountRow.PersonGenderIdentity;
    row.language = accountRow.Languages_Known__c;
    row.country = firstNonBlank(
      accountRow.PersonMailingCountry,
      address != null ? address.Country__c : null
    );
    row.profileImage = resolveProfileImage(accountRow);
    row.lastActive = accountRow.Last_Active__c;
    row.willingToHelp = willingToHelp;
    row.isMentor = isMentor;
    row.isOnline = isCurrentlyOnline(row.lastActive);
    return row;
  }

  private static String formatDateTime(Datetime value) {
    if (value == null) {
      return null;
    }
    return value.format('dd MMM yyyy');
  }

  public class ProfileCardSummary {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String company;
    @AuraEnabled
    public String industry;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String currentCity;
    @AuraEnabled
    public String profileImage;
    @AuraEnabled
    public String educationLine;
    @AuraEnabled
    public String programLastAttended;
    @AuraEnabled
    public String graduationYear;
  }

  /**
   * Single source of truth for the profile summary shown on alumni cards.
   * Builds each field with the same precedence as getAlumniProfile so cards
   * and the profile detail view can never diverge.
   */
  public static Map<Id, ProfileCardSummary> getProfileCardSummaries(
    Set<Id> accountIds
  ) {
    Map<Id, ProfileCardSummary> summaryByAccountId = new Map<Id, ProfileCardSummary>();
    if (accountIds == null || accountIds.isEmpty()) {
      return summaryByAccountId;
    }

    Map<Id, Account> accountById = new Map<Id, Account>(
      [
        SELECT
          Id,
          Name,
          PersonTitle,
          PersonMailingCity,
          PersonMailingState,
          PersonMailingCountry,
          PhotoUrl,
          Profile_Photo_URL__c,
          Last_Active__c
        FROM Account
        WHERE Id IN :accountIds
      WITH SECURITY_ENFORCED
      ]
    );
    Map<Id, PersonEmployment> employmentByAccountId = getCurrentEmployment(
      accountIds
    );
    Map<Id, Ken_Address__c> addressByAccountId = getAddressByAccountId(
      accountIds
    );
    Map<Id, ConstituentRole> constituentRoleByAccountId = getConstituentRoleByAccountId(
      accountIds
    );
    Map<Id, String> educationLineByAccountId = buildEducationLines(accountIds);

    for (Id accountId : accountById.keySet()) {
      Account accountRow = accountById.get(accountId);
      ConstituentRole roleRow = constituentRoleByAccountId.get(accountId);
      PersonEmployment employment = employmentByAccountId.get(accountId);

      ProfileCardSummary summary = new ProfileCardSummary();
      summary.accountId = accountId;
      summary.name = accountRow.Name;
      summary.title = firstNonBlank(
        employment != null ? employment.Designation__c : null,
        accountRow.PersonTitle
      );
      summary.company = employment != null ? employment.Company_Name__c : null;
      summary.industry = firstNonBlank(
        employment != null ? employment.EmploymentIndustry : null,
        employment != null ? employment.Industry__c : null
      );
      summary.location = buildLocation(
        accountRow,
        employment,
        addressByAccountId.get(accountId)
      );
      summary.currentCity = extractCity(summary.location);
      summary.profileImage = resolveProfileImage(accountRow);
      summary.programLastAttended = roleRow != null
        ? sanitizeProgramName(roleRow.Program_Name__c)
        : null;
      summary.graduationYear = roleRow != null
        ? roleRow.Graduation_Year__c
        : null;
      summary.educationLine = firstNonBlank(
        educationLineByAccountId.get(accountId),
        buildProgramEducationLine(
          summary.programLastAttended,
          summary.graduationYear
        )
      );
      summaryByAccountId.put(accountId, summary);
    }
    return summaryByAccountId;
  }

  /**
   * Mirrors kenAlumniDetailView.educationLine: latest two PersonEducation
   * records rendered as "degree endYear" joined with " | ".
   */
  private static Map<Id, String> buildEducationLines(Set<Id> accountIds) {
    Map<Id, List<String>> partsByAccountId = new Map<Id, List<String>>();
    for (PersonEducation rec : [
      SELECT AccountId, Degree_Name__c, EndDate, Year_of_Completion__c
      FROM PersonEducation
      WHERE
        AccountId IN :accountIds
        AND (Is_Archived__c = FALSE
        OR Is_Archived__c = NULL)
      WITH SECURITY_ENFORCED
      ORDER BY EndDate DESC NULLS LAST, StartDate DESC NULLS LAST
    ]) {
      if (rec.AccountId == null) {
        continue;
      }
      List<String> parts = partsByAccountId.get(rec.AccountId);
      if (parts == null) {
        parts = new List<String>();
        partsByAccountId.put(rec.AccountId, parts);
      }
      if (parts.size() >= 2) {
        continue;
      }
      String degree = rec.Degree_Name__c != null
        ? rec.Degree_Name__c.trim()
        : '';
      String year = rec.EndDate != null
        ? String.valueOf(rec.EndDate.year())
        : (String.isNotBlank(rec.Year_of_Completion__c)
            ? rec.Year_of_Completion__c
            : '');
      String part = String.isNotBlank(year)
        ? (degree + ' ' + year).trim()
        : degree;
      if (String.isNotBlank(part)) {
        parts.add(part);
      }
    }

    Map<Id, String> lineByAccountId = new Map<Id, String>();
    for (Id accountId : partsByAccountId.keySet()) {
      List<String> parts = partsByAccountId.get(accountId);
      if (!parts.isEmpty()) {
        lineByAccountId.put(accountId, String.join(parts, ' | '));
      }
    }
    return lineByAccountId;
  }

  private static String buildProgramEducationLine(
    String program,
    String gradYear
  ) {
    if (String.isNotBlank(program) && String.isNotBlank(gradYear)) {
      return program + ' | ' + gradYear;
    }
    if (String.isNotBlank(program)) {
      return program;
    }
    return String.isNotBlank(gradYear) ? 'Batch ' + gradYear : null;
  }

  private static Map<Id, PersonEmployment> getCurrentEmployment(
    Set<Id> accountIds
  ) {
    Map<Id, PersonEmployment> employmentByAccountId = new Map<Id, PersonEmployment>();
    if (accountIds.isEmpty()) {
      return employmentByAccountId;
    }

    for (PersonEmployment rec : [
      SELECT
        Id,
        AccountId,
        Designation__c,
        EmploymentIndustry,
        Industry__c,
        Job_Role__c,
        Location__c,
        Company_Name__c,
        Currently_Employed__c,
        EmploymentType,
        StartDate
      FROM PersonEmployment
      WHERE
        AccountId IN :accountIds
        AND (Is_Archived__c = FALSE
        OR Is_Archived__c = NULL)
      WITH SECURITY_ENFORCED
      ORDER BY Currently_Employed__c DESC, StartDate DESC, LastModifiedDate DESC
    ]) {
      if (
        rec.AccountId != null &&
        !employmentByAccountId.containsKey(rec.AccountId)
      ) {
        employmentByAccountId.put(rec.AccountId, rec);
      }
    }
    return employmentByAccountId;
  }

  private static Map<Id, ConstituentRole> getConstituentRoleByAccountId(
    Set<Id> accountIds
  ) {
    Map<Id, ConstituentRole> constituentRoleByAccountId = new Map<Id, ConstituentRole>();
    if (accountIds.isEmpty()) {
      return constituentRoleByAccountId;
    }

    for (ConstituentRole cr : [
      SELECT
        PersonId,
        Institution_Name__c,
        Program_Name__c,
        Program_Plan__r.Name,
        Year_of_Enrollment__c,
        Graduation_Year__c
      FROM ConstituentRole
      WHERE PersonId IN :accountIds AND RoleType = :CONSTITUENT_ROLE_TYPE_ALUMNI
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
    ]) {
      if (
        cr.PersonId != null &&
        !constituentRoleByAccountId.containsKey(cr.PersonId)
      ) {
        constituentRoleByAccountId.put(cr.PersonId, cr);
      }
    }
    return constituentRoleByAccountId;
  }

  private static Map<Id, String> getSkillsByAccountId(Set<Id> accountIds) {
    Map<Id, String> skillsByAccountId = new Map<Id, String>();
    if (
      accountIds.isEmpty() ||
      !Schema.sObjectType.Ken_Alumni_Preferences__c.isAccessible()
    ) {
      return skillsByAccountId;
    }

    for (Ken_Alumni_Preferences__c rec : [
      SELECT Person_Account__c, Skill_set__c
      FROM Ken_Alumni_Preferences__c
      WHERE Person_Account__c IN :accountIds
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
    ]) {
      if (
        rec.Person_Account__c != null &&
        !skillsByAccountId.containsKey(rec.Person_Account__c)
      ) {
        skillsByAccountId.put(rec.Person_Account__c, rec.Skill_set__c);
      }
    }
    return skillsByAccountId;
  }

  private static Map<Id, Boolean> getMentorPreferenceByAccountIds(
    Set<Id> accountIds
  ) {
    Map<Id, Boolean> mentorPreferenceByAccountId = new Map<Id, Boolean>();
    if (
      accountIds.isEmpty() ||
      !Schema.sObjectType.Ken_Alumni_Preferences__c.isAccessible()
    ) {
      return mentorPreferenceByAccountId;
    }

    for (Ken_Alumni_Preferences__c rec : [
      SELECT Person_Account__c, Willing_to_be_a_mentor__c
      FROM Ken_Alumni_Preferences__c
      WHERE Person_Account__c IN :accountIds
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
    ]) {
      if (
        rec.Person_Account__c != null &&
        !mentorPreferenceByAccountId.containsKey(rec.Person_Account__c)
      ) {
        mentorPreferenceByAccountId.put(
          rec.Person_Account__c,
          rec.Willing_to_be_a_mentor__c == true
        );
      }
    }
    return mentorPreferenceByAccountId;
  }

  // True when the given person has flagged their account as private in their
  // engagement preferences (Ken_Alumni_Preferences__c.Is_Restricted_Account__c).
  private static Boolean isPrivateAccount(Id accountId) {
    if (
      accountId == null ||
      !Schema.sObjectType.Ken_Alumni_Preferences__c.isAccessible()
    ) {
      return false;
    }
    for (Ken_Alumni_Preferences__c rec : [
      SELECT Is_Restricted_Account__c
      FROM Ken_Alumni_Preferences__c
      WHERE Person_Account__c = :accountId
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
      LIMIT 1
    ]) {
      return rec.Is_Restricted_Account__c == true;
    }
    return false;
  }

  // Mask an email showing only its first 2 characters, e.g. "pr****".
  // Fixed-length asterisk run so the real length isn't leaked.
  private static String maskEmail(String email) {
    if (String.isBlank(email)) {
      return email;
    }
    String trimmed = email.trim();
    if (trimmed.length() <= 2) {
      return trimmed;
    }
    return trimmed.substring(0, 2) + '****';
  }

  // Mask a phone showing only its last 3 characters, e.g. "****210".
  private static String maskPhone(String phone) {
    if (String.isBlank(phone)) {
      return phone;
    }
    String trimmed = phone.trim();
    if (trimmed.length() <= 3) {
      return trimmed;
    }
    return '****' + trimmed.substring(trimmed.length() - 3);
  }

  // Public so KenChatController can render the same "Mentor" pill the network cards use.
  public static Map<Id, Boolean> getIsMentorByCounterpart(
    Id currentAccountId,
    Set<Id> counterpartIds
  ) {
    Map<Id, Boolean> isMentorByCounterpart = new Map<Id, Boolean>();
    if (
      currentAccountId == null ||
      counterpartIds == null ||
      counterpartIds.isEmpty()
    ) {
      return isMentorByCounterpart;
    }
    if (!Schema.sObjectType.Ken_Mentorship__c.isAccessible()) {
      return isMentorByCounterpart;
    }

    for (Ken_Mentorship__c m : [
      SELECT Mentor__c, Mentee__c
      FROM Ken_Mentorship__c
      WHERE
        Mentorship_Status__c = :STATUS_ACCEPTED
        AND Mentor__c IN :counterpartIds
        AND Mentee__c = :currentAccountId
    WITH SECURITY_ENFORCED
    ]) {
      if (m.Mentor__c != null) {
        isMentorByCounterpart.put(m.Mentor__c, true);
      }
    }
    return isMentorByCounterpart;
  }

  private static String resolveProfileImage(Account accountRow) {
    if (
      accountRow != null && String.isNotBlank(accountRow.Profile_Photo_URL__c)
    ) {
      return accountRow.Profile_Photo_URL__c;
    }
    if (accountRow != null && String.isNotBlank(accountRow.PhotoUrl)) {
      return URL.getOrgDomainUrl().toExternalForm() + accountRow.PhotoUrl;
    }
    return null;
  }

  // Build location string with Ken_Address__c as highest priority source
  private static String buildLocation(
    Account accountRow,
    PersonEmployment emp,
    Ken_Address__c address
  ) {
    if (
      address != null &&
      (String.isNotBlank(address.City__c) ||
      String.isNotBlank(address.State__c))
    ) {
      return buildLocationFromAddress(address);
    }
    if (emp != null && String.isNotBlank(emp.Location__c)) {
      return emp.Location__c;
    }
    List<String> parts = new List<String>();
    if (accountRow != null) {
      if (String.isNotBlank(accountRow.PersonMailingCity))
        parts.add(accountRow.PersonMailingCity);
      if (String.isNotBlank(accountRow.PersonMailingState))
        parts.add(accountRow.PersonMailingState);
      if (String.isNotBlank(accountRow.PersonMailingCountry))
        parts.add(accountRow.PersonMailingCountry);
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static String buildLocationFromAddress(Ken_Address__c address) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(address.City__c))
      parts.add(address.City__c);
    if (String.isNotBlank(address.State__c))
      parts.add(address.State__c);
    if (String.isNotBlank(address.Country__c))
      parts.add(address.Country__c);
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static Map<Id, Ken_Address__c> getAddressByAccountId(
    Set<Id> accountIds
  ) {
    Map<Id, Ken_Address__c> mailingByAccount = new Map<Id, Ken_Address__c>();
    Map<Id, Ken_Address__c> anyByAccount = new Map<Id, Ken_Address__c>();
    if (accountIds.isEmpty())
      return anyByAccount;

    for (Ken_Address__c addr : [
      SELECT
        Id,
        Person_Account__c,
        Address_Type__c,
        City__c,
        State__c,
        Country__c
      FROM Ken_Address__c
      WHERE
        Person_Account__c IN :accountIds
        AND (City__c != NULL
        OR State__c != NULL)
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
    ]) {
      if (addr.Person_Account__c == null)
        continue;
      if (!anyByAccount.containsKey(addr.Person_Account__c)) {
        anyByAccount.put(addr.Person_Account__c, addr);
      }
      if (
        addr.Address_Type__c == 'Mailing' &&
        !mailingByAccount.containsKey(addr.Person_Account__c)
      ) {
        mailingByAccount.put(addr.Person_Account__c, addr);
      }
    }

    Map<Id, Ken_Address__c> result = new Map<Id, Ken_Address__c>();
    for (Id accountId : accountIds) {
      if (mailingByAccount.containsKey(accountId)) {
        result.put(accountId, mailingByAccount.get(accountId));
      } else if (anyByAccount.containsKey(accountId)) {
        result.put(accountId, anyByAccount.get(accountId));
      }
    }
    return result;
  }

  private static String extractCity(String location) {
    if (String.isBlank(location)) {
      return null;
    }
    List<String> parts = location.split(',');
    return parts.isEmpty() ? location : parts[0].trim();
  }

  private static String extractState(String location) {
    if (String.isBlank(location)) {
      return null;
    }
    List<String> parts = location.split(',');
    return parts.size() >= 2 ? parts[1].trim() : null;
  }

  private static String firstNonBlank(String firstValue, String secondValue) {
    return String.isNotBlank(firstValue) ? firstValue : secondValue;
  }

  private static Boolean isCurrentlyOnline(Datetime lastActive) {
    if (lastActive == null) {
      return false;
    }
    return lastActive.getTime() >= System.now().addMinutes(-5).getTime();
  }

  private static Boolean isValidNetworkCardRow(AlumniRow row) {
    if (row == null) {
      return false;
    }
    return String.isNotBlank(row.name);
  }

  /**
   * The alumni the directory will show: an Active, registered Alumni ConstituentRole on a person
   * Account.
   *
   * Public because chat applies the SAME rule. It used to list any Accepted connection, so a
   * counterpart with no ConstituentRole appeared as a conversation while Network hid them from
   * "Your Connections" - one list saying one connection and the other saying two. Sharing the
   * definition is the only way the two cannot drift.
   */
  public static Set<Id> getEligibleAlumniAccountIds(Id currentAccountId) {
    Set<Id> rolePersonIds = new Set<Id>();
    for (ConstituentRole cr : [
      SELECT PersonId
      FROM ConstituentRole
      WHERE
        RoleType = :CONSTITUENT_ROLE_TYPE_ALUMNI
        AND Status = :CONSTITUENT_ROLE_STATUS_ACTIVE
        AND Registration_Status__c != :CONSTITUENT_ROLE_STATUS_UNREGISTERED
        AND PersonId != NULL
    WITH SECURITY_ENFORCED
    ]) {
      if (currentAccountId != null && cr.PersonId == currentAccountId) {
        continue;
      }
      rolePersonIds.add(cr.PersonId);
    }
    if (rolePersonIds.isEmpty()) {
      return new Set<Id>();
    }

    Set<Id> eligibleAccountIds = new Set<Id>();
    for (Account acc : [
      SELECT Id
      FROM Account
      WHERE Id IN :rolePersonIds AND IsPersonAccount = TRUE
    WITH SECURITY_ENFORCED
    ]) {
      eligibleAccountIds.add(acc.Id);
    }
    return eligibleAccountIds;
  }

  @AuraEnabled(cacheable=true)
  public static AlumniProfileDTO getAlumniProfile(Id accountId) {
    if (accountId == null) {
      return null;
    }

    List<Account> accounts = [
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
        Linkedin_Profile_URL__c,
        Description,
        Last_Active__c
      FROM Account
      WHERE Id = :accountId AND IsPersonAccount = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (accounts.isEmpty()) {
      return null;
    }
    Account acc = accounts[0];

    Map<Id, ConstituentRole> detailRoleMap = getConstituentRoleByAccountId(
      new Set<Id>{ accountId }
    );
    ConstituentRole detailRole = detailRoleMap.get(accountId);

    Map<Id, Ken_Address__c> profileAddressMap = getAddressByAccountId(
      new Set<Id>{ accountId }
    );
    Ken_Address__c profileAddress = profileAddressMap.get(accountId);

    List<EducationRow> educationRows = new List<EducationRow>();
    for (PersonEducation rec : [
      SELECT
        Id,
        Degree_Name__c,
        Institute_Name__c,
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
      ORDER BY EndDate DESC NULLS LAST, StartDate DESC NULLS LAST
    ]) {
      EducationRow row = new EducationRow();
      row.id = rec.Id;
      row.degree = String.isNotBlank(rec.Degree_Name__c)
        ? rec.Degree_Name__c
        : '';
      row.institution = rec.Institute_Name__c;
      String startY = rec.StartDate != null
        ? String.valueOf(rec.StartDate.year())
        : '';
      String endY = rec.EndDate != null
        ? String.valueOf(rec.EndDate.year())
        : (String.isNotBlank(rec.Year_of_Completion__c)
            ? rec.Year_of_Completion__c
            : 'Present');
      row.duration = String.isNotBlank(startY) ? (startY + ' - ' + endY) : endY;
      if (String.isNotBlank(rec.Grade__c)) {
        row.score =
          rec.Grade__c + (rec.Grade_Type__c == 'Percentage' ? '%' : '');
      }
      educationRows.add(row);
    }

    List<EmploymentRow> experienceRows = new List<EmploymentRow>();
    for (PersonEmployment rec : [
      SELECT
        Id,
        Designation__c,
        Company_Name__c,
        EmploymentType,
        Location__c,
        EmploymentSite,
        Description,
        StartDate,
        EndDate,
        Currently_Employed__c
      FROM PersonEmployment
      WHERE
        AccountId = :accountId
        AND (Is_Archived__c = FALSE
        OR Is_Archived__c = NULL)
      WITH SECURITY_ENFORCED
      ORDER BY Currently_Employed__c DESC NULLS LAST, StartDate DESC NULLS LAST
    ]) {
      EmploymentRow row = new EmploymentRow();
      row.id = rec.Id;
      row.position = rec.Designation__c;
      row.company = rec.Company_Name__c;
      row.employmentType = rec.EmploymentType;
      row.location = rec.Location__c;
      row.workType = rec.EmploymentSite;
      row.isCurrent = rec.Currently_Employed__c == true;
      row.description = rec.Description;
      row.duration = buildEmploymentDuration(
        rec.StartDate,
        rec.EndDate,
        row.isCurrent
      );
      experienceRows.add(row);
    }

    List<AchievementRow> achievementRows = new List<AchievementRow>();
    for (Ken_Achievement__c rec : [
      SELECT
        Id,
        Achievement_Type__c,
        Title__c,
        Issuing_Organisation__c,
        Date__c,
        Description__c
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
      row.type = rec.Achievement_Type__c;
      row.title = rec.Title__c;
      row.description = rec.Description__c;
      List<String> metaParts = new List<String>();
      if (String.isNotBlank(rec.Issuing_Organisation__c))
        metaParts.add(rec.Issuing_Organisation__c);
      if (rec.Date__c != null)
        metaParts.add(String.valueOf(rec.Date__c.year()));
      row.meta = metaParts.isEmpty() ? null : String.join(metaParts, ' | ');
      achievementRows.add(row);
    }

    Id currentAccountId = getCurrentUserAccountId();
    String connStatus = null;
    Id connId = null;
    String mentorStatus = null;
    Id mentorId = null;
    if (currentAccountId != null && currentAccountId != accountId) {
      List<Ken_Network_Connection__c> conns = [
        SELECT Id, Status__c
        FROM Ken_Network_Connection__c
        WHERE
          (Initiator__c = :currentAccountId
          AND Recipient__c = :accountId)
          OR (Initiator__c = :accountId
          AND Recipient__c = :currentAccountId)
        WITH SECURITY_ENFORCED
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!conns.isEmpty()) {
        connStatus = conns[0].Status__c;
        connId = conns[0].Id;

        List<Ken_Mentorship__c> mentorships = [
          SELECT Id, Mentorship_Status__c
          FROM Ken_Mentorship__c
          WHERE
            Network_Connection__c = :connId
            AND (Mentor__c = :currentAccountId
            OR Mentee__c = :currentAccountId)
            AND Mentorship_Status__c != 'Cancelled'
          WITH SECURITY_ENFORCED
          ORDER BY CreatedDate DESC
          LIMIT 1
        ];
        if (!mentorships.isEmpty()) {
          mentorId = mentorships[0].Id;
          mentorStatus = mentorships[0].Mentorship_Status__c;
        }
      }
    }

    EmploymentRow latestJob = experienceRows.isEmpty()
      ? null
      : experienceRows[0];
    KenAlumniProfileService.EmploymentSnapshot detailEmployment = KenAlumniProfileService.currentEmployment(
      accountId
    );
    String detailIndustry = detailEmployment != null
      ? detailEmployment.industry
      : null;

    AlumniProfileDTO dto = new AlumniProfileDTO();
    dto.id = acc.Id;
    dto.name = acc.Name;
    dto.title = firstNonBlank(
      latestJob != null ? latestJob.position : null,
      acc.PersonTitle
    );
    dto.company = firstNonBlank(
      latestJob != null ? latestJob.company : null,
      null
    );
    dto.industry = detailIndustry;
    dto.programLastAttended = detailRole != null
      ? sanitizeProgramName(detailRole.Program_Name__c)
      : null;
    dto.specialisation = null;
    dto.location = buildLocation(
      acc,
      latestJob != null ? latestJob.location : null,
      profileAddress
    );
    dto.profileImage = resolveProfileImage(acc);
    dto.isOnline = isCurrentlyOnline(acc.Last_Active__c);
    dto.graduationYear = detailRole != null
      ? detailRole.Graduation_Year__c
      : null;
    dto.batch = String.isNotBlank(dto.graduationYear)
      ? 'Batch ' + dto.graduationYear
      : null;
    Boolean isConnected = connStatus == STATUS_ACCEPTED;
    Boolean maskContact =
      currentAccountId != accountId &&
      !(isConnected && !isPrivateAccount(accountId));
    dto.email = maskContact ? maskEmail(acc.PersonEmail) : acc.PersonEmail;
    dto.phone = maskContact
      ? maskPhone(acc.PersonMobilePhone)
      : acc.PersonMobilePhone;
    dto.linkedin = acc.Linkedin_Profile_URL__c;
    dto.about = acc.Description;
    Map<Id, Boolean> mentorPreferenceForProfile = getMentorPreferenceByAccountIds(
      new Set<Id>{ accountId }
    );
    dto.willingToHelp = mentorPreferenceForProfile.containsKey(accountId)
      ? mentorPreferenceForProfile.get(accountId)
      : false;
    Map<Id, Boolean> isMentorMap = getIsMentorByCounterpart(
      currentAccountId,
      new Set<Id>{ accountId }
    );
    // Badge = "this person offers mentorship" (Willing_to_be_a_mentor__c),
    // not "has an accepted mentorship with me" — the latter wrongly flagged
    // people who were never willing mentors.
    dto.isMentor = dto.willingToHelp == true;
    dto.isMyMentor =
      isMentorMap.containsKey(accountId) && isMentorMap.get(accountId) == true;
    dto.connectionStatus = connStatus;
    dto.connectionId = connId;
    dto.mentorshipStatus = mentorStatus;
    dto.mentorshipId = mentorId;
    dto.education = educationRows;
    dto.experience = experienceRows;
    dto.achievements = achievementRows;
    return dto;
  }

  @AuraEnabled
  public static void removeConnection(Id connectionId) {
    if (connectionId == null) {
      throw new AuraHandledException('Connection ID is required.');
    }
    Id currentAccountId = getCurrentUserAccountId();
    if (currentAccountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }
    List<Ken_Network_Connection__c> conns = [
      SELECT Id, Initiator__c, Recipient__c, Status__c
      FROM Ken_Network_Connection__c
      WHERE
        Id = :connectionId
        AND (Initiator__c = :currentAccountId
        OR Recipient__c = :currentAccountId)
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (conns.isEmpty()) {
      throw new AuraHandledException('Connection not found or access denied.');
    }
    conns[0].Status__c = 'Cancelled';
    update conns[0];

    List<Ken_Mentorship__c> activeMentorships = [
      SELECT Id, Mentorship_Status__c
      FROM Ken_Mentorship__c
      WHERE
        Network_Connection__c = :connectionId
        AND Mentorship_Status__c != 'Cancelled'
    WITH SECURITY_ENFORCED
    ];
    if (!activeMentorships.isEmpty()) {
      for (Ken_Mentorship__c m : activeMentorships) {
        m.Mentorship_Status__c = 'Cancelled';
      }
      if (!Schema.sObjectType.Ken_Mentorship__c.isUpdateable()) {
          throw new KenCrudException('Ken_Mentorship__c is not updateable by the current user.');
      }
      update activeMentorships;
    }
  }

  @AuraEnabled
  public static void requestMentorship(Id connectionId) {
    if (connectionId == null) {
      throw new AuraHandledException('Connection ID is required.');
    }
    Id currentAccountId = getCurrentUserAccountId();
    if (currentAccountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }
    List<Ken_Network_Connection__c> conns = [
      SELECT Id, Initiator__c, Recipient__c, Status__c
      FROM Ken_Network_Connection__c
      WHERE
        Id = :connectionId
        AND (Initiator__c = :currentAccountId
        OR Recipient__c = :currentAccountId)
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (conns.isEmpty()) {
      throw new AuraHandledException('Connection not found or access denied.');
    }
    if (conns[0].Status__c != STATUS_ACCEPTED) {
      throw new AuraHandledException(
        'You must be connected before requesting mentorship.'
      );
    }

    Id mentorAccountId = conns[0].Initiator__c == currentAccountId
      ? conns[0].Recipient__c
      : conns[0].Initiator__c;

    // Reuse any prior Connection_Request for this pair rather than throwing
    // (a rejected one used to block re-requesting) or inserting a duplicate
    // (a cancelled one used to slip past the guard and create a new record).
    List<Ken_Mentorship__c> existing = [
      SELECT Id, Mentorship_Status__c
      FROM Ken_Mentorship__c
      WHERE
        Network_Connection__c = :connectionId
        AND RecordType.DeveloperName = 'Connection_Request'
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      String status = existing[0].Mentorship_Status__c;
      if (status == STATUS_REQUESTED || status == STATUS_ACCEPTED) {
        throw new AuraHandledException(
          'A mentorship request already exists for this connection.'
        );
      }
      // Rejected / Cancelled / Completed → reactivate the same record.
      existing[0].Mentorship_Status__c = STATUS_REQUESTED;
      existing[0].Mentee__c = currentAccountId;
      existing[0].Mentor__c = mentorAccountId;
      update existing[0];
      return;
    }

    Id connReqRtId = Schema.SObjectType.Ken_Mentorship__c
      .getRecordTypeInfosByDeveloperName()
      .get('Connection_Request')
      ?.getRecordTypeId();

    Ken_Mentorship__c mentorship = new Ken_Mentorship__c(
      RecordTypeId = connReqRtId,
      Network_Connection__c = connectionId,
      Mentee__c = currentAccountId,
      Mentor__c = mentorAccountId,
      Mentorship_Status__c = STATUS_REQUESTED
    );
    if (!Schema.sObjectType.Ken_Mentorship__c.isCreateable()) {
        throw new KenCrudException('Ken_Mentorship__c is not createable by the current user.');
    }
    insert mentorship;
  }

  @AuraEnabled
  public static void removeMentorship(Id connectionId) {
    if (connectionId == null) {
      throw new AuraHandledException('Connection ID is required.');
    }
    Id currentAccountId = getCurrentUserAccountId();
    if (currentAccountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }
    List<Ken_Mentorship__c> mentorships = [
      SELECT Id, Mentorship_Status__c
      FROM Ken_Mentorship__c
      WHERE
        Network_Connection__c = :connectionId
        AND (Mentor__c = :currentAccountId
        OR Mentee__c = :currentAccountId)
        AND Mentorship_Status__c != 'Cancelled'
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (mentorships.isEmpty()) {
      return;
    }
    mentorships[0].Mentorship_Status__c = 'Cancelled';
    update mentorships[0];
  }

  @AuraEnabled
  public static String requestConnection(Id targetAccountId) {
    if (targetAccountId == null) {
      throw new AuraHandledException('Target account is required.');
    }
    Id currentAccountId = getCurrentUserAccountId();
    if (currentAccountId == null) {
      throw new AuraHandledException(
        'Unable to determine current user account.'
      );
    }
    if (currentAccountId == targetAccountId) {
      throw new AuraHandledException('Cannot connect to yourself.');
    }

    List<Ken_Network_Connection__c> existing = [
      SELECT Id, Status__c
      FROM Ken_Network_Connection__c
      WHERE
        (Initiator__c = :currentAccountId
        AND Recipient__c = :targetAccountId)
        OR (Initiator__c = :targetAccountId
        AND Recipient__c = :currentAccountId)
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      // Re-requesting after a Rejected/Cancelled record: reuse that row
      // (reset to Requested from the current user) instead of piling up a
      // new duplicate connection each time.
      if (
        existing[0].Status__c == STATUS_REJECTED ||
        existing[0].Status__c == 'Cancelled'
      ) {
        existing[0].Status__c = STATUS_REQUESTED;
        existing[0].Initiator__c = currentAccountId;
        existing[0].Recipient__c = targetAccountId;
        existing[0].Requested_Date__c = Datetime.now();
        update existing[0];
        return STATUS_REQUESTED;
      }
      // Still active (Requested/Accepted/Blocked) — surface current status.
      return existing[0].Status__c;
    }

    Ken_Network_Connection__c conn = new Ken_Network_Connection__c(
      Initiator__c = currentAccountId,
      Recipient__c = targetAccountId,
      Status__c = STATUS_REQUESTED,
      Requested_Date__c = Datetime.now()
    );
    if (!Schema.sObjectType.Ken_Network_Connection__c.isCreateable()) {
        throw new KenCrudException('Ken_Network_Connection__c is not createable by the current user.');
    }
    insert conn;

    return STATUS_REQUESTED;
  }

  private static String buildEmploymentDuration(
    Date startDate,
    Date endDate,
    Boolean isCurrent
  ) {
    String start = formatMonthYear(startDate);
    String endLabel = isCurrent == true ? 'Present' : formatMonthYear(endDate);
    if (String.isBlank(start) && String.isBlank(endLabel)) {
      return null;
    }
    String range =
      (String.isNotBlank(start) ? start : '') +
      (String.isNotBlank(endLabel) ? ' - ' + endLabel : '');
    if (startDate != null) {
      Date endForCalc = (isCurrent == true ||
        endDate == null)
        ? Date.today()
        : endDate;
      Integer months = startDate.monthsBetween(endForCalc);
      Integer years = months / 12;
      Integer remMos = Math.mod(months, 12);
      String tenure = '';
      if (years > 0)
        tenure += years + ' yr' + (years > 1 ? 's' : '');
      if (remMos > 0)
        tenure +=
          (String.isNotBlank(tenure) ? ' ' : '') +
          remMos +
          ' mo' +
          (remMos > 1 ? 's' : '');
      if (String.isNotBlank(tenure))
        range += ' | ' + tenure;
    }
    return range;
  }

  private static String formatMonthYear(Date d) {
    if (d == null)
      return null;
    String[] months = new List<String>{
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
    return months[d.month() - 1] + ' ' + d.year();
  }

  private static String buildLocation(
    Account acc,
    String employmentLocation,
    Ken_Address__c address
  ) {
    if (
      address != null &&
      (String.isNotBlank(address.City__c) ||
      String.isNotBlank(address.State__c))
    ) {
      return buildLocationFromAddress(address);
    }
    if (String.isNotBlank(employmentLocation)) {
      return employmentLocation;
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

  private static Id getCurrentUserAccountId() {
    if (Test.isRunningTest() && testCurrentAccountId != null) {
      return testCurrentAccountId;
    }
    List<User> users = [
      SELECT Id, AccountId, ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (users.isEmpty()) {
      return null;
    }

    User currentUser = users[0];
    if (currentUser.AccountId != null) {
      return currentUser.AccountId;
    }
    if (currentUser.ContactId != null) {
      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :currentUser.ContactId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!contacts.isEmpty() && contacts[0].AccountId != null) {
        return contacts[0].AccountId;
      }
    }
    return null;
  }

  // Returns null when the stored value looks like a raw Salesforce record ID
  // (Program__c may store an ID instead of a human-readable name in some records)
  private static String sanitizeProgramName(String value) {
    if (String.isBlank(value))
      return null;
    String trimmed = value.trim();
    if (
      (trimmed.length() == 15 || trimmed.length() == 18) &&
      trimmed.isAlphanumeric()
    ) {
      return null;
    }
    return trimmed;
  }
}