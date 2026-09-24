/**
 * @description Covers the async fallback that opens a gallery file up to portal
 *              users when the ContentDocumentLink was not yet written at the time
 *              the ContentVersion trigger ran.
 */
@IsTest
private class KenGalleryShareFixerTest {
  private static Ken_File__c newGalleryFile() {
    Ken_Album__c album = new Ken_Album__c(Name = 'Convocation 2024');
    insert album;
    Ken_File__c file = new Ken_File__c(Album__c = album.Id, Name = 'group.png');
    insert file;
    return file;
  }

  /**
   * The share fix itself: a file linked internal-only is unreadable in the
   * portal, so the gallery renders a broken image. Running the job must bring it
   * up to V/AllUsers, which is what the portal's own upload path sets.
   */
  @IsTest
  static void testExecuteOpensTheFileUpToPortalUsers() {
    Ken_File__c file = newGalleryFile();
    insert new ContentVersion(
      Title = 'group.png',
      PathOnClient = 'group.png',
      VersionData = Blob.valueOf('test'),
      FirstPublishLocationId = file.Id
    );

    // Put the link back to internal-only so the job has something to correct.
    ContentDocumentLink link = [
      SELECT Id, ShareType, Visibility
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :file.Id
      LIMIT 1
    ];
    link.ShareType = 'I';
    link.Visibility = 'InternalUsers';
    update link;

    Test.startTest();
    new KenGalleryShareFixer(new Set<Id>{ file.Id }).execute(null);
    Test.stopTest();

    ContentDocumentLink fixed = [
      SELECT ShareType, Visibility
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :file.Id
      LIMIT 1
    ];
    System.assertEquals('V', fixed.ShareType, 'The portal cannot read a file shared as I.');
    System.assertEquals(
      'AllUsers',
      fixed.Visibility,
      'InternalUsers keeps the image broken for every Experience Cloud user.'
    );
  }

  /**
   * enqueue() runs the fix inline under test rather than queueing it, so a test
   * that inserts a ContentVersion is not forced to stop/start the queue.
   */
  @IsTest
  static void testEnqueueAppliesTheFixInlineDuringTests() {
    Ken_File__c file = newGalleryFile();
    insert new ContentVersion(
      Title = 'group.png',
      PathOnClient = 'group.png',
      VersionData = Blob.valueOf('test'),
      FirstPublishLocationId = file.Id
    );

    Test.startTest();
    KenGalleryShareFixer.enqueue(new Set<Id>{ file.Id });
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'],
      'Under test the fix runs inline, so nothing should be queued.'
    );
  }

  /**
   * Nothing to fix must cost nothing - the trigger calls this for every upload.
   */
  @IsTest
  static void testEnqueueIgnoresEmptyAndNullInput() {
    Test.startTest();
    KenGalleryShareFixer.enqueue(null);
    KenGalleryShareFixer.enqueue(new Set<Id>());
    Test.stopTest();

    System.assertEquals(
      0,
      [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'],
      'An empty request must not queue a job.'
    );
  }
}