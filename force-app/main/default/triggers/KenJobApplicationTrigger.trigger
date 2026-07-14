trigger KenJobApplicationTrigger on Ken_Job_Application__c (before insert, before update, after insert, after update, after delete, after undelete) {
    new KenJobApplicationTriggerHandler().process();
}