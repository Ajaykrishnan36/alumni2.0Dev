trigger KenBusinessDirectoryTrigger on Ken_Business_Directory__c (after insert, after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Business_Directory_Trigger__c) {
        return;
    }

    new KenBusinessDirectoryTriggerHandler().process();
}