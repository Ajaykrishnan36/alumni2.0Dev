trigger KenConstituentRoleTrigger on ConstituentRole (after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.ConstituentRole_Trigger__c) {
        return;
    }

    new KenConstituentRoleTriggerHandler().process();
}