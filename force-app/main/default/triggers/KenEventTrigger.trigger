trigger KenEventTrigger on Ken_Event_Master__c (after insert, after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Event_Trigger__c) {
        return;
    }

    new KenEventTriggerHandler().process();
}