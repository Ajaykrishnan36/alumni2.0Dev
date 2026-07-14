/**
 * Alumni bulk-import batch — ONE ROW PER TRANSACTION.
 *
 * Lives in its own file because Salesforce Batchable<...> must be top-level
 * (cannot be an inner class). All chunk-storage + per-row helpers live on
 * KenAlumniBulkImportController; this class just orchestrates the iteration.
 *
 * - All of a row's fields are validated up front. If any field is invalid,
 *   the entire row is rejected and nothing is inserted.
 * - Person Account + ConstituentRole + Ken_Alumni_CRM__c are provisioned via
 *   KenAlumniOnboardingService inside a Savepoint — never a partial row.
 * - A failure in one row never blocks the others.
 */
public without sharing class KenAlumniBulkImportBatch implements Database.Batchable<String>, Database.Stateful {
    private final String processName;
    private final String importSessionKey;
    private final String dataSource;

    public KenAlumniBulkImportBatch(String processName, String importSessionKey, String dataSource) {
        this.processName = String.isBlank(processName) ? KenAlumniBulkImportController.PROCESS_NAME : processName;
        this.importSessionKey = importSessionKey;
        this.dataSource = String.isBlank(dataSource) ? KenAlumniBulkImportController.DEFAULT_DATA_SOURCE : dataSource;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> rows = new List<String>();
        for (Id versionId : KenAlumniBulkImportController.getChunkVersionIds(processName, importSessionKey)) {
            String chunkJson = KenAlumniBulkImportController.getChunkJson(versionId);
            if (String.isBlank(chunkJson)) continue;
            for (Object row : (List<Object>) JSON.deserializeUntyped(chunkJson)) {
                if (row instanceof Map<String, Object>) rows.add(JSON.serialize(row));
            }
        }
        return rows;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {
        Id jobId = bc == null ? null : bc.getJobId();
        if (scope == null || scope.isEmpty()) return;
        String resolvedDataSource = KenAlumniBulkImportController.resolveDataSource(dataSource);
        Map<String, String> specializationValues = KenAlumniBulkImportController.picklistValues(Ken_Alumni_CRM__c.Specialization__c.getDescribe());
        Map<String, String> gradeTypeValues = KenAlumniBulkImportController.picklistValues(PersonEducation.Grade_Type__c.getDescribe());
        Map<String, String> statusValues = KenAlumniBulkImportController.picklistValues(ConstituentRole.Registration_Status__c.getDescribe());

        for (String rowJson : scope) {
            processOneRow(rowJson, jobId, resolvedDataSource, specializationValues, gradeTypeValues, statusValues);
        }
    }

    public void finish(Database.BatchableContext bc) {
        KenAlumniBulkImportController.deleteChunks(processName, importSessionKey);
    }

    private void processOneRow(
        String rowJson, Id jobId, String resolvedDataSource,
        Map<String, String> specializationValues, Map<String, String> gradeTypeValues,
        Map<String, String> statusValues
    ) {
        Map<String, Object> row;
        try {
            row = (Map<String, Object>) JSON.deserializeUntyped(rowJson);
        } catch (Exception ex) {
            writeLog(KenLogService.TYPE_ERROR, 'A row could not be read and was skipped.', jobId);
            return;
        }

        String rowNo = KenAlumniBulkImportController.getRowNumber(row);

        List<String> fieldErrors = validateRow(row, specializationValues, gradeTypeValues, statusValues);
        String programRaw = KenAlumniBulkImportController.getRowValue(row, 'Program');
        KenAlumniBulkImportController.ProgramResolution programRes = KenAlumniBulkImportController.resolveProgram(programRaw);
        if (programRes.provided && !programRes.resolved) {
            fieldErrors.add('Program "' + programRaw + '" did not match any program record (provide a valid program name or program Id).');
        }
        if (!fieldErrors.isEmpty()) {
            List<Ken_Logs__c> logs = new List<Ken_Logs__c>();
            for (String fieldError : fieldErrors) {
                logs.add(buildLog(KenLogService.TYPE_ERROR, 'Row ' + rowNo + ': ' + fieldError, jobId));
            }
            KenLogService.insertLogs(logs);
            return;
        }

        String email = KenAlumniBulkImportController.getRowValue(row, 'Email');
        Boolean preExisting = isExistingAlumni(email);

        Savepoint sp = Database.setSavepoint();
        try {
            KenAlumniOnboardingService.provisionOnLeadVerification(new List<Lead>{ buildLead(row) });
            enrichCrm(email, row, resolvedDataSource, programRes.programId, specializationValues);
            Account person = findPerson(email);
            if (person != null) {
                enrichProfile(person, row, gradeTypeValues);
                applyRoleStatus(person.Id, row, programRes.programId, statusValues);
            }
        } catch (Exception ex) {
            Database.rollback(sp);
            KenLogService.log(
                KenLogService.CATEGORY_IMPORT, KenLogService.TYPE_ERROR, processName, KenAlumniBulkImportController.SOURCE_NAME,
                jobId == null ? null : String.valueOf(jobId),
                'Row ' + rowNo + ': could not be imported and was skipped — ' + ex.getMessage(), ex.getStackTraceString()
            );
            return;
        }

        if (preExisting) {
            writeLog(KenLogService.TYPE_WARNING,
                'Row ' + rowNo + ': Possible duplicate — an alumni with email "' + email + '" already existed and was updated instead of creating a new record.', jobId);
        }
    }

    private List<String> validateRow(
        Map<String, Object> row,
        Map<String, String> specializationValues,
        Map<String, String> gradeTypeValues,
        Map<String, String> statusValues
    ) {
        List<String> errors = new List<String>();
        String email = KenAlumniBulkImportController.getRowValue(row, 'Email');
        if (String.isBlank(email)) {
            errors.add('Email is required.');
        } else if (!KenAlumniBulkImportController.isValidEmail(email)) {
            errors.add('Email "' + email + '" is not a valid email address.');
        }
        String regNo = KenAlumniBulkImportController.getRowValue(row, 'Registration Number');
        if (String.isNotBlank(regNo) && regNo.length() > 18) {
            errors.add('Registration Number "' + regNo + '" exceeds the 18 character limit.');
        }
        String specialization = KenAlumniBulkImportController.getRowValue(row, 'Specialization');
        if (String.isNotBlank(specialization) && !specializationValues.containsKey(KenAlumniBulkImportController.normalizeKey(specialization))) {
            errors.add('Specialization "' + specialization + '" is not a valid option.');
        }
        String status = KenAlumniBulkImportController.getRowValue(row, 'Status');
        if (String.isNotBlank(status) && !statusValues.containsKey(KenAlumniBulkImportController.normalizeKey(status))) {
            errors.add('Status "' + status + '" is not a valid option (Unregistered, Verified, Registered, Initial Login Done).');
        }
        validateDate(errors, row, 'Date of Birth');
        validateDate(errors, row, 'Employment Start Date');
        for (EduLevel lvl : eduLevels()) {
            String gradeType = KenAlumniBulkImportController.getRowValue(row, lvl.gradeTypeCol);
            if (String.isNotBlank(gradeType) && !gradeTypeValues.containsKey(KenAlumniBulkImportController.normalizeKey(gradeType))) {
                errors.add(lvl.gradeTypeCol + ' "' + gradeType + '" is not a valid option (Percentage, CGPA, GPA, Letter Grade).');
            }
        }
        return errors;
    }

    private void validateDate(List<String> errors, Map<String, Object> row, String column) {
        String raw = KenAlumniBulkImportController.getRowValue(row, column);
        if (String.isNotBlank(raw) && KenAlumniBulkImportController.parseDate(raw) == null) {
            errors.add(column + ' "' + raw + '" is not a valid date (use YYYY-MM-DD).');
        }
    }

    private Lead buildLead(Map<String, Object> row) {
        return new Lead(
            FirstName = KenAlumniBulkImportController.getRowValue(row, 'First Name'),
            LastName = KenAlumniBulkImportController.defaultString(KenAlumniBulkImportController.getRowValue(row, 'Last Name'), 'Alumni'),
            Email = KenAlumniBulkImportController.getRowValue(row, 'Email'),
            Phone = KenAlumniBulkImportController.getRowValue(row, 'Phone'),
            LeadSource = 'Bulk Import',
            Registration_Number__c = KenAlumniBulkImportController.getRowValue(row, 'Registration Number'),
            Year_of_Graduation__c = KenAlumniBulkImportController.getRowValue(row, 'Year of Graduation')
        );
    }

    private void enrichCrm(
        String email, Map<String, Object> row, String resolvedDataSource,
        String resolvedProgramId, Map<String, String> specializationValues
    ) {
        List<Ken_Alumni_CRM__c> crms = [
            SELECT Id, Data_Source__c FROM Ken_Alumni_CRM__c
            WHERE Person_Account__r.PersonEmail = :email
            ORDER BY CreatedDate LIMIT 1
        ];
        if (crms.isEmpty()) return;
        Ken_Alumni_CRM__c crm = crms[0];
        crm.Current_Company__c = KenAlumniBulkImportController.getRowValue(row, 'Current Company');
        crm.Current_Location__c = KenAlumniBulkImportController.getRowValue(row, 'Current Location');
        crm.Industry__c = KenAlumniBulkImportController.getRowValue(row, 'Industry');
        crm.Registration_Number__c = KenAlumniBulkImportController.getRowValue(row, 'Registration Number');
        crm.Year_of_Graduation__c = KenAlumniBulkImportController.getRowValue(row, 'Year of Graduation');
        if (String.isBlank(crm.Data_Source__c)) crm.Data_Source__c = resolvedDataSource;
        // Program is stored as the resolved LearningProgramPlan Id (Alumni 360 resolves it to the name).
        if (String.isNotBlank(resolvedProgramId)) crm.Program__c = resolvedProgramId;
        String specialization = KenAlumniBulkImportController.getRowValue(row, 'Specialization');
        if (String.isNotBlank(specialization)) crm.Specialization__c = specializationValues.get(KenAlumniBulkImportController.normalizeKey(specialization));
        update crm;
    }

    private Account findPerson(String email) {
        if (String.isBlank(email)) return null;
        List<Account> accounts = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true AND PersonEmail = :email
            ORDER BY CreatedDate
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    private void enrichProfile(Account person, Map<String, Object> row, Map<String, String> gradeTypeValues) {
        enrichPersonAccount(person.Id, row);
        upsertEducation(person.Id, row, gradeTypeValues);
        upsertCurrentEmployment(person, row);
    }

    private void applyRoleStatus(Id accountId, Map<String, Object> row, String programId, Map<String, String> statusValues) {
        String statusRaw = KenAlumniBulkImportController.getRowValue(row, 'Status');
        if (String.isBlank(statusRaw)) return;
        String status = statusValues.get(KenAlumniBulkImportController.normalizeKey(statusRaw));
        if (String.isBlank(status)) return; // already validated up front; defensive

        List<ConstituentRole> roles = [
            SELECT Id, Registration_Number__c, Program_Plan__c, Registration_Status__c
            FROM ConstituentRole
            WHERE PersonId = :accountId AND RoleType = 'Alumni'
            ORDER BY CreatedDate DESC
        ];
        if (roles.isEmpty()) return;

        ConstituentRole target = matchRole(roles, programId, KenAlumniBulkImportController.getRowValue(row, 'Registration Number'));
        if (target != null && target.Registration_Status__c != status) {
            update new ConstituentRole(Id = target.Id, Registration_Status__c = status);
        }
    }

    private ConstituentRole matchRole(List<ConstituentRole> roles, String programId, String regNo) {
        Id programPlanId = null;
        if (String.isNotBlank(programId)) {
            try { programPlanId = Id.valueOf(programId); } catch (Exception e) { programPlanId = null; }
        }
        if (programPlanId != null) {
            for (ConstituentRole cr : roles) {
                if (cr.Program_Plan__c == programPlanId) return cr;
            }
        }
        if (String.isNotBlank(regNo)) {
            for (ConstituentRole cr : roles) {
                if (cr.Registration_Number__c == regNo) return cr;
            }
        }
        return roles[0];
    }

    private void enrichPersonAccount(Id accountId, Map<String, Object> row) {
        Account acc = new Account(Id = accountId);
        Boolean dirty = false;
        dirty = setIfPresent(row, 'LinkedIn URL', acc, Account.Linkedin_Profile_URL__c) || dirty;
        dirty = setIfPresent(row, 'Languages Known', acc, Account.Languages_Known__c) || dirty;
        dirty = setIfPresent(row, 'Address Street', acc, Account.PersonMailingStreet) || dirty;
        dirty = setIfPresent(row, 'Address City', acc, Account.PersonMailingCity) || dirty;
        dirty = setIfPresent(row, 'Address State', acc, Account.PersonMailingState) || dirty;
        dirty = setIfPresent(row, 'Address Postal Code', acc, Account.PersonMailingPostalCode) || dirty;
        dirty = setIfPresent(row, 'Address Country', acc, Account.PersonMailingCountry) || dirty;
        Date dob = KenAlumniBulkImportController.parseDate(KenAlumniBulkImportController.getRowValue(row, 'Date of Birth'));
        if (dob != null) {
            acc.PersonBirthdate = dob;
            dirty = true;
        }
        if (dirty) update acc;
    }

    private void upsertEducation(Id accountId, Map<String, Object> row, Map<String, String> gradeTypeValues) {
        Map<String, PersonEducation> existingByDegree = new Map<String, PersonEducation>();
        for (PersonEducation pe : [
            SELECT Id, Degree_Name__c
            FROM PersonEducation
            WHERE AccountId = :accountId AND (Is_Archived__c = false OR Is_Archived__c = null)
        ]) {
            if (String.isNotBlank(pe.Degree_Name__c)) {
                existingByDegree.put(KenAlumniBulkImportController.normalizeKey(pe.Degree_Name__c), pe);
            }
        }

        List<PersonEducation> toInsert = new List<PersonEducation>();
        List<PersonEducation> toUpdate = new List<PersonEducation>();
        for (EduLevel lvl : eduLevels()) {
            String institute = KenAlumniBulkImportController.getRowValue(row, lvl.instituteCol);
            String grade = KenAlumniBulkImportController.getRowValue(row, lvl.gradeCol);
            String year = KenAlumniBulkImportController.getRowValue(row, lvl.yearCol);
            String gradeTypeRaw = KenAlumniBulkImportController.getRowValue(row, lvl.gradeTypeCol);
            String providedDegree = lvl.degreeCol == null ? null : KenAlumniBulkImportController.getRowValue(row, lvl.degreeCol);

            if (institute == null && grade == null && year == null && gradeTypeRaw == null && providedDegree == null) {
                continue;
            }

            String degree = KenAlumniBulkImportController.defaultString(providedDegree, lvl.fixedDegree);
            String gradeType = gradeTypeRaw == null ? null : gradeTypeValues.get(KenAlumniBulkImportController.normalizeKey(gradeTypeRaw));

            PersonEducation existing = existingByDegree.get(KenAlumniBulkImportController.normalizeKey(degree));
            PersonEducation pe = existing == null
                ? new PersonEducation(AccountId = accountId)
                : new PersonEducation(Id = existing.Id);
            pe.Name = degree.length() > 80 ? degree.substring(0, 80) : degree;
            pe.Degree_Name__c = degree;
            pe.Institute_Name__c = institute;
            pe.Grade__c = grade;
            pe.Grade_Type__c = gradeType;
            pe.Year_of_Completion__c = year;
            pe.Is_Archived__c = false;
            if (existing == null) {
                toInsert.add(pe);
            } else {
                toUpdate.add(pe);
            }
        }
        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    private void upsertCurrentEmployment(Account person, Map<String, Object> row) {
        String company = KenAlumniBulkImportController.getRowValue(row, 'Current Company');
        String designation = KenAlumniBulkImportController.getRowValue(row, 'Current Designation');
        String location = KenAlumniBulkImportController.getRowValue(row, 'Current Location');
        Date startDate = KenAlumniBulkImportController.parseDate(KenAlumniBulkImportController.getRowValue(row, 'Employment Start Date'));

        if (company == null && designation == null) return;

        List<PersonEmployment> existingRows = [
            SELECT Id
            FROM PersonEmployment
            WHERE AccountId = :person.Id AND Currently_Employed__c = true
              AND (Is_Archived__c = false OR Is_Archived__c = null)
            ORDER BY CreatedDate
            LIMIT 1
        ];

        PersonEmployment emp = existingRows.isEmpty()
            ? new PersonEmployment(AccountId = person.Id, RelatedPersonId = person.PersonContactId)
            : new PersonEmployment(Id = existingRows[0].Id);
        String employerName = KenAlumniBulkImportController.defaultString(company, 'Employer');
        emp.Name = employerName.length() > 80 ? employerName.substring(0, 80) : employerName;
        emp.Company_Name__c = company;
        emp.Designation__c = designation;
        emp.Location__c = location;
        emp.StartDate = startDate;
        emp.Currently_Employed__c = true;
        emp.EndDate = null;
        emp.Is_Archived__c = false;
        if (existingRows.isEmpty()) {
            insert emp;
        } else {
            update emp;
        }
    }

    private Boolean setIfPresent(Map<String, Object> row, String column, SObject record, Schema.SObjectField field) {
        String value = KenAlumniBulkImportController.getRowValue(row, column);
        if (value == null) return false;
        record.put(field, value);
        return true;
    }

    private class EduLevel {
        String instituteCol;
        String degreeCol;
        String fixedDegree;
        String gradeCol;
        String gradeTypeCol;
        String yearCol;
        EduLevel(String instituteCol, String degreeCol, String fixedDegree, String gradeCol, String gradeTypeCol, String yearCol) {
            this.instituteCol = instituteCol;
            this.degreeCol = degreeCol;
            this.fixedDegree = fixedDegree;
            this.gradeCol = gradeCol;
            this.gradeTypeCol = gradeTypeCol;
            this.yearCol = yearCol;
        }
    }

    private static List<EduLevel> eduLevels() {
        return new List<EduLevel>{
            new EduLevel('10th School', null, '10th', '10th Grade', '10th Grade Type', '10th Year'),
            new EduLevel('12th School', null, '12th', '12th Grade', '12th Grade Type', '12th Year'),
            new EduLevel('Bachelors Institute', 'Bachelors Degree', 'Bachelors', 'Bachelors Grade', 'Bachelors Grade Type', 'Bachelors Year'),
            new EduLevel('Masters Institute', 'Masters Degree', 'Masters', 'Masters Grade', 'Masters Grade Type', 'Masters Year')
        };
    }

    private Boolean isExistingAlumni(String email) {
        if (String.isBlank(email)) return false;
        return [SELECT COUNT() FROM Account WHERE IsPersonAccount = true AND PersonEmail = :email] > 0;
    }

    private Ken_Logs__c buildLog(String logType, String message, Id jobId) {
        return KenLogService.build(
            KenLogService.CATEGORY_IMPORT, logType, processName, KenAlumniBulkImportController.SOURCE_NAME,
            jobId == null ? null : String.valueOf(jobId), message, null
        );
    }

    private void writeLog(String logType, String message, Id jobId) {
        KenLogService.insertLogs(new List<Ken_Logs__c>{ buildLog(logType, message, jobId) });
    }
}