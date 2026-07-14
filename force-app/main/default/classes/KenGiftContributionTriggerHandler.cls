/**
 * Validation for Ken_Gift_Contribution__c (trigger-based, per Phase 1 spec §11).
 *   - Amount must be > 0.
 *   - When allocations exist, their sum (Allocated_Total__c roll-up) must equal Amount.
 * The sum check only fires when allocations are present, so unallocated single-fund
 * donations are allowed. The roll-up recalculates the parent on allocation DML, which
 * re-fires this before-update — that's where the equality is enforced.
 */
public without sharing class KenGiftContributionTriggerHandler extends KenTriggerHandler {

    protected override void processBeforeInsert() {
        validate((List<Ken_Gift_Contribution__c>) Trigger.new, false);
    }

    protected override void processBeforeUpdate() {
        validate((List<Ken_Gift_Contribution__c>) Trigger.new, true);
    }

    private void validate(List<Ken_Gift_Contribution__c> records, Boolean isUpdate) {
        for (Ken_Gift_Contribution__c c : records) {
            if (c.Amount__c == null || c.Amount__c <= 0) {
                c.addError('Donation amount must be greater than zero.');
                continue;
            }
            // Allocated_Total__c is a roll-up summary (0 when there are no allocations).
            if (c.Allocated_Total__c != null && c.Allocated_Total__c > 0
                && c.Allocated_Total__c != c.Amount__c) {
                c.addError('Fund allocations (' + c.Allocated_Total__c
                    + ') must sum to the donation amount (' + c.Amount__c + ').');
            }
        }
    }
}