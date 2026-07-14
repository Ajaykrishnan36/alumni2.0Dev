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
    public static final String DEFAULT_DATA_SOURCE = 'Historic Import';
    private static final String FILE_EXTENSION = '.json';
    private static final Integer TITLE_PAD_LENGTH = 6;

    private static final Set<String> RUNNING_STATUSES = new Set<String>{
        'Holding', 'Queued', 'Preparing', 'Processing'
    };

    public class BatchStatusInfo {
        @AuraEnabled public Id jobId;
        @AuraEnabled public String status;
        @AuraEnabled public Integer processed;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer errors;
        @AuraEnabled public Boolean isRunning;
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
    public static Id startChunkedImport(String sessionKey, String dataSource) {
        if (String.isBlank(sessionKey)) {
            throw new AuraHandledException('Import session key is required.');
        }
        if (getChunkVersionIds(PROCESS_NAME, sessionKey).isEmpty()) {
            throw new AuraHandledException('Upload at least one row before importing.');
        }
        return Database.executeBatch(
            new KenAlumniBulkImportBatch(PROCESS_NAME, sessionKey, dataSource),
            1
        );
    }

    @AuraEnabled
    public static List<String> getImportErrors(Id jobId) {
        List<String> errors = new List<String>();
        if (jobId == null) return errors;
        for (Ken_Logs__c logRecord : [
            SELECT Message__c FROM Ken_Logs__c
            WHERE Reference_Id__c = :String.valueOf(jobId)
              AND Process__c = :PROCESS_NAME
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
     * Returns the current user's most recent alumni-import job so the screen can
     * reconnect to a run that is still in progress (or show the last completed
     * run's results) even after the tab was closed and reopened.
     */
    @AuraEnabled
    public static BatchStatusInfo getLatestImportJob() {
        List<AsyncApexJob> jobs = [
            SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
              AND ApexClass.Name = 'KenAlumniBulkImportBatch'
              AND CreatedById = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return jobs.isEmpty() ? null : toInfo(jobs[0]);
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
        insert new ContentVersion(
            Title = title,
            PathOnClient = title + FILE_EXTENSION,
            VersionData = Blob.valueOf(chunkJson),
            IsMajorVersion = false
        );
    }

    public static List<Id> getChunkVersionIds(String processName, String sessionKey) {
        List<Id> versionIds = new List<Id>();
        if (String.isBlank(processName) || String.isBlank(sessionKey)) return versionIds;
        String titlePrefix = buildChunkTitlePrefix(processName, sessionKey) + '%';
        for (ContentVersion versionRow : [
            SELECT Id FROM ContentVersion
            WHERE IsLatest = true AND Title LIKE :titlePrefix
            ORDER BY Title
        ]) {
            versionIds.add(versionRow.Id);
        }
        return versionIds;
    }

    public static String getChunkJson(Id versionId) {
        if (versionId == null) return null;
        List<ContentVersion> rows = [
            SELECT VersionData FROM ContentVersion WHERE Id = :versionId LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].VersionData == null) return null;
        return rows[0].VersionData.toString();
    }

    public static void deleteChunks(String processName, String sessionKey) {
        if (String.isBlank(processName) || String.isBlank(sessionKey)) return;
        String titlePrefix = buildChunkTitlePrefix(processName, sessionKey) + '%';
        Set<Id> documentIds = new Set<Id>();
        for (ContentVersion versionRow : [
            SELECT ContentDocumentId FROM ContentVersion
            WHERE IsLatest = true AND Title LIKE :titlePrefix
        ]) {
            if (versionRow.ContentDocumentId != null) documentIds.add(versionRow.ContentDocumentId);
        }
        if (!documentIds.isEmpty()) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :documentIds];
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

    public static String resolveDataSource(String dataSource) {
        Map<String, String> values = picklistValues(Ken_Alumni_CRM__c.Data_Source__c.getDescribe());
        String matched = values.get(normalizeKey(dataSource));
        return matched != null ? matched : DEFAULT_DATA_SOURCE;
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
        public Boolean resolved = true;
        public String programId;
    }

    public static ProgramResolution resolveProgram(String raw) {
        ProgramResolution res = new ProgramResolution();
        if (String.isBlank(raw)) return res;
        res.provided = true;
        String value = raw.trim();
        if (isProgramPlanId(value)) {
            res.programId = value;
            return res;
        }
        List<LearningProgramPlan> plans = [
            SELECT Id FROM LearningProgramPlan WHERE Name = :value ORDER BY CreatedDate LIMIT 1
        ];
        if (plans.isEmpty()) {
            res.resolved = false;
        } else {
            res.programId = plans[0].Id;
        }
        return res;
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