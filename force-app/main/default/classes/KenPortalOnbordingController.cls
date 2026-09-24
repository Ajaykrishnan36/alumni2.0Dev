/**
 * @description Class responsible for handling alumni onboarding workflows,
 *              managing role-based onboarding states,
 *              sending user notifications via email,
 *              configuring the Ken alumni onboarding process,
 *              and saving profile-related URLs.
 */

public without sharing class KenPortalOnbordingController {
  @TestVisible
  private static final String PERSON_ACCOUNT_RT = 'PersonAccount';
  @TestVisible
  private static final String ONBOARD_ORG_WIDE_NAME = KenMessagingService.orgWideAddressName();
  @TestVisible
  private static final String MSG_MISSING_EMAIL = 'Email is required to reset password.';
  @TestVisible
  private static final String MSG_USER_NOT_FOUND = 'User credentials not found. Please check the email entered.';
  @TestVisible
  private static final String REG_STATUS_UNREGISTERED = 'Unregistered';
  @TestVisible
  private static final String REG_STATUS_REGISTERED = 'Registered';
  @TestVisible
  private static final String REG_STATUS_INITIAL_LOGIN_DONE = 'Initial Login Done';
  @TestVisible
  private static final String REG_STATUS_ONBOARDING_IN_PROGRESS = 'Onboarding In Progress';
  private static final Map<String, Integer> REG_STATUS_RANK = new Map<String, Integer>{
    'Unregistered' => 0,
    'Unverified' => 0,
    'Onboarding In Progress' => 1,
    'Registered' => 2,
    'Initial Login Done' => 3
  };
  private static final String ROLETYPE_ALUMNI = 'Alumni';
  private static Map<String, String> Employment_Type_By_Lower = null;
  /**
   * @description Wrapper representing the current onboarding state
   *              of an alumni user.
   */

  public class OnboardingState {
    @AuraEnabled
    public Boolean isVerified;
    @AuraEnabled
    public String email;
    // Mirrors Ken_Alm_Org_Parameters__c.Lock_Registration_Details__c. Read once
    // here so both onboarding steps share one value for the whole session
    // rather than each re-reading the setting and possibly disagreeing.
    @AuraEnabled
    public Boolean lockRegistrationDetails;
  }
  /**
   * @description Data transfer object used for sending and receiving
   *              alumni profile information during onboarding.
   */

  public class ProfilePayload {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public String lastName;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phoneNumber;
    @AuraEnabled
    public String linkedinUrl;
    @AuraEnabled
    public String twitterUrl;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String currentCity;
    @AuraEnabled
    public String graduationYear;
    @AuraEnabled
    public String enrollmentYear;
    @AuraEnabled
    public String programme;
    @AuraEnabled
    public String programmeId;
    @AuraEnabled
    public Boolean agreeToTerms;
    @AuraEnabled
    public String profileImageUrl;
    @AuraEnabled
    public Date dateOfBirth;
    @AuraEnabled
    public String nationality;
    @AuraEnabled
    public String languages;
    @AuraEnabled
    public String institutionName;
    @AuraEnabled
    public String gender;
    @AuraEnabled
    public String bloodGroup;
  }
  /**
   * @description Completes onboarding verification. Clicking the magic link is
   *              the only proof required, so this moves the role to Onboarding
   *              In Progress and logs the user in.
   *
   *              That status change is also what retires the link: a second click
   *              is stopped by KenAlumniOnboardingService.processVerifiedLead,
   *              which refuses any role ranked past Unregistered. The lead's
   *              verification token is deliberately left intact so resendMagicLink
   *              can still find the lead by it.
   *
   * @return Redirect/login URL for the onboarding form, or null if no login was issued.
   */
  @AuraEnabled
  public static String autoVerifyOnboarding(
    String email,
    String accountId,
    String roleId,
    String token
  ) {
    Id roleRecordId = normalizeId(roleId);
    Id resolvedAccountId = resolveAccountId(
      normalizeId(accountId),
      roleRecordId
    );
    Account pa = getPersonAccountForContext(resolvedAccountId);
    if (pa == null) {
      throw new AuraHandledException('NO_PERSON_ACCOUNT');
    }
    ensureAlumniRoleExists(roleRecordId, pa.Id);

    String resolvedEmail = String.isNotBlank(email) ? email : pa.PersonEmail;
    if (String.isNotBlank(resolvedEmail)) {
      updateConstituentRoleEmail(roleRecordId, pa.Id, resolvedEmail);
      try {
        updateLeadDetails(pa.Id, roleRecordId, resolvedEmail);
      } catch (Exception ex) {
        System.debug('Auto verify: lead sync skipped. ' + ex.getMessage());
      }
    }
    updateRegistrationStatus(
      roleRecordId,
      pa.Id,
      REG_STATUS_ONBOARDING_IN_PROGRESS
    );
    KenAlumniOnboardingService.UserLoginInfo info = KenAlumniOnboardingService.getLatestLoginInfo(
      pa.Id
    );

    if (
      info != null &&
      info.user != null &&
      String.isNotBlank(info.tempPassword)
    ) {
      return KenCommunityLoginController.login(
          info.user.Username,
          info.tempPassword,
          '/alumni/onboarding-form?roleId=' + roleRecordId
        )
        .url;
    }
    return null;
  }
  /**
   * @description Retrieves the current onboarding verification state
   *              for the given person account.
   *
   * @param accountId Person Account Id of the alumni user.
   * @return          OnboardingState containing verification status and email.
   */

  @AuraEnabled(cacheable=false)
  public static OnboardingState getOnboardingState(
    String accountId,
    String roleId
  ) {
    Id roleRecordId = normalizeId(roleId);
    Id resolvedAccountId = resolveAccountId(
      normalizeId(accountId),
      roleRecordId
    );
    Account pa = getPersonAccountForContext(resolvedAccountId);
    if (pa == null) {
      throw new AuraHandledException('NO_PERSON_ACCOUNT');
    }
    OnboardingState state = new OnboardingState();
    state.isVerified = false;
    state.email = pa.PersonEmail;
    state.lockRegistrationDetails = isRegistrationDetailsLocked();

    ConstituentRole cr = fetchAlumniRoleById(roleRecordId, pa.Id);
    if (cr != null) {
      // Already provisioned means the magic-link step is done and the
      // onboarding form can render straight away.
      state.isVerified =
        cr.Registration_Status__c == REG_STATUS_ONBOARDING_IN_PROGRESS ||
        cr.Registration_Status__c == REG_STATUS_REGISTERED ||
        cr.Registration_Status__c == REG_STATUS_INITIAL_LOGIN_DONE;
      if (String.isNotBlank(cr.Email__c)) {
        state.email = cr.Email__c;
      }
    }

    return state;
  }
  /**
   * @description Wrapper representing an alumni employment record
   *              used for UI data exchange.
   */

  public class EmploymentRecord {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String jobTitle;
    @AuraEnabled
    public String organization;
    @AuraEnabled
    public String startDate;
    @AuraEnabled
    public String endDate;
    @AuraEnabled
    public Boolean isCurrentJob;
    @AuraEnabled
    public String industry;
    @AuraEnabled
    public String location;
    @AuraEnabled
    public String roleDescription;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String roleSummary;
    @AuraEnabled
    public String employmentType;
    @AuraEnabled
    public String jobRole;
  }
  /**
   * @description Generic response wrapper indicating success or failure
   *              of a save operation.
   */

  public class SaveResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
  }
  /**
   * @description Generic label-value pair used for dropdown and
   *              selection options.
   */

  public class OptionValue {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }
  /**
   * @description Retrieves the basic profile details of the currently
   *              logged-in alumni user.
   *
   * @return ProfilePayload containing basic profile information.
   */

  @AuraEnabled(cacheable=false)
  public static ProfilePayload getBasicProfile(String roleId) {
    Id roleRecordId = normalizeId(roleId);
    Id accountIdFromRole = getAccountIdByRole(roleRecordId);
    Account pa = accountIdFromRole != null
      ? fetchPersonAccountById(accountIdFromRole)
      : getCurrentUserPersonAccount();
    if (pa == null) {
      return null;
    }

    return buildProfilePayload(pa.Id, roleRecordId);
  }

  @TestVisible
  private static Account fetchPersonAccountByEmail(String email) {
    if (String.isBlank(email)) {
      return null;
    }

    List<Account> accounts = [
      SELECT
        Id,
        RecordTypeId,
        FirstName,
        LastName,
        PersonEmail,
        Phone,
        PersonMobilePhone,
        Linkedin_Profile_URL__c,
        Twitter_Profile_URL__c
      FROM Account
      WHERE PersonEmail = :email AND IsPersonAccount = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    return accounts.isEmpty() ? null : accounts[0];
  }

  private static Account fetchPersonAccountById(Id accountId) {
    if (accountId == null) {
      return null;
    }

    List<Account> accounts = [
      SELECT
        Id,
        RecordTypeId,
        FirstName,
        LastName,
        PersonEmail,
        Agree_to_T_C__c,
        Phone,
        PersonMobilePhone,
        Linkedin_Profile_URL__c,
        Twitter_Profile_URL__c,
        Profile_Photo_URL__c,
        PersonBirthdate,
        Nationality__c,
        Languages_Known__c,
        PersonGenderIdentity,
        Blood_Group__c
      FROM Account
      WHERE Id = :accountId AND IsPersonAccount = TRUE
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    return accounts.isEmpty() ? null : accounts[0];
  }
  /**
   * @description Saves or updates the basic alumni profile information
   *              provided during onboarding.
   *
   * @param requestJson JSON string containing profile details.
   * @return            ProfilePayload indicating save status and account Id.
   */

  @AuraEnabled(cacheable=false)
  public static ProfilePayload saveBasicProfile(
    String requestJson,
    String roleId
  ) {
    if (String.isBlank(requestJson)) {
      throw new AuraHandledException('INVALID_REQUEST');
    }

    ProfilePayload request;
    try {
      // Manually deserialize the JSON string into ProfilePayload
      request = (ProfilePayload) JSON.deserialize(
        requestJson,
        ProfilePayload.class
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Invalid request format: ' + e.getMessage()
      );
    }

    if (String.isNotBlank(request.profileImageUrl)) {
      request.profileImageUrl = resolveProfileImageUrl(
        request.profileImageUrl,
        request.email
      );
    }

    Id roleRecordId = normalizeId(roleId);
    Id accountIdFromRole = getAccountIdByRole(roleRecordId);
    if (roleRecordId != null) {
      updateRegistrationStatus(
        roleRecordId,
        accountIdFromRole,
        REG_STATUS_ONBOARDING_IN_PROGRESS
      );
    }
    Account personAccount = accountIdFromRole != null
      ? fetchPersonAccountById(accountIdFromRole)
      : upsertPersonAccount(request.email, request);
    if (personAccount == null) {
      personAccount = upsertPersonAccount(request.email, request);
    }
    updatePersonAccount(personAccount, request);
    upsertKenAlumniProfile(personAccount.Id, request);
    upsertKenAddress(personAccount.Id, request);
    updateConstituentRoleProgram(
      roleRecordId,
      personAccount.Id,
      request.programmeId,
      request.programme,
      request.graduationYear
    );

    ProfilePayload response = new ProfilePayload();
    response.success = true;
    response.message = 'Basic profile saved successfully.';
    response.accountId = personAccount != null ? personAccount.Id : null;
    return response;
  }

  @TestVisible
  private static String resolveProfileImageUrl(
    String imageValue,
    String email
  ) {
    if (String.isBlank(imageValue)) {
      return imageValue;
    }

    if (imageValue.startsWith('http://') || imageValue.startsWith('https://')) {
      return imageValue;
    }

    if (!imageValue.startsWith('data:') || !imageValue.contains('base64,')) {
      return imageValue;
    }

    String base64Data = imageValue.substringAfter('base64,');
    String extension = extractFileExtension(imageValue);
    String safeEmail = String.isNotBlank(email)
      ? email.replace('@', '_').replace('.', '_')
      : 'user';
    String title =
      'profile_' +
      safeEmail +
      '_' +
      String.valueOf(System.now().getTime()) +
      extension;
    return KenCreateContentVersion.createContentVersion(title, base64Data);
  }

  @TestVisible
  private static String extractFileExtension(String dataUrl) {
    if (String.isBlank(dataUrl)) {
      return '.png';
    }

    String mime = '';
    if (dataUrl.startsWith('data:') && dataUrl.contains(';')) {
      mime = dataUrl.substringBetween('data:', ';');
    }

    if (mime == 'image/jpeg') {
      return '.jpg';
    }
    if (mime == 'image/png') {
      return '.png';
    }
    if (mime == 'image/svg+xml') {
      return '.svg';
    }
    if (mime == 'image/webp') {
      return '.webp';
    }
    return '.png';
  }

  @TestVisible
  private static Account upsertPersonAccount(
    String email,
    ProfilePayload request
  ) {
    Account personAccount = String.isBlank(email)
      ? null
      : fetchPersonAccountByEmail(email);

    if (personAccount == null) {
      personAccount = new Account();
      Schema.RecordTypeInfo paRtInfo = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
        .get(PERSON_ACCOUNT_RT);
      if (paRtInfo == null) {
        throw new AuraHandledException(
          'Person Account record type is missing. Please contact your administrator.'
        );
      }
      personAccount.RecordTypeId = paRtInfo.getRecordTypeId();
    }

    return personAccount;
  }

  private static void updatePersonAccount(
    Account personAccount,
    ProfilePayload request
  ) {
    if (personAccount == null || request == null) {
      return;
    }


    personAccount.FirstName = String.isNotBlank(request.firstName)
      ? request.firstName
      : null;
    personAccount.LastName = String.isNotBlank(request.lastName)
      ? request.lastName
      : 'User';
    if (String.isNotBlank(request.email)) {
      personAccount.PersonEmail = request.email;
    }
    personAccount.Phone = request.phoneNumber;
    if (String.isNotBlank(request.phoneNumber)) {
      personAccount.PersonMobilePhone = request.phoneNumber;
    }
    personAccount.Linkedin_Profile_URL__c = request.linkedinUrl;
    personAccount.Twitter_Profile_URL__c = request.twitterUrl;
    if (request.dateOfBirth != null) {
      personAccount.PersonBirthdate = request.dateOfBirth;
    }
    if (String.isNotBlank(request.nationality)) {
      personAccount.Nationality__c = request.nationality;
    }
    if (String.isNotBlank(request.languages)) {
      personAccount.Languages_Known__c = request.languages;
    }
    if (String.isNotBlank(request.gender)) {
      personAccount.PersonGenderIdentity = request.gender;
    }
    if (String.isNotBlank(request.bloodGroup)) {
      personAccount.Blood_Group__c = request.bloodGroup;
    }

    if (personAccount.Id == null) {
      Database.insert(personAccount, true, AccessLevel.SYSTEM_MODE);
    } else {
      Database.update(personAccount, true, AccessLevel.SYSTEM_MODE);
    }
  }

  @TestVisible
  private static Id testCurrentAccountId;

  private static Id getCurrentUserAccountId() {
    if (Test.isRunningTest() && testCurrentAccountId != null) {
      return testCurrentAccountId;
    }
    Id userId = UserInfo.getUserId();
    if (userId == null) {
      return null;
    }

    List<User> users = [
      SELECT AccountId
      FROM User
      WHERE Id = :userId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return users.isEmpty() ? null : users[0].AccountId;
  }

  private static Account getPersonAccountForContext(Id accountIdParam) {
    Id resolved = accountIdParam != null
      ? accountIdParam
      : getCurrentUserAccountId();
    return resolved == null ? null : fetchPersonAccountById(resolved);
  }

  private static Id resolveAccountId(Id accountIdParam, Id roleIdParam) {
    if (accountIdParam != null) {
      return accountIdParam;
    }
    Id accountIdFromRole = getAccountIdByRole(roleIdParam);
    if (accountIdFromRole != null) {
      return accountIdFromRole;
    }
    return getCurrentUserAccountId();
  }

  private static Id getAccountIdByRole(Id roleId) {
    if (roleId == null) {
      return null;
    }
    List<ConstituentRole> roles = [
      SELECT PersonId
      FROM ConstituentRole
      WHERE Id = :roleId AND RoleType = :ROLETYPE_ALUMNI
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return roles.isEmpty() ? null : roles[0].PersonId;
  }

  private static Account getCurrentUserPersonAccount() {
    Id accountId = getCurrentUserAccountId();
    return accountId == null ? null : fetchPersonAccountById(accountId);
  }

  // Safe Id parsing for values coming from the client/session
  private static Id normalizeId(String rawId) {
    if (String.isBlank(rawId)) {
      return null;
    }
    try {
      return (Id) rawId;
    } catch (Exception e) {
      return null;
    }
  }

  private static ProfilePayload buildProfilePayload(Id accountId, Id roleId) {
    if (accountId == null) {
      return null;
    }

    Account pa = fetchPersonAccountById(accountId);
    if (pa == null) {
      return null;
    }

    ConstituentRole alumniRole = fetchAlumniRoleById(roleId, accountId);

    List<Ken_Address__c> addressList = [
      SELECT City__c, State__c, Country__c
      FROM Ken_Address__c
      WHERE Person_Account__c = :accountId AND Address_Type__c = 'Mailing'
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];

    ProfilePayload data = new ProfilePayload();
    data.accountId = pa.Id;
    data.firstName = pa.FirstName;
    data.lastName = pa.LastName;
    data.email = alumniRole != null && !String.isBlank(alumniRole.Email__c)
      ? alumniRole.Email__c
      : pa.PersonEmail;
    data.phoneNumber = String.isNotBlank(pa.Phone)
      ? pa.Phone
      : pa.PersonMobilePhone;
    data.linkedinUrl = pa.Linkedin_Profile_URL__c;
    data.twitterUrl = pa.Twitter_Profile_URL__c;
    data.profileImageUrl = pa.Profile_Photo_URL__c;
    data.dateOfBirth = pa.PersonBirthdate;
    data.nationality = pa.Nationality__c;
    data.languages = pa.Languages_Known__c;
    data.gender = pa.PersonGenderIdentity;
    data.bloodGroup = pa.Blood_Group__c;

    // Programme, graduation year and enrolment year all come from the
    // ConstituentRole, which Lead conversion populates.
    if (alumniRole != null) {
      data.programme = String.isNotBlank(alumniRole.Program_Plan__c)
        ? alumniRole.Program_Plan__c
        : null;
      data.graduationYear = String.isNotBlank(alumniRole.Graduation_Year__c)
        ? alumniRole.Graduation_Year__c
        : null;
      data.enrollmentYear = String.isNotBlank(alumniRole.Year_of_Enrollment__c)
        ? alumniRole.Year_of_Enrollment__c
        : null;
      data.programmeId = data.programme;
      data.institutionName = alumniRole.Institution_Name__c;
    }
    data.agreeToTerms = pa.Agree_to_T_C__c;
    if (!addressList.isEmpty()) {
      Ken_Address__c address = addressList[0];
      data.country = address.Country__c;
      data.state = address.State__c;
      data.currentCity = address.City__c;
    }

    return data;
  }

  // === Address + Alumni CRM ===
  @TestVisible
  private static Ken_Address__c upsertKenAddress(
    Id accountId,
    ProfilePayload request
  ) {
    if (accountId == null) {
      return null;
    }
    if (!Schema.sObjectType.Ken_Address__c.isAccessible()) {
      return null;
    }

    Ken_Address__c address;
    List<Ken_Address__c> existingAddresses = [
      SELECT
        Id,
        City__c,
        Country__c,
        State__c,
        Address_Type__c,
        Person_Account__c
      FROM Ken_Address__c
      WHERE Person_Account__c = :accountId AND Address_Type__c = 'Mailing'
      LIMIT 1
    ];
    if (!existingAddresses.isEmpty()) {
      address = existingAddresses[0];

    } else {

      address = new Ken_Address__c();
      address.Person_Account__c = accountId;
      address.Address_Type__c = 'Mailing';
    }

    address.City__c = request != null ? request.currentCity : null;
    address.Country__c = request != null ? request.country : null;
    address.State__c = request != null ? request.state : null;

    if (address.Id == null) {
      Database.insert(address, true, AccessLevel.SYSTEM_MODE);
    } else {
      Database.update(address, true, AccessLevel.SYSTEM_MODE);
    }

    return address;
  }

  /**
   * @description Persists the person-level facts captured on the onboarding form:
   *              terms acceptance and the profile photo, both on the Person
   *              Account. Programme and registration date are already carried by
   *              the ConstituentRole created earlier in the flow, so nothing else
   *              needs storing here.
   *
   * @param accountId Person Account being onboarded.
   * @param request Onboarding form payload.
   */
  @TestVisible
  private static void upsertKenAlumniProfile(
    Id accountId,
    ProfilePayload request
  ) {
    if (accountId == null || request == null) {
      return;
    }
    Account pending = new Account(Id = accountId);
    pending.Agree_to_T_C__c = request.agreeToTerms == true;
    if (String.isNotBlank(request.profileImageUrl)) {
      pending.Profile_Photo_URL__c = request.profileImageUrl;
    }
    Database.update(pending, true, AccessLevel.SYSTEM_MODE);
  }

  @TestVisible
  private static void updateConstituentRoleProgram(
    Id roleId,
    Id accountId,
    String programmeId,
    String programme,
    String graduationYear
  ) {
    ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
    if (cr == null)
      return;

    String programValue = !String.isBlank(programmeId)
      ? programmeId
      : programme;

    Boolean programChanged =
      String.isNotBlank(programValue) && cr.Program_Plan__c != programValue;
    Boolean yearChanged = graduationYear != cr.Graduation_Year__c; // handles null vs value too

    if (programChanged || yearChanged) {
      ConstituentRole upd = new ConstituentRole(Id = cr.Id);
      if (programChanged)
        upd.Program_Plan__c = programValue;
      if (yearChanged)
        upd.Graduation_Year__c = graduationYear;
      Database.update(upd, true, AccessLevel.SYSTEM_MODE);
    }
  }

  /**
   * @description Retrieves the Account.Nationality__c picklist values for
   *              the onboarding nationality selector.
   *
   * @return List of OptionValue entries representing nationalities.
   */
  @AuraEnabled(cacheable=true)
  public static List<OptionValue> getNationalityOptions() {
    return picklistValues(Account.Nationality__c.getDescribe());
  }

  /**
   * @description Retrieves the standard PersonGenderIdentity picklist values
   *              for the onboarding gender selector, limited to Male, Female
   *              and Others (the "Not Listed" picklist value relabelled).
   *
   * @return List of OptionValue entries representing gender identities.
   */
  @AuraEnabled(cacheable=true)
  public static List<OptionValue> getGenderOptions() {
    List<OptionValue> results = new List<OptionValue>();
    for (
      OptionValue opt : picklistValues(
        Account.PersonGenderIdentity.getDescribe()
      )
    ) {
      if (opt.value == 'Male' || opt.value == 'Female') {
        results.add(opt);
      } else if (opt.value == 'Not Listed') {
        opt.label = 'Others';
        results.add(opt);
      }
    }
    return results;
  }

  /**
   * @description Retrieves the Account.Blood_Group__c picklist values for
   *              the onboarding blood group selector. Orgs where the field is
   *              a plain text field (e.g. KJS) get the standard blood groups
   *              so the selector is never empty.
   *
   * @return List of OptionValue entries representing blood groups.
   */
  @AuraEnabled(cacheable=true)
  public static List<OptionValue> getBloodGroupOptions() {
    List<OptionValue> options = picklistValues(
      Account.Blood_Group__c.getDescribe()
    );
    if (!options.isEmpty()) {
      return options;
    }
    for (
      String value : new List<String>{
        'A+',
        'A-',
        'B+',
        'B-',
        'AB+',
        'AB-',
        'O+',
        'O-'
      }
    ) {
      OptionValue opt = new OptionValue();
      opt.label = value;
      opt.value = value;
      options.add(opt);
    }
    return options;
  }

  private static List<OptionValue> picklistValues(
    Schema.DescribeFieldResult dfr
  ) {
    List<OptionValue> results = new List<OptionValue>();
    if (dfr.getType() == Schema.DisplayType.Picklist) {
      for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
        if (
          entry == null ||
          !entry.isActive() ||
          String.isBlank(entry.getValue())
        ) {
          continue;
        }
        OptionValue opt = new OptionValue();
        opt.label = entry.getLabel();
        opt.value = entry.getValue();
        results.add(opt);
      }
    }
    return results;
  }

  /**
   * @description Retrieves available learning program options for
   *              alumni selection during onboarding.
   *
   * @return List of OptionValue entries representing programs.
   */

  // === Program Options ===
  @AuraEnabled(cacheable=true)
  public static List<OptionValue> getLearningProgramOptions() {
    List<OptionValue> results = new List<OptionValue>();
    Schema.DescribeFieldResult dfr = ConstituentRole.Program_Plan__c.getDescribe();
    Schema.DisplayType fieldType = dfr.getType();

    if (
      fieldType == Schema.DisplayType.Picklist ||
      fieldType == Schema.DisplayType.MultiPicklist
    ) {
      for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
        if (entry == null || String.isBlank(entry.getValue())) {
          continue;
        }
        OptionValue opt = new OptionValue();
        opt.label = entry.getLabel();
        opt.value = entry.getValue();
        results.add(opt);
      }
    } else if (fieldType == Schema.DisplayType.Reference) {
      List<Schema.SObjectType> refs = dfr.getReferenceTo();
      if (!refs.isEmpty()) {
        String targetObject = refs[0].getDescribe().getName();
        try {
          List<SObject> rows = Database.queryWithBinds(
            'SELECT Id, Name FROM ' + targetObject + ' ORDER BY Name LIMIT 200',
            new Map<String, Object>(),
            AccessLevel.SYSTEM_MODE
          );
          for (SObject row : rows) {
            String idVal = (String) row.get('Id');
            String nameVal = (String) row.get('Name');
            if (String.isBlank(idVal) || String.isBlank(nameVal)) {
              continue;
            }
            OptionValue opt = new OptionValue();
            opt.label = nameVal;
            opt.value = idVal;
            results.add(opt);
          }
        } catch (Exception e) {
          throw new AuraHandledException(
            'unable to load learning program options:' + e.getmessage()
          );
        }
      }
    }
    return results;
  }
  /**
   * @description Retrieves active employment details for the currently
   *              logged-in alumni user.
   *
   * @return List of EmploymentRecord entries for the user.
   */

  @AuraEnabled(cacheable=false)
  public static List<EmploymentRecord> getEmploymentDetails(String roleId) {
    List<EmploymentRecord> results = new List<EmploymentRecord>();

    try {
      Id roleRecordId = normalizeId(roleId);
      Id accountId = resolveAccountId(null, roleRecordId);
      if (accountId == null) {
        return results;
      }

      List<PersonEmployment> empRecords = [
        SELECT
          Id,
          Company_Name__c,
          Designation__c,
          EmploymentIndustry,
          Location__c,
          StartDate,
          EndDate,
          Currently_Employed__c,
          EmploymentType,
          Description__c,
          Is_Archived__c,
          Job_Role__c
        FROM PersonEmployment
        WHERE
          AccountId = :accountId
          AND (Is_Archived__c = FALSE
          OR Is_Archived__c = NULL)
        WITH SECURITY_ENFORCED
        ORDER BY StartDate DESC
      ];

      for (PersonEmployment emp : empRecords) {
        EmploymentRecord rec = new EmploymentRecord();
        rec.id = String.valueOf(emp.Id);
        rec.organization = emp.Company_Name__c;
        rec.jobTitle = emp.Designation__c;
        rec.industry = emp.EmploymentIndustry;
        rec.location = emp.Location__c;
        rec.country = emp.Location__c;
        rec.isCurrentJob = emp.Currently_Employed__c;
        rec.startDate = emp.StartDate != null
          ? String.valueOf(emp.StartDate)
          : null;
        rec.endDate = emp.EndDate != null ? String.valueOf(emp.EndDate) : null;
        rec.employmentType = emp.EmploymentType;
        rec.roleDescription = emp.Description__c;
        rec.roleSummary = emp.Description__c;
        rec.jobRole = emp.Job_Role__c;

        results.add(rec);
      }

      return results;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving employment details: ' + e.getMessage()
      );
    }
  }
  /**
   * @description Creates, updates, or archives alumni employment details
   *              based on the submitted employment data.
   *
   * @param requestJson JSON string containing employment records.
   * @return            SaveResult indicating operation success or failure.
   */

  @AuraEnabled
  public static SaveResult saveEmploymentDetails(
    String requestJson,
    String roleId
  ) {
    SaveResult result = new SaveResult();
    try {
      if (String.isBlank(requestJson)) {
        throw new AuraHandledException('INVALID_REQUEST');
      }

      List<EmploymentRecord> records;
      try {
        records = (List<EmploymentRecord>) JSON.deserialize(
          requestJson,
          List<EmploymentRecord>.class
        );
      } catch (Exception e) {
        throw new AuraHandledException(
          'Invalid request format: ' + e.getMessage()
        );
      }

      Id roleRecordId = normalizeId(roleId);
      Id accountId = resolveAccountId(null, roleRecordId);
      if (accountId == null) {
        throw new AuraHandledException('NO_PERSON_ACCOUNT');
      }

      // Load existing employment records to update/archieve
      List<PersonEmployment> existingRecords = [
        SELECT Id, Is_Archived__c
        FROM PersonEmployment
        WHERE AccountId = :accountId
      WITH SECURITY_ENFORCED
      ];
      Map<Id, PersonEmployment> existingById = new Map<Id, PersonEmployment>(
        existingRecords
      );
      Set<Id> incomingIds = new Set<Id>();

      // PersonEmployment.RelatedPersonId is required; resolve from the Person Account's Contact.
      Id relatedPersonId;
      List<Account> personAccts = [
        SELECT PersonContactId FROM Account WHERE Id = :accountId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!personAccts.isEmpty()) {
        relatedPersonId = personAccts[0].PersonContactId;
      }

      List<PersonEmployment> toUpsert = new List<PersonEmployment>();

      for (EmploymentRecord rec : records) {
        if (rec == null) {
          continue;
        }

        PersonEmployment emp;
        if (
          isSalesforceId(rec.id) && existingById.containsKey(Id.valueOf(rec.id))
        ) {
          emp = existingById.get(Id.valueOf(rec.id));
          incomingIds.add(emp.Id);
        } else {
          emp = new PersonEmployment();
          emp.AccountId = accountId;
          if (relatedPersonId != null) {
            emp.RelatedPersonId = relatedPersonId;
          }
        }
        String companyName = rec.organization;
        // PersonEmployment.Name has the standard label "Employer" and is required. Mirror it
        // into Company_Name__c; reads use Company_Name__c.
        emp.Name = String.isNotBlank(companyName) ? companyName : 'Employer';
        emp.Company_Name__c = companyName;
        emp.Designation__c = rec.jobTitle;
        emp.EmploymentIndustry = rec.industry;
        emp.Location__c = String.isNotBlank(rec.location)
          ? rec.location
          : rec.country;
        emp.Currently_Employed__c = rec.isCurrentJob != null
          ? rec.isCurrentJob
          : false;
        emp.EmploymentType = normalizeEmploymentType(rec.employmentType);
        emp.Description__c = String.isNotBlank(rec.roleDescription)
          ? rec.roleDescription
          : rec.roleSummary;
        emp.Job_Role__c = rec.jobRole;

        // Parse dates
        emp.StartDate = String.isNotBlank(rec.startDate)
          ? Date.valueOf(rec.startDate)
          : null;
        if (!emp.Currently_Employed__c) {
          emp.EndDate = String.isNotBlank(rec.endDate)
            ? Date.valueOf(rec.endDate)
            : null;
        } else {
          emp.EndDate = null;
        }

        toUpsert.add(emp);
      }

      if (!toUpsert.isEmpty()) {
        Database.upsert(toUpsert, true, AccessLevel.SYSTEM_MODE);
      }

      List<PersonEmployment> toArchive = new List<PersonEmployment>();
      for (PersonEmployment existing : existingRecords) {
        if (existing.Id != null && !incomingIds.contains(existing.Id)) {
          if (existing.Is_Archived__c != true) {
            toArchive.add(
              new PersonEmployment(Id = existing.Id, Is_Archived__c = true)
            );
          }
        }
      }

      if (!toArchive.isEmpty()) {
        Database.update(toArchive, true, AccessLevel.SYSTEM_MODE);
      }

      String currentCompany = null;
      Date currentStart = null;
      for (EmploymentRecord rec : records) {
        if (
          rec == null ||
          rec.isCurrentJob != true ||
          String.isBlank(rec.organization)
        ) {
          continue;
        }
        Date recStart = String.isNotBlank(rec.startDate)
          ? Date.valueOf(rec.startDate)
          : null;
        if (
          currentCompany == null ||
          (recStart != null &&
          (currentStart == null ||
          recStart > currentStart))
        ) {
          currentCompany = rec.organization;
          if (recStart != null) {
            currentStart = recStart;
          }
        }
      }
      result.success = true;
      result.message = 'Employment details saved successfully.';
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error saving employment details: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Saves alumni engagement and communication preferences
   *              and updates registration status.
   *
   * @param preferences Engagement preferences data.
   * @return            SaveResult indicating save outcome.
   */

  // === Engagement ===
  @AuraEnabled
  public static SaveResult saveEngagementPreferences(
    String preferences,
    String roleId
  ) {
    SaveResult result = new SaveResult();

    try {
      Id roleRecordId = normalizeId(roleId);
      Id accountId = resolveAccountId(null, roleRecordId);
      if (accountId == null) {
        throw new AuraHandledException('NO_PERSON_ACCOUNT');
      }

      // Semicolon-separated names from the configurable
      // Ken_Engagement_Preference__c object, stored as plain text on the
      // Person Account so admin-added preferences save without
      // restricted-picklist errors.
      String prefText = preferences == null ? '' : preferences;
      if (prefText.length() > 255) {
        prefText = prefText.substring(0, 255);
      }
      Database.update(new Account(Id = accountId, Engagement_Preferences__c = prefText), true, AccessLevel.SYSTEM_MODE);
      updateRegistrationStatus(roleRecordId, accountId, REG_STATUS_REGISTERED);

      result.success = true;
      result.message = 'Preferences saved successfully.';
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error saving preferences: ' + e.getMessage()
      );
    }
  }
  /**
   * @description Retrieves the saved engagement preferences for the
   *              currently logged-in alumni user.
   *
   * @return Engagement preferences data as a string.
   */

  @AuraEnabled(cacheable=false)
  public static String getEngagementPreferences(String roleId) {
    Id roleRecordId = normalizeId(roleId);
    Id accountId = resolveAccountId(null, roleRecordId);
    if (accountId == null) {
      throw new AuraHandledException('NO_PERSON_ACCOUNT');
    }

    return [
      SELECT Engagement_Preferences__c FROM Account WHERE Id = :accountId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ]
    .Engagement_Preferences__c;
  }
  /**
   * @description Marks the alumni user as having completed the initial
   *              login after onboarding.
   *
   * @return SaveResult indicating whether the update was successful.
   */

  @AuraEnabled
  public static SaveResult markLoggedInOnce(String roleId) {
    SaveResult result = new SaveResult();

    try {
      Id roleRecordId = normalizeId(roleId);
      Id accountId = resolveAccountId(null, roleRecordId);
      if (accountId == null) {
        throw new AuraHandledException('NO_PERSON_ACCOUNT');
      }

      ConstituentRole cr = fetchAlumniRoleById(roleRecordId, accountId);
      if (cr == null) {
        throw new AuraHandledException('ALUMNI_ROLE_NOT_FOUND');
      }

      if (cr.Registration_Status__c != REG_STATUS_INITIAL_LOGIN_DONE) {
        Database.update(new ConstituentRole(
          Id = cr.Id,
          Registration_Status__c = REG_STATUS_INITIAL_LOGIN_DONE
        ), true, AccessLevel.SYSTEM_MODE);
      }

      result.success = true;
      result.message = 'Marked login as completed.';
      return result;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error updating login status: ' + e.getMessage()
      );
    }
  }

  // === Employment Helpers ===
  @TestVisible
  private static String normalizeEmploymentType(String inputValue) {
    if (String.isBlank(inputValue)) {
      return null;
    }

    String normalized = inputValue.trim().toLowerCase();
    Map<String, String> valueByLower = getEmploymentTypeValueMap();
    if (valueByLower.containsKey(normalized)) {
      return valueByLower.get(normalized);
    }

    String noHyphen = normalized.replace('-', ' ');
    noHyphen = noHyphen.replaceAll('\\s+', ' ').trim();
    if (valueByLower.containsKey(noHyphen)) {
      return valueByLower.get(noHyphen);
    }

    return null;
  }

  private static Map<String, String> getEmploymentTypeValueMap() {
    if (Employment_Type_By_Lower != null) {
      return Employment_Type_By_Lower;
    }

    Employment_Type_By_Lower = new Map<String, String>();
    for (
      Schema.PicklistEntry entry : PersonEmployment.EmploymentType.getDescribe()
        .getPicklistValues()
    ) {
      String value = entry.getValue();
      if (String.isNotBlank(value)) {
        Employment_Type_By_Lower.put(value.toLowerCase(), value);
      }
    }
    return Employment_Type_By_Lower;
  }

  @TestVisible
  private static Boolean isSalesforceId(String value) {
    if (String.isBlank(value)) {
      return false;
    }
    try {
      Id temp = (Id) value;
      return temp != null;
    } catch (Exception e) {
      return false;
    }
  }

  @TestVisible
  private static void updateConstituentRoleEmail(
    Id roleId,
    Id accountId,
    String email
  ) {
    if (roleId == null || String.isBlank(email)) {
      return;
    }

    ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
    if (cr == null || cr.Email__c == email) {
      return;
    }

    Database.update(new ConstituentRole(Id = cr.Id, Email__c = email), true, AccessLevel.SYSTEM_MODE);
  }

  @TestVisible
  private static Lead findLeadForRole(Id accountId, Id roleId, String email) {
    ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
    if (cr == null) {
      return null;
    }
    Id effectiveAccountId = accountId != null ? accountId : cr.PersonId;

    if (KenNamespaceUtil.hasField(ConstituentRole.SObjectType.getDescribe().fields.getMap(), 'Lead__c') && cr.Lead__c != null) {
      List<Lead> byLookup = [
        SELECT
          Id,
          Email,
          Phone,
          Year_of_Graduation__c,
          Program_Plan__c,
          Registration_Number__c
        FROM Lead
        WHERE Id = :cr.Lead__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!byLookup.isEmpty()) {
        return byLookup[0];
      }
    }

    if (String.isNotBlank(cr.Registration_Number__c)) {
      List<Lead> byReg = [
        SELECT
          Id,
          Email,
          Phone,
          Year_of_Graduation__c,
          Program_Plan__c,
          Registration_Number__c
        FROM Lead
        WHERE Registration_Number__c = :cr.Registration_Number__c
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC
      ];
      if (byReg.size() > 1) {
        throw new AuraHandledException(
          'Duplicate lead detected for registration number. Please contact support.'
        );
      }
      if (!byReg.isEmpty()) {
        return byReg[0];
      }
    }

    Set<String> candidateEmails = new Set<String>();
    if (String.isNotBlank(email)) {
      candidateEmails.add(email);
    }
    if (String.isNotBlank(cr.Email__c)) {
      candidateEmails.add(cr.Email__c);
    }
    Account pa = fetchPersonAccountById(effectiveAccountId);
    if (pa != null && String.isNotBlank(pa.PersonEmail)) {
      candidateEmails.add(pa.PersonEmail);
    }

    if (!candidateEmails.isEmpty() && cr.Program_Plan__c != null) {
      List<Lead> byProgramAndEmail = [
        SELECT
          Id,
          Email,
          Phone,
          Year_of_Graduation__c,
          Program_Plan__c,
          Registration_Number__c
        FROM Lead
        WHERE
          Program_Plan__c = :cr.Program_Plan__c
          AND Email IN :candidateEmails
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC
      ];
      if (!byProgramAndEmail.isEmpty()) {
        return byProgramAndEmail[0];
      }
    }

    if (!candidateEmails.isEmpty()) {
      List<Lead> byEmail = [
        SELECT
          Id,
          Email,
          Phone,
          Year_of_Graduation__c,
          Program_Plan__c,
          Registration_Number__c
        FROM Lead
        WHERE Email IN :candidateEmails
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC
      ];
      if (!byEmail.isEmpty()) {
        if (cr.Program_Plan__c != null) {
          for (Lead l : byEmail) {
            if (l.Program_Plan__c == cr.Program_Plan__c) {
              return l;
            }
          }
        }
        return byEmail[0];
      }
    }

    return null;
  }

  @TestVisible
  private static void updateLeadDetails(Id accountId, Id roleId, String email) {
    if (accountId == null) {
      return;
    }

    List<Account> paList = [
      SELECT Id, PersonEmail, Phone, PersonMobilePhone
      FROM Account
      WHERE Id = :accountId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    Account pa = paList.isEmpty() ? null : paList[0];

    if (pa == null) {
      return;
    }

    Lead lead = findLeadForRole(accountId, roleId, email);
    if (lead == null) {
      return;
    }

    ConstituentRole selectedRole = fetchAlumniRoleById(roleId, accountId);

    Lead leadToUpdate = new Lead(
      Id = lead.Id,
      Phone = (lead != null && String.isNotBlank(lead.Phone))
        ? lead.Phone
        : (String.isNotBlank(pa.Phone) ? pa.Phone : pa.PersonMobilePhone)
    );

    // Sync graduation year and programme between the lead and the role. The
    // role wins when it already holds a value; otherwise the lead seeds it.
    if (selectedRole != null) {
      ConstituentRole roleToUpdate = new ConstituentRole(Id = selectedRole.Id);
      Boolean roleDirty = false;

      if (String.isNotBlank(selectedRole.Graduation_Year__c)) {
        leadToUpdate.Year_of_Graduation__c = selectedRole.Graduation_Year__c;
      } else if (lead.Year_of_Graduation__c != null) {
        roleToUpdate.Graduation_Year__c = String.valueOf(
          lead.Year_of_Graduation__c
        );
        roleDirty = true;
      }

      if (String.isNotBlank(selectedRole.Program_Plan__c)) {
        leadToUpdate.Program_Plan__c = selectedRole.Program_Plan__c;
      } else if (lead.Program_Plan__c != null) {
        roleToUpdate.Program_Plan__c = lead.Program_Plan__c;
        roleDirty = true;
      }

      if (roleDirty) {
        Database.update(roleToUpdate, true, AccessLevel.SYSTEM_MODE);
      }
    }

    // Sync phone back to account if missing
    if (
      lead != null &&
      String.isNotBlank(lead.Phone) &&
      String.isBlank(pa.Phone) &&
      String.isBlank(pa.PersonMobilePhone)
    ) {
      pa.Phone = lead.Phone;
      pa.PersonMobilePhone = lead.Phone;
      Database.update(pa, true, AccessLevel.SYSTEM_MODE);
    }

    Database.update(leadToUpdate, true, AccessLevel.SYSTEM_MODE);
  }

  @TestVisible
  private static void ensureAlumniRoleExists(Id roleId, Id accountId) {
    ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
    if (cr == null) {
      throw new AuraHandledException('ALUMNI_ROLE_NOT_FOUND');
    }
  }

  @TestVisible
  private static User findUserByEmail(String email) {
    List<User> users = [
      SELECT Id, AccountId
      FROM User
      WHERE Email = :email AND IsActive = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    if (users.isEmpty()) {
      throw new AuraHandledException(MSG_USER_NOT_FOUND);
    }

    return users[0];
  }

  private static Map<String, Account> getOrCreateCompanyAccounts(
    List<EmploymentRecord> records
  ) {
    Map<String, Account> result = new Map<String, Account>();
    if (records == null || records.isEmpty()) {
      return result;
    }

    Map<String, String> nameByKey = new Map<String, String>();
    for (EmploymentRecord rec : records) {
      if (rec != null && String.isNotBlank(rec.organization)) {
        String normalized = rec.organization.trim();
        nameByKey.put(normalized.toLowerCase(), normalized);
      }
    }
    if (nameByKey.isEmpty()) {
      return result;
    }

    Id companyRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
      .get('Company')
      .getRecordTypeId();

    for (Account a : [
      SELECT Id, Name
      FROM Account
      WHERE RecordTypeId = :companyRtId AND Name IN :nameByKey.values()
    WITH SECURITY_ENFORCED
    ]) {
      result.put(a.Name.trim().toLowerCase(), a);
    }

    List<Account> toInsert = new List<Account>();
    for (String nameKey : nameByKey.keySet()) {
      if (!result.containsKey(nameKey)) {
        String nameValue = nameByKey.get(nameKey);
        toInsert.add(new Account(RecordTypeId = companyRtId, Name = nameValue));
      }
    }

    if (!toInsert.isEmpty()) {
      if (!toInsert.isEmpty()) {
        Database.insert(toInsert, true, AccessLevel.SYSTEM_MODE);
      }
      for (Account a : toInsert) {
        result.put(a.Name.trim().toLowerCase(), a);
      }
    }

    return result;
  }

  @TestVisible
  private static ConstituentRole fetchAlumniRoleById(Id roleId, Id accountId) {
    if (roleId == null) {
      return null;
    }
    List<ConstituentRole> roles;
    if (accountId != null) {
      roles = [
        SELECT
          Id,
          PersonId,
          Registration_Status__c,
          Email__c,
          Program_Plan__c,
          Graduation_Year__c,
          Year_of_Enrollment__c,
          Registration_Number__c,
          Lead__c,
          Institution_Name__c
        FROM ConstituentRole
        WHERE
          Id = :roleId
          AND PersonId = :accountId
          AND RoleType = :ROLETYPE_ALUMNI
        WITH SYSTEM_MODE
        LIMIT 1
      ];
    } else {
      roles = [
        SELECT
          Id,
          PersonId,
          Registration_Status__c,
          Email__c,
          Program_Plan__c,
          Graduation_Year__c,
          Year_of_Enrollment__c,
          Registration_Number__c,
          Lead__c,
          Institution_Name__c
        FROM ConstituentRole
        WHERE Id = :roleId AND RoleType = :ROLETYPE_ALUMNI
        WITH SYSTEM_MODE
        LIMIT 1
      ];
    }
    return roles.isEmpty() ? null : roles[0];
  }

  /**
   * @description True when the org has opted to freeze the details captured at
   *              registration so the alumnus cannot edit them during onboarding.
   *
   *              A missing org-parameters record returns false, leaving every
   *              field editable — the behaviour that predates this setting, so an
   *              unconfigured org is never changed by deploying it.
   *
   * @return Whether registration-derived fields render read-only.
   */
  @TestVisible
  private static Boolean isRegistrationDetailsLocked() {
    Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
    return params != null && params.Lock_Registration_Details__c == true;
  }

  @TestVisible
  private static void updateRegistrationStatus(
    Id roleId,
    Id accountId,
    String targetStatus
  ) {
    if (roleId == null || String.isBlank(targetStatus)) {
      return;
    }
    ConstituentRole cr = fetchAlumniRoleById(roleId, accountId);
    if (cr == null) {
      return;
    }
    if (cr.Registration_Status__c == targetStatus) {
      return;
    }
    if (
      regStatusRank(targetStatus) <= regStatusRank(cr.Registration_Status__c)
    ) {
      return;
    }
    Database.update(new ConstituentRole(
      Id = cr.Id,
      Registration_Status__c = targetStatus
    ), true, AccessLevel.SYSTEM_MODE);
  }

  /**
   * @description Ordinal rank of a registration status used to keep lifecycle
   *              transitions advance-only (a record is never moved backwards).
   */
  private static Integer regStatusRank(String status) {
    if (status == null) {
      return 0;
    }
    Integer r = REG_STATUS_RANK.get(status);
    return r == null ? 0 : r;
  }
}