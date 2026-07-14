public without sharing class KenGalleryV2Controller {

    public class AlbumItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Integer count;
        @AuraEnabled public String cover;
        @AuraEnabled public String year;
        @AuraEnabled public String privacy;
    }

    public class PhotoItem {
        @AuraEnabled public String id;
        @AuraEnabled public String color;
        @AuraEnabled public String caption;
        @AuraEnabled public String uploader;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String albumId;
    }

    @AuraEnabled(cacheable=true)
    public static List<AlbumItem> getAlbums() {
        List<AlbumItem> result = new List<AlbumItem>();
        for (Ken_Photo_Album__c a : [
            SELECT Id, Name, Year__c, Cover_Color__c, Photo_Count__c, Privacy__c
            FROM Ken_Photo_Album__c
            WHERE Privacy__c IN ('Public', 'Alumni Only', 'Batch Only')
            ORDER BY Year__c DESC, Name ASC
            LIMIT 200
        ]) {
            AlbumItem ai = new AlbumItem();
            ai.id = a.Id;
            ai.name = a.Name;
            ai.year = a.Year__c;
            ai.cover = a.Cover_Color__c;
            ai.count = a.Photo_Count__c == null ? 0 : Integer.valueOf(a.Photo_Count__c);
            ai.privacy = a.Privacy__c;
            result.add(ai);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<PhotoItem> getAlbumPhotos(Id albumId) {
        List<PhotoItem> result = new List<PhotoItem>();
        if (albumId == null) return result;
        for (Ken_Photo__c p : [
            SELECT Id, Name, Album__c, Content_Version__c, Caption__c,
                   Uploader__r.Name, Color_Hint__c
            FROM Ken_Photo__c
            WHERE Album__c = :albumId
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            PhotoItem pi = new PhotoItem();
            pi.id = p.Id;
            pi.albumId = p.Album__c;
            pi.color = p.Color_Hint__c;
            pi.caption = p.Caption__c;
            pi.uploader = p.Uploader__r != null ? p.Uploader__r.Name : null;
            pi.contentVersionId = p.Content_Version__c;
            result.add(pi);
        }
        return result;
    }

    @AuraEnabled
    public static Id createAlbum(Map<String, Object> payload) {
        if (payload == null) throw new AuraHandledException('Payload required');
        Ken_Photo_Album__c a = new Ken_Photo_Album__c();
        a.Name = asString(payload.get('name'));
        a.Year__c = asString(payload.get('year'));
        a.Cover_Color__c = asString(payload.get('cover'));
        String privacy = asString(payload.get('privacy'));
        a.Privacy__c = String.isBlank(privacy) ? 'Public' : privacy;
        if (String.isBlank(a.Name)) throw new AuraHandledException('Album name required');
        if (String.isBlank(a.Year__c)) a.Year__c = String.valueOf(Date.today().year());
        insert a;
        return a.Id;
    }

    @AuraEnabled
    public static Id addPhoto(Map<String, Object> payload) {
        if (payload == null) throw new AuraHandledException('Payload required');
        String albumIdStr = asString(payload.get('albumId'));
        if (String.isBlank(albumIdStr)) throw new AuraHandledException('albumId required');
        Ken_Photo__c p = new Ken_Photo__c();
        p.Album__c = (Id) albumIdStr;
        p.Name = asString(payload.get('name'));
        if (String.isBlank(p.Name)) p.Name = 'Photo';
        p.Caption__c = asString(payload.get('caption'));
        p.Color_Hint__c = asString(payload.get('color'));
        String cvId = asString(payload.get('contentVersionId'));
        if (String.isNotBlank(cvId)) p.Content_Version__c = cvId;
        String uploaderId = asString(payload.get('uploaderId'));
        if (String.isNotBlank(uploaderId)) p.Uploader__c = (Id) uploaderId;
        insert p;
        return p.Id;
    }

    @AuraEnabled
    public static void deletePhoto(Id photoId) {
        if (photoId == null) throw new AuraHandledException('photoId required');
        delete [SELECT Id FROM Ken_Photo__c WHERE Id = :photoId LIMIT 1];
    }

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }
}