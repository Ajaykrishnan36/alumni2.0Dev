trigger KenLeadTrigger on Lead (before insert, after insert, after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();
    
    if(triggerSettings!= null && triggerSettings.Lead_Trigger__c){
        return;
    }

    new KenLeadTriggerHandler().process();
}