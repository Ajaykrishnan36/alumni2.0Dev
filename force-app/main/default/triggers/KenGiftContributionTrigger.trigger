trigger KenGiftContributionTrigger on Ken_Gift_Contribution__c (before insert, before update) {
    new KenGiftContributionTriggerHandler().process();
}