public with sharing class KenThemeConfigController {

    public class portalconfigs {
        @AuraEnabled public String primaryColor;
        @AuraEnabled public String secondaryColor;
        @AuraEnabled public String tertiaryColor;
        @AuraEnabled public String institutionName;
        @AuraEnabled public String institutionAlias;
        @AuraEnabled public String portalUrl;
        @AuraEnabled public String linkedInSsoProvider;
        @AuraEnabled public Boolean showHostEvent;
        @AuraEnabled public Boolean disableEventFee;

        public portalconfigs(String pri, String sec, String ter, String Name, String Alias, String url) {
            primaryColor = pri;
            secondaryColor = sec;
            tertiaryColor = ter;
			institutionName = Name;
			institutionAlias = Alias;
            portalUrl = url;
        }
    }

    private static final String DEFAULT_LINKEDIN_SSO_PROVIDER = 'LinkedInNewSSO';

    @AuraEnabled(cacheable=true)
    public static portalconfigs getPortalConfigs() {
        Alumni_Org_Parameters__c cs = Alumni_Org_Parameters__c.getOrgDefaults();

        String primary = cs.Portal_Primary_colour__c;
        String secondary = cs.Portal_Secondary_colour__c;
        String tertiary = cs.Portal_Tertiary_colour__c;
		String institutionName = (cs != null && String.isNotBlank(cs.Institution_Name__c)) ? cs.Institution_Name__c : 'Kenverse';
		String institutionAlias = (cs != null && String.isNotBlank(cs.Institution_Alias__c)) ? cs.Institution_Alias__c : 'Ken42';
        String portalUrl = (cs != null && String.isNotBlank(cs.Portal_URL__c)) ? cs.Portal_URL__c : '';

        portalconfigs config = new portalconfigs(primary, secondary, tertiary, institutionName, institutionAlias, portalUrl);
        config.linkedInSsoProvider = (cs != null && String.isNotBlank(cs.LinkedIn_SSO_Provider__c))
            ? cs.LinkedIn_SSO_Provider__c
            : DEFAULT_LINKEDIN_SSO_PROVIDER;
        config.showHostEvent = (cs != null && cs.Show_Host_Event__c == true);
        config.disableEventFee = (cs != null && cs.Disable_Event_Fee__c == true);
        return config;
    }
}