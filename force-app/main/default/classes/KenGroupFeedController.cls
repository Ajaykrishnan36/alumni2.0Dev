/**
 * Facade for the group-feed LWCs. Reads/writes FeedItem, FeedComment, FeedLike
 * on Ken_Group__c records. Slice 1: text posts, likes, flat comments.
 */
public without sharing class KenGroupFeedController {
  private static final Integer DEFAULT_PAGE_SIZE = 10;
  private static final Integer MAX_PAGE_SIZE = 50;
  private static final Integer MAX_BODY_LENGTH = 4000;

  @TestVisible
  private static Id testCurrentAccountId;
  @TestVisible
  private static Id testCurrentUserId;

  // ── DTOs ──────────────────────────────────────────────────────────────────

  public class PostDTO {
    @AuraEnabled
    public Id feedItemId;
    @AuraEnabled
    public Id groupId;
    @AuraEnabled
    public Id authorAccountId;
    @AuraEnabled
    public Id authorUserId;
    @AuraEnabled
    public String authorName;
    @AuraEnabled
    public String authorPhotoUrl;
    @AuraEnabled
    public String authorBatch;
    @AuraEnabled
    public String body;
    @AuraEnabled
    public DateTime createdAt;
    @AuraEnabled
    public String createdAtLabel;
    @AuraEnabled
    public Integer likeCount;
    @AuraEnabled
    public Integer commentCount;
    @AuraEnabled
    public Boolean likedByMe;
    @AuraEnabled
    public Id myLikeId; // FeedLike.Id when liked by current user; null otherwise
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public Boolean canDelete;
    @AuraEnabled
    public Boolean commentsEnabled;
    @AuraEnabled
    public List<AttachmentDTO> attachments;
    @AuraEnabled
    public PollDTO pollState;
  }

  public class ToggleLikeResult {
    @AuraEnabled
    public Boolean liked;
    @AuraEnabled
    public Id likeId;
    @AuraEnabled
    public Integer likeCount;
  }

  public class AttachmentDTO {
    @AuraEnabled
    public Id contentVersionId;
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String fileType;
    @AuraEnabled
    public String previewUrl;
    @AuraEnabled
    public String downloadUrl;
    @AuraEnabled
    public Boolean isImage;
  }

  public class PollDTO {
    @AuraEnabled
    public Id pollId;
    @AuraEnabled
    public String question;
    @AuraEnabled
    public DateTime endsAt;
    @AuraEnabled
    public Boolean isClosed;
    @AuraEnabled
    public Boolean hasVoted;
    @AuraEnabled
    public Integer totalVotes;
    @AuraEnabled
    public List<PollOptionDTO> options;
  }

  public class PollOptionDTO {
    @AuraEnabled
    public String optionId; // option text doubles as the per-poll-unique key
    @AuraEnabled
    public String optionText;
    @AuraEnabled
    public Integer order_x;
    @AuraEnabled
    public Integer voteCount;
    @AuraEnabled
    public Integer votePercent;
    @AuraEnabled
    public Boolean votedByMe;
  }

  public class CommentDTO {
    @AuraEnabled
    public Id commentId;
    @AuraEnabled
    public Id authorAccountId;
    @AuraEnabled
    public String authorName;
    @AuraEnabled
    public String authorPhotoUrl;
    @AuraEnabled
    public String authorBatch;
    @AuraEnabled
    public String body;
    @AuraEnabled
    public DateTime createdAt;
    @AuraEnabled
    public String createdAtLabel;
    @AuraEnabled
    public Boolean canDelete;
  }

  public class FeedPage {
    @AuraEnabled
    public List<PostDTO> posts;
    @AuraEnabled
    public Boolean hasMore;
    @AuraEnabled
    public Integer totalSize;
  }

  public class CommentPage {
    @AuraEnabled
    public List<CommentDTO> comments;
    @AuraEnabled
    public Boolean hasMore;
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  @AuraEnabled(cacheable=false)
  public static FeedPage getFeed(Id groupId, Integer offset, Integer pageSize) {
    if (groupId == null)
      throw new AuraHandledException('Group ID is required.');
    Integer limitN = clamp(pageSize, 1, MAX_PAGE_SIZE, DEFAULT_PAGE_SIZE);
    Integer offsetN = offset == null || offset < 0 ? 0 : offset;

    Id currentAccountId = currentAccountId();
    Id currentUserId = currentUserId();
    Boolean isAdmin = isGroupAdmin(groupId, currentAccountId);

    List<FeedItem> rows = [
      SELECT
        Id,
        Body,
        CreatedDate,
        CreatedById,
        LikeCount,
        CommentCount,
        Type,
        ParentId,
        Status
      FROM FeedItem
      WHERE
        ParentId = :groupId
        AND Type IN ('TextPost', 'ContentPost', 'LinkPost')
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT :limitN
      OFFSET :offsetN
    ];

    FeedPage page = new FeedPage();
    page.posts = new List<PostDTO>();
    page.hasMore = rows.size() == limitN;
    page.totalSize = rows.size();
    if (rows.isEmpty())
      return page;

    Set<Id> feedItemIds = new Set<Id>();
    Set<Id> authorUserIds = new Set<Id>();
    for (FeedItem fi : rows) {
      feedItemIds.add(fi.Id);
      if (fi.CreatedById != null)
        authorUserIds.add(fi.CreatedById);
    }

    // Like counts come from FeedItem.LikeCount (auto-maintained by Chatter, zero storage cost).
    // "Liked by me" comes from Ken_Alumni_Preferences__c.Liked_Feed_Items__c (one JSON map
    // per user) because FeedLike SOQL is blocked in this org.
    Map<Id, String> likedFeedItemIdToLikeId = readMyLikedMap();
    Set<Id> likedByMeIds = new Set<Id>();
    Map<Id, Id> myLikeIdByFeedItem = new Map<Id, Id>();
    for (Id fid : feedItemIds) {
      String likeIdStr = likedFeedItemIdToLikeId.get(fid);
      if (String.isNotBlank(likeIdStr)) {
        likedByMeIds.add(fid);
        try {
          myLikeIdByFeedItem.put(fid, Id.valueOf(likeIdStr));
        } catch (Exception e) {
          /* skip */
        }
      }
    }

    Map<Id, Id> accountByUserId = mapUsersToAccounts(authorUserIds);
    Set<Id> accountIds = new Set<Id>();
    for (Id a : accountByUserId.values())
      if (a != null)
        accountIds.add(a);

    Map<Id, String> nameByAccount = mapAccountNames(accountIds);
    Map<Id, String> photoByAccount = KenGroupFeedService.lookupProfileImages(
      accountIds
    );
    Map<Id, String> batchByAccount = KenGroupFeedService.lookupBatchLabels(
      accountIds
    );
    Map<Id, UserInfoDTO> userFallback = mapUserFallbacks(authorUserIds);
    Map<Id, String> bodyByFeedItem = new Map<Id, String>();
    for (FeedItem fi : rows)
      bodyByFeedItem.put(fi.Id, fi.Body);
    Map<Id, List<AttachmentDTO>> attachmentsByFeedItem = KenGroupFeedService.lookupAttachments(
      feedItemIds,
      bodyByFeedItem
    );
    Map<Id, PollDTO> pollByFeedItem = KenGroupFeedService.lookupPolls(
      feedItemIds,
      currentUserId
    );
    // Inline images are stored as sfdc://<ContentDocumentId>; resolve them all
    // in one query rather than per post.
    Map<Id, String> inlineImageUrls = KenGroupFeedService.lookupInlineImageUrls(
      KenGroupFeedService.extractInlineImageIds(bodyByFeedItem.values())
    );

    for (FeedItem fi : rows) {
      PostDTO dto = new PostDTO();
      dto.feedItemId = fi.Id;
      dto.groupId = fi.ParentId;
      dto.authorUserId = fi.CreatedById;
      dto.authorAccountId = accountByUserId.get(fi.CreatedById);
      dto.authorName = nameByAccount.get(dto.authorAccountId);
      dto.authorPhotoUrl = photoByAccount.get(dto.authorAccountId);
      dto.authorBatch = batchByAccount.get(dto.authorAccountId);
      // Fallback to User.Name / SmallPhotoUrl when there's no Person Account (admin users).
      if (
        String.isBlank(dto.authorName) &&
        userFallback.containsKey(fi.CreatedById)
      ) {
        dto.authorName = userFallback.get(fi.CreatedById).name;
      }
      if (
        String.isBlank(dto.authorPhotoUrl) &&
        userFallback.containsKey(fi.CreatedById)
      ) {
        dto.authorPhotoUrl = userFallback.get(fi.CreatedById).photoUrl;
      }
      dto.body = KenGroupFeedService.rewriteInlineImages(
        fi.Body,
        inlineImageUrls
      );
      dto.createdAt = fi.CreatedDate;
      dto.createdAtLabel = KenGroupFeedService.relativeTime(fi.CreatedDate);
      dto.likeCount = fi.LikeCount == null ? 0 : fi.LikeCount;
      dto.commentCount = fi.CommentCount == null ? 0 : fi.CommentCount;
      dto.myLikeId = myLikeIdByFeedItem.get(fi.Id);
      dto.likedByMe = likedByMeIds.contains(fi.Id);
      Boolean isAuthor =
        currentUserId != null &&
        fi.CreatedById == currentUserId;
      Boolean isInternal = currentAccountId == null;
      dto.canEdit = isAuthor || isInternal;
      dto.canDelete = isAuthor || isAdmin || isInternal;
      dto.attachments = attachmentsByFeedItem.containsKey(fi.Id)
        ? attachmentsByFeedItem.get(fi.Id)
        : new List<AttachmentDTO>();
      dto.pollState = pollByFeedItem.get(fi.Id);
      dto.commentsEnabled = fi.Status != 'PendingReview';
      page.posts.add(dto);
    }
    return page;
  }

  @AuraEnabled(cacheable=false)
  public static CommentPage getComments(
    Id feedItemId,
    Integer offset,
    Integer pageSize
  ) {
    if (feedItemId == null)
      throw new AuraHandledException('Feed item ID is required.');
    Integer limitN = clamp(pageSize, 1, MAX_PAGE_SIZE, DEFAULT_PAGE_SIZE);
    Integer offsetN = offset == null || offset < 0 ? 0 : offset;

    Id currentUserId = currentUserId();
    Id currentAccountId = currentAccountId();
    Id parentGroupId = null;
    List<FeedItem> parent = [
      SELECT ParentId
      FROM FeedItem
      WHERE Id = :feedItemId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (!parent.isEmpty())
      parentGroupId = parent[0].ParentId;
    Boolean isAdmin = parentGroupId != null
      ? isGroupAdmin(parentGroupId, currentAccountId)
      : false;

    List<FeedComment> rows = [
      SELECT Id, CommentBody, CreatedDate, CreatedById, FeedItemId
      FROM FeedComment
      WHERE FeedItemId = :feedItemId
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate ASC
      LIMIT :limitN
      OFFSET :offsetN
    ];

    CommentPage page = new CommentPage();
    page.comments = new List<CommentDTO>();
    page.hasMore = rows.size() == limitN;
    if (rows.isEmpty())
      return page;

    Set<Id> authorUserIds = new Set<Id>();
    for (FeedComment fc : rows)
      if (fc.CreatedById != null)
        authorUserIds.add(fc.CreatedById);
    Map<Id, Id> accountByUserId = mapUsersToAccounts(authorUserIds);
    Set<Id> accountIds = new Set<Id>();
    for (Id a : accountByUserId.values())
      if (a != null)
        accountIds.add(a);
    Map<Id, String> nameByAccount = mapAccountNames(accountIds);
    Map<Id, String> photoByAccount = KenGroupFeedService.lookupProfileImages(
      accountIds
    );
    Map<Id, String> batchByAccount = KenGroupFeedService.lookupBatchLabels(
      accountIds
    );
    Map<Id, UserInfoDTO> userFallback = mapUserFallbacks(authorUserIds);

    for (FeedComment fc : rows) {
      CommentDTO dto = new CommentDTO();
      dto.commentId = fc.Id;
      dto.authorAccountId = accountByUserId.get(fc.CreatedById);
      dto.authorName = nameByAccount.get(dto.authorAccountId);
      dto.authorPhotoUrl = photoByAccount.get(dto.authorAccountId);
      dto.authorBatch = batchByAccount.get(dto.authorAccountId);
      if (
        String.isBlank(dto.authorName) &&
        userFallback.containsKey(fc.CreatedById)
      ) {
        dto.authorName = userFallback.get(fc.CreatedById).name;
      }
      if (
        String.isBlank(dto.authorPhotoUrl) &&
        userFallback.containsKey(fc.CreatedById)
      ) {
        dto.authorPhotoUrl = userFallback.get(fc.CreatedById).photoUrl;
      }
      dto.body = fc.CommentBody;
      dto.createdAt = fc.CreatedDate;
      dto.createdAtLabel = KenGroupFeedService.relativeTime(fc.CreatedDate);
      Boolean isAuthor =
        currentUserId != null &&
        fc.CreatedById == currentUserId;
      dto.canDelete = isAuthor || isAdmin;
      page.comments.add(dto);
    }
    return page;
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  @AuraEnabled(cacheable=false)
  public static Id createPost(Id groupId, String body) {
    return createPostInternal(groupId, body, null, null);
  }

  /**
   * Create a post with one or more file attachments. ContentDocumentIds come from
   * a prior lightning-file-upload — we link each to the FeedItem via ContentDocumentLink.
   */
  @AuraEnabled(cacheable=false)
  public static Id createPostWithAttachments(
    Id groupId,
    String body,
    List<Id> contentDocumentIds
  ) {
    return createPostInternal(groupId, body, contentDocumentIds, null);
  }

  /**
   * Same as createPost / createPostWithAttachments, but lets the caller set the
   * comments-enabled toggle. Apex doesn't allow overloading @AuraEnabled methods,
   * so this is its own entry point rather than a third createPost signature.
   */
  @AuraEnabled(cacheable=false)
  public static Id createGroupPost(
    Id groupId,
    String body,
    List<Id> contentDocumentIds,
    Boolean commentsEnabled
  ) {
    return createPostInternal(
      groupId,
      body,
      contentDocumentIds,
      commentsEnabled
    );
  }

  private static Id createPostInternal(
    Id groupId,
    String body,
    List<Id> contentDocumentIds,
    Boolean commentsEnabled
  ) {
    if (groupId == null)
      throw new AuraHandledException('Group ID is required.');
    Boolean hasAttachments =
      contentDocumentIds != null && !contentDocumentIds.isEmpty();
    if (String.isBlank(body) && !hasAttachments) {
      throw new AuraHandledException('Post must have text or an attachment.');
    }
    // The rich-text editor emits <div>/<br>/style=, none of which Chatter
    // accepts - without this the insert fails with INVALID_MARKUP.
    String trimmed = String.isBlank(body)
      ? ''
      : KenGroupFeedService.normalizeRichText(body.trim());
    if (trimmed.length() > MAX_BODY_LENGTH) {
      throw new AuraHandledException(
        'Post body exceeds maximum length of ' +
          MAX_BODY_LENGTH +
          ' characters.'
      );
    }
    assertGroupAccessible(groupId);

    if (String.isBlank(trimmed) && !hasAttachments) {
      throw new AuraHandledException('Post must have text or an attachment.');
    }
    Boolean richText =
      !String.isBlank(trimmed) &&
      (trimmed.contains('<') && trimmed.contains('>'));
    FeedItem fi = new FeedItem(
      ParentId = groupId,
      Body = String.isBlank(trimmed) ? null : trimmed,
      IsRichText = richText,
      Visibility = 'AllUsers',
      // Comments toggle rides on the standard Status field — PendingReview means
      // "comments off" for this post. No moderation rules exist in this org today,
      // so nothing else writes to Status; see KenGroupFeedController class doc.
      Status = commentsEnabled == false ? 'PendingReview' : 'Published'
    );
    Database.insert(fi, true, AccessLevel.SYSTEM_MODE);

    if (hasAttachments) {
      List<ContentDocumentLink> links = new List<ContentDocumentLink>();
      for (Id cdId : contentDocumentIds) {
        links.add(
          new ContentDocumentLink(
            ContentDocumentId = cdId,
            LinkedEntityId = fi.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
          )
        );
      }
      try {
        Database.insert(links, true, AccessLevel.SYSTEM_MODE);
      } catch (DmlException dex) {
        // Don't roll back the post if a single attachment fails to share — log and continue.
        System.debug('Attachment link failed: ' + dex.getMessage());
      }
    }
    return fi.Id;
  }

  /**
   * @description Posts a poll to a group: the question becomes the post body, and the question
   *              and its options are stored as a one-question question set tagged with the post.
   * @param groupId Group to post into.
   * @param question Poll question.
   * @param options Option texts in display order.
   * @param durationDays Days the poll stays open.
   * @return Id of the feed post carrying the poll.
   */
  @AuraEnabled(cacheable=false)
  public static Id createPollPost(
    Id groupId,
    String question,
    List<String> options,
    Integer durationDays
  ) {
    if (groupId == null)
      throw new AuraHandledException('Group ID is required.');
    if (String.isBlank(question))
      throw new AuraHandledException('Poll question is required.');
    if (options == null || options.size() < 2) {
      throw new AuraHandledException('A poll needs at least 2 options.');
    }
    List<String> cleanOptions = new List<String>();
    for (String o : options) {
      if (String.isNotBlank(o)) {
        String trimmed = o.trim();
        if (trimmed.contains(';'))
          trimmed = trimmed.replace(';', ',');
        cleanOptions.add(
          trimmed.length() > 255 ? trimmed.substring(0, 255) : trimmed
        );
      }
    }
    if (cleanOptions.size() < 2) {
      throw new AuraHandledException(
        'A poll needs at least 2 non-empty options.'
      );
    }
    if (cleanOptions.size() > 10) {
      throw new AuraHandledException('A poll can have at most 10 options.');
    }
    Integer days = durationDays == null ||
      durationDays < 1
      ? 7
      : Math.min(durationDays, 60);
    assertGroupAccessible(groupId);

    FeedItem fi = new FeedItem(
      ParentId = groupId,
      Body = question.trim(),
      Visibility = 'AllUsers'
    );
    KenFeedItemTriggerHandler.suppressBroadcastForPoll = true;
    try {
      Database.insert(fi, true, AccessLevel.SYSTEM_MODE);
    } finally {
      KenFeedItemTriggerHandler.suppressBroadcastForPoll = false;
    }

    KenGroupFeedService.savePollQuestionSet(
      fi.Id,
      question.trim(),
      cleanOptions,
      days
    );

    try {
      KenGroupFeedNotifications.notifyPollCreated(
        fi.Id,
        groupId,
        currentUserId(),
        question
      );
    } catch (Exception ex) {
      System.debug('Group_Poll_New dispatch tolerated: ' + ex.getMessage());
    }
    return fi.Id;
  }

  /**
   * @description Casts the running user's vote on a poll. Voting again replaces the earlier
   *              answer rather than adding a second one, so a poll counts one vote per person.
   * @param pollId Question version the client knows the poll by.
   * @param optionText Chosen option.
   * @return The poll state after the vote.
   */
  @AuraEnabled(cacheable=false)
  public static PollDTO votePoll(Id pollId, String optionText) {
    if (pollId == null || String.isBlank(optionText)) {
      throw new AuraHandledException('Poll and option are required.');
    }
    Id currentAccountId = currentAccountId();
    if (currentAccountId == null) {
      throw new AuraHandledException(
        'Only alumni can vote — internal admin votes are not stored.'
      );
    }

    KenGroupFeedService.PollContext poll = KenGroupFeedService.pollContext(
      pollId
    );
    if (poll == null)
      throw new AuraHandledException('Poll not found.');
    if (poll.endsAt != null && poll.endsAt < Datetime.now()) {
      throw new AuraHandledException('This poll has closed.');
    }
    if (poll.feedItemId == null) {
      throw new AuraHandledException('Poll is not linked to a feed post.');
    }
    List<FeedItem> fis = [
      SELECT ParentId
      FROM FeedItem
      WHERE Id = :poll.feedItemId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (fis.isEmpty())
      throw new AuraHandledException('Poll post no longer exists.');
    assertGroupAccessible(fis[0].ParentId);

    if (!poll.optionTexts.contains(optionText)) {
      throw new AuraHandledException('Invalid option for this poll.');
    }

    KenGroupFeedService.recordPollVote(
      pollId,
      currentAccountId,
      optionText,
      poll.questionText
    );

    Map<Id, PollDTO> polled = KenGroupFeedService.lookupPolls(
      new Set<Id>{ poll.feedItemId },
      currentUserId()
    );
    return polled.get(poll.feedItemId);
  }

  /**
   * Toggle a like using the standard FeedLike object (zero custom records — FeedItem.LikeCount
   * is auto-maintained by Chatter). FeedLike SOQL is blocked in this org, so we persist the
   * FeedLike.Id in the user's Ken_Alumni_Preferences__c.Liked_Feed_Items__c JSON map. The LWC
   * also passes back the cached likeId so we don't even need to read the map on unlike.
   */
  @AuraEnabled(cacheable=false)
  public static ToggleLikeResult toggleLike(
    Id feedItemId,
    Boolean currentlyLiked,
    Id knownLikeId
  ) {
    if (feedItemId == null)
      throw new AuraHandledException('Feed item ID is required.');

    List<FeedItem> parent = [
      SELECT ParentId
      FROM FeedItem
      WHERE Id = :feedItemId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (parent.isEmpty())
      throw new AuraHandledException('Post not found.');
    assertGroupAccessible(parent[0].ParentId);

    ToggleLikeResult res = new ToggleLikeResult();
    Map<Id, String> myLikes = readMyLikedMap();

    if (currentlyLiked == true) {
      Id likeIdToDelete = knownLikeId;
      if (likeIdToDelete == null && myLikes.containsKey(feedItemId)) {
        try {
          likeIdToDelete = Id.valueOf(myLikes.get(feedItemId));
        } catch (Exception e) {
          /* skip */
        }
      }
      if (likeIdToDelete != null) {
        try {
          Database.delete(new FeedLike(Id = likeIdToDelete), true, AccessLevel.SYSTEM_MODE);
        } catch (DmlException dex) {
          // Already gone — treat as unliked.
        }
        myLikes.remove(feedItemId);
        writeMyLikedMap(myLikes);
      }
      res.liked = false;
      res.likeId = null;
    } else {
      try {
        FeedLike fl = new FeedLike(FeedItemId = feedItemId);
        Database.insert(fl, true, AccessLevel.SYSTEM_MODE);
        myLikes.put(feedItemId, String.valueOf(fl.Id));
        writeMyLikedMap(myLikes);
        res.liked = true;
        res.likeId = fl.Id;
      } catch (DmlException dex) {
        // DUPLICATE_VALUE means the user already liked this — treat as success.
        res.liked = true;
        res.likeId = myLikes.containsKey(feedItemId)
          ? (Id) Id.valueOf(myLikes.get(feedItemId))
          : null;
      }
    }

    FeedItem fresh = [
      SELECT LikeCount
      FROM FeedItem
      WHERE Id = :feedItemId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    res.likeCount = fresh.LikeCount == null ? 0 : fresh.LikeCount;
    return res;
  }

  /**
   * Read the running user's like-id map from Ken_Alumni_Preferences__c.Liked_Feed_Items__c.
   * Returns Map<FeedItemId, FeedLikeId-as-String>. Returns empty map for admins (no prefs record).
   */
  private static Map<Id, String> readMyLikedMap() {
    Map<Id, String> out = new Map<Id, String>();
    Id myAccountId = currentAccountId();
    if (myAccountId == null)
      return out;
    List<Ken_Alumni_Preferences__c> prefs = [
      SELECT Liked_Feed_Items__c
      FROM Ken_Alumni_Preferences__c
      WHERE Person_Account__c = :myAccountId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (prefs.isEmpty() || String.isBlank(prefs[0].Liked_Feed_Items__c))
      return out;
    try {
      Object raw = JSON.deserializeUntyped(prefs[0].Liked_Feed_Items__c);
      if (raw instanceof Map<String, Object>) {
        for (String k : ((Map<String, Object>) raw).keySet()) {
          Object v = ((Map<String, Object>) raw).get(k);
          if (v != null)
            out.put(Id.valueOf(k), String.valueOf(v));
        }
      }
    } catch (Exception e) {
      // Corrupt JSON — treat as empty and overwrite on next write.
    }
    return out;
  }

  private static void writeMyLikedMap(Map<Id, String> likedMap) {
    Id myAccountId = currentAccountId();
    if (myAccountId == null)
      return; // admins don't persist; in-session only
    Map<String, String> serializable = new Map<String, String>();
    for (Id k : likedMap.keySet())
      serializable.put(String.valueOf(k), likedMap.get(k));
    String payload = JSON.serialize(serializable);
    // Cap to field limit, prune oldest entries if necessary.
    if (payload.length() > 32760) {
      // Drop a quarter of entries (Apex Maps don't preserve insertion order, but pruning
      // any is better than failing the write).
      List<String> keys = new List<String>(serializable.keySet());
      for (Integer i = 0; i < keys.size() / 4; i++)
        serializable.remove(keys[i]);
      payload = JSON.serialize(serializable);
    }
    List<Ken_Alumni_Preferences__c> prefs = [
      SELECT Id
      FROM Ken_Alumni_Preferences__c
      WHERE Person_Account__c = :myAccountId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (prefs.isEmpty()) {
      if (!Schema.sObjectType.Ken_Alumni_Preferences__c.isCreateable()) {
          throw new KenCrudException('Ken_Alumni_Preferences__c is not createable by the current user.');
      }
      insert new Ken_Alumni_Preferences__c(
        Person_Account__c = myAccountId,
        Liked_Feed_Items__c = payload
      );
    } else {
      prefs[0].Liked_Feed_Items__c = payload;
      update prefs[0];
    }
  }

  @AuraEnabled(cacheable=false)
  public static Id addComment(Id feedItemId, String body) {
    if (feedItemId == null)
      throw new AuraHandledException('Feed item ID is required.');
    if (String.isBlank(body))
      throw new AuraHandledException('Comment cannot be empty.');
    String trimmed = body.trim();
    if (trimmed.length() > MAX_BODY_LENGTH) {
      throw new AuraHandledException(
        'Comment exceeds maximum length of ' + MAX_BODY_LENGTH + ' characters.'
      );
    }
    List<FeedItem> parent = [
      SELECT ParentId, Status
      FROM FeedItem
      WHERE Id = :feedItemId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (parent.isEmpty())
      throw new AuraHandledException('Post not found.');
    if (parent[0].Status == 'PendingReview') {
      throw new AuraHandledException('Comments are turned off for this post.');
    }
    assertGroupAccessible(parent[0].ParentId);

    FeedComment fc = new FeedComment(
      FeedItemId = feedItemId,
      CommentBody = trimmed
    );
    Database.insert(fc, true, AccessLevel.SYSTEM_MODE);
    return fc.Id;
  }

  /**
   * @description Deletes a post and, when the post carried a poll, everything that poll owns:
   *              its votes, their submission headers and its question set.
   * @param feedItemId Post to delete.
   */
  @AuraEnabled(cacheable=false)
  public static void deletePost(Id feedItemId) {
    if (feedItemId == null)
      throw new AuraHandledException('Feed item ID is required.');
    Id currentUserId = currentUserId();
    Id currentAccountId = currentAccountId();
    List<FeedItem> rows = [
      SELECT Id, ParentId, CreatedById
      FROM FeedItem
      WHERE Id = :feedItemId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (rows.isEmpty())
      throw new AuraHandledException('Post not found.');
    Boolean isAuthor =
      currentUserId != null &&
      rows[0].CreatedById == currentUserId;
    Boolean isAdmin =
      isInternalUser() || isGroupAdmin(rows[0].ParentId, currentAccountId);
    if (!isAuthor && !isAdmin) {
      throw new AuraHandledException(
        'You do not have permission to delete this post.'
      );
    }
    KenGroupFeedService.deletePollData(feedItemId);
    delete rows[0];
  }

  @AuraEnabled(cacheable=false)
  public static void deleteComment(Id commentId) {
    if (commentId == null)
      throw new AuraHandledException('Comment ID is required.');
    Id currentUserId = currentUserId();
    Id currentAccountId = currentAccountId();
    List<FeedComment> rows = [
      SELECT Id, CreatedById, FeedItemId
      FROM FeedComment
      WHERE Id = :commentId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (rows.isEmpty())
      throw new AuraHandledException('Comment not found.');
    Boolean isAuthor =
      currentUserId != null &&
      rows[0].CreatedById == currentUserId;
    Boolean isAdmin = isInternalUser();
    if (!isAuthor && !isAdmin) {
      List<FeedItem> parent = [
        SELECT ParentId
        FROM FeedItem
        WHERE Id = :rows[0].FeedItemId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!parent.isEmpty())
        isAdmin = isGroupAdmin(parent[0].ParentId, currentAccountId);
    }
    if (!isAuthor && !isAdmin) {
      throw new AuraHandledException(
        'You do not have permission to delete this comment.'
      );
    }
    delete rows[0];
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  private static Integer clamp(
    Integer val,
    Integer minVal,
    Integer maxVal,
    Integer defaultVal
  ) {
    if (val == null)
      return defaultVal;
    if (val < minVal)
      return minVal;
    if (val > maxVal)
      return maxVal;
    return val;
  }

  private static Id currentUserId() {
    if (Test.isRunningTest() && testCurrentUserId != null)
      return testCurrentUserId;
    return UserInfo.getUserId();
  }

  /**
   * @description Person Account behind the running user. Exposed to KenGroupFeedService so a
   *              poll vote and the feed that reads it back resolve the same voter.
   * @return The account id, or null when the running user has none.
   */
  public static Id resolveCurrentAccountId() {
    return currentAccountId();
  }

  private static Id currentAccountId() {
    if (Test.isRunningTest() && testCurrentAccountId != null)
      return testCurrentAccountId;
    List<User> users = [
      SELECT AccountId, ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (users.isEmpty())
      return null;
    if (users[0].AccountId != null)
      return users[0].AccountId;
    if (users[0].ContactId != null) {
      List<Contact> cs = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :users[0].ContactId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!cs.isEmpty())
        return cs[0].AccountId;
    }
    return null;
  }

  private static Boolean isGroupAdmin(Id groupId, Id currentAccountId) {
    if (groupId == null || currentAccountId == null)
      return false;
    List<Ken_Group__c> grps = [
      SELECT Created_By__c
      FROM Ken_Group__c
      WHERE Id = :groupId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (!grps.isEmpty() && grps[0].Created_By__c == currentAccountId)
      return true;
    List<Ken_Group_Member__c> admins = [
      SELECT Id
      FROM Ken_Group_Member__c
      WHERE
        Group__c = :groupId
        AND Member__c = :currentAccountId
        AND Role__c = 'Admin'
        AND Status__c = 'Approved'
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    return !admins.isEmpty();
  }

  private static void assertGroupAccessible(Id groupId) {
    if (groupId == null)
      throw new AuraHandledException('Group context required.');
    Id currentAccountId = currentAccountId();
    List<Ken_Group__c> grps = [
      SELECT Id, Group_Type__c, Created_By__c, Status__c
      FROM Ken_Group__c
      WHERE Id = :groupId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (grps.isEmpty())
      throw new AuraHandledException('Group not found.');
    if (grps[0].Status__c != 'Approved')
      throw new AuraHandledException('Group is not active.');

    // Internal users (admins / staff) have no Person Account — they can post/comment freely.
    if (currentAccountId == null)
      return;

    if (grps[0].Created_By__c == currentAccountId)
      return;

    List<Ken_Group_Member__c> members = [
      SELECT Id
      FROM Ken_Group_Member__c
      WHERE
        Group__c = :groupId
        AND Member__c = :currentAccountId
        AND Status__c = 'Approved'
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (members.isEmpty()) {
      throw new AuraHandledException(
        'You must be a member of this group to participate in its feed.'
      );
    }
  }

  private static Boolean isInternalUser() {
    return currentAccountId() == null;
  }

  private static Map<Id, Id> mapUsersToAccounts(Set<Id> userIds) {
    Map<Id, Id> out = new Map<Id, Id>();
    if (userIds == null || userIds.isEmpty())
      return out;
    for (User u : [
      SELECT Id, AccountId, ContactId
      FROM User
      WHERE Id IN :userIds
    WITH SYSTEM_MODE
    ]) {
      if (u.AccountId != null) {
        out.put(u.Id, u.AccountId);
      } else {
        out.put(u.Id, null);
      }
    }
    Set<Id> missingUserIds = new Set<Id>();
    for (Id uid : userIds) {
      if (out.get(uid) == null)
        missingUserIds.add(uid);
    }
    if (!missingUserIds.isEmpty()) {
      Map<Id, Id> contactByUser = new Map<Id, Id>();
      for (User u : [
        SELECT Id, ContactId
        FROM User
        WHERE Id IN :missingUserIds AND ContactId != NULL
      WITH SYSTEM_MODE
      ]) {
        contactByUser.put(u.Id, u.ContactId);
      }
      if (!contactByUser.isEmpty()) {
        Map<Id, Id> accountByContact = new Map<Id, Id>();
        for (Contact c : [
          SELECT Id, AccountId
          FROM Contact
          WHERE Id IN :contactByUser.values()
        WITH SECURITY_ENFORCED
        ]) {
          accountByContact.put(c.Id, c.AccountId);
        }
        for (Id uid : contactByUser.keySet()) {
          Id cid = contactByUser.get(uid);
          if (cid != null && accountByContact.get(cid) != null) {
            out.put(uid, accountByContact.get(cid));
          }
        }
      }
    }
    return out;
  }

  /**
   * Internal users (admins) have no Person Account — fall back to User.Name / SmallPhotoUrl
   * so backend posts/comments render with proper author info.
   */
  public class UserInfoDTO {
    public String name;
    public String photoUrl;
  }

  public static Map<Id, UserInfoDTO> mapUserFallbacks(Set<Id> userIds) {
    Map<Id, UserInfoDTO> out = new Map<Id, UserInfoDTO>();
    if (userIds == null || userIds.isEmpty())
      return out;
    for (User u : [
      SELECT Id, Name, SmallPhotoUrl
      FROM User
      WHERE Id IN :userIds
    WITH SYSTEM_MODE
    ]) {
      UserInfoDTO dto = new UserInfoDTO();
      dto.name = u.Name;
      dto.photoUrl = u.SmallPhotoUrl;
      out.put(u.Id, dto);
    }
    return out;
  }

  private static Map<Id, String> mapAccountNames(Set<Id> accountIds) {
    Map<Id, String> out = new Map<Id, String>();
    if (accountIds == null || accountIds.isEmpty())
      return out;
    for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :accountIds WITH SECURITY_ENFORCED]) {
      out.put(a.Id, a.Name);
    }
    return out;
  }

  /**
   * What the composer needs to drop an image straight into the editor: the
   * document Id it will store as sfdc://, plus a URL it can render right now.
   */
  public class InlineImageDTO {
    @AuraEnabled
    public Id contentDocumentId;
    @AuraEnabled
    public Id contentVersionId;
    @AuraEnabled
    public String previewUrl;
  }

  @AuraEnabled(cacheable=false)
  public static InlineImageDTO uploadInlineImage(
    String fileName,
    String base64Data
  ) {
    Id documentId = uploadAttachment(fileName, base64Data);
    ContentVersion cv = [
      SELECT Id
      FROM ContentVersion
      WHERE ContentDocumentId = :documentId AND IsLatest = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    InlineImageDTO dto = new InlineImageDTO();
    dto.contentDocumentId = documentId;
    dto.contentVersionId = cv.Id;
    // Shepherd URLs are root-relative and resolve past the Experience Cloud
    // site path, so inside the portal they come back as a broken image (the
    // same reason KenGalleryController prefers a distribution link).
    //
    // This MUST NOT be allowed to throw. An uncaught exception here rolls the
    // whole transaction back - including the ContentVersion inserted above -
    // so a failure to mint the public link would silently discard the upload
    // itself and leave the user with an error and no file. A caught exception
    // leaves earlier DML intact, so the upload survives and the caller simply
    // gets the shepherd URL instead.
    String url = null;
    try {
      Map<Id, String> publicUrl = KenCreateContentVersion.createDistributions(
        new Set<Id>{ cv.Id },
        false
      );
      url = publicUrl.get(cv.Id);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'uploadInlineImage: public link failed, falling back to shepherd: ' +
        e.getMessage()
      );
    }
    dto.previewUrl = String.isNotBlank(url)
      ? url
      : '/sfc/servlet.shepherd/version/download/' + cv.Id;
    return dto;
  }

  public class ImageBytesResult {
    @AuraEnabled
    public String base64Data;
    @AuraEnabled
    public String contentType;
    @AuraEnabled
    public String fileName;
  }

  /**
   * @description Returns a post image's raw bytes (base64) instead of a URL, so the browser
   *              never has to fetch the file cross-origin. The share feature's own attempt to
   *              download the image via a plain fetch() to its Salesforce URL was silently
   *              blocked by CORS whenever that URL's domain differs from the portal page's —
   *              routing the bytes through this existing Apex/LDS channel sidesteps that
   *              entirely, since it's the same mechanism every other @AuraEnabled call already
   *              uses successfully. Covers both a gallery attachment (linked via
   *              ContentDocumentLink) and an inline body image (identified only by the
   *              sfdc://&lt;ContentDocumentId&gt; reference embedded in the post's own Body) —
   *              ownership is verified against whichever of those two this document actually is,
   *              not just trusted from the client.
   */
  @AuraEnabled(cacheable=false)
  public static ImageBytesResult getImageBytes(
    Id groupId,
    Id feedItemId,
    Id contentDocumentId
  ) {
    if (groupId == null || feedItemId == null || contentDocumentId == null) {
      throw new AuraHandledException('Missing required parameters.');
    }
    assertGroupAccessible(groupId);

    List<FeedItem> feedItems = [
      SELECT Id, Body
      FROM FeedItem
      WHERE Id = :feedItemId AND ParentId = :groupId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (feedItems.isEmpty())
      throw new AuraHandledException('Post not found in this group.');

    Boolean isInlineImage =
      String.isNotBlank(feedItems[0].Body) &&
      feedItems[0].Body.contains('sfdc://' + contentDocumentId);

    Boolean isGalleryAttachment = false;
    if (!isInlineImage) {
      for (ContentDocumentLink link : [
        SELECT Id
        FROM ContentDocumentLink
        WHERE
          LinkedEntityId = :feedItemId
          AND ContentDocumentId = :contentDocumentId
      WITH SYSTEM_MODE
      ]) {
        isGalleryAttachment = true;
      }
    }
    if (!isInlineImage && !isGalleryAttachment) {
      throw new AuraHandledException('Attachment not found on this post.');
    }

    List<ContentVersion> versions = [
      SELECT VersionData, FileType, Title, PathOnClient
      FROM ContentVersion
      WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (versions.isEmpty())
      throw new AuraHandledException('Attachment not found.');

    ContentVersion cv = versions[0];
    ImageBytesResult result = new ImageBytesResult();
    result.base64Data = EncodingUtil.base64Encode(cv.VersionData);
    result.contentType = String.isNotBlank(cv.FileType)
      ? 'image/' + cv.FileType.toLowerCase()
      : 'image/jpeg';
    result.fileName = String.isNotBlank(cv.PathOnClient)
      ? cv.PathOnClient
      : (String.isNotBlank(cv.Title) ? cv.Title : 'shared-image') + '.jpg';
    return result;
  }

  @AuraEnabled(cacheable=false)
  public static Id uploadAttachment(String fileName, String base64Data) {
    if (String.isBlank(fileName) || String.isBlank(base64Data)) {
      throw new AuraHandledException('File name and data are required.');
    }
    ContentVersion cv = new ContentVersion(
      Title = fileName,
      PathOnClient = fileName,
      VersionData = EncodingUtil.base64Decode(base64Data),
      IsMajorVersion = true
    );
    Database.insert(cv, true, AccessLevel.SYSTEM_MODE);
    ContentVersion saved = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    return saved.ContentDocumentId;
  }
}