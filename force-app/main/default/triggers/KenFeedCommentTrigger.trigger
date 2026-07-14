trigger KenFeedCommentTrigger on FeedComment (after insert) {

    Alumni_Trigger_Settings__c triggerSettings = Alumni_Trigger_Settings__c.getInstance();

    if (triggerSettings != null && triggerSettings.Feed_Comment_Trigger__c) {
        return;
    }

    new KenFeedCommentTriggerHandler().process();
}