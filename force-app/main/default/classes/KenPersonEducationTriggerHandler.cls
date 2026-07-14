public without sharing class KenPersonEducationTriggerHandler extends KenTriggerHandler {

    private static final String INST_TYPE_OWN = 'Our Institute';
    private static final String ROLE_TYPE_SECONDARY = 'Secondary';
    private static final Id ALUMNI_LEAD_RT_ID =
        Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Alumni Lead').getRecordTypeId();

    public override void processAfterInsert() {
        createSecondaryRoleLeads((List<PersonEducation>) Trigger.new);
    }

    @TestVisible
    private static void createSecondaryRoleLeads(List<PersonEducation> educations) {
        if (educations == null || educations.isEmpty()) {
            return;
        }

        Map<Id, List<PersonEducation>> eduByAccount = new Map<Id, List<PersonEducation>>();
        for (PersonEducation edu : educations) {
            if (edu.Institution_Type__c != INST_TYPE_OWN || edu.AccountId == null) {
                continue;
            }
            if (!eduByAccount.containsKey(edu.AccountId)) {
                eduByAccount.put(edu.AccountId, new List<PersonEducation>());
            }
            eduByAccount.get(edu.AccountId).add(edu);
        }
        if (eduByAccount.isEmpty()) {
            return;
        }

        Map<Id, Account> accts = new Map<Id, Account>([
            SELECT Id, FirstName, LastName, PersonEmail, Phone, OwnerId
            FROM Account
            WHERE Id IN :eduByAccount.keySet() AND IsPersonAccount = true
        ]);

        List<Lead> toInsert = new List<Lead>();
        for (Id accId : eduByAccount.keySet()) {
            Account a = accts.get(accId);
            if (a == null || String.isBlank(a.PersonEmail)) {
                continue;
            }
            for (PersonEducation edu : eduByAccount.get(accId)) {
                toInsert.add(new Lead(
                    OwnerId                  = a.OwnerId,
                    RecordTypeId             = ALUMNI_LEAD_RT_ID,
                    FirstName                = a.FirstName,
                    LastName                 = String.isBlank(a.LastName) ? 'Alumni' : a.LastName,
                    Company                  = 'Alumni',
                    Email                    = a.PersonEmail,
                    Phone                    = a.Phone,
                    Status                   = 'new',
                    LeadSource               = 'Web',
                    Existing_Account__c      = accId,
                    Constituent_Role_Type__c = ROLE_TYPE_SECONDARY,
                    Institution_Name__c      = edu.Institute_Name__c,
                    Year_of_Graduation__c    = edu.Year_of_Completion__c,
                    Program_Plan__c          = edu.Program_Plan__c,
                    Registration_Number__c   = edu.Registration_Number__c
                ));
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }
}