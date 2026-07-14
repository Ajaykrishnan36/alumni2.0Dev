/**
 * KenAudienceMetadataController
 * ------------------------------------------------------------
 * Apex controller used by the Target Audience Selection LWC.
 *
 * Current behavior (generic / starter):
 * - Returns sample multi-select picklist options by role and field key.
 *
 * Future (recommended) enhancements:
 * - Replace sample lists with dynamic values from Education Cloud / Alumni Cloud
 *   "Attribute" objects, Custom Metadata, Field Sets, or Picklist Fields.
 * - Add methods to persist selected audience payload into a custom object
 *   (e.g., Target_Audience__c) when the wizard is submitted.
 *
 * Best practices:
 * - @AuraEnabled(cacheable=true) is used for read-only metadata methods.
 * - Defensive checks ensure invalid object/field names return empty results.
 */
public with sharing class KenAudienceMetadataController {

    /**
     * Lightweight DTO for LWC picklist options.
     */
    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /**
     * Returns multi-select option lists for the requested role.
     * The returned map is keyed by fieldKey (the LWC field config key).
     *
     * Example return:
     * {
     *   "academicYear": [ {label:"2025-26", value:"2025-26"}, ... ],
     *   "program": [...]
     * }
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Option>> getRoleAttributeOptions(String role) {
        if (String.isBlank(role)) {
            return new Map<String, List<Option>>();
        }

        // Normalize role key
        String r = role.trim().toUpperCase();

        // NOTE: These are sample values. Replace with dynamic data later.
        if (r == 'STUDENT') {
            return new Map<String, List<Option>>{
                'academicYear' => options(new List<String>{ '2025 - 26', '2024 - 25', '2023 - 24' }),
                'program' => options(new List<String>{ 'Computer Science', 'Business Administration', 'Design', 'Law' }),
                'school' => options(new List<String>{ 'School of Engineering', 'School of Business', 'School of Arts' }),
                'department' => options(new List<String>{ 'Business', 'Finance', 'Computer Science', 'Mechanical' }),
                'campus' => options(new List<String>{ 'Main Campus', 'North Campus' }),
                'status' => options(new List<String>{ 'Active', 'Former' })
            };
        } else if (r == 'ALUMNI') {
            return new Map<String, List<Option>>{
                'graduationYear' => options(new List<String>{ '2025', '2024', '2023', '2022', '2021' }),
                'degree' => options(new List<String>{ 'B.Tech', 'BBA', 'MBA', 'M.Tech', 'PhD' }),
                'school' => options(new List<String>{ 'School of Engineering', 'School of Business', 'School of Arts' }),
                'department' => options(new List<String>{ 'Business', 'Finance', 'Computer Science', 'Mechanical' }),
                'campus' => options(new List<String>{ 'Main Campus', 'North Campus' }),
                'status' => options(new List<String>{ 'Active', 'Inactive' })
                // currentLocation is search-based (free text), so no options needed
            };
        } else if (r == 'PARENT') {
            return new Map<String, List<Option>>{
                'parentsOf' => options(new List<String>{ 'Students', 'Applicants' }),
                'childSchool' => options(new List<String>{ 'School of Engineering', 'School of Business' }),
                'childProgram' => options(new List<String>{ 'Computer Science', 'Business Administration' }),
                'childGradYear' => options(new List<String>{ '2026', '2025', '2024' }),
                'status' => options(new List<String>{ 'Active', 'Inactive' })
            };
        } else if (r == 'FACULTY') {
            return new Map<String, List<Option>>{
                'school' => options(new List<String>{ 'School of Engineering', 'School of Business', 'School of Arts' }),
                'department' => options(new List<String>{ 'Computer Science', 'Mechanical', 'Finance', 'HR' }),
                'campus' => options(new List<String>{ 'Main Campus', 'North Campus' }),
                'employmentType' => options(new List<String>{ 'Full-time', 'Adjunct', 'Visiting' }),
                'status' => options(new List<String>{ 'Active', 'Inactive' })
            };
        } else if (r == 'STAFF') {
            return new Map<String, List<Option>>{
                'department' => options(new List<String>{ 'Admissions', 'Operations', 'IT', 'Finance' }),
                'campus' => options(new List<String>{ 'Main Campus', 'North Campus' }),
                'status' => options(new List<String>{ 'Active', 'Inactive' })
            };
        } else if (r == 'ORG') {
            return new Map<String, List<Option>>{
                'university' => options(new List<String>{ 'Kenverse University', 'Turbostart Institute' }),
                'school' => options(new List<String>{ 'School of Engineering', 'School of Business' }),
                'department' => options(new List<String>{ 'Computer Science', 'Finance', 'Operations' }),
                'program' => options(new List<String>{ 'Placement Partners', 'Internship Partners' })
            };
        } else if (r == 'OTHERS') {
            return new Map<String, List<Option>>{
                'category' => options(new List<String>{ 'Vendors', 'Guests', 'Mentors' }),
                'campus' => options(new List<String>{ 'Main Campus', 'North Campus' }),
                'status' => options(new List<String>{ 'Active', 'Inactive' })
            };
        }

        return new Map<String, List<Option>>();
    }

    /**
     * Generic helper to read picklist values from Salesforce metadata.
     * Useful when you later map your role fields to actual Object + Field API names.
     */
    @AuraEnabled(cacheable=true)
    public static List<Option> getPicklistValues(String objectApiName, String fieldApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return new List<Option>();
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType sobjectType = globalDescribe.get(objectApiName.trim());
        if (sobjectType == null) {
            return new List<Option>();
        }

        Schema.DescribeSObjectResult dor = sobjectType.getDescribe();
        Map<String, Schema.SObjectField> fields = dor.fields.getMap();
        Schema.SObjectField field = fields.get(fieldApiName.trim());
        if (field == null) {
            return new List<Option>();
        }

        Schema.DescribeFieldResult fdr = field.getDescribe();
        // Supports both Picklist and MultiPicklist types
        if (fdr.getType() != Schema.DisplayType.Picklist && fdr.getType() != Schema.DisplayType.MultiPicklist) {
            return new List<Option>();
        }

        List<Option> out = new List<Option>();
        for (Schema.PicklistEntry pe : fdr.getPicklistValues()) {
            if (pe == null) continue;
            out.add(new Option(pe.getLabel(), pe.getValue()));
        }
        return out;
    }

    /**
     * Small factory to convert List<String> into List<Option>.
     */
    private static List<Option> options(List<String> values) {
        List<Option> out = new List<Option>();
        if (values == null) {
            return out;
        }
        for (String v : values) {
            if (String.isBlank(v)) continue;
            out.add(new Option(v, v));
        }
        return out;
    }

    /**
     * Stubbed save hook for the Target Audience payload.
     * Replace with real persistence logic when ready.
     */
    @AuraEnabled
    public static Boolean saveAudienceSelection(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            return false;
        }
        return true;
    }

    /**
     * Stubbed delete hook for a saved group.
     * Replace with real delete logic when ready.
     */
    @AuraEnabled
    public static Boolean deleteSavedGroup(String groupId) {
        if (String.isBlank(groupId)) {
            return false;
        }
        return true;
    }
}