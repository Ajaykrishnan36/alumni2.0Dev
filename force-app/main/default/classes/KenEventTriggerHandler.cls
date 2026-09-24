public without sharing class KenEventTriggerHandler extends KenTriggerHandler{

    public static final String NOTIFICATION_CATEGORY = 'Event';

    private static final String STATUS_PENDING   = 'In Review';
    private static final String STATUS_APPROVED  = 'Approved';
    private static final String STATUS_REJECTED  = 'Rejected';
    private static final String STATUS_CANCELLED = 'Cancelled';

    private static final String TPL_EVENT_APPROVED  = 'Event_Approved';
    private static final String TPL_EVENT_REJECTED  = 'Event_Rejected';
    private static final String TPL_EVENT_CANCELLED = 'Event_Cancelled';

    public override void processBeforeInsert(){
        KenInstitutePopulationService.stampInstitute(Trigger.new, Trigger.oldMap);
    }

    public override void processBeforeUpdate(){
        KenInstitutePopulationService.stampInstitute(Trigger.new, Trigger.oldMap);
    }

    public override void processAfterInsert(){
        pushToExternalSystem();
    }

    public override void processAfterUpdate(){
        submitEventForApproval();
        notifyOnApprovalDecision();
        notifyOnCancellation();
        sendSpeakerInvitesOnApproval();
        activateApprovedEvents();
        pushToExternalSystem();
    }

    // Hands the event to the external website when it goes live, stops being live, or changes
    // while live. The service owns the whole decision — whether the feature is on, whether this
    // org pushes at all, and what leaves the org — so there is deliberately no flag tested here.
    // Tolerated on failure: publishing an event must not depend on somebody else's server.
    private static void pushToExternalSystem() {
        try {
            if (Trigger.isInsert) {
                KenEventExternalPushService.pushOnInsert((List<Ken_Event_Master__c>) Trigger.new);
            } else {
                KenEventExternalPushService.pushOnUpdate(
                    (List<Ken_Event_Master__c>) Trigger.new,
                    (Map<Id, Ken_Event_Master__c>) Trigger.oldMap
                );
            }
        } catch (Exception ex) {
            System.debug('Event external push tolerated — ' + ex.getMessage());
        }
    }

    // Event_Status__c can be set to 'Approved' outside the real Approval Process
    // (e.g. clicking directly on the record's Path component, or a data load), which
    // skips the workflow field update that normally sets Is_Active__c. Keep it in sync
    // regardless of how the record got approved, so it never silently drops off the
    // portal's active-events list.
    private static void activateApprovedEvents() {
        Map<Id, Ken_Event_Master__c> oldMap = (Map<Id, Ken_Event_Master__c>) Trigger.oldMap;
        if (oldMap == null) return;

        List<Ken_Event_Master__c> toActivate = new List<Ken_Event_Master__c>();
        for (Ken_Event_Master__c ev : (List<Ken_Event_Master__c>) Trigger.New) {
            Ken_Event_Master__c old = oldMap.get(ev.Id);
            if (old == null) continue;
            if (ev.Event_Status__c == STATUS_APPROVED && old.Event_Status__c != STATUS_APPROVED && ev.Is_Active__c != true) {
                toActivate.add(new Ken_Event_Master__c(Id = ev.Id, Is_Active__c = true));
            }
        }
        if (!toActivate.isEmpty()) {
            try {
                if (!Schema.sObjectType.Ken_Event_Master__c.isUpdateable()) {
                    throw new KenCrudException('Ken_Event_Master__c is not updateable by the current user.');
                }
                update toActivate;
            } catch (Exception ex) {
                System.debug('Event auto-activate on approval tolerated — ' + ex.getMessage());
            }
        }
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