public without sharing class KenGalleryController {
  @TestVisible
  private static Id testCurrentAccountId;

  /**
   * Lets a test exercise the portal side of the upload guard. Every test user is
   * built on an internal profile, so without this the community denial path is
   * unreachable from Apex tests.
   */
  @TestVisible
  private static Boolean testIsInternalCurator;

  /**
   * The album whose files are published publicly. Matched by name (SOQL text
   * comparison is case-insensitive) rather than a flag field, per the original
   * newsletter-banner decision; KenLandingPageController matches the same way.
   */
  @TestVisible
  private static final Set<String> NEWSLETTER_ALBUM_NAMES = new Set<String>{
    'Newsletter',
    'Newsletters'
  };

  public class AlbumRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    /** Thumbnail of the album's most recent upload. Null for an empty album, in
     *  which case the card shows the static placeholder instead. */
    @AuraEnabled
    public String coverImageUrl;
    /** False when the newest upload is a document. The card needs to tell that
     *  apart from an empty album: a PDF cover cannot render in an <img>, and
     *  falling back to the empty-album art made a full album read "No files yet". */
    @AuraEnabled
    public Boolean coverIsImage;
    @AuraEnabled
    public String coverFileName;
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
    /** Absolute ContentDistribution link. Preferred over imageUrl because the
     *  shepherd URLs below are root-relative, and inside an Experience Cloud site
     *  they resolve past the site path and come back as a broken image. */
    @AuraEnabled
    public String publicUrl;
  }

  public class AlbumResolveResult {
    @AuraEnabled
    public AlbumRow album;
    @AuraEnabled
    public Id photoId;
  }

  public class NewsletterBanner {
    @AuraEnabled
    public Id albumId;
    @AuraEnabled
    public String albumName;
    @AuraEnabled
    public Id photoId;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public Datetime photoDate;
    @AuraEnabled
    public String previewUrl;
    @AuraEnabled
    public String fileType;
  }

  @AuraEnabled(cacheable=true)
  public static List<AlbumRow> getAlbums() {
    List<Ken_Album__c> albums = [
      SELECT Id, Name, File_Count__c, Last_File_Added_Date__c, OwnerId, External_Link__c, CreatedDate
      FROM Ken_Album__c
      WITH SECURITY_ENFORCED
      ORDER BY Last_File_Added_Date__c DESC NULLS LAST, CreatedDate DESC
      LIMIT 500
    ];
    return buildAlbumRows(albums);
  }

  /**
   * Resolves the album for a gallery deep link. Accepts either a
   * Ken_Album__c Id or a Ken_File__c Id; when a photo Id is passed the
   * parent album is returned along with the photoId so the caller can open
   * that photo directly.
   */
  @AuraEnabled(cacheable=true)
  public static AlbumResolveResult getAlbumForRecord(Id recordId) {
    if (recordId == null)
      throw new AuraHandledException('Record is required.');

    AlbumResolveResult result = new AlbumResolveResult();
    Id albumId = recordId;
    if (recordId.getSobjectType() == Ken_File__c.SObjectType) {
      List<Ken_File__c> photos = [
        SELECT Album__c FROM Ken_File__c WHERE Id = :recordId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (photos.isEmpty())
        throw new AuraHandledException('Photo not found.');
      albumId = photos[0].Album__c;
      result.photoId = recordId;
    } else if (recordId.getSobjectType() != Ken_Album__c.SObjectType) {
      throw new AuraHandledException('Unsupported record.');
    }

    List<Ken_Album__c> albums = [
      SELECT Id, Name, File_Count__c, Last_File_Added_Date__c, OwnerId, External_Link__c, CreatedDate
      FROM Ken_Album__c
      WHERE Id = :albumId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (albums.isEmpty())
      throw new AuraHandledException('Album not found.');
    result.album = buildAlbumRows(albums)[0];
    return result;
  }

  private static List<AlbumRow> buildAlbumRows(List<Ken_Album__c> albums) {
    Id meUserId = UserInfo.getUserId();

    Set<Id> ownerIds = new Set<Id>();
    Set<Id> albumIds = new Set<Id>();
    for (Ken_Album__c a : albums) {
      ownerIds.add(a.OwnerId);
      albumIds.add(a.Id);
    }

    Map<Id, User> ownerMap = new Map<Id, User>(
      [SELECT Id, Name, SmallPhotoUrl, AccountId, ContactId FROM User WHERE Id IN :ownerIds WITH SYSTEM_MODE]
    );
    Map<Id, String> ownerProfileImages = lookupOwnerProfileImages(ownerMap.values());
    Map<Id, AlbumCover> covers = lookupAlbumCovers(albumIds);

    List<AlbumRow> rows = new List<AlbumRow>();
    for (Ken_Album__c a : albums) {
      AlbumRow r = new AlbumRow();
      r.id = a.Id;
      r.name = a.Name;
      r.photoCount = a.File_Count__c != null ? a.File_Count__c.intValue() : 0;
      r.lastUpdatedDate = a.Last_File_Added_Date__c != null ? a.Last_File_Added_Date__c : a.CreatedDate;
      r.ownerId = a.OwnerId;
      User owner = ownerMap.get(a.OwnerId);
      r.ownerName = owner != null ? owner.Name : null;
      String accountPhoto = ownerProfileImages.get(a.OwnerId);
      r.ownerImage = String.isNotBlank(accountPhoto) ? accountPhoto : (owner != null ? owner.SmallPhotoUrl : null);
      r.isOwner = (a.OwnerId == meUserId);
      r.externalLink = a.External_Link__c;
      AlbumCover cover = covers.get(a.Id);
      r.coverImageUrl = cover != null ? cover.url : null;
      r.coverIsImage = cover != null && cover.isImage == true;
      r.coverFileName = cover != null ? cover.fileName : null;
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
      if (String.isNotBlank(externalLink)) {
        name = 'Untitled Folder';
      } else {
        throw new AuraHandledException('Album name is required.');
      }
    }

    Ken_Album__c album = new Ken_Album__c(
      Name = name,
      External_Link__c = externalLink
    );
    if (!Schema.sObjectType.Ken_Album__c.isCreateable()) {
      throw new KenCrudException('Ken_Album__c is not createable by the current user.');
    }
    insert album;
    return album.Id;
  }

  @AuraEnabled
  public static void deleteAlbum(Id albumId) {
    if (albumId == null)
      throw new AuraHandledException('Album is required.');

    List<Ken_Album__c> existing = [
      SELECT Id, OwnerId FROM Ken_Album__c WHERE Id = :albumId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Album not found.');
    if (existing[0].OwnerId != UserInfo.getUserId())
      throw new AuraHandledException('Access denied.');

    Set<Id> photoIds = new Map<Id, Ken_File__c>(
      [SELECT Id FROM Ken_File__c WHERE Album__c = :albumId WITH SECURITY_ENFORCED]
    ).keySet();
    deleteUnderlyingFiles(photoIds);

    delete existing[0];
  }

  @AuraEnabled
  public static void updateAlbumLink(Id albumId, String externalLink, String name) {
    if (albumId == null)
      throw new AuraHandledException('Album is required.');
    validateExternalLink(externalLink);

    List<Ken_Album__c> existing = [
      SELECT Id, OwnerId FROM Ken_Album__c WHERE Id = :albumId
      WITH SECURITY_ENFORCED
      LIMIT 1
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

  @AuraEnabled(cacheable=true)
  public static List<PhotoRow> getAlbumPhotos(Id albumId) {
    if (albumId == null)
      return new List<PhotoRow>();

    List<Ken_File__c> photos = [
      SELECT Id, Album__c, Uploaded_By__c, CreatedDate, Share_URL__c
      FROM Ken_File__c
      WHERE Album__c = :albumId
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT 500
    ];

    Set<Id> photoIds = new Set<Id>();
    Set<Id> uploaderIds = new Set<Id>();
    for (Ken_File__c p : photos) {
      photoIds.add(p.Id);
      if (p.Uploaded_By__c != null)
        uploaderIds.add(p.Uploaded_By__c);
    }

    Map<Id, ContentVersion> versionByPhoto = lookupLatestVersions(photoIds);
    Map<Id, String> uploaderNames = new Map<Id, String>();
    for (Account acc : [SELECT Id, Name FROM Account WHERE Id IN :uploaderIds WITH SECURITY_ENFORCED]) {
      uploaderNames.put(acc.Id, acc.Name);
    }
    Map<Id, String> uploaderImages = KenGroupFeedService.lookupProfileImages(uploaderIds);

    List<PhotoRow> rows = new List<PhotoRow>();
    for (Ken_File__c p : photos) {
      PhotoRow r = new PhotoRow();
      r.id = p.Id;
      r.albumId = p.Album__c;
      r.uploadedDate = p.CreatedDate;
      r.publicUrl = p.Share_URL__c;
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

  /**
   * Homepage "Newsletter" banner: looks up an album matched by exact name
   * ("Newsletter"/"Newsletters") and returns its most recently added photo, or
   * null when no such album exists so the LWC can fall back to its static
   * default banner copy.
   */
  @AuraEnabled(cacheable=true)
  public static NewsletterBanner getNewsletterBanner() {
    List<Ken_Album__c> albums = [
      SELECT Id, Name
      FROM Ken_Album__c
      WHERE Name IN :NEWSLETTER_ALBUM_NAMES
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate ASC
      LIMIT 1
    ];
    if (albums.isEmpty())
      return null;

    Ken_Album__c album = albums[0];
    List<Ken_File__c> latestPhotos = [
      SELECT Id, CreatedDate
      FROM Ken_File__c
      WHERE Album__c = :album.Id
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (latestPhotos.isEmpty())
      return null;

    Ken_File__c latestPhoto = latestPhotos[0];
    Map<Id, ContentVersion> versionByPhoto = lookupLatestVersions(new Set<Id>{ latestPhoto.Id });
    ContentVersion cv = versionByPhoto.get(latestPhoto.Id);

    NewsletterBanner banner = new NewsletterBanner();
    banner.albumId = album.Id;
    banner.albumName = album.Name;
    banner.photoId = latestPhoto.Id;
    banner.photoDate = latestPhoto.CreatedDate;
    if (cv != null) {
      banner.fileName = cv.Title;
      banner.previewUrl = '/sfc/servlet.shepherd/version/download/' + cv.Id;
      banner.fileType = cv.FileType;
    }
    return banner;
  }

  @AuraEnabled
  public static void uploadPhotos(Id albumId, List<Map<String, Object>> photos) {
    if (albumId == null)
      throw new AuraHandledException('Album is required.');
    if (photos == null || photos.isEmpty())
      throw new AuraHandledException('At least one photo is required.');

    List<Ken_Album__c> albumList = [
      SELECT Id, Name, OwnerId
      FROM Ken_Album__c
      WHERE Id = :albumId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (albumList.isEmpty())
      throw new AuraHandledException('Album not found.');
    Ken_Album__c album = albumList[0];
    if (album.OwnerId != UserInfo.getUserId() && !isInternalCurator())
      throw new AuraHandledException('Access denied.');

    Id currentAccountId = getCurrentUserAccountId();

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
    Database.insert(versions, true, AccessLevel.SYSTEM_MODE);

    Map<Id, ContentVersion> versionMap = new Map<Id, ContentVersion>(
      [
        SELECT Id, ContentDocumentId, FileType, FileExtension
        FROM ContentVersion
        WHERE Id IN :versions
      WITH SYSTEM_MODE
      ]
    );

    List<Ken_File__c> newPhotos = new List<Ken_File__c>();
    for (Integer i = 0; i < versions.size(); i++) {
      Ken_File__c p = new Ken_File__c();
      p.Album__c = albumId;
      p.Uploaded_By__c = currentAccountId;
      p.Name = truncateName(versions[i].Title);
      ContentVersion saved = versionMap.get(versions[i].Id);
      p.Is_Image__c = saved != null && isImageType(saved.FileType, saved.FileExtension);
      newPhotos.add(p);
    }
    if (!Schema.sObjectType.Ken_File__c.isCreateable()) {
        throw new KenCrudException('Ken_File__c is not createable by the current user.');
    }
    insert newPhotos;

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
    Database.insert(links, true, AccessLevel.SYSTEM_MODE);

    Map<Id, ContentVersion> versionByFileId = new Map<Id, ContentVersion>();
    for (Integer i = 0; i < newPhotos.size(); i++) {
      versionByFileId.put(newPhotos[i].Id, versions[i]);
    }
    publishPublicLinks(versionByFileId);
  }

  /**
   * @description Stores the anonymously reachable download link for a gallery file
   *              on Ken_File__c.Share_URL__c.
   *
   *              The link itself is minted by
   *              KenCreateContentVersion.createDistributions(), which is where
   *              every public link in the portal comes from - the settings that
   *              make one work (latest version, view in browser, no visit
   *              notifications) are defined there once. This method only decides
   *              WHICH files need one and writes the result back.
   *
   *              The landing page is the reason these exist: it is served to the
   *              site guest user, which cannot read ContentVersion at all, so a
   *              shepherd URL renders as a broken image for an anonymous visitor.
   *
   *              A file that already carries a link keeps it, so re-uploading
   *              against the same record cannot pile up duplicate
   *              ContentDistribution rows.
   *
   *              Best-effort by design. If public links are disabled in the org
   *              the upload itself must still succeed, so a failure here leaves
   *              Share_URL__c blank rather than rolling the transaction back.
   *
   * @param versionByFileId the uploaded ContentVersion keyed by the Ken_File__c it
   *        belongs to. Both must already be inserted - ContentDistribution needs a
   *        real ContentVersion Id.
   */
  private static void publishPublicLinks(Map<Id, ContentVersion> versionByFileId) {
    if (versionByFileId == null || versionByFileId.isEmpty()) {
      return;
    }

    try {
      List<Id> pending = new List<Id>();
      for (Ken_File__c f : [
        SELECT Id, Share_URL__c
        FROM Ken_File__c
        WHERE Id IN :versionByFileId.keySet()
      WITH SECURITY_ENFORCED
      ]) {
        if (String.isBlank(f.Share_URL__c)) {
          pending.add(f.Id);
        }
      }
      if (pending.isEmpty()) {
        return;
      }

      Set<Id> versionIds = new Set<Id>();
      for (Id fileId : pending) {
        versionIds.add(versionByFileId.get(fileId).Id);
      }
      Map<Id, String> urlByVersionId = KenCreateContentVersion.createDistributions(versionIds);

      List<Ken_File__c> updates = new List<Ken_File__c>();
      for (Id fileId : pending) {
        String url = urlByVersionId.get(versionByFileId.get(fileId).Id);
        if (String.isBlank(url)) {
          continue;
        }
        updates.add(new Ken_File__c(Id = fileId, Share_URL__c = url));
      }
      if (!updates.isEmpty()) {
        if (!Schema.sObjectType.Ken_File__c.isUpdateable()) {
            throw new KenCrudException('Ken_File__c is not updateable by the current user.');
        }
        update updates;
      }
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'KenGalleryController.publishPublicLinks failed: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Whether the running user is internal staff rather than a portal
   *              member, which is what lets an admin upload into an album they do
   *              not own - curating the Newsletter album is exactly that case.
   *
   *              A portal user is still held to owning the album, so community
   *              behaviour is unchanged. Experience Cloud licences report a
   *              UserType of CspLitePortal / CustomerSuccess / PowerPartner and
   *              similar; only internal licences report Standard.
   */
  private static Boolean isInternalCurator() {
    if (Test.isRunningTest() && testIsInternalCurator != null) {
      return testIsInternalCurator;
    }
    return UserInfo.getUserType() == 'Standard';
  }

  /**
   * Ken_File__c.Name is an 80-character text field, but file titles are not
   * capped.
   */
  private static String truncateName(String value) {
    if (String.isBlank(value)) {
      return 'Photo';
    }
    return value.length() > 80 ? value.substring(0, 80) : value;
  }

  @AuraEnabled
  public static void deletePhoto(Id photoId) {
    if (photoId == null)
      throw new AuraHandledException('Photo is required.');

    List<Ken_File__c> existing = [
      SELECT Id, Album__r.OwnerId
      FROM Ken_File__c
      WHERE Id = :photoId
      WITH SECURITY_ENFORCED
      LIMIT 1
    ];
    if (existing.isEmpty())
      throw new AuraHandledException('Photo not found.');
    if (existing[0].Album__r.OwnerId != UserInfo.getUserId())
      throw new AuraHandledException('Access denied.');

    deleteUnderlyingFiles(new Set<Id>{ photoId });
    delete existing[0];
  }

  private static void deleteUnderlyingFiles(Set<Id> photoIds) {
    if (photoIds.isEmpty())
      return;
    Set<Id> documentIds = new Set<Id>();
    for (ContentDocumentLink link : [
      SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :photoIds
    WITH SYSTEM_MODE
    ]) {
      documentIds.add(link.ContentDocumentId);
    }
    if (!documentIds.isEmpty()) {
      delete [SELECT Id FROM ContentDocument WHERE Id IN :documentIds WITH SYSTEM_MODE];
    }
  }

  /**
   * Album ownership is standard User-based (OwnerId), but alumni profile photos
   * live on their Person Account, not the User record. Resolves each owning User
   * to their Account and reuses the uploader-avatar lookup.
   */
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
      for (Contact c : [SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds AND AccountId != null WITH SECURITY_ENFORCED]) {
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

  /**
   * Resolves the latest ContentVersion for each record linked via the standard
   * ContentDocumentLink relationship.
   */
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
    WITH SYSTEM_MODE
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
    WITH SYSTEM_MODE
    ]) {
      Id entityId = documentToEntity.get(cv.ContentDocumentId);
      if (entityId != null) {
        out.put(entityId, cv);
      }
    }
    return out;
  }

  /**
   * The album cover is derived from its files rather than stored, so it needs
   * no field of its own and refreshes on its own: whatever was uploaded last is
   * the cover, and deleting that file simply promotes the one before it.
   *
   * Reports whether that newest upload is actually an image as well as its URL,
   * because a document cover cannot be rendered in an <img>. An album with no
   * files at all is absent from the map, which is what lets the card tell
   * "nothing uploaded yet" apart from "newest upload is a PDF".
   */
  private class AlbumCover {
    private String url;
    private Boolean isImage;
    private String fileName;
  }

  private static Map<Id, AlbumCover> lookupAlbumCovers(Set<Id> albumIds) {
    Map<Id, AlbumCover> covers = new Map<Id, AlbumCover>();
    if (albumIds.isEmpty()) {
      return covers;
    }
    Map<Id, Id> latestFileByAlbum = new Map<Id, Id>();
    Map<Id, String> publicUrlByFile = new Map<Id, String>();
    for (Ken_File__c f : [
      SELECT Id, Album__c, Share_URL__c
      FROM Ken_File__c
      WHERE Album__c IN :albumIds
      WITH SECURITY_ENFORCED
      ORDER BY CreatedDate ASC
    ]) {
      latestFileByAlbum.put(f.Album__c, f.Id);
      publicUrlByFile.put(f.Id, f.Share_URL__c);
    }
    if (latestFileByAlbum.isEmpty()) {
      return covers;
    }

    Map<Id, ContentVersion> versionByFile = lookupLatestVersions(
      new Set<Id>(latestFileByAlbum.values())
    );
    for (Id albumId : latestFileByAlbum.keySet()) {
      Id fileId = latestFileByAlbum.get(albumId);
      ContentVersion cv = versionByFile.get(fileId);

      AlbumCover cover = new AlbumCover();
      cover.isImage = cv != null && isImageType(cv.FileType, cv.FileExtension);
      cover.fileName = cv != null ? cv.Title : null;

      String publicUrl = publicUrlByFile.get(fileId);
      if (String.isNotBlank(publicUrl)) {
        cover.url = publicUrl;
      } else if (cv != null) {
        cover.url =
          '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' +
          cv.Id;
      }
      covers.put(albumId, cover);
    }
    return covers;
  }

  private static Map<Id, String> buildDownloadUrlsByLinkedEntity(Set<Id> linkedEntityIds) {
    Map<Id, String> urls = new Map<Id, String>();
    Map<Id, ContentVersion> versionByEntity = lookupLatestVersions(linkedEntityIds);
    for (Id entityId : versionByEntity.keySet()) {
      urls.put(entityId, '/sfc/servlet.shepherd/version/download/' + versionByEntity.get(entityId).Id);
    }
    return urls;
  }

  /**
   * The single definition of "renderable image" for the gallery. Ken_File__c.Is_Image__c
   * is stamped from this on both upload paths, and the landing page DROPS non-image
   * newsletters rather than giving them a stock cover, so a second copy of this
   * list drifting apart would silently hide a newsletter.
   */
  public static Boolean isImageType(String fileType, String fileExtension) {
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
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (users.isEmpty())
      return null;
    User u = users[0];
    if (u.AccountId != null)
      return u.AccountId;
    if (u.ContactId != null) {
      List<Contact> contacts = [
        SELECT AccountId FROM Contact WHERE Id = :u.ContactId
        WITH SECURITY_ENFORCED
        LIMIT 1
      ];
      if (!contacts.isEmpty() && contacts[0].AccountId != null)
        return contacts[0].AccountId;
    }
    return null;
  }
}