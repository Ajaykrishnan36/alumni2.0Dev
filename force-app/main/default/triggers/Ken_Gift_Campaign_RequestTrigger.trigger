trigger Ken_Gift_Campaign_RequestTrigger on Ken_Gift_Campaign_Request__c (after insert, after update) {
    new KenGiftCampaignRequestTriggerHandler().handleAfter(Trigger.new, Trigger.oldMap);
}