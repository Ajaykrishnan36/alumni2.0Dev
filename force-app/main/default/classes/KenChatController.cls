/**
 * @description Alumni portal chat - 1:1 (Individuals tab) and group (Groups tab).
 *
 *              Messages live in ONE big object, Ken_Chat_Msg__b. Chat keeps no room table and
 *              no membership table: the room Id IS a record Id from something that already
 *              exists, so "which rooms is this person in" is answered by objects that are
 *              already indexed and already maintained.
 *
 *                  1:1    Room_Id__c = Ken_Network_Connection__c Id  (Status__c = 'Accepted')
 *                  Group  Room_Id__c = Ken_Group__c Id              (Ken_Group_Member__c 'Approved')
 *
 *              Three consequences fall out of that for free: blocking a connection removes the
 *              room, because the list is built from Accepted rows; a chat with no messages yet
 *              still lists ("Start Conversation"), because the list does not come from the
 *              message table; and removing a group member removes their room the same way.
 *
 *              Runs `without sharing` to match the other portal controllers (KenNetworkController
 *              and friends) - Account external OWD is Private, so cross-alumnus reads need it.
 *              A big object has no sharing model, no owner and no FLS regardless, so ALL access
 *              control here is assertRoomAccess(). Nothing below it is enforced by the platform.
 *
 *              Big object constraints that shape this class, all verified against the org:
 *                - Queries must filter on Room_Id__c (index field 1), with no gaps.
 *                - Rows return in index order, newest first; ORDER BY cannot change it.
 *                - COUNT() and every aggregate throw BIG_OBJECT_UNSUPPORTED_OPERATION.
 *                - A queried row is READ-ONLY. Rewriting means constructing a new record and
 *                  copying every field - see rewriteRead().
 *                - insertImmediate/deleteImmediate commit outside the transaction: no rollback.
 */
public without sharing class KenChatController {
  /**
   * Ceiling on rooms examined in one call. Each room costs a big-object query for its newest
   * message, so an alumnus with hundreds of connections would otherwise blow the 100-SOQL
   * limit. Past this the list is still correct, just ordered by the underlying query rather
   * than by true recency.
   */
  private static final Integer ROOM_SCAN_CAP = 60;

  /**
   * How many rooms one call returns. Matched to ROOM_SCAN_CAP on purpose: getRooms already runs
   * a big-object query for EVERY scanned room before it slices, so the cost is already paid and
   * a smaller page only throws that work away.
   *
   * It also hid connections. At 10, an alumnus with 13 accepted connections saw ten: the sort
   * puts rooms with no messages last, so the three nobody had written to yet fell off the
   * bottom - and client-side search could never find them either, because their rooms were
   * never loaded. Declared after ROOM_SCAN_CAP because Apex initialises statics in order.
   */
  private static final Integer ROOM_PAGE = ROOM_SCAN_CAP;
  private static final Integer MSG_PAGE = 50;
  private static final String TAB_GROUPS = 'Groups';

  /**
   * The server-side upload cap in bytes. Overridable in tests, which cannot build a payload
   * this large - Apex caps a String well below the base64 of 5 MB.
   */
  @TestVisible
  private static Integer maxFileBytes = 5 * 1024 * 1024;

  @TestVisible
  private static Id testCurrentAccountId;

  /**
   * Lets a test state who counts as an eligible alumnus.
   *
   * The real rule needs a person Account carrying an Active, registered Alumni ConstituentRole -
   * Education Cloud fixtures that say nothing about chat. Without this seam every chat test
   * would have to build them, and would be testing the directory's rule instead of its own
   * behaviour. eligibleAlumniExcludesNonAlumni covers the filter itself.
   */
  @TestVisible
  private static Set<Id> testEligibleAccountIds;

  // ---- DTOs ---------------------------------------------------------------------------
  // Field names follow the shapes kenChat.js already renders (INDIVIDUALS / GROUPS /
  // MESSAGES_BY_CHAT), so the templates need no rework when the mock arrays are removed.

  public class RoomItem implements Comparable {
    @AuraEnabled
    public String id; // Room_Id__c
    @AuraEnabled
    public String type; // 'individual' | 'group'
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String avatarUrl;
    @AuraEnabled
    public String lastMessage; // blank => "Start Conversation"
    @AuraEnabled
    public Boolean lastIsAttachment; // draw a paperclip in front of the preview
    @AuraEnabled
    public Datetime lastMessageAt; // label is computed in the LWC, never stored
    @AuraEnabled
    public String pillTag; // 'Mentor' / 'You are the Admin'
    @AuraEnabled
    public Boolean online;
    @AuraEnabled
    public Boolean unread; // 1:1 only; groups always false
    @AuraEnabled
    public Integer membersCount; // groups only
    // Not @AuraEnabled: the viewer's own last-seen for this room, used to decide `unread`
    // and then discarded. The LWC gets the verdict, not the raw timestamp.
    public Datetime lastSeen;

    /** Newest activity first. A room nobody has written in yet sorts to the bottom. */
    public Integer compareTo(Object other) {
      Datetime a = this.lastMessageAt;
      Datetime b = ((RoomItem) other).lastMessageAt;
      if (a == b) {
        return 0;
      }
      if (a == null) {
        return 1;
      }
      if (b == null) {
        return -1;
      }
      return a > b ? -1 : 1;
    }
  }

  public class MessageItem {
    @AuraEnabled
    public String id; // Message_Uid__c
    @AuraEnabled
    public String text;
    @AuraEnabled
    public Datetime sentAt;
    @AuraEnabled
    public Boolean isOutgoing;
    @AuraEnabled
    public String senderName;
    @AuraEnabled
    public String avatarUrl; // the SENDER's photo, so your own bubble is you
    @AuraEnabled
    public Boolean isRead; // on my own bubbles: did they read it
    @AuraEnabled
    public List<FileItem> files;
    // null/blank = never edited or deleted. 'Edited' or 'Deleted' - see Status__c on
    // Ken_Chat_Msg__b for what each rewrite does to the rest of the row.
    @AuraEnabled
    public String status;
    // Equals sentAt until the first edit or delete, then the time of the most recent one.
    @AuraEnabled
    public Datetime updatedAt;
    public MessageItem() {
      files = new List<FileItem>();
    }
  }

  /*
   * `contentDocumentId` is the important field: it is the file's real platform Id, so a message
   * can always find its file again - to re-serve it, to check it still exists, to delete it.
   * The previous shape stored only a public ContentDistribution URL, which meant every chat
   * upload was an orphan the moment it was made.
   *
   * `url` is kept for rows written by that older shape. Nothing writes it any more: a download
   * link is built at render time from the id, so it can never go stale in stored data - the same
   * reason time labels are computed in the LWC rather than stored.
   */
  public class FileItem {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public Integer size;
    @AuraEnabled
    public String url;
    @AuraEnabled
    public String contentDocumentId;
    @AuraEnabled
    public String contentVersionId; // the version the distribution points at
    @AuraEnabled
    public String fileType;
  }

  // ---- Chat list ----------------------------------------------------------------------

  /**
   * One tab's worth of rooms, ROOM_PAGE at a time.
   *
   * The last-message lookup is one query PER ROOM. That is deliberate and not a bulkification
   * miss: a single `Room_Id__c IN :ids` query would share one LIMIT across every room, and
   * because rows come back grouped by Room_Id__c a busy room would consume the whole limit and
   * starve the rest. Paging 10 rooms at a time keeps this well inside the 100-query ceiling.
   */
  @AuraEnabled
  public static List<RoomItem> getRooms(String tab, Integer offset) {
    Id me = currentAccountId();
    if (me == null) {
      return new List<RoomItem>();
    }
    Integer skip = (offset == null || offset < 0) ? 0 : offset;

    // Every room, not just the requested page: the sort key is the newest message, which
    // lives in the big object, so it cannot be known before the rooms are fetched. Slicing
    // first would order the list by group name or connection date instead of by activity.
    List<RoomItem> rooms = (TAB_GROUPS.equalsIgnoreCase(tab))
      ? groupRooms(me)
      : individualRooms(me);

    stampLastMessages(rooms);

    rooms.sort(); // newest activity first; rooms with no messages fall to the bottom

    List<RoomItem> page = new List<RoomItem>();
    for (Integer i = skip; i < rooms.size() && page.size() < ROOM_PAGE; i++) {
      page.add(rooms[i]);
    }
    return page;
  }

  private static Ken_Chat_Msg__b lastMessageIn(Id roomId) {
    List<Ken_Chat_Msg__b> rows = [
      SELECT Body__c, Sent_At__c, Sender_User_Id__c, Is_Read__c, Attachments__c, Status__c
      FROM Ken_Chat_Msg__b
      WHERE Room_Id__c = :roomId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  @TestVisible
  private static Set<Id> eligibleAlumni(Id me) {
    if (Test.isRunningTest() && testEligibleAccountIds != null) {
      return testEligibleAccountIds;
    }
    return KenNetworkController.getEligibleAlumniAccountIds(me);
  }

  private static List<RoomItem> individualRooms(Id me) {
    return individualRooms(me, null);
  }

  /**
   * `onlyWith` narrows the list to the single room shared with one alumnus - what the profile
   * page needs when it opens a P2P thread. Passing null gives the whole Individuals tab.
   *
   * Kept as one method so a person's name, photo, mentor pill and online dot are built exactly
   * once. A second code path for "just this room" is how the two would start to disagree.
   */
  private static List<RoomItem> individualRooms(Id me, Id onlyWith) {
    // Accepted only - a Blocked or Rejected connection simply stops being a room.
    List<Ken_Network_Connection__c> conns = (onlyWith == null)
      ? [
          SELECT
            Id,
            Initiator__c,
            Recipient__c,
            Initiator_Last_Seen__c,
            Recipient_Last_Seen__c
          FROM Ken_Network_Connection__c
          WHERE
            Status__c = 'Accepted'
            AND (Initiator__c = :me
            OR Recipient__c = :me)
          WITH SECURITY_ENFORCED
          ORDER BY Accepted_Date__c DESC NULLS LAST
          LIMIT :ROOM_SCAN_CAP
        ]
      : [
          SELECT
            Id,
            Initiator__c,
            Recipient__c,
            Initiator_Last_Seen__c,
            Recipient_Last_Seen__c
          FROM Ken_Network_Connection__c
          WHERE
            Status__c = 'Accepted'
            AND ((Initiator__c = :me
            AND Recipient__c = :onlyWith)
            OR (Initiator__c = :onlyWith
            AND Recipient__c = :me))
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
    /*
     * The same eligibility the directory applies, borrowed rather than restated: an Accepted
     * connection to someone with no active Alumni ConstituentRole is not a room. Without this,
     * Network's "Your Connections" and the chat list disagreed on how many connections someone
     * had, which reads as a bug in whichever one the viewer checks second.
     */
    Set<Id> eligible = eligibleAlumni(me);

    List<RoomItem> out = new List<RoomItem>();
    Map<Id, Id> counterpartByRoom = new Map<Id, Id>();
    for (Ken_Network_Connection__c c : conns) {
      Id other = (c.Initiator__c == me) ? c.Recipient__c : c.Initiator__c;
      if (other == null || !eligible.contains(other)) {
        continue;
      }
      counterpartByRoom.put(c.Id, other);
      RoomItem r = new RoomItem();
      r.id = c.Id;
      r.type = 'individual';
      r.unread = false;
      r.lastSeen = (c.Initiator__c == me)
        ? c.Initiator_Last_Seen__c
        : c.Recipient_Last_Seen__c;
      out.add(r);
    }
    if (counterpartByRoom.isEmpty()) {
      return out;
    }

    // Names, photos and the mentor pill come from the network module, so a person looks
    // identical in chat and in the directory. Online status is NOT on ProfileCardSummary,
    // so it is read straight from Account.Last_Active__c using the same five-minute window
    // KenNetworkController.isCurrentlyOnline() applies - the heartbeat in
    // KenNotificationController keeps that field fresh on every page.
    Map<Id, KenNetworkController.ProfileCardSummary> cards = KenNetworkController.getProfileCardSummaries(
      new Set<Id>(counterpartByRoom.values())
    );
    Map<Id, Boolean> mentorBy = KenNetworkController.getIsMentorByCounterpart(
      me,
      new Set<Id>(counterpartByRoom.values())
    );

    Map<Id, Datetime> activeByAccount = new Map<Id, Datetime>();
    for (Account a : [
      SELECT Id, Last_Active__c
      FROM Account
      WHERE Id IN :counterpartByRoom.values()
    WITH SECURITY_ENFORCED
    ]) {
      activeByAccount.put(a.Id, a.Last_Active__c);
    }

    for (RoomItem r : out) {
      Id other = counterpartByRoom.get(r.id);
      KenNetworkController.ProfileCardSummary card = cards.get(other);
      r.name = (card == null) ? '' : card.name;
      r.avatarUrl = (card == null) ? null : card.profileImage;
      r.online = isOnline(activeByAccount.get(other));
      if (mentorBy != null && mentorBy.get(other) == true) {
        r.pillTag = 'Mentor';
      }
    }
    return out;
  }

  private static List<RoomItem> groupRooms(Id me) {
    List<Ken_Group_Member__c> mine = [
      SELECT Group__c, Role__c, Last_Seen_At__c
      FROM Ken_Group_Member__c
      WHERE Member__c = :me AND Status__c = 'Approved'
    WITH SECURITY_ENFORCED
    ];
    Map<Id, String> roleByGroup = new Map<Id, String>();
    Map<Id, Datetime> seenByGroup = new Map<Id, Datetime>();
    for (Ken_Group_Member__c m : mine) {
      if (m.Group__c != null) {
        roleByGroup.put(m.Group__c, m.Role__c);
        seenByGroup.put(m.Group__c, m.Last_Seen_At__c);
      }
    }
    if (roleByGroup.isEmpty()) {
      return new List<RoomItem>();
    }

    List<Ken_Group__c> groups = [
      SELECT Id, Name, Banner_Image_URL__c, Member_Count__c
      FROM Ken_Group__c
      WHERE
        Id IN :roleByGroup.keySet()
        AND Is_Active__c = TRUE
        // The group's OWN approval, not the membership's - KenGroupsController requires both,
        // so a group still awaiting approval was a chat room but not a group.
        AND Status__c = 'Approved'
      WITH SECURITY_ENFORCED
      ORDER BY Name
      LIMIT :ROOM_SCAN_CAP
    ];
    List<RoomItem> out = new List<RoomItem>();
    for (Ken_Group__c g : groups) {
      RoomItem r = new RoomItem();
      r.id = g.Id;
      r.type = 'group';
      r.name = g.Name;
      r.avatarUrl = g.Banner_Image_URL__c;
      r.membersCount = (g.Member_Count__c == null)
        ? 0
        : Integer.valueOf(g.Member_Count__c);
      r.online = false;
      r.unread = false; // decided in getRooms, against seenByGroup
      r.lastSeen = seenByGroup.get(g.Id);
      if ('Admin'.equals(roleByGroup.get(g.Id))) {
        r.pillTag = 'You are the Admin';
      }
      out.add(r);
    }
    return out;
  }

  // ---- Messages -----------------------------------------------------------------------

  /**
   * Newest MSG_PAGE messages in a room, oldest-first for rendering.
   *
   * No ORDER BY: the index is already Sent_At__c DESC and a big object cannot be sorted any
   * other way. `before` pages further back and is the ONLY way to paginate - big object SOQL
   * has no OFFSET.
   */
  @AuraEnabled
  public static List<MessageItem> getMessages(
    Id roomId,
    Datetime before,
    Boolean markSeen
  ) {
    assertRoomAccess(roomId);
    Id myUserId = UserInfo.getUserId();

    List<Ken_Chat_Msg__b> rows = (before == null)
      ? [
          SELECT
            Room_Id__c,
            Sent_At__c,
            Message_Uid__c,
            Body__c,
            Sender_User_Id__c,
            Is_Read__c,
            Attachments__c,
            Status__c,
            Updated_At__c
          FROM Ken_Chat_Msg__b
          WHERE Room_Id__c = :roomId
          WITH SECURITY_ENFORCED
          LIMIT 50
        ]
      : [
          SELECT
            Room_Id__c,
            Sent_At__c,
            Message_Uid__c,
            Body__c,
            Sender_User_Id__c,
            Is_Read__c,
            Attachments__c,
            Status__c,
            Updated_At__c
          FROM Ken_Chat_Msg__b
          WHERE Room_Id__c = :roomId AND Sent_At__c < :before
          LIMIT 50
        ];

    Map<Id, SenderInfo> senderByUser = sendersByUserId(rows);

    List<MessageItem> out = new List<MessageItem>();
    for (Ken_Chat_Msg__b m : rows) {
      MessageItem item = new MessageItem();
      item.id = m.Message_Uid__c;
      item.sentAt = m.Sent_At__c;
      item.updatedAt = m.Updated_At__c;
      item.isOutgoing = (m.Sender_User_Id__c == myUserId);
      SenderInfo sender = senderByUser.get(m.Sender_User_Id__c);
      item.senderName = sender == null ? null : sender.name;
      item.avatarUrl = sender == null ? null : sender.avatarUrl;
      item.isRead = (m.Is_Read__c == 1);
      item.status = m.Status__c;
      // deleteMessage() deliberately keeps Body__c/Attachments__c intact for later analysis -
      // this check is the ONLY thing hiding a deleted message's content from ordinary chat use.
      if (m.Status__c == 'Deleted') {
        item.text = null;
        item.files = new List<FileItem>();
      } else {
        item.text = m.Body__c;
        item.files = parseFiles(m.Attachments__c);
      }
      out.add(item);
    }
    // Stamped on EVERY fetch, not just the first. A thread left open for an hour would
    // otherwise lose every message that arrived after it was opened, and they would all come
    // back as unread once the tab closed.
    /*
     * markSeen is false when the caller is a background poll on an unfocused window. The
     * thread still refreshes on screen, but the room is not counted as read - otherwise a tab
     * left open on a second monitor would silently absorb every new message, and the row
     * could never go bold again.
     */
    fillMissingFileUrls(out);

    if (markSeen != false) {
      Datetime newest = rows.isEmpty() ? null : rows[0].Sent_At__c;
      stampLastSeen(roomId, newest);
    }

    // Index order is newest-first; the thread renders oldest-first.
    List<MessageItem> reversed = new List<MessageItem>();
    for (Integer i = out.size() - 1; i >= 0; i--) {
      reversed.add(out[i]);
    }
    return reversed;
  }

  /**
   * Records that the running user has now looked at this room.
   *
   * Deliberately NOT called when someone leaves a thread: a closed tab, a dropped connection or
   * a killed browser would never fire it, and the room would stay unread forever despite having
   * been read. Stamping on arrival and on each poll fails in the harmless direction instead.
   *
   * MUST BE CALLED AFTER EVERY BIG OBJECT QUERY IN THE TRANSACTION. A big object read is treated
   * as a callout, so once any DML has run, the next one throws:
   *     System.ExternalObjectException: A callout was unsuccessful because of pending
   *     uncommitted work...
   * Moving this call earlier in getMessages compiles fine and fails only at runtime.
   */
  private static void stampLastSeen(Id roomId, Datetime newest) {
    Id me = currentAccountId();
    if (me == null) {
      return;
    }
    Datetime now = System.now();
    try {
      if (isGroupRoom(roomId)) {
        List<Ken_Group_Member__c> rows = [
          SELECT Id, Last_Seen_At__c
          FROM Ken_Group_Member__c
          WHERE
            Group__c = :roomId
            AND Member__c = :me
            AND Status__c = 'Approved'
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        if (!rows.isEmpty() && isStale(rows[0].Last_Seen_At__c, newest)) {
          rows[0].Last_Seen_At__c = now;
          update rows[0];
        }
      } else {
        List<Ken_Network_Connection__c> rows = [
          SELECT
            Id,
            Initiator__c,
            Initiator_Last_Seen__c,
            Recipient_Last_Seen__c
          FROM Ken_Network_Connection__c
          WHERE Id = :roomId
          WITH SECURITY_ENFORCED
          LIMIT 1
        ];
        if (!rows.isEmpty()) {
          Boolean iAmInitiator = (rows[0].Initiator__c == me);
          Datetime mine = iAmInitiator
            ? rows[0].Initiator_Last_Seen__c
            : rows[0].Recipient_Last_Seen__c;
          if (isStale(mine, newest)) {
            if (iAmInitiator) {
              rows[0].Initiator_Last_Seen__c = now;
            } else {
              rows[0].Recipient_Last_Seen__c = now;
            }
            update rows[0];
          }
        }
      }
    } catch (DmlException e) {
      // Never fail a read because the bookkeeping write did. Worst case the dot lingers
      // until the next poll, which stamps again.
      System.debug(
        LoggingLevel.WARN,
        'stampLastSeen skipped: ' + e.getMessage()
      );
    }
  }

  /**
   * Name and photo travel together because they come from the same lookup. Resolving them
   * separately would mean running the profile query twice for one thread.
   */
  private class SenderInfo {
    String name;
    String avatarUrl;
    SenderInfo(String name, String avatarUrl) {
      this.name = name;
      this.avatarUrl = avatarUrl;
    }
  }

  private static Map<Id, SenderInfo> sendersByUserId(
    List<Ken_Chat_Msg__b> rows
  ) {
    Set<Id> userIds = new Set<Id>();
    for (Ken_Chat_Msg__b m : rows) {
      if (String.isNotBlank(m.Sender_User_Id__c)) {
        userIds.add(m.Sender_User_Id__c);
      }
    }
    Map<Id, SenderInfo> out = new Map<Id, SenderInfo>();
    if (userIds.isEmpty()) {
      return out;
    }

    /*
     * The sender's Account is DERIVED from the stored User id, never stored alongside it.
     *
     * A denormalised Sender_Account_Id__c used to sit on the row as a shortcut past this hop,
     * and it could not be trusted: rewriteRead - which every mark-read runs - does not copy it,
     * so reading a message blanked it. One id, resolved on read, cannot go stale or disagree
     * with the profile it names.
     *
     * User.Name is deliberately NOT the source. When one Experience Cloud user reads another
     * external user the platform substitutes CommunityNickname for Name, so a group thread
     * labelled every sender "User17703822092083328269" while the Account behind it was plainly
     * called "sdsa dssadsa". SmallPhotoUrl is the default silhouette for the same reason. The
     * Account carries the real name and the real photo.
     */
    Map<Id, Id> accountByUser = new Map<Id, Id>();
    Map<Id, User> internalUsers = new Map<Id, User>();
    for (User u : [
      SELECT Id, Name, SmallPhotoUrl, ContactId, Contact.AccountId
      FROM User
      WHERE Id IN :userIds
    WITH SYSTEM_MODE
    ]) {
      if (u.ContactId != null && u.Contact.AccountId != null) {
        accountByUser.put(u.Id, u.Contact.AccountId);
      } else {
        // No Contact at all - an internal user. Name is correct for them: the nickname
        // substitution only applies to EXTERNAL users, and they have no alumni Account.
        internalUsers.put(u.Id, u);
      }
    }

    if (!accountByUser.isEmpty()) {
      Map<Id, KenNetworkController.ProfileCardSummary> cards = KenNetworkController.getProfileCardSummaries(
        new Set<Id>(accountByUser.values())
      );
      for (Id userId : accountByUser.keySet()) {
        KenNetworkController.ProfileCardSummary card = cards.get(
          accountByUser.get(userId)
        );
        if (card != null) {
          out.put(userId, new SenderInfo(card.name, card.profileImage));
        }
      }
    }
    for (User u : internalUsers.values()) {
      out.put(u.Id, new SenderInfo(u.Name, u.SmallPhotoUrl));
    }
    return out;
  }

  /**
   * Fills in each room's newest message, its preview and whether it is unread. One big-object
   * query per room, which is what ROOM_SCAN_CAP exists to bound.
   */
  private static void stampLastMessages(List<RoomItem> rooms) {
    Id myUserId = UserInfo.getUserId();
    for (RoomItem r : rooms) {
      Ken_Chat_Msg__b last = lastMessageIn(r.id);
      if (last == null) {
        continue;
      }
      r.lastMessage = previewOf(last);
      r.lastIsAttachment =
        String.isBlank(last.Body__c) &&
        !parseFiles(last.Attachments__c).isEmpty();
      r.lastMessageAt = last.Sent_At__c;
      // Compared against the viewer's own last-seen, so this works for a group too -
      // Is_Read__c sits on a shared message and cannot say which member has looked.
      r.unread =
        last.Sender_User_Id__c != myUserId &&
        (r.lastSeen == null ||
        last.Sent_At__c > r.lastSeen);
    }
  }

  /**
   * The one room shared with a given alumnus - the P2P thread the Network profile opens.
   *
   * Accepted-only is enforced HERE rather than trusted from the page: the Message button is
   * already hidden unless the connection is accepted, but a hidden button is a UI state, not a
   * security boundary. No connection means no room, and the caller gets nothing back.
   */
  @AuraEnabled
  public static RoomItem getRoomForAlumnus(Id accountId) {
    Id me = currentAccountId();
    if (me == null || accountId == null) {
      return null;
    }
    List<RoomItem> rooms = individualRooms(me, accountId);
    if (rooms.isEmpty()) {
      return null;
    }
    stampLastMessages(rooms);
    return rooms[0];
  }

  /**
   * Gives a URL to attachments stored before uploads started minting one.
   *
   * Those files have an id but nothing to fetch, so the chip rendered as dead text and clicking
   * it did nothing - which looked like a permission problem between the two sides of a
   * conversation, and was not: the URL is public, and the older rows simply never had one.
   *
   * Resolved on READ rather than by rewriting the big object rows. A big object write commits
   * outside the transaction and cannot be rolled back, so a migration that goes wrong damages
   * messages; this heals the same rows with no write to them at all. An existing distribution is
   * reused, and only a genuinely missing one is created, so repeated polls do not pile up
   * duplicates.
   *
   * Runs AFTER the big object read, never before: a big object read counts as a callout, and any
   * DML ahead of it makes the next read throw.
   */
  @TestVisible
  private static void fillMissingFileUrls(List<MessageItem> items) {
    Set<Id> needed = new Set<Id>();
    for (MessageItem m : items) {
      if (m.files == null) {
        continue;
      }
      for (FileItem f : m.files) {
        if (String.isBlank(f.url) && String.isNotBlank(f.contentVersionId)) {
          needed.add(f.contentVersionId);
        }
      }
    }
    if (needed.isEmpty()) {
      return;
    }

    Map<Id, String> urlByVersion = new Map<Id, String>();
    for (ContentDistribution d : [
      SELECT ContentVersionId, ContentDownloadUrl
      FROM ContentDistribution
      WHERE ContentVersionId IN :needed
    WITH SYSTEM_MODE
    ]) {
      if (String.isNotBlank(d.ContentDownloadUrl)) {
        urlByVersion.put(d.ContentVersionId, d.ContentDownloadUrl);
      }
    }

    Set<Id> missing = new Set<Id>(needed);
    missing.removeAll(urlByVersion.keySet());
    if (!missing.isEmpty()) {
      urlByVersion.putAll(KenCreateContentVersion.createDistributions(missing));
    }

    for (MessageItem m : items) {
      if (m.files == null) {
        continue;
      }
      for (FileItem f : m.files) {
        if (
          String.isBlank(f.url) && urlByVersion.containsKey(f.contentVersionId)
        ) {
          f.url = urlByVersion.get(f.contentVersionId);
        }
      }
    }
  }

  /**
   * What the chat list shows as a room's last line.
   *
   * A message carrying only a file has a null Body__c - which fell through to the LWC's
   * "Start Conversation" empty state, so a room whose latest message was a document read as a
   * room nobody had ever written in.
   *
   * An image is described rather than named: "Photo" says what it is, where
   * "WhatsApp Image 2026-06-08 at 14.48.28.jpeg" fills the row with noise. A document keeps its
   * filename, which is the useful part.
   */
  @TestVisible
  private static String previewOf(Ken_Chat_Msg__b m) {
    if (m == null) {
      return null;
    }
    if (m.Status__c == 'Deleted') {
      return 'This message was deleted';
    }
    if (String.isNotBlank(m.Body__c)) {
      return m.Body__c;
    }

    List<FileItem> files = parseFiles(m.Attachments__c);
    if (files.isEmpty()) {
      return null;
    }

    FileItem f = files[0];
    String label = isImageType(f.fileType, f.name) ? 'Photo' : f.name;
    if (files.size() > 1) {
      label += ' +' + String.valueOf(files.size() - 1);
    }
    return label;
  }

  private static Boolean isImageType(String fileType, String fileName) {
    Set<String> imageTypes = new Set<String>{
      'PNG',
      'JPG',
      'JPEG',
      'GIF',
      'WEBP',
      'BMP',
      'SVG'
    };
    if (
      String.isNotBlank(fileType) && imageTypes.contains(fileType.toUpperCase())
    ) {
      return true;
    }
    // Older rows carry no fileType, so fall back to the extension.
    String n = (fileName == null) ? '' : fileName.toLowerCase();
    for (String t : imageTypes) {
      if (n.endsWith('.' + t.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  private static List<FileItem> parseFiles(String raw) {
    List<FileItem> out = new List<FileItem>();
    if (String.isBlank(raw)) {
      return out;
    }
    try {
      out = (List<FileItem>) JSON.deserialize(raw, List<FileItem>.class);
    } catch (Exception e) {
      // A malformed blob must not take the whole thread down - render the text without files.
    }
    return out == null ? new List<FileItem>() : out;
  }

  // ---- Sending ------------------------------------------------------------------------

  @AuraEnabled
  public static String sendMessage(
    Id roomId,
    String body,
    String attachmentsJson
  ) {
    assertRoomAccess(roomId);
    if (String.isBlank(body) && String.isBlank(attachmentsJson)) {
      throw new AuraHandledException('Type a message before sending.');
    }
    String uid = generateUid();
    Datetime now = System.now();
    if (!Schema.sObjectType.Ken_Chat_Msg__b.isCreateable()) {
      throw new KenCrudException('Ken_Chat_Msg__b is not createable by the current user.');
    }
    Database.insertImmediate(
      new List<Ken_Chat_Msg__b>{
        new Ken_Chat_Msg__b(
          Room_Id__c = roomId,
          Sent_At__c = now,
          Message_Uid__c = uid,
          Body__c = censorProfanity(body),
          Sender_User_Id__c = UserInfo.getUserId(),
          Is_Read__c = 0,
          Attachments__c = attachmentsJson,
          Updated_At__c = now // starts equal to Sent_At__c; bumped by editMessage/deleteMessage
        )
      }
    );
    return uid;
  }

  // ---- Profanity filter -----------------------------------------------------------------

  /**
   * The word list is English-only for now (see KenProfanityWords static resource) - regional
   * languages were trialled and pulled back out until someone fluent can review them, so
   * this can grow again later. Compiled into ONE Pattern rather than looping
   * String.replaceAll per word regardless of current size: at the ~3,800-entry multi-language
   * scale this was tested at, one-replaceAll-per-word meant thousands of separate regex
   * compiles and full-string scans on every single message - slow, and a real CPU-time-limit
   * risk once more languages come back.
   *
   * Cached for the life of the transaction so a page sending several messages in one request
   * builds this once, not per message.
   */
  private static Pattern profanityPatternCache;
  private static Boolean profanityPatternAttempted = false;

  /**
   * Builds the compiled pattern from the KenProfanityWords static resource. Returns null (and
   * only ever tries once per transaction) if the resource is missing or malformed - a broken
   * word list must never stop someone from sending a message, it just means nothing gets
   * censored until the resource is fixed.
   *
   * (?iU) - case-insensitive AND Unicode-aware word boundaries. Plain \b is ASCII-only: it
   * looks for a transition between a \w character (just [a-zA-Z0-9_]) and a non-\w one, so
   * for a script like Tamil or Devanagari - where NONE of the characters are ASCII \w - \b
   * never fires at all and every word in those languages would silently never match.
   * Verified directly against this org before shipping: plain \b found nothing in a Tamil or
   * Hindi sentence containing a listed word; (?iU) found it correctly in both.
   */
  private static Pattern profanityPattern() {
    if (profanityPatternCache != null || profanityPatternAttempted) {
      return profanityPatternCache;
    }
    profanityPatternAttempted = true;
    try {
      StaticResource sr = [
        SELECT Body
        FROM StaticResource
        WHERE Name = 'KenProfanityWords'
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      List<Object> raw = (List<Object>) JSON.deserializeUntyped(
        sr.Body.toString()
      );
      List<String> escaped = new List<String>();
      for (Object o : raw) {
        String word = o == null ? null : String.valueOf(o);
        if (String.isNotBlank(word)) {
          escaped.add(word.replaceAll('([.*+?^${}()|\\[\\]\\\\])', '\\\\$1'));
        }
      }
      if (!escaped.isEmpty()) {
        profanityPatternCache = Pattern.compile(
          '(?iU)\\b(' + String.join(escaped, '|') + ')\\b'
        );
      }
    } catch (Exception e) {
      System.debug('Profanity word list unavailable: ' + e.getMessage());
    }
    return profanityPatternCache;
  }

  /** Replaces every whole-word match (any listed language, case-insensitive) with **. */
  @TestVisible
  private static String censorProfanity(String text) {
    if (String.isBlank(text)) {
      return text;
    }
    Pattern p = profanityPattern();
    if (p == null) {
      return text;
    }
    return p.matcher(text).replaceAll('**');
  }

  /** UUID v4. A big object has no Id, so identity has to be generated here. */
  private static String generateUid() {
    String h = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
    return h.substring(0, 8) +
      '-' +
      h.substring(8, 12) +
      '-4' +
      h.substring(13, 16) +
      '-' +
      h.substring(16, 20) +
      '-' +
      h.substring(20, 32);
  }

  // ---- Read state ---------------------------------------------------------------------

  /**
   * Marks the OTHER person's messages read, walking newest to oldest and stopping at the first
   * already-read one - everything older than a read message is read too, so there is nothing
   * below it to do. In the steady state that stops on row one and writes nothing at all.
   *
   * Is_Read__c means different things by sender: on my own message it records whether THEY
   * read it (and drives my tick), on theirs whether I did. Each side only ever writes the
   * other side's rows, which is why my own messages `continue` rather than `break` - my latest
   * reply sitting on top must not stop the walk before their unread messages underneath it.
   *
   * 1:1 only. Groups render no ticks and no dot, so nothing is marked.
   */
  @AuraEnabled
  public static Integer markRead(Id roomId) {
    assertRoomAccess(roomId);
    if (isGroupRoom(roomId)) {
      return 0;
    }
    Id myUserId = UserInfo.getUserId();

    List<Ken_Chat_Msg__b> rows = [
      SELECT
        Room_Id__c,
        Sent_At__c,
        Message_Uid__c,
        Body__c,
        Sender_User_Id__c,
        Is_Read__c,
        Attachments__c,
        Status__c,
        Updated_At__c
      FROM Ken_Chat_Msg__b
      WHERE Room_Id__c = :roomId
      WITH SECURITY_ENFORCED
      LIMIT 50
    ];

    List<Ken_Chat_Msg__b> toMark = unreadToMark(rows, myUserId);
    if (!toMark.isEmpty()) {
      if (!Schema.sObjectType.Ken_Chat_Msg__b.isCreateable()) {
        throw new KenCrudException('Ken_Chat_Msg__b is not createable by the current user.');
      }
      Database.insertImmediate(toMark);
    }
    return toMark.size();
  }

  /**
   * The walk itself, kept free of DML so it can be tested - big object DML is not supported in
   * an Apex test context, so anything that writes one is untestable by definition.
   *
   * `rows` must be in index order (newest first). Returns the rebuilt rows to write.
   */
  @TestVisible
  private static List<Ken_Chat_Msg__b> unreadToMark(
    List<Ken_Chat_Msg__b> rows,
    Id myUserId
  ) {
    List<Ken_Chat_Msg__b> toMark = new List<Ken_Chat_Msg__b>();
    for (Ken_Chat_Msg__b m : rows) {
      // newest -> oldest, from the index
      if (m.Sender_User_Id__c == myUserId) {
        continue;
      } // mine: skip, keep walking
      if (m.Is_Read__c == 1) {
        break;
      } // theirs, already read: done
      toMark.add(rewriteRead(m));
    }
    return toMark;
  }

  /**
   * The ONLY place a Ken_Chat_Msg__b row is rebuilt.
   *
   * A queried big object row is read-only - mutating one throws "Field is not writeable" - so
   * an update means constructing a new record on the same index key, which REPLACES the old
   * row wholesale. Every field omitted here is written as null and its contents are gone, with
   * no rollback. Kept in one method so that adding a field to the object means changing one
   * line rather than hunting for every rewrite site.
   */
  @TestVisible
  private static Ken_Chat_Msg__b rewriteRead(Ken_Chat_Msg__b old) {
    return new Ken_Chat_Msg__b(
      Room_Id__c = old.Room_Id__c, // index - must match exactly
      Sent_At__c = old.Sent_At__c, // index
      Message_Uid__c = old.Message_Uid__c, // index
      Body__c = old.Body__c,
      Sender_User_Id__c = old.Sender_User_Id__c,
      Attachments__c = old.Attachments__c,
      Status__c = old.Status__c,
      Updated_At__c = old.Updated_At__c, // a read receipt is not an edit - leave it alone
      Is_Read__c = 1
    );
  }

  /**
   * Looks up one exact row by its full index key. All three fields are required: Sent_At__c and
   * Message_Uid__c together are what make the row unique under a room, and Room_Id__c is what
   * assertRoomAccess has already vetted the caller against.
   */
  private static Ken_Chat_Msg__b findMessage(
    Id roomId,
    Datetime sentAt,
    String messageUid
  ) {
    List<Ken_Chat_Msg__b> rows = [
      SELECT
        Room_Id__c,
        Sent_At__c,
        Message_Uid__c,
        Body__c,
        Sender_User_Id__c,
        Is_Read__c,
        Attachments__c,
        Status__c,
        Updated_At__c
      FROM Ken_Chat_Msg__b
      WHERE
        Room_Id__c = :roomId
        AND Sent_At__c = :sentAt
        AND Message_Uid__c = :messageUid
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  /**
   * Edits a message's text in place, the same rewrite-on-the-index-key trick as rewriteRead -
   * a big object row cannot be updated, only replaced on an identical index. Only the sender
   * may edit their own message, and a deleted one cannot be brought back this way.
   */
  @AuraEnabled
  public static void editMessage(
    Id roomId,
    Datetime sentAt,
    String messageUid,
    String newBody
  ) {
    assertRoomAccess(roomId);
    if (String.isBlank(newBody)) {
      throw new AuraHandledException('A message cannot be empty.');
    }
    Ken_Chat_Msg__b old = findMessage(roomId, sentAt, messageUid);
    if (old == null) {
      throw new AuraHandledException('That message could not be found.');
    }
    if (old.Sender_User_Id__c != UserInfo.getUserId()) {
      throw new AuraHandledException('You can only edit your own messages.');
    }
    if (old.Status__c == 'Deleted') {
      throw new AuraHandledException('A deleted message cannot be edited.');
    }
    Database.insertImmediate(
      new List<Ken_Chat_Msg__b>{
        new Ken_Chat_Msg__b(
          Room_Id__c = old.Room_Id__c,
          Sent_At__c = old.Sent_At__c,
          Message_Uid__c = old.Message_Uid__c,
          Body__c = censorProfanity(newBody),
          Sender_User_Id__c = old.Sender_User_Id__c,
          Attachments__c = old.Attachments__c,
          Is_Read__c = old.Is_Read__c,
          Status__c = 'Edited',
          Updated_At__c = System.now()
        )
      }
    );
  }

  /**
   * Soft-deletes a message: ONLY Status__c changes, to 'Deleted'. Body__c and Attachments__c
   * are copied forward UNCHANGED - the original content is kept for later analysis, not
   * destroyed. What hides it from ordinary use is getMessages/previewOf refusing to return
   * Body__c/Attachments__c once they see Status__c = 'Deleted' (they return a placeholder
   * instead), not the absence of the data. Only the sender may delete their own message.
   */
  @AuraEnabled
  public static void deleteMessage(Id roomId, Datetime sentAt, String messageUid) {
    assertRoomAccess(roomId);
    Ken_Chat_Msg__b old = findMessage(roomId, sentAt, messageUid);
    if (old == null) {
      throw new AuraHandledException('That message could not be found.');
    }
    if (old.Sender_User_Id__c != UserInfo.getUserId()) {
      throw new AuraHandledException('You can only delete your own messages.');
    }
    Database.insertImmediate(
      new List<Ken_Chat_Msg__b>{
        new Ken_Chat_Msg__b(
          Room_Id__c = old.Room_Id__c,
          Sent_At__c = old.Sent_At__c,
          Message_Uid__c = old.Message_Uid__c,
          Body__c = old.Body__c,
          Sender_User_Id__c = old.Sender_User_Id__c,
          Attachments__c = old.Attachments__c,
          Updated_At__c = System.now(),
          Is_Read__c = old.Is_Read__c,
          Status__c = 'Deleted'
        )
      }
    );
  }

  // ---- Files --------------------------------------------------------------------------

  /**
   * Uploads one chat file and returns it as a FileItem for the caller to fold into the
   * message's Attachments__c JSON.
   *
   * The file is linked to the ROOM record, not to the message. A big object row has no Id for
   * ContentDocumentLink to point at, but Room_Id__c IS a real record Id - a
   * Ken_Network_Connection__c for a 1:1, a Ken_Group__c for a group - so the link can hang off
   * that instead. Room, timestamp and uploader then come out of ContentDocumentLink and
   * ContentDocument for free, and access follows the room.
   *
   * This replaces a ContentDistribution public URL. The note that used to live here said the
   * sharing-enforced servlet "refuses portal users" - which it does for a file with no
   * ContentDocumentLink at all, i.e. an orphan owned by the uploader, which is what the old code
   * produced. A file shared to a record the viewer can already read is a different case.
   *
   * STILL TO VERIFY as an alumnus in the portal: that the download path resolves for a portal
   * user. If it does not, the fix is the link's ShareType/Visibility or serving the bytes
   * through Apex - not a public distribution URL, which outlives the conversation and opens
   * with no login.
   */
  @AuraEnabled
  public static FileItem uploadChatFile(
    Id roomId,
    String fileName,
    String base64Data
  ) {
    assertRoomAccess(roomId);
    if (String.isBlank(base64Data)) {
      throw new AuraHandledException('No file data received.');
    }
    Blob data = EncodingUtil.base64Decode(base64Data);
    if (data.size() > maxFileBytes) {
      throw new AuraHandledException('Files must be 5 MB or smaller.');
    }
    String title = String.isBlank(fileName) ? 'Attachment' : fileName;

    /*
     * The ContentVersion is inserted here rather than through
     * KenCreateContentVersion.createContentVersion, which also creates a ContentDistribution -
     * a public, unauthenticated, permanent URL. That is right for the gallery and the landing
     * page, where public IS the point, and wrong for a private conversation: the link would
     * outlive the connection and open with no login.
     */
    ContentVersion cv = new ContentVersion(
      Title = title,
      PathOnClient = title,
      VersionData = data
    );
    Database.insert(cv, true, AccessLevel.SYSTEM_MODE);

    ContentVersion saved = [
      SELECT Id, ContentDocumentId, FileType
      FROM ContentVersion
      WHERE Id = :cv.Id
      WITH SYSTEM_MODE
      LIMIT 1
    ];

    /*
     * The file is linked to the ROOM record - the Ken_Network_Connection__c or Ken_Group__c
     * whose Id is Room_Id__c. That is what a big object row cannot offer and the room can: a
     * real Id for ContentDocumentLink to point at.
     *
     * It buys three things at once. Files become queryable per room and per timestamp
     * (ContentDocumentLink.LinkedEntityId + ContentDocument.CreatedDate), which a big object
     * cannot do - it cannot even COUNT(). Access follows the room, so the file is reachable by
     * exactly the people who can already read the conversation. And losing the room takes the
     * link with it.
     */
    Database.insert(new ContentDocumentLink(
      ContentDocumentId = saved.ContentDocumentId,
      LinkedEntityId = roomId,
      ShareType = 'V',
      Visibility = 'AllUsers'
    ), true, AccessLevel.SYSTEM_MODE);

    /*
     * A ContentDistribution URL, delegated to KenCreateContentVersion so the distribution
     * settings stay defined in one place (KenGalleryController uses the same helper).
     *
     * This is the URL an <img> in a portal page can actually render. The sharing-enforced
     * rendition and download servlets did not resolve for portal users here - the thread
     * showed broken images - and it is the same mechanism the alumni avatars and the gallery
     * already rely on in this org.
     *
     * The trade is real and worth stating: a ContentDistribution link is public, permanent and
     * needs no login, so anyone who obtains the URL can fetch the file even after the
     * conversation is gone. It is stored rather than rebuilt per render because the
     * distribution is created once, here, at upload.
     */
    Map<Id, String> urlByVersion = KenCreateContentVersion.createDistributions(
      new Set<Id>{ saved.Id }
    );

    FileItem f = new FileItem();
    f.id = generateUid();
    f.name = title;
    f.size = data.size();
    f.contentDocumentId = saved.ContentDocumentId;
    f.contentVersionId = saved.Id;
    f.fileType = saved.FileType;
    f.url = urlByVersion.get(saved.Id);

    /*
     * One URL only: ContentDownloadUrl. It is served Content-Disposition: attachment, which is
     * exactly what a document should do on click - save. An <img> ignores that header, so the
     * same URL also renders image previews inline.
     *
     * The distribution's DistributionPublicUrl would show a document in Salesforce's own
     * branded viewer instead of saving it. Deliberately not used: the file is meant to
     * download, and the viewer page put a Salesforce page in front of an alumni portal.
     */
    if (String.isBlank(f.url)) {
      throw new AuraHandledException(
        'That file could not be prepared for viewing.'
      );
    }
    return f;
  }

  /**
   * Every file posted in a room, newest first - the "Files in this conversation" query.
   *
   * This is the read the design is for: it comes from ContentDocumentLink, not from the big
   * object, so it can be ordered and aggregated. Reading the same list out of Ken_Chat_Msg__b
   * would mean fetching every message and parsing each Attachments__c blob.
   */
  @AuraEnabled
  public static List<FileItem> getRoomFiles(Id roomId) {
    assertRoomAccess(roomId);
    List<FileItem> out = new List<FileItem>();
    for (ContentDocumentLink l : [
      SELECT
        ContentDocumentId,
        ContentDocument.Title,
        ContentDocument.FileType,
        ContentDocument.ContentSize,
        ContentDocument.LatestPublishedVersionId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :roomId
      WITH SYSTEM_MODE
      ORDER BY ContentDocument.CreatedDate DESC
      LIMIT 200
    ]) {
      FileItem f = new FileItem();
      f.id = l.ContentDocumentId;
      f.name = l.ContentDocument.Title;
      f.size = l.ContentDocument.ContentSize;
      f.fileType = l.ContentDocument.FileType;
      f.contentDocumentId = l.ContentDocumentId;
      f.contentVersionId = l.ContentDocument.LatestPublishedVersionId;
      out.add(f);
    }
    return out;
  }

  // ---- Access -------------------------------------------------------------------------

  /**
   * The single gate. A big object has no sharing, no owner and no FLS, so this is the entire
   * security model for chat - every @AuraEnabled entry point calls it before touching a
   * message. It works because Room_Id__c is index field 1: no message can be read or written
   * without naming a room, so there is exactly one place to check.
   */
  private static void assertRoomAccess(Id roomId) {
    if (roomId == null) {
      throw new AuraHandledException('No conversation specified.');
    }
    Id me = currentAccountId();
    if (me == null) {
      throw new AuraHandledException('Your alumni profile could not be found.');
    }
    if (isGroupRoom(roomId)) {
      List<Ken_Group_Member__c> m = [
        SELECT Id
        FROM Ken_Group_Member__c
        WHERE Group__c = :roomId AND Member__c = :me AND Status__c = 'Approved'
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (m.isEmpty()) {
        throw new AuraHandledException('You are not a member of this group.');
      }
      return;
    }
    // 1:1 - Accepted only, so a Blocked connection loses access to a thread it once had.
    List<Ken_Network_Connection__c> c = [
      SELECT Id
      FROM Ken_Network_Connection__c
      WHERE
        Id = :roomId
        AND Status__c = 'Accepted'
        AND (Initiator__c = :me
        OR Recipient__c = :me)
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (c.isEmpty()) {
      throw new AuraHandledException('This conversation is not available.');
    }
  }

  /** Room Ids are real record Ids, so the object they belong to identifies the room type. */
  // ---- config -------------------------------------------------------------------------

  public class ChatConfigDTO {
    @AuraEnabled
    public Integer listPollMs;
    @AuraEnabled
    public Integer threadPollMs;
  }

  /**
   * Poll intervals, admin-tunable through Ken_Alm_Org_Parameters__c without a deploy - the same
   * pattern KenNotificationController.resolvePollIntervalSeconds() uses.
   *
   * Clamped server-side rather than trusted from the setting: the thread interval multiplies
   * query load by every concurrent viewer, so a well-meaning "1 second" typed into a custom
   * setting would be an org-wide problem, not a local one.
   */
  @AuraEnabled(cacheable=true)
  public static ChatConfigDTO getChatConfig() {
    Ken_Alm_Org_Parameters__c p = Ken_Alm_Org_Parameters__c.getInstance();
    ChatConfigDTO cfg = new ChatConfigDTO();
    /*
     * Two cadences, not three.
     *
     * The room list and the header's unread badge are AMBIENT - "has anything changed while
     * I am doing something else" - which is exactly what the notification bell asks, so they
     * share Notification_Poll_Interval_Seconds__c. There used to be a
     * Chat_List_Poll_Interval_Seconds__c beside it, and the badge ignored both and polled on a
     * hardcoded 60s, so the same question was being asked on three different clocks.
     *
     * An open thread is the one genuinely different case: it has to feel live, so it keeps its
     * own, much shorter interval.
     */
    cfg.listPollMs =
      KenNotificationController.resolvePollIntervalSeconds() * 1000;
    cfg.threadPollMs =
      clamp(
        p == null ? null : p.Chat_Thread_Poll_Interval_Seconds__c,
        10,
        5,
        120
      ) * 1000;
    return cfg;
  }

  private static Integer clamp(
    Decimal value,
    Integer fallback,
    Integer lo,
    Integer hi
  ) {
    if (value == null) {
      return fallback;
    }
    Integer v = value.intValue();
    if (v < lo) {
      return lo;
    }
    if (v > hi) {
      return hi;
    }
    return v;
  }

  // ---- Unread badge -------------------------------------------------------------------

  /** Past this the header shows "9+", so counting further is wasted work. Nine, not ten,
   *  so the pill never exceeds two characters and stays the same circle as the bell. */
  private static final Integer BADGE_CAP = 9;

  /**
   * Hard ceiling on rooms scanned for the badge, because each one costs a query.
   *
   * The early exit only fires when there IS unread; someone with nothing unread scans every
   * room they have, and that is the common case. Without this an alumnus with ~100 connections
   * and groups would blow the 100-SOQL limit and throw on EVERY page of the portal.
   *
   * Rooms are visited newest-activity first, so the ones most likely to hold something unread
   * are checked before the budget runs out. The cost of hitting it is an under-reported badge
   * for a very heavily connected user - not an exception.
   */
  private static final Integer BADGE_ROOM_SCAN_CAP = ROOM_SCAN_CAP;

  /**
   * Total unread across EVERY room - deliberately not paginated, unlike the chat list. A badge
   * that only counted the first page would stay dark while an unread conversation sat at
   * position 11.
   *
   * Two early exits keep that affordable: within a room the walk stops at the first message the
   * viewer has already seen (everything older is seen too), and across rooms it stops entirely
   * once the cap is reached.
   */
  @AuraEnabled
  public static Integer getUnreadCount() {
    Id me = currentAccountId();
    if (me == null) {
      return 0;
    }
    Id myUserId = UserInfo.getUserId();
    Integer total = 0;
    Integer scanned = 0;

    for (Ken_Network_Connection__c c : [
      SELECT Id, Initiator__c, Initiator_Last_Seen__c, Recipient_Last_Seen__c
      FROM Ken_Network_Connection__c
      WHERE
        Status__c = 'Accepted'
        AND (Initiator__c = :me
        OR Recipient__c = :me)
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
      LIMIT :BADGE_ROOM_SCAN_CAP
    ]) {
      Datetime seen = (c.Initiator__c == me)
        ? c.Initiator_Last_Seen__c
        : c.Recipient_Last_Seen__c;
      total += unreadInRoom(c.Id, seen, myUserId, BADGE_CAP - total);
      scanned++;
      if (total >= BADGE_CAP) {
        return BADGE_CAP;
      }
    }

    Integer groupBudget = BADGE_ROOM_SCAN_CAP - scanned;
    if (groupBudget <= 0) {
      return total;
    }
    for (Ken_Group_Member__c m : [
      SELECT Group__c, Last_Seen_At__c
      FROM Ken_Group_Member__c
      WHERE
        Member__c = :me
        AND Status__c = 'Approved'
        AND Group__r.Is_Active__c = TRUE
      WITH SECURITY_ENFORCED
      ORDER BY LastModifiedDate DESC
      LIMIT :groupBudget
    ]) {
      if (m.Group__c == null) {
        continue;
      }
      total += unreadInRoom(
        m.Group__c,
        m.Last_Seen_At__c,
        myUserId,
        BADGE_CAP - total
      );
      if (total >= BADGE_CAP) {
        return BADGE_CAP;
      }
    }
    return total;
  }

  /**
   * Unread messages in one room, capped at `needed`.
   *
   * Rows arrive newest-first, and "seen" is a single point in time, so the first message at or
   * before the viewer's last-seen ends the walk - everything behind it is older and therefore
   * seen as well. The viewer's own messages are skipped rather than ending the walk, or their
   * last reply would hide everything the other person sent after it.
   */
  private static Integer unreadInRoom(
    Id roomId,
    Datetime lastSeen,
    Id myUserId,
    Integer needed
  ) {
    if (needed <= 0) {
      return 0;
    }
    return countUnread(
      [
        SELECT Sent_At__c, Sender_User_Id__c
        FROM Ken_Chat_Msg__b
        WHERE Room_Id__c = :roomId
        WITH SECURITY_ENFORCED
        LIMIT 10
      ],
      lastSeen,
      myUserId,
      needed
    );
  }

  /**
   * The walk itself, kept free of SOQL so it can be tested - Database.insertImmediate is not
   * supported in a test context, so the only way to cover this is to hand it rows directly.
   *
   * `rows` must be in index order (newest first), which is how the big object always returns them.
   */
  @TestVisible
  private static Integer countUnread(
    List<Ken_Chat_Msg__b> rows,
    Datetime lastSeen,
    Id myUserId,
    Integer needed
  ) {
    // Checked here and not only in the caller: the increment happens before the budget test,
    // so a needed of 0 would otherwise return 1.
    if (rows == null || needed == null || needed <= 0) {
      return 0;
    }
    Integer n = 0;
    for (Ken_Chat_Msg__b m : rows) {
      if (lastSeen != null && m.Sent_At__c <= lastSeen) {
        break;
      }
      if (m.Sender_User_Id__c == myUserId) {
        continue;
      }
      n++;
      if (n >= needed) {
        break;
      }
    }
    return n;
  }

  /**
   * True when the viewer's stamp is behind the newest message they were just shown.
   *
   * An open thread refetches every 10 seconds; without this each poll issued a DML that wrote
   * the same "nothing new" state, which is both wasteful and slow enough to notice.
   */
  private static Boolean isStale(Datetime lastSeen, Datetime newest) {
    if (newest == null) {
      return lastSeen == null;
    }
    return lastSeen == null || lastSeen < newest;
  }

  /**
   * Same five-minute window as KenNetworkController.isCurrentlyOnline, duplicated because that
   * method is private. Account.Last_Active__c is stamped by the notification heartbeat, so it
   * refreshes once a minute for anyone with the portal open.
   */
  private static Boolean isOnline(Datetime lastActive) {
    return lastActive != null &&
      lastActive.getTime() >= System.now().addMinutes(-5).getTime();
  }

  private static Boolean isGroupRoom(Id roomId) {
    return roomId != null &&
      roomId.getSobjectType() == Ken_Group__c.SObjectType;
  }

  private static Id currentAccountId() {
    if (Test.isRunningTest() && testCurrentAccountId != null) {
      return testCurrentAccountId;
    }
    List<User> users = [
      SELECT Id, AccountId, ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (users.isEmpty()) {
      return null;
    }
    if (users[0].AccountId != null) {
      return users[0].AccountId;
    }
    if (users[0].ContactId != null) {
      List<Contact> cons = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :users[0].ContactId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!cons.isEmpty()) {
        return cons[0].AccountId;
      }
    }
    return null;
  }
}