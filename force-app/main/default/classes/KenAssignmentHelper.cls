public without sharing class KenAssignmentHelper {

    public static void updateRecordOwner(List<SObject> records) {
        updateRecordOwner(records, null);
    }

    // stage: when provided, only rules with Stage__c = stage are applied.
    // When null, only rules with Stage__c = null/blank are applied (general rules).
    // Admin tags Ken_Assignment_Rule__c records with Stage__c = 'Hostel' for hostel
    // user assignment and Stage__c = 'Finance' for finance user assignment.
    // Rules with blank Stage__c are general rules used for all other assignments.
    public static void updateRecordOwner(List<SObject> records, String stage) {
        updateRecordOwner(records, stage, null);
    }

    // preResolvedOverrides: caller-supplied field values for formula fields that
    // getCalculatedFormula() cannot expose (e.g. deep cross-object formulas).
    // Values are merged into the formula override map only when the generic resolver
    // did not already produce a value for that field.
    public static void updateRecordOwner(List<SObject> records, String stage, Map<SObject, Map<String, Object>> preResolvedOverrides) {
        if (records == null || records.isEmpty()) return;

        String sObjectName = records[0].getSObjectType().getDescribe().getName();

        List<Ken_Assignment_Rule__c> rules;
        if (String.isNotBlank(stage)) {
            rules = [
                SELECT Id,
                       AssignedQueue__c,
                       AssignedUserAsOwner__c,
                       Index__c,
                       IsActive__c,
                       IsRoundRobin__c,
                       Operator__c,
                       OwnerType__c,
                       ReferenceField__c,
                       ReferenceFieldType__c,
                       ReferenceValue__c,
                       Sequence__c,
                       Stage__c,
                       sObject__c
                FROM Ken_Assignment_Rule__c
                WHERE IsActive__c = true AND sObject__c = :sObjectName AND Stage__c = :stage
                ORDER BY Sequence__c ASC NULLS LAST
            ];
        } else {
            rules = [
                SELECT Id,
                       AssignedQueue__c,
                       AssignedUserAsOwner__c,
                       Index__c,
                       IsActive__c,
                       IsRoundRobin__c,
                       Operator__c,
                       OwnerType__c,
                       ReferenceField__c,
                       ReferenceFieldType__c,
                       ReferenceValue__c,
                       Sequence__c,
                       Stage__c,
                       sObject__c
                FROM Ken_Assignment_Rule__c
                WHERE IsActive__c = true AND sObject__c = :sObjectName AND Stage__c = null
                ORDER BY Sequence__c ASC NULLS LAST
            ];
        }
        if (rules.isEmpty()) return;

        Set<String> roundRobinQueueNames = new Set<String>();
        Set<String> directQueueNames    = new Set<String>();
        for (Ken_Assignment_Rule__c rule : rules) {
            if (String.isBlank(rule.AssignedQueue__c)) continue;
            if (rule.IsRoundRobin__c) {
                roundRobinQueueNames.add(rule.AssignedQueue__c);
            } else {
                directQueueNames.add(rule.AssignedQueue__c);
            }
        }

        Map<String, List<Id>> userIdsByQueueDevName = new Map<String, List<Id>>();
        if (!roundRobinQueueNames.isEmpty()) {
            for (GroupMember gm : [
                SELECT UserOrGroupId, Group.DeveloperName
                FROM GroupMember
                WHERE Group.DeveloperName IN :roundRobinQueueNames
                AND Group.Type = 'Queue'
                ORDER BY Id ASC
            ]) {
                if (!String.valueOf(gm.UserOrGroupId).startsWith('005')) continue;
                if (!userIdsByQueueDevName.containsKey(gm.Group.DeveloperName)) {
                    userIdsByQueueDevName.put(gm.Group.DeveloperName, new List<Id>());
                }
                userIdsByQueueDevName.get(gm.Group.DeveloperName).add(gm.UserOrGroupId);
            }
        }

        Map<String, Id> queueIdByDevName = new Map<String, Id>();
        if (!directQueueNames.isEmpty()) {
            for (Group g : [
                SELECT Id, DeveloperName
                FROM Group
                WHERE DeveloperName IN :directQueueNames AND Type = 'Queue'
            ]) {
                queueIdByDevName.put(g.DeveloperName, g.Id);
            }
        }

        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(sObjectName)
            .getDescribe()
            .fields.getMap();

        // Auto-resolve formula fields that return null in before-insert trigger context.
        // Returns a per-record map of formula field overrides for fields that could not
        // be written back (formula fields throw SObjectException on put).
        Map<SObject, Map<String, Object>> formulaOverrides = resolveFormulaFields(records, rules, sObjectName);

        // Merge caller-supplied pre-resolved values as fallback for formula fields
        // that getCalculatedFormula() cannot expose (returns null for deep cross-object formulas).
        if (preResolvedOverrides != null) {
            for (SObject rec : records) {
                Map<String, Object> preRes = preResolvedOverrides.get(rec);
                if (preRes == null || preRes.isEmpty()) continue;
                if (!formulaOverrides.containsKey(rec)) {
                    formulaOverrides.put(rec, new Map<String, Object>());
                }
                Map<String, Object> existing = formulaOverrides.get(rec);
                for (String f : preRes.keySet()) {
                    if (!existing.containsKey(f)) existing.put(f, preRes.get(f));
                }
            }
        }

        Boolean rulesUpdated = false;

        for (SObject rec : records) {
            Map<String, Object> recOverrides = formulaOverrides.get(rec);
            for (Ken_Assignment_Rule__c rule : rules) {
                if (String.isBlank(rule.ReferenceField__c)) continue;
                if (!fieldMap.containsKey(rule.ReferenceField__c.toLowerCase())) continue;
                if (!matchesCriteria(rec, rule, fieldMap, recOverrides)) continue;

                if (rule.OwnerType__c == 'Queue' && rule.IsRoundRobin__c) {
                    List<Id> members = userIdsByQueueDevName.get(rule.AssignedQueue__c);
                    if (members != null && !members.isEmpty()) {
                        Integer idx = (rule.Index__c == null || (Integer) rule.Index__c >= members.size())
                            ? 0
                            : (Integer) rule.Index__c;
                        rec.put('OwnerId', members[idx]);
                        rule.Index__c = idx + 1;
                        rulesUpdated = true;
                    }
                } else if (rule.OwnerType__c == 'Queue' && !rule.IsRoundRobin__c) {
                    Id qId = queueIdByDevName.get(rule.AssignedQueue__c);
                    if (qId != null) {
                        rec.put('OwnerId', qId);
                    }
                } else if (rule.OwnerType__c == 'User' && rule.AssignedUserAsOwner__c != null) {
                    rec.put('OwnerId', rule.AssignedUserAsOwner__c);
                }

                break;
            }
        }

        if (rulesUpdated) {
            update rules;
        }
    }

    // Inner class to hold parsed formula resolution info
    @TestVisible
    private class FormulaResolution {
        @TestVisible String formulaField;
        @TestVisible String lookupField;
        @TestVisible String soqlField;
    }

    // Fully generic formula field resolver.
    // Uses Schema API to detect formula fields, parses relationship formulas (1–3+ hops),
    // queries related objects, and either sets values in-memory (writable fields) or
    // returns them in a per-record override map (formula fields, which are not writable).
    // No code changes needed when new formula fields are used in assignment rules.
    @TestVisible
    private static Map<SObject, Map<String, Object>> resolveFormulaFields(
        List<SObject> records,
        List<Ken_Assignment_Rule__c> rules,
        String sObjectName
    ) {
        Map<SObject, Map<String, Object>> overrides = new Map<SObject, Map<String, Object>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(sObjectName).getDescribe().fields.getMap();

        // Identify formula fields that return null on these records
        List<FormulaResolution> resolutions = new List<FormulaResolution>();
        for (Ken_Assignment_Rule__c rule : rules) {
            if (String.isBlank(rule.ReferenceField__c)) continue;
            String fLower = rule.ReferenceField__c.toLowerCase();
            Schema.SObjectField schemaField = fieldMap.get(fLower);
            if (schemaField == null) continue;
            if (records[0].get(rule.ReferenceField__c) != null) continue;

            Schema.DescribeFieldResult dfr = schemaField.getDescribe();
            String formula = dfr.getCalculatedFormula();
            if (String.isBlank(formula)) continue;

            FormulaResolution res = parseRelationshipFormula(formula.trim(), fieldMap);
            if (res != null) {
                res.formulaField = rule.ReferenceField__c;
                resolutions.add(res);
            }
        }
        if (resolutions.isEmpty()) return overrides;

        // Group resolutions by their first-hop lookup field to batch SOQL
        Map<String, List<FormulaResolution>> byLookup = new Map<String, List<FormulaResolution>>();
        for (FormulaResolution res : resolutions) {
            if (!byLookup.containsKey(res.lookupField)) {
                byLookup.put(res.lookupField, new List<FormulaResolution>());
            }
            byLookup.get(res.lookupField).add(res);
        }

        for (String lookupField : byLookup.keySet()) {
            List<FormulaResolution> resGroup = byLookup.get(lookupField);

            // Collect related IDs
            Set<Id> relatedIds = new Set<Id>();
            for (SObject rec : records) {
                Object v = rec.get(lookupField);
                if (v != null) relatedIds.add((Id) v);
            }
            if (relatedIds.isEmpty()) continue;

            // Determine the related sObject type from the lookup field's reference
            Schema.SObjectField lookupSField = fieldMap.get(lookupField.toLowerCase());
            if (lookupSField == null) continue;
            List<Schema.SObjectType> refs = lookupSField.getDescribe().getReferenceTo();
            if (refs.isEmpty()) continue;
            String relatedObj = refs[0].getDescribe().getName();

            // Build SOQL — select all needed soqlFields in one query
            Set<String> soqlFields = new Set<String>{ 'Id' };
            for (FormulaResolution res : resGroup) soqlFields.add(res.soqlField);
            String soqlFieldList = String.join(new List<String>(soqlFields), ', ');

            Map<Id, SObject> relatedById = new Map<Id, SObject>();
            try {
                String q = 'SELECT ' + soqlFieldList + ' FROM ' + relatedObj + ' WHERE Id IN :relatedIds';
                for (SObject rel : Database.query(q)) {
                    relatedById.put(rel.Id, rel);
                }
            } catch (Exception ignored) {}
            if (relatedById.isEmpty()) continue;

            // Set formula field values in-memory on each record.
            // Formula fields (not writable) are stored in the override map instead.
            for (SObject rec : records) {
                Object v = rec.get(lookupField);
                if (v == null) continue;
                SObject related = relatedById.get((Id) v);
                if (related == null) continue;
                for (FormulaResolution res : resGroup) {
                    String resolvedVal = getNestedValue(related, res.soqlField);
                    if (resolvedVal != null) {
                        try {
                            rec.put(res.formulaField, resolvedVal);
                        } catch (SObjectException ignored) {
                            // Formula field — store in override map for matchesCriteria to use
                            if (!overrides.containsKey(rec)) {
                                overrides.put(rec, new Map<String, Object>());
                            }
                            overrides.get(rec).put(res.formulaField, resolvedVal);
                        }
                    }
                }
            }
        }
        return overrides;
    }

    // Parses a formula like "Service_Offering__r.Name" (1-hop)
    // or "Service_Offering__r.Service__r.Name" (2-hop) into a FormulaResolution.
    // Also handles complex formulas that wrap the traversal in functions like
    // IF(X != null, X__r.Field__c, '') or BLANKVALUE(X__r.Field__c, '') by
    // extracting the first valid __r traversal found in the expression.
    @TestVisible
    private static FormulaResolution parseRelationshipFormula(
        String formula, Map<String, Schema.SObjectField> fieldMap
    ) {
        List<String> parts = formula.split('\\.');
        if (parts.size() >= 2) {
            String relPart = parts[0].trim();
            if (relPart.endsWith('__r') || relPart.endsWith('r')) {
                String lookupField = relPart.endsWith('__r')
                    ? relPart.substring(0, relPart.length() - 1) + 'c'
                    : relPart + 'Id';
                if (fieldMap.containsKey(lookupField.toLowerCase())) {
                    List<String> soqlParts = new List<String>();
                    for (Integer i = 1; i < parts.size(); i++) soqlParts.add(parts[i]);
                    FormulaResolution res = new FormulaResolution();
                    res.lookupField = lookupField;
                    res.soqlField   = String.join(soqlParts, '.');
                    return res;
                }
            }
        }
        // Fallback: formula uses functions (IF, BLANKVALUE, TEXT, CASE, etc.) wrapping
        // a relationship traversal. Extract the first valid Obj__r.Field pattern and
        // parse that clean path instead.
        Pattern p = Pattern.compile('(\\w+__r(?:\\.\\w+)+)');
        Matcher m = p.matcher(formula);
        while (m.find()) {
            String extracted = m.group(1);
            if (extracted.equals(formula)) continue; // guard: same string would recurse infinitely
            FormulaResolution res = parseRelationshipFormula(extracted, fieldMap);
            if (res != null) return res;
        }
        return null;
    }

    // Traverses a dot-notation field path on an SObject (e.g. "Service__r.Name")
    @TestVisible
    private static String getNestedValue(SObject record, String dotPath) {
        List<String> parts = dotPath.split('\\.');
        SObject current = record;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            current = current.getSObject(parts[i]);
            if (current == null) return null;
        }
        Object val = current.get(parts[parts.size() - 1]);
        return val != null ? String.valueOf(val) : null;
    }

    @TestVisible
    private static Boolean matchesCriteria(
        SObject rec,
        Ken_Assignment_Rule__c rule,
        Map<String, Schema.SObjectField> fieldMap
    ) {
        return matchesCriteria(rec, rule, fieldMap, null);
    }

    @TestVisible
    private static Boolean matchesCriteria(
        SObject rec,
        Ken_Assignment_Rule__c rule,
        Map<String, Schema.SObjectField> fieldMap,
        Map<String, Object> formulaOverrides
    ) {
        Schema.SObjectField field = fieldMap.get(rule.ReferenceField__c.toLowerCase());
        String fieldType = String.valueOf(field.getDescribe().getType());
        // Check formula override map first (for formula fields that couldn't be written back)
        String fieldValue = (formulaOverrides != null && formulaOverrides.containsKey(rule.ReferenceField__c))
            ? String.valueOf(formulaOverrides.get(rule.ReferenceField__c))
            : String.valueOf(rec.get(rule.ReferenceField__c));
        String ruleValue  = rule.ReferenceValue__c;

        if (fieldType == 'MULTIPICKLIST' || rule.Operator__c == 'INCLUDES') {
            Set<String> fieldVals = fieldValue != null
                ? new Set<String>(fieldValue.split(';'))
                : new Set<String>();
            List<String> ruleVals = ruleValue != null
                ? ruleValue.split(';')
                : new List<String>();
            return fieldVals.containsAll(ruleVals);
        }

        if (rule.Operator__c == '=')      return fieldValue == ruleValue;
        if (rule.Operator__c == '!=')     return fieldValue != ruleValue;
        if (rule.Operator__c == 'IN')     return toList(ruleValue, rule.ReferenceFieldType__c).contains(fieldValue);
        if (rule.Operator__c == 'NOT IN') return !toList(ruleValue, rule.ReferenceFieldType__c).contains(fieldValue);

        return false;
    }

    private static List<String> toList(String values, String fieldType) {
        List<String> result = new List<String>();
        if (String.isBlank(values)) return result;
        for (String v : values.split(';')) {
            result.add(v.trim());
        }
        return result;
    }
}