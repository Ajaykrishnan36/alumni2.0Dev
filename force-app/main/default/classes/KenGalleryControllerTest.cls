@IsTest
private class KenGalleryControllerTest {

    private static final String ALUMNI_RT = 'Alumni_Person_Account';

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
        ];
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account']) {
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
        Ken_Photo_Album__c album = [
            SELECT Name, OwnerId FROM Ken_Photo_Album__c WHERE Id = :albumId
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
        Ken_Photo_Album__c album = [
            SELECT Name, External_Link__c FROM Ken_Photo_Album__c WHERE Id = :albumId
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

        Ken_Photo_Album__c album = [
            SELECT Photo_Count__c, Last_Photo_Added_Date__c, Cover_Photo__c
            FROM Ken_Photo_Album__c
            WHERE Id = :albumId
        ];
        System.assertEquals(1, Integer.valueOf(album.Photo_Count__c), 'Rollup should count the new photo');
        System.assertNotEquals(null, album.Last_Photo_Added_Date__c);
        System.assertNotEquals(null, album.Cover_Photo__c, 'First uploaded photo should become the cover');

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
        Id photoId = [SELECT Id FROM Ken_Photo__c WHERE Album__c = :albumId LIMIT 1].Id;

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

        System.assertEquals(0, [SELECT COUNT() FROM Ken_Photo_Album__c WHERE Id = :albumId]);
        System.assertEquals(0, [SELECT COUNT() FROM Ken_Photo__c WHERE Album__c = :albumId]);
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

        Ken_Photo_Album__c album = [
            SELECT External_Link__c FROM Ken_Photo_Album__c WHERE Id = :albumId
        ];
        System.assertEquals('https://drive.google.com/drive/folders/abc123', album.External_Link__c);

        System.runAs(ownerUser()) {
            KenGalleryController.updateAlbumLink(albumId, '', null);
        }
        album = [SELECT External_Link__c FROM Ken_Photo_Album__c WHERE Id = :albumId];
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

        Ken_Photo_Album__c album = [SELECT Name FROM Ken_Photo_Album__c WHERE Id = :albumId];
        System.assertEquals('Real Album Name', album.Name);
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
}