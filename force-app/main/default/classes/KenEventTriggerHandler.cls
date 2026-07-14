public class KenEventTriggerHandler extends KenTriggerHandler{

    public static final String NOTIFICATION_CATEGORY = 'Event';

    private static final String STATUS_PENDING   = 'In Review';
    private static final String STATUS_APPROVED  = 'Approved';
    private static final String STATUS_REJECTED  = 'Rejected';
    private static final String STATUS_CANCELLED = 'Cancelled';

    private static final String TPL_EVENT_APPROVED  = 'Event_Approved';
    private static final String TPL_EVENT_REJECTED  = 'Event_Rejected';
    private static final String TPL_EVENT_CANCELLED = 'Event_Cancelled';

    public override void processAfterInsert(){
    }

    public override void processAfterUpdate(){
        submitEventForApproval();
        notifyOnApprovalDecision();
        notifyOnCancellation();
        sendSpeakerInvitesOnApproval();
    }

    // On approval, email the event's flagged speakers (async; tolerated on failure).
    private static void sendSpeakerInvitesOnApproval() {
        Map<Id, Ken_Event_Master__c> oldMap = (Map<Id, Ken_Event_Master__c>) Trigger.oldMap;
        if (oldMap == null) return;
        Set<Id> approvedEventIds = new Set<Id>();
        for (Ken_Event_Master__c ev : (List<Ken_Event_Master__c>) Trigger.New) {
            Ken_Event_Master__c old = oldMap.get(ev.Id);
            if (old == null) continue;
            if (ev.Event_Status__c == STATUS_APPROVED && old.Event_Status__c != STATUS_APPROVED) {
                approvedEventIds.add(ev.Id);
            }
        }
        if (!approvedEventIds.isEmpty()) {
            try {
                KenSpeakerInviteEmailService.enqueueForEvents(approvedEventIds);
            } catch (Exception ex) {
                System.debug('Speaker invite enqueue tolerated — ' + ex.getMessage());
            }
        }
    }

    @TestVisible
    private static void submitEventForApproval(){
        for(Ken_Event_Master__c event : (List<Ken_Event_Master__c>)Trigger.New){
            Map<Id,Ken_Event_Master__c> oldMap = (Map<Id,Ken_Event_Master__c>)Trigger.oldMap;
            Ken_Event_Master__c oldEvent = oldMap != null ? oldMap.get(event.Id) : null;

            // Submit to the approval process when the event moves into In Review (final submit).
            if (event.Event_Status__c == STATUS_PENDING && (oldEvent == null || oldEvent.Event_Status__c != STATUS_PENDING)) {
                KenApprovalProcessHelper.submitForApproval(
                    event.Id,
                    'Event_Publish_Approval',
                    null,
                    null
                );
            }
        }
    }

    private static void notifyOnApprovalDecision() {
        Map<Id, Ken_Event_Master__c> oldMap = (Map<Id, Ken_Event_Master__c>) Trigger.oldMap;
        if (oldMap == null) return;

        List<KenNotificationFactory.Context> approved = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> rejected = new List<KenNotificationFactory.Context>();

        for (Ken_Event_Master__c ev : (List<Ken_Event_Master__c>) Trigger.New) {
            Ken_Event_Master__c old = oldMap.get(ev.Id);
            if (old == null || ev.Event_Status__c == old.Event_Status__c) continue;
            if (ev.Person_Account__c == null) continue;

            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                ev.Person_Account__c, null, ev.Id
            );
            ctx.extras = new Map<String, String>{ 'Event.Name' => ev.Name };

            if (ev.Event_Status__c == STATUS_APPROVED)      approved.add(ctx);
            else if (ev.Event_Status__c == STATUS_REJECTED) rejected.add(ctx);
        }
        try {
            if (!approved.isEmpty()) KenNotificationFactory.create(TPL_EVENT_APPROVED, approved);
            if (!rejected.isEmpty()) KenNotificationFactory.create(TPL_EVENT_REJECTED, rejected);
        } catch (Exception ex) {
            System.debug('Event approval notif tolerated — ' + ex.getMessage());
        }
    }

    private static void notifyOnCancellation() {
        Map<Id, Ken_Event_Master__c> oldMap = (Map<Id, Ken_Event_Master__c>) Trigger.oldMap;
        if (oldMap == null) return;

        List<KenNotificationFactory.Context> ctxs = new List<KenNotificationFactory.Context>();
        for (Ken_Event_Master__c ev : (List<Ken_Event_Master__c>) Trigger.New) {
            Ken_Event_Master__c old = oldMap.get(ev.Id);
            if (old == null) continue;
            if (ev.Event_Status__c != STATUS_CANCELLED || old.Event_Status__c == STATUS_CANCELLED) continue;
            if (ev.Person_Account__c == null) continue;

            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                ev.Person_Account__c, null, ev.Id
            );
            ctx.extras = new Map<String, String>{ 'Event.Name' => ev.Name };
            ctxs.add(ctx);
        }
        if (!ctxs.isEmpty()) {
            try { KenNotificationFactory.create(TPL_EVENT_CANCELLED, ctxs); }
            catch (Exception ex) { System.debug('Event cancel notif tolerated — ' + ex.getMessage()); }
        }
    }
}