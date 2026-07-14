public class KenMentorshipTriggerHandler extends KenTriggerHandler {

    private static final String STATUS_REQUESTED = 'Requested';
    private static final String STATUS_ACCEPTED  = 'Accepted';
    private static final String STATUS_REJECTED  = 'Rejected';

    private static final String TPL_REQUEST  = 'Mentorship_Request_Received';
    private static final String TPL_ACCEPTED = 'Mentorship_Accepted';
    private static final String TPL_REJECTED = 'Mentorship_Rejected';

    private static final String TPL_CALL_REQUEST  = 'Mentorship_Call_Request_Received';
    private static final String TPL_CALL_ACCEPTED = 'Mentorship_Call_Request_Accepted';
    private static final String TPL_CALL_REJECTED = 'Mentorship_Call_Request_Rejected';

    public override void processAfterInsert() {
        notifyMentorOfRequest((List<Ken_Mentorship__c>) Trigger.new);
        notifyOtherPartyOfCallRequest((List<Ken_Mentorship__c>) Trigger.new, null);
    }

    public override void processAfterUpdate() {
        notifyMenteeOfResponse(
            (List<Ken_Mentorship__c>) Trigger.new,
            (Map<Id, Ken_Mentorship__c>) Trigger.oldMap
        );
        notifyOtherPartyOfCallRequest(
            (List<Ken_Mentorship__c>) Trigger.new,
            (Map<Id, Ken_Mentorship__c>) Trigger.oldMap
        );
        notifyRequesterOfCallResponse(
            (List<Ken_Mentorship__c>) Trigger.new,
            (Map<Id, Ken_Mentorship__c>) Trigger.oldMap
        );
    }

    @TestVisible
    private static void notifyMentorOfRequest(List<Ken_Mentorship__c> rows) {
        if (rows == null || rows.isEmpty()) return;
        List<KenNotificationFactory.Context> ctxs = new List<KenNotificationFactory.Context>();
        for (Ken_Mentorship__c m : rows) {
            if (m.Mentorship_Status__c != STATUS_REQUESTED) continue;
            if (m.Mentor__c == null || m.Mentee__c == null) continue;
            ctxs.add(new KenNotificationFactory.Context(m.Mentor__c, m.Mentee__c, m.Id));
        }
        if (!ctxs.isEmpty()) KenNotificationFactory.create(TPL_REQUEST, ctxs);
    }

    @TestVisible
    private static void notifyMenteeOfResponse(List<Ken_Mentorship__c> rows, Map<Id, Ken_Mentorship__c> oldMap) {
        if (rows == null || rows.isEmpty() || oldMap == null) return;
        List<KenNotificationFactory.Context> acceptedCtxs = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> rejectedCtxs = new List<KenNotificationFactory.Context>();

        for (Ken_Mentorship__c m : rows) {
            Ken_Mentorship__c old = oldMap.get(m.Id);
            if (old == null || old.Mentorship_Status__c != STATUS_REQUESTED) continue;
            if (m.Mentor__c == null || m.Mentee__c == null) continue;
            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(m.Mentee__c, m.Mentor__c, m.Id);
            if (m.Mentorship_Status__c == STATUS_ACCEPTED) acceptedCtxs.add(ctx);
            else if (m.Mentorship_Status__c == STATUS_REJECTED) rejectedCtxs.add(ctx);
        }
        if (!acceptedCtxs.isEmpty()) KenNotificationFactory.create(TPL_ACCEPTED, acceptedCtxs);
        if (!rejectedCtxs.isEmpty()) KenNotificationFactory.create(TPL_REJECTED, rejectedCtxs);
    }

    @TestVisible
    private static void notifyOtherPartyOfCallRequest(List<Ken_Mentorship__c> rows, Map<Id, Ken_Mentorship__c> oldMap) {
        if (rows == null || rows.isEmpty()) return;
        List<KenNotificationFactory.Context> ctxs = new List<KenNotificationFactory.Context>();
        for (Ken_Mentorship__c m : rows) {
            if (m.Call_Request_Status__c != STATUS_REQUESTED) continue;
            if (oldMap != null) {
                Ken_Mentorship__c old = oldMap.get(m.Id);
                if (old != null && old.Call_Request_Status__c == STATUS_REQUESTED) continue;
            }
            Id requester = m.MeetingRequestedBy__c;
            if (requester == null || m.Mentor__c == null || m.Mentee__c == null) continue;
            Id otherParty = (requester == m.Mentor__c) ? m.Mentee__c : m.Mentor__c;
            ctxs.add(new KenNotificationFactory.Context(otherParty, requester, m.Id));
        }
        if (!ctxs.isEmpty()) {
            try { KenNotificationFactory.create(TPL_CALL_REQUEST, ctxs); }
            catch (Exception ex) { System.debug('Call request-notif tolerated — ' + ex.getMessage()); }
        }
    }

    @TestVisible
    private static void notifyRequesterOfCallResponse(List<Ken_Mentorship__c> rows, Map<Id, Ken_Mentorship__c> oldMap) {
        if (rows == null || rows.isEmpty() || oldMap == null) return;
        List<KenNotificationFactory.Context> accepted = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> rejected = new List<KenNotificationFactory.Context>();
        for (Ken_Mentorship__c m : rows) {
            Ken_Mentorship__c old = oldMap.get(m.Id);
            if (old == null || old.Call_Request_Status__c != STATUS_REQUESTED) continue;
            Id requester = m.MeetingRequestedBy__c;
            if (requester == null || m.Mentor__c == null || m.Mentee__c == null) continue;
            Id otherParty = (requester == m.Mentor__c) ? m.Mentee__c : m.Mentor__c;
            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(requester, otherParty, m.Id);
            if (m.Call_Request_Status__c == STATUS_ACCEPTED) accepted.add(ctx);
            else if (m.Call_Request_Status__c == STATUS_REJECTED) rejected.add(ctx);
        }
        try {
            if (!accepted.isEmpty()) KenNotificationFactory.create(TPL_CALL_ACCEPTED, accepted);
            if (!rejected.isEmpty()) KenNotificationFactory.create(TPL_CALL_REJECTED, rejected);
        } catch (Exception ex) {
            System.debug('Call response-notif tolerated — ' + ex.getMessage());
        }
    }
}