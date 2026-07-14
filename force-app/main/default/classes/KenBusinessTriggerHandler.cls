public without sharing class KenBusinessTriggerHandler extends KenTriggerHandler {
    private static final String BUSINESS_RT      = 'Business';
    private static final String STATUS_PENDING   = 'Pending';
    private static final String APPROVER_GROUP   = 'Business_Approvers';
    private static final String APPROVAL_PROCESS = 'Business_Approval_Process';

    // Feature ("featured business") approval — keyed off a SEPARATE field
    // (Business_Feature_Approval__c) so it never interferes with the business-
    // approval process above. Reuses the same Business_Approvers group.
    private static final String FEATURE_STATUS_PENDING   = 'Pending Approval';
    private static final String FEATURE_APPROVAL_PROCESS = 'Business_Feature_Approval_Process';

    private static Id businessRtIdCache;
    private static Id getBusinessRtId() {
        if (businessRtIdCache == null) {
            businessRtIdCache = Schema.SObjectType.Account
                .getRecordTypeInfosByDeveloperName().get(BUSINESS_RT).getRecordTypeId();
        }
        return businessRtIdCache;
    }

    // Resolve (once) an active member of the Business_Approvers queue.
    private static Boolean approverResolved = false;
    private static Id cachedApproverId;
    private static Id resolveApproverId() {
        if (!approverResolved) {
            approverResolved = true;
            List<Group> groups = [
                SELECT Id FROM Group WHERE DeveloperName = :APPROVER_GROUP AND Type = 'Queue' LIMIT 1
            ];
            if (!groups.isEmpty()) {
                Set<Id> memberIds = new Set<Id>();
                for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :groups[0].Id]) {
                    memberIds.add(gm.UserOrGroupId);
                }
                if (!memberIds.isEmpty()) {
                    List<User> users = [
                        SELECT Id FROM User WHERE Id IN :memberIds AND IsActive = true ORDER BY Name LIMIT 1
                    ];
                    if (!users.isEmpty()) {
                        cachedApproverId = users[0].Id;
                    }
                }
            }
        }
        return cachedApproverId;
    }

    public override void processBeforeInsert() { assignApprover(); assignFeatureApprover(); }
    public override void processBeforeUpdate() { assignApprover(); assignFeatureApprover(); }
    public override void processAfterInsert()  { handlePendingBusinesses(); handlePendingFeatureRequests(); }
    public override void processAfterUpdate()  { handlePendingBusinesses(); handlePendingFeatureRequests(); }

    // BEFORE context: stamp the approver (a Business_Approvers queue member) onto newly-Pending
    // businesses so the approval process can route to that user via the relatedUserField.
    private static void assignApprover() {
        Id bizRtId = getBusinessRtId();
        Map<Id, Account> oldMap = (Map<Id, Account>) Trigger.oldMap;
        for (Account acc : (List<Account>) Trigger.new) {
            if (acc.RecordTypeId != bizRtId) continue;
            if (acc.Business_Approval__c != STATUS_PENDING) continue;
            Account oldAcc = oldMap != null ? oldMap.get(acc.Id) : null;
            Boolean newlyPending = (oldAcc == null || oldAcc.Business_Approval__c != STATUS_PENDING);
            if (newlyPending && acc.Business_Approver__c == null) {
                Id approverId = resolveApproverId();
                if (approverId != null) {
                    acc.Business_Approver__c = approverId;
                }
            }
        }
    }

    // BEFORE context: stamp Featured_Approver__c on newly feature-pending businesses.
    private static void assignFeatureApprover() {
        Id bizRtId = getBusinessRtId();
        Map<Id, Account> oldMap = (Map<Id, Account>) Trigger.oldMap;
        for (Account acc : (List<Account>) Trigger.new) {
            if (acc.RecordTypeId != bizRtId) continue;
            if (acc.Business_Feature_Approval__c != FEATURE_STATUS_PENDING) continue;
            Account oldAcc = oldMap != null ? oldMap.get(acc.Id) : null;
            Boolean newlyPending = (oldAcc == null || oldAcc.Business_Feature_Approval__c != FEATURE_STATUS_PENDING);
            if (newlyPending && acc.Featured_Approver__c == null) {
                Id approverId = resolveApproverId();
                if (approverId != null) {
                    acc.Featured_Approver__c = approverId;
                }
            }
        }
    }

    // AFTER context: bell-notify the approver group + auto-submit to the approval process.
    private static void handlePendingBusinesses() {
        Id bizRtId = getBusinessRtId();
        Map<Id, Account> oldMap = (Map<Id, Account>) Trigger.oldMap;
        List<Account> pending = new List<Account>();
        for (Account acc : (List<Account>) Trigger.new) {
            if (acc.RecordTypeId != bizRtId) continue;
            if (acc.Business_Approval__c != STATUS_PENDING) continue;
            Account oldAcc = oldMap != null ? oldMap.get(acc.Id) : null;
            if (oldAcc == null || oldAcc.Business_Approval__c != STATUS_PENDING) {
                pending.add(acc);
            }
        }
        if (pending.isEmpty()) return;

        submitForApproval(pending);
    }

    private static void submitForApproval(List<Account> businesses) {
        for (Account biz : businesses) {
            KenApprovalProcessHelper.submitForApproval(biz.Id, APPROVAL_PROCESS, biz.OwnerId, null);
        }
    }


    // AFTER context: notify the approver group + submit to the FEATURE approval process.
    private static void handlePendingFeatureRequests() {
        Id bizRtId = getBusinessRtId();
        Map<Id, Account> oldMap = (Map<Id, Account>) Trigger.oldMap;
        List<Account> pending = new List<Account>();
        for (Account acc : (List<Account>) Trigger.new) {
            if (acc.RecordTypeId != bizRtId) continue;
            if (acc.Business_Feature_Approval__c != FEATURE_STATUS_PENDING) continue;
            Account oldAcc = oldMap != null ? oldMap.get(acc.Id) : null;
            if (oldAcc == null || oldAcc.Business_Feature_Approval__c != FEATURE_STATUS_PENDING) {
                pending.add(acc);
            }
        }
        if (pending.isEmpty()) return;

        for (Account biz : pending) {
            String comment = String.isNotBlank(biz.Feature_Subject__c) ? biz.Feature_Subject__c : 'Feature request';
            if (String.isNotBlank(biz.Feature_Message__c)) {
                comment += ' — ' + biz.Feature_Message__c;
            }
            KenApprovalProcessHelper.submitForApproval(biz.Id, FEATURE_APPROVAL_PROCESS, null, comment);
        }
    }
}