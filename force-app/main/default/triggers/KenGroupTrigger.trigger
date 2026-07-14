trigger KenGroupTrigger on Ken_Group__c (after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Group_Trigger__c) {
        return;
    }

    new KenGroupTriggerHandler().process();
}