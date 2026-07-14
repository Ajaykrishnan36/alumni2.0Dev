/**
 * Fires Group_Post_New (group-wide, preference-gated) and Group_Post_Mention
 * for any new FeedItem posted on a Ken_Group__c record.
 *
 * Skips:
 *   - FeedItems whose ParentId isn't Ken_Group__c (other Chatter contexts)
 *   - TrackedChange / system-generated items (only TextPost / ContentPost / LinkPost)
 *   - Posts authored by the running user (no self-notification)
 *   - Polls (those fire Group_Poll_New from createPollPost instead — detected via
 *     Ken_Questionnaire_Parameter__c.Feed_Item__c set after the FeedItem insert
 *     within the same transaction).
 */
public without sharing class KenFeedItemTriggerHandler extends KenTriggerHandler {

    /**
     * Set by KenGroupFeedController.createPollPost before inserting the FeedItem so the
     * trigger skips the generic Group_Post_New broadcast — Group_Poll_New fires separately.
     * The controller resets this in a finally block.
     */
    public static Boolean suppressBroadcastForPoll = false;

    public override void processAfterInsert() {
        if (suppressBroadcastForPoll) return;

        List<FeedItem> rows = (List<FeedItem>) Trigger.New;
        if (rows == null || rows.isEmpty()) return;

        for (FeedItem fi : rows) {
            if (fi.ParentId == null) continue;
            if (fi.ParentId.getSObjectType() != Ken_Group__c.SObjectType) continue;
            String t = fi.Type;
            if (t != 'TextPost' && t != 'ContentPost' && t != 'LinkPost') continue;

            try {
                KenGroupFeedNotifications.notifyPostCreated(
                    fi.Id, fi.ParentId, fi.CreatedById, fi.Body
                );
            } catch (Exception ex) {
                System.debug('Group_Post_New dispatch tolerated: ' + ex.getMessage());
            }
        }
    }
}