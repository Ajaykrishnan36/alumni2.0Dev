public without sharing class KenMyProfileController {
    public class ProfileData {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String company;
        @AuraEnabled public String location;
        @AuraEnabled public String profileImage;
        @AuraEnabled public Boolean isOnline;
        @AuraEnabled public String batch;
        @AuraEnabled public String expertise;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String linkedin;
        @AuraEnabled public Boolean willingToHelp;
        @AuraEnabled public String about;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String idCardUrl;
        @AuraEnabled public List<EducationRow> education;
        @AuraEnabled public List<ExperienceRow> experience;
        @AuraEnabled public List<AchievementRow> achievements;
    }

    public class EducationRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String degree;
        @AuraEnabled public String institution;
        @AuraEnabled public String duration;
        @AuraEnabled public String score;
        @AuraEnabled public String startMonth;
        @AuraEnabled public String startYear;
        @AuraEnabled public String endMonth;
        @AuraEnabled public String endYear;
        @AuraEnabled public String gradingFormat;
        @AuraEnabled public String cgpa;
        @AuraEnabled public String programPlan;
        @AuraEnabled public String registrationNumber;
        @AuraEnabled public String institutionType;
    }

    public class ExperienceRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String position;
        @AuraEnabled public String company;
        @AuraEnabled public String employmentType;
        @AuraEnabled public String location;
        @AuraEnabled public String workType;
        @AuraEnabled public String duration;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean isCurrentJob;
        @AuraEnabled public String startMonth;
        @AuraEnabled public String startYear;
        @AuraEnabled public String endMonth;
        @AuraEnabled public String endYear;
        @AuraEnabled public String jobRole;
    }

    public class AchievementRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String type;
        @AuraEnabled public String title;
        @AuraEnabled public String organization;
        @AuraEnabled public String meta;
        @AuraEnabled public String description;
        @AuraEnabled public String dateMonth;
        @AuraEnabled public String dateYear;
        @AuraEnabled public String patentNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String role;
        @AuraEnabled public String referenceUrl;
        @AuraEnabled public String paperType;
    }

    public class EducationInput {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String degree { get; set; }
        @AuraEnabled public String institution { get; set; }
        @AuraEnabled public String startMonth { get; set; }
        @AuraEnabled public String startYear { get; set; }
        @AuraEnabled public String endMonth { get; set; }
        @AuraEnabled public String endYear { get; set; }
        @AuraEnabled public String gradingFormat { get; set; }
        @AuraEnabled public String cgpa { get; set; }
        @AuraEnabled public String institutionType { get; set; }
        @AuraEnabled public String programPlan { get; set; }
        @AuraEnabled public String registrationNumber { get; set; }
    }

    public class ExperienceInput {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String jobTitle { get; set; }
        @AuraEnabled public String organization { get; set; }
        @AuraEnabled public String employmentType { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String startMonth { get; set; }
        @AuraEnabled public String startYear { get; set; }
        @AuraEnabled public String endMonth { get; set; }
        @AuraEnabled public String endYear { get; set; }
        @AuraEnabled public Boolean isCurrentJob { get; set; }
        @AuraEnabled public String roleDescription { get; set; }
        @AuraEnabled public String workType { get; set; }
        @AuraEnabled public String jobRole { get; set; }
    }

    public class AchievementInput {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String organization { get; set; }
        @AuraEnabled public String dateMonth { get; set; }
        @AuraEnabled public String dateYear { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String patentNumber { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String role { get; set; }
        @AuraEnabled public String referenceUrl { get; set; }
        @AuraEnabled public String paperType { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static ProfileData getMyProfile() {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) {
            return buildEmptyProfile();
        }

        List<Account> accountRows = [
            SELECT Id, Name, PersonTitle, PersonEmail, PersonMobilePhone,
                   PersonMailingCity, PersonMailingState, PersonMailingCountry, PhotoUrl,
                   Description, Linkedin_Profile_URL__c
            FROM Account
            WHERE Id = :accountId AND IsPersonAccount = true
            LIMIT 1
        ];
        if (accountRows.isEmpty()) {
            return buildEmptyProfile();
        }

        Account acc = accountRows[0];

        Id constituentRoleId = getActiveConstituentRoleId(accountId);
        List<Ken_Alumni_CRM__c> alumniRows = constituentRoleId != null
            ? [
                SELECT Id, Person_Account__c, Profile_Photo_URL__c, Current_Location__c,
                       Current_Company__c, Specialization__c, Year_of_Graduation__c, Last_Active__c,
                       Registration_Number__c, ID_Card_URL__c
                FROM Ken_Alumni_CRM__c
                WHERE ConstituentRole__c = :constituentRoleId
                LIMIT 1
              ]
            : [
                SELECT Id, Person_Account__c, Profile_Photo_URL__c, Current_Location__c,
                       Current_Company__c, Specialization__c, Year_of_Graduation__c, Last_Active__c,
                       Registration_Number__c, ID_Card_URL__c
                FROM Ken_Alumni_CRM__c
                WHERE Person_Account__c = :accountId
                ORDER BY LastModifiedDate DESC
                LIMIT 1
              ];
        Ken_Alumni_CRM__c alumni = alumniRows.isEmpty() ? null : alumniRows[0];

        List<EducationRow> educationRows = queryEducationRows(accountId);
        List<ExperienceRow> experienceRows = queryExperienceRows(accountId);
        List<AchievementRow> achievementRows = queryAchievementRows(accountId);

        ExperienceRow latestJob = experienceRows.isEmpty() ? null : experienceRows[0];

        ProfileData profile = new ProfileData();
        profile.accountId = accountId;
        profile.name = acc.Name;
        profile.title = firstNonBlank(latestJob != null ? latestJob.position : null, acc.PersonTitle);
        profile.company = firstNonBlank(alumni != null ? alumni.Current_Company__c : null, latestJob != null ? latestJob.company : null);
        profile.location = buildLocation(acc, alumni, latestJob);
        profile.profileImage = resolveProfileImage(acc, alumni);
        profile.isOnline = isCurrentlyOnline(alumni != null ? alumni.Last_Active__c : null);
        profile.batch = String.isNotBlank(alumni != null ? alumni.Year_of_Graduation__c : null)
            ? 'Batch ' + alumni.Year_of_Graduation__c
            : null;
        profile.expertise = alumni != null ? alumni.Specialization__c : null;
        profile.email = acc.PersonEmail;
        profile.phone = acc.PersonMobilePhone;
        profile.linkedin = acc.Linkedin_Profile_URL__c;
        profile.willingToHelp = true;
        profile.about = acc.Description;
        profile.registrationNumber = alumni != null ? alumni.Registration_Number__c : null;
        profile.idCardUrl = alumni != null ? alumni.ID_Card_URL__c : null;
        profile.education = educationRows;
        profile.experience = experienceRows;
        profile.achievements = achievementRows;
        return profile;
    }

    @AuraEnabled
    public static Id saveEducation(EducationInput input) {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) {
            throw new AuraHandledException('Unable to determine current user account.');
        }
        if (input == null) {
            throw new AuraHandledException('Education payload was empty.');
        }

        PersonEducation recordRow;
        if (input != null && input.id != null) {
            List<PersonEducation> existingRows = [
                SELECT Id
                FROM PersonEducation
                WHERE Id = :input.id AND AccountId = :accountId
                LIMIT 1
            ];
            if (existingRows.isEmpty()) {
                throw new AuraHandledException('Education record not found.');
            }
            recordRow = existingRows[0];
        } else {
            recordRow = new PersonEducation();
            recordRow.AccountId = accountId;
        }

        String institutionName = sanitize(input != null ? input.institution : null);
        String degreeName = sanitize(input != null ? input.degree : null);
        // PersonEducation.Name has the standard label "Degree" and is required. Mirror it
        // into Degree_Name__c (matches KjsUat pattern); reads use Degree_Name__c.
        recordRow.Name = String.isNotBlank(degreeName) ? degreeName : 'Degree';
        recordRow.Degree_Name__c = degreeName;
        recordRow.Institute_Name__c = institutionName;
        recordRow.StartDate = buildDate(input != null ? input.startYear : null, input != null ? input.startMonth : null);
        recordRow.EndDate = buildDate(input != null ? input.endYear : null, input != null ? input.endMonth : null);
        recordRow.Year_of_Completion__c = sanitize(input != null ? input.endYear : null);
        recordRow.Grade_Type__c = normalizeGradeType(input != null ? input.gradingFormat : null);
        recordRow.Grade__c = sanitize(input != null ? input.cgpa : null);
        recordRow.Is_Archived__c = false;
        if (input != null && String.isNotBlank(input.institutionType)) {
            recordRow.Institution_Type__c = (input.institutionType == 'other') ? 'Other' : 'Our Institute';
        }

        Id planId = null;
        if (input != null && String.isNotBlank(input.programPlan)) {
            try {
                planId = (Id) input.programPlan;
            } catch (Exception e) {
                planId = null;
            }
        }
        recordRow.Program_Plan__c = planId;
        recordRow.Registration_Number__c = sanitize(input != null ? input.registrationNumber : null);

        upsert recordRow;
        return recordRow.Id;
    }
    @AuraEnabled
    public static void archiveEducation(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Education record id is required.');
        }
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) {
            throw new AuraHandledException('Unable to determine current user account.');
        }

        List<PersonEducation> rows = [
            SELECT Id, Is_Archived__c
            FROM PersonEducation
            WHERE Id = :recordId AND AccountId = :accountId
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
            throw new AuraHandledException('Unable to determine current user account.');
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
                SELECT PersonContactId FROM Account WHERE Id = :accountId LIMIT 1
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
        row.EmploymentType = normalizeEmploymentType(input != null ? input.employmentType : null);
        row.Job_Role__c = normalizeJobRole(input != null ? input.jobRole : null);
        row.Location__c = sanitize(input != null ? input.location : null);
        row.EmploymentSite = normalizeLocationType(input != null ? input.workType : null);
        row.StartDate = buildDate(input != null ? input.startYear : null, input != null ? input.startMonth : null);
        row.Currently_Employed__c = isCurrent;
        row.EndDate = isCurrent ? null : buildDate(input != null ? input.endYear : null, input != null ? input.endMonth : null);
        row.Description__c = input != null ? input.roleDescription : null;
        row.Is_Archived__c = false;

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
            throw new AuraHandledException('Unable to determine current user account.');
        }

        List<PersonEmployment> rows = [
            SELECT Id, Is_Archived__c
            FROM PersonEmployment
            WHERE Id = :recordId AND AccountId = :accountId
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
            throw new AuraHandledException('Unable to determine current user account.');
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

        row.Achievement_Type__c = normalizeAchievementType(input != null ? input.type : null);
        row.Title__c = sanitize(input != null ? input.title : null);
        row.Issuing_Organisation__c = sanitize(input != null ? input.organization : null);
        row.Date__c = buildDate(input != null ? input.dateYear : null, input != null ? input.dateMonth : null);
        row.Description__c = sanitize(input != null ? input.description : null);
        row.Application_or_Patent_Number__c = keepOnlyDigits(input != null ? input.patentNumber : null);
        row.Achievement_Status__c = normalizeAchievementStatus(input != null ? input.status : null);
        row.Role__c = normalizeAchievementRole(input != null ? input.role : null);
        row.Reference_URL__c = sanitize(input != null ? input.referenceUrl : null);
        row.Paper_Type__c = normalizePaperType(input != null ? input.paperType : null);
        row.Is_Archived__c = false;

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
            throw new AuraHandledException('Unable to determine current user account.');
        }

        List<Ken_Achievement__c> rows = [
            SELECT Id, Is_Archived__c
            FROM Ken_Achievement__c
            WHERE Id = :recordId AND Person_Account__c = :accountId
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
            throw new AuraHandledException('Unable to determine current user account.');
        }

        List<Account> rows = [
            SELECT Id, Description
            FROM Account
            WHERE Id = :accountId AND IsPersonAccount = true
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

        for (PersonEducation rec : [
            SELECT Id, Degree_Name__c, Institute_Name__c, Institution_Type__c,
                   Program_Plan__c, Registration_Number__c,
                   StartDate, EndDate, Year_of_Completion__c, Grade__c, Grade_Type__c
            FROM PersonEducation
            WHERE AccountId = :accountId
              AND (Is_Archived__c = false OR Is_Archived__c = null)
            ORDER BY EndDate DESC NULLS LAST, StartDate DESC NULLS LAST, CreatedDate DESC
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
            row.startMonth = rec.StartDate != null ? twoDigit(rec.StartDate.month()) : null;
            row.startYear = rec.StartDate != null ? String.valueOf(rec.StartDate.year()) : null;
            row.endMonth = rec.EndDate != null ? twoDigit(rec.EndDate.month()) : null;
            row.endYear = rec.EndDate != null ? String.valueOf(rec.EndDate.year()) : rec.Year_of_Completion__c;
            row.gradingFormat = normalizeGradeTypeOutput(rec.Grade_Type__c);
            row.cgpa = rec.Grade__c;
            row.programPlan = rec.Program_Plan__c != null ? String.valueOf(rec.Program_Plan__c) : null;
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
            SELECT Id, Designation__c, Company_Name__c, EmploymentType, Job_Role__c, Location__c,
                   EmploymentSite, Description__c, StartDate, EndDate, Currently_Employed__c
            FROM PersonEmployment
            WHERE AccountId = :accountId
              AND (Is_Archived__c = false OR Is_Archived__c = null)
            ORDER BY Currently_Employed__c DESC NULLS LAST, StartDate DESC NULLS LAST, CreatedDate DESC
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
            row.duration = buildEmploymentDuration(rec.StartDate, rec.EndDate, row.isCurrentJob);
            row.startMonth = rec.StartDate != null ? twoDigit(rec.StartDate.month()) : null;
            row.startYear = rec.StartDate != null ? String.valueOf(rec.StartDate.year()) : null;
            row.endMonth = rec.EndDate != null ? twoDigit(rec.EndDate.month()) : null;
            row.endYear = rec.EndDate != null ? String.valueOf(rec.EndDate.year()) : null;
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
            SELECT Id, Achievement_Type__c, Title__c, Issuing_Organisation__c, Date__c, Description__c,
                   Application_or_Patent_Number__c, Achievement_Status__c, Role__c, Reference_URL__c, Paper_Type__c
            FROM Ken_Achievement__c
            WHERE Person_Account__c = :accountId
              AND (Is_Archived__c = false OR Is_Archived__c = null)
            ORDER BY Date__c DESC NULLS LAST, CreatedDate DESC
        ]) {
            AchievementRow row = new AchievementRow();
            row.id = rec.Id;
            row.type = normalizeAchievementTypeOutput(rec.Achievement_Type__c);
            row.title = rec.Title__c;
            row.organization = rec.Issuing_Organisation__c;
            row.description = rec.Description__c;
            row.dateMonth = rec.Date__c != null ? twoDigit(rec.Date__c.month()) : null;
            row.dateYear = rec.Date__c != null ? String.valueOf(rec.Date__c.year()) : null;
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
        List<User> users = [SELECT Id, AccountId, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (users.isEmpty()) return null;
        User currentUser = users[0];
        if (currentUser.AccountId != null) return currentUser.AccountId;
        if (currentUser.ContactId != null) {
            List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :currentUser.ContactId LIMIT 1];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) return contacts[0].AccountId;
        }
        return null;
    }

    private static String resolveProfileImage(Account acc, Ken_Alumni_CRM__c alumni) {
        if (alumni != null && String.isNotBlank(alumni.Profile_Photo_URL__c)) {
            return alumni.Profile_Photo_URL__c;
        }
        return null;
    }

    private static String buildLocation(Account acc, Ken_Alumni_CRM__c alumni, ExperienceRow latestJob) {
        if (alumni != null && String.isNotBlank(alumni.Current_Location__c)) {
            return alumni.Current_Location__c;
        }
        if (latestJob != null && String.isNotBlank(latestJob.location)) {
            return latestJob.location;
        }

        List<String> parts = new List<String>();
        if (acc != null) {
            if (String.isNotBlank(acc.PersonMailingCity)) parts.add(acc.PersonMailingCity);
            if (String.isNotBlank(acc.PersonMailingState)) parts.add(acc.PersonMailingState);
            if (String.isNotBlank(acc.PersonMailingCountry)) parts.add(acc.PersonMailingCountry);
        }
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static Boolean isCurrentlyOnline(Datetime lastActive) {
        if (lastActive == null) {
            return false;
        }
        return lastActive.getTime() >= System.now().addMinutes(-5).getTime();
    }

    private static String buildEducationDuration(Date startDate, Date endDate, String yearOfGraduation) {
        String startY = startDate != null ? String.valueOf(startDate.year()) : null;
        String endY = endDate != null ? String.valueOf(endDate.year()) : sanitize(yearOfGraduation);
        if (String.isBlank(startY) && String.isBlank(endY)) return null;
        if (String.isBlank(startY)) return endY;
        if (String.isBlank(endY)) return startY;
        return startY + ' - ' + endY;
    }

    private static String buildEmploymentDuration(Date startDate, Date endDate, Boolean isCurrent) {
        if (startDate == null) {
            return null;
        }

        String startLabel = shortMonthName(startDate.month()) + ' ' + String.valueOf(startDate.year());
        String endLabel;
        if (isCurrent == true) {
            endLabel = 'Present';
        } else if (endDate != null) {
            endLabel = shortMonthName(endDate.month()) + ' ' + String.valueOf(endDate.year());
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
        return normalizePicklistValue(PersonEmployment.EmploymentType.getDescribe(), inputValue);
    }

    private static String normalizeJobRole(String inputValue) {
        return normalizePicklistValue(PersonEmployment.Job_Role__c.getDescribe(), inputValue);
    }

    private static String normalizeLocationType(String inputValue) {
        String normalized = normalizePicklistValue(PersonEmployment.EmploymentSite.getDescribe(), inputValue);
        return String.isNotBlank(normalized) ? normalized : 'Onsite';
    }

    private static String normalizeGradeType(String inputValue) {
        if (String.isBlank(inputValue)) {
            return null;
        }

        String trimmed = inputValue.trim();
        String normalized = normalizePicklistValue(PersonEducation.Grade_Type__c.getDescribe(), trimmed);
        if (String.isNotBlank(normalized)) {
            return normalized;
        }

        if (trimmed.toLowerCase().contains('percent')) {
            String alt = normalizePicklistValue(PersonEducation.Grade_Type__c.getDescribe(), 'PERCENTAGE');
            return String.isNotBlank(alt) ? alt : null;
        }
        if (trimmed.equalsIgnoreCase('cgpa')) {
            return normalizePicklistValue(PersonEducation.Grade_Type__c.getDescribe(), 'CGPA');
        }
        return null;
    }

    private static String normalizeGradeTypeOutput(String value) {
        if (String.isBlank(value)) {
            return 'CGPA';
        }
        return value.equalsIgnoreCase('PERCENTAGE') || value.equalsIgnoreCase('Percentage')
            ? 'Percentage'
            : value;
    }

    private static String normalizeAchievementType(String inputValue) {
        String normalized = normalizePicklistValue(Ken_Achievement__c.Achievement_Type__c.getDescribe(), inputValue);
        if (String.isNotBlank(normalized)) {
            return normalized;
        }

        if (String.isBlank(inputValue)) {
            return null;
        }

        String trimmed = inputValue.trim();
        if (trimmed.equalsIgnoreCase('Honour / Award')) return normalizePicklistValue(Ken_Achievement__c.Achievement_Type__c.getDescribe(), 'Honors & Awards');
        if (trimmed.equalsIgnoreCase('Certification')) return normalizePicklistValue(Ken_Achievement__c.Achievement_Type__c.getDescribe(), 'Certifications');
        if (trimmed.equalsIgnoreCase('Publication')) return normalizePicklistValue(Ken_Achievement__c.Achievement_Type__c.getDescribe(), 'Publications');
        if (trimmed.equalsIgnoreCase('Patent')) return normalizePicklistValue(Ken_Achievement__c.Achievement_Type__c.getDescribe(), 'Patents');
        return trimmed;
    }

    private static String normalizeAchievementTypeOutput(String value) {
        if (String.isBlank(value)) {
            return 'Honors & Awards';
        }

        if (value.equalsIgnoreCase('Honour / Award')) return 'Honors & Awards';
        if (value.equalsIgnoreCase('Certification')) return 'Certifications';
        if (value.equalsIgnoreCase('Publication')) return 'Publications';
        if (value.equalsIgnoreCase('Patent')) return 'Patents';
        return value;
    }

    private static String normalizeAchievementStatus(String inputValue) {
        return normalizePicklistValue(Ken_Achievement__c.Achievement_Status__c.getDescribe(), inputValue);
    }

    private static String normalizeAchievementRole(String inputValue) {
        return normalizePicklistValue(Ken_Achievement__c.Role__c.getDescribe(), inputValue);
    }

    private static String normalizePaperType(String inputValue) {
        return normalizePicklistValue(Ken_Achievement__c.Paper_Type__c.getDescribe(), inputValue);
    }

    private static String normalizePicklistValue(Schema.DescribeFieldResult describeResult, String inputValue) {
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
            WHERE Name = :normalized AND IsPersonAccount = false
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        Account organization = new Account(Name = normalized);
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
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
     * @description Persists the generated ID card download URL on the current
     *              user's Ken_Alumni_CRM__c record.
     *
     * @param url  ContentDownloadUrl returned by KenCreateContentVersion.
     */
    @AuraEnabled
    public static void saveIdCardUrl(String url) {
        Id accountId = getCurrentUserAccountId();
        if (accountId == null) {
            throw new AuraHandledException('Unable to determine current user account.');
        }

        Id constituentRoleId = getActiveConstituentRoleId(accountId);
        List<Ken_Alumni_CRM__c> rows = constituentRoleId != null
            ? [SELECT Id, ID_Card_URL__c FROM Ken_Alumni_CRM__c
               WHERE ConstituentRole__c = :constituentRoleId LIMIT 1]
            : [SELECT Id, ID_Card_URL__c FROM Ken_Alumni_CRM__c
               WHERE Person_Account__c = :accountId ORDER BY LastModifiedDate DESC LIMIT 1];

        if (rows.isEmpty()) {
            return;
        }

        if (Schema.sObjectType.Ken_Alumni_CRM__c.isUpdateable()) {
            rows[0].ID_Card_URL__c = url;
            update rows[0];
        }
    }

    /**
     * @description Returns the Id of the most relevant active ConstituentRole for
     *              the given PersonAccount. Prefers a 'Registered' role, then any
     *              alumni role, falling back to null if none exist.
     *
     * @param accountId  PersonAccount Id.
     * @return           ConstituentRole Id, or null.
     */
    private static Id getActiveConstituentRoleId(Id accountId) {
        if (accountId == null) {
            return null;
        }
        List<ConstituentRole> registered = [
            SELECT Id FROM ConstituentRole
            WHERE PersonId = :accountId
              AND RoleType = 'Alumni'
              AND Registration_Status__c = 'Registered'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!registered.isEmpty()) {
            return registered[0].Id;
        }
        List<ConstituentRole> allRoles = [
            SELECT Id FROM ConstituentRole
            WHERE PersonId = :accountId
              AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return allRoles.isEmpty() ? null : allRoles[0].Id;
    }
}