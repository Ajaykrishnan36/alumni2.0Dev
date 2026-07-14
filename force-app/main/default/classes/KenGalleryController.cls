public without sharing class KenGalleryController {
  @TestVisible
  private static Id testCurrentAccountId;

  // ── DTOs ──────────────────────────────────────────────────────────────────

  public class AlbumRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String coverImageUrl;
    @AuraEnabled
    public Integer photoCount;
    @AuraEnabled
    public Datetime lastUpdatedDate;
    @AuraEnabled
    public Id ownerId;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public String ownerImage;
    @AuraEnabled
    public Boolean isOwner;
    @AuraEnabled
    public String externalLink;
  }

  public class PhotoRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public Id albumId;
    @AuraEnabled
    public String imageUrl;
    @AuraEnabled
    public String thumbnailUrl;
    @AuraEnabled
    public Datetime uploadedDate;
    @AuraEnabled
    public String uploaderName;
    @AuraEnabled
    public String uploaderImage;
    @AuraEnabled
    public Boolean isImage;
    @AuraEnabled
    public String fileName;
  }

  // ── Albums ────────────────────────────────────────────────────────────────

  @AuraEnabled(cacheable=true)
  public static List<AlbumRow> getAlbums() {
    Id meUserId = UserInfo.getUserId();

    List<Ken_Photo_Album__c> albums = [
      SELECT Id, Name, Photo_Count__c, Last_Photo_Added_Date__c, OwnerId, External_Link__c, Cover_Photo__c, CreatedDate
      FROM Ken_Photo_Album__c
      ORDER BY Last_Photo_Added_Date__c DESC NULLS LAST, CreatedDate DESC
      LIMIT 500
    ];

    Set<Id> ownerIds = new Set<Id>();
    Set<Id> coverPhotoIds = new Set<Id>();
    for (Ken_Photo_Album__c a : albums) {
      ownerIds.add(a.OwnerId);
      if (a.Cover_Photo__c != null) {
        coverPhotoIds.add(a.Cover_Photo__c);
      }
    }

    Map<Id, User> ownerMap = new Map<Id, User>(
      [SELECT Id, Name, SmallPhotoUrl, AccountId, ContactId FROM User WHERE Id IN :ownerIds]
    );
    Map<Id, String> coverUrls = buildDownloadUrlsByLinkedEntity(coverPhotoIds);
    Map<Id, String> ownerProfileImages = lookupOwnerProfileImages(ownerMap.values());

    List<AlbumRow> rows = new List<AlbumRow>();
    for (Ken_Photo_Album__c a : albums) {
      AlbumRow r = new AlbumRow();
      r.id = a.Id;
      r.name = a.Name;
      r.photoCount = a.Photo_Count__c != null ? a.Photo_Count__c.intValue() : 0;
      r.lastUpdatedDate = a.Last_Photo_Added_Date__c != null ? a.Last_Photo_Added_Date__c : a.CreatedDate;
      r.ownerId = a.OwnerId;
      User owner = ownerMap.get(a.OwnerId);
      r.ownerName = owner != null ? owner.Name : null;
      String accountPhoto = ownerProfileImages.get(a.OwnerId);
      r.ownerImage = String.isNotBlank(accountPhoto) ? accountPhoto : (owner != null ? owner.SmallPhotoUrl : null);
      r.isOwner = (a.OwnerId == meUserId);
      r.externalLink = a.External_Link__c;
      if (a.Cover_Photo__c != null) {
        r.coverImageUrl = coverUrls.get(a.Cover_Photo__c);
      }
      rows.add(r);
    }
    return rows;
  }

  @AuraEnabled
  public static Id createAlbum(Map<String, Object> req) {
    if (req == null)
      throw new AuraHandledException('Request is required.');
    String name = getString(req, 'name');
    String externalLink = getString(req, 'externalLink');
    validateExternalLink(externalLink);

    if (String.isBlank(name)) {
      // A pasted Drive link with no typed name still needs a name to satisfy the
      // schema; the owner can rename it later via updateAlbumLink.
      if (String.isNotBlank(externalLink)) {
        name = 'Untitled Folder';
      } else {
        throw new AuraHandledException('Album name is required.');
      }
    }

    // Year__c and Privacy__c are required fields shared with KenGalleryV2Controller;
    // this feature doesn't use them, but they must be populated to satisfy the schema.
    Ken_Photo_Album__c album = new Ken_Photo_Album__c(
      Name = name,
      Year__c = String.valueOf(Date.today().year()),
      Privacy__c = 'Public',
      External_Link__c = externalLink
    );
    insert album;
    return album.Id;
  }

  @AuraEnabled
  public static void deleteAlbum(Id albumId) {
    if (albumId == null)
      throw new AuraHandledException('Album is required.');

    List<Ken_Photo_Album__c> existing = [
      SELECT Id, OwnerId FROM Ken_Photo_Album__c WHERE Id = :albumId LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Album not found.');
    if (existing[0].OwnerId != UserInfo.getUserId())
      throw new AuraHandledException('Access denied.');

    Set<Id> photoIds = new Map<Id, Ken_Photo__c>(
      [SELECT Id FROM Ken_Photo__c WHERE Album__c = :albumId]
    ).keySet();
    deleteUnderlyingFiles(photoIds);

    delete existing[0]; // cascades Ken_Photo__c children via Master-Detail
  }

  @AuraEnabled
  public static void updateAlbumLink(Id albumId, String externalLink, String name) {
    if (albumId == null)
      throw new AuraHandledException('Album is required.');
    validateExternalLink(externalLink);

    List<Ken_Photo_Album__c> existing = [
      SELECT Id, OwnerId FROM Ken_Photo_Album__c WHERE Id = :albumId LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Album not found.');
    if (existing[0].OwnerId != UserInfo.getUserId())
      throw new AuraHandledException('Access denied.');

    if (String.isNotBlank(name)) {
      existing[0].Name = name;
    }
    existing[0].External_Link__c = String.isNotBlank(externalLink) ? externalLink : null;
    update existing[0];
  }

  // ── Photos ────────────────────────────────────────────────────────────────

  @AuraEnabled(cacheable=true)
  public static List<PhotoRow> getAlbumPhotos(Id albumId) {
    if (albumId == null)
      return new List<PhotoRow>();

    List<Ken_Photo__c> photos = [
      SELECT Id, Album__c, Uploaded_By__c, CreatedDate
      FROM Ken_Photo__c
      WHERE Album__c = :albumId
      ORDER BY CreatedDate DESC
      LIMIT 500
    ];

    Set<Id> photoIds = new Set<Id>();
    Set<Id> uploaderIds = new Set<Id>();
    for (Ken_Photo__c p : photos) {
      photoIds.add(p.Id);
      if (p.Uploaded_By__c != null)
        uploaderIds.add(p.Uploaded_By__c);
    }

    Map<Id, ContentVersion> versionByPhoto = lookupLatestVersions(photoIds);
    Map<Id, String> uploaderNames = new Map<Id, String>();
    for (Account acc : [SELECT Id, Name FROM Account WHERE Id IN :uploaderIds]) {
      uploaderNames.put(acc.Id, acc.Name);
    }
    Map<Id, String> uploaderImages = KenGroupFeedService.lookupProfileImages(uploaderIds);

    List<PhotoRow> rows = new List<PhotoRow>();
    for (Ken_Photo__c p : photos) {
      PhotoRow r = new PhotoRow();
      r.id = p.Id;
      r.albumId = p.Album__c;
      r.uploadedDate = p.CreatedDate;
      ContentVersion cv = versionByPhoto.get(p.Id);
      if (cv != null) {
        r.imageUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
        r.thumbnailUrl = '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + cv.Id;
        r.fileName = cv.Title;
        r.isImage = isImageType(cv.FileType, cv.FileExtension);
      }
      r.uploaderName = uploaderNames.get(p.Uploaded_By__c);
      r.uploaderImage = uploaderImages.get(p.Uploaded_By__c);
      rows.add(r);
    }
    return rows;
  }

  @AuraEnabled
  public static void uploadPhotos(Id albumId, List<Map<String, Object>> photos) {
    if (albumId == null)
      throw new AuraHandledException('Album is required.');
    if (photos == null || photos.isEmpty())
      throw new AuraHandledException('At least one photo is required.');

    List<Ken_Photo_Album__c> albumList = [
      SELECT Id, OwnerId, Cover_Photo__c FROM Ken_Photo_Album__c WHERE Id = :albumId LIMIT 1
    ];
    if (albumList.isEmpty())
      throw new AuraHandledException('Album not found.');
    Ken_Photo_Album__c album = albumList[0];
    if (album.OwnerId != UserInfo.getUserId())
      throw new AuraHandledException('Access denied.');

    Id currentAccountId = getCurrentUserAccountId();

    // 1. Create a ContentVersion per photo.
    List<ContentVersion> versions = new List<ContentVersion>();
    for (Map<String, Object> photo : photos) {
      String base64 = getString(photo, 'base64');
      if (String.isBlank(base64))
        continue;
      String title = getString(photo, 'title');
      if (String.isBlank(title))
        title = 'Photo';
      ContentVersion cv = new ContentVersion();
      cv.Title = title;
      cv.PathOnClient = title;
      cv.VersionData = EncodingUtil.base64Decode(base64.substringAfter(','));
      versions.add(cv);
    }
    if (versions.isEmpty())
      throw new AuraHandledException('No valid photos to upload.');
    insert versions;

    Map<Id, ContentVersion> versionMap = new Map<Id, ContentVersion>(
      [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :versions]
    );

    // 2. Create the Ken_Photo__c record for each uploaded file.
    List<Ken_Photo__c> newPhotos = new List<Ken_Photo__c>();
    for (Integer i = 0; i < versions.size(); i++) {
      Ken_Photo__c p = new Ken_Photo__c();
      p.Album__c = albumId;
      p.Uploaded_By__c = currentAccountId;
      newPhotos.add(p);
    }
    insert newPhotos;

    // 3. Link the uploaded files to their Ken_Photo__c records via ContentDocumentLink
    //    (the standard, sole source of truth for the record-to-file relationship).
    List<ContentDocumentLink> links = new List<ContentDocumentLink>();
    for (Integer i = 0; i < versions.size(); i++) {
      ContentVersion cv = versionMap.get(versions[i].Id);
      ContentDocumentLink link = new ContentDocumentLink();
      link.ContentDocumentId = cv.ContentDocumentId;
      link.LinkedEntityId = newPhotos[i].Id;
      link.ShareType = 'V';
      link.Visibility = 'AllUsers';
      links.add(link);
    }
    insert links;

    // 4. Bump the album's "last updated" timestamp; default a cover photo if none set yet.
    album.Last_Photo_Added_Date__c = Datetime.now();
    if (album.Cover_Photo__c == null) {
      album.Cover_Photo__c = newPhotos[0].Id;
    }
    update album;
  }

  @AuraEnabled
  public static void deletePhoto(Id photoId) {
    if (photoId == null)
      throw new AuraHandledException('Photo is required.');

    List<Ken_Photo__c> existing = [
      SELECT Id, Album__r.OwnerId
      FROM Ken_Photo__c
      WHERE Id = :photoId
      LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Photo not found.');
    if (existing[0].Album__r.OwnerId != UserInfo.getUserId())
      throw new AuraHandledException('Access denied.');

    deleteUnderlyingFiles(new Set<Id>{ photoId });
    delete existing[0];
  }

  // ── Internal helpers ─────────────────────────────────────────────────────

  private static void deleteUnderlyingFiles(Set<Id> photoIds) {
    if (photoIds.isEmpty())
      return;
    Set<Id> documentIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :photoIds
    ]) {
      documentIds.add(link.ContentDocumentId);
    }
    if (!documentIds.isEmpty()) {
      delete [SELECT Id FROM ContentDocument WHERE Id IN :documentIds];
    }
  }

  // Album ownership is standard User-based (OwnerId), but alumni's real profile photos
  // live on their Person Account (via Ken_Alumni_CRM__c / Account.PhotoUrl), not on the
  // User record. Resolve each owning User to their Account and reuse the same lookup
  // already used for photo uploader avatars in getAlbumPhotos().
  private static Map<Id, String> lookupOwnerProfileImages(List<User> owners) {
    Map<Id, Id> userIdToAccountId = new Map<Id, Id>();
    Set<Id> accountIds = new Set<Id>();
    Set<Id> contactIds = new Set<Id>();
    for (User u : owners) {
      if (u.AccountId != null) {
        userIdToAccountId.put(u.Id, u.AccountId);
        accountIds.add(u.AccountId);
      } else if (u.ContactId != null) {
        contactIds.add(u.ContactId);
      }
    }
    if (!contactIds.isEmpty()) {
      for (Contact c : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds AND AccountId != null]) {
        for (User u : owners) {
          if (u.ContactId == c.Id) {
            userIdToAccountId.put(u.Id, c.AccountId);
            accountIds.add(c.AccountId);
          }
        }
      }
    }

    Map<Id, String> accountPhotos = KenGroupFeedService.lookupProfileImages(accountIds);
    Map<Id, String> out = new Map<Id, String>();
    for (Id userId : userIdToAccountId.keySet()) {
      String photo = accountPhotos.get(userIdToAccountId.get(userId));
      if (String.isNotBlank(photo)) {
        out.put(userId, photo);
      }
    }
    return out;
  }

  // Resolves the latest ContentVersion for each record (Ken_Photo__c or Ken_Photo_Album__c
  // cover photo) linked via the standard ContentDocumentLink relationship.
  private static Map<Id, ContentVersion> lookupLatestVersions(Set<Id> linkedEntityIds) {
    Map<Id, ContentVersion> out = new Map<Id, ContentVersion>();
    if (linkedEntityIds.isEmpty())
      return out;

    Map<Id, Id> documentToEntity = new Map<Id, Id>();
    Set<Id> documentIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :linkedEntityIds
    ]) {
      documentToEntity.put(link.ContentDocumentId, link.LinkedEntityId);
      documentIds.add(link.ContentDocumentId);
    }
    if (documentIds.isEmpty())
      return out;

    for (ContentVersion cv : [
      SELECT Id, ContentDocumentId, Title, FileType, FileExtension
      FROM ContentVersion
      WHERE ContentDocumentId IN :documentIds AND IsLatest = true
    ]) {
      Id entityId = documentToEntity.get(cv.ContentDocumentId);
      if (entityId != null) {
        out.put(entityId, cv);
      }
    }
    return out;
  }

  private static Map<Id, String> buildDownloadUrlsByLinkedEntity(Set<Id> linkedEntityIds) {
    Map<Id, String> urls = new Map<Id, String>();
    Map<Id, ContentVersion> versionByEntity = lookupLatestVersions(linkedEntityIds);
    for (Id entityId : versionByEntity.keySet()) {
      urls.put(entityId, '/sfc/servlet.shepherd/version/download/' + versionByEntity.get(entityId).Id);
    }
    return urls;
  }

  private static Boolean isImageType(String fileType, String fileExtension) {
    if (String.isNotBlank(fileType)) {
      String f = fileType.toUpperCase();
      if (f == 'JPG' || f == 'JPEG' || f == 'PNG' || f == 'GIF' || f == 'WEBP' || f == 'BMP' || f == 'SVG')
        return true;
    }
    if (String.isNotBlank(fileExtension)) {
      String ex = fileExtension.toLowerCase();
      if (ex == 'jpg' || ex == 'jpeg' || ex == 'png' || ex == 'gif' || ex == 'webp' || ex == 'bmp' || ex == 'svg')
        return true;
    }
    return false;
  }

  private static void validateExternalLink(String externalLink) {
    if (String.isBlank(externalLink))
      return;
    if (!Pattern.matches('^https?://[^\\s]+$', externalLink)) {
      throw new AuraHandledException('Please enter a valid link starting with http:// or https://.');
    }
  }

  private static String getString(Map<String, Object> m, String key) {
    if (m == null || String.isBlank(key) || !m.containsKey(key) || m.get(key) == null)
      return null;
    return String.valueOf(m.get(key));
  }

  private static Id getCurrentUserAccountId() {
    if (Test.isRunningTest() && testCurrentAccountId != null)
      return testCurrentAccountId;
    List<User> users = [
      SELECT Id, AccountId, ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (users.isEmpty())
      return null;
    User u = users[0];
    if (u.AccountId != null)
      return u.AccountId;
    if (u.ContactId != null) {
      List<Contact> contacts = [
        SELECT AccountId FROM Contact WHERE Id = :u.ContactId LIMIT 1
      ];
      if (!contacts.isEmpty() && contacts[0].AccountId != null)
        return contacts[0].AccountId;
    }
    return null;
  }
}