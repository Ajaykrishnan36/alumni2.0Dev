@IsTest
private class KenGroupFeedControllerTest {

    @TestSetup
    static void setupData() {
        Account author = new Account(Name = 'Feed Author');
        Account member = new Account(Name = 'Feed Member');
        Account outsider = new Account(Name = 'Feed Outsider');
        insert new List<Account>{ author, member, outsider };

        Ken_Group__c grp = new Ken_Group__c(
            Name           = 'Feed Test Group',
            Description__c = 'Group for feed tests',
            Group_Type__c  = 'Public',
            Status__c      = 'Approved',
            Is_Active__c   = true,
            Created_By__c  = author.Id,
            Member_Count__c = 2
        );
        insert grp;

        insert new List<Ken_Group_Member__c>{
            new Ken_Group_Member__c(
                Group__c = grp.Id, Member__c = author.Id,
                Role__c = 'Admin', Status__c = 'Approved', Joined_Date__c = Date.today()
            ),
            new Ken_Group_Member__c(
                Group__c = grp.Id, Member__c = member.Id,
                Role__c = 'Member', Status__c = 'Approved', Joined_Date__c = Date.today()
            )
        };
    }

    private static Id groupId() {
        return [SELECT Id FROM Ken_Group__c WHERE Name = 'Feed Test Group' LIMIT 1].Id;
    }
    private static Id authorAccountId() {
        return [SELECT Id FROM Account WHERE Name = 'Feed Author' LIMIT 1].Id;
    }
    private static Id memberAccountId() {
        return [SELECT Id FROM Account WHERE Name = 'Feed Member' LIMIT 1].Id;
    }
    private static Id outsiderAccountId() {
        return [SELECT Id FROM Account WHERE Name = 'Feed Outsider' LIMIT 1].Id;
    }

    @IsTest
    static void testCreatePostAsMember() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();

        Test.startTest();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Hello group!');
        Test.stopTest();

        System.assertNotEquals(null, postId, 'Post should be created');
        List<FeedItem> created = [SELECT Body, ParentId FROM FeedItem WHERE Id = :postId];
        System.assertEquals(1, created.size());
        System.assertEquals('Hello group!', created[0].Body);
        System.assertEquals(groupId(), created[0].ParentId);
    }

    @IsTest
    static void testCreatePostBlocksOutsider() {
        KenGroupFeedController.testCurrentAccountId = outsiderAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();

        Boolean blocked = false;
        try {
            KenGroupFeedController.createPost(groupId(), 'I am not a member');
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        System.assert(blocked, 'Outsider should be blocked from posting');
    }

    @IsTest
    static void testCreatePostRejectsEmpty() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Boolean rejected = false;
        try {
            KenGroupFeedController.createPost(groupId(), '   ');
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'Empty post should be rejected');
    }

    @IsTest
    static void testCreatePostRejectsOverlongBody() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        String huge = 'x'.repeat(4001);
        Boolean rejected = false;
        try {
            KenGroupFeedController.createPost(groupId(), huge);
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'Overlong post should be rejected');
    }

    @IsTest
    static void testGetFeedReturnsPosts() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        KenGroupFeedController.createPost(groupId(), 'First post');
        KenGroupFeedController.createPost(groupId(), 'Second post');

        Test.startTest();
        KenGroupFeedController.FeedPage page = KenGroupFeedController.getFeed(groupId(), 0, 10);
        Test.stopTest();

        System.assertEquals(2, page.posts.size(), 'Should return both posts');
        System.assertEquals('Second post', page.posts[0].body, 'Newest first');
    }

    @IsTest
    static void testToggleLike() {
        // toggleLike(feedItemId, currentlyLiked, knownLikeId) likes on the first call and
        // unlikes on the second. FeedItem.LikeCount is auto-maintained by Chatter; the
        // "liked by me" state is persisted in Ken_Alumni_Preferences__c.Liked_Feed_Items__c.
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Like me');

        Test.startTest();
        KenGroupFeedController.ToggleLikeResult liked =
            KenGroupFeedController.toggleLike(postId, false, null);
        KenGroupFeedController.ToggleLikeResult unliked =
            KenGroupFeedController.toggleLike(postId, true, liked.likeId);
        Test.stopTest();

        System.assertEquals(true, liked.liked, 'First toggle should like the post');
        System.assertEquals(false, unliked.liked, 'Second toggle should unlike the post');
    }

    @IsTest
    static void testToggleLikeBlocksOutsider() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Outside cant like');

        KenGroupFeedController.testCurrentAccountId = outsiderAccountId();
        Boolean blocked = false;
        try {
            KenGroupFeedController.toggleLike(postId, false, null);
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        System.assert(blocked, 'Outsider should be blocked from liking');
    }

    @IsTest
    static void testAddCommentAndGetComments() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Comment thread');

        Test.startTest();
        Id c1 = KenGroupFeedController.addComment(postId, 'First comment');
        Id c2 = KenGroupFeedController.addComment(postId, 'Second comment');
        Test.stopTest();

        System.assertNotEquals(null, c1);
        System.assertNotEquals(null, c2);

        KenGroupFeedController.CommentPage page = KenGroupFeedController.getComments(postId, 0, 10);
        System.assertEquals(2, page.comments.size(), 'Should return both comments');
        System.assertEquals('First comment', page.comments[0].body, 'Oldest comment first');
    }

    @IsTest
    static void testAddCommentRejectsEmpty() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Has post');
        Boolean rejected = false;
        try {
            KenGroupFeedController.addComment(postId, '');
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'Empty comment should be rejected');
    }

    @IsTest
    static void testDeletePostAsAuthor() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Will delete');

        Test.startTest();
        KenGroupFeedController.deletePost(postId);
        Test.stopTest();

        List<FeedItem> remaining = [SELECT Id FROM FeedItem WHERE Id = :postId];
        System.assertEquals(0, remaining.size(), 'Post should be deleted');
    }

    @IsTest
    static void testDeleteCommentAsAuthor() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Has comment');
        Id cId    = KenGroupFeedController.addComment(postId, 'Will delete');

        Test.startTest();
        KenGroupFeedController.deleteComment(cId);
        Test.stopTest();

        List<FeedComment> remaining = [SELECT Id FROM FeedComment WHERE Id = :cId];
        System.assertEquals(0, remaining.size(), 'Comment should be deleted');
    }

    @IsTest
    static void testGetFeedRejectsNullGroupId() {
        Boolean rejected = false;
        try {
            KenGroupFeedController.getFeed(null, 0, 10);
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'Null group id should be rejected');
    }

    @IsTest
    static void testServiceHelpers() {
        Test.startTest();
        String just = KenGroupFeedService.relativeTime(Datetime.now());
        String min  = KenGroupFeedService.relativeTime(Datetime.now().addMinutes(-5));
        String hr   = KenGroupFeedService.relativeTime(Datetime.now().addHours(-2));
        String day  = KenGroupFeedService.relativeTime(Datetime.now().addDays(-3));
        String old  = KenGroupFeedService.relativeTime(Datetime.now().addDays(-30));
        Test.stopTest();
        System.assertNotEquals(null, just);
        System.assertNotEquals(null, min);
        System.assertNotEquals(null, hr);
        System.assertNotEquals(null, day);
        System.assertNotEquals(null, old);

        Set<Id> none = new Set<Id>();
        System.assertEquals(0, KenGroupFeedService.lookupProfileImages(none).size());
        System.assertEquals(0, KenGroupFeedService.lookupBatchLabels(none).size());
    }

    @IsTest
    static void testTriggerHandlersInvoke() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();

        Test.startTest();
        Id postId = KenGroupFeedController.createPost(groupId(), 'For triggers');
        KenGroupFeedController.addComment(postId, 'Trigger comment');
        Test.stopTest();

        // Slice 1 handlers are stubs — assert the records survived (no exceptions thrown).
        System.assertEquals(1, [SELECT COUNT() FROM FeedItem WHERE Id = :postId]);
        System.assertEquals(1, [SELECT COUNT() FROM FeedComment WHERE FeedItemId = :postId]);
    }

    // ── Polls ──────────────────────────────────────────────────────────────────

    @IsTest
    static void testCreatePollVoteAndFeed() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();

        Test.startTest();
        Id pollPostId = KenGroupFeedController.createPollPost(
            groupId(), 'Favourite language?', new List<String>{ 'Apex', 'JS' }, 5
        );
        Ken_Questionnaire_Parameter__c qp = [
            SELECT Id FROM Ken_Questionnaire_Parameter__c
            WHERE Feed_Item__c = :String.valueOf(pollPostId) LIMIT 1
        ];
        KenGroupFeedController.PollDTO afterVote = KenGroupFeedController.votePoll(qp.Id, 'Apex');
        KenGroupFeedController.FeedPage page = KenGroupFeedController.getFeed(groupId(), 0, 10);
        Test.stopTest();

        System.assertNotEquals(null, pollPostId, 'Poll post should be created');
        System.assertNotEquals(null, afterVote, 'votePoll should return the poll state');
        System.assertEquals(1, afterVote.totalVotes, 'One vote should be recorded');

        Boolean foundPoll = false;
        for (KenGroupFeedController.PostDTO p : page.posts) {
            if (p.feedItemId == pollPostId && p.pollState != null) foundPoll = true;
        }
        System.assert(foundPoll, 'Feed should expose the poll state on its post');
    }

    @IsTest
    static void testCreatePollRejectsTooFewOptions() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Boolean rejected = false;
        try {
            KenGroupFeedController.createPollPost(groupId(), 'One option only', new List<String>{ 'Solo' }, 7);
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'Poll with fewer than 2 options should be rejected');
    }

    @IsTest
    static void testVotePollRejectsInvalidOption() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Id pollPostId = KenGroupFeedController.createPollPost(
            groupId(), 'Pick one', new List<String>{ 'X', 'Y' }, 3
        );
        Ken_Questionnaire_Parameter__c qp = [
            SELECT Id FROM Ken_Questionnaire_Parameter__c
            WHERE Feed_Item__c = :String.valueOf(pollPostId) LIMIT 1
        ];
        Boolean rejected = false;
        try {
            KenGroupFeedController.votePoll(qp.Id, 'Z-not-an-option');
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'Voting for an option not on the poll should be rejected');
    }

    // ── Attachments ──────────────────────────────────────────────────────────────

    @IsTest
    static void testCreatePostWithAttachments() {
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();

        Id docId = KenGroupFeedController.uploadAttachment(
            'photo.png', EncodingUtil.base64Encode(Blob.valueOf('fake-image-bytes'))
        );
        System.assertNotEquals(null, docId, 'uploadAttachment should return a ContentDocumentId');

        Test.startTest();
        Id postId = KenGroupFeedController.createPostWithAttachments(
            groupId(), 'See attached', new List<Id>{ docId }
        );
        KenGroupFeedController.FeedPage page = KenGroupFeedController.getFeed(groupId(), 0, 10);
        Test.stopTest();

        System.assertNotEquals(null, postId, 'Post with attachment should be created');
        Boolean foundPost = false;
        for (KenGroupFeedController.PostDTO p : page.posts) {
            if (p.feedItemId == postId) {
                foundPost = true;
                System.assertNotEquals(null, p.attachments, 'attachments list should not be null');
            }
        }
        System.assert(foundPost, 'Feed should include the attachment post');
    }

    @IsTest
    static void testUploadAttachmentRejectsBlank() {
        Boolean rejected = false;
        try {
            KenGroupFeedController.uploadAttachment('', '');
        } catch (AuraHandledException ex) {
            rejected = true;
        }
        System.assert(rejected, 'Blank file name/data should be rejected');
    }

    // ── Service lookups (CRM-backed) ───────────────────────────────────────────

    @IsTest
    static void testServiceProfileAndBatchLookups() {
        Id memberId = memberAccountId();
        insert new Ken_Alumni_CRM__c(
            Person_Account__c     = memberId,
            Profile_Photo_URL__c  = 'https://example.com/p.jpg',
            Year_of_Graduation__c = '2019'
        );
        Set<Id> accIds = new Set<Id>{ memberId };

        Test.startTest();
        Map<Id, String> photos  = KenGroupFeedService.lookupProfileImages(accIds);
        Map<Id, String> batches = KenGroupFeedService.lookupBatchLabels(accIds);
        Test.stopTest();

        System.assertEquals('https://example.com/p.jpg', photos.get(memberId), 'CRM photo should resolve');
        System.assertEquals('Batch - 2019', batches.get(memberId), 'CRM grad year should map to a batch label');
    }

    @IsTest
    static void testServiceLookupAttachments() {
        // ContentDocumentLink cannot target a FeedItem in test context, so we anchor the
        // documents on an Account and pass that Id as the lookup key. lookupAttachments
        // resolves links by LinkedEntityId regardless of entity type, so this still exercises
        // the ContentVersion projection + isImageType for both an image and a non-image file.
        Id anchorId = authorAccountId();

        ContentVersion img = new ContentVersion(
            Title = 'pic', PathOnClient = 'pic.png',
            VersionData = Blob.valueOf('img-bytes'), IsMajorVersion = true
        );
        ContentVersion doc = new ContentVersion(
            Title = 'spec', PathOnClient = 'spec.pdf',
            VersionData = Blob.valueOf('pdf-bytes'), IsMajorVersion = true
        );
        insert new List<ContentVersion>{ img, doc };

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentVersion cv : [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id IN :new List<Id>{ img.Id, doc.Id }
        ]) {
            links.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId    = anchorId,
                ShareType         = 'V'
            ));
        }
        insert links;

        Test.startTest();
        Map<Id, List<KenGroupFeedController.AttachmentDTO>> byItem =
            KenGroupFeedService.lookupAttachments(new Set<Id>{ anchorId });
        Test.stopTest();

        System.assert(byItem.containsKey(anchorId), 'Attachments should resolve for the anchor record');
        System.assertEquals(2, byItem.get(anchorId).size(), 'Both files should be returned');
        Boolean sawImage = false, sawNonImage = false;
        for (KenGroupFeedController.AttachmentDTO a : byItem.get(anchorId)) {
            if (a.isImage) sawImage = true; else sawNonImage = true;
        }
        System.assert(sawImage,    'PNG should be flagged as an image');
        System.assert(sawNonImage, 'PDF should not be flagged as an image');
    }

    // ── Notifications ──────────────────────────────────────────────────────────

    @IsTest
    static void testNotificationEntryPoints() {
        Id grp = groupId();
        Id runningUserId = UserInfo.getUserId();
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = runningUserId;
        Id realPost = KenGroupFeedController.createPost(grp, 'Notify base');

        // A body carrying a (well-formed) mention marker + an invalid one to exercise parseMentions.
        String body = '<p>Hi <a data-mention-user-id="' + runningUserId + '">@me</a> '
                    + 'and <a data-mention-user-id="notARealId12345">@bad</a></p>';

        Test.startTest();
        KenGroupFeedNotifications.notifyPostCreated(realPost, grp, runningUserId, body);
        Id commentId = KenGroupFeedController.addComment(realPost, 'A comment');
        KenGroupFeedNotifications.notifyCommentCreated(commentId, realPost, runningUserId, body);
        KenGroupFeedNotifications.notifyPollCreated(realPost, grp, runningUserId, 'A poll question?');

        // Direct coverage of the @TestVisible helpers.
        Set<Id> mentions = KenGroupFeedNotifications.parseMentions(body);
        Set<Id> eligible = KenGroupFeedNotifications.eligibleGroupMembers(grp, 'New posts');
        Test.stopTest();

        System.assert(mentions.contains(runningUserId), 'Valid mention id should be parsed');
        System.assert(!eligible.isEmpty(), 'Approved members with no opt-out should be eligible');
    }

    @IsTest
    static void testEligibleMembersRespectsPreferences() {
        Id grp = groupId();
        Id memberId = memberAccountId();
        Id authorId = authorAccountId();

        // Member opted out of all group updates → excluded.
        insert new Ken_Alumni_Preferences__c(
            Person_Account__c                     = memberId,
            Receive_updates_from_joined_groups__c = false
        );
        // Author opted in but only for 'Polls' → excluded for the 'New posts' channel.
        insert new Ken_Alumni_Preferences__c(
            Person_Account__c                     = authorId,
            Receive_updates_from_joined_groups__c = true,
            Notify_me_for_groups__c               = 'Polls'
        );

        Test.startTest();
        Set<Id> forPosts = KenGroupFeedNotifications.eligibleGroupMembers(grp, 'New posts');
        Set<Id> forPolls = KenGroupFeedNotifications.eligibleGroupMembers(grp, 'Polls');
        Test.stopTest();

        System.assert(!forPosts.contains(memberId), 'Opted-out member should be excluded');
        System.assert(!forPosts.contains(authorId), 'Author wants only Polls, not New posts');
        System.assert(forPolls.contains(authorId), 'Author should receive Polls notifications');
    }

    // ── Internal (admin) user paths ──────────────────────────────────────────────

    @IsTest
    static void testInternalUserCanPostAndDelete() {
        // Internal/admin users have no Person Account (currentAccountId == null).
        KenGroupFeedController.testCurrentAccountId = null;
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();

        Test.startTest();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Internal post');
        Id commentId = KenGroupFeedController.addComment(postId, 'Internal comment');
        KenGroupFeedController.FeedPage page = KenGroupFeedController.getFeed(groupId(), 0, 10);
        KenGroupFeedController.deleteComment(commentId);
        KenGroupFeedController.deletePost(postId);
        Test.stopTest();

        System.assertNotEquals(null, postId, 'Internal user should be able to post');
        System.assert(!page.posts.isEmpty(), 'Feed should render for internal user');
        System.assertEquals(0, [SELECT COUNT() FROM FeedItem WHERE Id = :postId], 'Post should be deleted');
    }

    @IsTest
    static void testDeletePostBlocksNonAuthorNonAdmin() {
        // Member creates a post; an outsider (non-author, non-admin) cannot delete it.
        KenGroupFeedController.testCurrentAccountId = memberAccountId();
        KenGroupFeedController.testCurrentUserId    = UserInfo.getUserId();
        Id postId = KenGroupFeedController.createPost(groupId(), 'Protected post');

        KenGroupFeedController.testCurrentAccountId = outsiderAccountId();
        // Force a non-author by overriding the "current user" to a different id.
        KenGroupFeedController.testCurrentUserId = UserInfo.getOrganizationId();
        Boolean blocked = false;
        try {
            KenGroupFeedController.deletePost(postId);
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        System.assert(blocked, 'Non-author non-admin should not be able to delete');
    }

    // ── Trigger kill-switch ──────────────────────────────────────────────────────

    @IsTest
    static void testTriggerKillSwitch() {
        // When the kill-switch is on, the trigger should return before dispatching.
        insert new Alumni_Trigger_Settings__c(
            SetupOwnerId          = UserInfo.getOrganizationId(),
            Feed_Item_Trigger__c  = true
        );

        Test.startTest();
        FeedItem fi = new FeedItem(ParentId = groupId(), Body = 'Killed switch', Visibility = 'AllUsers');
        insert fi;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM FeedItem WHERE Id = :fi.Id], 'Post should still insert');
    }
}