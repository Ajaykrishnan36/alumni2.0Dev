/**
 * Generic controller for Audience (Ken_Segmentation__c) ↔ parent-record junction objects.
 *
 * Each consumer module (Event, Survey, Group, Campaign, …) owns its own junction object that
 * pairs a parent record with a Ken_Segmentation__c. This controller encapsulates the
 * lookup, insert and save-with-reuse semantics against any registered junction, keyed by a
 * short module name.
 *
 * To add a new module, append an entry to JUNCTION_CONFIG.
 */
public with sharing class KenAudienceJunctionController {

    @TestVisible
    private static final Map<String, Map<String, String>> JUNCTION_CONFIG = new Map<String, Map<String, String>>{
        'Event'  => new Map<String, String>{
            'object'        => 'Ken_Event_Segmentation__c',
            'parentField'   => 'Event_Master__c',
            'segField'      => 'Segmentation__c'
        },
        'Survey' => new Map<String, String>{
            'object'        => 'Ken_Survey_Segmentation__c',
            'parentField'   => 'Survey__c',
            'segField'      => 'Segmentation__c'
        },
        'Group'  => new Map<String, String>{
            'object'        => 'Ken_Group_Segmentation__c',
            'parentField'   => 'Group__c',
            'segField'      => 'Segmentation__c'
        },
        'Campaign' => new Map<String, String>{
            'object'        => 'Ken_Fundraise_Segmentation__c',
            'parentField'   => 'Fundraise__c',
            'segField'      => 'Segmentation__c'
        }
    };

    /**
     * String (not Id) + explicit accessors: community-user LWC calls on the LWR site
     * receive plain @AuraEnabled fields as null.
     */
    public class SaveResultDTO {
        @AuraEnabled public String segmentationId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Boolean forked { get; set; }
    }

    private static Map<String, String> configFor(String parentObjectType) {
        if (String.isBlank(parentObjectType)) {
            throw new AuraHandledException('parentObjectType is required.');
        }
        Map<String, String> cfg = JUNCTION_CONFIG.get(parentObjectType);
        if (cfg == null) {
            throw new AuraHandledException('Unsupported parentObjectType: ' + parentObjectType);
        }
        return cfg;
    }

    @AuraEnabled(cacheable=false)
    public static Id getLinkedSegmentation(String parentObjectType, Id parentId) {
        if (parentId == null) {
            return null;
        }
        Map<String, String> cfg = configFor(parentObjectType);
        return new ElevatedReader().fetchLinkedSegmentation(cfg, parentId);
    }

    /**
     * Saves the whole audience selection as ONE segmentation and links it to the parent
     * record, deciding between create / update-in-place / fork:
     *
     *  - segmentationId null                  → create a new segmentation (name required).
     *  - segmentation used ONLY by this parent → update it in place (it belongs to this record).
     *  - segmentation used by other records,
     *    or forceFork (picked from Saved
     *    Audience and then edited)            → clone into a NEW segmentation with a unique
     *                                           name and re-point this parent's junction to
     *                                           the clone; the original is never mutated.
     *
     * parentId may be null (standalone save); linking then happens later via
     * linkSegmentationToParent.
     */
    @AuraEnabled
    public static SaveResultDTO saveSegmentationForParent(
        String parentObjectType,
        Id parentId,
        Id segmentationId,
        String audienceName,
        String payloadJson,
        Boolean forceFork
    ) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Audience payload is required.');
        }
        Map<String, String> cfg = (parentId != null) ? configFor(parentObjectType) : null;

        SaveResultDTO result = new SaveResultDTO();
        result.forked = false;
        Id savedSegId;

        if (segmentationId == null) {
            if (String.isBlank(audienceName)) {
                throw new AuraHandledException('Audience name is required.');
            }
            savedSegId = KenAudienceEngineService.saveAudiencePayload(
                audienceName, payloadJson, null, true, 'Active');
            result.name = audienceName;
        } else {
            ElevatedReader reader = new ElevatedReader();
            String existingName = reader.fetchSegmentationName(segmentationId);
            Boolean shared = (forceFork == true)
                || reader.isSegmentationUsedElsewhere(segmentationId, parentObjectType, parentId);

            if (!shared) {
                String name = String.isBlank(audienceName) ? existingName : audienceName;
                savedSegId = KenAudienceEngineService.saveAudiencePayload(
                    name, payloadJson, segmentationId, true, 'Active');
                result.name = name;
            } else {
                String baseName = String.isBlank(existingName) ? 'Audience' : existingName;
                String uniqueName = reader.nextAvailableName(baseName);
                savedSegId = KenAudienceEngineService.saveAudiencePayload(
                    uniqueName, payloadJson, null, true, 'Active');
                result.name = uniqueName;
                result.forked = true;
            }
        }
        result.segmentationId = savedSegId;

        if (cfg != null) {
            new ElevatedLinker().link(cfg, parentId, savedSegId);
        }
        return result;
    }

    /**
     * Reads run in a system context because community-user sharing on the parent
     * (Survey/Event/Group are external Private) hides junction rows the caller doesn't
     * own — and the shared-elsewhere check MUST see every module's rows or a shared
     * segmentation would be silently mutated. The caller has already been authorized at
     * the parent level by the page that invoked us.
     */
    private without sharing class ElevatedReader {
        Id fetchLinkedSegmentation(Map<String, String> cfg, Id parentId) {
            String soql = 'SELECT ' + cfg.get('segField')
                        + ' FROM ' + cfg.get('object')
                        + ' WHERE ' + cfg.get('parentField') + ' = :parentId'
                        + ' ORDER BY CreatedDate DESC LIMIT 1';
            List<SObject> rows = Database.query(soql);
            if (rows.isEmpty()) {
                return null;
            }
            return (Id) rows[0].get(cfg.get('segField'));
        }

        String fetchSegmentationName(Id segmentationId) {
            List<Ken_Segmentation__c> rows = [
                SELECT Name FROM Ken_Segmentation__c WHERE Id = :segmentationId LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].Name;
        }

        /** True when any junction row of ANY module points at this segmentation for a DIFFERENT parent. */
        Boolean isSegmentationUsedElsewhere(Id segmentationId, String parentObjectType, Id parentId) {
            for (String module : JUNCTION_CONFIG.keySet()) {
                Map<String, String> cfg = JUNCTION_CONFIG.get(module);
                if (Schema.getGlobalDescribe().get(cfg.get('object')) == null) {
                    continue;
                }
                String soql = 'SELECT ' + cfg.get('parentField')
                            + ' FROM ' + cfg.get('object')
                            + ' WHERE ' + cfg.get('segField') + ' = :segmentationId';
                Boolean sameModule = module == parentObjectType && parentId != null;
                if (sameModule) {
                    soql += ' AND ' + cfg.get('parentField') + ' != :parentId';
                }
                soql += ' LIMIT 1';
                if (!Database.query(soql).isEmpty()) {
                    return true;
                }
            }
            return false;
        }

        /** First "<base>", "<base> (2)", "<base> (3)"… name not taken by another segmentation. */
        String nextAvailableName(String baseName) {
            String likeTerm = String.escapeSingleQuotes(baseName) + '%';
            Set<String> taken = new Set<String>();
            for (Ken_Segmentation__c seg : [
                SELECT Name FROM Ken_Segmentation__c WHERE Name LIKE :likeTerm LIMIT 2000
            ]) {
                taken.add(seg.Name);
            }
            if (!taken.contains(baseName)) {
                return baseName;
            }
            for (Integer i = 2; i <= 99; i++) {
                String candidate = baseName + ' (' + i + ')';
                if (!taken.contains(candidate)) {
                    return candidate;
                }
            }
            return baseName + ' ' + Datetime.now().getTime();
        }
    }

    @AuraEnabled
    public static Id linkSegmentationToParent(String parentObjectType, Id parentId, Id segmentationId) {
        if (parentId == null || segmentationId == null) {
            throw new AuraHandledException('Parent Id and Segmentation Id are required.');
        }
        Map<String, String> cfg = configFor(parentObjectType);
        SObjectType juncType = Schema.getGlobalDescribe().get(cfg.get('object'));
        if (juncType == null) {
            throw new AuraHandledException('Junction object not available: ' + cfg.get('object'));
        }

        return new ElevatedLinker().link(cfg, parentId, segmentationId);
    }

    /**
     * Writes run in a system context: community users own the parent record but do not
     * have (and should not need) CRUD on the junction objects — the page invoking this
     * has already authorized them at the parent level.
     */
    private without sharing class ElevatedLinker {
        Id link(Map<String, String> cfg, Id parentId, Id segmentationId) {
            String staleSoql = 'SELECT Id FROM ' + cfg.get('object')
                        + ' WHERE ' + cfg.get('parentField') + ' = :parentId'
                        + ' AND ' + cfg.get('segField') + ' != :segmentationId';
            List<SObject> stale = Database.query(staleSoql);
            if (!stale.isEmpty()) {
                delete stale;
            }

            String soql = 'SELECT Id FROM ' + cfg.get('object')
                        + ' WHERE ' + cfg.get('parentField') + ' = :parentId'
                        + ' AND ' + cfg.get('segField') + ' = :segmentationId'
                        + ' LIMIT 1';
            List<SObject> existing = Database.query(soql);
            if (!existing.isEmpty()) {
                return (Id) existing[0].get('Id');
            }

            SObject junction = Schema.getGlobalDescribe().get(cfg.get('object')).newSObject();
            junction.put(cfg.get('parentField'), parentId);
            junction.put(cfg.get('segField'), segmentationId);
            insert junction;
            return (Id) junction.get('Id');
        }
    }
}