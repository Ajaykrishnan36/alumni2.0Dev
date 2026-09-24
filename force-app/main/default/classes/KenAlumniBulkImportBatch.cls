/**
 * Alumni bulk-import batch — ONE CHUNK FILE PER JOB, BULKIFIED PIPELINE.
 *
 * Lives in its own file because Salesforce Batchable<...> must be top-level
 * (cannot be an inner class). All chunk-storage + row helpers live on
 * KenAlumniBulkImportController; this class orchestrates the import.
 *
 * - start() loads ONLY the lowest-numbered staged chunk file, so heap stays
 *   flat no matter how many rows the whole import has (loading every chunk in
 *   start() blew the 12MB async heap on a 183k-row import). finish() deletes
 *   the processed file, folds this job's counts into the session progress
 *   marker, and chains a new job while chunk files remain.
 * - execute() processes the whole scope set-based: one bulk provisioning call
 *   and one query + partial-success DML per related object for all rows
 *   together. The previous one-row-per-transaction pipeline took ~1h45m for
 *   10k rows; this design imports the same rows in minutes.
 * - All of a row's fields are validated up front. If any field is invalid,
 *   the entire row is rejected and nothing is inserted.
 * - Rows repeating an email within one chunk are provisioned in sequential
 *   passes, so each repeat sees the account/roles the previous row created
 *   (multiple programmes for the same person import as multiple roles).
 * - Provisioning failures are isolated by savepoint split-retry: the failing
 *   subset is halved until the bad row is found, so one bad row never blocks
 *   the others. Enrichment writes use partial-success DML with per-row logs.
 */
public without sharing class KenAlumniBulkImportBatch implements Database.Batchable<String>, Database.Stateful {
    private static final Integer MAX_DUPLICATE_PASSES = 5;
    private static final Integer QUERY_GUARD = 150;
    private static final Integer DML_GUARD = 120;
    @TestVisible private static Integer cpuGuardMs = 40000;

    private final String processName;
    private final String importSessionKey;
    private final String dataSource;
    private Id currentChunkDocumentId;
    private Integer chunkRowsAttempted = 0;
    private Integer chunkRowsFailed = 0;
    private transient List<Ken_Logs__c> pendingLogs;

    public KenAlumniBulkImportBatch(String processName, String importSessionKey, String dataSource) {
        this.processName = String.isBlank(processName) ? KenAlumniBulkImportController.PROCESS_NAME : processName;
        this.importSessionKey = importSessionKey;
        this.dataSource = String.isBlank(dataSource) ? KenAlumniBulkImportController.DEFAULT_DATA_SOURCE : dataSource;
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        List<String> rows = new List<String>();
        KenAlumniBulkImportController.ChunkPayload chunk = KenAlumniBulkImportController.getFirstChunk(processName, importSessionKey);
        if (chunk == null) return rows;
        currentChunkDocumentId = chunk.documentId;
        if (String.isBlank(chunk.body)) return rows;
        try {
            for (Object row : (List<Object>) JSON.deserializeUntyped(chunk.body)) {
                if (row instanceof Map<String, Object>) rows.add(JSON.serialize(row));
            }
        } catch (Exception ex) {
            rows.clear();
            writeLog(KenLogService.TYPE_ERROR, 'A staged chunk could not be read and was skipped.');
        }
        return rows;
    }

    /**
     * An exception escaping the pipeline used to take the whole scope down
     * SILENTLY: Database.Stateful members roll back with the transaction, so the
     * row counters returned to their pre-scope values and finish() folded
     * 0 attempted / 0 failed into the session marker and stamped it Completed
     * over a chunk that imported nothing. Catching it here keeps the counters
     * and the row logs gathered before the throw, charges the scope as failed,
     * and names the real error instead of leaving a clean-looking success.
     */
    public void execute(Database.BatchableContext bc, List<String> scope) {
        if (scope == null || scope.isEmpty()) return;
        Integer attemptedBefore = chunkRowsAttempted;
        Integer failedBefore = chunkRowsFailed;
        try {
            processScope(scope);
        } catch (Exception ex) {
            chunkRowsAttempted = attemptedBefore + scope.size();
            chunkRowsFailed = failedBefore + scope.size();
            if (pendingLogs == null) pendingLogs = new List<Ken_Logs__c>();
            pendingLogs.add(KenLogService.build(
                KenLogService.CATEGORY_IMPORT, KenLogService.TYPE_ERROR, processName,
                KenAlumniBulkImportController.SOURCE_NAME, importSessionKey,
                'This batch stopped on an unexpected error, so its ' + scope.size() +
                ' row(s) are counted as failed and may not have been imported — ' + ex.getMessage() +
                '. Re-import these rows and check the row logs above for any that did land.',
                ex.getStackTraceString()
            ));
            try {
                KenLogService.insertLogs(pendingLogs);
            } catch (Exception logsFailed) {
                writeLog(KenLogService.TYPE_ERROR, 'Import batch stopped on an unexpected error: ' + ex.getMessage());
            }
        }
    }

    private void processScope(List<String> scope) {
        KenInstitutePopulationService.skipFanout = true;
        pendingLogs = new List<Ken_Logs__c>();
        String resolvedDataSource = KenAlumniBulkImportController.resolveDataSource(dataSource);
        Map<String, Map<String, String>> picklists = new Map<String, Map<String, String>>{
            'Grade Type' => KenAlumniBulkImportController.picklistValues(PersonEducation.Grade_Type__c.getDescribe()),
            'Status' => KenAlumniBulkImportController.picklistValues(ConstituentRole.Registration_Status__c.getDescribe()),
            'Nationality' => KenAlumniBulkImportController.picklistValues(Account.Nationality__c.getDescribe()),
            'Gender' => KenAlumniBulkImportController.picklistValues(Account.PersonGenderIdentity.getDescribe()),
            'Blood Group' => KenAlumniBulkImportController.picklistValues(Account.Blood_Group__c.getDescribe())
        };

        List<RowWork> validRows = parseAndValidate(scope, picklists);
        assignProgramResolutions(validRows, resolvedDataSource);
        validRows = rejectUnresolvedPrograms(validRows);
        Set<String> preExistingEmails = fetchExistingEmails(validRows);
        List<List<RowWork>> passes = buildDuplicateEmailPasses(validRows);
        for (Integer p = 0; p < passes.size(); p++) {
            if (p > 0 && Limits.getCpuTime() > cpuGuardMs) {
                restageRemainingPasses(passes, p);
                break;
            }
            processPass(passes[p], resolvedDataSource, picklists, preExistingEmails);
        }
        if (!pendingLogs.isEmpty()) KenLogService.insertLogs(pendingLogs);
    }

    /**
     * Deletes the chunk file this job processed, folds the job's row counts into
     * the session progress marker (the last chunk flips it to Completed), and
     * chains a new job for the next chunk file. Chaining is skipped in tests —
     * Database.executeBatch cannot be chained from finish() in a test context;
     * tests drain remaining chunks by invoking the batch contract directly.
     */
    public void finish(Database.BatchableContext bc) {
        logFailedTransactions(bc);
        KenAlumniBulkImportController.deleteChunkDocument(currentChunkDocumentId);
        Boolean hasMoreChunks = !KenAlumniBulkImportController.getChunkVersionIds(processName, importSessionKey).isEmpty();
        KenAlumniBulkImportController.updateSessionProgress(importSessionKey, chunkRowsAttempted, chunkRowsFailed, !hasMoreChunks);
        if (hasMoreChunks && !Test.isRunningTest()) {
            Database.executeBatch(
                new KenAlumniBulkImportBatch(processName, importSessionKey, dataSource),
                KenAlumniBulkImportController.importBatchScope()
            );
        } else if (!hasMoreChunks && !Test.isRunningTest()) {
            KenInstitutePopulationBatch.runForAll();
        }
    }

    /**
     * Surfaces transactions that died on an untrappable limit (CPU, heap):
     * their rows vanish without row-level logs, so without this marker entry a
     * partially-imported chunk would look successful. Lower
     * Ken_Alm_Org_Parameters__c.Import_Batch_Scope__c when this appears.
     */
    private void logFailedTransactions(Database.BatchableContext bc) {
        if (bc == null || bc.getJobId() == null) return;
        List<AsyncApexJob> jobs = [
            SELECT NumberOfErrors, ExtendedStatus FROM AsyncApexJob WHERE Id = :bc.getJobId() LIMIT 1
        ];
        if (jobs.isEmpty() || jobs[0].NumberOfErrors == null || jobs[0].NumberOfErrors == 0) return;
        writeLog(KenLogService.TYPE_ERROR,
            jobs[0].NumberOfErrors + ' transaction(s) in this import job failed before completing (' +
            (String.isBlank(jobs[0].ExtendedStatus) ? 'no details' : jobs[0].ExtendedStatus) +
            '); their rows were not imported. Lower Import Batch Scope in Alumni Org Parameters and re-import the missing rows.');
    }

    /**
     * Defers the not-yet-processed duplicate-email passes to a freshly staged
     * chunk file when the transaction is close to the CPU limit, so the rows
     * import in a later job instead of risking an untrappable limit exception.
     * The rows are subtracted from this job's attempted count because the job
     * that processes the restaged chunk will count them again.
     */
    private void restageRemainingPasses(List<List<RowWork>> passes, Integer fromPass) {
        List<Map<String, Object>> deferredRows = new List<Map<String, Object>>();
        for (Integer p = fromPass; p < passes.size(); p++) {
            for (RowWork w : passes[p]) {
                deferredRows.add(w.row);
            }
        }
        if (deferredRows.isEmpty()) return;
        chunkRowsAttempted -= deferredRows.size();
        Integer restageIndex = 900000 + Integer.valueOf(Math.mod(Datetime.now().getTime(), 90000));
        KenAlumniBulkImportController.saveChunk(processName, importSessionKey, restageIndex, JSON.serialize(deferredRows));
        pendingLogs.add(buildLog(KenLogService.TYPE_INFO,
            'Deferred ' + deferredRows.size() + ' row(s) with repeated emails to a new staged chunk to stay within CPU limits; they will import in a later job.'));
    }

    /**
     * Parses and field-validates every scope row. Rows that cannot be read or
     * fail validation are counted, logged, and excluded from the pipeline.
     */
    private List<RowWork> parseAndValidate(List<String> scope, Map<String, Map<String, String>> picklists) {
        List<RowWork> out = new List<RowWork>();
        for (String rowJson : scope) {
            chunkRowsAttempted++;
            Map<String, Object> row;
            try {
                row = (Map<String, Object>) JSON.deserializeUntyped(rowJson);
            } catch (Exception ex) {
                chunkRowsFailed++;
                pendingLogs.add(buildLog(KenLogService.TYPE_ERROR, 'A row could not be read and was skipped.'));
                continue;
            }
            RowWork work = new RowWork();
            work.row = row;
            work.rowNo = KenAlumniBulkImportController.getRowNumber(row);
            work.email = KenAlumniBulkImportController.getRowValue(row, 'Email');
            List<String> fieldErrors = validateRow(row, picklists);
            if (!fieldErrors.isEmpty()) {
                chunkRowsFailed++;
                for (String fieldError : fieldErrors) {
                    pendingLogs.add(buildLog(KenLogService.TYPE_ERROR, 'Row ' + work.rowNo + ': ' + fieldError));
                }
                continue;
            }
            out.add(work);
        }
        return out;
    }

    /**
     * Resolves every distinct Program value for the scope in one bulk call and
     * builds each row's Lead from the resolution result.
     */
    private void assignProgramResolutions(List<RowWork> rows, String resolvedDataSource) {
        Set<String> rawValues = new Set<String>();
        for (RowWork w : rows) {
            String raw = KenAlumniBulkImportController.getRowValue(w.row, 'Program');
            if (String.isNotBlank(raw)) rawValues.add(raw);
        }
        Map<String, KenAlumniBulkImportController.ProgramResolution> byRaw = KenAlumniBulkImportController.resolvePrograms(rawValues);
        for (RowWork w : rows) {
            String raw = KenAlumniBulkImportController.getRowValue(w.row, 'Program');
            w.programRes = String.isNotBlank(raw) && byRaw.containsKey(raw)
                ? byRaw.get(raw)
                : new KenAlumniBulkImportController.ProgramResolution();
            w.lead = buildLead(w.row, w.programRes.programId, resolvedDataSource);
        }
    }

    /**
     * Program is required to resolve: a provided value that matches no
     * LearningProgramPlan (by Id, plan name, or unambiguous programme name)
     * rejects the whole row — the role's program lookup and the derived
     * institute both depend on it.
     */
    private List<RowWork> rejectUnresolvedPrograms(List<RowWork> rows) {
        List<RowWork> out = new List<RowWork>();
        for (RowWork w : rows) {
            if (w.programRes.provided && !w.programRes.resolved) {
                failRow(w, 'Program "' + w.programRes.storedValue + '" does not match any program in this org (use an existing program name or Id); the row was skipped.', null);
                continue;
            }
            out.add(w);
        }
        return out;
    }

    private Set<String> fetchExistingEmails(List<RowWork> rows) {
        Set<String> emails = new Set<String>();
        for (RowWork w : rows) {
            if (String.isNotBlank(w.email)) emails.add(w.email);
        }
        Set<String> existing = new Set<String>();
        if (emails.isEmpty()) return existing;
        for (Account a : [
            SELECT PersonEmail FROM Account
            WHERE IsPersonAccount = true AND PersonEmail IN :emails
        WITH SECURITY_ENFORCED
        ]) {
            if (String.isNotBlank(a.PersonEmail)) existing.add(a.PersonEmail.toLowerCase());
        }
        return existing;
    }

    /**
     * Groups the valid rows into sequential passes by email occurrence, so a
     * file listing the same person for several programmes provisions each row
     * against the account/roles the previous pass committed. Rows repeating an
     * email beyond MAX_DUPLICATE_PASSES are rejected with a clear message
     * instead of risking transaction limits.
     */
    private List<List<RowWork>> buildDuplicateEmailPasses(List<RowWork> rows) {
        Map<String, Integer> occurrenceByEmail = new Map<String, Integer>();
        List<List<RowWork>> passes = new List<List<RowWork>>();
        for (RowWork w : rows) {
            String key = w.emailKey();
            Integer ordinal = occurrenceByEmail.containsKey(key) ? occurrenceByEmail.get(key) : 0;
            occurrenceByEmail.put(key, ordinal + 1);
            if (ordinal >= MAX_DUPLICATE_PASSES) {
                failRow(w, 'was skipped — the email "' + w.email + '" appears more than ' +
                    MAX_DUPLICATE_PASSES + ' times in one uploaded file; split the repeats across separate files.', null);
                continue;
            }
            while (passes.size() <= ordinal) passes.add(new List<RowWork>());
            passes[ordinal].add(w);
        }
        return passes;
    }

    /**
     * Runs one full import pass: bulk provisioning, then set-based enrichment
     * of CRM, profile, address, education, employment and role status. Emails
     * that existed before the pass produce the duplicate warning the old
     * per-row pipeline logged.
     */
    private void processPass(
        List<RowWork> rows, String resolvedDataSource,
        Map<String, Map<String, String>> picklists, Set<String> preExistingEmails
    ) {
        for (RowWork w : rows) {
            w.preExisting = preExistingEmails.contains(w.emailKey());
        }
        provisionRows(rows);
        List<RowWork> live = new List<RowWork>();
        for (RowWork w : rows) {
            if (!w.failed) {
                preExistingEmails.add(w.emailKey());
                live.add(w);
            }
        }
        if (!live.isEmpty()) {
            enrichCrms(live, resolvedDataSource);
            Map<String, Account> personByEmail = findPersons(live);
            enrichPersonAccounts(live, personByEmail, picklists);
            upsertMailingAddresses(live, personByEmail);
            upsertEducations(live, personByEmail, picklists.get('Grade Type'));
            upsertCurrentEmployments(live, personByEmail);
            applyRoleStatuses(live, personByEmail, picklists.get('Status'));
        }
        for (RowWork w : rows) {
            if (!w.failed && w.preExisting) {
                pendingLogs.add(buildLog(KenLogService.TYPE_WARNING,
                    'Row ' + w.rowNo + ': Possible duplicate — an alumni with email "' + w.email + '" already existed and was updated instead of creating a new record.'));
            }
        }
    }

    /**
     * Provisions Person Account + ConstituentRole + Ken_Alumni_CRM__c for the
     * given rows through KenAlumniOnboardingService in ONE bulk call. If the
     * call throws, the work rolls back to a savepoint and each half is retried,
     * halving until the failing row is isolated — one bad row never blocks the
     * others. A governor guard fails the remaining rows instead of letting a
     * pathological chunk exhaust transaction limits.
     */
    private void provisionRows(List<RowWork> rows) {
        if (rows.isEmpty()) return;
        List<Lead> leads = new List<Lead>();
        for (RowWork w : rows) leads.add(w.lead);
        // enrichProfile writes the real education rows from the CSV's per-level columns,
        // so suppress the provisioning seed rather than adding a blank-degree row per
        // imported alumnus. Statics do not survive across transactions — set it per call.
        KenAlumniOnboardingService.seedEducationOnProvision = false;
        Savepoint sp = Database.setSavepoint();
        try {
            KenAlumniOnboardingService.provisionOnLeadVerification(leads);
            return;
        } catch (Exception ex) {
            Database.rollback(sp);
            if (rows.size() == 1) {
                failRow(rows[0], 'could not be imported and was skipped — ' + ex.getMessage(), ex.getStackTraceString());
                return;
            }
        }
        if (Limits.getQueries() > QUERY_GUARD || Limits.getDmlStatements() > DML_GUARD || Limits.getCpuTime() > cpuGuardMs) {
            for (RowWork w : rows) {
                failRow(w, 'was skipped — too many failing rows in this chunk; re-upload this row.', null);
            }
            return;
        }
        List<RowWork> firstHalf = new List<RowWork>();
        List<RowWork> secondHalf = new List<RowWork>();
        for (Integer i = 0; i < rows.size(); i++) {
            if (i < rows.size() / 2) {
                firstHalf.add(rows[i]);
            } else {
                secondHalf.add(rows[i]);
            }
        }
        provisionRows(firstHalf);
        provisionRows(secondHalf);
    }

    /**
     * Loads each email's earliest CRM row once for the whole pass and applies
     * the CSV columns with partial-success DML. Also stamps ConstituentRole__c
     * on CRM rows that have no link yet — Alumni 360 reads the role (stage,
     * Year of Enrollment) through that lookup, so an unlinked row renders blank.
     */
    private void enrichCrms(List<RowWork> rows, String resolvedDataSource) {
        Set<String> emails = new Set<String>();
        for (RowWork w : rows) emails.add(w.email);

        Map<String, Account> personByEmail = new Map<String, Account>();
        for (Account a : [
            SELECT Id, PersonEmail
            FROM Account
            WHERE IsPersonAccount = true AND PersonEmail IN :emails
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate
        ]) {
            String key = a.PersonEmail == null ? null : a.PersonEmail.toLowerCase();
            if (key != null && !personByEmail.containsKey(key)) personByEmail.put(key, a);
        }

        Map<Id, List<ConstituentRole>> rolesByAccount = new Map<Id, List<ConstituentRole>>();
        Set<Id> accountIds = new Set<Id>();
        for (Account a : personByEmail.values()) accountIds.add(a.Id);
        if (!accountIds.isEmpty()) {
            for (ConstituentRole cr : [
                SELECT Id, PersonId, Registration_Number__c, Graduation_Year__c,
                       Program_Plan__c, Source_Funnel__c
                FROM ConstituentRole
                WHERE PersonId IN :accountIds AND RoleType = 'Alumni'
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
            ]) {
                if (!rolesByAccount.containsKey(cr.PersonId)) {
                    rolesByAccount.put(cr.PersonId, new List<ConstituentRole>());
                }
                rolesByAccount.get(cr.PersonId).add(cr);
            }
        }

        Map<Id, PersonEmployment> employmentByAccount = new Map<Id, PersonEmployment>();
        if (!accountIds.isEmpty()) {
            for (PersonEmployment pe : [
                SELECT Id, AccountId, Company_Name__c, Industry__c
                FROM PersonEmployment
                WHERE AccountId IN :accountIds
                  AND (Is_Archived__c = false OR Is_Archived__c = null)
                WITH SECURITY_ENFORCED
                ORDER BY Currently_Employed__c DESC, StartDate DESC NULLS LAST
            ]) {
                if (!employmentByAccount.containsKey(pe.AccountId)) {
                    employmentByAccount.put(pe.AccountId, pe);
                }
            }
        }

        List<SObject> updates = new List<SObject>();
        List<RowWork> owners = new List<RowWork>();
        List<PersonEmployment> employmentInserts = new List<PersonEmployment>();
        List<RowWork> employmentInsertOwners = new List<RowWork>();
        List<PersonEmployment> employmentUpdates = new List<PersonEmployment>();
        List<RowWork> employmentUpdateOwners = new List<RowWork>();

        for (RowWork w : rows) {
            Account person = personByEmail.get(w.emailKey());
            if (person == null) continue;

            String regNo = KenAlumniBulkImportController.getRowValue(w.row, 'Registration Number');
            String gradYear = KenAlumniBulkImportController.getRowValue(w.row, 'Year of Graduation');
            ConstituentRole target = rolesByAccount.containsKey(person.Id)
                ? matchRole(rolesByAccount.get(person.Id), w.programRes.programId, regNo)
                : null;
            if (target == null && rolesByAccount.containsKey(person.Id)
                && !rolesByAccount.get(person.Id).isEmpty()) {
                target = rolesByAccount.get(person.Id)[0];
            }
            if (target != null) {
                ConstituentRole roleUpdate = new ConstituentRole(Id = target.Id);
                Boolean roleDirty = false;
                if (String.isBlank(target.Registration_Number__c)
                    && String.isNotBlank(regNo) && regNo.length() <= 18) {
                    roleUpdate.Registration_Number__c = regNo;
                    roleDirty = true;
                }
                if (String.isBlank(target.Graduation_Year__c) && String.isNotBlank(gradYear)) {
                    roleUpdate.Graduation_Year__c = gradYear;
                    roleDirty = true;
                }
                if (String.isBlank(target.Source_Funnel__c) && String.isNotBlank(resolvedDataSource)) {
                    roleUpdate.Source_Funnel__c = resolvedDataSource;
                    roleDirty = true;
                }
                if (roleDirty) {
                    updates.add(roleUpdate);
                    owners.add(w);
                }
            }

            String company = KenAlumniBulkImportController.getRowValue(w.row, 'Current Company');
            String industry = KenAlumniBulkImportController.getRowValue(w.row, 'Industry');
            if (String.isNotBlank(company) || String.isNotBlank(industry)) {
                PersonEmployment existing = employmentByAccount.get(person.Id);
                if (existing == null) {
                    PersonEmployment pe = new PersonEmployment(
                        AccountId = person.Id,
                        RelatedPersonId = person.Id,
                        Name = String.isNotBlank(company) ? company.abbreviate(80) : 'Employment',
                        Currently_Employed__c = true,
                        Is_Archived__c = false
                    );
                    if (String.isNotBlank(company)) pe.Company_Name__c = company;
                    if (String.isNotBlank(industry)) pe.Industry__c = industry;
                    employmentInserts.add(pe);
                    employmentInsertOwners.add(w);
                } else {
                    PersonEmployment pe = new PersonEmployment(Id = existing.Id);
                    Boolean employmentDirty = false;
                    if (String.isBlank(existing.Company_Name__c) && String.isNotBlank(company)) {
                        pe.Company_Name__c = company;
                        employmentDirty = true;
                    }
                    if (String.isBlank(existing.Industry__c) && String.isNotBlank(industry)) {
                        pe.Industry__c = industry;
                        employmentDirty = true;
                    }
                    if (employmentDirty) {
                        employmentUpdates.add(pe);
                        employmentUpdateOwners.add(w);
                    }
                }
            }
        }

        savePartial('Constituent Role enrichment', updates, owners, false);
        savePartial('Employment enrichment', employmentInserts, employmentInsertOwners, true);
        savePartial('Employment enrichment', employmentUpdates, employmentUpdateOwners, false);
    }

    private Map<String, Account> findPersons(List<RowWork> rows) {
        Set<String> emails = new Set<String>();
        for (RowWork w : rows) emails.add(w.email);
        Map<String, Account> out = new Map<String, Account>();
        for (Account a : [
            SELECT Id, PersonContactId, PersonEmail
            FROM Account
            WHERE IsPersonAccount = true AND PersonEmail IN :emails
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate
        ]) {
            String key = a.PersonEmail == null ? null : a.PersonEmail.toLowerCase();
            if (key != null && !out.containsKey(key)) out.put(key, a);
        }
        return out;
    }

    private void enrichPersonAccounts(List<RowWork> rows, Map<String, Account> personByEmail, Map<String, Map<String, String>> picklists) {
        List<Account> updates = new List<Account>();
        List<RowWork> owners = new List<RowWork>();
        for (RowWork w : rows) {
            Account person = personByEmail.get(w.emailKey());
            if (person == null) continue;
            Account acc = new Account(Id = person.Id);
            Boolean dirty = false;
            dirty = setIfPresent(w.row, 'Phone', acc, Account.PersonMobilePhone) || dirty;
            dirty = setIfPresent(w.row, 'LinkedIn URL', acc, Account.Linkedin_Profile_URL__c) || dirty;
            dirty = setIfPresent(w.row, 'Languages Known', acc, Account.Languages_Known__c) || dirty;
            dirty = setIfPresent(w.row, 'Address Street', acc, Account.PersonMailingStreet) || dirty;
            dirty = setIfPresent(w.row, 'Address City', acc, Account.PersonMailingCity) || dirty;
            dirty = setIfPresent(w.row, 'Address State', acc, Account.PersonMailingState) || dirty;
            dirty = setIfPresent(w.row, 'Address Postal Code', acc, Account.PersonMailingPostalCode) || dirty;
            dirty = setIfPresent(w.row, 'Address Country', acc, Account.PersonMailingCountry) || dirty;
            dirty = setPicklistIfPresent(w.row, 'Nationality', acc, Account.Nationality__c, picklists.get('Nationality')) || dirty;
            dirty = setPicklistIfPresent(w.row, 'Gender', acc, Account.PersonGenderIdentity, picklists.get('Gender')) || dirty;
            dirty = setPicklistIfPresent(w.row, 'Blood Group', acc, Account.Blood_Group__c, picklists.get('Blood Group')) || dirty;
            Date dob = KenAlumniBulkImportController.parseDate(KenAlumniBulkImportController.getRowValue(w.row, 'Date of Birth'));
            if (dob != null) {
                acc.PersonBirthdate = dob;
                dirty = true;
            }
            if (dirty) {
                updates.add(acc);
                owners.add(w);
            }
        }
        savePartial('Profile update', updates, owners, false);
    }

    /**
     * Mirrors the mailing address onto a Ken_Address__c (Address_Type = Mailing)
     * record. That custom object — not the Person Account PersonMailing* fields —
     * is what the portal map, Alumni 360 address panel, dashboard regional
     * demographics and network location all read, so an imported alumnus is
     * invisible to those views until this row exists. Updates the person's
     * single mailing row so re-imports update in place instead of duplicating.
     */
    private void upsertMailingAddresses(List<RowWork> rows, Map<String, Account> personByEmail) {
        List<RowWork> withAddress = new List<RowWork>();
        Set<Id> accountIds = new Set<Id>();
        for (RowWork w : rows) {
            Account person = personByEmail.get(w.emailKey());
            if (person == null) continue;
            if (KenAlumniBulkImportController.getRowValue(w.row, 'Address Street') == null &&
                KenAlumniBulkImportController.getRowValue(w.row, 'Address City') == null &&
                KenAlumniBulkImportController.getRowValue(w.row, 'Address State') == null &&
                KenAlumniBulkImportController.getRowValue(w.row, 'Address Postal Code') == null &&
                KenAlumniBulkImportController.getRowValue(w.row, 'Address Country') == null) {
                continue;
            }
            withAddress.add(w);
            accountIds.add(person.Id);
        }
        if (withAddress.isEmpty()) return;

        Map<Id, Id> existingByAccount = new Map<Id, Id>();
        for (Ken_Address__c addr : [
            SELECT Id, Person_Account__c
            FROM Ken_Address__c
            WHERE Person_Account__c IN :accountIds AND Address_Type__c = 'Mailing'
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate
        ]) {
            if (!existingByAccount.containsKey(addr.Person_Account__c)) {
                existingByAccount.put(addr.Person_Account__c, addr.Id);
            }
        }

        List<Ken_Address__c> inserts = new List<Ken_Address__c>();
        List<RowWork> insertOwners = new List<RowWork>();
        List<Ken_Address__c> updates = new List<Ken_Address__c>();
        List<RowWork> updateOwners = new List<RowWork>();
        for (RowWork w : withAddress) {
            Account person = personByEmail.get(w.emailKey());
            Id existingId = existingByAccount.get(person.Id);
            Ken_Address__c addr = existingId == null
                ? new Ken_Address__c(Person_Account__c = person.Id, Address_Type__c = 'Mailing')
                : new Ken_Address__c(Id = existingId);
            addr.Street__c = KenAlumniBulkImportController.getRowValue(w.row, 'Address Street');
            addr.City__c = KenAlumniBulkImportController.getRowValue(w.row, 'Address City');
            addr.State__c = KenAlumniBulkImportController.getRowValue(w.row, 'Address State');
            addr.Pincode__c = KenAlumniBulkImportController.getRowValue(w.row, 'Address Postal Code');
            addr.Country__c = KenAlumniBulkImportController.getRowValue(w.row, 'Address Country');
            if (existingId == null) {
                inserts.add(addr);
                insertOwners.add(w);
            } else {
                updates.add(addr);
                updateOwners.add(w);
            }
        }
        savePartial('Mailing address insert', inserts, insertOwners, true);
        savePartial('Mailing address update', updates, updateOwners, false);
    }

    /**
     * Upserts the education rows for the pass, keyed on degree per account.
     * ContactId is mirrored so the rows appear in the Person Account's
     * Education related list.
     */
    private void upsertEducations(List<RowWork> rows, Map<String, Account> personByEmail, Map<String, String> gradeTypeValues) {
        Set<Id> accountIds = new Set<Id>();
        for (RowWork w : rows) {
            Account person = personByEmail.get(w.emailKey());
            if (person != null) accountIds.add(person.Id);
        }
        if (accountIds.isEmpty()) return;

        Map<Id, Map<String, PersonEducation>> existingByAccount = new Map<Id, Map<String, PersonEducation>>();
        for (PersonEducation pe : [
            SELECT Id, AccountId, Degree_Name__c
            FROM PersonEducation
            WHERE AccountId IN :accountIds AND (Is_Archived__c = false OR Is_Archived__c = null)
        WITH SECURITY_ENFORCED
        ]) {
            if (String.isBlank(pe.Degree_Name__c)) continue;
            if (!existingByAccount.containsKey(pe.AccountId)) {
                existingByAccount.put(pe.AccountId, new Map<String, PersonEducation>());
            }
            existingByAccount.get(pe.AccountId).put(KenAlumniBulkImportController.normalizeKey(pe.Degree_Name__c), pe);
        }

        List<PersonEducation> inserts = new List<PersonEducation>();
        List<RowWork> insertOwners = new List<RowWork>();
        List<PersonEducation> updates = new List<PersonEducation>();
        List<RowWork> updateOwners = new List<RowWork>();
        for (RowWork w : rows) {
            Account person = personByEmail.get(w.emailKey());
            if (person == null) continue;
            Map<String, PersonEducation> existingByDegree = existingByAccount.containsKey(person.Id)
                ? existingByAccount.get(person.Id)
                : new Map<String, PersonEducation>();
            for (EduLevel lvl : eduLevels()) {
                String institute = KenAlumniBulkImportController.getRowValue(w.row, lvl.instituteCol);
                String grade = KenAlumniBulkImportController.getRowValue(w.row, lvl.gradeCol);
                String year = KenAlumniBulkImportController.getRowValue(w.row, lvl.yearCol);
                String gradeTypeRaw = KenAlumniBulkImportController.getRowValue(w.row, lvl.gradeTypeCol);
                String providedDegree = lvl.degreeCol == null ? null : KenAlumniBulkImportController.getRowValue(w.row, lvl.degreeCol);

                if (institute == null && grade == null && year == null && gradeTypeRaw == null && providedDegree == null) {
                    continue;
                }

                String degree = KenAlumniBulkImportController.defaultString(providedDegree, lvl.fixedDegree);
                String gradeType = gradeTypeRaw == null ? null : gradeTypeValues.get(KenAlumniBulkImportController.normalizeKey(gradeTypeRaw));

                PersonEducation existing = existingByDegree.get(KenAlumniBulkImportController.normalizeKey(degree));
                PersonEducation pe = existing == null
                    ? new PersonEducation(AccountId = person.Id)
                    : new PersonEducation(Id = existing.Id);
                pe.Name = degree.length() > 80 ? degree.substring(0, 80) : degree;
                pe.Degree_Name__c = degree;
                pe.Institute_Name__c = institute;
                pe.Grade__c = grade;
                pe.Grade_Type__c = gradeType;
                pe.Year_of_Completion__c = year;
                pe.Is_Archived__c = false;
                if (person.PersonContactId != null) pe.ContactId = person.PersonContactId;
                if (existing == null) {
                    inserts.add(pe);
                    insertOwners.add(w);
                } else {
                    updates.add(pe);
                    updateOwners.add(w);
                }
            }
        }
        savePartial('Education insert', inserts, insertOwners, true);
        savePartial('Education update', updates, updateOwners, false);
    }

    private void upsertCurrentEmployments(List<RowWork> rows, Map<String, Account> personByEmail) {
        List<RowWork> withEmployment = new List<RowWork>();
        Set<Id> accountIds = new Set<Id>();
        for (RowWork w : rows) {
            Account person = personByEmail.get(w.emailKey());
            if (person == null) continue;
            if (KenAlumniBulkImportController.getRowValue(w.row, 'Current Company') == null &&
                KenAlumniBulkImportController.getRowValue(w.row, 'Current Designation') == null) {
                continue;
            }
            withEmployment.add(w);
            accountIds.add(person.Id);
        }
        if (withEmployment.isEmpty()) return;

        Map<Id, Id> existingByAccount = new Map<Id, Id>();
        for (PersonEmployment emp : [
            SELECT Id, AccountId
            FROM PersonEmployment
            WHERE AccountId IN :accountIds AND Currently_Employed__c = true
              AND (Is_Archived__c = false OR Is_Archived__c = null)
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate
        ]) {
            if (!existingByAccount.containsKey(emp.AccountId)) {
                existingByAccount.put(emp.AccountId, emp.Id);
            }
        }

        List<PersonEmployment> inserts = new List<PersonEmployment>();
        List<RowWork> insertOwners = new List<RowWork>();
        List<PersonEmployment> updates = new List<PersonEmployment>();
        List<RowWork> updateOwners = new List<RowWork>();
        for (RowWork w : withEmployment) {
            Account person = personByEmail.get(w.emailKey());
            Id existingId = existingByAccount.get(person.Id);
            PersonEmployment emp = existingId == null
                ? new PersonEmployment(AccountId = person.Id, RelatedPersonId = person.PersonContactId)
                : new PersonEmployment(Id = existingId);
            String company = KenAlumniBulkImportController.getRowValue(w.row, 'Current Company');
            String employerName = KenAlumniBulkImportController.defaultString(company, 'Employer');
            emp.Name = employerName.length() > 80 ? employerName.substring(0, 80) : employerName;
            emp.Company_Name__c = company;
            emp.Designation__c = KenAlumniBulkImportController.getRowValue(w.row, 'Current Designation');
            emp.Location__c = KenAlumniBulkImportController.getRowValue(w.row, 'Current Location');
            emp.StartDate = KenAlumniBulkImportController.parseDate(KenAlumniBulkImportController.getRowValue(w.row, 'Employment Start Date'));
            emp.Currently_Employed__c = true;
            emp.EndDate = null;
            emp.Is_Archived__c = false;
            if (existingId == null) {
                inserts.add(emp);
                insertOwners.add(w);
            } else {
                updates.add(emp);
                updateOwners.add(w);
            }
        }
        savePartial('Employment insert', inserts, insertOwners, true);
        savePartial('Employment update', updates, updateOwners, false);
    }

    private void applyRoleStatuses(List<RowWork> rows, Map<String, Account> personByEmail, Map<String, String> statusValues) {
        List<RowWork> withStatus = new List<RowWork>();
        Set<Id> accountIds = new Set<Id>();
        for (RowWork w : rows) {
            Account person = personByEmail.get(w.emailKey());
            if (person == null) continue;
            String statusRaw = KenAlumniBulkImportController.getRowValue(w.row, 'Status');
            if (String.isBlank(statusRaw)) continue;
            if (String.isBlank(statusValues.get(KenAlumniBulkImportController.normalizeKey(statusRaw)))) continue;
            withStatus.add(w);
            accountIds.add(person.Id);
        }
        if (withStatus.isEmpty()) return;

        Map<Id, List<ConstituentRole>> rolesByAccount = new Map<Id, List<ConstituentRole>>();
        for (ConstituentRole cr : [
            SELECT Id, PersonId, Registration_Number__c, Program_Plan__c, Registration_Status__c
            FROM ConstituentRole
            WHERE PersonId IN :accountIds AND RoleType = 'Alumni'
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ]) {
            if (!rolesByAccount.containsKey(cr.PersonId)) {
                rolesByAccount.put(cr.PersonId, new List<ConstituentRole>());
            }
            rolesByAccount.get(cr.PersonId).add(cr);
        }

        List<ConstituentRole> updates = new List<ConstituentRole>();
        List<RowWork> owners = new List<RowWork>();
        for (RowWork w : withStatus) {
            Account person = personByEmail.get(w.emailKey());
            List<ConstituentRole> roles = rolesByAccount.get(person.Id);
            if (roles == null || roles.isEmpty()) continue;
            String status = statusValues.get(KenAlumniBulkImportController.normalizeKey(KenAlumniBulkImportController.getRowValue(w.row, 'Status')));
            ConstituentRole target = matchRole(roles, w.programRes.programId, KenAlumniBulkImportController.getRowValue(w.row, 'Registration Number'));
            if (target != null && target.Registration_Status__c != status) {
                updates.add(new ConstituentRole(Id = target.Id, Registration_Status__c = status));
                owners.add(w);
            }
        }
        savePartial('Role status update', updates, owners, false);
    }

    /**
     * Applies partial-success DML and logs each failed record against the row
     * that produced it, so one bad row only fails itself.
     */
    private void savePartial(String step, List<SObject> records, List<RowWork> owners, Boolean isInsert) {
        if (records.isEmpty()) return;
        Database.SaveResult[] results = isInsert ? Database.insert(records, false) : Database.update(records, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) continue;
            String message = results[i].getErrors().isEmpty() ? 'Unknown error' : results[i].getErrors()[0].getMessage();
            failRow(owners[i], step + ' failed — ' + message, null);
        }
    }

    private void failRow(RowWork w, String message, String trace) {
        if (!w.failed) {
            w.failed = true;
            chunkRowsFailed++;
        }
        pendingLogs.add(KenLogService.build(
            KenLogService.CATEGORY_IMPORT, KenLogService.TYPE_ERROR, processName, KenAlumniBulkImportController.SOURCE_NAME,
            importSessionKey, 'Row ' + w.rowNo + ': ' + message, trace
        ));
    }

    private List<String> validateRow(Map<String, Object> row, Map<String, Map<String, String>> picklists) {
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
        String status = KenAlumniBulkImportController.getRowValue(row, 'Status');
        if (String.isNotBlank(status) && !picklists.get('Status').containsKey(KenAlumniBulkImportController.normalizeKey(status))) {
            errors.add('Status "' + status + '" is not a valid option (Unregistered, Verified, Registered, Initial Login Done).');
        }
        validatePicklistColumn(errors, row, 'Nationality', picklists.get('Nationality'));
        validatePicklistColumn(errors, row, 'Gender', picklists.get('Gender'));
        validatePicklistColumn(errors, row, 'Blood Group', picklists.get('Blood Group'));
        validateEnrollmentYear(errors, row);
        validateDate(errors, row, 'Date of Birth');
        validateDate(errors, row, 'Employment Start Date');
        for (EduLevel lvl : eduLevels()) {
            String gradeType = KenAlumniBulkImportController.getRowValue(row, lvl.gradeTypeCol);
            if (String.isNotBlank(gradeType) && !picklists.get('Grade Type').containsKey(KenAlumniBulkImportController.normalizeKey(gradeType))) {
                errors.add(lvl.gradeTypeCol + ' "' + gradeType + '" is not a valid option (Percentage, CGPA, GPA, Letter Grade).');
            }
        }
        return errors;
    }

    /**
     * Validates a value against the column's picklist entries. Orgs where the
     * backing field is a plain text field (e.g. Blood Group in KJS) have no
     * entries, so any value is accepted there and stored as typed.
     */
    private void validatePicklistColumn(List<String> errors, Map<String, Object> row, String column, Map<String, String> values) {
        String raw = KenAlumniBulkImportController.getRowValue(row, column);
        if (String.isBlank(raw) || values == null || values.isEmpty()) return;
        if (!values.containsKey(KenAlumniBulkImportController.normalizeKey(raw))) {
            errors.add(column + ' "' + raw + '" is not a valid option.');
        }
    }

    private void validateEnrollmentYear(List<String> errors, Map<String, Object> row) {
        String raw = KenAlumniBulkImportController.getRowValue(row, 'Year of Enrollment');
        if (String.isBlank(raw)) return;
        Integer enrollYear = KenAlumniBulkImportController.parseYear(raw);
        if (enrollYear == null) {
            errors.add('Year of Enrollment "' + raw + '" is not a valid year (use a 4-digit year).');
            return;
        }
        Integer gradYear = KenAlumniBulkImportController.parseYear(KenAlumniBulkImportController.getRowValue(row, 'Year of Graduation'));
        if (gradYear != null && enrollYear > gradYear) {
            errors.add('Year of Enrollment "' + raw + '" cannot be later than the Year of Graduation.');
        }
    }

    private void validateDate(List<String> errors, Map<String, Object> row, String column) {
        String raw = KenAlumniBulkImportController.getRowValue(row, column);
        if (String.isNotBlank(raw) && KenAlumniBulkImportController.parseDate(raw) == null) {
            errors.add(column + ' "' + raw + '" is not a valid date (use DD/MM/YYYY).');
        }
    }

    /**
     * The lead is in-memory only (never inserted), so LeadSource carries the
     * import's Data Source verbatim — KenAlumniOnboardingService.deriveSourceFunnel
     * maps it to the role's Source_Funnel__c (Historical Upload / Old Portal Migration).
     */
    private Lead buildLead(Map<String, Object> row, String programId, String resolvedDataSource) {
        Lead lead = new Lead(
            FirstName = KenAlumniBulkImportController.getRowValue(row, 'First Name'),
            LastName = KenAlumniBulkImportController.defaultString(KenAlumniBulkImportController.getRowValue(row, 'Last Name'), 'Alumni'),
            Email = KenAlumniBulkImportController.getRowValue(row, 'Email'),
            Phone = KenAlumniBulkImportController.getRowValue(row, 'Phone'),
            LeadSource = KenAlumniBulkImportController.defaultString(resolvedDataSource, 'Bulk Import'),
            Registration_Number__c = KenAlumniBulkImportController.getRowValue(row, 'Registration Number'),
            Year_of_Graduation__c = KenAlumniBulkImportController.getRowValue(row, 'Year of Graduation'),
            Year_of_Enrollment__c = KenAlumniBulkImportController.getRowValue(row, 'Year of Enrollment')
        );
        if (String.isNotBlank(programId)) {
            lead.Program_Plan__c = programId;
        }
        return lead;
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

    private Boolean setIfPresent(Map<String, Object> row, String column, SObject record, Schema.SObjectField field) {
        String value = KenAlumniBulkImportController.getRowValue(row, column);
        if (value == null) return false;
        record.put(field, value);
        return true;
    }

    /**
     * Writes a picklist-backed column using the exact picklist API value when the
     * org's field is a picklist; falls back to the raw value where the field is
     * plain text (e.g. Blood Group in KJS orgs).
     */
    private Boolean setPicklistIfPresent(Map<String, Object> row, String column, SObject record, Schema.SObjectField field, Map<String, String> values) {
        String raw = KenAlumniBulkImportController.getRowValue(row, column);
        if (raw == null) return false;
        String mapped = values == null || values.isEmpty()
            ? raw
            : values.get(KenAlumniBulkImportController.normalizeKey(raw));
        if (mapped == null) return false;
        record.put(field, mapped);
        return true;
    }

    private class RowWork {
        Map<String, Object> row;
        String rowNo;
        String email;
        Boolean preExisting = false;
        Boolean failed = false;
        Lead lead;
        KenAlumniBulkImportController.ProgramResolution programRes;

        String emailKey() {
            return email == null ? '' : email.toLowerCase();
        }
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

    private Ken_Logs__c buildLog(String logType, String message) {
        return KenLogService.build(
            KenLogService.CATEGORY_IMPORT, logType, processName, KenAlumniBulkImportController.SOURCE_NAME,
            importSessionKey, message, null
        );
    }

    private void writeLog(String logType, String message) {
        KenLogService.insertLogs(new List<Ken_Logs__c>{ buildLog(logType, message) });
    }
}