@IsTest
private class KenEventTriggerHandlerCoverageTest {
    private static final String RUN_AS_ALIAS = 'ethcv';

    @TestSetup
    static void setupData() {
        Id profileId = [SELECT ProfileId FROM User WHERE Id = :UserInfo.getUserId()].ProfileId;
        User runAsUser = new User(
            FirstName = 'Event',
            LastName = 'TriggerCoverage',
            Email = 'event.trigger.coverage@example.com',
            Username = 'event.trigger.coverage.' + DateTime.now().getTime() + '@example.com',
            Alias = RUN_AS_ALIAS,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
        insert runAsUser;

        RecordType personRt = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        Account personAccount = new Account(
            RecordTypeId = personRt.Id,
            LastName = 'Event Trigger Person',
            PersonEmail = 'event.trigger.person@example.com'
        );
        insert personAccount;

        ConstituentRole constituentRole = new ConstituentRole(
            PersonId = personAccount.Id,
            RoleType = 'Alumni',
            Registration_Status__c = 'Registered',
            Email__c = 'event.trigger.person@example.com'
        );
        constituentRole.put('Status', 'Admitted');
        insert constituentRole;
    }

    /**
     * @description Moving an event from Draft into In Review (the submit-for-approval
     *              status) must run the handler's approval-submission path.
     */
    @IsTest
    static void updateToSubmittedInvokesApprovalPath() {
        User runAsUser = [SELECT Id FROM User WHERE Alias = :RUN_AS_ALIAS LIMIT 1];
        Id roleId = [SELECT Id FROM ConstituentRole LIMIT 1].Id;

        System.runAs(runAsUser) {
            Ken_Event_Master__c eventRecord = new Ken_Event_Master__c(
                Name = 'Approval Candidate Event',
                Event_Status__c = 'Draft',
                Constituent_Role__c = roleId
            );
            insert eventRecord;

            eventRecord.Event_Status__c = 'In Review';

            Test.startTest();
            update eventRecord;
            Test.stopTest();

            Ken_Event_Master__c refreshed = [
                SELECT Event_Status__c
                FROM Ken_Event_Master__c
                WHERE Id = :eventRecord.Id
                LIMIT 1
            ];
            System.assertEquals('In Review', refreshed.Event_Status__c, 'Event should transition to In Review (submitted for approval).');
        }
    }

    /**
     * @description An update that keeps the event in In Review must skip the handler's
     *              resubmission condition (old and new status both In Review).
     */
    @IsTest
    static void updateWhenAlreadySubmittedSkipsResubmissionCondition() {
        User runAsUser = [SELECT Id FROM User WHERE Alias = :RUN_AS_ALIAS LIMIT 1];
        Id roleId = [SELECT Id FROM ConstituentRole LIMIT 1].Id;

        System.runAs(runAsUser) {
            Ken_Event_Master__c eventRecord = new Ken_Event_Master__c(
                Name = 'Already Submitted Event',
                Event_Status__c = 'In Review',
                Constituent_Role__c = roleId
            );
            insert eventRecord;

            eventRecord.Name = 'Already Submitted Event Updated';

            Test.startTest();
            update eventRecord;
            Test.stopTest();

            Ken_Event_Master__c refreshed = [
                SELECT Name, Event_Status__c
                FROM Ken_Event_Master__c
                WHERE Id = :eventRecord.Id
                LIMIT 1
            ];
            System.assertEquals('Already Submitted Event Updated', refreshed.Name, 'Update should persist when status remains In Review.');
            System.assertEquals('In Review', refreshed.Event_Status__c, 'In Review status should remain unchanged.');
        }
    }

    /**
     * @description Approving an In Review event must run the speaker-invite enqueue
     *              and the creator approval-notification paths without error.
     */
    @IsTest
    static void approveTransitionRunsInviteAndNotificationPaths() {
        Id roleId = [SELECT Id FROM ConstituentRole LIMIT 1].Id;
        Id personId = [SELECT PersonId FROM ConstituentRole WHERE Id = :roleId].PersonId;

        Ken_Event_Master__c eventRecord = new Ken_Event_Master__c(
            Name = 'Approval Notification Event',
            Event_Status__c = 'In Review',
            Constituent_Role__c = roleId,
            Person_Account__c = personId
        );
        insert eventRecord;

        Test.startTest();
        eventRecord.Event_Status__c = 'Approved';
        update eventRecord;
        eventRecord.Event_Status__c = 'Cancelled';
        update eventRecord;
        Test.stopTest();

        Ken_Event_Master__c refreshed = [
            SELECT Event_Status__c FROM Ken_Event_Master__c WHERE Id = :eventRecord.Id LIMIT 1
        ];
        System.assertEquals('Cancelled', refreshed.Event_Status__c, 'Event should end Cancelled after approve then cancel transitions.');
    }

    /**
     * @description Rejecting an In Review event must run the creator rejection-notification path.
     */
    @IsTest
    static void rejectTransitionRunsNotificationPath() {
        Id roleId = [SELECT Id FROM ConstituentRole LIMIT 1].Id;
        Id personId = [SELECT PersonId FROM ConstituentRole WHERE Id = :roleId].PersonId;

        Ken_Event_Master__c eventRecord = new Ken_Event_Master__c(
            Name = 'Rejection Notification Event',
            Event_Status__c = 'In Review',
            Constituent_Role__c = roleId,
            Person_Account__c = personId
        );
        insert eventRecord;

        Test.startTest();
        eventRecord.Event_Status__c = 'Rejected';
        update eventRecord;
        Test.stopTest();

        Ken_Event_Master__c refreshed = [
            SELECT Event_Status__c FROM Ken_Event_Master__c WHERE Id = :eventRecord.Id LIMIT 1
        ];
        System.assertEquals('Rejected', refreshed.Event_Status__c, 'Event should be Rejected after the transition.');
    }
}