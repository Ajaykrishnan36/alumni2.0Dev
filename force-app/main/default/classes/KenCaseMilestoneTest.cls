@IsTest
private class KenCaseMilestoneTest {
    private static Group createCaseQueue(String name, String developerName) {
        Group queueGroup = new Group(
            Name = name,
            DeveloperName = developerName,
            Type = 'Queue'
        );
        insert queueGroup;
        insert new QueueSobject(QueueId = queueGroup.Id, SobjectType = 'Case');
        insert new GroupMember(GroupId = queueGroup.Id, UserOrGroupId = UserInfo.getUserId());
        return queueGroup;
    }

    private static Map<String, Id> getTemplateIds(Set<String> developerNames) {
        Map<String, Id> templateIds = new Map<String, Id>();
        for (EmailTemplate template : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :developerNames
        ]) {
            templateIds.put(template.DeveloperName, template.Id);
        }
        return templateIds;
    }

    private static Id getAlumniManagementOrgWideId() {
        String displayName = KenSnSConstants.getOrgWideEmailDisplayName();
        if (String.isBlank(displayName)) return null;
        List<OrgWideEmailAddress> orgWideAddresses = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE DisplayName = :displayName
            LIMIT 1
        ];
        return orgWideAddresses.isEmpty() ? null : orgWideAddresses[0].Id;
    }

    @IsTest
    static void getImpactedQueueCaseIds_filtersInsertCases() {
        Id queueId = (Id) '00G000000000001AAA';
        Id entitlementId = (Id) '550000000000001AAA';
        Id caseId = (Id) '500000000000001AAA';

        Case eligibleCase = new Case(
            Id = caseId,
            OwnerId = queueId,
            EntitlementId = entitlementId
        );
        Case userOwnedCase = new Case(
            Id = (Id) '500000000000002AAA',
            OwnerId = UserInfo.getUserId(),
            EntitlementId = entitlementId
        );

        Set<Id> caseIds = KenCaseEscalationEmailTriggerHandler.getImpactedQueueCaseIds(
            new List<Case>{ eligibleCase, userOwnedCase },
            null
        );

        System.assertEquals(new Set<Id>{ caseId }, caseIds);
    }

    @IsTest
    static void getImpactedQueueCaseIds_filtersUpdateCases() {
        Id queueId = (Id) '00G000000000001AAA';
        Id entitlementId = (Id) '550000000000001AAA';
        Id updatedEntitlementId = (Id) '550000000000002AAA';
        Id caseId = (Id) '500000000000001AAA';

        Case oldCase = new Case(
            Id = caseId,
            OwnerId = queueId,
            EntitlementId = entitlementId
        );
        Case newCase = new Case(
            Id = caseId,
            OwnerId = queueId,
            EntitlementId = updatedEntitlementId
        );

        Set<Id> caseIds = KenCaseEscalationEmailTriggerHandler.getImpactedQueueCaseIds(
            new List<Case>{ newCase },
            new Map<Id, Case>{ caseId => oldCase }
        );

        System.assertEquals(new Set<Id>{ caseId }, caseIds);
    }

    @IsTest
    static void getRecipientEmailsByOwnerId_returnsEmptyForUnknownOwner() {
        Map<Id, List<String>> recipientEmailsByOwnerId =
            KenCaseEscalationEmailTriggerHandler.getRecipientEmailsByOwnerId(
                new Set<Id>{ (Id) '001000000000001AAA' }
            );

        System.assertEquals(0, recipientEmailsByOwnerId.size(),
            'Non-user, non-queue id prefix should yield empty map');
    }

    @IsTest
    static void handleAfterUpdate_sendsEscalationEmail() {
        Case caseRecord = new Case(
            Subject = 'Escalation Email Test',
            Status = 'New',
            Origin = 'Web',
            Priority = 'Medium',
            OwnerId = UserInfo.getUserId()
        );
        insert caseRecord;

        Case storedCase = [
            SELECT Id, OwnerId, EntitlementId, IsClosed, MilestoneStatus, IsEscalated
            FROM Case
            WHERE Id = :caseRecord.Id
        ];
        Case oldCase = storedCase.clone(false, true, false, false);
        oldCase.Id = storedCase.Id;
        oldCase.IsEscalated = false;

        Case newCase = storedCase.clone(false, true, false, false);
        newCase.Id = storedCase.Id;
        newCase.IsEscalated = true;

        Test.startTest();
        KenCaseEscalationEmailTriggerHandler.handleAfterUpdate(
            new List<Case>{ newCase },
            new Map<Id, Case>{ caseRecord.Id => oldCase }
        );
        System.assertEquals(1, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @IsTest
    static void getRecipientEmailsByOwnerId_returnsQueueAndUserRecipients() {
        Group queueGroup = createCaseQueue('Escalation Queue', 'Escalation_Queue_Test');

        Map<Id, List<String>> recipientEmailsByOwnerId =
            KenCaseEscalationEmailTriggerHandler.getRecipientEmailsByOwnerId(
                new Set<Id>{ queueGroup.Id, UserInfo.getUserId() }
            );

        System.assertEquals(
            new List<String>{ UserInfo.getUserEmail() },
            recipientEmailsByOwnerId.get(queueGroup.Id)
        );
        System.assertEquals(
            new List<String>{ UserInfo.getUserEmail() },
            recipientEmailsByOwnerId.get(UserInfo.getUserId())
        );
    }

    @IsTest
    static void sendEscalationEmails_usesBreachTemplateWhenAvailable() {
        Map<String, Id> templateIds = getTemplateIds(new Set<String>{
            'Ken_Case_Escalation_Notification',
            'Ken_Case_Milestone_Breach'
        });
        System.assert(templateIds.containsKey('Ken_Case_Escalation_Notification'));
        System.assert(templateIds.containsKey('Ken_Case_Milestone_Breach'));

        Case caseRecord = new Case(
            Subject = 'Breach Email Test',
            Status = 'New',
            Origin = 'Web',
            Priority = 'High',
            OwnerId = UserInfo.getUserId()
        );
        insert caseRecord;

        Case storedCase = [
            SELECT Id, OwnerId
            FROM Case
            WHERE Id = :caseRecord.Id
        ];

        Test.startTest();
        KenCaseEscalationEmailTriggerHandler.sendEscalationEmails(
            new List<Case>{ storedCase },
            new Map<Id, List<String>>{
                UserInfo.getUserId() => new List<String>{ UserInfo.getUserEmail() }
            },
            new Set<Id>{ storedCase.Id },
            templateIds.get('Ken_Case_Escalation_Notification'),
            templateIds.get('Ken_Case_Milestone_Breach'),
            getAlumniManagementOrgWideId()
        );
        System.assertEquals(1, Limits.getEmailInvocations());
        Test.stopTest();
    }

    @IsTest
    static void handleAfterInsert_isNoOp() {
        Group queueGroup = createCaseQueue('Insert Warning Queue', 'Insert_Warning_Queue_Test');
        Case queueOwnedCase = new Case(
            Id = (Id) '500000000000011AAA',
            OwnerId = queueGroup.Id,
            EntitlementId = (Id) '550000000000011AAA'
        );

        Test.startTest();
        KenCaseEscalationEmailTriggerHandler.handleAfterInsert(new List<Case>{ queueOwnedCase });
        Test.stopTest();

        // Milestone warning scheduling has been moved to KenCaseMilestoneWarningSweeper;
        // handleAfterInsert no longer schedules per-milestone jobs.
        System.assertEquals(0, Limits.getEmailInvocations());
    }
}