public without sharing class KenResourceV2Controller {

    public class FolderItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String owner;
        @AuraEnabled public String updated;
        @AuraEnabled public Integer count;
        @AuraEnabled public String color;
        @AuraEnabled public String icon;
        @AuraEnabled public String privacy;
    }

    public class ResourceItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String size;
        @AuraEnabled public String fileDate;
        @AuraEnabled public String ext;
        @AuraEnabled public String notes;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String folderId;
    }

    @AuraEnabled(cacheable=true)
    public static List<FolderItem> getCategories() {
        List<FolderItem> result = new List<FolderItem>();
        for (Ken_Resource_Folder__c f : [
            SELECT Id, Name, Owner_Label__c, Color__c, Icon__c, Last_Updated_Label__c,
                   Resource_Count__c, Privacy__c
            FROM Ken_Resource_Folder__c
            WHERE Privacy__c IN ('Public', 'Alumni Only')
            ORDER BY Name ASC
            LIMIT 200
        ]) {
            FolderItem fi = new FolderItem();
            fi.id = f.Id;
            fi.name = f.Name;
            fi.owner = f.Owner_Label__c;
            fi.color = f.Color__c;
            fi.icon = f.Icon__c;
            fi.updated = f.Last_Updated_Label__c;
            fi.count = f.Resource_Count__c == null ? 0 : Integer.valueOf(f.Resource_Count__c);
            fi.privacy = f.Privacy__c;
            result.add(fi);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<ResourceItem> getResources(Id folderId) {
        List<ResourceItem> result = new List<ResourceItem>();
        if (folderId == null) return result;
        for (Ken_Resource__c r : [
            SELECT Id, Name, Folder__c, Content_Version__c, Size_Label__c,
                   File_Date_Label__c, Extension__c, Notes__c
            FROM Ken_Resource__c
            WHERE Folder__c = :folderId
            ORDER BY CreatedDate DESC
            LIMIT 500
        ]) {
            result.add(toResourceItem(r));
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static ResourceItem getResource(Id resourceId) {
        if (resourceId == null) return null;
        List<Ken_Resource__c> rows = [
            SELECT Id, Name, Folder__c, Content_Version__c, Size_Label__c,
                   File_Date_Label__c, Extension__c, Notes__c
            FROM Ken_Resource__c
            WHERE Id = :resourceId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : toResourceItem(rows[0]);
    }

    @AuraEnabled
    public static Id createFolder(Map<String, Object> payload) {
        if (payload == null) throw new AuraHandledException('Payload required');
        Ken_Resource_Folder__c f = new Ken_Resource_Folder__c();
        f.Name = asString(payload.get('name'));
        f.Owner_Label__c = asString(payload.get('owner'));
        f.Color__c = asString(payload.get('color'));
        f.Icon__c = asString(payload.get('icon'));
        f.Last_Updated_Label__c = asString(payload.get('updated'));
        String privacy = asString(payload.get('privacy'));
        f.Privacy__c = String.isBlank(privacy) ? 'Public' : privacy;
        if (String.isBlank(f.Name)) throw new AuraHandledException('Folder name required');
        insert f;
        return f.Id;
    }

    @AuraEnabled
    public static Id createResource(Map<String, Object> payload) {
        if (payload == null) throw new AuraHandledException('Payload required');
        Ken_Resource__c r = new Ken_Resource__c();
        r.Name = asString(payload.get('name'));
        String folderIdStr = asString(payload.get('folderId'));
        if (String.isBlank(folderIdStr)) throw new AuraHandledException('folderId required');
        r.Folder__c = (Id) folderIdStr;
        String cvId = asString(payload.get('contentVersionId'));
        if (String.isNotBlank(cvId)) r.Content_Version__c = cvId;
        r.Size_Label__c = asString(payload.get('size'));
        r.File_Date_Label__c = asString(payload.get('fileDate'));
        String ext = asString(payload.get('ext'));
        r.Extension__c = String.isBlank(ext) ? 'PDF' : ext;
        r.Notes__c = asString(payload.get('notes'));
        if (String.isBlank(r.Name)) throw new AuraHandledException('Resource name required');
        insert r;
        return r.Id;
    }

    @AuraEnabled
    public static void archiveResource(Id resourceId) {
        if (resourceId == null) throw new AuraHandledException('resourceId required');
        delete [SELECT Id FROM Ken_Resource__c WHERE Id = :resourceId LIMIT 1];
    }

    private static ResourceItem toResourceItem(Ken_Resource__c r) {
        ResourceItem ri = new ResourceItem();
        ri.id = r.Id;
        ri.name = r.Name;
        ri.size = r.Size_Label__c;
        ri.fileDate = r.File_Date_Label__c;
        ri.ext = r.Extension__c;
        ri.notes = r.Notes__c;
        ri.contentVersionId = r.Content_Version__c;
        ri.folderId = r.Folder__c;
        return ri;
    }

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }
}