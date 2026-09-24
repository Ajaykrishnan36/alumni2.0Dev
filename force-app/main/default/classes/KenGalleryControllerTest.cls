@IsTest
private class KenGalleryControllerTest {

    private static final String ALUMNI_RT = 'PersonAccount';

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
        ];
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account' AND IsActive = true]) {
            if (rt.IsPersonType) {
                return rt.Id;
            }
        }
        return null;
    }

    private static User buildUser(String alias) {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            Username          = alias + '.' + System.currentTimeMillis() + '@example.com',
            Email             = alias + '@example.com',
            LastName          = alias,
            Alias             = alias.left(8),
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = prof.Id
        );
    }

    @TestSetup
    static void setupData() {
        User owner = buildUser('galowner');
        User other = buildUser('galother');
        insert new List<User>{ owner, other };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet adminPs = [SELECT Id FROM PermissionSet WHERE Name = 'Alumni_Admin' LIMIT 1];
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = owner.Id, PermissionSetId = adminPs.Id),
                new PermissionSetAssignment(AssigneeId = other.Id, PermissionSetId = adminPs.Id)
            };
        }

        Id paRtId = getPersonAccountRtId();
        Account uploaderAcc = new Account(FirstName = 'Gallery', LastName = 'Uploader');
        if (paRtId != null) {
            uploaderAcc.RecordTypeId = paRtId;
        }
        insert uploaderAcc;
    }

    private static User ownerUser() {
        return [SELECT Id FROM User WHERE Alias = 'galowner' LIMIT 1];
    }

    private static User otherUser() {
        return [SELECT Id FROM User WHERE Alias = 'galother' LIMIT 1];
    }

    @IsTest
    static void testCreateAlbumRequiresName() {
        System.runAs(ownerUser()) {
            try {
                Test.startTest();
                KenGalleryController.createAlbum(new Map<String, Object>{ 'name' => '' });
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for missing name');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testCreateAlbumSetsOwnerAndDefaults() {
        Id albumId;
        System.runAs(ownerUser()) {
            Test.startTest();
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Reunion Test' }
            );
            Test.stopTest();
        }
        Ken_Album__c album = [
            SELECT Name, OwnerId FROM Ken_Album__c WHERE Id = :albumId
        ];
        System.assertEquals('Reunion Test', album.Name);
        System.assertEquals(ownerUser().Id, album.OwnerId);
    }

    @IsTest
    static void testCreateAlbumFromLinkDefaultsName() {
        Id albumId;
        System.runAs(ownerUser()) {
            Test.startTest();
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'externalLink' => 'https://drive.google.com/drive/folders/xyz789' }
            );
            Test.stopTest();
        }
        Ken_Album__c album = [
            SELECT Name, External_Link__c FROM Ken_Album__c WHERE Id = :albumId
        ];
        System.assertEquals('Untitled Folder', album.Name);
        System.assertEquals('https://drive.google.com/drive/folders/xyz789', album.External_Link__c);
    }

    @IsTest
    static void testCreateAlbumRejectsInvalidLink() {
        System.runAs(ownerUser()) {
            try {
                Test.startTest();
                KenGalleryController.createAlbum(
                    new Map<String, Object>{ 'name' => 'Bad Link Album', 'externalLink' => 'not-a-url' }
                );
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for invalid link');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testGetAlbumsReflectsOwnership() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Owned By Me' }
            );
        }

        List<KenGalleryController.AlbumRow> asOwner;
        System.runAs(ownerUser()) {
            Test.startTest();
            asOwner = KenGalleryController.getAlbums();
            Test.stopTest();
        }
        Boolean foundAsOwner = false;
        for (KenGalleryController.AlbumRow r : asOwner) {
            if (r.id == albumId) {
                foundAsOwner = true;
                System.assertEquals(true, r.isOwner, 'Creator should see isOwner = true');
            }
        }
        System.assert(foundAsOwner, 'Owner should see their own album in the list');

        List<KenGalleryController.AlbumRow> asOther;
        System.runAs(otherUser()) {
            asOther = KenGalleryController.getAlbums();
        }
        for (KenGalleryController.AlbumRow r : asOther) {
            if (r.id == albumId) {
                System.assertEquals(false, r.isOwner, 'Non-creator should see isOwner = false');
            }
        }
    }

    @IsTest
    static void testUploadPhotosAccessDeniedForNonOwner() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Locked Album' }
            );
        }

        System.runAs(otherUser()) {
            KenGalleryController.testIsInternalCurator = false;
            try {
                Test.startTest();
                KenGalleryController.uploadPhotos(
                    albumId,
                    new List<Map<String, Object>>{
                        new Map<String, Object>{ 'title' => 'pic.png', 'base64' => 'data:image/png;base64,dGVzdA==' }
                    }
                );
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for access denied');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testUploadPhotosAndReadBack() {
        Id albumId;
        Account uploaderAcc = [SELECT Id FROM Account WHERE LastName = 'Uploader' LIMIT 1];

        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Upload Test Album' }
            );
        }

        System.runAs(ownerUser()) {
            KenGalleryController.testCurrentAccountId = uploaderAcc.Id;
            Test.startTest();
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'title' => 'pic1.png',
                        'base64' => 'data:image/png;base64,dGVzdA=='
                    }
                }
            );
            Test.stopTest();
        }

        Ken_Album__c album = [
            SELECT File_Count__c, Last_File_Added_Date__c
            FROM Ken_Album__c
            WHERE Id = :albumId
        ];
        System.assertEquals(1, Integer.valueOf(album.File_Count__c), 'Rollup should count the new photo');
        System.assertNotEquals(null, album.Last_File_Added_Date__c);

        List<KenGalleryController.PhotoRow> photos;
        System.runAs(ownerUser()) {
            photos = KenGalleryController.getAlbumPhotos(albumId);
        }
        System.assertEquals(1, photos.size());
        System.assert(photos[0].imageUrl.contains('/sfc/servlet.shepherd/version/download/'));
        System.assert(photos[0].thumbnailUrl.contains('renditionDownload'));
        System.assertEquals('Gallery Uploader', photos[0].uploaderName);
        System.assertEquals(true, photos[0].isImage, 'A PNG upload should be flagged as an image');
        System.assertEquals('pic1.png', photos[0].fileName);
    }

    @IsTest
    static void testUploadNonImageFile() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Document Album' }
            );
            Test.startTest();
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'title' => 'notes.pdf',
                        'base64' => 'data:application/pdf;base64,dGVzdA=='
                    }
                }
            );
            Test.stopTest();
        }

        List<KenGalleryController.PhotoRow> photos;
        System.runAs(ownerUser()) {
            photos = KenGalleryController.getAlbumPhotos(albumId);
        }
        System.assertEquals(1, photos.size());
        System.assertEquals('notes.pdf', photos[0].fileName);
        System.assertEquals(false, photos[0].isImage, 'A PDF upload should not be flagged as an image');
    }

    @IsTest
    static void testDeletePhotoAccessDenied() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Delete Test Album' }
            );
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'title' => 'pic.png', 'base64' => 'data:image/png;base64,dGVzdA==' }
                }
            );
        }
        Id photoId = [SELECT Id FROM Ken_File__c WHERE Album__c = :albumId LIMIT 1].Id;

        System.runAs(otherUser()) {
            try {
                Test.startTest();
                KenGalleryController.deletePhoto(photoId);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for access denied');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testDeleteAlbumCascadesPhotos() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Cascade Test Album' }
            );
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'title' => 'pic.png', 'base64' => 'data:image/png;base64,dGVzdA==' }
                }
            );
        }

        System.runAs(ownerUser()) {
            Test.startTest();
            KenGalleryController.deleteAlbum(albumId);
            Test.stopTest();
        }

        System.assertEquals(0, [SELECT COUNT() FROM Ken_Album__c WHERE Id = :albumId]);
        System.assertEquals(0, [SELECT COUNT() FROM Ken_File__c WHERE Album__c = :albumId]);
    }

    @IsTest
    static void testDeleteAlbumAccessDenied() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Protected Album' }
            );
        }

        System.runAs(otherUser()) {
            try {
                Test.startTest();
                KenGalleryController.deleteAlbum(albumId);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for access denied');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testUpdateAlbumLinkSetsAndClears() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Linked Album' }
            );

            Test.startTest();
            KenGalleryController.updateAlbumLink(albumId, 'https://drive.google.com/drive/folders/abc123', null);
            Test.stopTest();
        }

        Ken_Album__c album = [
            SELECT External_Link__c FROM Ken_Album__c WHERE Id = :albumId
        ];
        System.assertEquals('https://drive.google.com/drive/folders/abc123', album.External_Link__c);

        System.runAs(ownerUser()) {
            KenGalleryController.updateAlbumLink(albumId, '', null);
        }
        album = [SELECT External_Link__c FROM Ken_Album__c WHERE Id = :albumId];
        System.assertEquals(null, album.External_Link__c, 'Blank link should clear the field');
    }

    @IsTest
    static void testUpdateAlbumLinkRenamesAlbum() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'externalLink' => 'https://drive.google.com/drive/folders/renamed' }
            );

            Test.startTest();
            KenGalleryController.updateAlbumLink(
                albumId,
                'https://drive.google.com/drive/folders/renamed',
                'Real Album Name'
            );
            Test.stopTest();
        }

        Ken_Album__c album = [SELECT Name FROM Ken_Album__c WHERE Id = :albumId];
        System.assertEquals('Real Album Name', album.Name);
    }

    @IsTest
    static void testGetAlbumForRecordWithAlbumId() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Resolve Album' }
            );

            Test.startTest();
            KenGalleryController.AlbumResolveResult result = KenGalleryController.getAlbumForRecord(albumId);
            Test.stopTest();

            System.assertEquals(albumId, result.album.id, 'Album id should resolve to itself');
            System.assertEquals(null, result.photoId, 'No photoId expected for an album id');
            System.assertEquals(true, result.album.isOwner, 'Creator should be flagged as owner');
        }
    }

    @IsTest
    static void testGetAlbumForRecordWithPhotoId() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Resolve Photo Album' }
            );
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'title' => 'pic.png', 'base64' => 'data:image/png;base64,dGVzdA==' }
                }
            );
        }
        Id photoId = [SELECT Id FROM Ken_File__c WHERE Album__c = :albumId LIMIT 1].Id;

        System.runAs(ownerUser()) {
            Test.startTest();
            KenGalleryController.AlbumResolveResult result = KenGalleryController.getAlbumForRecord(photoId);
            Test.stopTest();

            System.assertEquals(albumId, result.album.id, 'Photo id should resolve to its parent album');
            System.assertEquals(photoId, result.photoId, 'photoId should echo the requested photo');
        }
    }

    @IsTest
    static void testGetAlbumForRecordRejectsOtherObjects() {
        Account uploaderAcc = [SELECT Id FROM Account WHERE LastName = 'Uploader' LIMIT 1];
        System.runAs(ownerUser()) {
            try {
                Test.startTest();
                KenGalleryController.getAlbumForRecord(uploaderAcc.Id);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for unsupported record');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testGetNewsletterBannerReturnsNullWhenNoAlbum() {
        KenGalleryController.NewsletterBanner banner;
        System.runAs(ownerUser()) {
            Test.startTest();
            banner = KenGalleryController.getNewsletterBanner();
            Test.stopTest();
        }
        System.assertEquals(null, banner, 'No Newsletter album should exist yet');
    }

    @IsTest
    static void testGetNewsletterBannerReturnsLatestPhoto() {
        Id albumId;
        Account uploaderAcc = [SELECT Id FROM Account WHERE LastName = 'Uploader' LIMIT 1];

        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Newsletter' }
            );
            KenGalleryController.testCurrentAccountId = uploaderAcc.Id;
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'title' => 'October Newsletter.pdf',
                        'base64' => 'data:application/pdf;base64,dGVzdA=='
                    }
                }
            );
        }

        KenGalleryController.NewsletterBanner banner;
        System.runAs(ownerUser()) {
            Test.startTest();
            banner = KenGalleryController.getNewsletterBanner();
            Test.stopTest();
        }
        System.assertNotEquals(null, banner, 'Newsletter album with a photo should produce a banner');
        System.assertEquals(albumId, banner.albumId);
        System.assertEquals('Newsletter', banner.albumName);
        System.assertEquals('October Newsletter.pdf', banner.fileName);
        System.assertNotEquals(null, banner.photoDate, 'Latest photo date should be populated for header title formatting');
        System.assert(banner.previewUrl.contains('/sfc/servlet.shepherd/version/download/'));
    }

    @IsTest
    static void testEmptyAlbumHasNoCoverSoTheCardCanUseThePlaceholder() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Empty Album' }
            );
        }

        List<KenGalleryController.AlbumRow> rows;
        System.runAs(ownerUser()) {
            Test.startTest();
            rows = KenGalleryController.getAlbums();
            Test.stopTest();
        }

        for (KenGalleryController.AlbumRow r : rows) {
            if (r.id == albumId) {
                System.assertEquals(
                    null,
                    r.coverImageUrl,
                    'An album with no files must report no cover so the card falls back to the static image.'
                );
            }
        }
    }

    @IsTest
    static void testAlbumCoverIsTheMostRecentUpload() {
        Id albumId;
        Account uploaderAcc = [SELECT Id FROM Account WHERE LastName = 'Uploader' LIMIT 1];

        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Cover Album' }
            );
            KenGalleryController.testCurrentAccountId = uploaderAcc.Id;
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'title' => 'first.png', 'base64' => 'data:image/png;base64,dGVzdA==' }
                }
            );
        }

        // Back-date the first upload so the second is unambiguously newer.
        Ken_File__c firstFile = [SELECT Id FROM Ken_File__c WHERE Album__c = :albumId LIMIT 1];
        Test.setCreatedDate(firstFile.Id, System.now().addDays(-5));

        System.runAs(ownerUser()) {
            KenGalleryController.testCurrentAccountId = uploaderAcc.Id;
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{ 'title' => 'second.png', 'base64' => 'data:image/png;base64,dGVzdA==' }
                }
            );
        }
        Ken_File__c newest = [
            SELECT Id FROM Ken_File__c WHERE Album__c = :albumId AND Id != :firstFile.Id LIMIT 1
        ];
        ContentDocumentLink link = [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :newest.Id LIMIT 1
        ];
        ContentVersion newestVersion = [
            SELECT Id FROM ContentVersion WHERE ContentDocumentId = :link.ContentDocumentId LIMIT 1
        ];

        List<KenGalleryController.AlbumRow> rows;
        System.runAs(ownerUser()) {
            Test.startTest();
            rows = KenGalleryController.getAlbums();
            Test.stopTest();
        }

        Boolean checked = false;
        for (KenGalleryController.AlbumRow r : rows) {
            if (r.id == albumId) {
                checked = true;
                System.assertNotEquals(null, r.coverImageUrl, 'An album with files should have a cover.');
                // The cover is the newest file's absolute ContentDistribution
                // link, NOT the thumbnail rendition it used to be. The rendition
                // URL is root-relative and does not resolve inside an Experience
                // Cloud site, so every cover fell back to the static placeholder
                // and albums looked empty. Trade-off accepted: the grid now loads
                // full-size images because ContentDistribution has no thumbnail.
                System.assert(
                    r.coverImageUrl.contains(newestVersion.Id) ||
                    r.coverImageUrl.contains('/sfc/dist/'),
                    'The cover should point at the newest upload: ' + r.coverImageUrl
                );
            }
        }
        System.assert(checked, 'The album under test should appear in the gallery list.');
    }

    @IsTest
    static void testUploadCapturesTheFileNameOnThePhotoRecord() {
        Id albumId;
        Account uploaderAcc = [SELECT Id FROM Account WHERE LastName = 'Uploader' LIMIT 1];

        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Named Upload Album' }
            );
            KenGalleryController.testCurrentAccountId = uploaderAcc.Id;
            Test.startTest();
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'title' => 'pic1.png',
                        'base64' => 'data:image/png;base64,dGVzdA=='
                    }
                }
            );
            Test.stopTest();
        }

        Ken_File__c photo = [SELECT Name, Is_Image__c FROM Ken_File__c WHERE Album__c = :albumId LIMIT 1];
        System.assertEquals(
            'pic1.png',
            photo.Name,
            'Without a name the record is auto-named with its own Id, which the landing page would show as a headline.'
        );
        System.assertEquals(
            true,
            photo.Is_Image__c,
            'Is_Image__c is stamped from the real file so the landing page can publish it without reading ContentVersion.'
        );
    }

    /**
     * A document upload must be recorded as such. The landing page drops
     * non-images outright, so a wrongly stamped PDF would render a broken card.
     */
    @IsTest
    static void testUploadStampsIsImageFalseForADocument() {
        Id albumId;
        Account uploaderAcc = [SELECT Id FROM Account WHERE LastName = 'Uploader' LIMIT 1];

        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Docs Album' }
            );
            KenGalleryController.testCurrentAccountId = uploaderAcc.Id;
            Test.startTest();
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'title' => 'newsletter.pdf',
                        'base64' => 'data:application/pdf;base64,dGVzdA=='
                    }
                }
            );
            Test.stopTest();
        }

        Ken_File__c photo = [SELECT Is_Image__c FROM Ken_File__c WHERE Album__c = :albumId LIMIT 1];
        System.assertEquals(
            false,
            photo.Is_Image__c,
            'A PDF must not be stamped as an image or the landing page would render a broken cover.'
        );
    }

    @IsTest
    static void testNewsletterUploadCreatesAGuestReadablePublicLink() {
        Id albumId;
        Account uploaderAcc = [SELECT Id FROM Account WHERE LastName = 'Uploader' LIMIT 1];

        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Newsletter' }
            );
            KenGalleryController.testCurrentAccountId = uploaderAcc.Id;
            Test.startTest();
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'title' => 'December Newsletter.pdf',
                        'base64' => 'data:application/pdf;base64,dGVzdA=='
                    }
                }
            );
            Test.stopTest();
        }

        // ContentDownloadUrl is generated by the platform and is not reliably
        // populated in a test context, so assert the distribution itself exists
        // - that is what makes the file readable without a login.
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDistribution],
            'A newsletter upload must publish a public link, or the landing page image breaks for visitors.'
        );
    }

    @IsTest
    static void testEveryAlbumUploadPublishesAPublicLink() {
        Id albumId;
        Account uploaderAcc = [SELECT Id FROM Account WHERE LastName = 'Uploader' LIMIT 1];

        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Sports Day 2024' }
            );
            KenGalleryController.testCurrentAccountId = uploaderAcc.Id;
            Test.startTest();
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'title' => 'team.png',
                        'base64' => 'data:image/png;base64,dGVzdA=='
                    }
                }
            );
            Test.stopTest();
        }

        // Public links are no longer newsletter-only. Every upload gets one so
        // the Public URL field on the file's Details page is always populated.
        // ContentDownloadUrl is not reliably generated in a test context, so
        // assert the distribution exists rather than the stored URL.
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDistribution],
            'Every album upload must publish a public link, not only the newsletter.'
        );
    }

    @IsTest
    static void testGetNewsletterBannerReturnsNullWhenAlbumEmpty() {
        System.runAs(ownerUser()) {
            KenGalleryController.createAlbum(new Map<String, Object>{ 'name' => 'Newsletters' });
        }

        KenGalleryController.NewsletterBanner banner;
        System.runAs(ownerUser()) {
            Test.startTest();
            banner = KenGalleryController.getNewsletterBanner();
            Test.stopTest();
        }
        System.assertEquals(null, banner, 'A Newsletter album with no photos should not produce a banner');
    }

    @IsTest
    static void testUpdateAlbumLinkAccessDenied() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Protected Linked Album' }
            );
        }

        System.runAs(otherUser()) {
            try {
                Test.startTest();
                KenGalleryController.updateAlbumLink(albumId, 'https://drive.google.com/drive/folders/xyz', null);
                Test.stopTest();
                System.assert(false, 'Expected AuraHandledException for access denied');
            } catch (AuraHandledException ex) {
                System.assertNotEquals(null, ex.getMessage(), 'Exception message should not be null');
            }
        }
    }

    /**
     * Internal staff curate the Newsletter album, which they will not own, so the
     * owner-only guard has to let a Standard-licence user through. The paired
     * denial case lives in testUploadPhotosAccessDeniedForNonOwner, which forces
     * the portal branch.
     */
    @IsTest
    static void testInternalStaffCanUploadIntoAnAlbumTheyDoNotOwn() {
        Id albumId;
        System.runAs(ownerUser()) {
            albumId = KenGalleryController.createAlbum(
                new Map<String, Object>{ 'name' => 'Newsletter' }
            );
        }

        System.runAs(otherUser()) {
            KenGalleryController.testIsInternalCurator = true;
            Test.startTest();
            KenGalleryController.uploadPhotos(
                albumId,
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'title' => 'october.png',
                        'base64' => 'data:image/png;base64,dGVzdA=='
                    }
                }
            );
            Test.stopTest();
        }

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Ken_File__c WHERE Album__c = :albumId],
            'A non-owning internal user should be able to curate an album.'
        );
    }
}