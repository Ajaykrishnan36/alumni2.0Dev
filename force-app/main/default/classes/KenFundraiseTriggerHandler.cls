public without sharing class KenFundraiseTriggerHandler extends KenTriggerHandler {
    private static final String STATUS_IN_REVIEW = 'In Review';
    private static final String STATUS_APPROVED  = 'Approved';
    private static final String STATUS_REJECTED  = 'Rejected';

    private static final String TPL_APPROVED  = 'Fundraise_Approved';
    private static final String TPL_REJECTED  = 'Fundraise_Rejected';

    public override void processAfterInsert() {
        submitNewCampaignsForApproval();
    }

    public override void processAfterUpdate() {
        submitNewCampaignsForApproval();
        notifyCreatorOfDecision();
    }

    private void submitNewCampaignsForApproval() {
        Map<Id, Ken_Fundraise__c> oldMap = (Map<Id, Ken_Fundraise__c>) Trigger.oldMap;
        for (Ken_Fundraise__c fr : (List<Ken_Fundraise__c>) Trigger.New) {
            Ken_Fundraise__c old = oldMap != null ? oldMap.get(fr.Id) : null;
            Boolean isNewSubmission = (fr.Approval_Status__c == STATUS_IN_REVIEW)
                && (old == null || old.Approval_Status__c != STATUS_IN_REVIEW);
            if (!isNewSubmission || fr.Constituent_Role__c == null) continue;

            KenApprovalProcessHelper.submitForApproval(
                fr.Id,
                'Fundraise_Campaign_Approval_Process',
                null,
                null
            );
        }
    }

    private void notifyCreatorOfDecision() {
        Map<Id, Ken_Fundraise__c> oldMap = (Map<Id, Ken_Fundraise__c>) Trigger.oldMap;
        if (oldMap == null) return;

        List<Ken_Fundraise__c> qualifying = new List<Ken_Fundraise__c>();
        Set<Id> roleIds = new Set<Id>();
        for (Ken_Fundraise__c fr : (List<Ken_Fundraise__c>) Trigger.New) {
            Ken_Fundraise__c old = oldMap.get(fr.Id);
            if (old == null || fr.Approval_Status__c == old.Approval_Status__c) continue;
            if (fr.Constituent_Role__c == null) continue;
            qualifying.add(fr);
            roleIds.add(fr.Constituent_Role__c);
        }
        if (qualifying.isEmpty()) return;

        Map<Id, ConstituentRole> roles = new Map<Id, ConstituentRole>([
            SELECT Id, PersonId FROM ConstituentRole WHERE Id IN :roleIds
        ]);

        List<KenNotificationFactory.Context> approved = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> rejected = new List<KenNotificationFactory.Context>();

        for (Ken_Fundraise__c fr : qualifying) {
            Ken_Fundraise__c old = oldMap.get(fr.Id);
            ConstituentRole role = roles.get(fr.Constituent_Role__c);
            if (role == null || role.PersonId == null) continue;

            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                role.PersonId, null, fr.Id
            );
            ctx.extras = new Map<String, String>{ 'Fundraise.Name' => fr.Name };

            if (fr.Approval_Status__c == STATUS_APPROVED && old.Approval_Status__c == STATUS_IN_REVIEW) approved.add(ctx);
            else if (fr.Approval_Status__c == STATUS_REJECTED) rejected.add(ctx);
        }
        try {
            if (!approved.isEmpty()) KenNotificationFactory.create(TPL_APPROVED, approved);
            if (!rejected.isEmpty()) KenNotificationFactory.create(TPL_REJECTED, rejected);
        } catch (Exception ex) {
            System.debug('Fundraise decision notif tolerated — ' + ex.getMessage());
        }
    }

}