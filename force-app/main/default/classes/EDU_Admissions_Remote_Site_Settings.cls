public class EDU_Admissions_Remote_Site_Settings {

    public static void create_RemoteSiteSettings() {        
              
        MetadataService.MetadataPort service = new MetadataService.MetadataPort();

                    service.SessionHeader = new MetadataService.SessionHeader_element();
                    service.SessionHeader.sessionId = UserInfo.getSessionId();
                    
                   String baseURL = System.URL.getSalesforceBaseURL().gethost();
                    
        // Create RemoteSiteSetting with base Domain URL
                    MetadataService.RemoteSiteSetting rssBase = new MetadataService.RemoteSiteSetting();
                    rssBase.fullName = 'This_Domain';
                    rssBase.isActive = true;
                    rssBase.disableProtocolSecurity = false;
                    rssBase.Description  = 'desc';
                    rssBase.url='https://' + baseURL;
        
        // Create RemoteSiteSetting for sfLabs
                    MetadataService.RemoteSiteSetting rssSFLabs = new MetadataService.RemoteSiteSetting();
                    rssSFLabs.fullName = 'Salesforce_Labs';
                    rssSFLabs.isActive = true;
                    rssSFLabs.disableProtocolSecurity = false;
                    rssSFLabs.Description  = 'desc';
                    rssSFLabs.url='https://' + baseURL.left(baseURL.indexOf('.',1)) + '--sflabs-cms-ct.visualforce.com';

        // Create RemoteSiteSetting for MetadataService
                    MetadataService.RemoteSiteSetting rssMS = new MetadataService.RemoteSiteSetting();
                    rssMS.fullName = 'Metadata_Service';
                    rssMS.isActive = true;
                    rssMS.disableProtocolSecurity = false;
                    rssMS.Description  = 'desc';
                    rssMS.url='https://' + baseURL.left(baseURL.indexOf('.',1)) + '--c.vf.force.com/services/Soap/m/57.0';
                    
        //Add all RSS to package
        MetadataService.Metadata[] packages = new MetadataService.Metadata[] { rssBase, rssSFLabs, rssMS };
                        
                    for ( MetadataService.UpsertResult result : service.upsertMetadata(packages) )
                    {
                        if ( !result.success )
                        {
                            System.debug( LoggingLevel.ERROR, JSON.serialize( result.errors[0].message ) );
                        }
                    }
            }
}