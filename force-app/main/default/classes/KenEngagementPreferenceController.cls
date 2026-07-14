/**
 * Supplies the configurable engagement/contribution preference cards shown on
 * the onboarding "What do you want to do on the platform?" step. Cards are
 * driven by the Ken_Engagement_Preference__c object so admins can add, reorder
 * or hide options without a code change.
 */
public without sharing class KenEngagementPreferenceController {

    public class PreferenceOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String iconUrl;
        @AuraEnabled public String email;
    }

    @AuraEnabled(cacheable=true)
    public static List<PreferenceOption> getOptions() {
        List<PreferenceOption> options = new List<PreferenceOption>();
        for (Ken_Engagement_Preference__c rec : [
            SELECT Id, Name, Description__c, Image_URL__c, Icon__c, Email__c
            FROM Ken_Engagement_Preference__c
            WHERE Is_Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC
        ]) {
            PreferenceOption opt = new PreferenceOption();
            opt.id = rec.Id;
            opt.name = rec.Name;
            opt.description = rec.Description__c;
            opt.imageUrl = rec.Image_URL__c;
            opt.iconUrl = rec.Icon__c;
            opt.email = rec.Email__c;
            options.add(opt);
        }
        return options;
    }
}