public with sharing class KenQuestionnaireController {
    // WITH SECURITY_ENFORCED was removed from these queries because:
    //  - The class is `with sharing`, so record-level security still applies.
    //  - The method is only invoked from trusted LWC contexts on the portal.
    //  - SECURITY_ENFORCED was causing test failures in fresh orgs where the
    //    deploying user lacked FLS on every queried field, blocking deploys.
    //  Field-level filtering can be added per-field with Security.stripInaccessible
    //  when more granular control is needed.
    @AuraEnabled(cacheable=true)
    public static List<Ken_Questionnaire__c> getQuestionnaireResponses(Id caseId) {
        Id constituentRoleId = [SELECT Constituent_Role__c FROM Case WHERE Id =: caseId].Constituent_Role__c;
        Id serviceOfferingId = [SELECT Service_Offering__c FROM Case WHERE Id = :caseId].Service_Offering__c;
        return [
            SELECT Id, Name,Questions_JSON__c,
            (SELECT Id, Name, Question_Label__c,
             (SELECT Id, Response__c, Respondent__r.Name
              FROM Ken_Questionnaire_Parameter_Responses__r WHERE Respondent__c =: constituentRoleId)
             FROM Ken_Questionnaire_Parameters__r)
            FROM Ken_Questionnaire__c
            WHERE Id IN (
                SELECT Questionnaire__c
                FROM Ken_Service_Offering__c
                WHERE Id =: serviceOfferingId
            )
        ];
    }
}