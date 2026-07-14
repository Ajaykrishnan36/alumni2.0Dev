trigger KenMentorshipTrigger on Ken_Mentorship__c (after insert, after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Mentorship_Trigger__c) {
        return;
    }

    new KenMentorshipTriggerHandler().process();
}