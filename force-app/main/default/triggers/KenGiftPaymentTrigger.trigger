trigger KenGiftPaymentTrigger on Ken_Gift_Payment__c (after insert, after update) {
    new KenGiftPaymentTriggerHandler().process();
}