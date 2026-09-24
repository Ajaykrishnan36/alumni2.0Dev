/**
 * KenAlumniReportController
 *
 * The two alumni CSV downloads offered in the Alumni Demographics dashboard
 * header (the Report tab of Alumni Management). One click streams the rows from
 * live data in slices, the browser assembles the CSV and saves it — there is no
 * queue, no email and no file stored in Salesforce.
 *
 *   - All Fields (product level): the full 43-column extract, one row per
 *     Alumni ConstituentRole, matching the Bulk Import template column set
 *     plus Institute Name.
 *   - Minimal Fields: the 6-column registration handover.
 *
 * Everything the feature needs lives in this one class. getReportChunk() is
 * called repeatedly by the dashboard, so every slice is its own transaction with
 * its own governor limits and the export has no size ceiling. Paging is by Id,
 * not OFFSET, which Salesforce caps at 2,000. The class runs
 * `with sharing`, so an institute coordinator downloads only the alumni their
 * sharing lets them see.
 *
 * ConstituentRole.PersonId is polymorphic and some legacy roles hold the
 * Person Account's Contact (003) Id rather than the Account (001) Id. Those
 * are resolved through Contact.AccountId, otherwise every personal column on
 * such a row would export blank with no error.
 *
 * Education is written into the fixed 10th / 12th / Bachelors / Masters column
 * blocks the format defines. PersonEducation carries no level field, so the
 * block is chosen from Degree_Name__c: school-level tokens pick 10th or 12th,
 * post-graduate tokens pick Masters, and everything else lands in Bachelors.
 * Where two rows claim the same block the later completion year wins.
 */
public with sharing class KenAlumniReportController {

    public static final String REPORT_ALL_FIELDS = 'alumniAllFields';
    public static final String REPORT_MINIMAL_FIELDS = 'minimalFields';

    public static final String PREFIX_ALL_FIELDS = 'alumni-all-fields-';
    public static final String PREFIX_MINIMAL_FIELDS = 'alumni-minimal-fields-';

    @TestVisible private static Integer chunkAllFields = 1000;
    @TestVisible private static Integer chunkMinimalFields = 5000;

    private static final Integer SLOT_TENTH = 0;
    private static final Integer SLOT_TWELFTH = 1;
    private static final Integer SLOT_BACHELORS = 2;
    private static final Integer SLOT_MASTERS = 3;
    private static final Integer SLOT_COUNT = 4;

    private static final List<String> TWELFTH_KEYWORDS = new List<String>{
        '12th', '12 th', 'class 12', 'std 12', 'xii', 'hsc', 'higher secondary',
        'intermediate', 'pre-university', 'pre university', 'puc'
    };
    private static final List<String> TENTH_KEYWORDS = new List<String>{
        '10th', '10 th', 'class 10', 'std 10', 'sslc', 'ssc', 'matric', 'secondary school'
    };
    private static final List<String> MASTERS_KEYWORDS = new List<String>{
        'master', 'm.tech', 'mtech', 'm.e.', 'm.sc', 'msc', 'mba', 'mca', 'm.com', 'mcom',
        'm.a.', 'm.phil', 'mphil', 'post graduate', 'postgraduate', 'post-graduate', 'pgdm',
        'pg diploma', 'phd', 'ph.d', 'doctor'
    };

    public static final List<String> ALL_FIELDS_HEADERS = new List<String>{
        'Email', 'First Name', 'Last Name', 'Phone', 'Date of Birth', 'Nationality', 'Gender',
        'Blood Group', 'LinkedIn URL', 'Languages Known', 'Address Street', 'Address City',
        'Address State', 'Address Postal Code', 'Address Country', 'Institute Name', 'Program Name',
        'Registration Number', 'Year of Enrollment', 'Year of Graduation', 'Current Company',
        'Current Location', 'Industry', 'Current Designation', 'Employment Start Date',
        '10th School', '10th Grade', '10th Grade Type', '10th Year',
        '12th School', '12th Grade', '12th Grade Type', '12th Year',
        'Bachelors Institute', 'Bachelors Degree', 'Bachelors Grade', 'Bachelors Grade Type', 'Bachelors Year',
        'Masters Institute', 'Masters Degree', 'Masters Grade', 'Masters Grade Type', 'Masters Year'
    };

    public static final List<String> MINIMAL_FIELDS_HEADERS = new List<String>{
        'Registration_Number', 'Email_ID', 'Institute_Name', 'Program_Name',
        'Year_Of_Joining', 'Year_Of_Completion'
    };

    public class ReportOption {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public Integer columnCount;
        @AuraEnabled public String filePrefix;
    }

    public class ReportChunk {
        @AuraEnabled public String headerLine;
        @AuraEnabled public String csv;
        @AuraEnabled public Id lastId;
        @AuraEnabled public Integer rowsInChunk;
        @AuraEnabled public Boolean done;
    }

    /**
     * @description Downloads the running user may take, in display order.
     * @return Report definitions for the dashboard buttons.
     */
    @AuraEnabled(cacheable=true)
    public static List<ReportOption> getReports() {
        List<ReportOption> options = new List<ReportOption>();
        options.add(buildOption(
            REPORT_ALL_FIELDS,
            'All Fields',
            'Every alumni record with all 43 columns — personal, contact, address, programme, '
                + 'employment and education. One row per alumni programme.'
        ));
        options.add(buildOption(
            REPORT_MINIMAL_FIELDS,
            'Minimal Fields',
            'Registration handover, six columns only: registration number, email, institute, '
                + 'programme, joining and completion year.'
        ));
        return options;
    }

    /**
     * @description Total rows the download will contain, within the running user's
     *              sharing. Used to drive the progress bar. A plain COUNT() is
     *              charged one query row however large the org is.
     * @param reportKey Report about to be downloaded.
     * @return Alumni ConstituentRole count.
     */
    @AuraEnabled
    public static Integer getRowCount(String reportKey) {
        resolveReportKey(reportKey);
        return alumniRoleCount();
    }

    /**
     * @description Returns the next slice of the report. The browser calls this
     *              repeatedly and assembles the file itself, so each slice is its
     *              own transaction with its own governor limits and the export has
     *              no size ceiling. Paging is by Id rather than OFFSET, which
     *              Salesforce caps at 2,000.
     * @param reportKey Report being downloaded.
     * @param afterId Last Id from the previous slice; null for the first.
     * @return The slice, plus the Id to resume from and whether this was the last.
     */
    @AuraEnabled
    public static ReportChunk getReportChunk(String reportKey, Id afterId) {
        String resolved = resolveReportKey(reportKey);
        Integer size = chunkSize(resolved);
        List<ConstituentRole> roles = afterId == null
            ? [
                SELECT Id, PersonId, Institution_Name__c, Program_Name__c, Registration_Number__c,
                       Year_of_Enrollment__c, Graduation_Year__c
                FROM ConstituentRole WHERE RoleType = 'Alumni'
                WITH USER_MODE
                ORDER BY Id LIMIT :size
            ]
            : [
                SELECT Id, PersonId, Institution_Name__c, Program_Name__c, Registration_Number__c,
                       Year_of_Enrollment__c, Graduation_Year__c
                FROM ConstituentRole WHERE RoleType = 'Alumni' AND Id > :afterId
                WITH USER_MODE
                ORDER BY Id LIMIT :size
            ];

        ReportChunk chunk = new ReportChunk();
        if (afterId == null) {
            chunk.headerLine = toCsvLine(headersFor(resolved));
        }
        List<String> rows = REPORT_MINIMAL_FIELDS.equals(resolved)
            ? minimalFieldsLines(roles)
            : allFieldsLines(roles);
        chunk.csv = String.join(rows, '\r\n');
        chunk.rowsInChunk = rows.size();
        chunk.lastId = roles.isEmpty() ? null : roles[roles.size() - 1].Id;
        chunk.done = roles.size() < size;
        return chunk;
    }

    /**
     * @description Number of alumni roles visible to the running user.
     * @return Alumni ConstituentRole count.
     */
    public static Integer alumniRoleCount() {
        return [SELECT COUNT() FROM ConstituentRole WHERE RoleType = 'Alumni' WITH USER_MODE];
    }

    /**
     * @description Roles read per slice. The wide report reads up to eight query
     *              rows per role (role, account, address, employment and its
     *              education rows), so it takes the smaller slice; both stay well
     *              inside the 50,000 query-row and 6MB heap limits of one
     *              synchronous transaction.
     * @param reportKey Report key.
     * @return Slice size.
     */
    @TestVisible
    private static Integer chunkSize(String reportKey) {
        return REPORT_MINIMAL_FIELDS.equals(reportKey) ? chunkMinimalFields : chunkAllFields;
    }

    @TestVisible
    private static List<String> minimalFieldsLines(List<ConstituentRole> roles) {
        List<String> rows = new List<String>();
        Map<Id, Id> accountByPerson = resolveAccounts(roles);
        Set<Id> accountIds = new Set<Id>(accountByPerson.values());
        Map<Id, Account> personById = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            for (Account person : [SELECT Id, PersonEmail FROM Account WHERE Id IN :accountIds WITH USER_MODE]) {
                personById.put(person.Id, person);
            }
        }
        for (ConstituentRole role : roles) {
            Account person = personById.get(accountByPerson.get(role.PersonId));
            rows.add(toCsvLine(new List<String>{
                role.Registration_Number__c,
                person == null ? null : person.PersonEmail,
                role.Institution_Name__c,
                role.Program_Name__c,
                role.Year_of_Enrollment__c,
                role.Graduation_Year__c
            }));
        }
        return rows;
    }

    @TestVisible
    private static List<String> allFieldsLines(List<ConstituentRole> roles) {
        List<String> rows = new List<String>();
        Map<Id, Id> accountByPerson = resolveAccounts(roles);
        Set<Id> personIds = new Set<Id>(accountByPerson.values());
        Map<Id, Account> personById = new Map<Id, Account>();
        Map<Id, Ken_Address__c> addressByPerson = new Map<Id, Ken_Address__c>();
        Map<Id, PersonEmployment> employmentByPerson = new Map<Id, PersonEmployment>();
        Map<Id, List<PersonEducation>> educationByPerson = new Map<Id, List<PersonEducation>>();

        if (!personIds.isEmpty()) {
            for (Account person : [
                SELECT Id, FirstName, LastName, PersonEmail, PersonMobilePhone, Phone,
                       PersonBirthdate, Nationality__c, PersonGenderIdentity, Blood_Group__c,
                       Linkedin_Profile_URL__c, Languages_Known__c, PersonMailingStreet,
                       PersonMailingCity, PersonMailingState, PersonMailingPostalCode,
                       PersonMailingCountry
                FROM Account WHERE Id IN :personIds
            WITH USER_MODE
            ]) {
                personById.put(person.Id, person);
            }
            for (Ken_Address__c address : [
                SELECT Person_Account__c, Street__c, City__c, State__c, Pincode__c, Country__c
                FROM Ken_Address__c
                WHERE Person_Account__c IN :personIds AND Address_Type__c = 'Mailing'
                WITH USER_MODE
                ORDER BY CreatedDate
            ]) {
                if (!addressByPerson.containsKey(address.Person_Account__c)) {
                    addressByPerson.put(address.Person_Account__c, address);
                }
            }
            for (PersonEmployment job : [
                SELECT AccountId, Company_Name__c, Designation__c, Location__c, Industry__c, StartDate
                FROM PersonEmployment
                WHERE AccountId IN :personIds AND Currently_Employed__c = true
                  AND (Is_Archived__c = false OR Is_Archived__c = null)
                WITH USER_MODE
                ORDER BY CreatedDate
            ]) {
                if (!employmentByPerson.containsKey(job.AccountId)) {
                    employmentByPerson.put(job.AccountId, job);
                }
            }
            for (PersonEducation education : [
                SELECT AccountId, Degree_Name__c, Institute_Name__c, Grade__c, Grade_Type__c,
                       Year_of_Completion__c
                FROM PersonEducation
                WHERE AccountId IN :personIds AND (Is_Archived__c = false OR Is_Archived__c = null)
                WITH USER_MODE
                ORDER BY CreatedDate
            ]) {
                if (!educationByPerson.containsKey(education.AccountId)) {
                    educationByPerson.put(education.AccountId, new List<PersonEducation>());
                }
                educationByPerson.get(education.AccountId).add(education);
            }
        }

        for (ConstituentRole role : roles) {
            Id accountId = accountByPerson.get(role.PersonId);
            List<PersonEducation> education = educationByPerson.containsKey(accountId)
                ? educationByPerson.get(accountId)
                : new List<PersonEducation>();
            rows.add(toCsvLine(allFieldsCells(
                role,
                personById.get(accountId),
                addressByPerson.get(accountId),
                employmentByPerson.get(accountId),
                slotEducation(education)
            )));
        }
        return rows;
    }

    private static List<String> allFieldsCells(
        ConstituentRole role,
        Account person,
        Ken_Address__c address,
        PersonEmployment job,
        List<PersonEducation> slots
    ) {
        List<String> cells = new List<String>{
            person == null ? null : person.PersonEmail,
            person == null ? null : person.FirstName,
            person == null ? null : person.LastName,
            person == null ? null : firstNotBlank(person.PersonMobilePhone, person.Phone),
            person == null ? null : formatDate(person.PersonBirthdate),
            person == null ? null : person.Nationality__c,
            person == null ? null : person.PersonGenderIdentity,
            person == null ? null : person.Blood_Group__c,
            person == null ? null : person.Linkedin_Profile_URL__c,
            person == null ? null : person.Languages_Known__c,
            firstNotBlank(address == null ? null : address.Street__c, person == null ? null : person.PersonMailingStreet),
            firstNotBlank(address == null ? null : address.City__c, person == null ? null : person.PersonMailingCity),
            firstNotBlank(address == null ? null : address.State__c, person == null ? null : person.PersonMailingState),
            firstNotBlank(address == null ? null : address.Pincode__c, person == null ? null : person.PersonMailingPostalCode),
            firstNotBlank(address == null ? null : address.Country__c, person == null ? null : person.PersonMailingCountry),
            role.Institution_Name__c,
            role.Program_Name__c,
            role.Registration_Number__c,
            role.Year_of_Enrollment__c,
            role.Graduation_Year__c,
            job == null ? null : job.Company_Name__c,
            job == null ? null : job.Location__c,
            job == null ? null : job.Industry__c,
            job == null ? null : job.Designation__c,
            job == null ? null : formatDate(job.StartDate)
        };
        cells.addAll(schoolCells(slots[SLOT_TENTH]));
        cells.addAll(schoolCells(slots[SLOT_TWELFTH]));
        cells.addAll(degreeCells(slots[SLOT_BACHELORS]));
        cells.addAll(degreeCells(slots[SLOT_MASTERS]));
        return cells;
    }

    private static List<String> schoolCells(PersonEducation row) {
        return new List<String>{
            row == null ? null : row.Institute_Name__c,
            row == null ? null : row.Grade__c,
            row == null ? null : row.Grade_Type__c,
            row == null ? null : row.Year_of_Completion__c
        };
    }

    private static List<String> degreeCells(PersonEducation row) {
        return new List<String>{
            row == null ? null : row.Institute_Name__c,
            row == null ? null : row.Degree_Name__c,
            row == null ? null : row.Grade__c,
            row == null ? null : row.Grade_Type__c,
            row == null ? null : row.Year_of_Completion__c
        };
    }

    /**
     * @description Places a person's education rows into the four fixed column
     *              blocks the report format defines.
     * @param rows The person's active education rows.
     * @return A four-entry list indexed by slot, entries null where unfilled.
     */
    @TestVisible
    private static List<PersonEducation> slotEducation(List<PersonEducation> rows) {
        List<PersonEducation> slots = new List<PersonEducation>();
        for (Integer i = 0; i < SLOT_COUNT; i++) {
            slots.add(null);
        }
        for (PersonEducation row : rows) {
            Integer slot = educationSlot(row.Degree_Name__c);
            PersonEducation held = slots[slot];
            if (held == null || completionYear(row) > completionYear(held)) {
                slots[slot] = row;
            }
        }
        return slots;
    }

    @TestVisible
    private static Integer educationSlot(String degreeName) {
        String key = degreeName == null ? '' : degreeName.toLowerCase();
        if (containsAny(key, TWELFTH_KEYWORDS)) return SLOT_TWELFTH;
        if (containsAny(key, TENTH_KEYWORDS)) return SLOT_TENTH;
        if (containsAny(key, MASTERS_KEYWORDS)) return SLOT_MASTERS;
        return SLOT_BACHELORS;
    }

    private static Boolean containsAny(String value, List<String> tokens) {
        for (String token : tokens) {
            if (value.contains(token)) return true;
        }
        return false;
    }

    private static Integer completionYear(PersonEducation row) {
        String value = row.Year_of_Completion__c;
        if (String.isBlank(value) || !Pattern.matches('^\\d{4}$', value.trim())) return -1;
        return Integer.valueOf(value.trim());
    }

    /**
     * @description Maps each role's PersonId onto the Person Account Id its
     *              personal, address, employment and education data hangs off.
     *              A role anchored to the Person Account's Contact resolves
     *              through Contact.AccountId.
     * @param roles Alumni roles being rendered.
     * @return Person Account Id keyed by the PersonId held on the role.
     */
    private static Map<Id, Id> resolveAccounts(List<ConstituentRole> roles) {
        Map<Id, Id> accountByPerson = new Map<Id, Id>();
        Set<Id> contactIds = new Set<Id>();
        for (ConstituentRole role : roles) {
            if (role.PersonId == null) continue;
            if (role.PersonId.getSObjectType() == Contact.SObjectType) {
                contactIds.add(role.PersonId);
            } else {
                accountByPerson.put(role.PersonId, role.PersonId);
            }
        }
        if (!contactIds.isEmpty()) {
            for (Contact person : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds WITH USER_MODE]) {
                if (person.AccountId != null) accountByPerson.put(person.Id, person.AccountId);
            }
        }
        return accountByPerson;
    }

    /**
     * @description Column headers for a report, in file order.
     * @param reportKey Report key.
     * @return Header labels.
     */
    public static List<String> headersFor(String reportKey) {
        return REPORT_MINIMAL_FIELDS.equals(reportKey) ? MINIMAL_FIELDS_HEADERS : ALL_FIELDS_HEADERS;
    }

    /**
     * @description File name prefix for a report.
     * @param reportKey Report key.
     * @return Prefix ending in a hyphen.
     */
    public static String filePrefix(String reportKey) {
        return REPORT_MINIMAL_FIELDS.equals(reportKey) ? PREFIX_MINIMAL_FIELDS : PREFIX_ALL_FIELDS;
    }
    /**
     * @description Validates a report key coming from the UI.
     * @param reportKey Key to validate.
     * @return The validated key.
     */
    public static String resolveReportKey(String reportKey) {
        if (REPORT_MINIMAL_FIELDS.equals(reportKey)) {
            return REPORT_MINIMAL_FIELDS;
        }
        if (REPORT_ALL_FIELDS.equals(reportKey)) {
            return REPORT_ALL_FIELDS;
        }
        throw error('Unknown report: ' + reportKey);
    }

    /**
     * @description Builds an AuraHandledException whose text survives. A bare
     *              AuraHandledException reports only "Script-thrown exception" to
     *              getMessage(), which hides the reason from logs and tests.
     * @param message Text to surface.
     * @return The exception to throw.
     */
    private static AuraHandledException error(String message) {
        AuraHandledException raised = new AuraHandledException(message);
        raised.setMessage(message);
        return raised;
    }

    /**
     * @description Joins one row of cells into a quoted CSV line.
     * @param cells Cell values in column order.
     * @return CSV line without a trailing newline.
     */
    public static String toCsvLine(List<String> cells) {
        List<String> quoted = new List<String>();
        for (String cell : cells) {
            String text = cell == null ? '' : cell;
            quoted.add('"' + text.replace('"', '""') + '"');
        }
        return String.join(quoted, ',');
    }

    /**
     * @description Formats a date the way the report format shows it (01-Jun-1995).
     * @param value Date to format.
     * @return Formatted date, or an empty string when the date is null.
     */
    public static String formatDate(Date value) {
        if (value == null) return '';
        return Datetime.newInstance(value.year(), value.month(), value.day()).format('dd-MMM-yyyy');
    }

    private static String firstNotBlank(String preferred, String fallback) {
        return String.isNotBlank(preferred) ? preferred : fallback;
    }

    private static ReportOption buildOption(String key, String label, String description) {
        ReportOption option = new ReportOption();
        option.key = key;
        option.label = label;
        option.description = description;
        option.columnCount = headersFor(key).size();
        option.filePrefix = filePrefix(key);
        return option;
    }
}