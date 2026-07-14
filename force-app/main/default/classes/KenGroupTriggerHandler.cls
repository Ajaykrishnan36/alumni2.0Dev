public without sharing class KenGroupTriggerHandler extends KenTriggerHandler {
    private static final String APPROVAL_NAME = 'Ken_Group_Approval';

    private static final String STATUS_IN_REVIEW = 'In Review';
    private static final String STATUS_APPROVED  = 'Approved';
    private static final String STATUS_REJECTED  = 'Rejected';

    private static final String TPL_GROUP_APPROVED = 'Group_Approved';
    private static final String TPL_GROUP_REJECTED = 'Group_Rejected';

    public override void processAfterUpdate() {
        submitGroupsForApproval();
        notifyCreatorOfApprovalDecision();
    }

    private static void submitGroupsForApproval() {
        Map<Id, Ken_Group__c> oldMap = (Map<Id, Ken_Group__c>)Trigger.oldMap;
        for (Ken_Group__c grp : (List<Ken_Group__c>)Trigger.New) {
            Ken_Group__c oldGrp = oldMap != null ? oldMap.get(grp.Id) : null;
            if (grp.Status__c == STATUS_IN_REVIEW
                    && (oldGrp == null || oldGrp.Status__c != STATUS_IN_REVIEW)) {
                KenApprovalProcessHelper.submitForApproval(grp.Id, APPROVAL_NAME, null, null);
            }
        }
    }

    private static void notifyCreatorOfApprovalDecision() {
        Map<Id, Ken_Group__c> oldMap = (Map<Id, Ken_Group__c>)Trigger.oldMap;
        if (oldMap == null) return;

        List<KenNotificationFactory.Context> approved = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> rejected = new List<KenNotificationFactory.Context>();

        for (Ken_Group__c grp : (List<Ken_Group__c>)Trigger.New) {
            Ken_Group__c oldGrp = oldMap.get(grp.Id);
            if (oldGrp == null) continue;
            if (grp.Status__c == oldGrp.Status__c) continue;
            if (grp.Created_By__c == null) continue;

            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                grp.Created_By__c, null, grp.Id
            );
            ctx.extras = new Map<String, String>{ 'Group.Name' => grp.Name };

            if (grp.Status__c == STATUS_APPROVED)      approved.add(ctx);
            else if (grp.Status__c == STATUS_REJECTED) rejected.add(ctx);
        }
        try {
            if (!approved.isEmpty()) KenNotificationFactory.create(TPL_GROUP_APPROVED, approved);
            if (!rejected.isEmpty()) KenNotificationFactory.create(TPL_GROUP_REJECTED, rejected);
        } catch (Exception ex) {
            System.debug('Group approval notif tolerated — ' + ex.getMessage());
        }
    }
}