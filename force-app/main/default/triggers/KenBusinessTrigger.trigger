trigger KenBusinessTrigger on Account (before insert, before update, after insert, after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Business_Trigger__c) {
        return;
    }

    new KenBusinessTriggerHandler().process();
}