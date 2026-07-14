public without sharing class KenNavBarController {
    
    @TestVisible private static Boolean TEST_MODE = false;
    
    public class UserContactDetails {
        @AuraEnabled public String profilePhotoUrl { get; set; }
        @AuraEnabled public String graduationYear { get; set; }
        @AuraEnabled public String studentName { get; set; }
        @AuraEnabled public String contactRecordTypeName { get; set; }
        @AuraEnabled public String primaryContactType { get; set; }
        @AuraEnabled public String profileName { get; set; }
    }
    
    @AuraEnabled(cacheable=true)
    public static UserContactDetails getUserContactDetails() {
        UserContactDetails userDetails = new UserContactDetails();
        
        try {
            User currentUser = [
                SELECT Id, Name, AccountId, Profile.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            
            if (currentUser.AccountId != null) {
                Account pa = [
                    SELECT Id, Name
                    FROM Account
                    WHERE Id = :currentUser.AccountId
                    LIMIT 1
                ];
                
                userDetails.studentName = pa.Name;
                userDetails.profileName = currentUser.Profile.Name;
                    
                // Prefer the CRM record linked to the user's most recently registered role
                List<ConstituentRole> registeredRoles = [
                    SELECT Id FROM ConstituentRole
                    WHERE PersonId = :pa.Id AND RoleType = 'Alumni'
                      AND Registration_Status__c = 'Registered'
                    ORDER BY CreatedDate DESC LIMIT 1
                ];
                List<Ken_Alumni_CRM__c> alumniProfiles;
                if (!registeredRoles.isEmpty()) {
                    alumniProfiles = [
                        SELECT Profile_Photo_URL__c FROM Ken_Alumni_CRM__c
                        WHERE ConstituentRole__c = :registeredRoles[0].Id LIMIT 1
                    ];
                } else {
                    alumniProfiles = [
                        SELECT Profile_Photo_URL__c FROM Ken_Alumni_CRM__c
                        WHERE Person_Account__c = :pa.Id LIMIT 1
                    ];
                }

                if (!alumniProfiles.isEmpty()) {
                    userDetails.profilePhotoUrl = alumniProfiles[0].Profile_Photo_URL__c;
                }

                List<ConstituentRole> roles = [
                    SELECT Graduation_Year__c
                    FROM ConstituentRole
                    WHERE PersonId = :pa.Id
                        AND RoleType = 'Alumni'
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];

                if (!roles.isEmpty() && roles[0].Graduation_Year__c != null) {
                    userDetails.graduationYear = String.valueOf(roles[0].Graduation_Year__c);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching user details: ' + e.getMessage());
        }
        
        return userDetails;
    }
        
    @AuraEnabled(cacheable=true)
    public static List<ConnectApi.NavigationMenuItem> getNavigationMenuItems( String navigationLinkSetMasterLabel, String publishStatus, Boolean addHomeMenuItem, Boolean includeImageUrl ) {
        if (TEST_MODE) {
            ConnectApi.NavigationMenuItem mockItem = new ConnectApi.NavigationMenuItem();
            mockItem.label = 'Home';
            mockItem.actionValue = '/alumni/home';
            mockItem.actionType = ConnectApi.NavigationMenuItemActionType.InternalLink;            
            return new List<ConnectApi.NavigationMenuItem>{ mockItem };
        }
        
        navigationLinkSetMasterLabel = String.isNotBlank(navigationLinkSetMasterLabel) ? navigationLinkSetMasterLabel : 'Default Navigation';
                
        ConnectApi.PublishStatus publishStatusEnum = publishStatus.equalsIgnoreCase(ConnectApi.PublishStatus.Draft.name()) ? ConnectApi.PublishStatus.Draft : ConnectApi.PublishStatus.Live;
        
        List<ConnectApi.NavigationMenuItemType> menuItemsToSkip = new List<ConnectApi.NavigationMenuItemType>{
            ConnectApi.NavigationMenuItemType.Event,
            ConnectApi.NavigationMenuItemType.SystemLink
        };

        String networkId = Network.getNetworkId();
        String navigationLinkSetDeveloperName = getNavigationLinkSetDeveloperName(navigationLinkSetMasterLabel);
        
        if (String.isBlank(navigationLinkSetDeveloperName)) {
            navigationLinkSetDeveloperName = 'Default_Navigation';
        }

        ConnectApi.NavigationMenuItemCollection menu = ConnectApi.NavigationMenu.getCommunityNavigationMenu(
            networkId,
            null,
            navigationLinkSetDeveloperName,
            publishStatusEnum,
            includeImageUrl,
            addHomeMenuItem,
            menuItemsToSkip
        );
        
        return menu.menuItems;
    }
    
    @TestVisible
    private static String getNavigationLinkSetDeveloperName(String navigationLinkSetMasterLabel) {
        String networkId = Network.getNetworkId();
        
        List<NavigationLinkSet> navigationLinkSets = [
            SELECT DeveloperName
            FROM NavigationLinkSet
            WHERE NetworkId = :networkId
              AND MasterLabel = :navigationLinkSetMasterLabel
            LIMIT 1
        ];
        
        return navigationLinkSets.isEmpty()
            ? null
            : navigationLinkSets[0].DeveloperName;
    }
}