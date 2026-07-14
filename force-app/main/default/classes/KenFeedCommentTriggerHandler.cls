/**
 * Fires Group_Post_Comment (to post author) and Group_Comment_Mention (to mentioned users)
 * for any new FeedComment on a Ken_Group__c-parented FeedItem.
 *
 * Group_Comment_Reply (nested replies) is intentionally not wired here — FeedComment is
 * flat in this org. Re-enable when a Parent_Comment__c custom field is added on FeedComment.
 */
public without sharing class KenFeedCommentTriggerHandler extends KenTriggerHandler {

    public override void processAfterInsert() {
        List<FeedComment> rows = (List<FeedComment>) Trigger.New;
        if (rows == null || rows.isEmpty()) return;

        for (FeedComment fc : rows) {
            if (fc.FeedItemId == null) continue;
            try {
                KenGroupFeedNotifications.notifyCommentCreated(
                    fc.Id, fc.FeedItemId, fc.CreatedById, fc.CommentBody
                );
            } catch (Exception ex) {
                System.debug('Comment notification dispatch tolerated: ' + ex.getMessage());
            }
        }
    }
}