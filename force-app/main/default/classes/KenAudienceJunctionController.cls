/**
 * Generic controller for the Audience (Ken_Segmentation__c) link carried by every
 * consumer module (Event, Survey, Group, Campaign).
 *
 * Each parent object holds its audience in a direct Segmentation__c lookup. A parent has
 * at most one audience — several audience blocks live inside one segmentation's
 * Definition_JSON__c — while one segmentation may be reused by many parents, which is what
 * makes the Saved Audience library work. That is a plain many-to-one, so the lookup sits on
 * the parent and no junction object is involved.
 *
 * To add a new module, append an entry to PARENT_OBJECT_BY_MODULE and give that object a
 * Segmentation__c lookup to Ken_Segmentation__c.
 */
public with sharing class KenAudienceJunctionController {

    /** Every parent object carries the audience in a field of this name. */
    @TestVisible
    private static final String SEG_FIELD = KenNamespaceUtil.qualifyCustom('Segmentation__c');

    @TestVisible
    private static final Map<String, String> PARENT_OBJECT_BY_MODULE = new Map<String, String>{
        'Event'    => 'Ken_Event_Master__c',
        'Survey'   => 'Ken_Survey__c',
        'Group'    => 'Ken_Group__c',
        'Campaign' => 'Ken_Fundraise__c'
    };

    /** Inverse of PARENT_OBJECT_BY_MODULE, so the two can never drift apart. */
    private static final Map<String, String> MODULE_BY_SOBJECT = buildModuleBySObject();

    private static Map<String, String> buildModuleBySObject() {
        Map<String, String> inverted = new Map<String, String>();
        for (String moduleKey : PARENT_OBJECT_BY_MODULE.keySet()) {
            inverted.put(KenNamespaceUtil.qualifyCustom(PARENT_OBJECT_BY_MODULE.get(moduleKey)), moduleKey);
        }
        return inverted;
    }

    /**
     * String (not Id) + explicit accessors: community-user LWC calls on the LWR site
     * receive plain @AuraEnabled fields as null.
     */
    public class SaveResultDTO {
        @AuraEnabled public String segmentationId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Boolean forked { get; set; }
    }

    private static String parentObjectFor(String parentObjectType) {
        if (String.isBlank(parentObjectType)) {
            throw new AuraHandledException('parentObjectType is required.');
        }
        String parentObject = PARENT_OBJECT_BY_MODULE.get(parentObjectType);
        if (parentObject == null) {
            throw new AuraHandledException('Unsupported parentObjectType: ' + parentObjectType);
        }
        return parentObject;
    }

    /**
     * True when the parent object exists in this org and carries the audience lookup. Orgs
     * run different metadata versions, so a module registered above may not be linkable
     * here yet and must be skipped rather than blowing up the caller.
     */
    private static Boolean isLinkable(String parentObject) {
        SObjectType parentType = KenNamespaceUtil.resolveSObjectType(parentObject);
        return parentType != null
            && KenNamespaceUtil.hasField(parentType.getDescribe().fields.getMap(), SEG_FIELD);
    }

    @AuraEnabled(cacheable=false)
    public static Id getLinkedSegmentation(String parentObjectType, Id parentId) {
        if (parentId == null) {
            return null;
        }
        String parentObject = parentObjectFor(parentObjectType);
        if (!isLinkable(parentObject)) {
            return null;
        }
        return new ElevatedReader().fetchLinkedSegmentation(parentObject, parentId);
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
     *                                           name and re-point this parent at the clone;
     *                                           the original is never mutated.
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
        String parentObject = (parentId != null) ? parentObjectFor(parentObjectType) : null;

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

        if (parentObject != null && isLinkable(parentObject)) {
            new ElevatedLinker().link(parentObject, parentId, savedSegId);
            mirrorToDependentSurveys(parentObjectType, parentId);
        }
        return result;
    }

    /**
     * Event feedback forms are wrapped in a Ken_Survey__c that the Survey module reads
     * from its own audience lookup, so an event's audience has to be mirrored there.
     * Without it the survey detail page shows an empty Target Audience and getSurveys()
     * filters the feedback form out of every respondent's list.
     *
     * @param parentObjectType Module the audience was written for.
     * @param parentId Parent record that was linked.
     */
    private static void mirrorToDependentSurveys(String parentObjectType, Id parentId) {
        if (parentObjectType == 'Event' && parentId != null) {
            KenEventFormController.syncEventAudienceToWrapperSurveys(parentId);
        }
    }

    private static final Map<String, String> AUDIENCE_TYPE_LABELS = new Map<String, String>{
        'ALL'        => 'Everyone',
        'CUSTOM'     => 'Matching a filter',
        'GROUP'      => 'Group members',
        'INDIVIDUAL' => 'Named people'
    };

    /**
     * @description The saved audience of any module record, in plain language.
     */
    public class AudienceViewDTO {
        @AuraEnabled public Boolean hasAudience { get; set; }
        @AuraEnabled public String segmentationName { get; set; }
        @AuraEnabled public String moduleLabel { get; set; }
        @AuraEnabled public String matchLabel { get; set; }
        @AuraEnabled public String reachLabel { get; set; }
        @AuraEnabled public Integer savedMemberCount { get; set; }
        @AuraEnabled public List<AudienceBlockDTO> blocks { get; set; }
        @AuraEnabled public List<String> simpleAudience { get; set; }
    }

    public class AudienceBlockDTO {
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String roleLabel { get; set; }
        @AuraEnabled public String typeLabel { get; set; }
        @AuraEnabled public Integer memberCount { get; set; }
        @AuraEnabled public List<String> criteria { get; set; }
    }

    /**
     * @description Reads the audience saved against any module record and describes it in
     *              words rather than filter syntax. Works on every module in
     *              PARENT_OBJECT_BY_MODULE, so one component can sit on an event, survey,
     *              group or campaign page.
     * @param recordId The module record being viewed.
     * @return The audience description; hasAudience is false when none is saved.
     */
    @AuraEnabled(cacheable=true)
    public static AudienceViewDTO getAudienceForRecord(Id recordId) {
        AudienceViewDTO view = new AudienceViewDTO();
        view.hasAudience = false;
        view.blocks = new List<AudienceBlockDTO>();
        view.simpleAudience = new List<String>();
        if (recordId == null) {
            return view;
        }

        String sObjectName = recordId.getSObjectType().getDescribe().getName();
        view.moduleLabel = MODULE_BY_SOBJECT.get(sObjectName);

        if (view.moduleLabel != null && isLinkable(sObjectName)) {
            Id segmentationId = new ElevatedReader()
                .fetchLinkedSegmentation(sObjectName, recordId);
            if (segmentationId != null) {
                describeSegmentation(segmentationId, view);
            }
        }

        if (!view.hasAudience) {
            addPlainAudience(sObjectName, recordId, view);
        }
        return view;
    }

    private static void describeSegmentation(Id segmentationId, AudienceViewDTO view) {
        List<Ken_Segmentation__c> rows = new ElevatedReader().fetchSegmentationDefinition(segmentationId);
        if (rows.isEmpty()) {
            return;
        }
        Ken_Segmentation__c seg = rows[0];
        view.segmentationName = seg.Name;
        view.hasAudience = true;

        if (String.isBlank(seg.Definition_JSON__c)) {
            return;
        }
        Map<String, Object> definition;
        try {
            definition = (Map<String, Object>) JSON.deserializeUntyped(seg.Definition_JSON__c);
        } catch (Exception e) {
            return;
        }

        Object logicRaw = definition.get('logic');
        String joinWord = 'all';
        if (logicRaw instanceof Map<String, Object>) {
            Object audiences = ((Map<String, Object>) logicRaw).get('audiences');
            joinWord = ('OR'.equalsIgnoreCase(String.valueOf(audiences))) ? 'any' : 'all';
        }

        Object itemsRaw = definition.get('items');
        if (!(itemsRaw instanceof List<Object>)) {
            return;
        }
        List<Object> items = (List<Object>) itemsRaw;
        Integer total = 0;
        for (Object itemRaw : items) {
            if (!(itemRaw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> item = (Map<String, Object>) itemRaw;
            AudienceBlockDTO block = new AudienceBlockDTO();
            block.title = String.valueOf(item.get('title'));
            block.roleLabel = String.valueOf(item.get('roleLabel'));
            String type = String.valueOf(item.get('type'));
            block.typeLabel = AUDIENCE_TYPE_LABELS.containsKey(type)
                ? AUDIENCE_TYPE_LABELS.get(type) : type;
            block.memberCount = item.get('memberCount') == null
                ? null : Integer.valueOf(String.valueOf(item.get('memberCount')));
            block.criteria = describeCriteria(item.get('criteria'));
            if (block.memberCount != null) {
                total += block.memberCount;
            }
            view.blocks.add(block);
        }

        view.savedMemberCount = total;
        view.matchLabel = view.blocks.size() > 1
            ? 'Matches ' + joinWord + ' of these audiences'
            : null;
        // Only a single audience has a defensible headline count. Several audiences can cover
        // the same people, so adding their saved counts would overstate the reach.
        if (view.blocks.size() == 1 && view.blocks[0].memberCount != null) {
            Integer one = view.blocks[0].memberCount;
            view.reachLabel = (one == 1 ? '1 member' : one + ' members') + ' when last saved';
        }
    }

    /**
     * @description Turns stored filter rows into sentences a reader can follow, e.g.
     *              "Registration Status is Initial Login Done".
     * @param criteriaRaw The criteria array from the saved definition.
     * @return One sentence per filter row.
     */
    private static List<String> describeCriteria(Object criteriaRaw) {
        List<String> described = new List<String>();
        if (!(criteriaRaw instanceof List<Object>)) {
            return described;
        }
        for (Object rowRaw : (List<Object>) criteriaRaw) {
            if (!(rowRaw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> row = (Map<String, Object>) rowRaw;
            String label = String.valueOf(row.get('label'));
            if (String.isBlank(label) || label == 'null') {
                label = String.valueOf(row.get('fieldApi'));
            }
            List<String> values = new List<String>();
            if (row.get('values') instanceof List<Object>) {
                for (Object v : (List<Object>) row.get('values')) {
                    if (v != null) {
                        values.add(String.valueOf(v));
                    }
                }
            }
            if (values.isEmpty()) {
                described.add(label + ' is set');
            } else if (values.size() == 1) {
                described.add(label + ' is ' + values[0]);
            } else {
                described.add(label + ' is any of ' + String.join(values, ', '));
            }
        }
        return described;
    }

    /**
     * @description Falls back to a record's own semicolon-separated audience text when no
     *              segmentation is linked.
     * @param sObjectName The parent object.
     * @param recordId The parent record.
     * @param view The view being populated.
     */
    private static void addPlainAudience(String sObjectName, Id recordId, AudienceViewDTO view) {
        if (!KenNamespaceUtil.resolveFieldMap(sObjectName)
                .containsKey(KenNamespaceUtil.qualifyCustom('Target_Audience__c'))) {
            return;
        }
        List<SObject> rows = new ElevatedReader().fetchPlainAudience(sObjectName, recordId);
        if (rows.isEmpty()) {
            return;
        }
        String raw = (String) rows[0].get(KenNamespaceUtil.qualifyCustom('Target_Audience__c'));
        if (String.isBlank(raw)) {
            return;
        }
        for (String part : raw.split(';')) {
            if (String.isNotBlank(part)) {
                view.simpleAudience.add(part.trim());
            }
        }
        view.hasAudience = !view.simpleAudience.isEmpty();
    }

    /**
     * Reads run in a system context because community-user sharing on the parent
     * (Survey/Event/Group/Campaign are external Private) hides rows the caller doesn't own
     * — and the shared-elsewhere check MUST see every module's rows or a shared
     * segmentation would be silently mutated. The caller has already been authorized at
     * the parent level by the page that invoked us.
     */
    private without sharing class ElevatedReader {
        List<Ken_Segmentation__c> fetchSegmentationDefinition(Id segmentationId) {
            return [
                SELECT Id, Name, Definition_JSON__c
                FROM Ken_Segmentation__c WHERE Id = :segmentationId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        }

        List<SObject> fetchPlainAudience(String sObjectName, Id recordId) {
            return Database.queryWithBinds(
                'SELECT Target_Audience__c FROM ' + String.escapeSingleQuotes(sObjectName)
                + ' WHERE Id = :recordId LIMIT 1',
                new Map<String, Object>{ 'recordId' => recordId },
                AccessLevel.SYSTEM_MODE
            );
        }

        Id fetchLinkedSegmentation(String parentObject, Id parentId) {
            String soql = 'SELECT ' + SEG_FIELD
                        + ' FROM ' + String.escapeSingleQuotes(parentObject)
                        + ' WHERE Id = :parentId LIMIT 1';
            List<SObject> rows = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'parentId' => parentId },
                AccessLevel.SYSTEM_MODE
            );
            if (rows.isEmpty()) {
                return null;
            }
            return (Id) rows[0].get(SEG_FIELD);
        }

        String fetchSegmentationName(Id segmentationId) {
            List<Ken_Segmentation__c> rows = [
                SELECT Name FROM Ken_Segmentation__c WHERE Id = :segmentationId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].Name;
        }

        /** True when any record of ANY module points at this segmentation, other than this parent. */
        Boolean isSegmentationUsedElsewhere(Id segmentationId, String parentObjectType, Id parentId) {
            for (String moduleKey : PARENT_OBJECT_BY_MODULE.keySet()) {
                String parentObject = PARENT_OBJECT_BY_MODULE.get(moduleKey);
                if (!isLinkable(parentObject)) {
                    continue;
                }
                String soql = 'SELECT Id FROM ' + String.escapeSingleQuotes(parentObject)
                            + ' WHERE ' + SEG_FIELD + ' = :segmentationId';
                Boolean sameModule = moduleKey == parentObjectType && parentId != null;
                if (sameModule) {
                    soql += ' AND Id != :parentId';
                }
                soql += ' LIMIT 1';
                Map<String, Object> binds = new Map<String, Object>{
                    'segmentationId' => segmentationId,
                    'parentId' => parentId
                };
                if (!Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE).isEmpty()) {
                    return true;
                }
            }
            return false;
        }

        /**
         * First "<root>", "<root> (2)", "<root> (3)"… name not taken by another segmentation.
         * The base is reduced to its root first so forking an already-forked copy increments
         * cleanly (test33new -> (2) -> (3)) instead of compounding suffixes (test33new (2) (2)).
         */
        String nextAvailableName(String baseName) {
            String root = stripCopySuffix(baseName);
            if (String.isBlank(root)) {
                root = 'Audience';
            }
            String likeTerm = String.escapeSingleQuotes(root) + '%';
            Set<String> taken = new Set<String>();
            for (Ken_Segmentation__c seg : [
                SELECT Name FROM Ken_Segmentation__c WHERE Name LIKE :likeTerm
                WITH SECURITY_ENFORCED
                LIMIT 2000
            ]) {
                taken.add(seg.Name);
            }
            if (!taken.contains(root)) {
                return root;
            }
            for (Integer i = 2; i <= 99; i++) {
                String candidate = root + ' (' + i + ')';
                if (!taken.contains(candidate)) {
                    return candidate;
                }
            }
            return root + ' ' + Datetime.now().getTime();
        }

        /** Removes trailing copy-counter suffixes " (2)", " (3) (4)"… added by prior forks. */
        String stripCopySuffix(String name) {
            if (String.isBlank(name)) {
                return name;
            }
            Matcher m = Pattern.compile('^(.*?)(?:\\s*\\(\\d+\\))+\\s*$').matcher(name);
            return m.matches() ? m.group(1).trim() : name.trim();
        }
    }

    /**
     * @description Points a module record at a saved audience, replacing whatever it had.
     * @param parentObjectType Module key from PARENT_OBJECT_BY_MODULE.
     * @param parentId Module record to link.
     * @param segmentationId Audience to link it to.
     * @return The parent record Id that now carries the audience.
     */
    @AuraEnabled
    public static Id linkSegmentationToParent(String parentObjectType, Id parentId, Id segmentationId) {
        if (parentId == null || segmentationId == null) {
            throw new AuraHandledException('Parent Id and Segmentation Id are required.');
        }
        String parentObject = parentObjectFor(parentObjectType);
        if (!isLinkable(parentObject)) {
            throw new AuraHandledException('Audience lookup not available on ' + parentObject);
        }

        new ElevatedLinker().link(parentObject, parentId, segmentationId);
        mirrorToDependentSurveys(parentObjectType, parentId);
        return parentId;
    }

    /**
     * Writes run in a system context: community users own the parent record but do not
     * always hold sharing access to it at save time — the page invoking this has already
     * authorized them at the parent level.
     */
    private without sharing class ElevatedLinker {
        Id link(String parentObject, Id parentId, Id segmentationId) {
            // A no-op write is skipped so the parent's after-update trigger does not run
            // for a value that is not changing.
            Id current = new ElevatedReader().fetchLinkedSegmentation(parentObject, parentId);
            if (current == segmentationId) {
                return parentId;
            }

            SObject parent = KenNamespaceUtil.resolveSObjectType(parentObject).newSObject();
            parent.put('Id', parentId);
            parent.put(SEG_FIELD, segmentationId);
            Database.update(parent, true, AccessLevel.SYSTEM_MODE);
            return parentId;
        }
    }
}