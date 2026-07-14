trigger KenPersonEducationTrigger on PersonEducation (after insert) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.PersonEducation_Trigger__c) {
        return;
    }

    new KenPersonEducationTriggerHandler().process();
}