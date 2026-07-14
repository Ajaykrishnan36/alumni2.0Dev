trigger KenGiftAllocationTrigger on Ken_Gift_Allocation__c (before insert, before update) {
    new KenGiftAllocationTriggerHandler().process();
}