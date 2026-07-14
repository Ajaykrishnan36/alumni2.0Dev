/**
 * @description Trigger handler for Ken_Group_Member__c. Fires notifications
 */
public without sharing class KenGroupMemberTriggerHandler extends KenTriggerHandler {

    private static final String S_PENDING         = 'Pending';
    private static final String S_APPROVED        = 'Approved';
    private static final String S_REJECTED        = 'Rejected';
    private static final String S_INVITED         = 'Invited';
    private static final String S_INV_ACCEPTED    = 'Invite Accepted';
    private static final String S_INV_DECLINED    = 'Invite Declined';

    private static final Set<String> COUNTED_STATUSES = new Set<String>{ S_APPROVED, S_INV_ACCEPTED };

    private static final String TPL_JOIN_REQ_RECEIVED   = 'Group_Join_Request_Received';
    private static final String TPL_JOIN_REQ_APPROVED   = 'Group_Join_Request_Approved';
    private static final String TPL_JOIN_REQ_REJECTED   = 'Group_Join_Request_Rejected';
    private static final String TPL_INVITE_RECEIVED     = 'Group_Invite_Received';
    private static final String TPL_INVITE_ACCEPTED     = 'Group_Invite_Accepted';
    private static final String TPL_INVITE_DECLINED     = 'Group_Invite_Declined';

    public override void processAfterInsert() {
        handle((List<Ken_Group_Member__c>) Trigger.new, null);
        recalculateMemberCounts(collectGroupIds((List<Ken_Group_Member__c>) Trigger.new));
    }

    public override void processAfterUpdate() {
        handle((List<Ken_Group_Member__c>) Trigger.new, (Map<Id, Ken_Group_Member__c>) Trigger.oldMap);
        Set<Id> affected = collectGroupIds((List<Ken_Group_Member__c>) Trigger.new);
        affected.addAll(collectGroupIds((List<Ken_Group_Member__c>) Trigger.old));
        recalculateMemberCounts(affected);
    }

    public override void processAfterDelete() {
        recalculateMemberCounts(collectGroupIds((List<Ken_Group_Member__c>) Trigger.old));
    }

    public override void processAfterUndelete() {
        recalculateMemberCounts(collectGroupIds((List<Ken_Group_Member__c>) Trigger.new));
    }

    private static Set<Id> collectGroupIds(List<Ken_Group_Member__c> rows) {
        Set<Id> ids = new Set<Id>();
        if (rows == null) return ids;
        for (Ken_Group_Member__c gm : rows) {
            if (gm.Group__c != null) ids.add(gm.Group__c);
        }
        return ids;
    }

    /**
     * @description Recalculates Member_Count__c for the given groups. A member counts when
     * its Status__c is Approved or Invite Accepted and it is NOT the group creator. Bulk-safe:
     * a fixed number of SOQL/DML statements regardless of how many groups or members are involved.
     * This behaves like a roll-up summary but supports the OR-status filter and creator exclusion
     * that a native roll-up cannot express. Runs without sharing so the count is complete.
     */
    public static void recalculateMemberCounts(Set<Id> groupIds) {
        if (groupIds == null) return;
        groupIds.remove(null);
        if (groupIds.isEmpty()) return;

        Map<Id, Ken_Group__c> groupById = new Map<Id, Ken_Group__c>([
            SELECT Id, Created_By__c FROM Ken_Group__c WHERE Id IN :groupIds
        ]);
        if (groupById.isEmpty()) return;

        Set<Id> creatorIds = new Set<Id>();
        for (Ken_Group__c g : groupById.values()) {
            if (g.Created_By__c != null) creatorIds.add(g.Created_By__c);
        }

        Map<Id, Integer> countByGroup = new Map<Id, Integer>();
        for (Id gid : groupById.keySet()) {
            countByGroup.put(gid, 0);
        }

        for (AggregateResult ar : [
            SELECT Group__c gid, COUNT(Id) c
            FROM Ken_Group_Member__c
            WHERE Group__c IN :groupById.keySet() AND Status__c IN :COUNTED_STATUSES
            GROUP BY Group__c
        ]) {
            countByGroup.put((Id) ar.get('gid'), (Integer) ar.get('c'));
        }

        if (!creatorIds.isEmpty()) {
            for (Ken_Group_Member__c gm : [
                SELECT Group__c, Member__c
                FROM Ken_Group_Member__c
                WHERE Group__c IN :groupById.keySet()
                  AND Status__c IN :COUNTED_STATUSES
                  AND Member__c IN :creatorIds
            ]) {
                Ken_Group__c grp = groupById.get(gm.Group__c);
                if (grp != null && gm.Member__c == grp.Created_By__c && countByGroup.containsKey(gm.Group__c)) {
                    countByGroup.put(gm.Group__c, Math.max(0, countByGroup.get(gm.Group__c) - 1));
                }
            }
        }

        List<Ken_Group__c> toUpdate = new List<Ken_Group__c>();
        for (Id gid : countByGroup.keySet()) {
            toUpdate.add(new Ken_Group__c(Id = gid, Member_Count__c = countByGroup.get(gid)));
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static void handle(List<Ken_Group_Member__c> rows, Map<Id, Ken_Group_Member__c> oldMap) {
        if (rows == null || rows.isEmpty()) return;

        Set<Id> groupIds = new Set<Id>();
        for (Ken_Group_Member__c gm : rows) {
            if (gm.Group__c != null) groupIds.add(gm.Group__c);
        }
        Map<Id, Ken_Group__c> groupById = groupIds.isEmpty()
            ? new Map<Id, Ken_Group__c>()
            : new Map<Id, Ken_Group__c>([
                SELECT Id, Name, Created_By__c FROM Ken_Group__c WHERE Id IN :groupIds
            ]);

        List<KenNotificationFactory.Context> joinReceived  = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> joinApproved  = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> joinRejected  = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> inviteRecv    = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> inviteOk      = new List<KenNotificationFactory.Context>();
        List<KenNotificationFactory.Context> inviteNo      = new List<KenNotificationFactory.Context>();

        for (Ken_Group_Member__c gm : rows) {
            if (gm.Group__c == null || gm.Member__c == null) continue;
            Ken_Group__c grp = groupById.get(gm.Group__c);
            if (grp == null) continue;

            Ken_Group_Member__c old = (oldMap != null) ? oldMap.get(gm.Id) : null;
            String prevStatus = old != null ? old.Status__c : null;
            String curStatus  = gm.Status__c;
            String groupName  = grp.Name != null ? grp.Name : '';
            Id     adminId    = grp.Created_By__c;

            if (old == null) {
                if (curStatus == S_PENDING && adminId != null) {
                    joinReceived.add(buildCtx(adminId, gm.Member__c, gm.Group__c, groupName));
                } else if (curStatus == S_INVITED && gm.Invited_By__c != null) {
                    inviteRecv.add(buildCtx(gm.Member__c, gm.Invited_By__c, gm.Group__c, groupName));
                }
                continue;
            }

            if (curStatus == prevStatus) continue;

            if (prevStatus == S_PENDING) {
                if (curStatus == S_APPROVED) {
                    joinApproved.add(buildCtx(gm.Member__c, gm.Approved_Rejected_By__c, gm.Group__c, groupName));
                } else if (curStatus == S_REJECTED) {
                    joinRejected.add(buildCtx(gm.Member__c, gm.Approved_Rejected_By__c, gm.Group__c, groupName));
                }
            }
            else if (prevStatus == S_INVITED) {
                if (curStatus == S_INV_ACCEPTED && adminId != null) {
                    inviteOk.add(buildCtx(adminId, gm.Member__c, gm.Group__c, groupName));
                } else if (curStatus == S_INV_DECLINED && adminId != null) {
                    inviteNo.add(buildCtx(adminId, gm.Member__c, gm.Group__c, groupName));
                }
            }
        }

        try {
            if (!joinReceived.isEmpty()) KenNotificationFactory.create(TPL_JOIN_REQ_RECEIVED, joinReceived);
            if (!joinApproved.isEmpty()) KenNotificationFactory.create(TPL_JOIN_REQ_APPROVED, joinApproved);
            if (!joinRejected.isEmpty()) KenNotificationFactory.create(TPL_JOIN_REQ_REJECTED, joinRejected);
            if (!inviteRecv.isEmpty())   KenNotificationFactory.create(TPL_INVITE_RECEIVED,   inviteRecv);
            if (!inviteOk.isEmpty())     KenNotificationFactory.create(TPL_INVITE_ACCEPTED,   inviteOk);
            if (!inviteNo.isEmpty())     KenNotificationFactory.create(TPL_INVITE_DECLINED,   inviteNo);
        } catch (Exception ex) {
            System.debug('Group member notif dispatch tolerated — ' + ex.getMessage());
        }
    }

    private static KenNotificationFactory.Context buildCtx(Id recipient, Id sender, Id groupId, String groupName) {
        KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(recipient, sender, groupId);
        ctx.extras = new Map<String, String>{ 'Group.Name' => groupName != null ? groupName : '' };
        return ctx;
    }
}