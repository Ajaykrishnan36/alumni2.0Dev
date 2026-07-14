trigger KenNetworkConnectionTrigger on Ken_Network_Connection__c (after insert, after update) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Network_Connection_Trigger__c) {
        return;
    }

    new KenNetworkConnectionTriggerHandler().process();
}