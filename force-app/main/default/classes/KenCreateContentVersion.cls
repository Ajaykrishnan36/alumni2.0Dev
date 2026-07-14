/**
 * @description Utility class for creating ContentVersion records from
 *              Base64-encoded data and generating public download URLs
 *              using ContentDistribution.
 */
public without sharing class KenCreateContentVersion {
    
    /**
     *  @description Creates a single ContentVersion from a Base64 string and
     *              returns a downloadable URL via ContentDistribution.
     *
     * @param title          File title and client path.
     * @param base64String   Base64-encoded file data.
     * @return               Content download URL (or exception message on error).
     */
    @AuraEnabled
    public static String createContentVersion(String title, String base64String) {
        try{
            Blob decodedData = EncodingUtil.base64Decode(base64String);
            ContentVersion newVersion = new ContentVersion();
            newVersion.Title = title;
            newVersion.PathOnClient = title;
            newVersion.VersionData = decodedData;

            if (Schema.sObjectType.ContentVersion.isCreateable()) {
                insert newVersion;
            }
            List<ContentVersion> documentId = [SELECT Id, ContentDocumentId, ContentUrl, ContentBodyId, Title, OwnerId, CreatedDate, FileType FROM ContentVersion WHERE Id=:newVersion.Id];

            ContentDistribution distribution = new ContentDistribution();
            distribution.Name = title;
            distribution.ContentVersionId  = documentId[0].Id;
            distribution.PreferencesLinkLatestVersion = true;
            distribution.PreferencesAllowViewInBrowser = true;
            distribution.PreferencesNotifyOnVisit = false;
            if (Schema.sObjectType.ContentDistribution.isCreateable()) {
                insert distribution;
            }
            
            ContentDistribution contentDistribution = [SELECT Id, CreatedDate, OwnerId, ContentVersionId, ContentDocumentId, RelatedRecordId, DistributionPublicUrl, ContentDownloadUrl, PdfDownloadUrl, PreferencesLinkLatestVersion, PreferencesAllowPDFDownload, PreferencesAllowOriginalDownload, PreferencesPasswordRequired FROM ContentDistribution WHERE Id =:distribution.Id LIMIT 1];
			String distributionPublicurl = contentDistribution?.ContentDownloadUrl;
            return distributionPublicurl;
        }Catch(Exception ex){
            return ex.getMessage();
        }
    }   

	    /**
     *@description Creates multiple ContentVersion records from a map of
     *              file titles to Base64-encoded content and returns
     *              downloadable URLs for each file. 
     * Behavior:
     * - Skips work and returns an empty map if the input is null/empty.
     * - Inserts ContentVersion and then creates ContentDistribution pointing to each version.
     * - Returns the ContentDownloadUrl for each created distribution keyed by title.
     *
     * @param titleToBase64Map  Map of file titles to Base64-encoded bodies.
     * @return                  Map of file titles to downloadable URLs.
     */
    public static Map<String, String> createMultipleContentVersions(Map<String, String> titleToBase64Map) {
        Map<String, String> titleToUrlMap = new Map<String, String>();
        if (titleToBase64Map == null || titleToBase64Map.isEmpty()) {
            return titleToUrlMap;
        }

        // Build ContentVersion list
        List<ContentVersion> contentVersions = new List<ContentVersion>();
        for (String title : titleToBase64Map.keySet()) {
            Blob decodedData = EncodingUtil.base64Decode(titleToBase64Map.get(title));
            ContentVersion cv = new ContentVersion();
            cv.Title = title;
            cv.PathOnClient = title;
            cv.VersionData = decodedData;
            contentVersions.add(cv);
        }

        // Insert ContentVersions (single decision, no nested if)
        if (!contentVersions.isEmpty() && Schema.sObjectType.ContentVersion.isCreateable()) {
            insert contentVersions;
        }

        // Build ContentDistribution list
        List<ContentDistribution> distributions = new List<ContentDistribution>();
        for (ContentVersion cv : contentVersions) {
            ContentDistribution dist = new ContentDistribution();
            dist.Name = cv.Title;
            dist.ContentVersionId = cv.Id;
            dist.PreferencesLinkLatestVersion = true;
            dist.PreferencesAllowViewInBrowser = true;
            dist.PreferencesNotifyOnVisit = false;
            distributions.add(dist);
        }

        // Insert ContentDistributions (single decision, no nested if)
        if (!distributions.isEmpty() && Schema.sObjectType.ContentDistribution.isCreateable()) {
            insert distributions;
        }

        // Fetch created distributions and build the return map
        Map<Id, ContentDistribution> distMap = new Map<Id, ContentDistribution>([
            SELECT Id, Name, DistributionPublicUrl, ContentDownloadUrl
            FROM ContentDistribution
            WHERE Id IN :distributions
        ]);

        for (ContentDistribution dist : distMap.values()) {
            // Keep using ContentDownloadUrl per existing behavior
            titleToUrlMap.put(dist.Name, dist.ContentDownloadUrl);
        }

        return titleToUrlMap;
    }


}