trigger KenFeedItemTrigger on FeedItem (after insert) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Feed_Item_Trigger__c) {
        return;
    }

    new KenFeedItemTriggerHandler().process();
}