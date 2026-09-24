/**
 * @description Tests for KenChatController.
 *
 *              Database.insertImmediate is NOT supported in an Apex test context - it fails with
 *              "Internal Salesforce.com Query Error" - so nothing that writes a big object row can
 *              be unit tested. That splits verification in two:
 *
 *                - Logic that can be isolated from DML is tested here, in memory. The mark-read
 *                  walk matters most: its continue-vs-break rule is the one bug in this feature
 *                  that silently stops a sender's tick from ever turning.
 *                - Platform behaviour that only exists against a real big object has NO automated
 *                  coverage and must be checked by hand against a sandbox after any change to the
 *                  object or its index: that the index returns newest-first, that Sent_At__c <
 *                  cutoff pages backwards, that two messages in the same millisecond both survive
 *                  (this is why Message_Uid__c is the third index field), and that a rewrite
 *                  overwrites in place rather than duplicating the row.
 *
 *                  The index IS the primary key and cannot be changed after creation - altering it
 *                  means dropping the object and every message in it - so these are worth
 *                  re-checking before any such change reaches users.
 */
@IsTest
private class KenChatControllerTest {
  private static Account alumnusA;
  private static Account alumnusB;

  private static void setup() {
    alumnusA = new Account(Name = 'Chat Test A');
    alumnusB = new Account(Name = 'Chat Test B');
    insert new List<Account>{ alumnusA, alumnusB };
    // Chat lists only eligible alumni, which really means a person Account with an Active
    // Alumni ConstituentRole. Declared here so each test exercises chat, not Education Cloud
    // fixtures; eligibleAlumniExcludesNonAlumni covers the filter itself.
    KenChatController.testEligibleAccountIds = new Set<Id>{
      alumnusA.Id,
      alumnusB.Id
    };
  }

  /** In-memory row; never inserted, so no big object DML is involved. */
  private static Ken_Chat_Msg__b row(String uid, Id sender, Integer read) {
    return new Ken_Chat_Msg__b(
      Room_Id__c = 'ZZTESTROOM00000001',
      Sent_At__c = Datetime.now(),
      Message_Uid__c = uid,
      Body__c = 'body ' + uid,
      Sender_User_Id__c = sender,
      Is_Read__c = read,
      Attachments__c = '[{"id":"f1","name":"cv.pdf","size":10,"url":"https://x/y"}]'
    );
  }

  /**
   * The walk skips the reader's own messages and stops at the first already-read one.
   * Rows are supplied newest-first, exactly as the index returns them:
   *
   *      theirs  unread   <- mark
   *      MINE             <- SKIP, must not be treated as a stopping point
   *      theirs  unread   <- mark; only reached if the walk continued past mine
   *      theirs  READ     <- stop here
   *      theirs  unread   <- leave alone, it is below the stop
   *
   * Breaking on the reader's own message instead of continuing leaves the second unread
   * message unmarked forever, and the sender's tick never turns.
   */
  @IsTest
  static void markReadSkipsOwnMessagesAndStopsAtFirstRead() {
    Id me = UserInfo.getUserId();
    Id them = '005000000000000AAA';

    List<Ken_Chat_Msg__b> newestFirst = new List<Ken_Chat_Msg__b>{
      row('m5', them, 0), // mark
      row('m4', me, 0), // skip
      row('m3', them, 0), // mark
      row('m2', them, 1), // stop
      row('m1', them, 0) // never reached
    };

    Test.startTest();
    List<Ken_Chat_Msg__b> marked = KenChatController.unreadToMark(
      newestFirst,
      me
    );
    Test.stopTest();

    Set<String> uids = new Set<String>();
    for (Ken_Chat_Msg__b m : marked) {
      uids.add(m.Message_Uid__c);
    }

    Assert.areEqual(
      2,
      marked.size(),
      'Only the two unread messages above the stop are marked'
    );
    Assert.isTrue(uids.contains('m5'), 'Newest unread must be marked');
    Assert.isTrue(
      uids.contains('m3'),
      'Must keep walking past the reader\'s own message - the continue-vs-break bug'
    );
    Assert.isFalse(
      uids.contains('m1'),
      'Must not walk below the first already-read message'
    );
    Assert.isFalse(
      uids.contains('m4'),
      'The reader\'s own message is never marked'
    );
  }

  /** Nothing to do when the newest message is already read - the steady state writes nothing. */
  @IsTest
  static void markReadWritesNothingWhenAlreadyCaughtUp() {
    Id me = UserInfo.getUserId();
    List<Ken_Chat_Msg__b> rows = new List<Ken_Chat_Msg__b>{
      row('m2', '005000000000000AAA', 1),
      row('m1', '005000000000000AAA', 1)
    };
    Test.startTest();
    List<Ken_Chat_Msg__b> marked = KenChatController.unreadToMark(rows, me);
    Test.stopTest();
    Assert.areEqual(
      0,
      marked.size(),
      'A caught-up thread should produce no writes at all'
    );
  }

  /**
   * A rewrite replaces the entire row, so rewriteRead must carry every field across. A field
   * missed here is written as null against live data, with no rollback - this test is the guard
   * for anyone adding a field to Ken_Chat_Msg__b later.
   */
  @IsTest
  static void rewriteReadCopiesEveryField() {
    Ken_Chat_Msg__b before = row('uid-X', '005000000000000AAA', 0);

    Test.startTest();
    Ken_Chat_Msg__b after = KenChatController.rewriteRead(before);
    Test.stopTest();

    Assert.areEqual(before.Room_Id__c, after.Room_Id__c, 'index field 1');
    Assert.areEqual(before.Sent_At__c, after.Sent_At__c, 'index field 2');
    Assert.areEqual(
      before.Message_Uid__c,
      after.Message_Uid__c,
      'index field 3'
    );
    Assert.areEqual(before.Body__c, after.Body__c, 'Body must be copied');
    Assert.areEqual(
      before.Sender_User_Id__c,
      after.Sender_User_Id__c,
      'Sender must be copied'
    );
    Assert.areEqual(
      before.Attachments__c,
      after.Attachments__c,
      'Attachments must be copied'
    );
    Assert.areEqual(
      1,
      Integer.valueOf(after.Is_Read__c),
      'Is_Read is the one field that changes'
    );
  }

  /** A user with no alumni Account sees no rooms rather than an error. */
  @IsTest
  static void noAccountYieldsNoRooms() {
    Test.startTest();
    List<KenChatController.RoomItem> rooms = KenChatController.getRooms(
      'Individuals',
      0
    );
    Test.stopTest();
    Assert.areEqual(
      0,
      rooms.size(),
      'A user with no alumni Account should see an empty list'
    );
  }

  /** Every entry point is gated; a room the caller is not in must be refused, not just hidden. */
  @IsTest
  static void assertRoomAccessRefusesNonMember() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Ken_Group__c g = new Ken_Group__c(
      Name = 'Closed Group',
      Is_Active__c = true,
      Status__c = 'Approved'
    );
    insert g; // alumnusA is deliberately NOT a member

    Boolean refused = false;
    Test.startTest();
    try {
      KenChatController.getMessages(g.Id, null, true);
    } catch (Exception e) {
      refused = true;
    }
    Test.stopTest();
    Assert.isTrue(refused, 'A non-member must be refused by assertRoomAccess');
  }

  /** An accepted connection is a room even before anyone has spoken in it. */
  @IsTest
  static void acceptedConnectionListsWithNoMessages() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;
    insert new Ken_Network_Connection__c(
      Initiator__c = alumnusA.Id,
      Recipient__c = alumnusB.Id,
      Status__c = 'Accepted',
      Accepted_Date__c = Datetime.now()
    );

    Test.startTest();
    List<KenChatController.RoomItem> rooms = KenChatController.getRooms(
      'Individuals',
      0
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      rooms.size(),
      'The accepted connection should appear as a room'
    );
    Assert.isTrue(
      String.isBlank(rooms[0].lastMessage),
      'With no messages the room lists blank, which the UI renders as Start Conversation'
    );
  }

  /** A blocked connection stops being a room, and its thread stops being reachable. */
  @IsTest
  static void blockedConnectionIsNotARoom() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;
    Ken_Network_Connection__c c = new Ken_Network_Connection__c(
      Initiator__c = alumnusA.Id,
      Recipient__c = alumnusB.Id,
      Status__c = 'Blocked'
    );
    insert c;

    Boolean refused = false;
    Test.startTest();
    List<KenChatController.RoomItem> rooms = KenChatController.getRooms(
      'Individuals',
      0
    );
    try {
      KenChatController.getMessages(c.Id, null, true);
    } catch (Exception e) {
      refused = true;
    }
    Test.stopTest();

    Assert.areEqual(
      0,
      rooms.size(),
      'A blocked connection must not list as a room'
    );
    Assert.isTrue(
      refused,
      'A blocked connection must also lose access to the existing thread'
    );
  }

  /** A group room the caller belongs to is listed, with the admin pill when they run it. */
  @IsTest
  static void groupRoomListsForApprovedMember() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;
    Ken_Group__c g = new Ken_Group__c(
      Name = 'Eco Warriors',
      Is_Active__c = true,
      Status__c = 'Approved'
    );
    insert g;
    insert new Ken_Group_Member__c(
      Group__c = g.Id,
      Member__c = alumnusA.Id,
      Status__c = 'Approved',
      Role__c = 'Admin'
    );

    Test.startTest();
    List<KenChatController.RoomItem> rooms = KenChatController.getRooms(
      'Groups',
      0
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      rooms.size(),
      'An approved membership should list as a group room'
    );
    Assert.areEqual('group', rooms[0].type, 'Type drives which tab renders it');
    Assert.areEqual(
      'You are the Admin',
      rooms[0].pillTag,
      'Admin role shows the admin pill'
    );
    Assert.isFalse(
      rooms[0].unread,
      'Groups carry no read state, so never show unread'
    );
  }

  // ---- poll config ------------------------------------------------------------------------
  /*
   * Two cadences: the room list and the header badge ride the portal's AMBIENT interval, the
   * same one the notification bell uses, and only an open thread has its own. There used to be a
   * third chat-specific list interval, plus a hardcoded 60s in the header, so the same question
   * was asked on three clocks.
   */

  @IsTest
  static void configFallsBackWhenUnset() {
    Test.startTest();
    KenChatController.ChatConfigDTO c = KenChatController.getChatConfig();
    Test.stopTest();
    Assert.areEqual(
      60000,
      c.listPollMs,
      'unset, the list falls back to the ambient 60s the notification bell uses'
    );
    Assert.areEqual(
      10000,
      c.threadPollMs,
      'thread interval should fall back to 10s'
    );
  }

  /** The list follows the notification setting, so one value tunes every background badge. */
  @IsTest
  static void listPollFollowsTheNotificationInterval() {
    Ken_Alm_Org_Parameters__c p = Ken_Alm_Org_Parameters__c.getOrgDefaults();
    p.Notification_Poll_Interval_Seconds__c = 90;
    upsert p;

    Test.startTest();
    KenChatController.ChatConfigDTO c = KenChatController.getChatConfig();
    Test.stopTest();

    Assert.areEqual(
      90000,
      c.listPollMs,
      'the ambient interval drives the chat list too'
    );
  }

  @IsTest
  static void configClampsValuesThatWouldHurtTheOrg() {
    // The thread interval multiplies query load by every concurrent viewer, so a "1" typed
    // into the custom setting has to be caught server-side, not trusted.
    Ken_Alm_Org_Parameters__c p = Ken_Alm_Org_Parameters__c.getOrgDefaults();
    p.Chat_Thread_Poll_Interval_Seconds__c = 1;
    p.Notification_Poll_Interval_Seconds__c = 1;
    upsert p;

    KenChatController.ChatConfigDTO low = KenChatController.getChatConfig();
    Assert.areEqual(
      5000,
      low.threadPollMs,
      'thread interval should clamp up to its 5s floor'
    );
    Assert.areEqual(
      10000,
      low.listPollMs,
      'the ambient interval has a 10s floor of its own'
    );

    p.Chat_Thread_Poll_Interval_Seconds__c = 99999;
    upsert p;

    KenChatController.ChatConfigDTO high = KenChatController.getChatConfig();
    Assert.areEqual(
      120000,
      high.threadPollMs,
      'thread interval should clamp down to its 120s ceiling'
    );
  }

  @IsTest
  static void configHonoursASensibleValue() {
    Ken_Alm_Org_Parameters__c p = Ken_Alm_Org_Parameters__c.getOrgDefaults();
    p.Chat_Thread_Poll_Interval_Seconds__c = 15;
    upsert p;

    KenChatController.ChatConfigDTO c = KenChatController.getChatConfig();
    Assert.areEqual(
      15000,
      c.threadPollMs,
      'an in-range thread value should pass through'
    );
  }

  // ---- unread counting for the header badge -----------------------------------------------

  /*
   * One frozen base for every timestamp in these tests. Calling System.now() per message made
   * the boundary case flaky: the cutoff and the message meant to sit exactly on it were built
   * microseconds apart, so "<= lastSeen" missed by a hair and the walk counted one row too many.
   */
  private static final Datetime T0 = Datetime.newInstance(2026, 1, 1, 12, 0, 0);

  private static Ken_Chat_Msg__b at(Integer minutesAgo, Id sender) {
    return new Ken_Chat_Msg__b(
      Room_Id__c = 'a0Q000000000001AAA',
      Sent_At__c = T0.addMinutes(-minutesAgo),
      Message_Uid__c = 'u' + minutesAgo,
      Sender_User_Id__c = sender
    );
  }

  @IsTest
  static void countsEverythingWhenNeverSeen() {
    Id me = UserInfo.getUserId();
    Id them = '005000000000000AAA';
    List<Ken_Chat_Msg__b> newestFirst = new List<Ken_Chat_Msg__b>{
      at(1, them),
      at(2, me),
      at(3, them),
      at(4, them)
    };
    Integer n = KenChatController.countUnread(newestFirst, null, me, 10);
    Assert.areEqual(
      3,
      n,
      'a null last-seen means every message from them is unread'
    );
  }

  @IsTest
  static void stopsAtTheFirstMessageAlreadySeen() {
    Id me = UserInfo.getUserId();
    Id them = '005000000000000AAA';
    Datetime seen = T0.addMinutes(-3); // exactly on the third message
    List<Ken_Chat_Msg__b> newestFirst = new List<Ken_Chat_Msg__b>{
      at(1, them),
      at(2, them),
      at(3, them),
      at(4, them)
    };
    Integer n = KenChatController.countUnread(newestFirst, seen, me, 10);
    Assert.areEqual(
      2,
      n,
      'only messages newer than last-seen count; the walk stops at the rest'
    );
  }

  /*
   * The bug this guards: treating your own message as a stopping point instead of skipping it.
   * Reply to someone, they send three more, and the badge would report nothing.
   */
  @IsTest
  static void ownMessageDoesNotStopTheWalk() {
    Id me = UserInfo.getUserId();
    Id them = '005000000000000AAA';
    List<Ken_Chat_Msg__b> newestFirst = new List<Ken_Chat_Msg__b>{
      at(1, them),
      at(2, me),
      at(3, them)
    };
    Integer n = KenChatController.countUnread(newestFirst, null, me, 10);
    Assert.areEqual(
      2,
      n,
      'my own reply must be skipped, not treated as a stop'
    );
  }

  @IsTest
  static void neverCountsPastWhatTheBadgeNeeds() {
    Id me = UserInfo.getUserId();
    Id them = '005000000000000AAA';
    List<Ken_Chat_Msg__b> rows = new List<Ken_Chat_Msg__b>();
    for (Integer i = 1; i <= 10; i++) {
      rows.add(at(i, them));
    }

    Assert.areEqual(
      3,
      KenChatController.countUnread(rows, null, me, 3),
      'the walk stops as soon as the remaining budget is filled'
    );
    Assert.areEqual(
      0,
      KenChatController.countUnread(rows, null, me, 0),
      'no budget left means no work done'
    );
  }

  @IsTest
  static void countsNothingWhenCaughtUp() {
    Id me = UserInfo.getUserId();
    Id them = '005000000000000AAA';
    List<Ken_Chat_Msg__b> rows = new List<Ken_Chat_Msg__b>{
      at(5, them),
      at(6, them)
    };
    Integer n = KenChatController.countUnread(rows, T0, me, 10);
    Assert.areEqual(0, n, 'seen just now means nothing outstanding');
  }

  @IsTest
  static void unreadCountIsZeroWithoutAnAlumniProfile() {
    Test.startTest();
    Integer n = KenChatController.getUnreadCount();
    Test.stopTest();
    Assert.areEqual(
      0,
      n,
      'a user with no Account has no rooms and so no badge'
    );
  }

  // ---- files ------------------------------------------------------------------------------
  /*
   * These CAN be unit tested, unlike the message writes: uploading touches ContentVersion and
   * ContentDocumentLink, not the big object, so no Database.insertImmediate is involved.
   *
   * What they pin down is the whole point of the design - a file is linked to the ROOM record,
   * because a big object row has no Id to link to, and that is what makes files retrievable
   * per room.
   */
  private static String sampleBase64() {
    return EncodingUtil.base64Encode(Blob.valueOf('a small pretend document'));
  }

  @IsTest
  static void uploadLinksTheFileToTheOneToOneRoomRecord() {
    setup();
    Ken_Network_Connection__c c = new Ken_Network_Connection__c(
      Initiator__c = alumnusA.Id,
      Recipient__c = alumnusB.Id,
      Status__c = 'Accepted',
      Accepted_Date__c = Datetime.now()
    );
    insert c;
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Test.startTest();
    KenChatController.FileItem f = KenChatController.uploadChatFile(
      c.Id,
      'deck.pdf',
      sampleBase64()
    );
    Test.stopTest();

    Assert.isNotNull(
      f.contentDocumentId,
      'The platform Id must come back - without it the message can never find its file again'
    );
    Assert.areEqual('deck.pdf', f.name, 'The file keeps its name');

    /*
     * Filtered to the room deliberately. Inserting a ContentVersion also makes Salesforce link
     * the document to its OWNER, so the unfiltered count is 2, not 1 - asserting on the total
     * tests the platform's bookkeeping rather than ours.
     */
    List<ContentDocumentLink> links = [
      SELECT LinkedEntityId
      FROM ContentDocumentLink
      WHERE ContentDocumentId = :f.contentDocumentId AND LinkedEntityId = :c.Id
    ];
    Assert.areEqual(
      1,
      links.size(),
      'The file is linked to the connection - the room Id IS a real record Id, which is the' +
      ' whole reason this works where linking to the message cannot'
    );
  }

  @IsTest
  static void uploadLinksTheFileToTheGroupRoomRecord() {
    setup();
    Ken_Group__c g = new Ken_Group__c(
      Name = 'Tech Innovators',
      Is_Active__c = true,
      Status__c = 'Approved'
    );
    insert g;
    insert new Ken_Group_Member__c(
      Group__c = g.Id,
      Member__c = alumnusA.Id,
      Status__c = 'Approved',
      Role__c = 'Admin'
    );
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Test.startTest();
    KenChatController.FileItem f = KenChatController.uploadChatFile(
      g.Id,
      'notes.txt',
      sampleBase64()
    );
    Test.stopTest();

    // Filtered to the room for the same reason as above: the owner link is also present.
    List<ContentDocumentLink> links = [
      SELECT LinkedEntityId
      FROM ContentDocumentLink
      WHERE ContentDocumentId = :f.contentDocumentId AND LinkedEntityId = :g.Id
    ];
    Assert.areEqual(
      1,
      links.size(),
      'A group room links the same way as a 1:1'
    );
  }

  /** The per-room read - and proof that one room cannot see another room's files. */
  @IsTest
  static void roomFilesAreScopedToTheirOwnRoom() {
    setup();
    Ken_Network_Connection__c c = new Ken_Network_Connection__c(
      Initiator__c = alumnusA.Id,
      Recipient__c = alumnusB.Id,
      Status__c = 'Accepted',
      Accepted_Date__c = Datetime.now()
    );
    insert c;
    Ken_Group__c g = new Ken_Group__c(
      Name = 'Other Room',
      Is_Active__c = true,
      Status__c = 'Approved'
    );
    insert g;
    insert new Ken_Group_Member__c(
      Group__c = g.Id,
      Member__c = alumnusA.Id,
      Status__c = 'Approved',
      Role__c = 'Member'
    );
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Test.startTest();
    KenChatController.uploadChatFile(c.Id, 'in-the-dm.pdf', sampleBase64());
    KenChatController.uploadChatFile(g.Id, 'in-the-group.pdf', sampleBase64());
    List<KenChatController.FileItem> dmFiles = KenChatController.getRoomFiles(
      c.Id
    );
    List<KenChatController.FileItem> groupFiles = KenChatController.getRoomFiles(
      g.Id
    );
    Test.stopTest();

    Assert.areEqual(1, dmFiles.size(), 'The 1:1 sees only its own file');
    Assert.areEqual(
      'in-the-dm.pdf',
      dmFiles[0].name,
      'and it is the right one'
    );
    Assert.isNotNull(
      dmFiles[0].size,
      'Size comes from ContentDocument, not from stored JSON'
    );
    Assert.areEqual(1, groupFiles.size(), 'The group sees only its own file');
    Assert.areEqual(
      'in-the-group.pdf',
      groupFiles[0].name,
      'and it is the right one'
    );
  }

  /** Uploading is gated by the same door as reading: a room you are not in refuses the file. */
  @IsTest
  static void uploadRefusedForARoomYouAreNotIn() {
    setup();
    Ken_Group__c g = new Ken_Group__c(
      Name = 'Closed Group',
      Is_Active__c = true,
      Status__c = 'Approved'
    );
    insert g; // alumnusA is deliberately NOT a member
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Boolean refused = false;
    Test.startTest();
    try {
      KenChatController.uploadChatFile(g.Id, 'sneaky.pdf', sampleBase64());
    } catch (Exception e) {
      refused = true;
    }
    Test.stopTest();

    Assert.isTrue(
      refused,
      'A non-member must not be able to put a file in the room'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :g.Id],
      'and nothing may be left behind by the attempt'
    );
  }

  @IsTest
  static void uploadRejectsAFileOverFiveMegabytes() {
    setup();
    Ken_Network_Connection__c c = new Ken_Network_Connection__c(
      Initiator__c = alumnusA.Id,
      Recipient__c = alumnusB.Id,
      Status__c = 'Accepted',
      Accepted_Date__c = Datetime.now()
    );
    insert c;
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Assert.areEqual(
      5 * 1024 * 1024,
      KenChatController.maxFileBytes,
      'The server-side cap must stay at 5 MB'
    );
    KenChatController.maxFileBytes = 1024;
    String big = EncodingUtil.base64Encode(Blob.valueOf('x'.repeat(2048)));

    Boolean refused = false;
    Test.startTest();
    try {
      KenChatController.uploadChatFile(c.Id, 'huge.zip', big);
    } catch (Exception e) {
      refused = true;
    }
    Test.stopTest();

    Assert.isTrue(
      refused,
      'The 5 MB cap must hold server-side, not only in the browser'
    );
  }

  /*
   * The chat list's last line. A file-only message has a null Body__c, which fell through to the
   * LWC's "Start Conversation" empty state - so a room whose newest message was a document read
   * as a room nobody had written in. In-memory rows, so no big object DML is involved.
   */
  @IsTest
  static void previewDescribesAnImageRatherThanNamingIt() {
    Ken_Chat_Msg__b m = new Ken_Chat_Msg__b(
      Body__c = null,
      Attachments__c = '[{"name":"WhatsApp Image 2026-06-08 at 14.48.28.jpeg",' +
        '"fileType":"JPEG","size":1024}]'
    );

    Assert.areEqual(
      'Photo',
      KenChatController.previewOf(m),
      'A filename that long would fill the row with noise'
    );
  }

  @IsTest
  static void previewKeepsADocumentFilename() {
    Ken_Chat_Msg__b m = new Ken_Chat_Msg__b(
      Body__c = null,
      Attachments__c = '[{"name":"offer-letter.pdf","fileType":"PDF","size":2048}]'
    );

    Assert.areEqual(
      'offer-letter.pdf',
      KenChatController.previewOf(m),
      'For a document the name IS the useful part'
    );
  }

  @IsTest
  static void previewPrefersTypedTextOverAnAttachment() {
    Ken_Chat_Msg__b m = new Ken_Chat_Msg__b(
      Body__c = 'have a look at this',
      Attachments__c = '[{"name":"offer-letter.pdf","fileType":"PDF","size":2048}]'
    );

    Assert.areEqual(
      'have a look at this',
      KenChatController.previewOf(m),
      'What someone wrote beats a description of what they sent'
    );
  }

  @IsTest
  static void previewStaysNullWhenThereIsGenuinelyNothing() {
    Assert.isNull(
      KenChatController.previewOf(
        new Ken_Chat_Msg__b(Body__c = null, Attachments__c = null)
      ),
      'A room with no messages must still fall through to the empty state'
    );
  }

  /*
   * Attachments stored before uploads minted a URL. They have an id but nothing to fetch, so
   * the chip rendered dead and a click did nothing - which read as a permission problem between
   * the two sides of a conversation and was not one.
   */
  @IsTest
  static void missingFileUrlsAreResolvedOnRead() {
    ContentVersion cv = new ContentVersion(
      Title = 'old.pdf',
      PathOnClient = 'old.pdf',
      VersionData = Blob.valueOf('an attachment stored before urls existed')
    );
    insert cv;
    Id versionId = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id].Id;

    KenChatController.FileItem f = new KenChatController.FileItem();
    f.name = 'old.pdf';
    f.contentVersionId = versionId; // ...but deliberately no url
    KenChatController.MessageItem m = new KenChatController.MessageItem();
    m.files = new List<KenChatController.FileItem>{ f };

    Test.startTest();
    KenChatController.fillMissingFileUrls(
      new List<KenChatController.MessageItem>{ m }
    );
    Test.stopTest();

    Assert.isNotNull(
      m.files[0].url,
      'A file with a version behind it must come back with something to fetch'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM ContentDistribution
        WHERE ContentVersionId = :versionId
      ],
      'Exactly one distribution - a poll must not pile up duplicates'
    );
  }

  /** An existing distribution is reused, so repeated reads create nothing new. */
  @IsTest
  static void resolvingTwiceReusesTheSameDistribution() {
    ContentVersion cv = new ContentVersion(
      Title = 'twice.pdf',
      PathOnClient = 'twice.pdf',
      VersionData = Blob.valueOf('read me twice')
    );
    insert cv;
    Id versionId = cv.Id;

    KenChatController.FileItem f1 = new KenChatController.FileItem();
    f1.contentVersionId = versionId;
    KenChatController.MessageItem m1 = new KenChatController.MessageItem();
    m1.files = new List<KenChatController.FileItem>{ f1 };

    KenChatController.FileItem f2 = new KenChatController.FileItem();
    f2.contentVersionId = versionId;
    KenChatController.MessageItem m2 = new KenChatController.MessageItem();
    m2.files = new List<KenChatController.FileItem>{ f2 };

    Test.startTest();
    KenChatController.fillMissingFileUrls(
      new List<KenChatController.MessageItem>{ m1 }
    );
    KenChatController.fillMissingFileUrls(
      new List<KenChatController.MessageItem>{ m2 }
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM ContentDistribution
        WHERE ContentVersionId = :versionId
      ],
      'The second read must reuse the first distribution, not mint another'
    );
    Assert.areEqual(
      m1.files[0].url,
      m2.files[0].url,
      'and hand back the same URL'
    );
  }

  /** A file with neither a url nor a version cannot be healed, and must not throw trying. */
  @IsTest
  static void resolvingSkipsFilesWithNothingToGoOn() {
    KenChatController.FileItem f = new KenChatController.FileItem();
    f.name = 'orphan.pdf';
    KenChatController.MessageItem m = new KenChatController.MessageItem();
    m.files = new List<KenChatController.FileItem>{ f };

    Test.startTest();
    KenChatController.fillMissingFileUrls(
      new List<KenChatController.MessageItem>{ m }
    );
    Test.stopTest();

    Assert.isNull(
      m.files[0].url,
      'Nothing to resolve from, so it stays unresolved'
    );
  }

  /*
   * Every accepted connection has to reach the list. A page of 10 against 13 connections showed
   * ten and dropped the rest - and because the LWC filters the LOADED rooms, search could not
   * find the missing ones either.
   */
  @IsTest
  static void everyAcceptedConnectionReachesTheList() {
    setup();
    List<Account> others = new List<Account>();
    for (Integer i = 0; i < 13; i++) {
      others.add(new Account(Name = 'Chat Conn ' + i));
    }
    insert others;

    List<Ken_Network_Connection__c> conns = new List<Ken_Network_Connection__c>();
    for (Account o : others) {
      conns.add(
        new Ken_Network_Connection__c(
          Initiator__c = alumnusA.Id,
          Recipient__c = o.Id,
          Status__c = 'Accepted',
          Accepted_Date__c = Datetime.now()
        )
      );
    }
    insert conns;
    for (Account o : others) {
      KenChatController.testEligibleAccountIds.add(o.Id);
    }
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Test.startTest();
    List<KenChatController.RoomItem> rooms = KenChatController.getRooms(
      'Individuals',
      0
    );
    Test.stopTest();

    Assert.areEqual(
      13,
      rooms.size(),
      'All 13 accepted connections must be listed - a 10-room page silently hid three'
    );
  }

  // ---- eligibility, shared with the directory ---------------------------------------------

  /*
   * An Accepted connection to someone who is not an eligible alumnus is not a room. Network's
   * "Your Connections" has always applied this; chat did not, so the two lists disagreed on how
   * many connections a person had - sdsa showed one in Network and two in chat, the second being
   * a counterpart with no ConstituentRole at all.
   */
  @IsTest
  static void eligibleAlumniExcludesNonAlumni() {
    setup();
    insert new Ken_Network_Connection__c(
      Initiator__c = alumnusA.Id,
      Recipient__c = alumnusB.Id,
      Status__c = 'Accepted',
      Accepted_Date__c = Datetime.now()
    );
    KenChatController.testCurrentAccountId = alumnusA.Id;

    // B is connected and accepted, but is not an eligible alumnus.
    KenChatController.testEligibleAccountIds = new Set<Id>{ alumnusA.Id };

    Test.startTest();
    List<KenChatController.RoomItem> rooms = KenChatController.getRooms(
      'Individuals',
      0
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      rooms.size(),
      'A counterpart the directory hides must not appear as a chat room either'
    );
  }

  /** A group still awaiting approval is not a room, matching KenGroupsController. */
  @IsTest
  static void unapprovedGroupIsNotARoom() {
    setup();
    Ken_Group__c g = new Ken_Group__c(
      Name = 'Pending Group',
      Is_Active__c = true,
      Status__c = 'Pending'
    );
    insert g;
    insert new Ken_Group_Member__c(
      Group__c = g.Id,
      Member__c = alumnusA.Id,
      Status__c = 'Approved',
      Role__c = 'Member'
    );
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Test.startTest();
    List<KenChatController.RoomItem> rooms = KenChatController.getRooms(
      'Groups',
      0
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      rooms.size(),
      'Active but unapproved: the Groups module hides it, so chat must too'
    );
  }

  // ---- reads that reach the big object ------------------------------------------------------
  /*
   * A test transaction cannot create a Ken_Chat_Msg__b row, so every thread below is empty and
   * the message loop itself stays unverifiable. Everything either side of it is not: the access
   * check, both paging queries, and the last-seen stamp that has to run AFTER the big object
   * read. The stamp is the part worth guarding - moving it earlier compiles fine and only fails
   * against a real big object, so a test that never calls getMessages would not notice.
   */

  private static Ken_Network_Connection__c acceptedPair() {
    Ken_Network_Connection__c c = new Ken_Network_Connection__c(
      Initiator__c = alumnusA.Id,
      Recipient__c = alumnusB.Id,
      Status__c = 'Accepted',
      Accepted_Date__c = Datetime.now()
    );
    insert c;
    return c;
  }

  /** Reading a 1:1 thread stamps the reader's own side of the connection, not the other's. */
  @IsTest
  static void readingAThreadStampsTheInitiatorSide() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;
    Ken_Network_Connection__c c = acceptedPair();

    Test.startTest();
    List<KenChatController.MessageItem> msgs = KenChatController.getMessages(
      c.Id,
      null,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      msgs.size(),
      'No big object rows exist in a test, so the thread reads back empty'
    );
    Ken_Network_Connection__c after = [
      SELECT Initiator_Last_Seen__c, Recipient_Last_Seen__c
      FROM Ken_Network_Connection__c
      WHERE Id = :c.Id
    ];
    Assert.areNotEqual(
      null,
      after.Initiator_Last_Seen__c,
      'The reader is the initiator, so their side is stamped'
    );
    Assert.areEqual(
      null,
      after.Recipient_Last_Seen__c,
      'The other side must not be stamped - that would mark the thread read for them'
    );
  }

  /** The same read from the other end of the connection stamps the recipient side instead. */
  @IsTest
  static void readingAThreadStampsTheRecipientSide() {
    setup();
    KenChatController.testCurrentAccountId = alumnusB.Id;
    Ken_Network_Connection__c c = acceptedPair();

    Test.startTest();
    KenChatController.getMessages(c.Id, null, true);
    Test.stopTest();

    Ken_Network_Connection__c after = [
      SELECT Initiator_Last_Seen__c, Recipient_Last_Seen__c
      FROM Ken_Network_Connection__c
      WHERE Id = :c.Id
    ];
    Assert.areNotEqual(
      null,
      after.Recipient_Last_Seen__c,
      'Reading as the recipient stamps the recipient side'
    );
    Assert.areEqual(
      null,
      after.Initiator_Last_Seen__c,
      'The initiator side stays untouched'
    );
  }

  /** A background poll refreshes the thread on screen without counting it as read. */
  @IsTest
  static void pollingWithoutMarkSeenLeavesTheStampAlone() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;
    Ken_Network_Connection__c c = acceptedPair();

    Test.startTest();
    KenChatController.getMessages(c.Id, Datetime.now(), false);
    Test.stopTest();

    Ken_Network_Connection__c after = [
      SELECT Initiator_Last_Seen__c
      FROM Ken_Network_Connection__c
      WHERE Id = :c.Id
    ];
    Assert.areEqual(
      null,
      after.Initiator_Last_Seen__c,
      'markSeen false must not absorb the room as read'
    );
  }

  /** A group read stamps the caller's membership row rather than a connection. */
  @IsTest
  static void readingAGroupThreadStampsTheMembership() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;
    Ken_Group__c g = new Ken_Group__c(
      Name = 'Chat Group',
      Is_Active__c = true,
      Status__c = 'Approved'
    );
    insert g;
    Ken_Group_Member__c m = new Ken_Group_Member__c(
      Group__c = g.Id,
      Member__c = alumnusA.Id,
      Status__c = 'Approved',
      Role__c = 'Member'
    );
    insert m;

    Test.startTest();
    KenChatController.getMessages(g.Id, null, true);
    Test.stopTest();

    Ken_Group_Member__c after = [
      SELECT Last_Seen_At__c
      FROM Ken_Group_Member__c
      WHERE Id = :m.Id
    ];
    Assert.areNotEqual(
      null,
      after.Last_Seen_At__c,
      'A group room stamps the membership, which is where its read state lives'
    );
  }

  // ---- unread badge --------------------------------------------------------------------------

  /** The badge walks both room kinds; with no messages anywhere it comes back at zero. */
  @IsTest
  static void unreadCountWalksConnectionsAndGroups() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;
    acceptedPair();
    Ken_Group__c g = new Ken_Group__c(
      Name = 'Badge Group',
      Is_Active__c = true,
      Status__c = 'Approved'
    );
    insert g;
    insert new Ken_Group_Member__c(
      Group__c = g.Id,
      Member__c = alumnusA.Id,
      Status__c = 'Approved',
      Role__c = 'Member'
    );

    Test.startTest();
    Integer n = KenChatController.getUnreadCount();
    Test.stopTest();

    Assert.areEqual(
      0,
      n,
      'Rooms exist but hold no messages, so nothing is unread'
    );
  }

  // ---- the room behind a profile --------------------------------------------------------------

  /** The Network profile's Message button resolves to the one accepted thread. */
  @IsTest
  static void roomForAlumnusReturnsTheSharedThread() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;
    Ken_Network_Connection__c c = acceptedPair();

    Test.startTest();
    KenChatController.RoomItem room = KenChatController.getRoomForAlumnus(
      alumnusB.Id
    );
    Test.stopTest();

    Assert.areNotEqual(null, room, 'An accepted connection has a room');
    Assert.areEqual(c.Id, room.id, 'The room IS the connection record');
    Assert.areEqual('individual', room.type, 'A 1:1 thread is an individual room');
  }

  /** No connection means no room - the caller gets nothing rather than an empty thread. */
  @IsTest
  static void roomForAlumnusIsNullWithoutAConnection() {
    setup();
    KenChatController.testCurrentAccountId = alumnusA.Id;

    Test.startTest();
    KenChatController.RoomItem room = KenChatController.getRoomForAlumnus(
      alumnusB.Id
    );
    KenChatController.RoomItem noTarget = KenChatController.getRoomForAlumnus(
      null
    );
    Test.stopTest();

    Assert.areEqual(
      null,
      room,
      'Without an accepted connection there is no room to open'
    );
    Assert.areEqual(null, noTarget, 'A missing target alumnus yields nothing');
  }
}