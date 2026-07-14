@IsTest
private class KenBusinessDirectoryTriggerHandlerTest {
    private static final String ALUMNI_RT   = 'Alumni_Person_Account';
    private static final String BUSINESS_RT = 'Business';
    private static final String OWNER_RT    = 'Business_Owner';

    private static Id getPersonAccountRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :ALUMNI_RT LIMIT 1
        ];
        if (!rts.isEmpty()) {
            return rts[0].Id;
        }
        for (RecordType rt : [SELECT Id, IsPersonType FROM RecordType WHERE SObjectType = 'Account']) {
            if (rt.IsPersonType) {
                return rt.Id;
            }
        }
        return null;
    }

    private static Id getBusinessRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = :BUSINESS_RT LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Id getOwnerJunctionRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Ken_Business_Directory__c' AND DeveloperName = :OWNER_RT LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    @IsTest
    static void mirrorsOwnerToBusinessAccount() {
        Id paRt = getPersonAccountRtId();
        Account owner = new Account(
            FirstName = 'Own', LastName = 'Er', PersonEmail = 'own.er.bizdir@test.example.com'
        );
        if (paRt != null) {
            owner.RecordTypeId = paRt;
        }
        insert owner;

        ConstituentRole ownerRole = new ConstituentRole(
            PersonId = owner.Id,
            RoleType = 'Alumni',
            Status = 'Active'
        );
        insert ownerRole;

        Account biz = new Account(
            Name = 'Dir Cafe', Business_Type__c = 'Technology',
            Business_Approval__c = 'Pending', Is_Active__c = true
        );
        Id bizRt = getBusinessRtId();
        if (bizRt != null) {
            biz.RecordTypeId = bizRt;
        }
        insert biz;

        Test.startTest();
        Ken_Business_Directory__c link = new Ken_Business_Directory__c(
            Constituent_Role__c = ownerRole.Id, Business_Account__c = biz.Id
        );
        Id ownerRt = getOwnerJunctionRtId();
        if (ownerRt != null) {
            link.RecordTypeId = ownerRt;
        }
        insert link;
        Test.stopTest();

        Account check = [SELECT Business_Owner_Role__c FROM Account WHERE Id = :biz.Id];
        System.assertEquals(ownerRole.Id, check.Business_Owner_Role__c,
            'Junction owner role should be mirrored onto the business account.');
    }
}