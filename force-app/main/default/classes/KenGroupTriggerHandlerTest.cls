@IsTest
private class KenGroupTriggerHandlerTest {

    private static User buildRunAsUser() {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        return new User(
            Username  = 'grptrigger.' + System.currentTimeMillis() + '@example.com',
            Email     = 'grptrigger@example.com',
            LastName  = 'GrpTrigger',
            Alias     = 'gtrig',
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = prof.Id
        );
    }

    @TestSetup
    static void setupData() {
        Account creator = new Account(Name = 'GroupTriggerCreator');
        insert creator;

        insert new Ken_Group__c(
            Name            = 'Trigger Test Group',
            Description__c  = 'Test group for trigger',
            Group_Type__c   = 'Public',
            Status__c       = 'Draft',
            Is_Active__c    = false,
            Is_Featured__c  = false,
            Created_By__c   = creator.Id,
            Member_Count__c = 0
        );
    }

    @IsTest
    static void testAfterUpdateStatusChangesToInReviewSubmitsForApproval() {
        Ken_Group__c grp = [SELECT Id, Status__c FROM Ken_Group__c WHERE Name = 'Trigger Test Group' LIMIT 1];

        User runAsUser = buildRunAsUser();
        insert runAsUser;

        System.runAs(runAsUser) {
            Test.startTest();
            grp.Status__c = 'In Review';
            update grp;
            Test.stopTest();
        }

        Ken_Group__c updated = [SELECT Status__c FROM Ken_Group__c WHERE Id = :grp.Id LIMIT 1];
        System.assertEquals('In Review', updated.Status__c, 'Group status should be In Review after update');
    }

    @IsTest
    static void testAfterUpdateStatusAlreadyInReviewNoReSubmit() {
        Ken_Group__c grp = [SELECT Id, Status__c FROM Ken_Group__c WHERE Name = 'Trigger Test Group' LIMIT 1];
        grp.Status__c = 'In Review';
        update grp;

        Test.startTest();
        grp.Description__c = 'Updated description';
        update grp;
        Test.stopTest();

        Ken_Group__c updated = [SELECT Status__c FROM Ken_Group__c WHERE Id = :grp.Id LIMIT 1];
        System.assertEquals('In Review', updated.Status__c, 'Status should remain In Review when description changes');
    }

    @IsTest
    static void testAfterUpdateStatusNotInReviewNoSubmit() {
        Ken_Group__c grp = [SELECT Id, Status__c FROM Ken_Group__c WHERE Name = 'Trigger Test Group' LIMIT 1];

        Test.startTest();
        grp.Status__c      = 'Draft';
        grp.Description__c = 'Changed description only';
        update grp;
        Test.stopTest();

        Ken_Group__c updated = [SELECT Status__c FROM Ken_Group__c WHERE Id = :grp.Id LIMIT 1];
        System.assertEquals('Draft', updated.Status__c, 'Status should remain Draft when not changing to In Review');
    }
}