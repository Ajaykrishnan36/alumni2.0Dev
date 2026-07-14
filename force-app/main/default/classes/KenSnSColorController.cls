/**
 * KenSnSColorController
 *
 * Returns primary/secondary portal colors for the Support & Services module
 * by reading the Ken_Support_Services_Parameters__c org-default custom setting.
 *
 * Falls back to KenConstantController defaults if the setting is missing or
 * holds an invalid hex value.
 */
public with sharing class KenSnSColorController {

    @TestVisible
    static Boolean forceExceptionForTesting = false;

    public class ColorResponse {
        @AuraEnabled public String primary;
        @AuraEnabled public String secondary;
    }

    /**
     * Returns the configured Support & Services portal colors. Cacheable so
     * LWCs can wire this without hitting the DB on every render.
     */
    @AuraEnabled(cacheable=true)
    public static ColorResponse getColors() {
        if (forceExceptionForTesting) {
            throw new IllegalArgumentException('Test exception for catch block coverage');
        }

        // Read from Ken_Support_Services_Parameters__c custom setting.
        // When no record exists OR fields are blank/invalid, return null —
        // the LWC then leaves the CSS variable unset so CSS falls back
        // to its own hardcoded values (the orange theme in each component).
        Ken_Support_Services_Parameters__c setting = Ken_Support_Services_Parameters__c.getOrgDefaults();
        ColorResponse response = new ColorResponse();

        response.primary = sanitizeHexColor(
            setting == null ? null : setting.Primary_Color__c,
            null
        );
        response.secondary = sanitizeHexColor(
            setting == null ? null : setting.Secondary_Color__c,
            null
        );
        return response;
    }

    /**
     * Validates and normalizes a hex color value.
     * Accepts colors with or without the leading '#'.
     * Returns the fallback when the input is blank or not a valid 6-digit hex.
     */
    @TestVisible
    private static String sanitizeHexColor(String inputColor, String fallbackColor) {
        if (String.isBlank(inputColor)) {
            return fallbackColor;
        }
        String value = inputColor.trim();
        if (!value.startsWith('#')) {
            value = '#' + value;
        }
        if (Pattern.matches('^#([0-9a-fA-F]{6})$', value)) {
            return value;
        }
        return fallbackColor;
    }
}