public without sharing class KenSurveyTriggerHandler extends KenTriggerHandler {
    private static final String APPROVAL_NAME = 'Survey_Approval_Process';

    private static final String STATUS_PENDING  = 'Pending Approval';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';

    private static final String TPL_SURVEY_SUBMITTED = 'Survey_Submitted_For_Approval';
    private static final String TPL_SURVEY_APPROVED  = 'Survey_Approved';
    private static final String TPL_SURVEY_REJECTED  = 'Survey_Rejected';

    public override void processAfterInsert() {
        submitSurveyForApproval();
        notifyAdminOnSubmission();
    }

    public override void processAfterUpdate() {
        submitSurveyForApproval();
        notifyAdminOnSubmission();
        notifyCreatorOfDecision();
    }

    private static void submitSurveyForApproval(){
        for(Ken_Survey__c survey : (List<Ken_Survey__c>)Trigger.New){
            Map<Id,Ken_Survey__c> oldMap = (Map<Id,Ken_Survey__c>)Trigger.oldMap;
            Ken_Survey__c oldSurvey = oldMap != null ? oldMap.get(survey.Id) : null;

            if (survey.Approval_Status__c == STATUS_PENDING
                && (oldSurvey == null || oldSurvey.Approval_Status__c != STATUS_PENDING)) {
                KenApprovalProcessHelper.submitForApproval(
                    survey.Id,
                    APPROVAL_NAME,
                    null,
                    null
                );
            }
        }
    }

    private static void notifyAdminOnSubmission() {
        Map<Id, Ken_Survey__c> oldMap = (Map<Id, Ken_Survey__c>) Trigger.oldMap;
        for (Ken_Survey__c srv : (List<Ken_Survey__c>) Trigger.New) {
            Ken_Survey__c old = oldMap != null ? oldMap.get(srv.Id) : null;
            if (srv.Approval_Status__c != STATUS_PENDING) continue;
            if (old != null && old.Approval_Status__c == STATUS_PENDING) continue;

            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                null, srv.Survey_Created_By__c, srv.Id
            );
            ctx.extras = new Map<String, String>{ 'Survey.Name' => srv.Name };
            try {
                KenNotificationFactory.createBroadcast(TPL_SURVEY_SUBMITTED, ctx, 'By_Role_Type');
            } catch (Exception ex) {
                System.debug('Survey submitted-admin notif tolerated — ' + ex.getMessage());
            }
        }
    }

    private static void notifyCreatorOfDecision() {
        Map<Id, Ken_Survey__c> oldMap = (Map<Id, Ken_Survey__c>) Trigger.oldMap;
        if (oldMap == null) return;

        List<KenNotificationFactory.Context> approved = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> rejected = new List<KenNotificationFactory.Context>();

        for (Ken_Survey__c srv : (List<Ken_Survey__c>) Trigger.New) {
            Ken_Survey__c old = oldMap.get(srv.Id);
            if (old == null || srv.Approval_Status__c == old.Approval_Status__c) continue;
            if (srv.Survey_Created_By__c == null) continue;

            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                srv.Survey_Created_By__c, null, srv.Id
            );
            ctx.extras = new Map<String, String>{ 'Survey.Name' => srv.Name };

            if (srv.Approval_Status__c == STATUS_APPROVED)      approved.add(ctx);
            else if (srv.Approval_Status__c == STATUS_REJECTED) rejected.add(ctx);
        }
        try {
            if (!approved.isEmpty()) KenNotificationFactory.create(TPL_SURVEY_APPROVED, approved);
            if (!rejected.isEmpty()) KenNotificationFactory.create(TPL_SURVEY_REJECTED, rejected);
        } catch (Exception ex) {
            System.debug('Survey decision notif tolerated — ' + ex.getMessage());
        }
    }
}