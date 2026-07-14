/**
 * Notification dispatch for the Group Feed feature.
 *
 * Responsibilities:
 *   - Parse @mention markers from rich-text body
 *   - Resolve group membership + per-member preferences
 *   - Skip self-notifications and dedupe (e.g. mention recipients don't ALSO get the broadcast)
 *   - Hand off to KenNotificationFactory
 *
 * Mention convention: any HTML anchor with data-mention-user-id="<UserId>" in the body.
 * Example: <a data-mention-user-id="005xxxxxxxxxxxx" href="/profile/...">@John</a>
 */
public without sharing class KenGroupFeedNotifications {

    // ── Public entry points ───────────────────────────────────────────────

    /** New post landed in a group. Fires Group_Post_New + Group_Post_Mention. */
    public static void notifyPostCreated(Id feedItemId, Id parentGroupId, Id authorUserId, String body) {
        if (feedItemId == null || parentGroupId == null) return;
        Id authorAccountId = userToAccount(authorUserId);
        Set<Id> mentionedUserIds = parseMentions(body);
        Set<Id> mentionedAccountIds = usersToAccounts(mentionedUserIds);
        mentionedAccountIds.remove(authorAccountId);

        // Mentions first — they get a higher-signal notification
        dispatchMentions('Group_Post_Mention', mentionedAccountIds, authorAccountId,
            parentGroupId, snippet(body, 80), null, null);

        // Broadcast to all eligible group members, EXCLUDING mentioned users (they got the better one)
        Set<Id> recipients = eligibleGroupMembers(parentGroupId, 'New posts');
        recipients.remove(authorAccountId);
        recipients.removeAll(mentionedAccountIds);
        dispatchToMany('Group_Post_New', recipients, authorAccountId, parentGroupId,
            new Map<String, String>{
                'Group.Name'   => groupName(parentGroupId),
                'Post.Snippet' => snippet(body, 100)
            });
    }

    /** New comment landed. Fires Group_Post_Comment to post author + Group_Comment_Mention to mentioned users. */
    public static void notifyCommentCreated(Id feedCommentId, Id feedItemId, Id commenterUserId, String commentBody) {
        if (feedCommentId == null || feedItemId == null) return;

        List<FeedItem> fis = [SELECT ParentId, CreatedById FROM FeedItem WHERE Id = :feedItemId LIMIT 1];
        if (fis.isEmpty()) return;
        Id parentGroupId = fis[0].ParentId;
        if (parentGroupId == null || parentGroupId.getSObjectType() != Ken_Group__c.SObjectType) return;

        Id commenterAccountId = userToAccount(commenterUserId);
        Id postAuthorAccountId = userToAccount(fis[0].CreatedById);
        Set<Id> mentionedUserIds = parseMentions(commentBody);
        Set<Id> mentionedAccountIds = usersToAccounts(mentionedUserIds);
        mentionedAccountIds.remove(commenterAccountId);

        // 1. @mentions in comment → Group_Comment_Mention
        dispatchMentions('Group_Comment_Mention', mentionedAccountIds, commenterAccountId,
            parentGroupId, snippet(commentBody, 80), feedCommentId, null);

        // 2. Comment to post author → Group_Post_Comment (skip if author is the commenter or already mentioned)
        if (postAuthorAccountId != null
                && postAuthorAccountId != commenterAccountId
                && !mentionedAccountIds.contains(postAuthorAccountId)) {
            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                postAuthorAccountId, commenterAccountId, parentGroupId
            );
            ctx.extras = new Map<String, String>{
                'Group.Name'      => groupName(parentGroupId),
                'Comment.Snippet' => snippet(commentBody, 100),
                'Comment.Id'      => String.valueOf(feedCommentId)
            };
            safeCreate('Group_Post_Comment', ctx);
        }
    }

    /** New poll posted. Fires Group_Poll_New to group members opted into "Polls". */
    public static void notifyPollCreated(Id feedItemId, Id parentGroupId, Id authorUserId, String question) {
        if (parentGroupId == null) return;
        Id authorAccountId = userToAccount(authorUserId);
        Set<Id> recipients = eligibleGroupMembers(parentGroupId, 'Polls');
        recipients.remove(authorAccountId);
        dispatchToMany('Group_Poll_New', recipients, authorAccountId, parentGroupId,
            new Map<String, String>{
                'Group.Name'    => groupName(parentGroupId),
                'Poll.Question' => snippet(question, 200)
            });
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static void dispatchMentions(
        String tplDevName, Set<Id> mentionedAccountIds, Id senderAccountId,
        Id parentGroupId, String snippetText, Id commentId, Id postId
    ) {
        if (mentionedAccountIds == null || mentionedAccountIds.isEmpty()) return;
        String groupName = groupName(parentGroupId);
        List<KenNotificationFactory.Context> ctxs = new List<KenNotificationFactory.Context>();
        for (Id recipient : mentionedAccountIds) {
            if (recipient == null) continue;
            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                recipient, senderAccountId, parentGroupId
            );
            ctx.extras = new Map<String, String>{
                'Group.Name'      => groupName,
                'Comment.Snippet' => snippetText == null ? '' : snippetText
            };
            if (commentId != null) ctx.extras.put('Comment.Id', String.valueOf(commentId));
            if (postId != null)    ctx.extras.put('Post.Id',    String.valueOf(postId));
            ctxs.add(ctx);
        }
        safeCreateMany(tplDevName, ctxs);
    }

    private static void dispatchToMany(
        String tplDevName, Set<Id> recipientAccountIds, Id senderAccountId, Id parentGroupId,
        Map<String, String> extras
    ) {
        if (recipientAccountIds == null || recipientAccountIds.isEmpty()) return;
        List<KenNotificationFactory.Context> ctxs = new List<KenNotificationFactory.Context>();
        for (Id recipient : recipientAccountIds) {
            if (recipient == null) continue;
            KenNotificationFactory.Context ctx = new KenNotificationFactory.Context(
                recipient, senderAccountId, parentGroupId
            );
            ctx.extras = extras == null ? new Map<String, String>() : extras.clone();
            ctxs.add(ctx);
        }
        safeCreateMany(tplDevName, ctxs);
    }

    private static void safeCreate(String tpl, KenNotificationFactory.Context ctx) {
        try {
            KenNotificationFactory.create(tpl, ctx);
        } catch (Exception ex) {
            System.debug('Notification ' + tpl + ' tolerated: ' + ex.getMessage());
        }
    }

    private static void safeCreateMany(String tpl, List<KenNotificationFactory.Context> ctxs) {
        if (ctxs.isEmpty()) return;
        try {
            KenNotificationFactory.create(tpl, ctxs);
        } catch (Exception ex) {
            System.debug('Notification ' + tpl + ' (' + ctxs.size() + ') tolerated: ' + ex.getMessage());
        }
    }

    /**
     * Members of the group who:
     *   - have an active membership (Status = 'Approved')
     *   - have not opted out of group updates (Receive_updates_from_joined_groups__c != false)
     *   - have the relevant channel in Notify_me_for_groups__c (or it's blank = receive all)
     */
    @TestVisible
    private static Set<Id> eligibleGroupMembers(Id groupId, String requiredChannel) {
        Set<Id> out = new Set<Id>();
        if (groupId == null) return out;
        Set<Id> memberAccountIds = new Set<Id>();
        for (Ken_Group_Member__c m : [
            SELECT Member__c FROM Ken_Group_Member__c
            WHERE Group__c = :groupId AND Status__c = 'Approved'
        ]) {
            if (m.Member__c != null) memberAccountIds.add(m.Member__c);
        }
        if (memberAccountIds.isEmpty()) return out;

        Map<Id, Ken_Alumni_Preferences__c> prefsByAccount = new Map<Id, Ken_Alumni_Preferences__c>();
        for (Ken_Alumni_Preferences__c p : [
            SELECT Person_Account__c, Receive_updates_from_joined_groups__c, Notify_me_for_groups__c
            FROM Ken_Alumni_Preferences__c
            WHERE Person_Account__c IN :memberAccountIds
        ]) {
            if (p.Person_Account__c != null) prefsByAccount.put(p.Person_Account__c, p);
        }

        for (Id aid : memberAccountIds) {
            Ken_Alumni_Preferences__c pref = prefsByAccount.get(aid);
            if (pref == null) {
                // No prefs record = receive everything (sane default for new alumni)
                out.add(aid);
                continue;
            }
            if (pref.Receive_updates_from_joined_groups__c == false) continue;
            if (String.isNotBlank(requiredChannel) && String.isNotBlank(pref.Notify_me_for_groups__c)) {
                Boolean matched = false;
                for (String v : pref.Notify_me_for_groups__c.split(';')) {
                    if (v != null && v.trim().equalsIgnoreCase(requiredChannel)) { matched = true; break; }
                }
                if (!matched) continue;
            }
            out.add(aid);
        }
        return out;
    }

    /**
     * Extract user IDs from @mention anchors in rich-text body.
     * Returns a Set<Id> of User Ids that may be mentioned. Empty if no mentions or invalid ids.
     */
    @TestVisible
    private static Set<Id> parseMentions(String body) {
        Set<Id> out = new Set<Id>();
        if (String.isBlank(body)) return out;
        Pattern p = Pattern.compile('data-mention-user-id="([0-9a-zA-Z]{15,18})"');
        Matcher m = p.matcher(body);
        while (m.find()) {
            String raw = m.group(1);
            try { out.add(Id.valueOf(raw)); } catch (Exception e) { /* skip bad id */ }
        }
        return out;
    }

    private static Id userToAccount(Id userId) {
        if (userId == null) return null;
        Set<Id> ids = usersToAccounts(new Set<Id>{ userId });
        for (Id v : ids) return v;
        return null;
    }

    private static Set<Id> usersToAccounts(Set<Id> userIds) {
        Set<Id> out = new Set<Id>();
        if (userIds == null || userIds.isEmpty()) return out;
        for (User u : [SELECT AccountId, ContactId FROM User WHERE Id IN :userIds]) {
            if (u.AccountId != null) out.add(u.AccountId);
            else if (u.ContactId != null) {
                List<Contact> cs = [SELECT AccountId FROM Contact WHERE Id = :u.ContactId LIMIT 1];
                if (!cs.isEmpty() && cs[0].AccountId != null) out.add(cs[0].AccountId);
            }
        }
        return out;
    }

    private static String groupName(Id groupId) {
        if (groupId == null) return '';
        List<Ken_Group__c> gs = [SELECT Name FROM Ken_Group__c WHERE Id = :groupId LIMIT 1];
        return gs.isEmpty() ? '' : gs[0].Name;
    }

    private static String snippet(String body, Integer maxLen) {
        if (String.isBlank(body)) return '';
        String text = body.replaceAll('<[^>]+>', '').replace('&nbsp;', ' ').trim();
        if (text.length() <= maxLen) return text;
        return text.substring(0, maxLen).trim() + '…';
    }
}