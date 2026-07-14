/**
 * Validation for Ken_Gift_Allocation__c (trigger-based, per Phase 1 spec §11).
 *   - Amount must be > 0.
 *   - Fund is required (enforced here rather than field-level so the donor permission
 *     set can keep editable FLS on Fund__c).
 */
public without sharing class KenGiftAllocationTriggerHandler extends KenTriggerHandler {

    protected override void processBeforeInsert() {
        validate((List<Ken_Gift_Allocation__c>) Trigger.new);
    }

    protected override void processBeforeUpdate() {
        validate((List<Ken_Gift_Allocation__c>) Trigger.new);
    }

    private void validate(List<Ken_Gift_Allocation__c> records) {
        for (Ken_Gift_Allocation__c a : records) {
            if (a.Amount__c == null || a.Amount__c <= 0) {
                a.addError('Allocation amount must be greater than zero.');
            }
            if (a.Fund__c == null) {
                a.addError('Each allocation must reference a Fund.');
            }
        }
    }
}