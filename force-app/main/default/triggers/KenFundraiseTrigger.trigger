trigger KenFundraiseTrigger on Ken_Fundraise__c (after insert, after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Fundraise_Trigger__c) {
        return;
    }

    new KenFundraiseTriggerHandler().process();
}