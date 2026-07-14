public class EDU_Core_PostSpinUserVisibility {
	
    
    
    // Constructor for the class
    public static void setSiteUserVisibility() {
        //get the Internal Users so we can set their visibility
    	List<User> users = [SELECT Id, Name, EDU_Core_Is_Key_User__c, UserRole.Name, UserPreferencesShowProfilePicToGuestUsers, UserPreferencesShowCityToExternalUsers, UserPreferencesShowWorkPhoneToExternalUsers,UserPreferencesShowTitleToExternalUsers, UserPreferencesShowStreetAddressToExternalUsers, UserPreferencesShowStateToExternalUsers, UserPreferencesShowPostalCodeToExternalUsers, UserPreferencesShowMobilePhoneToExternalUsers, UserPreferencesShowEmailToExternalUsers, UserPreferencesShowCountryToExternalUsers FROM User WHERE EDU_Core_Is_Key_User__c = TRUE AND IsActive = TRUE AND (NOT UserRole.Name LIKE '%customer%')];
        // Loop through users to set visibility
        for(User u : users){
            u.UserPreferencesShowCityToExternalUsers          = TRUE;
            u.UserPreferencesShowWorkPhoneToExternalUsers     = TRUE;
            u.UserPreferencesShowTitleToExternalUsers         = TRUE;
            u.UserPreferencesShowStreetAddressToExternalUsers = TRUE;
            u.UserPreferencesShowStateToExternalUsers         = TRUE;
            u.UserPreferencesShowPostalCodeToExternalUsers    = TRUE;
            u.UserPreferencesShowMobilePhoneToExternalUsers   = TRUE;
            u.UserPreferencesShowEmailToExternalUsers         = TRUE;
            u.UserPreferencesShowCountryToExternalUsers       = TRUE;
            u.UserPreferencesShowProfilePicToGuestUsers		  = TRUE;
            update u;
        }
    }
}