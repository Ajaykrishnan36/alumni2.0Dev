/**
 * KenAlumniBulkImportController
 *
 * Holds the alumni bulk import feature in two files:
 *   - This controller: @AuraEnabled endpoints, chunk storage helpers,
 *     and all per-row validation/build helpers shared with the batch.
 *   - KenAlumniBulkImportBatch (top-level): the Database.Batchable<String> —
 *     Salesforce requires Batchable to be a top-level class, so it cannot be
 *     an inner class here.
 *
 * Per-row errors and duplicate warnings are written to Ken_Logs__c (generic shared
 * logging service) and read back so the UI can surface and export failed rows.
 */
public with sharing class KenAlumniBulkImportController {
    @TestVisible public static final String PROCESS_NAME = 'Alumni Bulk Import';
    public static final String SOURCE_NAME = 'Class:KenAlumniBulkImportController';
    public static final String SOURCE_SESSION = 'Session:KenAlumniBulkImportController';
    public static final String DEFAULT_DATA_SOURCE = 'Historical Upload';
    private static final String FILE_EXTENSION = '.json';
    private static final Integer TITLE_PAD_LENGTH = 6;
    private static final String SESSION_STATE_RUNNING = 'Running';
    private static final String SESSION_STATE_COMPLETED = 'Completed';

    private static final Set<String> RUNNING_STATUSES = new Set<String>{
        'Holding', 'Queued', 'Preparing', 'Processing'
    };
    private static final Set<String> ROW_LOG_TYPES = new Set<String>{
        KenLogService.TYPE_ERROR, KenLogService.TYPE_WARNING
    };

    public class BatchStatusInfo {
        @AuraEnabled public Id jobId;
        @AuraEnabled public String status;
        @AuraEnabled public Integer processed;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer errors;
        @AuraEnabled public Boolean isRunning;
    }

    public class SessionStatusInfo {
        @AuraEnabled public String sessionKey;
        @AuraEnabled public String status;
        @AuraEnabled public Integer processed;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer errors;
        @AuraEnabled public Boolean isRunning;
    }

    private class SessionProgress {
        Integer total = 0;
        Integer attempted = 0;
        Integer failed = 0;
        String state = SESSION_STATE_RUNNING;
    }

    // ============================================================
    // @AuraEnabled endpoints used by the LWC
    // ============================================================

    @AuraEnabled
    public static String createImportSession() {
        return createSessionKey();
    }

    @AuraEnabled
    public static void saveImportChunk(String sessionKey, Integer chunkIndex, String chunkJson) {
        saveChunk(PROCESS_NAME, sessionKey, chunkIndex, chunkJson);
    }

    @AuraEnabled
    public static Id startChunkedImport(String sessionKey, String dataSource, Integer totalRows) {
        if (String.isBlank(sessionKey)) {
            throw new AuraHandledException('Import session key is required.');
        }
        if (getChunkVersionIds(PROCESS_NAME, sessionKey).isEmpty()) {
            throw new AuraHandledException('Upload at least one row before importing.');
        }
        Id jobId = Database.executeBatch(
            new KenAlumniBulkImportBatch(PROCESS_NAME, sessionKey, dataSource),
            importBatchScope()
        );
        KenLogService.log(
            KenLogService.CATEGORY_IMPORT, KenLogService.TYPE_INFO, PROCESS_NAME, SOURCE_SESSION,
            sessionKey, buildSessionMessage(totalRows == null ? 0 : totalRows, 0, 0, SESSION_STATE_RUNNING), null
        );
        return jobId;
    }

    /**
     * Rows per transaction for the import batch. Defaults to 100 and is
     * tunable per org via Ken_Alm_Org_Parameters__c.Import_Batch_Scope__c
     * without a redeploy — lower it in orgs whose Account automation is
     * CPU-heavy (KJS), raise it up to 200 where automation is light.
     * Out-of-range or blank values fall back to the default.
     */
    public static Integer importBatchScope() {
        Ken_Alm_Org_Parameters__c params = Ken_Alm_Org_Parameters__c.getOrgDefaults();
        if (params != null && params.Import_Batch_Scope__c != null
            && params.Import_Batch_Scope__c >= 1 && params.Import_Batch_Scope__c <= 200) {
            return Integer.valueOf(params.Import_Batch_Scope__c);
        }
        return 100;
    }

    @AuraEnabled
    public static List<String> getImportErrors(String sessionKey) {
        List<String> errors = new List<String>();
        if (String.isBlank(sessionKey)) return errors;
        for (Ken_Logs__c logRecord : [
            SELECT Message__c FROM Ken_Logs__c
            WHERE Reference_Id__c = :sessionKey
              AND Process__c = :PROCESS_NAME
              AND Log_Type__c IN :ROW_LOG_TYPES
            WITH USER_MODE
            ORDER BY CreatedDate ASC LIMIT 5000
        ]) {
            if (String.isNotBlank(logRecord.Message__c)) errors.add(logRecord.Message__c);
        }
        return errors;
    }

    @AuraEnabled
    public static BatchStatusInfo getBatchStatus(Id jobId) {
        if (jobId == null) return null;
        if (!AsyncApexJob.SObjectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Read access is required for AsyncApexJob.');
        }
        AsyncApexJob job = [
            SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
            FROM AsyncApexJob WHERE Id = :jobId LIMIT 1
        ];
        return toInfo(job);
    }

    /**
     * Returns whole-session progress for a chained chunk import. Counts come
     * from the session marker log (folded in by each chunk job's finish); the
     * currently running chunk job's live item count is added on top. A session
     * whose marker still says Running but has no active job was interrupted
     * (aborted job, failed finish) and reports as Stalled.
     */
    @AuraEnabled
    public static SessionStatusInfo getSessionStatus(String sessionKey) {
        Ken_Logs__c marker = findSessionMarker(sessionKey);
        return marker == null ? null : toSessionInfo(sessionKey, marker);
    }

    /**
     * Returns the current user's most recent import session so the screen can
     * reconnect to a run that is still in progress even after the tab was
     * closed and reopened.
     */
    @AuraEnabled
    public static SessionStatusInfo getLatestImportSession() {
        List<Ken_Logs__c> markers = [
            SELECT Id, Message__c, Reference_Id__c, CreatedById FROM Ken_Logs__c
            WHERE Process__c = :PROCESS_NAME
              AND Source__c = :SOURCE_SESSION
              AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return markers.isEmpty() ? null : toSessionInfo(markers[0].Reference_Id__c, markers[0]);
    }

    private static SessionStatusInfo toSessionInfo(String sessionKey, Ken_Logs__c marker) {
        SessionProgress progress = parseSessionMessage(marker.Message__c);
        SessionStatusInfo info = new SessionStatusInfo();
        info.sessionKey = sessionKey;
        info.total = progress.total;
        info.processed = progress.attempted;
        info.errors = progress.failed;
        if (progress.state == SESSION_STATE_COMPLETED) {
            info.isRunning = false;
            info.status = SESSION_STATE_COMPLETED;
            return info;
        }
        List<AsyncApexJob> active = [
            SELECT Status, JobItemsProcessed FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
              AND ApexClass.Name = 'KenAlumniBulkImportBatch'
              AND CreatedById = :marker.CreatedById
              AND Status IN :RUNNING_STATUSES
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        if (active.isEmpty()) {
            info.isRunning = false;
            info.status = 'Stalled';
        } else {
            info.isRunning = true;
            info.status = active[0].Status;
            info.processed += active[0].JobItemsProcessed == null ? 0 : Integer.valueOf(active[0].JobItemsProcessed);
        }
        return info;
    }

    private static BatchStatusInfo toInfo(AsyncApexJob job) {
        BatchStatusInfo info = new BatchStatusInfo();
        info.jobId = job.Id;
        info.status = job.Status;
        info.processed = Integer.valueOf(job.JobItemsProcessed);
        info.total = Integer.valueOf(job.TotalJobItems);
        info.errors = Integer.valueOf(job.NumberOfErrors);
        info.isRunning = RUNNING_STATUSES.contains(job.Status);
        return info;
    }

    // ============================================================
    // Chunk storage — stages CSV rows as ContentVersion files keyed by
    // (processName, sessionKey, chunkIndex).
    // ============================================================

    public static String createSessionKey() {
        String seed = UserInfo.getUserId() + ':' + String.valueOf(Datetime.now().getTime()) + ':' + String.valueOf(Crypto.getRandomInteger());
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(seed))).substring(0, 24);
    }

    public static void saveChunk(String processName, String sessionKey, Integer chunkIndex, String chunkJson) {
        if (String.isBlank(processName) || String.isBlank(sessionKey) || chunkIndex == null || String.isBlank(chunkJson)) {
            throw new AuraHandledException('Invalid bulk import chunk payload.');
        }
        String title = buildChunkTitle(processName, sessionKey, chunkIndex);
        Database.insert(new ContentVersion(
            Title = title,
            PathOnClient = title + FILE_EXTENSION,
            VersionData = Blob.valueOf(chunkJson),
            IsMajorVersion = false
        ), true, AccessLevel.USER_MODE);
    }

    public static List<Id> getChunkVersionIds(String processName, String sessionKey) {
        List<Id> versionIds = new List<Id>();
        if (String.isBlank(processName) || String.isBlank(sessionKey)) return versionIds;
        String titlePrefix = buildChunkTitlePrefix(processName, sessionKey) + '%';
        for (ContentVersion versionRow : [
            SELECT Id FROM ContentVersion
            WHERE IsLatest = true AND Title LIKE :titlePrefix
            WITH USER_MODE
            ORDER BY Title
        ]) {
            versionIds.add(versionRow.Id);
        }
        return versionIds;
    }

    public class ChunkPayload {
        public Id documentId;
        public String body;
    }

    /**
     * Returns the lowest-numbered staged chunk file for the session. The batch
     * processes exactly one chunk file per job so the heap never holds the
     * whole staged import at once.
     */
    public static ChunkPayload getFirstChunk(String processName, String sessionKey) {
        List<Id> versionIds = getChunkVersionIds(processName, sessionKey);
        if (versionIds.isEmpty()) return null;
        List<ContentVersion> rows = [
            SELECT ContentDocumentId, VersionData FROM ContentVersion WHERE Id = :versionIds[0]
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) return null;
        ChunkPayload chunk = new ChunkPayload();
        chunk.documentId = rows[0].ContentDocumentId;
        chunk.body = rows[0].VersionData == null ? null : rows[0].VersionData.toString();
        return chunk;
    }

    public static void deleteChunkDocument(Id documentId) {
        if (documentId == null) return;
        List<ContentDocument> docs = [SELECT Id FROM ContentDocument WHERE Id = :documentId WITH USER_MODE LIMIT 1];
        if (!docs.isEmpty()) {
            Database.delete(docs, true, AccessLevel.USER_MODE);
        }
    }

    // ============================================================
    // Session progress marker — one Ken_Logs__c row per import session
    // (Source = SOURCE_SESSION, Reference_Id = session key) whose message
    // holds "total|attempted|failed|state". Message__c is a long text area
    // (not filterable), so the marker is located via Source__c.
    // ============================================================

    /**
     * Folds one chunk job's row counts into the session marker; the final
     * chunk job flips the state to Completed. Called from the batch finish().
     */
    public static void updateSessionProgress(String sessionKey, Integer attemptedDelta, Integer failedDelta, Boolean isComplete) {
        Ken_Logs__c marker = findSessionMarker(sessionKey);
        if (marker == null) return;
        SessionProgress progress = parseSessionMessage(marker.Message__c);
        marker.Message__c = buildSessionMessage(
            progress.total,
            progress.attempted + (attemptedDelta == null ? 0 : attemptedDelta),
            progress.failed + (failedDelta == null ? 0 : failedDelta),
            isComplete ? SESSION_STATE_COMPLETED : SESSION_STATE_RUNNING
        );
        if (!Schema.sObjectType.Ken_Logs__c.isUpdateable()) {
            throw new KenCrudException('Ken_Logs__c is not updateable by the current user.');
        }
        update marker;
    }

    private static Ken_Logs__c findSessionMarker(String sessionKey) {
        if (String.isBlank(sessionKey)) return null;
        List<Ken_Logs__c> markers = [
            SELECT Id, Message__c, CreatedById FROM Ken_Logs__c
            WHERE Reference_Id__c = :sessionKey
              AND Process__c = :PROCESS_NAME
              AND Source__c = :SOURCE_SESSION
            WITH USER_MODE
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return markers.isEmpty() ? null : markers[0];
    }

    private static String buildSessionMessage(Integer total, Integer attempted, Integer failed, String state) {
        return total + '|' + attempted + '|' + failed + '|' + state;
    }

    private static SessionProgress parseSessionMessage(String message) {
        SessionProgress progress = new SessionProgress();
        List<String> parts = String.isBlank(message) ? new List<String>() : message.split('\\|');
        if (parts.size() > 0) progress.total = safeInt(parts[0]);
        if (parts.size() > 1) progress.attempted = safeInt(parts[1]);
        if (parts.size() > 2) progress.failed = safeInt(parts[2]);
        if (parts.size() > 3) progress.state = parts[3];
        return progress;
    }

    private static Integer safeInt(String value) {
        try {
            return Integer.valueOf(value.trim());
        } catch (Exception e) {
            return 0;
        }
    }

    private static String buildChunkTitle(String processName, String sessionKey, Integer chunkIndex) {
        return buildChunkTitlePrefix(processName, sessionKey) + padNumber(chunkIndex);
    }

    private static String buildChunkTitlePrefix(String processName, String sessionKey) {
        return 'BulkImport|' + processName + '|' + sessionKey + '|';
    }

    private static String padNumber(Integer value) {
        String raw = String.valueOf(value == null ? 0 : value);
        while (raw.length() < TITLE_PAD_LENGTH) raw = '0' + raw;
        return raw;
    }

    // ============================================================
    // Per-row helpers — exposed for KenAlumniBulkImportBatch
    //
    // The batch (top-level class, separate file) consumes these for row-by-row
    // validation/provisioning. We can't fold the batch in here because
    // Database.Batchable<...> may only be implemented by top-level classes.
    // ============================================================

    /**
     * @description Legacy Ken_Alumni_CRM__c.Data_Source__c labels mapped onto the
     *              equivalent ConstituentRole.Source_Funnel__c values. The two
     *              described the same thing in different words, so Source_Funnel__c
     *              is now the single home and these aliases keep older saved
     *              selections resolving.
     */
    private static final Map<String, String> DATA_SOURCE_ALIASES = new Map<String, String>{
        'historic import' => 'Historical Upload',
        'historic records' => 'Historical Upload',
        'portal migration' => 'Old Portal Migration',
        'new graduate' => 'Student-to-Alumni Transition',
        'self-registered' => 'Self-Declared Lead'
    };

    public static String resolveDataSource(String dataSource) {
        Map<String, String> values = picklistValues(ConstituentRole.Source_Funnel__c.getDescribe());
        String matched = values.get(normalizeKey(dataSource));
        if (matched != null) {
            return matched;
        }
        String aliased = DATA_SOURCE_ALIASES.get(normalizeKey(dataSource));
        return aliased != null ? aliased : DEFAULT_DATA_SOURCE;
    }

    public static Map<String, String> picklistValues(Schema.DescribeFieldResult describe) {
        Map<String, String> out = new Map<String, String>();
        for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
            if (entry.isActive()) {
                out.put(normalizeKey(entry.getValue()), entry.getValue());
                out.put(normalizeKey(entry.getLabel()), entry.getValue());
            }
        }
        return out;
    }

    public static String getRowValue(Map<String, Object> row, String key) {
        if (row == null || !row.containsKey(key) || row.get(key) == null) return null;
        String value = String.valueOf(row.get(key)).trim();
        return String.isBlank(value) ? null : value;
    }

    public static String getRowNumber(Map<String, Object> row) {
        if (row != null && row.containsKey('RowNumber') && row.get('RowNumber') != null) {
            try {
                return String.valueOf(Integer.valueOf(String.valueOf(row.get('RowNumber')).trim()));
            } catch (Exception ignored) {
                // fall through
            }
        }
        return '?';
    }

    public static String normalizeKey(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    public static String defaultString(String value, String fallback) {
        return String.isBlank(value) ? fallback : value;
    }

    public static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) return false;
        return Pattern.matches('^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$', email.trim());
    }

    public static Date parseDate(String value) {
        if (String.isBlank(value)) return null;
        String v = value.trim();
        Matcher iso = Pattern.compile('^(\\d{4})[/-](\\d{1,2})[/-](\\d{1,2})$').matcher(v);
        if (iso.matches()) {
            return safeDate(Integer.valueOf(iso.group(1)), Integer.valueOf(iso.group(2)), Integer.valueOf(iso.group(3)));
        }
        Matcher dmy = Pattern.compile('^(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})$').matcher(v);
        if (dmy.matches()) {
            return safeDate(Integer.valueOf(dmy.group(3)), Integer.valueOf(dmy.group(2)), Integer.valueOf(dmy.group(1)));
        }
        return null;
    }

    private static Date safeDate(Integer year, Integer month, Integer day) {
        if (month < 1 || month > 12 || day < 1 || day > 31) return null;
        Date result = Date.newInstance(year, month, day);
        if (result.year() != year || result.month() != month || result.day() != day) return null;
        return result;
    }

    public class ProgramResolution {
        public Boolean provided = false;
        public Boolean resolved = false;
        public String programId;
        public String storedValue;
    }

    /**
     * Resolves the CSV Program column, accepting either a LearningProgramPlan Id
     * or a program name. A resolved plan yields its Id (for the role lookup) and
     * its Name in storedValue (for display fields — never store the Id where the
     * UI reads it); anything unresolved is kept as plain text in storedValue so
     * historic program names that have no LearningProgramPlan still import.
     */
    public static ProgramResolution resolveProgram(String raw) {
        if (String.isBlank(raw)) return new ProgramResolution();
        return resolvePrograms(new Set<String>{ raw }).get(raw.trim());
    }

    /**
     * Bulk form of resolveProgram: resolves every distinct Program value in one
     * pass (two queries total, regardless of how many values are given) and
     * returns the resolutions keyed by the trimmed raw value.
     */
    public static Map<String, ProgramResolution> resolvePrograms(Set<String> rawValues) {
        Map<String, ProgramResolution> out = new Map<String, ProgramResolution>();
        if (rawValues == null) return out;
        Set<Id> idCandidates = new Set<Id>();
        Set<String> nameCandidates = new Set<String>();
        for (String raw : rawValues) {
            if (String.isBlank(raw)) continue;
            String value = raw.trim();
            if (out.containsKey(value)) continue;
            ProgramResolution res = new ProgramResolution();
            res.provided = true;
            res.storedValue = value;
            out.put(value, res);
            if (isProgramPlanId(value)) {
                idCandidates.add(Id.valueOf(value));
            } else {
                nameCandidates.add(value);
            }
        }
        Map<Id, String> nameById = new Map<Id, String>();
        if (!idCandidates.isEmpty()) {
            for (LearningProgramPlan plan : [SELECT Id, Name FROM LearningProgramPlan WHERE Id IN :idCandidates WITH USER_MODE]) {
                nameById.put(plan.Id, plan.Name);
            }
        }
        Map<String, LearningProgramPlan> planByNameKey = new Map<String, LearningProgramPlan>();
        if (!nameCandidates.isEmpty()) {
            for (LearningProgramPlan plan : [
                SELECT Id, Name FROM LearningProgramPlan WHERE Name IN :nameCandidates
                WITH USER_MODE
                ORDER BY CreatedDate
            ]) {
                String nameKey = normalizeKey(plan.Name);
                if (!planByNameKey.containsKey(nameKey)) planByNameKey.put(nameKey, plan);
            }
        }
        // A value may also be the parent programme's name (e.g. "MBA" instead of the
        // plan/batch name "JAN-2026-MBA"): resolve it when it maps to exactly ONE plan,
        // otherwise it stays plain text — an ambiguous programme can't pick a batch.
        Map<String, List<LearningProgramPlan>> plansByProgramKey = new Map<String, List<LearningProgramPlan>>();
        if (!nameCandidates.isEmpty()) {
            for (LearningProgramPlan plan : [
                SELECT Id, Name, LearningProgram.Name FROM LearningProgramPlan
                WHERE LearningProgram.Name IN :nameCandidates
                WITH USER_MODE
                ORDER BY CreatedDate
            ]) {
                String progKey = normalizeKey(plan.LearningProgram.Name);
                if (!plansByProgramKey.containsKey(progKey)) plansByProgramKey.put(progKey, new List<LearningProgramPlan>());
                plansByProgramKey.get(progKey).add(plan);
            }
        }
        for (String value : out.keySet()) {
            ProgramResolution res = out.get(value);
            if (isProgramPlanId(value)) {
                Id planId = Id.valueOf(value);
                if (nameById.containsKey(planId)) {
                    res.resolved = true;
                    res.programId = value;
                    res.storedValue = nameById.get(planId);
                }
            } else if (planByNameKey.containsKey(normalizeKey(value))) {
                LearningProgramPlan plan = planByNameKey.get(normalizeKey(value));
                res.resolved = true;
                res.programId = plan.Id;
                res.storedValue = plan.Name;
            } else if (plansByProgramKey.containsKey(normalizeKey(value))
                       && plansByProgramKey.get(normalizeKey(value)).size() == 1) {
                LearningProgramPlan plan = plansByProgramKey.get(normalizeKey(value))[0];
                res.resolved = true;
                res.programId = plan.Id;
                res.storedValue = plan.Name;
            }
        }
        return out;
    }

    public static Integer parseYear(String value) {
        if (String.isBlank(value) || !Pattern.matches('^\\d{4}$', value.trim())) return null;
        return Integer.valueOf(value.trim());
    }

    public static Boolean isProgramPlanId(String value) {
        if (String.isBlank(value) || (value.length() != 15 && value.length() != 18)) return false;
        try {
            return Id.valueOf(value).getSObjectType() == LearningProgramPlan.SObjectType;
        } catch (Exception e) {
            return false;
        }
    }
}