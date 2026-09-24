/**
 * @description Async fallback for opening a gallery file up to portal users.
 *
 *              The ContentDocumentLink for a Setup upload is not always written
 *              by the time the ContentVersion after-insert trigger runs, so when
 *              the inline attempt finds nothing this runs once the transaction
 *              has committed and the link definitely exists.
 *
 *              Deliberately does nothing but retry the share fix - the public
 *              link is already handled synchronously, where it works reliably.
 */
public without sharing class KenGalleryShareFixer implements Queueable {
  private final Set<Id> fileIds;

  // @TestVisible because enqueue() deliberately short-circuits under
  // Test.isRunningTest(), so the job is never queued in a test and execute()
  // would otherwise be unreachable.
  @TestVisible
  private KenGalleryShareFixer(Set<Id> fileIds) {
    this.fileIds = fileIds;
  }

  public static void enqueue(Set<Id> fileIds) {
    if (fileIds == null || fileIds.isEmpty()) {
      return;
    }
    // A test that inserts a ContentVersion should not need to stop/start the
    // queue just to avoid an "uncommitted work pending" style failure.
    if (Test.isRunningTest()) {
      KenFilePublicLinkService.openUpToPortalUsers(fileIds);
      return;
    }
    System.enqueueJob(new KenGalleryShareFixer(new Set<Id>(fileIds)));
  }

  public void execute(QueueableContext context) {
    KenFilePublicLinkService.openUpToPortalUsers(fileIds);
  }
}