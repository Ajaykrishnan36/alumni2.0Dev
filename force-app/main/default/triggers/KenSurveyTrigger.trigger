trigger KenSurveyTrigger on Ken_Survey__c (after insert, after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();
    
    if(triggerSettings!= null && triggerSettings.Survey_Trigger__c){
        return;
    }

    new KenSurveyTriggerHandler().process();
}