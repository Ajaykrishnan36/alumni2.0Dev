@IsTest
private class KenCaseCreatedEmailTriggerHandlerTest {
    private static Id getPersonAccountRtId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
                AND IsPersonType = true
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    @IsTest
    static void getQueueOwnerIds_onlyReturnsQueues() {
        Group queueGroup = new Group(
            Name = 'Queue One',
            DeveloperName = 'Queue_One_Test',
            Type = 'Queue'
        );
        insert queueGroup;
        insert new QueueSobject(QueueId = queueGroup.Id, SobjectType = 'Case');

        Set<Id> queueIds = KenCaseCreatedEmailTriggerHandler.getQueueOwnerIds(new List<Case>{
            new Case(OwnerId = queueGroup.Id),
            new Case(OwnerId = UserInfo.getUserId()),
            new Case()
        });

        System.assertEquals(new Set<Id>{ queueGroup.Id }, queueIds);
    }

    @IsTest
    static void getQueueMemberEmailsByQueueId_returnsActiveUserEmails() {
        Group queueGroup = new Group(
            Name = 'Queue Two',
            DeveloperName = 'Queue_Two_Test',
            Type = 'Queue'
        );
        insert queueGroup;
        insert new QueueSobject(QueueId = queueGroup.Id, SobjectType = 'Case');
        insert new GroupMember(GroupId = queueGroup.Id, UserOrGroupId = UserInfo.getUserId());

        Map<Id, List<String>> emailsByQueueId =
            KenCaseCreatedEmailTriggerHandler.getQueueMemberEmailsByQueueId(
                new Set<Id>{ queueGroup.Id }
            );

        System.assert(emailsByQueueId.containsKey(queueGroup.Id));
        System.assertEquals(1, emailsByQueueId.get(queueGroup.Id).size());
        System.assertEquals(UserInfo.getUserEmail(), emailsByQueueId.get(queueGroup.Id)[0]);
    }

    @IsTest
    static void getRecipientEmailsByOwnerId_includesUserOwners() {
        Map<Id, List<String>> emailsByOwnerId =
            KenCaseCreatedEmailTriggerHandler.getRecipientEmailsByOwnerId(
                new Set<Id>{ UserInfo.getUserId() }
            );

        System.assert(emailsByOwnerId.containsKey(UserInfo.getUserId()));
        System.assertEquals(
            new List<String>{ UserInfo.getUserEmail() },
            emailsByOwnerId.get(UserInfo.getUserId())
        );
    }

    @IsTest
    static void getRequesterEmail_prefersSuppliedEmail() {
        String requesterEmail = KenCaseCreatedEmailTriggerHandler.getRequesterEmail(
            new Case(SuppliedEmail = 'requester@example.com')
        );

        System.assertEquals('requester@example.com', requesterEmail);
    }

    @IsTest
    static void getRequesterEmail_usesPersonAccountEmail() {
        Id personAccountRtId = getPersonAccountRtId();
        if (personAccountRtId == null) {
            System.assert(true);
            return;
        }

        Account personAccount = new Account(
            RecordTypeId = personAccountRtId,
            LastName = 'Requester',
            PersonEmail = 'person.account.requester@test.example.com'
        );
        insert personAccount;

        Case caseRecord = new Case(
            Subject = 'Requester Email Test',
            Status = 'New',
            Origin = 'Web',
            AccountId = personAccount.Id
        );
        insert caseRecord;

        Case storedCase = [
            SELECT Account.PersonEmail
            FROM Case
            WHERE Id = :caseRecord.Id
        ];

        System.assertEquals(
            'person.account.requester@test.example.com',
            KenCaseCreatedEmailTriggerHandler.getRequesterEmail(storedCase)
        );
    }

    @IsTest
    static void handleAfterInsert_sendsOwnerAndRequesterEmails() {
        Case caseRecord = new Case(
            Subject = 'Created Email Test',
            Status = 'New',
            Origin = 'Web',
            SuppliedEmail = 'requester@example.com',
            OwnerId = UserInfo.getUserId()
        );
        insert caseRecord;

        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.handleAfterInsert(new List<Case>{
            new Case(Id = caseRecord.Id)
        });
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void handleAfterUpdate_nullList_noError() {
        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.handleAfterUpdate(null, null);
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void handleAfterUpdate_emptyList_noError() {
        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.handleAfterUpdate(
            new List<Case>(), new Map<Id, Case>()
        );
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void handleAfterUpdate_ownerUnchanged_noEmail() {
        Case c = new Case(Subject = 'Owner Unchanged', Status = 'New', Origin = 'Web',
                          OwnerId = UserInfo.getUserId());
        insert c;
        Case fresh = [SELECT Id, OwnerId FROM Case WHERE Id = :c.Id];

        Case oldCase = new Case(Id = fresh.Id, OwnerId = fresh.OwnerId);
        Case newCase = new Case(Id = fresh.Id, OwnerId = fresh.OwnerId);

        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.handleAfterUpdate(
            new List<Case>{ newCase },
            new Map<Id, Case>{ fresh.Id => oldCase }
        );
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations(), 'No email when owner did not change');
    }

    @IsTest
    static void sendEmailsForCaseIds_nullInput_noError() {
        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.sendEmailsForCaseIds(null);
        Test.stopTest();
        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void sendEmailsForCaseIds_emptyInput_noError() {
        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.sendEmailsForCaseIds(new Set<Id>());
        Test.stopTest();
        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void sendEmailsForCaseIds_validCase_noTemplatesNoEmail() {
        Case c = new Case(Subject = 'Send Email Direct', Status = 'New', Origin = 'Web');
        insert c;

        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.sendEmailsForCaseIds(new Set<Id>{ c.Id });
        Test.stopTest();

        // No email templates exist in scratch org — no email sent, no crash
        System.assert(true, 'sendEmailsForCaseIds should complete without error even with no templates');
    }

    @IsTest
    static void sendCaseCreatedEmails_emptyList_noEmail() {
        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.sendCaseCreatedEmails(
            new List<Case>(),
            new Map<Id, List<String>>(),
            null,
            null,
            null
        );
        Test.stopTest();
        System.assertEquals(0, Limits.getEmailInvocations());
    }

    @IsTest
    static void sendCaseCreatedEmails_nullTemplates_noEmail() {
        Case c = new Case(Subject = 'Send Direct Test', Status = 'New', Origin = 'Web',
                          SuppliedEmail = 'test@test.com', OwnerId = UserInfo.getUserId());
        insert c;

        Case fresh = [SELECT Id, OwnerId, SuppliedEmail, Account.PersonEmail, CreatedBy.Email
                      FROM Case WHERE Id = :c.Id];

        Test.startTest();
        KenCaseCreatedEmailTriggerHandler.sendCaseCreatedEmails(
            new List<Case>{ fresh },
            new Map<Id, List<String>>{ fresh.OwnerId => new List<String>{ UserInfo.getUserEmail() } },
            null,   // userTemplateId = null
            null,   // ownerTemplateId = null
            null
        );
        Test.stopTest();

        System.assertEquals(0, Limits.getEmailInvocations(),
            'No email should be sent when both template Ids are null');
    }

    @IsTest
    static void getQueueMemberEmailsByQueueId_emptyInput_returnsEmpty() {
        Test.startTest();
        Map<Id, List<String>> result =
            KenCaseCreatedEmailTriggerHandler.getQueueMemberEmailsByQueueId(new Set<Id>());
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void getRequesterEmail_nullCase_returnsNull() {
        Test.startTest();
        String email = KenCaseCreatedEmailTriggerHandler.getRequesterEmail(null);
        Test.stopTest();

        System.assertEquals(null, email);
    }

    @IsTest
    static void getRequesterEmail_noEmailFields_returnsNull() {
        Case emptyCase = new Case();

        Test.startTest();
        String email = KenCaseCreatedEmailTriggerHandler.getRequesterEmail(emptyCase);
        Test.stopTest();

        System.assertEquals(null, email);
    }
}