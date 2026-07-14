/**
 * @description Trigger handler for Ken_Network_Connection__c. Fires notifications
 */
public without sharing class KenNetworkConnectionTriggerHandler extends KenTriggerHandler {

    private static final String TPL_REQUEST_RECEIVED = 'Network_Connection_Request_Received';
    private static final String TPL_REQUEST_REJECTED = 'Network_Connection_Request_Rejected';
    private static final String STATUS_REQUESTED = 'Requested';
    private static final String STATUS_REJECTED  = 'Rejected';

    public override void processAfterInsert() {
        notifyRequestRecipients((List<Ken_Network_Connection__c>) Trigger.new);
    }

    public override void processAfterUpdate() {
        notifyInitiatorOfRejection(
            (List<Ken_Network_Connection__c>) Trigger.new,
            (Map<Id, Ken_Network_Connection__c>) Trigger.oldMap
        );
    }

    private static void notifyRequestRecipients(List<Ken_Network_Connection__c> rows) {
        if (rows == null || rows.isEmpty()) return;

        List<KenNotificationFactory.Context> ctxs = new List<KenNotificationFactory.Context>();
        for (Ken_Network_Connection__c conn : rows) {
            if (conn == null) continue;
            if (conn.Status__c != STATUS_REQUESTED) continue;
            if (conn.Recipient__c == null || conn.Initiator__c == null) continue;
            ctxs.add(new KenNotificationFactory.Context(
                conn.Recipient__c,
                conn.Initiator__c,
                conn.Initiator__c   // sourceRecordId → {!Id} resolves to the requester's profile id
            ));
        }
        if (ctxs.isEmpty()) return;
        try {
            KenNotificationFactory.create(TPL_REQUEST_RECEIVED, ctxs);
        } catch (Exception ex) {
            System.debug('Network rec-notif tolerated — ' + ex.getMessage());
        }
    }

    private static void notifyInitiatorOfRejection(List<Ken_Network_Connection__c> rows, Map<Id, Ken_Network_Connection__c> oldMap) {
        if (rows == null || rows.isEmpty() || oldMap == null) return;

        List<KenNotificationFactory.Context> ctxs = new List<KenNotificationFactory.Context>();
        for (Ken_Network_Connection__c conn : rows) {
            Ken_Network_Connection__c old = oldMap.get(conn.Id);
            if (old == null) continue;
            if (conn.Status__c != STATUS_REJECTED || old.Status__c == STATUS_REJECTED) continue;
            if (conn.Initiator__c == null || conn.Recipient__c == null) continue;
            ctxs.add(new KenNotificationFactory.Context(
                conn.Initiator__c,
                conn.Recipient__c,
                conn.Id
            ));
        }
        if (ctxs.isEmpty()) return;
        try {
            KenNotificationFactory.create(TPL_REQUEST_REJECTED, ctxs);
        } catch (Exception ex) {
            System.debug('Network rejection-notif tolerated — ' + ex.getMessage());
        }
    }
}