/**
 * @description Generic logging service that persists diagnostics to Ken_Logs__c.
 *              Used to capture import errors, email failures and other process
 *              issues without ever propagating an exception back to the caller —
 *              logging must never break the originating business flow.
 *
 * @author  Surya
 */
public with sharing class KenLogService {
    public static final String CATEGORY_IMPORT = 'Import';
    public static final String CATEGORY_EMAIL = 'Email';
    public static final String CATEGORY_GENERAL = 'General';

    public static final String TYPE_ERROR = 'Error';
    public static final String TYPE_WARNING = 'Warning';
    public static final String TYPE_INFO = 'Info';

    // Ken_Logs__c long text fields are 131072 characters.
    private static final Integer MAX_TEXT_LENGTH = 131072;

    /**
     * @description Builds an in-memory Ken_Logs__c record without inserting it.
     *              Callers (e.g. batch jobs) collect these and bulk-insert via insertLogs().
     */
    public static Ken_Logs__c build(
        String category,
        String logType,
        String process,
        String source,
        String referenceId,
        String message,
        String stackTrace
    ) {
        Ken_Logs__c logRecord = new Ken_Logs__c();
        logRecord.Category__c = category;
        logRecord.Log_Type__c = logType;
        logRecord.Process__c = process;
        logRecord.Source__c = source;
        logRecord.Reference_Id__c = referenceId;
        logRecord.Message__c = truncate(message);
        logRecord.Stack_Trace__c = truncate(stackTrace);
        return logRecord;
    }

    /**
     * @description Inserts a collection of logs, swallowing any failure so the
     *              caller's transaction is never impacted.
     */
    public static void insertLogs(List<Ken_Logs__c> logs) {
        if (logs == null || logs.isEmpty()) {
            return;
        }
        try {
            Database.DMLOptions options = new Database.DMLOptions();
            options.allowFieldTruncation = true;
            options.optAllOrNone = false;
            Database.insert(logs, options);
        } catch (Exception ignored) {
            // Logging failures are intentionally suppressed.
        }
    }

    /**
     * @description Persists a single log record immediately.
     */
    public static void log(
        String category,
        String logType,
        String process,
        String source,
        String referenceId,
        String message,
        String stackTrace
    ) {
        insertLogs(new List<Ken_Logs__c>{
            build(category, logType, process, source, referenceId, message, stackTrace)
        });
    }

    /**
     * @description Convenience helper for logging a caught exception.
     */
    public static void logException(
        String category,
        String process,
        String source,
        String referenceId,
        Exception ex
    ) {
        if (ex == null) {
            return;
        }
        log(category, TYPE_ERROR, process, source, referenceId, ex.getMessage(), ex.getStackTraceString());
    }

    private static String truncate(String value) {
        if (value == null) {
            return null;
        }
        return value.length() > MAX_TEXT_LENGTH ? value.substring(0, MAX_TEXT_LENGTH) : value;
    }
}