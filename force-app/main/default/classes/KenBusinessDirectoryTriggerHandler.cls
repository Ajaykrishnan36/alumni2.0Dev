public without sharing class KenBusinessDirectoryTriggerHandler extends KenTriggerHandler {
    private static final String OWNER_RT = 'Business_Owner';

    // Name is a plain Text(80) that no code ever populated, so rows showed their own
    // record Id as the link label in list views. Cap matches the field length.
    private static final Integer NAME_MAX = 80;

    public override void processBeforeInsert() {
        KenInstitutePopulationService.stampInstitute(Trigger.new, Trigger.oldMap);
        stampName();
    }

    public override void processBeforeUpdate() {
        KenInstitutePopulationService.stampInstitute(Trigger.new, Trigger.oldMap);
        stampName();
    }

    public override void processAfterInsert() { syncBusinessOwner(); }
    public override void processAfterUpdate() { syncBusinessOwner(); }

    // Build the readable label for a junction row: "<business account> - Owner|Prospect".
    // The record type is the only thing that distinguishes two rows on the same business,
    // so it reads better than the constituent-role auto-number. Truncates the business
    // name rather than the suffix, so the suffix stays visible on long business names.
    // Public so the one-time backfill script reuses the same rule.
    public static String buildLinkName(String businessName, Id recordTypeId) {
        String base = String.isNotBlank(businessName) ? businessName.trim() : 'Business link';
        String kind = recordTypeLabel(recordTypeId);
        String suffix = String.isNotBlank(kind) ? ' - ' + kind : '';
        Integer room = NAME_MAX - suffix.length();
        if (room < 0) {
            room = 0;
        }
        if (base.length() > room) {
            base = base.substring(0, room);
        }
        return base + suffix;
    }

    // Business_Owner -> "Owner", Business_Prospect -> "Prospect".
    private static String recordTypeLabel(Id recordTypeId) {
        if (recordTypeId == null) {
            return '';
        }
        Schema.RecordTypeInfo info = Schema.SObjectType.Ken_Business_Directory__c
            .getRecordTypeInfosById().get(recordTypeId);
        if (info == null) {
            return '';
        }
        String devName = info.getDeveloperName();
        return devName.startsWith('Business_') ? devName.substring(9) : devName;
    }

    // A row needs a name if it has none yet (inserts), or if it still carries the legacy
    // value where the record's own Id stood in for the name.
    private static Boolean needsName(Ken_Business_Directory__c link) {
        if (String.isBlank(link.Name)) {
            return true;
        }
        return link.Id != null && String.valueOf(link.Id).startsWith(link.Name);
    }

    // BEFORE context: stamp Name from the related business account and the record type.
    private static void stampName() {
        Set<Id> accountIds = new Set<Id>();
        for (Ken_Business_Directory__c link : (List<Ken_Business_Directory__c>) Trigger.new) {
            if (needsName(link) && link.Business_Account__c != null) {
                accountIds.add(link.Business_Account__c);
            }
        }
        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accountsById = new Map<Id, Account>([
            SELECT Id, Name FROM Account WHERE Id IN :accountIds
        WITH SECURITY_ENFORCED
        ]);

        for (Ken_Business_Directory__c link : (List<Ken_Business_Directory__c>) Trigger.new) {
            if (!needsName(link)) {
                continue;
            }
            Account acc = accountsById.get(link.Business_Account__c);
            link.Name = buildLinkName(acc != null ? acc.Name : null, link.RecordTypeId);
        }
    }

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
        if (!Schema.sObjectType.Account.isUpdateable()) {
            throw new KenCrudException('Account is not updateable by the current user.');
        }
        update updates;
    }
}