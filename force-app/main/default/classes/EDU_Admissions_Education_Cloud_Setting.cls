//WHAT: Use MetadataService class to enable Education Cloud setting in IndustriesSettings
//WHO: Brian Ricter | Q Branch
//WHEN: 242.1
public class EDU_Admissions_Education_Cloud_Setting {
    
    public static void enableEducationCloud() {
        MetadataService.MetadataPort service = new MetadataService.MetadataPort();
        
        service.SessionHeader = new MetadataService.SessionHeader_element();
        service.SessionHeader.sessionId = UserInfo.getSessionId();
        
        MetadataService.IndustriesSettings label = new MetadataService.IndustriesSettings();
        label.enableEducationCloud = true;
        MetadataService.Metadata[] packages = new MetadataService.Metadata[] { label };
            
            for ( MetadataService.UpsertResult result : service.upsertMetadata(packages) )
        {
            if ( !result.success )
            {
                System.debug( LoggingLevel.ERROR, JSON.serialize( result.errors[0].message ) );
            }
        }
    }
    
}