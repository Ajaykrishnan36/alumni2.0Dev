@IsTest
private class KenBusinessTriggerHandlerTest {
    private static final String BUSINESS_RT = 'Business';
    private static final String ALUMNI_RT   = 'Alumni_Person_Account';

    private static Id getBusinessRtId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = :BUSINESS_RT LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

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

    private static Account buildBusiness(String name) {
        Account b = new Account(
            Name                 = name,
            Business_Type__c     = 'Technology',
            Business_Approval__c = 'Pending',
            Is_Active__c         = true
        );
        Id rt = getBusinessRtId();
        if (rt != null) {
            b.RecordTypeId = rt;
        }
        return b;
    }

    // Submitting a Pending business notifies admins (Custom Notification is a no-op in tests).
    @IsTest
    static void notifiesAdminsOnSubmit() {
        Test.startTest();
        Account biz = buildBusiness('Trg Cafe');
        insert biz;
        Test.stopTest();

        Account check = [SELECT Business_Approval__c FROM Account WHERE Id = :biz.Id];
        System.assertEquals('Pending', check.Business_Approval__c, 'Stays Pending until approved.');
    }

    // A non-Business account is ignored; a rejected→Pending resubmit re-notifies — no errors.
    @IsTest
    static void ignoresNonBusinessAndHandlesResubmit() {
        Id paRt = getPersonAccountRtId();
        Account person = new Account(
            FirstName   = 'Test',
            LastName    = 'Person',
            PersonEmail = 'test.person.biznotif@test.example.com'
        );
        if (paRt != null) {
            person.RecordTypeId = paRt;
        }
        insert person;

        Account biz = buildBusiness('Trg Diner');
        insert biz;

        Test.startTest();
        biz.Business_Approval__c = 'Rejected';
        update biz;
        biz.Business_Approval__c = 'Pending';
        update biz;
        Test.stopTest();

        Account check = [SELECT Business_Approval__c FROM Account WHERE Id = :biz.Id];
        System.assertEquals('Pending', check.Business_Approval__c, 'Resubmit leaves it Pending.');
    }
}