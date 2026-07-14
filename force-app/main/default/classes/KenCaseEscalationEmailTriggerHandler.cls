public without sharing class KenCaseEscalationEmailTriggerHandler {
    private static final String ESCALATION_TEMPLATE_DEVELOPER_NAME = KenSnSConstants.EMAIL_TEMPLATE_CASE_ESCALATION;
    private static final String BREACH_TEMPLATE_DEVELOPER_NAME = KenSnSConstants.EMAIL_TEMPLATE_CASE_MILESTONE_BREACH;

    public static void handleAfterInsert(List<Case> newCases) {
        // Milestone warnings are now driven by KenCaseMilestoneWarningSweeper
        // (a single recurring scheduled job), so insert no longer schedules
        // per-milestone jobs. Escalation emails are only sent on update.
    }

    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldCaseMap) {
        if (shouldSkipContext() || newCases == null || newCases.isEmpty()) {
            return;
        }
        // Check individual bypasses — escalation and breach are independent
        Boolean escalationBypassed = KenSnSConstants.isEscalationEmailBypassed();
        Boolean breachBypassed     = KenSnSConstants.isMilestoneBreachEmailBypassed();
        if (escalationBypassed && breachBypassed) return;

        Set<Id> escalatedCaseIds = getNewEscalatedCaseIds(newCases, oldCaseMap);
        if (escalatedCaseIds.isEmpty()) {
            return;
        }

        Map<String, Id> templateIdsByDeveloperName = getTemplateIdsByDeveloperName(new Set<String>{
            ESCALATION_TEMPLATE_DEVELOPER_NAME,
            BREACH_TEMPLATE_DEVELOPER_NAME
        });
        Id escalationTemplateId = escalationBypassed ? null : templateIdsByDeveloperName.get(ESCALATION_TEMPLATE_DEVELOPER_NAME);
        Id breachTemplateId     = breachBypassed     ? null : templateIdsByDeveloperName.get(BREACH_TEMPLATE_DEVELOPER_NAME);
        if (escalationTemplateId == null && breachTemplateId == null) {
            return;
        }

        Set<Id> breachedCaseIds = getBreachedCaseIds(escalatedCaseIds);
        List<Case> escalatedCases = [
            SELECT Id, OwnerId, CaseNumber, Subject, Priority, Status, CreatedDate, Account.Name
            FROM Case
            WHERE Id IN :escalatedCaseIds
        ];
        if (escalatedCases.isEmpty()) {
            return;
        }

        Set<Id> ownerIds = new Set<Id>();
        for (Case escalatedCase : escalatedCases) {
            if (escalatedCase.OwnerId != null) {
                ownerIds.add(escalatedCase.OwnerId);
            }
        }
        Map<Id, List<String>> recipientEmailsByOwnerId = getRecipientEmailsByOwnerId(ownerIds);
        if (recipientEmailsByOwnerId.isEmpty()) {
            return;
        }

        sendEscalationEmails(
            escalatedCases,
            recipientEmailsByOwnerId,
            breachedCaseIds,
            escalationTemplateId,
            breachTemplateId,
            getOrgWideEmailAddressId()
        );
    }

    private static Boolean shouldSkipContext() {
        return System.isBatch()
            || System.isFuture()
            || System.isQueueable()
            || System.isScheduled();
    }

    private static Set<Id> getNewEscalatedCaseIds(List<Case> newCases, Map<Id, Case> oldCaseMap) {
        Set<Id> escalatedCaseIds = new Set<Id>();
        for (Case newCase : newCases) {
            Case oldCase = oldCaseMap != null ? oldCaseMap.get(newCase.Id) : null;
            if (oldCase != null && !oldCase.IsEscalated && newCase.IsEscalated) {
                escalatedCaseIds.add(newCase.Id);
            }
        }
        return escalatedCaseIds;
    }

    @TestVisible
    private static Set<Id> getImpactedQueueCaseIds(List<Case> newCases, Map<Id, Case> oldCaseMap) {
        Set<Id> caseIds = new Set<Id>();
        for (Case caseRecord : newCases) {
            if (caseRecord == null
                || caseRecord.Id == null
                || caseRecord.OwnerId == null
                || caseRecord.EntitlementId == null
                || caseRecord.IsClosed
                || !String.valueOf(caseRecord.OwnerId).startsWith('00G')) {
                continue;
            }

            if (oldCaseMap == null) {
                caseIds.add(caseRecord.Id);
                continue;
            }

            Case oldCase = oldCaseMap.get(caseRecord.Id);
            if (oldCase == null
                || oldCase.OwnerId != caseRecord.OwnerId
                || oldCase.EntitlementId != caseRecord.EntitlementId
                || oldCase.IsClosed != caseRecord.IsClosed
                || oldCase.MilestoneStatus != caseRecord.MilestoneStatus) {
                caseIds.add(caseRecord.Id);
            }
        }
        return caseIds;
    }

    private static Set<Id> getBreachedCaseIds(Set<Id> caseIds) {
        Set<Id> breachedCaseIds = new Set<Id>();
        for (CaseMilestone caseMilestone : [
            SELECT CaseId
            FROM CaseMilestone
            WHERE CaseId IN :caseIds
                AND IsCompleted = false
                AND IsViolated = true
        ]) {
            breachedCaseIds.add(caseMilestone.CaseId);
        }
        return breachedCaseIds;
    }

    private static Map<String, Id> getTemplateIdsByDeveloperName(Set<String> developerNames) {
        Map<String, Id> templateIdsByDeveloperName = new Map<String, Id>();
        for (EmailTemplate template : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :developerNames
        ]) {
            templateIdsByDeveloperName.put(template.DeveloperName, template.Id);
        }
        return templateIdsByDeveloperName;
    }

    private static Id getOrgWideEmailAddressId() {
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

    public static Map<Id, List<String>> getRecipientEmailsByOwnerId(Set<Id> ownerIds) {
        Map<Id, List<String>> recipientEmailsByOwnerId = new Map<Id, List<String>>();
        if (ownerIds == null || ownerIds.isEmpty()) {
            return recipientEmailsByOwnerId;
        }

        Set<Id> queueIds = new Set<Id>();
        Set<Id> userOwnerIds = new Set<Id>();
        for (Id ownerId : ownerIds) {
            if (ownerId == null) {
                continue;
            }

            String ownerIdValue = String.valueOf(ownerId);
            if (ownerIdValue.startsWith('00G')) {
                queueIds.add(ownerId);
            } else if (ownerIdValue.startsWith('005')) {
                userOwnerIds.add(ownerId);
            }
        }

        if (!queueIds.isEmpty()) {
            Map<Id, Set<Id>> userIdsByQueueId = new Map<Id, Set<Id>>();
            Set<Id> userIds = new Set<Id>();
            for (GroupMember queueMember : [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :queueIds
            ]) {
                if (!String.valueOf(queueMember.UserOrGroupId).startsWith('005')) {
                    continue;
                }

                if (!userIdsByQueueId.containsKey(queueMember.GroupId)) {
                    userIdsByQueueId.put(queueMember.GroupId, new Set<Id>());
                }
                userIdsByQueueId.get(queueMember.GroupId).add(queueMember.UserOrGroupId);
                userIds.add(queueMember.UserOrGroupId);
            }

            Map<Id, String> emailByUserId = new Map<Id, String>();
            if (!userIds.isEmpty()) {
                for (User queueUser : [
                    SELECT Id, Email
                    FROM User
                    WHERE Id IN :userIds
                        AND IsActive = true
                        AND Email != null
                    ORDER BY Email
                ]) {
                    emailByUserId.put(queueUser.Id, queueUser.Email);
                }
            }

            for (Id queueId : userIdsByQueueId.keySet()) {
                Set<String> emailAddresses = new Set<String>();
                for (Id userId : userIdsByQueueId.get(queueId)) {
                    String emailAddress = emailByUserId.get(userId);
                    if (String.isNotBlank(emailAddress)) {
                        emailAddresses.add(emailAddress);
                    }
                }
                if (!emailAddresses.isEmpty()) {
                    List<String> recipients = new List<String>(emailAddresses);
                    recipients.sort();
                    recipientEmailsByOwnerId.put(queueId, recipients);
                }
            }
        }

        if (!userOwnerIds.isEmpty()) {
            for (User ownerUser : [
                SELECT Id, Email
                FROM User
                WHERE Id IN :userOwnerIds
                    AND IsActive = true
                    AND Email != null
                ORDER BY Email
            ]) {
                recipientEmailsByOwnerId.put(ownerUser.Id, new List<String>{ ownerUser.Email });
            }
        }

        return recipientEmailsByOwnerId;
    }

    @TestVisible
    private static void sendEscalationEmails(
        List<Case> escalatedCases,
        Map<Id, List<String>> recipientEmailsByOwnerId,
        Set<Id> breachedCaseIds,
        Id escalationTemplateId,
        Id breachTemplateId,
        Id orgWideEmailAddressId
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Case escalatedCase : escalatedCases) {
            Id templateId = breachedCaseIds.contains(escalatedCase.Id) && breachTemplateId != null
                ? breachTemplateId
                : escalationTemplateId;
            if (templateId == null) {
                continue;
            }
            List<String> recipientEmails = recipientEmailsByOwnerId.get(escalatedCase.OwnerId);
            if (recipientEmails == null || recipientEmails.isEmpty()) {
                continue;
            }
            Messaging.SingleEmailMessage email =
                Messaging.renderStoredEmailTemplate(templateId, null, escalatedCase.Id);
            email.setToAddresses(recipientEmails);
            email.setSaveAsActivity(false);
            if (orgWideEmailAddressId != null) {
                email.setOrgWideEmailAddressId(orgWideEmailAddressId);
            }
            emails.add(email);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }
}