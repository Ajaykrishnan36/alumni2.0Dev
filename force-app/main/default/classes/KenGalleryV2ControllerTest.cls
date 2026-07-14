@IsTest
private class KenGalleryV2ControllerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'V2 Test Business Account');
        insert acc;
        Contact con = new Contact(FirstName = 'Gallery', LastName = 'Uploader', AccountId = acc.Id);
        insert con;
    }

    private static Contact uploaderContact() {
        return [SELECT Id FROM Contact WHERE LastName = 'Uploader' LIMIT 1];
    }

    @IsTest
    static void testCreateAlbumRequiresPayload() {
        try {
            KenGalleryV2Controller.createAlbum(null);
            System.assert(false, 'Expected AuraHandledException for null payload');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void testCreateAlbumRequiresName() {
        try {
            Test.startTest();
            KenGalleryV2Controller.createAlbum(new Map<String, Object>{ 'name' => '' });
            Test.stopTest();
            System.assert(false, 'Expected AuraHandledException for missing name');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void testCreateAlbumSetsDefaults() {
        Test.startTest();
        Id albumId = KenGalleryV2Controller.createAlbum(
            new Map<String, Object>{ 'name' => 'V2 Test Album', 'cover' => '#ff0000' }
        );
        Test.stopTest();

        Ken_Photo_Album__c album = [
            SELECT Name, Year__c, Privacy__c, Cover_Color__c FROM Ken_Photo_Album__c WHERE Id = :albumId
        ];
        System.assertEquals('V2 Test Album', album.Name);
        System.assertEquals(String.valueOf(Date.today().year()), album.Year__c);
        System.assertEquals('Public', album.Privacy__c);
        System.assertEquals('#ff0000', album.Cover_Color__c);
    }

    @IsTest
    static void testCreateAlbumWithExplicitYearAndPrivacy() {
        Id albumId = KenGalleryV2Controller.createAlbum(
            new Map<String, Object>{ 'name' => 'Reunion', 'year' => '2020', 'privacy' => 'Alumni Only' }
        );
        Ken_Photo_Album__c album = [SELECT Year__c, Privacy__c FROM Ken_Photo_Album__c WHERE Id = :albumId];
        System.assertEquals('2020', album.Year__c);
        System.assertEquals('Alumni Only', album.Privacy__c);
    }

    @IsTest
    static void testGetAlbumsReturnsOnlyNonPrivate() {
        Id publicId = KenGalleryV2Controller.createAlbum(new Map<String, Object>{ 'name' => 'Public Album' });
        Id privateId = KenGalleryV2Controller.createAlbum(
            new Map<String, Object>{ 'name' => 'Private Album', 'privacy' => 'Private' }
        );

        Test.startTest();
        List<KenGalleryV2Controller.AlbumItem> albums = KenGalleryV2Controller.getAlbums();
        Test.stopTest();

        Set<Id> returnedIds = new Set<Id>();
        for (KenGalleryV2Controller.AlbumItem a : albums) {
            returnedIds.add((Id) a.id);
        }
        System.assert(returnedIds.contains(publicId), 'Public album should be returned');
        System.assert(!returnedIds.contains(privateId), 'Private album should be excluded');
    }

    @IsTest
    static void testAddPhotoRequiresAlbumId() {
        try {
            KenGalleryV2Controller.addPhoto(new Map<String, Object>{ 'name' => 'pic.png' });
            System.assert(false, 'Expected AuraHandledException for missing albumId');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void testAddPhotoAndReadBack() {
        Id albumId = KenGalleryV2Controller.createAlbum(new Map<String, Object>{ 'name' => 'Photo Album' });
        Contact uploader = uploaderContact();

        Test.startTest();
        Id photoId = KenGalleryV2Controller.addPhoto(
            new Map<String, Object>{
                'albumId' => albumId,
                'name' => 'pic1.png',
                'caption' => 'Great day',
                'color' => '#336699',
                'contentVersionId' => '068000000000001AAA',
                'uploaderId' => uploader.Id
            }
        );
        Test.stopTest();

        System.assertNotEquals(null, photoId);

        List<KenGalleryV2Controller.PhotoItem> photos = KenGalleryV2Controller.getAlbumPhotos(albumId);
        System.assertEquals(1, photos.size());
        System.assertEquals('Great day', photos[0].caption);
        System.assertEquals('#336699', photos[0].color);
        System.assertEquals('Gallery Uploader', photos[0].uploader);
        System.assertEquals(albumId, (Id) photos[0].albumId);
    }

    @IsTest
    static void testGetAlbumPhotosNullAlbumIdReturnsEmpty() {
        List<KenGalleryV2Controller.PhotoItem> photos = KenGalleryV2Controller.getAlbumPhotos(null);
        System.assertEquals(0, photos.size());
    }

    @IsTest
    static void testDeletePhotoRequiresId() {
        try {
            KenGalleryV2Controller.deletePhoto(null);
            System.assert(false, 'Expected AuraHandledException for missing photoId');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }

    @IsTest
    static void testDeletePhoto() {
        Id albumId = KenGalleryV2Controller.createAlbum(new Map<String, Object>{ 'name' => 'Delete Test Album' });
        Id photoId = KenGalleryV2Controller.addPhoto(
            new Map<String, Object>{ 'albumId' => albumId, 'name' => 'pic.png' }
        );

        Test.startTest();
        KenGalleryV2Controller.deletePhoto(photoId);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Ken_Photo__c WHERE Id = :photoId]);
    }
}