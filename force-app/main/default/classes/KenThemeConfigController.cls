public with sharing class KenThemeConfigController {

    public class portalconfigs {
        @AuraEnabled public String primaryColor;
        @AuraEnabled public String secondaryColor;
        @AuraEnabled public String tertiaryColor;
        @AuraEnabled public String institutionName;
        @AuraEnabled public String institutionAlias;
        @AuraEnabled public String portalUrl;
        @AuraEnabled public String landingPageLogoUrl;
        @AuraEnabled public String linkedInSsoProvider;
        @AuraEnabled public String googleSsoProvider;
        @AuraEnabled public Boolean showHostEvent;
        @AuraEnabled public Boolean disableEventFee;
        // "Allow alumni to create" flags from Ken_Alm_Module_Settings__c. Fail-open:
        // allowed unless the checkbox is explicitly unchecked on a saved record,
        // so existing orgs keep every create action until an admin turns one off.
        @AuraEnabled public Boolean createGroups;
        @AuraEnabled public Boolean createSurvey;
        @AuraEnabled public Boolean createFundraise;
        @AuraEnabled public Boolean createBusiness;
        @AuraEnabled public Boolean createJobs;
        @AuraEnabled public Boolean createAlbum;
        // Login configuration from Ken_Alm_Org_Parameters__c. loginMethod is
        // Password, OTP or Both; otpDeliveryChannel is Email, SMS or Both. Both
        // fail safe to the password flow / email channel when left blank.
        @AuraEnabled public String loginMethod;
        @AuraEnabled public String otpDeliveryChannel;
        // ISO country code for c/kenCustomPhoneInput, from Default_Dial_Code__c —
        // the same value kenRegisterPage uses, so both screens open on the same
        // country and the picker stays usable.
        @AuraEnabled public String defaultDialCountry;

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
        Ken_Alm_Org_Parameters__c cs = Ken_Alm_Org_Parameters__c.getOrgDefaults();

        String primary = cs.Portal_Primary_colour__c;
        String secondary = cs.Portal_Secondary_colour__c;
        String tertiary = cs.Portal_Tertiary_colour__c;
		String institutionName = (cs != null && String.isNotBlank(cs.Institution_Name__c)) ? cs.Institution_Name__c : 'Institute Name';
		String institutionAlias = (cs != null && String.isNotBlank(cs.Institution_Alias__c)) ? cs.Institution_Alias__c : 'Institute';
        String portalUrl = (cs != null && String.isNotBlank(cs.Portal_URL__c)) ? cs.Portal_URL__c : '';

        portalconfigs config = new portalconfigs(primary, secondary, tertiary, institutionName, institutionAlias, portalUrl);
        // Blank means the admin has not uploaded a real logo yet; the LWC falls
        // back to its own placeholder image rather than rendering a broken <img>.
        config.landingPageLogoUrl = (cs != null && String.isNotBlank(cs.Landing_Page_Logo_URL__c))
            ? cs.Landing_Page_Logo_URL__c.trim()
            : null;
        config.linkedInSsoProvider = (cs != null && String.isNotBlank(cs.LinkedIn_SSO_Provider__c))
            ? cs.LinkedIn_SSO_Provider__c
            : DEFAULT_LINKEDIN_SSO_PROVIDER;
        config.googleSsoProvider = (cs != null && String.isNotBlank(cs.Google_SSO_Provider__c))
            ? cs.Google_SSO_Provider__c
            : null;
        // "Host an event" is now controlled from Ken_Alm_Module_Settings__c
        // (Allow Create Events) rather than Ken_Alm_Org_Parameters__c. Kept
        // fail-closed (shown only when explicitly enabled) to preserve the
        // existing host-event behaviour.
        Ken_Alm_Module_Settings__c ms = Ken_Alm_Module_Settings__c.getOrgDefaults();
        Boolean msHasRecord = (ms != null && ms.Id != null);
        config.showHostEvent = (ms != null && ms.Allow_Create_Events__c == true);
        // Fail-open: allowed unless explicitly unchecked on a saved record.
        config.createGroups = !msHasRecord || ms.Allow_Create_Groups__c != false;
        config.createSurvey = !msHasRecord || ms.Allow_Create_Survey__c != false;
        config.createFundraise = !msHasRecord || ms.Allow_Create_Fundraise__c != false;
        config.createBusiness = !msHasRecord || ms.Allow_Create_Business__c != false;
        config.createJobs = !msHasRecord || ms.Allow_Create_Jobs__c != false;
        config.createAlbum = !msHasRecord || ms.Allow_Create_Album__c != false;
        config.disableEventFee = (cs != null && cs.Disable_Event_Fee__c == true);
        config.loginMethod = (cs != null && String.isNotBlank(cs.Login_Method__c))
            ? cs.Login_Method__c.trim()
            : 'Password';
        config.otpDeliveryChannel = (cs != null && String.isNotBlank(cs.OTP_Delivery_Channel__c))
            ? cs.OTP_Delivery_Channel__c.trim()
            : 'Email';
        config.defaultDialCountry = (cs != null && String.isNotBlank(cs.Default_Dial_Code__c))
            ? cs.Default_Dial_Code__c.trim().toLowerCase()
            : 'in';
        return config;
    }
}