/**
 * KenAudienceEngineService
 *
 * Author: KEN42 Product
 * Created by: Sasi Naik
 *
 * Service layer for audience metadata, search, save, and segmentation payloads.
 * Includes dynamic SOQL generation for Account counts based on audience criteria.
 */
public without sharing class KenAudienceEngineService {

    // ==========================================================
    // CONFIG (update if needed)
    // ==========================================================
    private static final String CATEGORY_OBJ          = 'AttributeCategory';
    private static final String DISTRIBUTION_OBJ      = 'AttributeDefinition';

    // AttributeCategory fields
    private static final String CATEGORY_ROLE_FIELD   = 'Code';
    private static final String CATEGORY_ACTIVE_FIELD = 'Active__c'; // optional
    private static final String CATEGORY_TARGET_OBJ   = 'Target_Object__c'; // optional
    private static final String CATEGORY_FIELDSET     = 'Field_Set__c'; // optional

    // AttributeDefinition fields
    private static final String DIST_CATEGORY_LOOKUP  = 'Attribute_Category__c';
    private static final String DIST_FIELD_LABEL      = 'Label';
    private static final String DIST_FIELD_API        = 'DeveloperName'; // must match Account field API name
    private static final String DIST_DATA_TYPE        = 'DataType';
    private static final String DIST_ACTIVE_FIELD     = 'IsActive'; // optional

    // Ken_Segmentation__c fields
    private static final String SEG_OBJ               = 'Ken_Segmentation__c';
    private static final String SEG_JSON_FIELD        = 'Definition_JSON__c';
    private static final String SEG_SOQL_FIELD        = 'SOQL__c';
    private static final String SEG_ACTIVE_FIELD      = 'Active__c';
    private static final String SEG_STATUS_FIELD      = 'Status__c'; // optional
    private static final String SEG_TARGET_ROLE_FIELD = 'Target_Role__c'; // optional, not required for deploy
    private static final String SEG_DESC_FIELD        = 'Description__c'; // optional
    private static final String SEG_TARGET_OBJECT     = 'Target_Object__c'; // optional
    private static final String SEG_TARGET_ACCOUNT    = 'Target_Account__c'; // optional
    private static final String SEG_TARGET_CONTACT    = 'Target_Contact__c'; // optional

    private static final String DEFAULT_TARGET_OBJECT = 'ConstituentRole';
    private static final String DEFAULT_FIELDSET      = 'AudienceFilters';

    // ==========================================================
    // DTOs
    // ==========================================================
    public class OptionDTO {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public OptionDTO(String value, String label) { this.value = value; this.label = label; }
    }

    public class CategoryDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String targetRole;
    }

    public class DistributionFieldDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public String dataType;
        @AuraEnabled public List<OptionDTO> picklistValues;

        // helpful for debugging / grouping
        @AuraEnabled public Id categoryId;
        @AuraEnabled public String categoryName;
    }

    public class RoleContextDTO {
        @AuraEnabled public List<CategoryDTO> categories;
        @AuraEnabled public List<DistributionFieldDTO> fields;
        @AuraEnabled public String targetObject;
        @AuraEnabled public String fieldSetName;
    }

    public class FilterDTO {
        @AuraEnabled public String id;        // UI row id
        @AuraEnabled public String fieldApi;  // Account field API name
        @AuraEnabled public String operator;  // =, !=, >, <, >=, <=, contains, startsWith, in
        @AuraEnabled public String value;     // free input (IN = comma-separated)
        @AuraEnabled public String dataType;  // hint from AttributeDefinition.DataType
    }

    public class AudienceRequestDTO {
        @AuraEnabled public String audienceName;
        @AuraEnabled public String description;
        @AuraEnabled public String targetRole;
        @AuraEnabled public Boolean active;
        @AuraEnabled public String targetObject;
        @AuraEnabled public Id targetAccountId;
        @AuraEnabled public Id targetContactId;

        @AuraEnabled public String matchMode;    // AND / OR / CUSTOM
        @AuraEnabled public String customLogic;  // "1 AND (2 OR 3)"
        @AuraEnabled public List<FilterDTO> filters;
    }

    public class PersonRowDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String subtitle;
    }

    public class AudiencePreviewDTO {
        @AuraEnabled public Integer count;
        @AuraEnabled public List<PersonRowDTO> sample;
        @AuraEnabled public List<String> pills;
    }

    public class SavedAudienceDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Integer memberCount;
        @AuraEnabled public String payloadJson;
    }

    public class AudienceCountDTO {
        @AuraEnabled public String id;
        @AuraEnabled public Integer count;
    }

    public class AudienceGroupDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public String groupType;
        @AuraEnabled public Integer memberCount;
        @AuraEnabled public String membersLabel;
    }

    public class SavedGroupCriteriaDTO {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public List<String> values;
    }

    public class SavedGroupDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String role;
        @AuraEnabled public String roleLabel;
        @AuraEnabled public String title;
        @AuraEnabled public String type;
        @AuraEnabled public String membersLabel;
        @AuraEnabled public List<SavedGroupCriteriaDTO> criteria;
    }

    public class RoleCategoryDTO {
        @AuraEnabled public String code;
        @AuraEnabled public String name;
    }

    public class FieldConfigDTO {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String placeholder;
        @AuraEnabled public String type;
        @AuraEnabled public List<OptionDTO> options;
        @AuraEnabled public String fieldApi;
        @AuraEnabled public String objectApi;
        @AuraEnabled public String joinField;
    }

    private class SoqlBuildResult {
        public String whereClause;
        public List<String> pills = new List<String>();
    }

    private class FieldPathInfo {
        public String baseObjectApi;
        public String objectApi;
        public String fieldApi;
        public String resolvedPath;
        public String firstLookupApi;
        public Integer relationshipHops = 0;
        public Schema.DescribeFieldResult fieldDescribe;
    }

    // ==========================================================
    // 1) Target Roles from PICKLIST METADATA
    // ==========================================================
    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> getTargetRoles() {
        assertObjectAndFieldsExist();

        Schema.SObjectType sType = globalDescribe().get(CATEGORY_OBJ);
        Map<String, Schema.SObjectField> fMap = sType.getDescribe().fields.getMap();
        Schema.DescribeFieldResult dfr = fMap.get(CATEGORY_ROLE_FIELD).getDescribe();

        if (dfr.getType() == Schema.DisplayType.PICKLIST || dfr.getType() == Schema.DisplayType.MULTIPICKLIST) {
            List<String> keys = new List<String>();
            Map<String, OptionDTO> byKey = new Map<String, OptionDTO>();

            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (!pe.isActive()) continue;
                OptionDTO opt = new OptionDTO(pe.getValue(), pe.getLabel());
                String key = (pe.getLabel() == null ? pe.getValue() : pe.getLabel()) + '|' + pe.getValue();
                keys.add(key);
                byKey.put(key, opt);
            }
            keys.sort();

            List<OptionDTO> out = new List<OptionDTO>();
            for (String k : keys) out.add(byKey.get(k));
            return out;
        }

        // Fallback (only if the field is NOT a picklist)
        List<OptionDTO> fallback = new List<OptionDTO>();
        String soql =
            'SELECT ' + CATEGORY_ROLE_FIELD + ' role FROM ' + CATEGORY_OBJ +
            ' WHERE ' + CATEGORY_ROLE_FIELD + ' != null GROUP BY ' + CATEGORY_ROLE_FIELD + ' ORDER BY ' + CATEGORY_ROLE_FIELD;

        for (AggregateResult ar : (List<AggregateResult>)Database.query(soql)) {
            String v = (String)ar.get('role');
            if (!String.isBlank(v)) fallback.add(new OptionDTO(v, v));
        }
        return fallback;
    }

    // ==========================================================
    // 1b) Active AttributeCategory roles (Code + Name)
    // ==========================================================
    @AuraEnabled(cacheable=true)
    public static List<RoleCategoryDTO> getActiveRoleCategories() {
        String soql = 'SELECT ' + CATEGORY_ROLE_FIELD + ', Name FROM ' + CATEGORY_OBJ;
        if (fieldExists(CATEGORY_OBJ, CATEGORY_ACTIVE_FIELD)) {
            soql += ' WHERE ' + CATEGORY_ACTIVE_FIELD + ' = true';
        }
        if (fieldExists(CATEGORY_OBJ, 'Sort_Order__c')) {
            soql += ' ORDER BY Sort_Order__c, Name';
        } else {
            soql += ' ORDER BY Name';
        }

        List<RoleCategoryDTO> out = new List<RoleCategoryDTO>();
        for (SObject row : Database.query(soql)) {
            String code = (String)row.get(CATEGORY_ROLE_FIELD);
            String name = (String)row.get('Name');
            if (String.isBlank(code) || String.isBlank(name)) {
                continue;
            }
            RoleCategoryDTO dto = new RoleCategoryDTO();
            dto.code = code;
            dto.name = name;
            out.add(dto);
        }
        return out;
    }

    // ==========================================================
    // 1c) Role fields + values from AttributeDefinition
    // ==========================================================
    @AuraEnabled(cacheable=true)
    public static List<FieldConfigDTO> getRoleFieldOptions(String role) {
        if (String.isBlank(role)) {
            return new List<FieldConfigDTO>();
        }

        String r = role.trim();
        String catSoql = 'SELECT Id, Name, ' + CATEGORY_ROLE_FIELD;
        if (fieldExists(CATEGORY_OBJ, 'Sort_Order__c')) {
            catSoql += ', Sort_Order__c';
        }
        if (fieldExists(CATEGORY_OBJ, CATEGORY_TARGET_OBJ)) {
            catSoql += ', ' + CATEGORY_TARGET_OBJ;
        }
        catSoql += ' FROM ' + CATEGORY_OBJ;
        if (fieldExists(CATEGORY_OBJ, CATEGORY_ACTIVE_FIELD)) {
            catSoql += ' WHERE ' + CATEGORY_ACTIVE_FIELD + ' = true';
            catSoql += ' AND (' + CATEGORY_ROLE_FIELD + ' = :r OR Name = :r)';
        } else {
            catSoql += ' WHERE ' + CATEGORY_ROLE_FIELD + ' = :r OR Name = :r';
        }
        if (fieldExists(CATEGORY_OBJ, 'Sort_Order__c')) {
            catSoql += ' ORDER BY Sort_Order__c, Name';
        } else {
            catSoql += ' ORDER BY Name';
        }

        List<SObject> categories = Database.query(catSoql);
        if (categories.isEmpty()) {
            return new List<FieldConfigDTO>();
        }

        List<Id> catIds = new List<Id>();
        Map<Id, String> targetByCatId = new Map<Id, String>();
        for (SObject c : categories) {
            Id cid = (Id)c.get('Id');
            if (cid != null) catIds.add(cid);
            if (fieldExists(CATEGORY_OBJ, CATEGORY_TARGET_OBJ)) {
                String tgt = (String)c.get(CATEGORY_TARGET_OBJ);
                if (!String.isBlank(tgt)) {
                    targetByCatId.put(cid, tgt);
                }
            }
        }

        if (!fieldExists(DISTRIBUTION_OBJ, DIST_CATEGORY_LOOKUP)) {
            return new List<FieldConfigDTO>();
        }

        List<String> defSelect = new List<String>{ 'Id', 'Name', DIST_CATEGORY_LOOKUP };
        if (fieldExists(DISTRIBUTION_OBJ, 'DeveloperName')) defSelect.add('DeveloperName');
        if (fieldExists(DISTRIBUTION_OBJ, 'Label')) defSelect.add('Label');
        if (fieldExists(DISTRIBUTION_OBJ, 'Object_API_Name__c')) defSelect.add('Object_API_Name__c');
        if (fieldExists(DISTRIBUTION_OBJ, 'Field_API_Name__c')) defSelect.add('Field_API_Name__c');
        if (fieldExists(DISTRIBUTION_OBJ, 'Join_Field__c')) defSelect.add('Join_Field__c');
        if (fieldExists(DISTRIBUTION_OBJ, 'Order__c')) defSelect.add('Order__c');
        if (fieldExists(CATEGORY_OBJ, 'Sort_Order__c')) defSelect.add('Attribute_Category__r.Sort_Order__c');

        String defSoql =
            'SELECT ' + String.join(defSelect, ', ') +
            ' FROM ' + DISTRIBUTION_OBJ +
            ' WHERE ' + DIST_CATEGORY_LOOKUP + ' IN :catIds';
        if (fieldExists(DISTRIBUTION_OBJ, DIST_ACTIVE_FIELD)) {
            defSoql += ' AND ' + DIST_ACTIVE_FIELD + ' = true';
        }

        List<String> orderParts = new List<String>();
        if (fieldExists(CATEGORY_OBJ, 'Sort_Order__c')) orderParts.add('Attribute_Category__r.Sort_Order__c');
        if (fieldExists(DISTRIBUTION_OBJ, 'Order__c')) orderParts.add('Order__c');
        if (fieldExists(DISTRIBUTION_OBJ, 'Label')) {
            orderParts.add('Label');
        } else {
            orderParts.add('Name');
        }
        defSoql += ' ORDER BY ' + String.join(orderParts, ', ');

        List<FieldConfigDTO> out = new List<FieldConfigDTO>();

        for (SObject def : Database.query(defSoql)) {
            String objectApi = fieldExists(DISTRIBUTION_OBJ, 'Object_API_Name__c')
                ? (String)def.get('Object_API_Name__c')
                : null;
            String fieldApi = fieldExists(DISTRIBUTION_OBJ, 'Field_API_Name__c')
                ? (String)def.get('Field_API_Name__c')
                : null;
            String label = fieldExists(DISTRIBUTION_OBJ, 'Label')
                ? (String)def.get('Label')
                : null;
            String developerName = fieldExists(DISTRIBUTION_OBJ, 'DeveloperName')
                ? (String)def.get('DeveloperName')
                : null;
            String categoryTargetObject = null;
            if (fieldExists(CATEGORY_OBJ, CATEGORY_TARGET_OBJ)) {
                Id catId = (Id)def.get(DIST_CATEGORY_LOOKUP);
                categoryTargetObject = targetByCatId.get(catId);
            }
            if (String.isBlank(fieldApi)) {
                fieldApi = developerName;
            }

            FieldConfigDTO dto = new FieldConfigDTO();
            dto.key = !String.isBlank(developerName) ? developerName :
                (!String.isBlank(fieldApi) ? fieldApi : label);
            dto.label = !String.isBlank(label) ? label : (String)def.get('Name');
            dto.placeholder = 'Choose';
            dto.type = 'multiselect';
            dto.options = new List<OptionDTO>();
            dto.fieldApi = fieldApi;
            dto.objectApi = !String.isBlank(objectApi) ? objectApi : categoryTargetObject;
            if (String.isBlank(dto.objectApi)) {
                dto.objectApi = DEFAULT_TARGET_OBJECT;
            }
            dto.joinField = fieldExists(DISTRIBUTION_OBJ, 'Join_Field__c')
                ? (String)def.get('Join_Field__c')
                : null;

            if (!String.isBlank(dto.objectApi) && !String.isBlank(dto.fieldApi)) {
                FieldPathInfo info = resolveFieldPathInfo(dto.objectApi, dto.fieldApi);
                Schema.DescribeFieldResult fr = info == null ? null : info.fieldDescribe;
                if (info != null && !String.isBlank(info.resolvedPath)) {
                    dto.fieldApi = info.resolvedPath;
                }
                if (fr != null &&
                    (fr.getType() == Schema.DisplayType.PICKLIST || fr.getType() == Schema.DisplayType.MULTIPICKLIST)) {
                    for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
                        if (pe == null || !pe.isActive()) continue;
                        dto.options.add(new OptionDTO(pe.getValue(), pe.getLabel()));
                    }
                } else {
                    dto.type = 'search';
                }
            }
            out.add(dto);
        }

        return out;
    }

    @AuraEnabled
    public static List<OptionDTO> searchDistinctFieldValues(String objectApi, String fieldApi, String searchTerm, Integer limitSize) {
        List<OptionDTO> out = new List<OptionDTO>();
        if (String.isBlank(objectApi) || String.isBlank(fieldApi)) {
            return out;
        }

        FieldPathInfo info = resolveFieldPathInfo(objectApi, fieldApi);
        if (info == null || info.fieldDescribe == null) {
            return out;
        }

        Integer limitVal = (limitSize != null && limitSize > 0) ? Math.min(limitSize, 200) : 50;
        String term = (searchTerm == null) ? '' : searchTerm.trim();

        if (info.fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
            return queryReferenceOptions(info, term, limitVal);
        }

        Boolean useLike = !String.isBlank(term) && isTextSearchable(info.fieldDescribe);
        String queryObject = info.objectApi;
        String queryField = info.fieldApi;
        Boolean useSemiJoin = info.relationshipHops == 1
            && !String.isBlank(info.firstLookupApi)
            && info.baseObjectApi != info.objectApi;

        try {
            Boolean useGroupBy = info.fieldDescribe.isGroupable();
            if (useGroupBy) {
                String soql =
                    'SELECT ' + queryField + ' FROM ' + queryObject +
                    ' WHERE ' + queryField + ' != null';
                if (useLike) {
                    soql += ' AND ' + queryField + ' LIKE ' + toSoqlString('%' + escapeLike(term) + '%');
                }
                if (useSemiJoin) {
                    soql += ' AND Id IN (SELECT ' + info.firstLookupApi + ' FROM ' + info.baseObjectApi +
                        ' WHERE ' + info.firstLookupApi + ' != null)';
                }
                soql += ' GROUP BY ' + queryField + ' ORDER BY ' + queryField + ' LIMIT ' + limitVal;

                for (AggregateResult ar : (List<AggregateResult>)Database.query(soql)) {
                    Object val = ar.get(queryField);
                    if (val == null) continue;
                    String label = String.valueOf(val);
                    if (String.isBlank(label)) continue;
                    out.add(new OptionDTO(label, label));
                }
            } else {
                String soql =
                    'SELECT ' + queryField + ' FROM ' + queryObject +
                    ' WHERE ' + queryField + ' != null';
                if (useLike) {
                    soql += ' AND ' + queryField + ' LIKE ' + toSoqlString('%' + escapeLike(term) + '%');
                }
                if (useSemiJoin) {
                    soql += ' AND Id IN (SELECT ' + info.firstLookupApi + ' FROM ' + info.baseObjectApi +
                        ' WHERE ' + info.firstLookupApi + ' != null)';
                }
                Integer fetchLimit = Math.min(limitVal * 5, 500);
                soql += ' LIMIT ' + fetchLimit;

                Set<String> seen = new Set<String>();
                for (SObject row : Database.query(soql)) {
                    Object val = row.get(queryField);
                    if (val == null) continue;
                    String label = String.valueOf(val);
                    if (String.isBlank(label) || seen.contains(label)) continue;
                    seen.add(label);
                    out.add(new OptionDTO(label, label));
                    if (out.size() >= limitVal) break;
                }
            }
        } catch (Exception e) {
            // Ignore invalid field path or access issues; keep options empty.
        }

        return out;
    }

    private static Boolean isTextSearchable(Schema.DescribeFieldResult fr) {
        if (fr == null) return false;
        Schema.DisplayType t = fr.getType();
        return t == Schema.DisplayType.STRING ||
            t == Schema.DisplayType.TEXTAREA ||
            t == Schema.DisplayType.EMAIL ||
            t == Schema.DisplayType.PHONE ||
            t == Schema.DisplayType.URL ||
            t == Schema.DisplayType.PICKLIST ||
            t == Schema.DisplayType.MULTIPICKLIST;
    }

    private static String getNameFieldApi(String objectApi) {
        if (String.isBlank(objectApi)) return null;
        Schema.SObjectType sType = globalDescribe().get(objectApi);
        if (sType == null) return null;
        Map<String, Schema.SObjectField> fMap = sType.getDescribe().fields.getMap();
        if (fMap.containsKey('Name')) return 'Name';
        for (String key : fMap.keySet()) {
            Schema.DescribeFieldResult fr = fMap.get(key).getDescribe();
            if (fr != null && fr.isNameField()) {
                return key;
            }
        }
        return null;
    }

    private static List<OptionDTO> queryReferenceOptions(FieldPathInfo info, String searchTerm, Integer limitSize) {
        List<OptionDTO> out = new List<OptionDTO>();
        if (info == null || info.fieldDescribe == null) return out;
        List<Schema.SObjectType> refs = info.fieldDescribe.getReferenceTo();
        if (refs == null || refs.isEmpty()) return out;
        String refObjectApi = refs[0].getDescribe().getName();
        String nameField = getNameFieldApi(refObjectApi);
        if (String.isBlank(nameField)) return out;

        Integer limitVal = (limitSize != null && limitSize > 0) ? Math.min(limitSize, 200) : 50;
        String term = (searchTerm == null) ? '' : searchTerm.trim();

        String soql =
            'SELECT Id, ' + nameField + ' FROM ' + refObjectApi +
            ' WHERE Id IN (SELECT ' + info.fieldApi + ' FROM ' + info.objectApi +
            ' WHERE ' + info.fieldApi + ' != null';

        if (info.relationshipHops == 1 && !String.isBlank(info.firstLookupApi) && info.baseObjectApi != info.objectApi) {
            soql += ' AND Id IN (SELECT ' + info.firstLookupApi + ' FROM ' + info.baseObjectApi +
                ' WHERE ' + info.firstLookupApi + ' != null)';
        }
        soql += ')';

        if (!String.isBlank(term)) {
            soql += ' AND ' + nameField + ' LIKE ' + toSoqlString('%' + escapeLike(term) + '%');
        }
        soql += ' ORDER BY ' + nameField + ' LIMIT ' + limitVal;

        try {
            for (SObject row : Database.query(soql)) {
                String idVal = String.valueOf(row.get('Id'));
                Object nameRaw = row.get(nameField);
                String nameVal = nameRaw == null ? idVal : String.valueOf(nameRaw);
                if (String.isBlank(idVal)) continue;
                out.add(new OptionDTO(idVal, nameVal));
            }
        } catch (Exception e) {
            // Ignore invalid field path or access issues; keep options empty.
        }
        return out;
    }

    private static FieldPathInfo resolveFieldPathInfo(String objectApi, String fieldPath) {
        if (String.isBlank(objectApi) || String.isBlank(fieldPath)) return null;
        Map<String, Schema.SObjectType> gd = globalDescribe();
        Schema.SObjectType current = gd.get(objectApi);
        if (current == null) return null;

        List<String> parts = fieldPath.split('\\.');
        if (parts.isEmpty()) return null;

        FieldPathInfo info = new FieldPathInfo();
        info.baseObjectApi = objectApi;
        info.objectApi = objectApi;
        List<String> normalizedParts = new List<String>();

        for (Integer i = 0; i < parts.size(); i++) {
            String part = parts[i];
            Map<String, Schema.SObjectField> fMap = current.getDescribe().fields.getMap();

            if (i == parts.size() - 1) {
                String lastPart = resolveFieldApiFromMap(fMap, part);
                if (String.isBlank(lastPart)) return null;
                info.objectApi = current.getDescribe().getName();
                info.fieldApi = lastPart;
                info.fieldDescribe = fMap.get(lastPart).getDescribe();
                normalizedParts.add(lastPart);
                info.resolvedPath = String.join(normalizedParts, '.');
                return info;
            }

            String lookupApi = resolveLookupApiFromRelationshipPart(fMap, part);
            if (String.isBlank(lookupApi)) return null;
            if (info.firstLookupApi == null) {
                info.firstLookupApi = lookupApi;
            }
            Schema.DescribeFieldResult fr = fMap.get(lookupApi).getDescribe();
            List<Schema.SObjectType> refs = fr.getReferenceTo();
            if (refs == null || refs.isEmpty()) return null;
            String relationshipName = fr.getRelationshipName();
            if (String.isBlank(relationshipName)) {
                if (lookupApi.endsWith('__c')) {
                    relationshipName = lookupApi.substring(0, lookupApi.length() - 3) + '__r';
                } else if (lookupApi.endsWith('Id')) {
                    relationshipName = lookupApi.substring(0, lookupApi.length() - 2);
                } else {
                    relationshipName = part;
                }
            }
            normalizedParts.add(relationshipName);
            current = refs[0];
            info.relationshipHops++;
        }
        return null;
    }

    private static String resolveLookupApiFromRelationshipPart(Map<String, Schema.SObjectField> fieldMap, String rawPart) {
        if (fieldMap == null || String.isBlank(rawPart)) return null;

        List<String> candidates = new List<String>();
        candidates.add(rawPart);
        if (rawPart.endsWith('__r')) {
            candidates.add(rawPart.substring(0, rawPart.length() - 3) + '__c');
        } else if (rawPart.endsWith('_r')) {
            candidates.add(rawPart.substring(0, rawPart.length() - 2) + '__c');
        } else if (!rawPart.endsWith('__c') && !rawPart.endsWith('Id')) {
            candidates.add(rawPart + 'Id');
        }
        if (rawPart.endsWith('_c')) {
            candidates.add(rawPart.substring(0, rawPart.length() - 2) + '__c');
        }

        for (String c : candidates) {
            String key = findFieldApiIgnoreCase(fieldMap, c);
            if (String.isBlank(key)) continue;
            Schema.DescribeFieldResult fr = fieldMap.get(key).getDescribe();
            List<Schema.SObjectType> refs = fr == null ? null : fr.getReferenceTo();
            if (refs != null && !refs.isEmpty()) {
                return key;
            }
        }

        for (String key : fieldMap.keySet()) {
            Schema.DescribeFieldResult fr = fieldMap.get(key).getDescribe();
            List<Schema.SObjectType> refs = fr == null ? null : fr.getReferenceTo();
            if (refs == null || refs.isEmpty()) continue;
            String relationshipName = fr.getRelationshipName();
            String normalizedRelPart = rawPart.endsWith('_r')
                ? rawPart.substring(0, rawPart.length() - 2) + '__r'
                : rawPart;
            if (!String.isBlank(relationshipName) &&
                (relationshipName.equalsIgnoreCase(rawPart) || relationshipName.equalsIgnoreCase(normalizedRelPart))) {
                return key;
            }
        }
        return null;
    }

    private static String resolveFieldApiFromMap(Map<String, Schema.SObjectField> fieldMap, String rawPart) {
        if (fieldMap == null || String.isBlank(rawPart)) return null;

        List<String> candidates = new List<String>();
        candidates.add(rawPart);
        if (rawPart.endsWith('_c')) {
            candidates.add(rawPart.substring(0, rawPart.length() - 2) + '__c');
        } else if (rawPart.endsWith('__c')) {
            candidates.add(rawPart.substring(0, rawPart.length() - 3));
        } else {
            candidates.add(rawPart + '__c');
        }

        for (String c : candidates) {
            String key = findFieldApiIgnoreCase(fieldMap, c);
            if (!String.isBlank(key)) {
                return key;
            }
        }
        return null;
    }

    private static String findFieldApiIgnoreCase(Map<String, Schema.SObjectField> fieldMap, String candidate) {
        if (fieldMap == null || String.isBlank(candidate)) return null;
        if (fieldMap.containsKey(candidate)) return candidate;
        for (String key : fieldMap.keySet()) {
            if (key.equalsIgnoreCase(candidate)) return key;
        }
        return null;
    }

    // ==========================================================
    // 1b) Constituent Role picklist values (RoleType)
    // ==========================================================
    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> getConstituentRoleOptions() {
        Schema.SObjectType sType = globalDescribe().get('ConstituentRole');
        if (sType == null) {
            return new List<OptionDTO>();
        }
        Map<String, Schema.SObjectField> fMap = sType.getDescribe().fields.getMap();
        if (!fMap.containsKey('RoleType')) {
            return new List<OptionDTO>();
        }

        Schema.DescribeFieldResult dfr = fMap.get('RoleType').getDescribe();
        List<OptionDTO> out = new List<OptionDTO>();
        if (dfr.getType() == Schema.DisplayType.PICKLIST || dfr.getType() == Schema.DisplayType.MULTIPICKLIST) {
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe == null || !pe.isActive()) continue;
                out.add(new OptionDTO(pe.getValue(), pe.getLabel()));
            }
        }
        return out;
    }


    // ==========================================================
    // 2) Role Context: categories (by role) + fields (by categoryIds)
    // ==========================================================
    @AuraEnabled(cacheable=true)
    public static RoleContextDTO getRoleContext(String targetRole) {
        assertObjectAndFieldsExist();
        if (String.isBlank(targetRole)) {
            RoleContextDTO empty = new RoleContextDTO();
            empty.categories = new List<CategoryDTO>();
            empty.fields = new List<DistributionFieldDTO>();
            empty.targetObject = DEFAULT_TARGET_OBJECT;
            empty.fieldSetName = DEFAULT_FIELDSET;
            return empty;
        }

        String catWhere = ' WHERE ' + CATEGORY_ROLE_FIELD + ' = :targetRole';
        if (fieldExists(CATEGORY_OBJ, CATEGORY_ACTIVE_FIELD)) {
            catWhere += ' AND ' + CATEGORY_ACTIVE_FIELD + ' = true';
        }

        // 1) Query AttributeCategory by selected role and capture IDs
        String catSoql = 'SELECT Id, Name, ' + CATEGORY_ROLE_FIELD;
        if (fieldExists(CATEGORY_OBJ, CATEGORY_TARGET_OBJ)) catSoql += ', ' + CATEGORY_TARGET_OBJ;
        if (fieldExists(CATEGORY_OBJ, CATEGORY_FIELDSET)) catSoql += ', ' + CATEGORY_FIELDSET;
        catSoql += ' FROM ' + CATEGORY_OBJ + catWhere + ' ORDER BY Name';
        List<SObject> catRows = Database.query(catSoql);

        List<Id> catIds = new List<Id>();
        Map<Id, String> catNameById = new Map<Id, String>();

        List<CategoryDTO> cats = new List<CategoryDTO>();
        String targetObject = null;
        String fieldSetName = null;
        for (SObject c : catRows) {
            Id cid = (Id)c.get('Id');
            catIds.add(cid);
            catNameById.put(cid, (String)c.get('Name'));

            CategoryDTO dto = new CategoryDTO();
            dto.id = cid;
            dto.name = (String)c.get('Name');
            dto.targetRole = (String)c.get(CATEGORY_ROLE_FIELD);
            cats.add(dto);

            if (targetObject == null && fieldExists(CATEGORY_OBJ, CATEGORY_TARGET_OBJ)) {
                targetObject = (String)c.get(CATEGORY_TARGET_OBJ);
            }
            if (fieldSetName == null && fieldExists(CATEGORY_OBJ, CATEGORY_FIELDSET)) {
                fieldSetName = (String)c.get(CATEGORY_FIELDSET);
            }
        }

        if (String.isBlank(targetObject)) targetObject = DEFAULT_TARGET_OBJECT;
        if (String.isBlank(fieldSetName)) fieldSetName = DEFAULT_FIELDSET;

        // 2) Gather fields from the configured field set
        Map<String, Schema.SObjectType> gd = globalDescribe();
        Schema.SObjectType targetType = gd.get(targetObject);
        if (targetType == null) {
            throw new AuraHandledException('Invalid target object: ' + targetObject);
        }

        Map<String, Schema.SObjectField> targetFields = targetType.getDescribe().fields.getMap();
        Set<String> fieldSetApis = new Set<String>(); // now driven solely by AttributeDefinition rows

        // 2) Query AttributeDefinition for those category IDs
        Map<String, SObject> defByApi = new Map<String, SObject>();
        Set<Id> picklistIds = new Set<Id>();
        if (!catIds.isEmpty()) {
            String defWhere = ' WHERE ' + DIST_CATEGORY_LOOKUP + ' IN :catIds';
            if (fieldExists(DISTRIBUTION_OBJ, DIST_ACTIVE_FIELD)) {
                defWhere += ' AND ' + DIST_ACTIVE_FIELD + ' = true';
            }

            String defSoql =
                'SELECT Id, ' + DIST_FIELD_LABEL + ', ' + DIST_FIELD_API + ', ' + DIST_DATA_TYPE + ', Field_API_Name__c, ' + DIST_CATEGORY_LOOKUP +
                ' FROM ' + DISTRIBUTION_OBJ + defWhere +
                ' ORDER BY ' + DIST_FIELD_LABEL;

            for (SObject d : Database.query(defSoql)) {
                String api = (String)d.get(DIST_FIELD_API);
                if (String.isBlank(api)) {
                    api = (String)d.get('Field_API_Name__c');
                }
                if (String.isBlank(api)) continue;

                defByApi.put(api, d);
                if (fieldExists(DISTRIBUTION_OBJ, 'PicklistId')) {
                    Id pid = (Id)d.get('PicklistId');
                    if (pid != null) picklistIds.add(pid);
                }
            }
        }

        fieldSetApis.addAll(defByApi.keySet());

        Map<Id, List<OptionDTO>> picklistValuesById = new Map<Id, List<OptionDTO>>();
        if (!picklistIds.isEmpty()) {
            String pvSoql = 'SELECT PicklistId, Value, DisplayValue, Sequence FROM AttributePicklistValue' +
                ' WHERE PicklistId IN :picklistIds';
            if (fieldExists('AttributePicklistValue', 'Status')) {
                pvSoql += ' AND Status = \'Active\'';
            }
            pvSoql += ' ORDER BY Sequence';

            for (SObject pv : Database.query(pvSoql)) {
                Id pid = (Id)pv.get('PicklistId');
                String val = (String)pv.get('Value');
                String label = (String)pv.get('DisplayValue');
                if (String.isBlank(label)) label = val;

                if (!picklistValuesById.containsKey(pid)) {
                    picklistValuesById.put(pid, new List<OptionDTO>());
                }
                picklistValuesById.get(pid).add(new OptionDTO(val, label));
            }
        }

        // 3) Merge fieldset + AttributeDefinition into DTOs
        List<DistributionFieldDTO> fields = new List<DistributionFieldDTO>();
        for (String api : fieldSetApis) {
            Schema.DescribeFieldResult fr = null;
            if (targetFields.containsKey(api)) {
                fr = targetFields.get(api).getDescribe();
            }
            // If the field doesn't exist on the base object (e.g., relationship path),
            // still surface it with minimal metadata.
            if (fr != null && (!fr.isAccessible() || !fr.isFilterable())) continue;

            DistributionFieldDTO f = new DistributionFieldDTO();
            f.apiName = api;
            f.label = (fr == null) ? api : fr.getLabel();
            f.dataType = (fr == null) ? 'Text' : normalizeType(fr.getType());

            if (defByApi.containsKey(api)) {
                SObject d = defByApi.get(api);
                f.id = (Id)d.get('Id');

                String defLabel = (String)d.get(DIST_FIELD_LABEL);
                if (!String.isBlank(defLabel)) f.label = defLabel;

                String defType = (String)d.get(DIST_DATA_TYPE);
                if (!String.isBlank(defType)) f.dataType = defType;

                f.categoryId = (Id)d.get(DIST_CATEGORY_LOOKUP);
                f.categoryName = catNameById.get(f.categoryId);

                if (fieldExists(DISTRIBUTION_OBJ, 'PicklistId')) {
                    Id pid = (Id)d.get('PicklistId');
                    if (pid != null && picklistValuesById.containsKey(pid)) {
                        f.picklistValues = picklistValuesById.get(pid);
                    }
                }
            }

            if (fr != null && f.picklistValues == null && (fr.getType() == Schema.DisplayType.Picklist || fr.getType() == Schema.DisplayType.MultiPicklist)) {
                f.picklistValues = new List<OptionDTO>();
                for (Schema.PicklistEntry pe : fr.getPicklistValues()) {
                    if (pe == null || !pe.isActive()) continue;
                    f.picklistValues.add(new OptionDTO(pe.getValue(), pe.getLabel()));
                }
            }

            fields.add(f);
        }

        fields.sort(new DistributionFieldComparator());

        RoleContextDTO out = new RoleContextDTO();
        out.categories = cats;
        out.fields = fields;
        out.targetObject = targetObject;
        out.fieldSetName = fieldSetName;
        return out;
    }


    // ==========================================================
    // 3) Preview Audience
    // ==========================================================
    @AuraEnabled
    public static AudiencePreviewDTO preview(String requestJson) {
        AudienceRequestDTO req = (AudienceRequestDTO)JSON.deserialize(requestJson, AudienceRequestDTO.class);
        validateRequest(req, false);

        String targetObject = DEFAULT_TARGET_OBJECT;
        if (!String.isBlank(req.targetObject) && req.targetObject == DEFAULT_TARGET_OBJECT) {
            targetObject = req.targetObject;
        }

        SoqlBuildResult built = buildWhere(targetObject, req.matchMode, req.customLogic, req.filters);

        String whereClause = String.isBlank(built.whereClause) ? '' : (' WHERE ' + built.whereClause);
        Integer total = (Integer)((List<AggregateResult>)Database.query('SELECT COUNT(Id) c FROM ' + targetObject + whereClause))[0].get('c');

        List<String> sampleFields = new List<String>{ 'Id', 'Name' };
        List<SObject> rows = new List<SObject>();
        try {
            sampleFields.add('Person.Name');
            sampleFields.add('Person.PersonEmail');
            rows = Database.query(
                'SELECT ' + String.join(sampleFields, ',') + ' FROM ' + targetObject + whereClause +
                ' ORDER BY LastModifiedDate DESC LIMIT 10'
            );
        } catch (Exception e) {
            rows = Database.query(
                'SELECT Id, Name FROM ' + targetObject + whereClause +
                ' ORDER BY LastModifiedDate DESC LIMIT 10'
            );
        }

        AudiencePreviewDTO out = new AudiencePreviewDTO();
        out.count = total;
        out.pills = built.pills;
        out.sample = new List<PersonRowDTO>();

        for (SObject row : rows) {
            PersonRowDTO p = new PersonRowDTO();
            p.id = (Id)row.get('Id');
            p.name = (String)row.get('Name');
            SObject person = row.getSObject('Person');
            p.email = (person == null) ? null : (String)person.get('PersonEmail');
            out.sample.add(p);
        }
        return out;
    }

    // ==========================================================
    // 3b) Specific Individuals search
    // ==========================================================
    @AuraEnabled(cacheable=true)
    public static List<PersonRowDTO> searchSpecificIndividuals(
        String role,
        String searchTerm,
        Map<String, Object> filters,
        String targetObject,
        Integer limitSize
    ) {
        String term = String.isBlank(searchTerm) ? '' : searchTerm.trim();
        if (String.isBlank(term) && (filters == null || filters.isEmpty())) {
            return new List<PersonRowDTO>();
        }

        Integer maxRows = (limitSize == null || limitSize <= 0) ? 20 : limitSize;
        if (maxRows > 200) maxRows = 200;
        return searchSpecificIndividualsOnConstituentRole(role, term, filters, maxRows);
    }

    private static List<PersonRowDTO> searchSpecificIndividualsOnConstituentRole(
        String role,
        String term,
        Map<String, Object> filters,
        Integer maxRows
    ) {
        List<PersonRowDTO> out = new List<PersonRowDTO>();
        Schema.SObjectType roleType = globalDescribe().get(DEFAULT_TARGET_OBJECT);
        if (roleType == null) {
            return out;
        }
        Map<String, Schema.SObjectField> roleFields = roleType.getDescribe().fields.getMap();

        if (!roleFields.containsKey('PersonId')) {
            return out;
        }

        List<String> selectFields = new List<String>{ 'Id', 'Name', 'PersonId' };
        if (roleFields.containsKey('RoleType')) {
            selectFields.add('RoleType');
        }

        Schema.SObjectType accountType = globalDescribe().get('Account');
        Map<String, Schema.SObjectField> accountFields = accountType == null
            ? new Map<String, Schema.SObjectField>()
            : accountType.getDescribe().fields.getMap();
        String accountEmailField = accountFields.containsKey('PersonEmail')
            ? 'PersonEmail'
            : (accountFields.containsKey('Email') ? 'Email' : null);
        List<String> accountPhoneFields = new List<String>();
        for (String f : new List<String>{ 'PersonMobilePhone', 'Phone', 'PersonHomePhone', 'PersonOtherPhone' }) {
            if (accountFields.containsKey(f)) {
                accountPhoneFields.add(f);
            }
        }

        Map<String, String> advFieldMap = getAdvancedFieldMap(role);
        List<String> subtitleFields = new List<String>();
        for (String key : new List<String>{ 'program', 'department', 'school', 'campus' }) {
            String api = advFieldMap.get(key);
            if (!String.isBlank(api) && roleFields.containsKey(api)) {
                subtitleFields.add(api);
                if (!selectFields.contains(api)) selectFields.add(api);
            }
        }

        List<String> whereParts = new List<String>();
        whereParts.add('PersonId != null');
        if (!String.isBlank(role) && roleFields.containsKey('RoleType') && !role.equalsIgnoreCase('GROUPS')) {
            whereParts.add('RoleType = ' + toSoqlString(role.trim()));
        }

        Set<Id> matchingPersonIds = new Set<Id>();
        if (!String.isBlank(term)) {
            if (!accountFields.isEmpty()) {
                List<String> personSearchParts = new List<String>();
                String likeTerm = '%' + escapeLike(term) + '%';
                if (accountFields.containsKey('Name')) {
                    personSearchParts.add('Name LIKE ' + toSoqlString(likeTerm));
                }
                if (!String.isBlank(accountEmailField)) {
                    personSearchParts.add(accountEmailField + ' LIKE ' + toSoqlString(likeTerm));
                }
                for (String f : accountPhoneFields) {
                    personSearchParts.add(f + ' LIKE ' + toSoqlString(likeTerm));
                }
                if (term.length() >= 15 && term.length() <= 18) {
                    personSearchParts.add('Id = ' + toSoqlString(term));
                }
                if (!personSearchParts.isEmpty()) {
                    String personWhere = '(' + String.join(personSearchParts, ' OR ') + ')';
                    if (accountFields.containsKey('IsPersonAccount')) {
                        personWhere = '(IsPersonAccount = true) AND ' + personWhere;
                    }
                    String personSoql = 'SELECT Id FROM Account WHERE ' + personWhere + ' LIMIT 500';
                    for (SObject a : Database.query(personSoql)) {
                        Id pid = (Id)a.get('Id');
                        if (pid != null) matchingPersonIds.add(pid);
                    }
                }
            }

            List<String> searchParts = new List<String>();
            String likeTerm = '%' + escapeLike(term) + '%';
            searchParts.add('Name LIKE ' + toSoqlString(likeTerm));
            if (term.length() >= 15 && term.length() <= 18) {
                searchParts.add('Id = ' + toSoqlString(term));
                searchParts.add('PersonId = ' + toSoqlString(term));
            }
            if (roleFields.containsKey('RoleType')) {
                searchParts.add('RoleType LIKE ' + toSoqlString(likeTerm));
            }
            if (!matchingPersonIds.isEmpty()) {
                searchParts.add('PersonId IN :matchingPersonIds');
            }
            if (!searchParts.isEmpty()) {
                whereParts.add('(' + String.join(searchParts, ' OR ') + ')');
            }
        }

        if (filters != null && !filters.isEmpty()) {
            for (String key : filters.keySet()) {
                String api = advFieldMap.get(key);
                if (String.isBlank(api)) {
                    continue;
                }
                FieldPathInfo pathInfo = resolveFieldPathInfo(DEFAULT_TARGET_OBJECT, api);
                if (pathInfo == null || String.isBlank(pathInfo.resolvedPath)) {
                    continue;
                }
                String filterField = pathInfo.resolvedPath;
                List<String> values = toStringList(filters.get(key));
                if (values.isEmpty()) {
                    continue;
                }
                List<String> valueClauses = new List<String>();
                for (String v : values) {
                    if (String.isBlank(v)) continue;
                    valueClauses.add(filterField + ' LIKE ' + toSoqlString('%' + escapeLike(v.trim()) + '%'));
                }
                if (!valueClauses.isEmpty()) {
                    whereParts.add('(' + String.join(valueClauses, ' OR ') + ')');
                }
            }
        }

        String whereClause = whereParts.isEmpty() ? '' : ' WHERE ' + String.join(whereParts, ' AND ');
        String soql =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM ' + DEFAULT_TARGET_OBJECT +
            whereClause +
            ' ORDER BY LastModifiedDate DESC LIMIT ' + maxRows;

        List<SObject> roleRows = Database.query(soql);
        if (roleRows.isEmpty()) {
            return out;
        }

        Set<Id> personIds = new Set<Id>();
        for (SObject roleRow : roleRows) {
            Id pid = (Id)roleRow.get('PersonId');
            if (pid != null) personIds.add(pid);
        }
        Map<Id, SObject> peopleById = new Map<Id, SObject>();
        if (!personIds.isEmpty() && !accountFields.isEmpty()) {
            List<String> personSelectFields = new List<String>{ 'Id' };
            if (accountFields.containsKey('Name')) {
                personSelectFields.add('Name');
            }
            if (!String.isBlank(accountEmailField)) {
                personSelectFields.add(accountEmailField);
            }
            for (String f : accountPhoneFields) {
                if (!personSelectFields.contains(f)) personSelectFields.add(f);
            }
            String personDetailSoql =
                'SELECT ' + String.join(personSelectFields, ',') +
                ' FROM Account WHERE Id IN :personIds';
            for (SObject personRow : Database.query(personDetailSoql)) {
                Id idVal = (Id)personRow.get('Id');
                if (idVal != null) peopleById.put(idVal, personRow);
            }
        }

        for (SObject roleRow : roleRows) {
            SObject personRow = peopleById.get((Id)roleRow.get('PersonId'));

            PersonRowDTO dto = new PersonRowDTO();
            dto.id = (Id)roleRow.get('Id');
            dto.name = personRow == null || personRow.get('Name') == null
                ? (String)roleRow.get('Name')
                : String.valueOf(personRow.get('Name'));
            dto.email = (personRow == null || String.isBlank(accountEmailField) || personRow.get(accountEmailField) == null)
                ? null
                : String.valueOf(personRow.get(accountEmailField));
            dto.phone = (personRow == null) ? null : pickFirstPhone(personRow, accountPhoneFields);
            dto.subtitle = buildSubtitle(roleRow, subtitleFields);
            out.add(dto);
        }
        return out;
    }

    // ==========================================================
    // 4) Save Segmentation
    // ==========================================================
    @AuraEnabled
    public static Id saveSegmentation(String requestJson) {
        AudienceRequestDTO req = (AudienceRequestDTO)JSON.deserialize(requestJson, AudienceRequestDTO.class);
        validateRequest(req, true);

        ensureUniqueSegmentationName(req.audienceName, null);

        // validate filters/logic before saving JSON
        String targetObject = String.isBlank(req.targetObject) ? DEFAULT_TARGET_OBJECT : req.targetObject;
        buildWhere(targetObject, req.matchMode, req.customLogic, req.filters);

        SObject seg = globalDescribe().get(SEG_OBJ).newSObject();
        seg.put('Name', req.audienceName);

        if (fieldExists(SEG_OBJ, SEG_DESC_FIELD)) seg.put(SEG_DESC_FIELD, req.description);
        if (fieldExists(SEG_OBJ, SEG_TARGET_ROLE_FIELD)) seg.put(SEG_TARGET_ROLE_FIELD, req.targetRole);
        if (fieldExists(SEG_OBJ, SEG_ACTIVE_FIELD)) seg.put(SEG_ACTIVE_FIELD, (req.active == null ? true : req.active));
        if (fieldExists(SEG_OBJ, SEG_TARGET_OBJECT)) seg.put(SEG_TARGET_OBJECT, targetObject);
        if (fieldExists(SEG_OBJ, SEG_TARGET_ACCOUNT) && req.targetAccountId != null) seg.put(SEG_TARGET_ACCOUNT, req.targetAccountId);
        if (fieldExists(SEG_OBJ, SEG_TARGET_CONTACT) && req.targetContactId != null) seg.put(SEG_TARGET_CONTACT, req.targetContactId);

        if (!fieldExists(SEG_OBJ, SEG_JSON_FIELD)) {
            throw new AuraHandledException('Missing field ' + SEG_OBJ + '.' + SEG_JSON_FIELD);
        }
        seg.put(SEG_JSON_FIELD, requestJson);

        insert seg;
        return (Id)seg.get('Id');
    }

    // ==========================================================
    // 5) Saved Audience (Save Later / Activate)
    // ==========================================================
    @AuraEnabled
    public static Id saveAudienceForLater(String audienceName, String payloadJson) {
        return upsertAudiencePayload(null, audienceName, payloadJson, false, 'Save Later');
    }

    @AuraEnabled
    public static Id saveAudienceActive(String audienceName, String payloadJson, Id audienceId) {
        return upsertAudiencePayload(audienceId, audienceName, payloadJson, true, 'Active');
    }

    @AuraEnabled
    public static Id saveAudiencePayload(String audienceName, String payloadJson, Id audienceId, Boolean active, String statusValue) {
        return upsertAudiencePayload(audienceId, audienceName, payloadJson, active, statusValue);
    }

    @AuraEnabled(cacheable=false)
    public static List<AudienceCountDTO> getAudienceCounts(String payloadJson) {
        List<AudienceCountDTO> out = new List<AudienceCountDTO>();
        if (String.isBlank(payloadJson)) {
            return out;
        }

        Object raw = JSON.deserializeUntyped(payloadJson);
        if (!(raw instanceof Map<String, Object>)) {
            return out;
        }
        Map<String, Object> payload = (Map<String, Object>)raw;
        String targetObject = (String)payload.get('targetObject');
        if (String.isBlank(targetObject)) targetObject = DEFAULT_TARGET_OBJECT;
        Object itemsRaw = payload.get('items');
        if (!(itemsRaw instanceof List<Object>)) {
            return out;
        }
        List<Object> items = (List<Object>)itemsRaw;

        // Group items resolve their count through the SAME helper the Groups list uses, so the
        // Groups list, Selected Audience and Saved Audience can never report different numbers
        // for the same group. Batched: one pass for every group regardless of how many.
        Set<Id> groupIds = new Set<Id>();
        for (Object itemRaw : items) {
            if (!(itemRaw instanceof Map<String, Object>)) continue;
            Map<String, Object> item = (Map<String, Object>)itemRaw;
            if (isGroupItem(item)) {
                groupIds.add((Id)(String)item.get('id'));
            }
        }
        Map<Id, Integer> groupCounts = countGroupReach(groupIds, targetObject);

        for (Object itemRaw : items) {
            if (!(itemRaw instanceof Map<String, Object>)) continue;
            Map<String, Object> item = (Map<String, Object>)itemRaw;
            String id = (String)item.get('id');
            if (String.isBlank(id)) continue;

            Integer count = 0;
            if (isGroupItem(item)) {
                Integer g = groupCounts.get((Id)id);
                count = (g == null) ? 0 : g;
            } else {
                String whereClause = buildItemWhere(item, targetObject);
                try {
                    count = countAudience(targetObject, whereClause);
                } catch (Exception e) {
                    count = 0;
                }
            }
            AudienceCountDTO dto = new AudienceCountDTO();
            dto.id = id;
            dto.count = count;
            out.add(dto);
        }

        return out;
    }

    /** True when an audience item is a saved Group whose id is a real group record. */
    private static Boolean isGroupItem(Map<String, Object> item) {
        if (item == null) return false;
        String type = (String)item.get('type');
        String id = (String)item.get('id');
        return !String.isBlank(type) && type.equalsIgnoreCase('GROUP') && isLikelySalesforceId(id);
    }

    private static Integer countAudience(String targetObject, String whereClause) {
        String wc = String.isBlank(whereClause) ? '' : (' WHERE ' + whereClause);
        String anchor = resolveAnchorField(targetObject);
        if (!String.isBlank(anchor) && !anchor.equalsIgnoreCase('Id') && fieldExists(targetObject, anchor)) {
            List<AggregateResult> ars = Database.query(
                'SELECT COUNT_DISTINCT(' + anchor + ') cnt FROM ' + targetObject + wc);
            Object v = ars.isEmpty() ? null : ars[0].get('cnt');
            return (v == null) ? 0 : Integer.valueOf(v);
        }
        return Database.countQuery('SELECT COUNT() FROM ' + targetObject + wc);
    }

    @AuraEnabled(cacheable=false)
    public static List<AudienceGroupDTO> searchAudienceGroups(String searchTerm, Integer limitSize) {
        List<AudienceGroupDTO> out = new List<AudienceGroupDTO>();
        Integer maxRows = (limitSize == null || limitSize <= 0) ? 50 : limitSize;
        if (maxRows > 200) maxRows = 200;

        String term = String.isBlank(searchTerm) ? '' : searchTerm.trim();
        String soql =
            'SELECT Id, Name, Category__c, Group_Type__c, Member_Count__c ' +
            'FROM Ken_Group__c ' +
            'WHERE Is_Active__c = true AND Status__c = \'Approved\'';
        if (!String.isBlank(term)) {
            soql += ' AND Name LIKE ' + toSoqlString('%' + escapeLike(term) + '%');
        }
        soql += ' ORDER BY Member_Count__c DESC NULLS LAST, Name ASC LIMIT ' + maxRows;

        Set<Id> groupIds = new Set<Id>();
        List<Ken_Group__c> groups = (List<Ken_Group__c>)Database.query(soql);
        for (Ken_Group__c g : groups) {
            groupIds.add(g.Id);
        }

        // Live member reach for the whole list in at most two queries — the same number the
        // Selected Audience and Saved Audience screens compute, so counts never disagree.
        Map<Id, Integer> liveCounts = countGroupReach(groupIds, DEFAULT_TARGET_OBJECT);

        for (Ken_Group__c g : groups) {
            AudienceGroupDTO dto = new AudienceGroupDTO();
            dto.id = g.Id;
            dto.name = g.Name;
            dto.category = g.Category__c;
            dto.groupType = g.Group_Type__c;
            Integer live = liveCounts.get(g.Id);
            dto.memberCount = live == null ? 0 : live;
            dto.membersLabel = dto.memberCount == 1 ? '1 member' : (dto.memberCount + ' members');
            out.add(dto);
        }
        return out;
    }

    /**
     * Resolve specific groups (by id) to audience DTOs with live member reach. Used to seed a
     * pre-selected group — e.g. "Create an Event" launched from a group passes only the group id
     * in the URL, so the wizard needs the name + count to build the audience chip. Non-cacheable
     * so the count matches the live single-source reach (see countGroupReach).
     */
    @AuraEnabled
    public static List<AudienceGroupDTO> getAudienceGroupsByIds(List<Id> groupIds) {
        List<AudienceGroupDTO> out = new List<AudienceGroupDTO>();
        if (groupIds == null || groupIds.isEmpty()) {
            return out;
        }
        Set<Id> idSet = new Set<Id>(groupIds);
        List<Ken_Group__c> groups = [
            SELECT Id, Name, Category__c, Group_Type__c, Member_Count__c
            FROM Ken_Group__c
            WHERE Id IN :idSet
        ];
        Set<Id> found = new Set<Id>();
        for (Ken_Group__c g : groups) {
            found.add(g.Id);
        }
        Map<Id, Integer> liveCounts = countGroupReach(found, DEFAULT_TARGET_OBJECT);
        for (Ken_Group__c g : groups) {
            AudienceGroupDTO dto = new AudienceGroupDTO();
            dto.id = g.Id;
            dto.name = g.Name;
            dto.category = g.Category__c;
            dto.groupType = g.Group_Type__c;
            Integer live = liveCounts.get(g.Id);
            dto.memberCount = live == null ? 0 : live;
            dto.membersLabel = dto.memberCount == 1 ? '1 member' : (dto.memberCount + ' members');
            out.add(dto);
        }
        return out;
    }

    /**
     * Live member reach for a set of groups, batched into at most two queries regardless of how
     * many groups are passed. Returns, per group, the count of distinct approved members that
     * actually exist in the target population. This is identical (same Account Id set) to
     * countAudience(buildGroupClause(...)) run per group, so the Groups list, the Selected
     * Audience panel and the Saved Audience review all display the same number.
     */
    private static Map<Id, Integer> countGroupReach(Set<Id> groupIds, String targetObject) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (groupIds == null || groupIds.isEmpty()) return counts;
        for (Id gid : groupIds) counts.put(gid, 0);

        // 1) Distinct approved members per group (Member__c is a lookup to Account).
        Map<Id, Set<Id>> groupToMembers = new Map<Id, Set<Id>>();
        Set<Id> allMembers = new Set<Id>();
        for (Ken_Group_Member__c gm : [
            SELECT Group__c, Member__c
            FROM Ken_Group_Member__c
            WHERE Group__c IN :groupIds
              AND Status__c IN ('Approved', 'Invite Accepted')
              AND Member__c != null
        ]) {
            Set<Id> mem = groupToMembers.get(gm.Group__c);
            if (mem == null) {
                mem = new Set<Id>();
                groupToMembers.put(gm.Group__c, mem);
            }
            mem.add(gm.Member__c);
            allMembers.add(gm.Member__c);
        }
        if (allMembers.isEmpty()) return counts;

        // 2) Intersect with the target population via its anchor field (one query for all groups).
        String obj = String.isBlank(targetObject) ? DEFAULT_TARGET_OBJECT : targetObject;
        String anchor = resolveAnchorField(obj);
        Set<Id> valid = new Set<Id>();
        if (anchor.equalsIgnoreCase('Id') || !fieldExists(obj, anchor)) {
            // Target is keyed directly by the member Id space (or no usable anchor) — no intersection.
            valid.addAll(allMembers);
        } else {
            for (SObject row : Database.query(
                'SELECT ' + anchor + ' FROM ' + obj + ' WHERE ' + anchor + ' IN :allMembers')) {
                Object v = row.get(anchor);
                if (v != null) valid.add((Id)v);
            }
        }

        for (Id gid : groupToMembers.keySet()) {
            Integer c = 0;
            for (Id m : groupToMembers.get(gid)) {
                if (valid.contains(m)) c++;
            }
            counts.put(gid, c);
        }
        return counts;
    }

    private static String buildGroupClause(String groupId, String targetObject) {
        if (String.isBlank(groupId) || !isLikelySalesforceId(groupId)) return '';
        String obj = String.isBlank(targetObject) ? DEFAULT_TARGET_OBJECT : targetObject;
        String anchor = resolveAnchorField(obj);
        if (!anchor.equalsIgnoreCase('Id') && !fieldExists(obj, anchor)) return '';
        return anchor + ' IN (SELECT Member__c FROM Ken_Group_Member__c WHERE Group__c = ' +
            toSoqlString(groupId) + ' AND Status__c IN (\'Approved\',\'Invite Accepted\'))';
    }

    @AuraEnabled
    public static Boolean isAccountInSegmentation(Id accountId, Id segmentationId) {
        if (accountId == null || segmentationId == null) return false;
        String soql = 'SELECT Id, ' + SEG_JSON_FIELD + ' FROM ' + SEG_OBJ + ' WHERE Id = :segmentationId LIMIT 1';
        List<SObject> rows = Database.query(soql);
        if (rows.isEmpty()) return false;
        String payloadJson = (String)rows[0].get(SEG_JSON_FIELD);
        return isAccountMatchedByPayload(accountId, payloadJson);
    }

    /**
     * Resolve a saved Segmentation's payload into the set of Account Ids that match.
     * Used by the Communications module to materialise an audience snapshot for sending.
     * Skips groups/individuals/role criteria the engine cannot resolve and returns
     * an empty set rather than failing.
     */
    public static Set<Id> resolveSegmentationAccountIds(Id segmentationId) {
        Set<Id> out = new Set<Id>();
        if (segmentationId == null) return out;
        String soql = 'SELECT Id, ' + SEG_JSON_FIELD + ' FROM ' + SEG_OBJ + ' WHERE Id = :segmentationId LIMIT 1';
        List<SObject> rows = Database.query(soql);
        if (rows.isEmpty()) return out;
        String payloadJson = (String)rows[0].get(SEG_JSON_FIELD);
        return resolveAccountIdsFromPayload(payloadJson);
    }

    public static Set<Id> resolveAccountIdsFromPayload(String payloadJson) {
        Set<Id> out = new Set<Id>();
        if (String.isBlank(payloadJson)) return out;
        Object raw;
        try {
            raw = JSON.deserializeUntyped(payloadJson);
        } catch (Exception e) {
            return out;
        }
        if (!(raw instanceof Map<String, Object>)) return out;
        Map<String, Object> payload = (Map<String, Object>)raw;
        String targetObject = (String)payload.get('targetObject');
        if (String.isBlank(targetObject)) targetObject = DEFAULT_TARGET_OBJECT;
        Object itemsRaw = payload.get('items');
        if (!(itemsRaw instanceof List<Object>)) return out;

        Boolean hasPersonId = fieldExists(targetObject, 'PersonId');
        String selectField = hasPersonId ? 'PersonId' : 'Id';

        for (Object itemRaw : (List<Object>)itemsRaw) {
            if (!(itemRaw instanceof Map<String, Object>)) continue;
            Map<String, Object> item = (Map<String, Object>)itemRaw;

            String whereClause = buildItemWhere(item, targetObject);
            String soql = 'SELECT ' + selectField + ' FROM ' + targetObject;
            if (!String.isBlank(whereClause)) {
                soql += ' WHERE ' + whereClause;
            }
            soql += ' LIMIT 50000';
            try {
                for (SObject row : Database.query(soql)) {
                    Object val = hasPersonId ? row.get('PersonId') : row.get('Id');
                    if (val != null) out.add((Id)val);
                }
            } catch (Exception e) {
                // Skip malformed item; keep aggregating others
            }
        }
        return out;
    }

    // ==========================================================
    // Batch support: per-item base-object queries + count refresh
    // ==========================================================

    private static String loadSegmentationPayload(Id segmentationId) {
        if (segmentationId == null) return '';
        List<SObject> rows = Database.query(
            'SELECT ' + SEG_JSON_FIELD + ' FROM ' + SEG_OBJ + ' WHERE Id = :segmentationId LIMIT 1');
        return rows.isEmpty() ? '' : (String)rows[0].get(SEG_JSON_FIELD);
    }

    public static String getSegmentationBaseObject(Id segmentationId) {
        return targetObjectFromPayload(loadSegmentationPayload(segmentationId));
    }

    public static String getSegmentationAnchorField(Id segmentationId) {
        return resolveAnchorField(getSegmentationBaseObject(segmentationId));
    }

    private static String targetObjectFromPayload(String payloadJson) {
        if (String.isBlank(payloadJson)) return DEFAULT_TARGET_OBJECT;
        try {
            Object raw = JSON.deserializeUntyped(payloadJson);
            if (raw instanceof Map<String, Object>) {
                String t = (String)((Map<String, Object>)raw).get('targetObject');
                if (!String.isBlank(t)) return t;
            }
        } catch (Exception e) { /* default below */ }
        return DEFAULT_TARGET_OBJECT;
    }

    /**
     * One base-object SOQL per audience item: SELECT Id [, <anchor>] FROM base WHERE <itemWhere>.
     * Each is a single, valid query (semi-joins stay top-level), so a Batch can stream it via a
     * QueryLocator at any scale. Items are returned separately because their union (OR of semi-joins)
     * can't be expressed in one query - the batch unions the ids in Apex across items.
     */
    public static List<String> buildAudienceItemQueries(Id segmentationId) {
        List<String> out = new List<String>();
        String payloadJson = loadSegmentationPayload(segmentationId);
        if (String.isBlank(payloadJson)) return out;

        Object raw;
        try { raw = JSON.deserializeUntyped(payloadJson); } catch (Exception e) { return out; }
        if (!(raw instanceof Map<String, Object>)) return out;
        Map<String, Object> payload = (Map<String, Object>)raw;
        String targetObject = targetObjectFromPayload(payloadJson);
        Object itemsRaw = payload.get('items');
        if (!(itemsRaw instanceof List<Object>)) return out;

        String anchor = resolveAnchorField(targetObject);
        String selectClause = (!String.isBlank(anchor) && !anchor.equalsIgnoreCase('Id') && fieldExists(targetObject, anchor))
            ? 'SELECT Id, ' + anchor : 'SELECT Id';

        for (Object itemRaw : (List<Object>)itemsRaw) {
            if (!(itemRaw instanceof Map<String, Object>)) continue;
            String w = buildItemWhere((Map<String, Object>)itemRaw, targetObject);
            String soql = selectClause + ' FROM ' + targetObject;
            if (!String.isBlank(w)) soql += ' WHERE ' + w;
            out.add(soql);
        }
        return out;
    }

    /** Store the last resolved audience size on the segmentation (best-effort). */
    public static void updateSegmentationCount(Id segmentationId, Integer memberCount) {
        if (segmentationId == null || !fieldExists(SEG_OBJ, 'Member_Count__c')) return;
        try {
            SObject seg = globalDescribe().get(SEG_OBJ).newSObject(segmentationId);
            seg.put('Member_Count__c', memberCount);
            update seg;
        } catch (Exception e) { }
    }

    /**
     * Recompute the live audience size (distinct people) and store it on the segmentation.
     * Exact for audiences up to the 50k row read; very large audiences are sized by the batch.
     */
    @AuraEnabled
    public static Integer refreshSegmentationCount(Id segmentationId) {
        String payloadJson = loadSegmentationPayload(segmentationId);
        if (String.isBlank(payloadJson)) return 0;
        Integer count = resolveAccountIdsFromPayload(payloadJson).size();
        updateSegmentationCount(segmentationId, count);
        return count;
    }

    public static Boolean isAccountMatchedByPayload(Id accountId, String payloadJson) {
        if (accountId == null || String.isBlank(payloadJson)) return false;
        Object raw;
        try {
            raw = JSON.deserializeUntyped(payloadJson);
        } catch (Exception e) {
            return false;
        }
        if (!(raw instanceof Map<String, Object>)) return false;
        Map<String, Object> payload = (Map<String, Object>)raw;
        String targetObject = (String)payload.get('targetObject');
        if (String.isBlank(targetObject)) targetObject = DEFAULT_TARGET_OBJECT;
        Object itemsRaw = payload.get('items');
        if (!(itemsRaw instanceof List<Object>)) return false;

        String anchor = resolveAnchorField(targetObject); // e.g. PersonId, or Id when base IS the entity

        for (Object itemRaw : (List<Object>)itemsRaw) {
            if (!(itemRaw instanceof Map<String, Object>)) continue;
            Map<String, Object> item = (Map<String, Object>)itemRaw;

            String whereClause = buildItemWhere(item, targetObject);
            String soql = 'SELECT COUNT() FROM ' + targetObject + ' WHERE ' + anchor + ' = :accountId';
            if (!String.isBlank(whereClause)) {
                soql += ' AND ' + whereClause;
            }
            try {
                if (Database.countQuery(soql) > 0) return true;
            } catch (Exception e) {
                // ignore malformed clauses for individual items
            }
        }
        return false;
    }

    @AuraEnabled(cacheable=false)
    public static List<SavedAudienceDTO> searchSavedAudiences(String searchTerm) {
        assertObjectAndFieldsExist();

        List<SObject> rows = querySavedAudiences(searchTerm, 25);
        List<SavedAudienceDTO> out = new List<SavedAudienceDTO>();
        for (SObject row : rows) {
            SavedAudienceDTO dto = new SavedAudienceDTO();
            dto.id = (Id)row.get('Id');
            dto.name = (String)row.get('Name');
            dto.payloadJson = (String)row.get(SEG_JSON_FIELD);
            Integer accurate = accurateMemberCount(dto.payloadJson);
            dto.memberCount = (accurate != null) ? accurate : countMembersFromPayload(dto.payloadJson);
            out.add(dto);
        }
        return out;
    }

    @AuraEnabled(cacheable=false)
    public static SavedAudienceDTO getSavedAudienceDetail(Id audienceId) {
        if (audienceId == null) {
            return null;
        }
        List<SObject> rows = querySavedAudiences(null, null, audienceId);
        if (rows.isEmpty()) {
            return null;
        }
        SObject row = rows[0];
        SavedAudienceDTO dto = new SavedAudienceDTO();
        dto.id = (Id)row.get('Id');
        dto.name = (String)row.get('Name');
        dto.payloadJson = (String)row.get(SEG_JSON_FIELD);
        // Use the same live, de-duplicated count the saved-audience list uses so the
        // review-before-add count matches the list (and the engine's real reach). Only fall
        // back to the stored label sum if the live count can't be computed.
        Integer accurate = accurateMemberCount(dto.payloadJson);
        dto.memberCount = (accurate != null) ? accurate : countMembersFromPayload(dto.payloadJson);
        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static List<SavedGroupDTO> getSavedGroupsForRole(String role) {
        if (String.isBlank(role)) {
            return new List<SavedGroupDTO>();
        }
        String r = role.trim().toUpperCase();

        String soql = 'SELECT Id, Name, ' + SEG_JSON_FIELD + ' FROM ' + SEG_OBJ;
        if (fieldExists(SEG_OBJ, SEG_STATUS_FIELD)) {
            soql += ' WHERE ' + SEG_STATUS_FIELD + ' IN (\'Save Later\', \'Active\')';
        }
        soql += ' ORDER BY LastModifiedDate DESC';

        List<SObject> rows = Database.query(soql);
        List<SavedGroupDTO> out = new List<SavedGroupDTO>();

        for (SObject row : rows) {
            String payloadJson = (String)row.get(SEG_JSON_FIELD);
            if (String.isBlank(payloadJson)) continue;
            Object raw = JSON.deserializeUntyped(payloadJson);
            if (!(raw instanceof Map<String, Object>)) continue;

            Map<String, Object> payload = (Map<String, Object>)raw;
            Object itemsRaw = payload.get('items');
            if (!(itemsRaw instanceof List<Object>)) continue;

            for (Object itemRaw : (List<Object>)itemsRaw) {
                if (!(itemRaw instanceof Map<String, Object>)) continue;
                Map<String, Object> item = (Map<String, Object>)itemRaw;

                String type = (String)item.get('type');
                if (type == null || type.toUpperCase() != 'CUSTOM') continue;

                String itemRole = ((String)item.get('role'));
                if (String.isBlank(itemRole) || itemRole.trim().toUpperCase() != r) continue;

                SavedGroupDTO dto = new SavedGroupDTO();
                dto.id = (Id)row.get('Id');
                dto.role = itemRole;
                dto.roleLabel = (String)item.get('roleLabel');
                dto.title = (String)item.get('title');
                dto.type = 'CUSTOM';
                dto.membersLabel = (String)item.get('membersLabel');

                List<SavedGroupCriteriaDTO> criteria = new List<SavedGroupCriteriaDTO>();
                Object critRaw = item.get('criteria');
                if (critRaw instanceof List<Object>) {
                    for (Object cRaw : (List<Object>)critRaw) {
                        if (!(cRaw instanceof Map<String, Object>)) continue;
                        Map<String, Object> cMap = (Map<String, Object>)cRaw;
                        SavedGroupCriteriaDTO cDto = new SavedGroupCriteriaDTO();
                        cDto.key = (String)cMap.get('key');
                        cDto.label = (String)cMap.get('label');
                        cDto.values = toStringList(cMap.get('values'));
                        criteria.add(cDto);
                    }
                }
                dto.criteria = criteria;
                out.add(dto);
            }
        }

        return out;
    }

    @AuraEnabled
    public static Boolean activateSavedAudience(Id audienceId) {
        if (audienceId == null) {
            return false;
        }
        SObject seg = globalDescribe().get(SEG_OBJ).newSObject(audienceId);
        if (fieldExists(SEG_OBJ, SEG_ACTIVE_FIELD)) {
            seg.put(SEG_ACTIVE_FIELD, true);
        }
        if (fieldExists(SEG_OBJ, SEG_STATUS_FIELD)) {
            seg.put(SEG_STATUS_FIELD, 'Active');
        }
        update seg;
        return true;
    }

    // ==========================================================
    // Validation + Schema
    // ==========================================================
    private static void validateRequest(AudienceRequestDTO req, Boolean requireNameAndRole) {
        if (req == null) throw new AuraHandledException('Invalid request payload.');
        if (req.filters == null) req.filters = new List<FilterDTO>();
        if (String.isBlank(req.matchMode)) req.matchMode = 'AND';

        if (requireNameAndRole) {
            if (String.isBlank(req.audienceName)) throw new AuraHandledException('Audience Name is required.');
            if (String.isBlank(req.targetRole)) throw new AuraHandledException('Target Role is required.');
        }

        if (req.matchMode != null && req.matchMode.toUpperCase() == 'CUSTOM' && String.isBlank(req.customLogic)) {
            throw new AuraHandledException('Custom logic is required when Match Mode = Custom.');
        }
    }

    private static void assertObjectAndFieldsExist() {
        Map<String, Schema.SObjectType> gd = globalDescribe();
        if (!gd.containsKey(CATEGORY_OBJ)) throw new AuraHandledException('Missing object: ' + CATEGORY_OBJ);
        if (!gd.containsKey(DISTRIBUTION_OBJ)) throw new AuraHandledException('Missing object: ' + DISTRIBUTION_OBJ);
        if (!gd.containsKey(SEG_OBJ)) throw new AuraHandledException('Missing object: ' + SEG_OBJ);

        assertFieldExists(CATEGORY_OBJ, CATEGORY_ROLE_FIELD);

        assertFieldExists(DISTRIBUTION_OBJ, DIST_CATEGORY_LOOKUP);
        assertFieldExists(DISTRIBUTION_OBJ, DIST_FIELD_LABEL);
        assertFieldExists(DISTRIBUTION_OBJ, DIST_FIELD_API);
        assertFieldExists(DISTRIBUTION_OBJ, DIST_DATA_TYPE);

        assertFieldExists(SEG_OBJ, SEG_JSON_FIELD);
        assertFieldExists(SEG_OBJ, SEG_SOQL_FIELD);
    }

    private static Map<String, Schema.SObjectType> GLOBAL_DESCRIBE;
    private static final Map<String, Map<String, Schema.SObjectField>> FIELD_MAP_CACHE =
        new Map<String, Map<String, Schema.SObjectField>>();

    private static Map<String, Schema.SObjectType> globalDescribe() {
        if (GLOBAL_DESCRIBE == null) GLOBAL_DESCRIBE = Schema.getGlobalDescribe();
        return GLOBAL_DESCRIBE;
    }

    private static Map<String, Schema.SObjectField> fieldMapFor(String objApi) {
        if (String.isBlank(objApi)) return null;
        if (!FIELD_MAP_CACHE.containsKey(objApi)) {
            Schema.SObjectType t = globalDescribe().get(objApi);
            FIELD_MAP_CACHE.put(objApi, (t == null) ? null : t.getDescribe().fields.getMap());
        }
        return FIELD_MAP_CACHE.get(objApi);
    }

    private static Boolean fieldExists(String objApi, String fieldApi) {
        if (String.isBlank(fieldApi)) return false;
        Map<String, Schema.SObjectField> fm = fieldMapFor(objApi);
        return fm != null && fm.containsKey(fieldApi);
    }

    private static void assertFieldExists(String objApi, String fieldApi) {
        if (!fieldExists(objApi, fieldApi)) {
            throw new AuraHandledException('Missing field: ' + objApi + '.' + fieldApi);
        }
    }

    // ==========================================================
    // SOQL Builder (safe literals)
    // ==========================================================
    private static SoqlBuildResult buildWhere(String targetObject, String matchMode, String customLogic, List<FilterDTO> filters) {
        SoqlBuildResult out = new SoqlBuildResult();
        if (filters == null || filters.isEmpty()) {
            out.whereClause = '';
            return out;
        }

        Schema.SObjectType sType = globalDescribe().get(targetObject);
        if (sType == null) throw new AuraHandledException('Invalid target object: ' + targetObject);
        Map<String, Schema.SObjectField> fm = sType.getDescribe().fields.getMap();

        List<String> clauses = new List<String>();

        for (Integer i = 0; i < filters.size(); i++) {
            FilterDTO f = filters[i];

            if (String.isBlank(f.fieldApi)) throw new AuraHandledException('Filter #' + (i+1) + ': Field is required.');
            if (String.isBlank(f.operator)) throw new AuraHandledException('Filter #' + (i+1) + ': Operator is required.');

            Schema.DescribeFieldResult fr = resolveFieldDescribe(targetObject, f.fieldApi);
            if (fr != null) {
                if (!fr.isAccessible()) throw new AuraHandledException('Filter #' + (i+1) + ': No access to ' + f.fieldApi);
                if (!fr.isFilterable()) throw new AuraHandledException('Filter #' + (i+1) + ': Not filterable: ' + f.fieldApi);
            }

            String clause = buildClause(f, fr);
            clauses.add(clause);

            String pillLabel = (fr != null ? fr.getLabel() : f.fieldApi);
            out.pills.add(pillLabel + ' ' + f.operator + ' ' + (f.value == null ? '' : f.value));
        }

        String mode = String.valueOf(matchMode).toUpperCase();
        if (mode == 'OR') {
            out.whereClause = joinWrapped(clauses, ' OR ');
        } else if (mode == 'CUSTOM') {
            out.whereClause = buildCustomLogic(customLogic, clauses);
        } else {
            out.whereClause = joinWrapped(clauses, ' AND ');
        }
        return out;
    }

    private static String joinWrapped(List<String> clauses, String joiner) {
        List<String> w = new List<String>();
        for (String c : clauses) w.add('(' + c + ')');
        return String.join(w, joiner);
    }

    private static String buildClause(FilterDTO f, Schema.DescribeFieldResult fr) {
        String op = String.valueOf(f.operator).toLowerCase();
        Schema.DisplayType actualType = (fr == null) ? null : fr.getType();

        if (op == 'includes' || op == 'excludes') {
            if (String.isBlank(f.value)) throw new AuraHandledException('Value required for ' + op + '.');
            String verb = (op == 'includes') ? 'INCLUDES' : 'EXCLUDES';
            List<String> parts = f.value.split(',');
            List<String> literals = new List<String>();
            for (String p : parts) {
                String raw = (p == null) ? null : p.trim();
                if (String.isBlank(raw)) continue;
                literals.add(toSoqlLiteral(raw));
            }
            if (literals.isEmpty()) throw new AuraHandledException(op + ' requires at least one value.');
            return f.fieldApi + ' ' + verb + ' (' + String.join(literals, ',') + ')';
        }

        if (op == 'in') {
            if (String.isBlank(f.value)) throw new AuraHandledException('IN requires comma-separated values.');
            List<String> parts = f.value.split(',');
            List<String> literals = new List<String>();

            for (String p : parts) {
                String raw = (p == null) ? null : p.trim();
                if (String.isBlank(raw)) continue;
                Object typed = parseTyped(raw, f.dataType, actualType);
                literals.add(toSoqlLiteral(typed));
            }
            if (literals.isEmpty()) throw new AuraHandledException('IN requires at least one value.');
            return f.fieldApi + ' IN (' + String.join(literals, ',') + ')';
        }

        if (op == 'contains') {
            if (String.isBlank(f.value)) throw new AuraHandledException('Value required for contains.');
            return f.fieldApi + ' LIKE ' + toSoqlString('%' + escapeLike(f.value) + '%');
        }

        if (op == 'startswith') {
            if (String.isBlank(f.value)) throw new AuraHandledException('Value required for startsWith.');
            return f.fieldApi + ' LIKE ' + toSoqlString(escapeLike(f.value) + '%');
        }

        if (op != '=' && op != '!=' && op != '>' && op != '>=' && op != '<' && op != '<=') {
            throw new AuraHandledException('Unsupported operator: ' + f.operator);
        }
        if (String.isBlank(f.value)) throw new AuraHandledException('Value required.');

        Object typedValue = parseTyped(f.value.trim(), f.dataType, actualType);
        return f.fieldApi + ' ' + op + ' ' + toSoqlLiteral(typedValue);
    }

    private static Object parseTyped(String raw, String typeHint, Schema.DisplayType actualType) {
        String v = (raw == null) ? null : raw.trim();
        if (String.isBlank(v)) return null;

        String hints = (typeHint == null) ? '' : typeHint.trim().toLowerCase();

        if (hints == 'boolean')  return (v.toLowerCase() == 'true' || v == '1' || v.toLowerCase() == 'yes');
        if (hints == 'date')     return Date.valueOf(v);
        if (hints == 'datetime') return Datetime.valueOf(v);
        if (hints == 'integer')  return Integer.valueOf(v);
        if (hints == 'number' || hints == 'decimal' || hints == 'currency' || hints == 'percent') return Decimal.valueOf(v);

        if (actualType == Schema.DisplayType.BOOLEAN) return (v.toLowerCase() == 'true' || v == '1' || v.toLowerCase() == 'yes');
        if (actualType == Schema.DisplayType.DATE)    return Date.valueOf(v);
        if (actualType == Schema.DisplayType.INTEGER) return Integer.valueOf(v);
        if (actualType == Schema.DisplayType.DOUBLE ||
            actualType == Schema.DisplayType.CURRENCY ||
            actualType == Schema.DisplayType.PERCENT) return Decimal.valueOf(v);

        return v;
    }

    private static String toSoqlLiteral(Object typed) {
        if (typed == null) return 'NULL';
        if (typed instanceof Boolean)  return ((Boolean)typed) ? 'true' : 'false';
        if (typed instanceof Integer)  return String.valueOf((Integer)typed);
        if (typed instanceof Decimal)  return String.valueOf((Decimal)typed);
        if (typed instanceof Date)     return ((Date)typed).toString();
        if (typed instanceof Datetime) return ((Datetime)typed).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        return toSoqlString(String.valueOf(typed));
    }

    private static String toSoqlString(String s) {
        return '\'' + String.escapeSingleQuotes(s) + '\'';
    }

    private static String escapeLike(String s) {
        if (s == null) return null;
        String out = s.replace('\\', '\\\\');
        out = out.replace('%', '\\%');
        out = out.replace('_', '\\_');
        return out;
    }

    private static String buildCustomLogic(String customLogic, List<String> clauses) {
        if (String.isBlank(customLogic)) throw new AuraHandledException('Custom logic is empty.');

        String expr = customLogic.trim();
        if (!Pattern.compile('^[0-9\\s\\(\\)AaNnDdOoRr]+$').matcher(expr).matches()) {
            throw new AuraHandledException('Custom logic contains invalid characters.');
        }

        Matcher m = Pattern.compile('(?i)(\\d+|\\(|\\)|AND|OR)').matcher(expr);
        List<String> tokens = new List<String>();
        while (m.find()) tokens.add(m.group(0));
        if (tokens.isEmpty()) throw new AuraHandledException('Custom logic is invalid.');

        List<String> rebuilt = new List<String>();
        for (String t : tokens) {
            String up = t.toUpperCase();
            if (up == 'AND' || up == 'OR' || t == '(' || t == ')') {
                rebuilt.add((up == 'AND' || up == 'OR') ? up : t);
                continue;
            }
            Integer idx = Integer.valueOf(t);
            if (idx < 1 || idx > clauses.size()) {
                throw new AuraHandledException('Custom logic references #' + idx + ' but only ' + clauses.size() + ' filters exist.');
            }
            rebuilt.add('(' + clauses[idx - 1] + ')');
        }
        return String.join(rebuilt, ' ');
    }

    private static List<SObject> querySavedAudiences(String searchTerm, Integer limitSize) {
        return querySavedAudiences(searchTerm, limitSize, null);
    }

    private static List<SObject> querySavedAudiences(String searchTerm, Integer limitSize, Id audienceId) {
        List<String> clauses = new List<String>();

        if (audienceId != null) {
            clauses.add('Id = :audienceId');
        }

        String term = String.isBlank(searchTerm) ? '' : searchTerm.trim();
        if (!String.isBlank(term)) {
            String likeTerm = '%' + escapeLike(term) + '%';
            List<String> searchClauses = new List<String>();
            searchClauses.add('Name LIKE ' + toSoqlString(likeTerm));
            if (term.length() >= 15 && term.length() <= 18) {
                searchClauses.add('Id = ' + toSoqlString(term));
            }
            clauses.add('(' + String.join(searchClauses, ' OR ') + ')');
        }

        String soql = 'SELECT Id, Name, ' + SEG_JSON_FIELD;
        if (fieldExists(SEG_OBJ, SEG_STATUS_FIELD)) soql += ', ' + SEG_STATUS_FIELD;
        if (fieldExists(SEG_OBJ, SEG_ACTIVE_FIELD)) soql += ', ' + SEG_ACTIVE_FIELD;
        soql += ' FROM ' + SEG_OBJ;

        if (!clauses.isEmpty()) {
            soql += ' WHERE ' + String.join(clauses, ' AND ');
        }
        soql += ' ORDER BY LastModifiedDate DESC';
        if (limitSize != null && limitSize > 0) {
            soql += ' LIMIT ' + limitSize;
        }
        return Database.query(soql);
    }

    private static Id upsertAudiencePayload(Id audienceId, String audienceName, String payloadJson, Boolean active, String statusValue) {
        if (String.isBlank(audienceName)) {
            audienceName = 'Saved Audience';
        }
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Payload is required.');
        }

        assertObjectAndFieldsExist();
        ensureUniqueSegmentationName(audienceName, audienceId);

        SObject seg = (audienceId == null)
            ? globalDescribe().get(SEG_OBJ).newSObject()
            : globalDescribe().get(SEG_OBJ).newSObject(audienceId);

        seg.put('Name', audienceName);

        if (fieldExists(SEG_OBJ, SEG_ACTIVE_FIELD) && active != null) {
            seg.put(SEG_ACTIVE_FIELD, active);
        }
        if (fieldExists(SEG_OBJ, SEG_STATUS_FIELD) && !String.isBlank(statusValue)) {
            seg.put(SEG_STATUS_FIELD, statusValue);
        }
        seg.put(SEG_JSON_FIELD, payloadJson);
        if (fieldExists(SEG_OBJ, SEG_SOQL_FIELD)) {
            seg.put(SEG_SOQL_FIELD, buildBaseSoqlFromPayload(payloadJson));
        }

        if (audienceId == null) {
            insert seg;
        } else {
            update seg;
        }
        return (Id)seg.get('Id');
    }

    private static void ensureUniqueSegmentationName(String name, Id excludeId) {
        if (String.isBlank(name)) return;
        String soql = 'SELECT Id FROM ' + SEG_OBJ + ' WHERE Name = :name';
        if (excludeId != null) {
            soql += ' AND Id != :excludeId';
        }
        soql += ' LIMIT 1';
        List<SObject> rows = Database.query(soql);
        if (!rows.isEmpty()) {
            throw new AuraHandledException('Audience name already exists. Please use a different name.');
        }
    }

    private static Integer accurateMemberCount(String payloadJson) {
        if (String.isBlank(payloadJson)) return null;
        if (Limits.getQueries() >= Limits.getLimitQueries() - 10) return null;
        try {
            String baseSoql = buildBaseSoqlFromPayload(payloadJson);
            if (String.isBlank(baseSoql)) return null;
            String countSoql = baseSoql.replace('SELECT Id FROM', 'SELECT COUNT() FROM');
            return Database.countQuery(countSoql);
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer countMembersFromPayload(String payloadJson) {
        if (String.isBlank(payloadJson)) return null;
        try {
            Object raw = JSON.deserializeUntyped(payloadJson);
            if (!(raw instanceof Map<String, Object>)) return null;
            Map<String, Object> payload = (Map<String, Object>)raw;
            Object itemsRaw = payload.get('items');
            if (!(itemsRaw instanceof List<Object>)) return null;
            List<Object> items = (List<Object>)itemsRaw;
            Integer total = 0;
            Boolean found = false;

            for (Object obj : items) {
                if (!(obj instanceof Map<String, Object>)) continue;
                Map<String, Object> item = (Map<String, Object>)obj;
                String label = (String)item.get('membersLabel');
                Integer count = extractNumber(label);
                if (count != null) {
                    total += count;
                    found = true;
                }
            }

            if (!found) {
                total = items.size();
            }
            return total;
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer extractNumber(String label) {
        if (String.isBlank(label)) return null;
        Matcher m = Pattern.compile('(\\d+)').matcher(label);
        if (m.find()) {
            return Integer.valueOf(m.group(1));
        }
        return null;
    }

    /**
     * Build a single Account SOQL query by OR-ing each audience item clause.
     * Audience clauses are AND-ed across fields and OR-ed within field values.
     */
    private static String buildBaseSoqlFromPayload(String payloadJson) {
        Object raw = JSON.deserializeUntyped(payloadJson);
        if (!(raw instanceof Map<String, Object>)) {
            return 'SELECT Id FROM ' + DEFAULT_TARGET_OBJECT;
        }
        Map<String, Object> payload = (Map<String, Object>)raw;
        String targetObject = (String)payload.get('targetObject');
        if (String.isBlank(targetObject)) targetObject = DEFAULT_TARGET_OBJECT;

        String baseSoql = 'SELECT Id FROM ' + targetObject;

        Object itemsRaw = payload.get('items');
        if (!(itemsRaw instanceof List<Object>)) return baseSoql;

        List<String> itemWheres = new List<String>();
        for (Object itemRaw : (List<Object>)itemsRaw) {
            if (!(itemRaw instanceof Map<String, Object>)) continue;
            String w = buildItemWhere((Map<String, Object>)itemRaw, targetObject);
            if (!String.isBlank(w)) itemWheres.add(w);
        }

        if (itemWheres.isEmpty()) return baseSoql;
        if (itemWheres.size() == 1) return baseSoql + ' WHERE ' + itemWheres[0];
        List<String> wrapped = new List<String>();
        for (String w : itemWheres) wrapped.add('(' + w + ')');
        return baseSoql + ' WHERE ' + String.join(wrapped, ' OR ');
    }

    /** Base-object predicates vs related-object semi-joins for one audience item. */
    private class Clauses {
        List<String> base = new List<String>();
        List<String> semi = new List<String>();
    }

    /** Accumulates all criteria on one related object reached by the same join field. */
    private class RelGroup {
        String objectApi;
        String joinField;
        List<String> fieldApis = new List<String>();
        List<List<String>> valueSets = new List<List<String>>();
    }

    /**
     * Split one item's criteria into base-object predicates and related-object semi-joins.
     * AND between fields, OR within a field's values. Multiple criteria on the SAME related
     * object (via the same join) are combined into ONE semi-join so they match the SAME record
     * (e.g. an enrollment that is for event X AND session Y), not just the same person.
     */
    private static Clauses buildCriteriaClauses(Object criteriaRaw, String targetObject) {
        Clauses cc = new Clauses();
        if (!(criteriaRaw instanceof List<Object>)) return cc;
        String obj = String.isBlank(targetObject) ? DEFAULT_TARGET_OBJECT : targetObject;

        Map<String, List<List<String>>> fieldToValues = new Map<String, List<List<String>>>();
        Map<String, RelGroup> relGroups = new Map<String, RelGroup>();
        List<String> relOrder = new List<String>();

        for (Object cRaw : (List<Object>)criteriaRaw) {
            if (!(cRaw instanceof Map<String, Object>)) continue;
            Map<String, Object> cMap = (Map<String, Object>)cRaw;
            String key = (String)cMap.get('key');
            String label = (String)cMap.get('label');
            String fieldApi = (String)cMap.get('fieldApi');
            String critObject = (String)cMap.get('objectApi');   // object the field lives on
            String critJoinField = (String)cMap.get('joinField'); // declared lookup back to base/anchor

            List<String> values = toStringList(cMap.get('values'));
            if (values.isEmpty()) continue;

            String ctxObject = String.isBlank(critObject) ? obj : critObject;
            if (String.isBlank(fieldApi)) fieldApi = resolveFieldApiFromAttributeDefinition(key, label, ctxObject);
            if (String.isBlank(fieldApi)) fieldApi = mapCriteriaField(key, label, ctxObject);
            if (String.isBlank(fieldApi)) continue;

            if (!String.isBlank(critObject) && !critObject.equalsIgnoreCase(obj)) {
                String gk = critObject.toLowerCase() + '|' + (String.isBlank(critJoinField) ? '' : critJoinField.toLowerCase());
                RelGroup g = relGroups.get(gk);
                if (g == null) {
                    g = new RelGroup();
                    g.objectApi = critObject;
                    g.joinField = critJoinField;
                    relGroups.put(gk, g);
                    relOrder.add(gk);
                }
                g.fieldApis.add(fieldApi);
                g.valueSets.add(values);
                continue;
            }

            FieldPathInfo info = resolveFieldPathInfo(obj, fieldApi);
            Schema.DescribeFieldResult fr = info == null ? null : info.fieldDescribe;
            if (info != null && !String.isBlank(info.resolvedPath)) fieldApi = info.resolvedPath;
            if (fr == null && !fieldApi.contains('.')) continue;
            if (!fieldToValues.containsKey(fieldApi)) fieldToValues.put(fieldApi, new List<List<String>>());
            fieldToValues.get(fieldApi).add(values);
        }

        for (String fieldApi : fieldToValues.keySet()) {
            List<String> perField = new List<String>();
            for (List<String> values : fieldToValues.get(fieldApi)) {
                String clause = buildTypedInClause(obj, fieldApi, values);
                if (!String.isBlank(clause)) perField.add(clause);
            }
            if (perField.isEmpty()) continue;
            cc.base.add(perField.size() == 1 ? perField[0] : '(' + String.join(perField, ' OR ') + ')');
        }

        for (String gk : relOrder) {
            RelGroup g = relGroups.get(gk);
            String semiJoin = buildRelatedSemiJoin(obj, g.objectApi, g.joinField, g.fieldApis, g.valueSets);
            if (!String.isBlank(semiJoin)) cc.semi.add(semiJoin);
        }
        return cc;
    }

    /**
     * Flat top-level WHERE for one audience item. Group membership and related-object filters
     * are semi-joins appended as top-level AND conjuncts (never wrapped in parentheses or OR-ed
     * within a single query), which is what Salesforce requires. The OR/union across audience
     * items is done in Apex by the callers, not in one SOQL. Returns '' for an unconstrained item.
     */
    private static String buildItemWhere(Map<String, Object> item, String targetObject) {
        String itemId = (String)item.get('id');
        String itemType = (String)item.get('type');
        Boolean isGroup = !String.isBlank(itemType) && itemType.equalsIgnoreCase('GROUP');
        Boolean isIndividual = !String.isBlank(itemType) && itemType.equalsIgnoreCase('INDIVIDUAL');
        Boolean hasCriteria = item.get('criteria') instanceof List<Object> &&
            !((List<Object>)item.get('criteria')).isEmpty();
        Boolean useIdScope = !isGroup && isLikelySalesforceId(itemId) &&
            (isIndividual || String.isBlank(itemType) || !hasCriteria);

        List<String> conj = new List<String>();

        if (isGroup) {
            String g = buildGroupClause(itemId, targetObject); // semi-join -> top level
            if (!String.isBlank(g)) conj.add(g);
            return String.join(conj, ' AND ');
        }

        if (useIdScope) {
            conj.add('Id = ' + toSoqlString(itemId));
        } else {
            String roleClause = buildRoleClause((String)item.get('role'), targetObject);
            if (!String.isBlank(roleClause)) conj.add(roleClause);
        }

        Clauses cc = buildCriteriaClauses(item.get('criteria'), targetObject);
        conj.addAll(cc.base);
        conj.addAll(cc.semi);

        return String.join(conj, ' AND ');
    }

    /**
     * Build a semi-join WHERE fragment that scopes the base/target object to rows that HAVE a
     * related record (on relatedObject) matching ALL of the given field predicates together:
     *
     *
     * The sub-select is evaluated by the database, so the filter stays fully dynamic (new
     * matching records are included automatically) and scales to any number of rows with no
     * id baking and no SOQL length limit. Semi-joins must stay at the top level of the WHERE,
     * so callers append them as top-level AND conjuncts and never wrap or OR them in one query.
     * Returns '' when the relationship cannot be resolved so we never emit broken SOQL.
     */
    private static String buildRelatedSemiJoin(String baseObject, String relatedObject, String declaredJoinField,
        List<String> fieldApis, List<List<String>> valueSets) {
        if (String.isBlank(relatedObject) || fieldApis == null || fieldApis.isEmpty()) return '';
        if (globalDescribe().get(relatedObject) == null) return '';

        RelatedJoin rj = resolveRelatedJoin(baseObject, relatedObject, declaredJoinField);
        if (rj == null) return '';

        List<String> innerPreds = new List<String>();
        for (Integer i = 0; i < fieldApis.size(); i++) {
            String c = buildTypedInClause(relatedObject, fieldApis[i], valueSets[i]);
            if (!String.isBlank(c)) innerPreds.add(c);
        }
        if (innerPreds.isEmpty()) return '';

        return rj.baseKey + ' IN (SELECT ' + rj.joinLookup + ' FROM ' + relatedObject +
            ' WHERE ' + rj.joinLookup + ' != null AND ' + String.join(innerPreds, ' AND ') + ')';
    }

    private class RelatedJoin {
        String baseKey;
        String joinLookup;
    }

    /**
     * Resolve how a related object joins back to the base/target object. Metadata-driven:
     *   - baseKey      = AttributeCategory.Anchor_Field__c for the base object (default 'Id').
     *   - joinLookup   = AttributeDefinition.Join_Field__c when declared, else auto-discovered.
     * The anchor field's referenceTo gives the "anchor object" (e.g. ConstituentRole.PersonId ->
     * Account), so neither the anchor field nor the anchor object is hardcoded. A related object
     * may link to the base object directly (Id match) or to the anchor object (anchor-field match).
     */
    private static RelatedJoin resolveRelatedJoin(String baseObject, String relatedObject, String declaredJoinField) {
        if (String.isBlank(baseObject) || String.isBlank(relatedObject)) return null;
        Map<String, Schema.SObjectField> relFields = fieldMapFor(relatedObject);
        if (relFields == null) return null;

        String anchorField = resolveAnchorField(baseObject);          // e.g. 'PersonId' or 'Id'
        String anchorObject = anchorObjectFor(baseObject, anchorField); // object the anchor references

        if (!String.isBlank(declaredJoinField)) {
            RelatedJoin rj = joinFromLookup(relFields, declaredJoinField, baseObject, anchorObject, anchorField);
            if (rj != null) return rj;
        }

        List<String> toBase = new List<String>();
        List<String> toAnchor = new List<String>();
        for (String fkey : relFields.keySet()) {
            Schema.DescribeFieldResult fr = relFields.get(fkey).getDescribe();
            if (fr.getType() != Schema.DisplayType.REFERENCE) continue;
            for (Schema.SObjectType ref : fr.getReferenceTo()) {
                String refName = ref.getDescribe().getName();
                if (refName.equalsIgnoreCase(baseObject)) {
                    toBase.add(fkey);
                } else if (!String.isBlank(anchorObject) && refName.equalsIgnoreCase(anchorObject)) {
                    toAnchor.add(fkey);
                }
            }
        }
        if (!toBase.isEmpty()) {
            RelatedJoin rj = new RelatedJoin();
            rj.baseKey = 'Id';
            rj.joinLookup = toBase[0];
            return rj;
        }
        if (!toAnchor.isEmpty()) {
            RelatedJoin rj = new RelatedJoin();
            rj.baseKey = anchorField;
            rj.joinLookup = toAnchor[0];
            return rj;
        }
        return null;
    }

    /** Build a join from an explicitly declared lookup field, validating what it references. */
    private static RelatedJoin joinFromLookup(Map<String, Schema.SObjectField> relFields,
        String declaredJoinField, String baseObject, String anchorObject, String anchorField) {
        String key = findFieldApiIgnoreCase(relFields, declaredJoinField);
        if (String.isBlank(key)) return null;
        Schema.DescribeFieldResult fr = relFields.get(key).getDescribe();
        if (fr.getType() != Schema.DisplayType.REFERENCE) return null;
        for (Schema.SObjectType ref : fr.getReferenceTo()) {
            String refName = ref.getDescribe().getName();
            if (refName.equalsIgnoreCase(baseObject)) {
                RelatedJoin rj = new RelatedJoin();
                rj.baseKey = 'Id';
                rj.joinLookup = key;
                return rj;
            }
            if (!String.isBlank(anchorObject) && refName.equalsIgnoreCase(anchorObject)) {
                RelatedJoin rj = new RelatedJoin();
                rj.baseKey = anchorField;
                rj.joinLookup = key;
                return rj;
            }
        }
        return null;
    }

    /**
     * The base object's anchor field that related records join through, e.g. ConstituentRole.PersonId.
     * Driven purely by config: AttributeCategory.Anchor_Field__c for the Target Object. Defaults to
     * 'Id' (the base object IS the audience entity) when no anchor is configured - no object-specific
     * guessing. Person/Account-anchored objects therefore REQUIRE Anchor_Field__c to be set.
     */
    private static final Map<String, String> ANCHOR_BY_OBJECT = new Map<String, String>();
    private static String resolveAnchorField(String baseObject) {
        if (String.isBlank(baseObject)) return 'Id';
        if (ANCHOR_BY_OBJECT.containsKey(baseObject)) return ANCHOR_BY_OBJECT.get(baseObject);

        String anchor = null;
        if (fieldExists(CATEGORY_OBJ, 'Anchor_Field__c') && fieldExists(CATEGORY_OBJ, CATEGORY_TARGET_OBJ)) {
            try {
                List<SObject> rows = Database.query(
                    'SELECT Anchor_Field__c FROM ' + CATEGORY_OBJ +
                    ' WHERE ' + CATEGORY_TARGET_OBJ + ' = :baseObject AND Anchor_Field__c != null LIMIT 1');
                if (!rows.isEmpty()) {
                    String a = (String)rows[0].get('Anchor_Field__c');
                    if (!String.isBlank(a) && fieldExists(baseObject, a.trim())) anchor = a.trim();
                }
            } catch (Exception e) {
            }
        }
        if (String.isBlank(anchor)) anchor = 'Id';
        ANCHOR_BY_OBJECT.put(baseObject, anchor);
        return anchor;
    }

    /** The object an anchor field points to (e.g. PersonId -> Account); the base object when anchor = Id. */
    private static String anchorObjectFor(String baseObject, String anchorField) {
        if (String.isBlank(anchorField) || anchorField.equalsIgnoreCase('Id')) return baseObject;
        Map<String, Schema.SObjectField> fm = fieldMapFor(baseObject);
        if (fm == null) return baseObject;
        String key = findFieldApiIgnoreCase(fm, anchorField);
        if (String.isBlank(key)) return baseObject;
        Schema.DescribeFieldResult fr = fm.get(key).getDescribe();
        if (fr.getType() == Schema.DisplayType.REFERENCE) {
            List<Schema.SObjectType> refs = fr.getReferenceTo();
            if (refs != null && !refs.isEmpty()) return refs[0].getDescribe().getName();
        }
        return baseObject;
    }

    /**
     * Map criteria key/label to a field API name on the target object.
     * Extend this mapping as more filters are enabled.
     */
    private static String mapCriteriaField(String key, String label, String targetObject) {
        String obj = String.isBlank(targetObject) ? DEFAULT_TARGET_OBJECT : targetObject;
        Schema.SObjectType sType = globalDescribe().get(obj);
        if (sType == null) return null;

        Map<String, Schema.SObjectField> fm = sType.getDescribe().fields.getMap();

        // Direct match (supports relationship paths too)
        if (!String.isBlank(key)) {
            if (key.contains('.')) return key;

            for (String candidate : new List<String>{
                key,
                key.endsWith('__c') ? key : key + '__c'
            }) {
                if (fm.containsKey(candidate)) return candidate;
            }
        }

        if (!String.isBlank(label)) {
            if (label.contains('.')) return label;
            String normalized = label.replace(' ', '_').trim();
            for (String candidate : new List<String>{
                normalized,
                normalized.endsWith('__c') ? normalized : normalized + '__c'
            }) {
                if (fm.containsKey(candidate)) return candidate;
            }
        }

        return null;
    }

    /**
     * Resolve field API name from AttributeDefinition when criteria uses DeveloperName/Label.
     */
    private static String resolveFieldApiFromAttributeDefinition(String key, String label, String targetObject) {
        if (String.isBlank(key) && String.isBlank(label)) return null;
        String obj = String.isBlank(targetObject) ? DEFAULT_TARGET_OBJECT : targetObject;

        List<String> whereParts = new List<String>();
        if (!String.isBlank(key)) {
            whereParts.add('DeveloperName = :key');
        }
        if (!String.isBlank(label)) {
            whereParts.add('Label = :label OR Name = :label');
        }
        if (whereParts.isEmpty()) return null;

        String soql = 'SELECT Field_API_Name__c FROM ' + DISTRIBUTION_OBJ + ' WHERE IsActive = true';
        if (fieldExists(DISTRIBUTION_OBJ, 'Object_API_Name__c')) {
            soql += ' AND Object_API_Name__c = :obj';
        }
        soql += ' AND (' + String.join(whereParts, ' OR ') + ')';
        soql += ' LIMIT 1';

        try {
            List<SObject> rows = Database.query(soql);
            if (!rows.isEmpty()) {
                return (String)rows[0].get('Field_API_Name__c');
            }
        } catch (Exception e) {
            // Ignore and fall back to other mappings
        }
        return null;
    }

    /**
     * Resolve a (possibly dotted) field path to its DescribeFieldResult.
     */
    private static Schema.DescribeFieldResult resolveFieldDescribe(String objectApi, String fieldPath) {
        FieldPathInfo info = resolveFieldPathInfo(objectApi, fieldPath);
        return info == null ? null : info.fieldDescribe;
    }

    /**
     * Build a RoleType filter when the target object supports it.
     */
    private static String buildRoleClause(String role, String targetObject) {
        if (String.isBlank(role)) return '';
        String obj = String.isBlank(targetObject) ? DEFAULT_TARGET_OBJECT : targetObject;
        if (!fieldExists(obj, 'RoleType')) return '';
        String r = role.trim();
        // Ignore pseudo-roles that don't map to ConstituentRole.RoleType picklist
        if (r.equalsIgnoreCase('GROUPS')) return '';
        return 'RoleType = ' + toSoqlLiteral(r);
    }

    /**
     * Build a type-aware IN clause for a (possibly dotted) field. Text/picklist values are
     * quoted; boolean/number/date/datetime values are emitted unquoted so the SOQL is valid.
     * A single boolean value uses '=' (e.g. Is_Active__c = true).
     */
    private static String buildTypedInClause(String objectApi, String fieldPath, List<String> values) {
        if (String.isBlank(fieldPath) || values == null || values.isEmpty()) return '';
        FieldPathInfo info = resolveFieldPathInfo(objectApi, fieldPath);
        String resolved = (info != null && !String.isBlank(info.resolvedPath)) ? info.resolvedPath : fieldPath;
        Schema.DisplayType t = (info == null || info.fieldDescribe == null) ? null : info.fieldDescribe.getType();

        if (t == Schema.DisplayType.BOOLEAN) {
            Object b;
            try { b = parseTyped(values[0], null, t); } catch (Exception e) { return ''; }
            return (b == null) ? '' : resolved + ' = ' + toSoqlLiteral(b);
        }

        List<String> literals = new List<String>();
        for (String v : values) {
            if (String.isBlank(v)) continue;
            Object typed;
            try {
                typed = parseTyped(v.trim(), null, t);
            } catch (Exception e) {
                typed = v.trim(); // fall back to a quoted string on parse failure
            }
            literals.add(toSoqlLiteral(typed));
        }
        if (literals.isEmpty()) return '';
        return resolved + ' IN (' + String.join(literals, ',') + ')';
    }

    private static Boolean isLikelySalesforceId(String value) {
        if (String.isBlank(value)) return false;
        Integer len = value.length();
        if (len != 15 && len != 18) return false;
        return Pattern.matches('^[a-zA-Z0-9]{15,18}$', value);
    }

    private static Map<String, String> getAdvancedFieldMap(String role) {
        Map<String, String> out = new Map<String, String>();
        out.put('program', 'Program_Plan__r.LearningProgram.Name');
        out.put('school', 'Program_Plan__r.Provider.Name');
        out.put('campus', 'Program_Plan__r.Provider.Campus__c');
        out.put('department', 'Program_Plan__r.LearningProgram.Program_Stream__c');
        return out;
    }

    private static List<String> toStringList(Object raw) {
        List<String> out = new List<String>();
        if (raw == null) return out;

        if (raw instanceof List<Object>) {
            for (Object v : (List<Object>)raw) {
                if (v == null) continue;
                String s = String.valueOf(v);
                if (!String.isBlank(s)) out.add(s);
            }
            return out;
        }
        if (raw instanceof List<String>) {
            for (String s : (List<String>)raw) {
                if (!String.isBlank(s)) out.add(s);
            }
            return out;
        }
        if (raw instanceof String) {
            String s = (String)raw;
            if (!String.isBlank(s)) out.add(s);
        }
        return out;
    }

    private static String pickFirstPhone(SObject row, List<String> phoneFields) {
        if (row == null || phoneFields == null) return null;
        for (String f : phoneFields) {
            Object val = row.get(f);
            if (val != null && !String.isBlank(String.valueOf(val))) {
                return String.valueOf(val);
            }
        }
        return null;
    }

    private static String buildSubtitle(SObject row, List<String> fields) {
        if (row == null || fields == null) return null;
        List<String> parts = new List<String>();
        for (String f : fields) {
            Object val = row.get(f);
            if (val == null) continue;
            String s = String.valueOf(val);
            if (!String.isBlank(s)) parts.add(s);
            if (parts.size() >= 2) break;
        }
        if (parts.isEmpty()) return null;
        return (parts.size() == 1) ? parts[0] : parts[0] + ' - ' + parts[1];
    }

    private static String normalizeType(Schema.DisplayType t) {
        if (t == Schema.DisplayType.BOOLEAN) return 'Boolean';
        if (t == Schema.DisplayType.DATE) return 'Date';
        if (t == Schema.DisplayType.DATETIME) return 'Datetime';
        if (t == Schema.DisplayType.INTEGER) return 'Integer';
        if (t == Schema.DisplayType.DOUBLE) return 'Number';
        if (t == Schema.DisplayType.CURRENCY) return 'Currency';
        if (t == Schema.DisplayType.PERCENT) return 'Percent';
        if (t == Schema.DisplayType.PICKLIST) return 'Picklist';
        if (t == Schema.DisplayType.MULTIPICKLIST) return 'MultiPicklist';
        return 'Text';
    }

    private class DistributionFieldComparator implements Comparator<DistributionFieldDTO> {
        public Integer compare(DistributionFieldDTO a, DistributionFieldDTO b) {
            String al = (a == null || a.label == null) ? '' : a.label;
            String bl = (b == null || b.label == null) ? '' : b.label;
            return al.toLowerCase().compareTo(bl.toLowerCase());
        }
    }
}