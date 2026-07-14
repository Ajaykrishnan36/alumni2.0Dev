/**
 * KenSegmentationAudienceBatch
 *
 * Reusable Batch that streams the base-object record ids of a saved segmentation's audience and
 * hands each chunk to a pluggable processor (e.g. an email/notification sender).
 *
 * Why batch: COUNT() of an audience is unlimited, but *fetching* the matched records is capped at
 * 50,000 rows per transaction. Batch Apex streams via a QueryLocator, so the audience scales to
 * millions. Each audience item is one valid query (semi-joins stay at the top level); items are
 * processed in sequence and de-duplicated in Apex (their OR-union can't be one SOQL).
 *
 * The audience stays DYNAMIC: each run re-resolves the live semi-joins, so newly qualifying
 * records are included automatically - nothing is baked into a stored id list.
 *
 * Usage:
 *   KenSegmentationAudienceBatch.run(segmentationId, 'MyProcessorClass', 2000);
 * where MyProcessorClass implements KenSegmentationAudienceBatch.Processor.
 */
public without sharing class KenSegmentationAudienceBatch implements Database.Batchable<SObject>, Database.Stateful {

    public interface Processor {
        void handle(Id segmentationId, List<Id> baseIds);
        void onComplete(Id segmentationId, Integer distinctPeople);
    }

    private final Id segmentationId;
    private final String processorType;
    private final List<String> itemQueries;
    private final String anchorField;
    private final Integer itemIndex;
    private final Integer scopeSize;

    private Set<Id> seenBase;
    private Set<Id> seenPeople;

    public static Id run(Id segmentationId, String processorType, Integer scopeSize) {
        Integer sz = (scopeSize == null || scopeSize <= 0 || scopeSize > 2000) ? 2000 : scopeSize;
        List<String> queries = KenAudienceEngineService.buildAudienceItemQueries(segmentationId);
        String anchor = KenAudienceEngineService.getSegmentationAnchorField(segmentationId);
        return Database.executeBatch(
            new KenSegmentationAudienceBatch(segmentationId, processorType, queries, anchor, 0, sz,
                new Set<Id>(), new Set<Id>()),
            sz);
    }

    private KenSegmentationAudienceBatch(Id segmentationId, String processorType, List<String> itemQueries,
        String anchorField, Integer itemIndex, Integer scopeSize, Set<Id> seenBase, Set<Id> seenPeople) {
        this.segmentationId = segmentationId;
        this.processorType = processorType;
        this.itemQueries = (itemQueries == null) ? new List<String>() : itemQueries;
        this.anchorField = String.isBlank(anchorField) ? 'Id' : anchorField;
        this.itemIndex = itemIndex;
        this.scopeSize = scopeSize;
        this.seenBase = seenBase;
        this.seenPeople = seenPeople;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String soql = (itemIndex < itemQueries.size()) ? itemQueries[itemIndex] : null;
        if (String.isBlank(soql)) {
            String baseObj = KenAudienceEngineService.getSegmentationBaseObject(segmentationId);
            soql = 'SELECT Id FROM ' + baseObj + ' WHERE Id = null';
        }
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Id> newIds = new List<Id>();
        Boolean hasAnchor = !anchorField.equalsIgnoreCase('Id');
        for (SObject s : scope) {
            Id baseId = (Id)s.get('Id');
            if (baseId == null) continue;
            if (seenBase.add(baseId)) {
                newIds.add(baseId);
            }
            Object personVal = hasAnchor ? safeGet(s, anchorField) : baseId;
            if (personVal != null) seenPeople.add((Id)personVal);
        }
        if (!newIds.isEmpty() && !String.isBlank(processorType)) {
            Processor p = newProcessor();
            if (p != null) p.handle(segmentationId, newIds);
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (itemIndex + 1 < itemQueries.size()) {
            Database.executeBatch(
                new KenSegmentationAudienceBatch(segmentationId, processorType, itemQueries, anchorField,
                    itemIndex + 1, scopeSize, seenBase, seenPeople),
                scopeSize);
            return;
        }
        KenAudienceEngineService.updateSegmentationCount(segmentationId, seenPeople.size());
        if (!String.isBlank(processorType)) {
            Processor p = newProcessor();
            if (p != null) p.onComplete(segmentationId, seenPeople.size());
        }
    }

    private Processor newProcessor() {
        Type t = Type.forName(processorType);
        if (t == null) return null;
        Object inst = t.newInstance();
        return (inst instanceof Processor) ? (Processor)inst : null;
    }

    private static Object safeGet(SObject s, String field) {
        try { return s.get(field); } catch (Exception e) { return null; }
    }
}