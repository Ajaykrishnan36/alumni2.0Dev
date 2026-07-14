public without sharing class KenBusinessDirectoryTriggerHandler extends KenTriggerHandler {
    private static final String OWNER_RT = 'Business_Owner';

    public override void processAfterInsert() { syncBusinessOwner(); }
    public override void processAfterUpdate() { syncBusinessOwner(); }

    // Mirror the owning ConstituentRole from the Business_Owner junction onto the business
    // Account's Business_Owner_Role__c lookup, so it shows (and is clickable) on the approval page / record.
    private static void syncBusinessOwner() {
        Id ownerRtId = Schema.SObjectType.Ken_Business_Directory__c
            .getRecordTypeInfosByDeveloperName().get(OWNER_RT).getRecordTypeId();

        Map<Id, Id> ownerByBusiness = new Map<Id, Id>();
        for (Ken_Business_Directory__c link : (List<Ken_Business_Directory__c>) Trigger.new) {
            if (link.RecordTypeId != ownerRtId) continue;
            if (link.Business_Account__c == null || link.Constituent_Role__c == null) continue;
            ownerByBusiness.put(link.Business_Account__c, link.Constituent_Role__c);
        }
        if (ownerByBusiness.isEmpty()) return;

        List<Account> updates = new List<Account>();
        for (Id businessId : ownerByBusiness.keySet()) {
            updates.add(new Account(Id = businessId, Business_Owner_Role__c = ownerByBusiness.get(businessId)));
        }
        update updates;
    }
}