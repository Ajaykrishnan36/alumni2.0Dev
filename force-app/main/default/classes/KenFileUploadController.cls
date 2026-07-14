public with sharing class KenFileUploadController {

    @AuraEnabled
    public static String uploadAndGetPublicUrl(String fileName, String base64Content) {
        return KenCreateContentVersion.createContentVersion(fileName, base64Content);
    }

    /**
     * @description Maps each supported object API name to the field that should
     *              store the uploaded image URL. Add an entry here to enable the
     *              reusable image-upload quick action on a new object.
     */
    private static final Map<String, String> OBJECT_TO_IMAGE_FIELD = new Map<String, String>{
        'Account' => 'Logo_File_URL__c',
        'Ken_Engagement_Preference__c' => 'Image_URL__c',
        'KenAlumniSpotlight__c' => 'Content_Link__c'
    };

    /**
     * @description Converts a Base64 image to a public URL and stores that URL on
     *              the given record. The target field is resolved from
     *              OBJECT_TO_IMAGE_FIELD, so the same action works across objects.
     *
     * @param recordId    Id of the record to update.
     * @param objectName  API name of the record's object.
     * @param fileName    Name to give the stored file.
     * @param base64Data  Base64 image data (data-URI prefix tolerated).
     */
    @AuraEnabled
    public static void uploadImage(String recordId, String objectName, String fileName, String base64Data) {
        try {
            if (String.isBlank(recordId) || String.isBlank(objectName)) {
                throw new AuraHandledException('Record Id and object name are required.');
            }

            String fieldName = OBJECT_TO_IMAGE_FIELD.get(objectName);
            if (String.isBlank(fieldName)) {
                throw new AuraHandledException('Image upload is not configured for object: ' + objectName);
            }

            String content = base64Data.contains(',') ? base64Data.substringAfter(',') : base64Data;
            String imageUrl = KenCreateContentVersion.createContentVersion(fileName, content);

            SObject record = Schema.getGlobalDescribe().get(objectName).newSObject();
            record.put('Id', recordId);
            record.put(fieldName, imageUrl);
            update record;
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading image: ' + e.getMessage());
        }
    }
}