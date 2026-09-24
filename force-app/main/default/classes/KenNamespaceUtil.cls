/**
 * Resolves object and Apex type names supplied by callers without the package
 * namespace.
 *
 * Inside a managed package the global describe is keyed by the namespaced API
 * name (pmken42__Ken_Event_Master__c), so Schema.getGlobalDescribe().get() on a
 * bare name returns null and the caller fails with a null dereference. Dynamic
 * SOQL is unaffected because it compiles in the namespace context; only the
 * string-keyed lookups need help.
 *
 * In an org where the source is deployed unpackaged the prefix resolves to an
 * empty string and every lookup behaves exactly as before.
 */
public with sharing class KenNamespaceUtil {

    private static final String REFERENCE_OBJECT = 'Ken_Event_Master__c';

    @TestVisible
    private static String cachedPrefix;

    /**
     * Returns the package namespace prefix including the trailing '__', or an
     * empty string when the code is not running inside a namespace. Derived from
     * a known packaged object rather than hardcoded, so it stays correct if the
     * namespace ever changes.
     */
    public static String namespacePrefix() {
        if (cachedPrefix == null) {
            String fullName = String.valueOf(Ken_Event_Master__c.SObjectType);
            cachedPrefix = fullName.length() > REFERENCE_OBJECT.length()
                ? fullName.substring(0, fullName.length() - REFERENCE_OBJECT.length())
                : '';
        }
        return cachedPrefix;
    }

    /**
     * Resolves an sObject type from an API name that may or may not carry the
     * namespace. Returns null when the name matches nothing.
     */
    public static Schema.SObjectType resolveSObjectType(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType resolved = globalDescribe.get(apiName);
        if (resolved != null) {
            return resolved;
        }
        String prefix = namespacePrefix();
        return String.isBlank(prefix) ? null : globalDescribe.get(prefix + apiName);
    }

    /**
     * Resolves the field map of an object named dynamically, or null when the
     * object cannot be resolved.
     */
    public static Map<String, Schema.SObjectField> resolveFieldMap(String apiName) {
        Schema.SObjectType resolved = resolveSObjectType(apiName);
        return resolved == null ? null : resolved.getDescribe().fields.getMap();
    }

    /**
     * Namespace-tolerant containsKey for a field map obtained from a describe.
     * Field map keys carry the package namespace (pmken42__Blood_Group__c), so a
     * bare name misses and the caller silently takes its 'field absent' branch.
     */
    public static Boolean hasField(Map<String, Schema.SObjectField> fieldMap, String fieldApiName) {
        if (fieldMap == null || String.isBlank(fieldApiName)) {
            return false;
        }
        if (fieldMap.containsKey(fieldApiName)) {
            return true;
        }
        String prefix = namespacePrefix();
        return String.isNotBlank(prefix) && fieldMap.containsKey(prefix + fieldApiName);
    }

    /**
     * Qualifies a custom object or field API name with the package namespace.
     * Standard names (no __c suffix) are returned untouched, as are names that
     * already carry the prefix. Returns the input unchanged outside a package.
     */
    public static String qualifyCustom(String apiName) {
        if (String.isBlank(apiName) || !(apiName.endsWithIgnoreCase('__c') || apiName.endsWithIgnoreCase('__r'))) {
            return apiName;
        }
        String prefix = namespacePrefix();
        if (String.isBlank(prefix) || apiName.startsWithIgnoreCase(prefix)) {
            return apiName;
        }
        return prefix + apiName;
    }

    /**
     * Resolves an Apex type from a class name that may or may not carry the
     * namespace. Returns null when the name matches nothing.
     */
    public static Type resolveType(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        Type resolved = Type.forName(className);
        if (resolved != null) {
            return resolved;
        }
        String prefix = namespacePrefix();
        return String.isBlank(prefix) ? null : Type.forName(prefix.removeEnd('__'), className);
    }
}