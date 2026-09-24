/**
 * @description Gives a public link to files attached to a Ken_File__c through
 *              the standard Salesforce UI. Those uploads never reach
 *              KenGalleryController, so without this the Public URL field on the
 *              record's Details page would stay blank for everything an admin
 *              uploaded from Setup.
 *
 *              FirstPublishLocationId is the record the file was uploaded
 *              against and is the only link available at this point - the
 *              ContentDocumentLink does not exist yet when this fires, and
 *              ContentDocumentLink does not support triggers at all.
 */
public without sharing class KenContentVersionTriggerHandler extends KenTriggerHandler {
  /**
   * This runs for every file uploaded anywhere in the org, so it must stay
   * cheap: the loop below touches no SOQL and exits immediately unless a
   * gallery file is actually involved.
   */
  public override void processAfterInsert() {
    Map<Id, ContentVersion> versionByFileId = new Map<Id, ContentVersion>();
    for (ContentVersion cv : (List<ContentVersion>) Trigger.new) {
      Id parentId = cv.FirstPublishLocationId;
      if (parentId == null) {
        continue;
      }
      if (parentId.getSobjectType() != Ken_File__c.SObjectType) {
        continue;
      }
      versionByFileId.put(parentId, cv);
    }
    if (versionByFileId.isEmpty()) {
      return;
    }
    stampIsImage(versionByFileId);
    KenFilePublicLinkService.publish(versionByFileId);
    // The share row the platform creates for a Setup upload is internal-only,
    // which makes the image unreadable in the portal. In practice the link does
    // exist by now, so this succeeds inline; the async retry only covers the
    // case where the platform has not written it yet.
    Integer linksFound = KenFilePublicLinkService.openUpToPortalUsers(
      versionByFileId.keySet()
    );
    if (linksFound == 0 && !System.isQueueable() && !System.isFuture()) {
      KenGalleryShareFixer.enqueue(versionByFileId.keySet());
    }
  }

  /**
   * Records whether the attached file is really an image, from the file itself.
   *
   * This is what makes a Setup upload publishable. The record Name is typed by
   * hand here, so it routinely carries no extension - a file named "vgh" holding
   * a JPEG is normal - and the landing page now drops anything it cannot confirm
   * is an image. Judging by name would silently hide such a newsletter.
   */
  private void stampIsImage(Map<Id, ContentVersion> versionByFileId) {
    // FileType and FileExtension are derived by the platform, so they are read
    // back from the saved rows rather than trusted from Trigger.new.
    Map<Id, ContentVersion> saved = new Map<Id, ContentVersion>(
      [
        SELECT Id, FileType, FileExtension
        FROM ContentVersion
        WHERE Id IN :versionByFileId.values()
        WITH SYSTEM_MODE
      ]
    );

    List<Ken_File__c> updates = new List<Ken_File__c>();
    for (Id fileId : versionByFileId.keySet()) {
      ContentVersion cv = saved.get(versionByFileId.get(fileId).Id);
      if (cv == null) {
        continue;
      }
      updates.add(
        new Ken_File__c(
          Id = fileId,
          Is_Image__c = KenGalleryController.isImageType(cv.FileType, cv.FileExtension)
        )
      );
    }
    if (updates.isEmpty()) {
      return;
    }
    try {
      Database.update(updates, true, AccessLevel.SYSTEM_MODE);
    } catch (Exception e) {
      // Leave the flag alone rather than failing the upload. The file still
      // uploads; it just will not publish to the landing page until corrected.
    }
  }
}