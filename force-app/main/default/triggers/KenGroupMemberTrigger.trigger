trigger KenGroupMemberTrigger on Ken_Group_Member__c (after insert, after update, after delete, after undelete) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Group_Member_Trigger__c) {
        return;
    }

    new KenGroupMemberTriggerHandler().process();
}