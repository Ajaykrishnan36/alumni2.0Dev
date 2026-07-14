/**
 * Detects a payment capture and kicks off materialization.
 *
 * Fires on Ken_Gift_Payment__c after insert/update. A contribution is queued for
 * materialization only when its payment is newly 'Captured' (just-transitioned, so a
 * repeat 'Captured' webhook is ignored here; the materializer's Opportunity__c gate is
 * the second line of defence against duplicates).
 */
public without sharing class KenGiftPaymentTriggerHandler extends KenTriggerHandler {

    protected override void processAfterInsert() {
        collectAndMaterialize((List<Ken_Gift_Payment__c>) Trigger.new, null);
    }

    protected override void processAfterUpdate() {
        collectAndMaterialize(
            (List<Ken_Gift_Payment__c>) Trigger.new,
            (Map<Id, Ken_Gift_Payment__c>) Trigger.oldMap
        );
    }

    private void collectAndMaterialize(List<Ken_Gift_Payment__c> records, Map<Id, Ken_Gift_Payment__c> oldMap) {
        Set<Id> contributionIds = new Set<Id>();
        for (Ken_Gift_Payment__c p : records) {
            if (p.Status__c != 'Captured' || p.Contribution__c == null) continue;
            Ken_Gift_Payment__c old = (oldMap != null) ? oldMap.get(p.Id) : null;
            Boolean justCaptured = (old == null) || (old.Status__c != 'Captured');
            if (justCaptured) contributionIds.add(p.Contribution__c);
        }
        if (!contributionIds.isEmpty()) {
            KenGiftMaterializerService.materialize(contributionIds);
        }
    }
}