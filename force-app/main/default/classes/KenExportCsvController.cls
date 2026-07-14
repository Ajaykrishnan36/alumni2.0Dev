public with sharing class KenExportCsvController {

    @AuraEnabled
    public static String getDownloadUrl(String csvContent, String filename) {
        try {
            ContentVersion cv = new ContentVersion(
                Title          = filename,
                PathOnClient   = filename,
                VersionData    = Blob.valueOf(csvContent),
                IsMajorVersion = true,
                Origin         = 'H'
            );
            insert cv;
            return '/sfc/servlet.shepherd/version/download/' + cv.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}