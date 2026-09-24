/**
 * The single entry point for reading configuration: org parameters, feature
 * switches, and the Named Credential that each outbound integration calls through.
 *
 * Two things this fixes.
 *
 * **One accessor, one meaning.** `Ken_Alm_Org_Parameters__c` was being read through
 * `getInstance()` in some classes and `getOrgDefaults()` in others. They are not the
 * same: `getInstance()` resolves the hierarchy - user, then profile, then the org
 * default - while `getOrgDefaults()` always reads the org row and ignores any
 * override. A per-user or per-profile value therefore worked in some modules and was
 * silently discarded in the rest. Everything now goes through `getInstance()`, which
 * is a strict superset: with no override configured it returns exactly what
 * `getOrgDefaults()` returned.
 *
 * **One guard, written once.** `orgParam != null && String.isNotBlank(x) ? x : fallback`
 * was spelled out by hand in a dozen places, with the fallback differing each time.
 * The guards below carry it.
 *
 * **Credentials.** A `*_Connection__c` setting holds the DEVELOPER NAME of a Named
 * Credential; blank means that integration is switched off. No endpoint, token or key
 * is stored in Apex, in a custom setting or in custom metadata - the credential holds
 * the secret and the platform resolves it at callout time.
 *
 * Managed package: every field is referenced through the compiler, never by a name
 * string, so the namespace is applied automatically on install. Do not reintroduce
 * string-based field access here - see KenNamespaceUtil for why that breaks.
 */
public with sharing class KenSettings {

    private static final String CALLOUT_PREFIX = 'callout:';

    @TestVisible
    private static Ken_Alm_Org_Parameters__c cachedParameters;

    @TestVisible
    private static Ken_Alm_Bypass_Settings__c cachedBypass;

    // ============================================================
    // Org parameters
    // ============================================================

    /**
     * @description The org parameters for the running user, read once per transaction.
     * @return the settings record, never null
     */
    public static Ken_Alm_Org_Parameters__c orgParameters() {
        if (cachedParameters == null) {
            Ken_Alm_Org_Parameters__c resolved = Ken_Alm_Org_Parameters__c.getInstance();
            cachedParameters = resolved == null ? new Ken_Alm_Org_Parameters__c() : resolved;
        }
        return cachedParameters;
    }

    /**
     * @description The institution's display name, preferring the short alias.
     * @param fallback returned when neither the alias nor the name is set
     */
    public static String institutionAlias(String fallback) {
        return textOr(orgParameters().Institution_Alias__c, textOr(orgParameters().Institution_Name__c, fallback));
    }

    /**
     * @description The institution's full name.
     * @param fallback returned when the name is not set
     */
    public static String institutionName(String fallback) {
        return textOr(orgParameters().Institution_Name__c, fallback);
    }

    /**
     * @description The institution's contact address.
     * @param fallback returned when the address is not set
     */
    public static String institutionEmail(String fallback) {
        return textOr(orgParameters().Institution_Email__c, fallback);
    }

    /**
     * @description The portal's base URL, with any trailing slash removed so callers
     *              can append a path without producing a double slash.
     * @param fallback returned when the URL is not set
     */
    public static String portalUrl(String fallback) {
        String url = textOr(orgParameters().Portal_URL__c, fallback);
        return url != null && url.endsWith('/') ? url.removeEnd('/') : url;
    }

    /**
     * @description The bypass switches for the running user, read once per transaction.
     *
     *              Every field means the same thing: ticked, that automation does not
     *              run. Triggers call this, so the 21 of them share one read instead of
     *              each issuing its own.
     *
     * @return the settings record, never null
     */
    public static Ken_Alm_Bypass_Settings__c bypass() {
        if (cachedBypass == null) {
            Ken_Alm_Bypass_Settings__c resolved = Ken_Alm_Bypass_Settings__c.getInstance();
            cachedBypass = resolved == null ? new Ken_Alm_Bypass_Settings__c() : resolved;
        }
        return cachedBypass;
    }

    // ============================================================
    // Integration credentials
    // ============================================================

    /**
     * @description The Named Credential for pushing events to an external system.
     * @return the credential's developer name, or null when the integration is off
     */
    public static String eventPushConnection() {
        return textOr(orgParameters().Event_Push_Connection__c, null);
    }

    /**
     * @description The Named Credential for Marketing Cloud.
     * @return the credential's developer name, or null when the integration is off
     */
    public static String marketingCloudConnection() {
        return textOr(orgParameters().SFMC_Connection__c, null);
    }

    /**
     * @description The Named Credential for the KAI chat service.
     * @return the credential's developer name, or null when the integration is off
     */
    public static String kaiChatConnection() {
        return textOr(orgParameters().KAI_Chat_Connection__c, null);
    }

    /**
     * @description The Named Credential for the LinkedIn profile enrichment service.
     * @return the credential's developer name, or null when the integration is off
     */
    public static String linkedInEnrichmentConnection() {
        return textOr(orgParameters().LinkedIn_Enrichment_Connection__c, null);
    }

    /**
     * @description The Named Credential naming one external integration.
     * @param config the integration's configuration record
     * @return the credential's developer name, or null when that integration is off
     */
    public static String connectionFor(Ken_Alm_Integration_Settings__mdt config) {
        return config == null ? null : textOr(config.Connection__c, null);
    }

    /**
     * @description Whether an integration has been configured at all.
     * @param connection a credential developer name from one of the accessors above
     */
    public static Boolean isConfigured(String connection) {
        return String.isNotBlank(connection);
    }

    /**
     * @description A callout endpoint addressed through a Named Credential.
     * @param connection a credential developer name from one of the accessors above
     * @param path the path beneath the credential's base URL, starting with a slash
     * @return the endpoint to set on the request, or null when the integration is off
     */
    public static String endpoint(String connection, String path) {
        if (!isConfigured(connection)) {
            return null;
        }
        return CALLOUT_PREFIX + connection + (path == null ? '' : path);
    }

    // ============================================================
    // Guards
    // ============================================================

    /**
     * @description A trimmed setting value, or a fallback when it is blank.
     * @param value the raw setting value
     * @param fallback returned when the value is blank
     */
    public static String textOr(String value, String fallback) {
        return String.isBlank(value) ? fallback : value.trim();
    }

    /**
     * @description A checkbox read as true only when explicitly ticked.
     * @param value the raw setting value
     */
    public static Boolean isOn(Boolean value) {
        return value == true;
    }

    /**
     * @description A numeric setting, or a fallback when it is unset or not positive.
     * @param value the raw setting value
     * @param fallback returned when the value is null or below one
     */
    public static Integer countOr(Decimal value, Integer fallback) {
        return value == null || value < 1 ? fallback : Integer.valueOf(value);
    }

    /**
     * @description Clears the cached record. Tests that change settings mid-run must
     *              call this, because the record is otherwise read once per transaction.
     */
    @TestVisible
    private static void clearCache() {
        cachedParameters = null;
        cachedBypass = null;
    }
}