/**
 * Supplies per-module show/hide flags for the alumni portal navigation and the
 * internal Alumni Management app, sourced from the Alumni_Module_Settings__c
 * hierarchy custom setting.
 *
 * Semantics: a module is HIDDEN only when its checkbox is explicitly unchecked
 * (false). A missing setting record or a null value means the module is SHOWN,
 * so existing orgs keep every module visible until an admin turns one off.
 */
public with sharing class KenModuleVisibilityController {

    public class ModuleVisibility {
        @AuraEnabled public Boolean home;
        @AuraEnabled public Boolean events;
        @AuraEnabled public Boolean jobs;
        @AuraEnabled public Boolean network;
        @AuraEnabled public Boolean mentorship;
        @AuraEnabled public Boolean fundraise;
        @AuraEnabled public Boolean groups;
        @AuraEnabled public Boolean gallery;
        @AuraEnabled public Boolean businessDirectory;
        @AuraEnabled public Boolean feedbackSurvey;
        @AuraEnabled public Boolean serviceSupport;
    }

    // Only false when the checkbox is explicitly unchecked; null/missing => shown.
    private static Boolean shown(Boolean value) {
        return value != false;
    }

    @AuraEnabled(cacheable=true)
    public static ModuleVisibility getModuleVisibility() {
        Alumni_Module_Settings__c cs = Alumni_Module_Settings__c.getOrgDefaults();
        // getOrgDefaults() returns an UNSAVED instance (Id == null) when no org
        // default record exists — and its checkboxes read false, not null. Only
        // honour the flags when a real record has been saved; otherwise every
        // module stays visible.
        Boolean hasRecord = cs != null && cs.Id != null;

        ModuleVisibility mv = new ModuleVisibility();
        mv.home = !hasRecord || shown(cs.Show_Home__c);
        mv.events = !hasRecord || shown(cs.Show_Events__c);
        mv.jobs = !hasRecord || shown(cs.Show_Jobs__c);
        mv.network = !hasRecord || shown(cs.Show_Network__c);
        mv.mentorship = !hasRecord || shown(cs.Show_Mentorship__c);
        mv.fundraise = !hasRecord || shown(cs.Show_Fundraise__c);
        mv.groups = !hasRecord || shown(cs.Show_Groups__c);
        mv.gallery = !hasRecord || shown(cs.Show_Gallery__c);
        mv.businessDirectory = !hasRecord || shown(cs.Show_Business_Directory__c);
        mv.feedbackSurvey = !hasRecord || shown(cs.Show_Feedback_Survey__c);
        mv.serviceSupport = !hasRecord || shown(cs.Show_Service_Support__c);
        return mv;
    }
}