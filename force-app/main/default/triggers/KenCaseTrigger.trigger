trigger KenCaseTrigger on Case (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            KenCaseTriggerHandler.handleBeforeInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            KenCaseTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            KenCaseCreatedEmailTriggerHandler.handleAfterInsert(Trigger.new);
            KenCaseEscalationEmailTriggerHandler.handleAfterInsert(Trigger.new);
            KenCaseTriggerHandler.handleHostelApprovalAfterInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            KenCaseCreatedEmailTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
            KenCaseEscalationEmailTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
            KenCaseTriggerHandler.handleGatePassAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}