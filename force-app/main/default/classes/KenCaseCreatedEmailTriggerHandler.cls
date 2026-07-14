public without sharing class KenCaseCreatedEmailTriggerHandler {
    private static final String CASE_CREATED_OWNER_TEMPLATE_DEVELOPER_NAME = KenSnSConstants.EMAIL_TEMPLATE_CASE_CREATED_OWNER;
    private static final String CASE_CREATED_USER_TEMPLATE_DEVELOPER_NAME = KenSnSConstants.EMAIL_TEMPLATE_CASE_CREATED_USER;

    public static void handleAfterInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) return;
        // Skip only if BOTH owner and user emails are bypassed
        if (KenSnSConstants.isCaseOwnerEmailBypassed() && KenSnSConstants.isCaseUserEmailBypassed()) return;

        Set<Id> caseIds = new Map<Id, Case>(newCases).keySet();

        // Try async first; fall back to sync if already in async context
        if (!shouldSkipContext()) {
            System.enqueueJob(new KenCaseCreatedEmailQueueable(caseIds));
        } else {
            // Running inside a Queueable/Future/Batch — send synchronously
            sendEmailsForCaseIds(caseIds);
        }
    }

    @TestVisible
    public static void sendEmailsForCaseIds(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;
        try {
            List<Case> casesToNotify = [
                SELECT Id, OwnerId, SuppliedEmail, Account.PersonEmail, CreatedBy.Email
                FROM Case
                WHERE Id IN :caseIds
            ];
            if (casesToNotify.isEmpty()) return;

            Map<String, Id> templateIds = getTemplateIdsByDeveloperName(
                new Set<String>{ CASE_CREATED_OWNER_TEMPLATE_DEVELOPER_NAME, CASE_CREATED_USER_TEMPLATE_DEVELOPER_NAME }
            );
            Id ownerTemplateId = templateIds.get(CASE_CREATED_OWNER_TEMPLATE_DEVELOPER_NAME);
            Id userTemplateId  = templateIds.get(CASE_CREATED_USER_TEMPLATE_DEVELOPER_NAME);
            if (ownerTemplateId == null && userTemplateId == null) return;

            Set<Id> ownerIds = new Set<Id>();
            for (Case c : casesToNotify) {
                if (c.OwnerId != null) ownerIds.add(c.OwnerId);
            }

            Map<Id, List<String>> recipientEmailsByOwnerId = getRecipientEmailsByOwnerId(ownerIds);
            Id orgWideEmailId = getOrgWideEmailAddressId();

            sendCaseCreatedEmails(casesToNotify, recipientEmailsByOwnerId, userTemplateId, ownerTemplateId, orgWideEmailId);
        } catch (Exception ignored) {}
    }

    // Handles owner re-assignment after case creation (e.g. manual reassignment or escalation).
    // New cases no longer need this for initial owner notification since OwnerId is
    // set correctly at insert time by the before-insert trigger.
    public static void handleAfterUpdate(List<Case> newCases, Map<Id, Case> oldCaseById) {
        if (shouldSkipContext() || newCases == null || newCases.isEmpty()) {
            return;
        }
        if (KenSnSConstants.isCaseOwnerEmailBypassed() && KenSnSConstants.isCaseUserEmailBypassed()) return;

        // Find cases where OwnerId just changed (to queue OR user) on a recently created case.
        // Covers both: standard assignment rules (queue) and round-robin helper (user).
        Set<Id> caseIds = new Set<Id>();
        Datetime fiveMinutesAgo = System.now().addMinutes(-5);
        for (Case newCase : newCases) {
            Case oldCase = oldCaseById != null ? oldCaseById.get(newCase.Id) : null;
            if (oldCase == null) continue;
            Boolean ownerChanged = oldCase.OwnerId != newCase.OwnerId;
            Boolean recentlyCreated = newCase.CreatedDate != null && newCase.CreatedDate >= fiveMinutesAgo;
            if (ownerChanged && recentlyCreated) {
                caseIds.add(newCase.Id);
            }
        }
        if (caseIds.isEmpty()) return;

        List<Case> casesToNotify = [
            SELECT Id, OwnerId, SuppliedEmail, Account.PersonEmail, CreatedBy.Email
            FROM Case
            WHERE Id IN :caseIds
        ];
        if (casesToNotify.isEmpty()) return;

        Id ownerTemplateId = getTemplateIdsByDeveloperName(
            new Set<String>{ CASE_CREATED_OWNER_TEMPLATE_DEVELOPER_NAME }
        ).get(CASE_CREATED_OWNER_TEMPLATE_DEVELOPER_NAME);
        if (ownerTemplateId == null) return;

        Set<Id> ownerIds = new Set<Id>();
        for (Case c : casesToNotify) {
            if (c.OwnerId != null) ownerIds.add(c.OwnerId);
        }
        Map<Id, List<String>> recipientEmailsByOwnerId = getRecipientEmailsByOwnerId(ownerIds);

        // Send only the owner notification — user email was already sent on insert
        sendCaseCreatedEmails(
            casesToNotify,
            recipientEmailsByOwnerId,
            null,
            ownerTemplateId,
            getOrgWideEmailAddressId()
        );
    }

    private static Boolean shouldSkipContext() {
        return System.isBatch()
            || System.isFuture()
            || System.isQueueable()
            || System.isScheduled();
    }

    @TestVisible
    private static Set<Id> getQueueOwnerIds(List<Case> cases) {
        Set<Id> queueOwnerIds = new Set<Id>();
        for (Case caseRecord : cases) {
            if (caseRecord.OwnerId != null && String.valueOf(caseRecord.OwnerId).startsWith('00G')) {
                queueOwnerIds.add(caseRecord.OwnerId);
            }
        }
        return queueOwnerIds;
    }

    @TestVisible
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
            recipientEmailsByOwnerId.putAll(getQueueMemberEmailsByQueueId(queueIds));
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
    private static Map<Id, List<String>> getQueueMemberEmailsByQueueId(Set<Id> queueIds) {
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

        if (userIds.isEmpty()) {
            return new Map<Id, List<String>>();
        }

        Map<Id, String> emailByUserId = new Map<Id, String>();
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

        Map<Id, List<String>> recipientEmailsByQueueId = new Map<Id, List<String>>();
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
                recipientEmailsByQueueId.put(queueId, recipients);
            }
        }

        return recipientEmailsByQueueId;
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

    @TestVisible
    private static String getRequesterEmail(Case caseRecord) {
        if (caseRecord == null) {
            return null;
        }
        if (caseRecord.Account != null && String.isNotBlank(caseRecord.Account.PersonEmail)) {
            return caseRecord.Account.PersonEmail;
        }
        if (String.isNotBlank(caseRecord.SuppliedEmail)) {
            return caseRecord.SuppliedEmail;
        }
        if (caseRecord.CreatedBy != null && String.isNotBlank(caseRecord.CreatedBy.Email)) {
            return caseRecord.CreatedBy.Email;
        }
        return null;
    }

    @TestVisible
    public static void sendCaseCreatedEmails(
        List<Case> newCases,
        Map<Id, List<String>> recipientEmailsByOwnerId,
        Id userTemplateId,
        Id ownerTemplateId,
        Id orgWideEmailAddressId
    ) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Boolean ownerBypassed = KenSnSConstants.isCaseOwnerEmailBypassed();
        Boolean userBypassed  = KenSnSConstants.isCaseUserEmailBypassed();
        for (Case caseRecord : newCases) {
            // Owner email — respect Case_Owner_Email_Bypass__c
            if (!ownerBypassed) {
                List<String> ownerRecipientEmails = recipientEmailsByOwnerId.get(caseRecord.OwnerId);
                if (ownerTemplateId != null && ownerRecipientEmails != null && !ownerRecipientEmails.isEmpty()) {
                    Messaging.SingleEmailMessage ownerEmail =
                        Messaging.renderStoredEmailTemplate(ownerTemplateId, null, caseRecord.Id);
                    ownerEmail.setToAddresses(ownerRecipientEmails);
                    ownerEmail.setSaveAsActivity(false);
                    if (orgWideEmailAddressId != null) {
                        ownerEmail.setOrgWideEmailAddressId(orgWideEmailAddressId);
                    }
                    emails.add(ownerEmail);
                }
            }

            // User/Student email — respect Case_User_Email_Bypass__c
            if (!userBypassed) {
                String requesterEmail = getRequesterEmail(caseRecord);
                if (userTemplateId != null && String.isNotBlank(requesterEmail)) {
                    Id contactId = caseRecord.ContactId != null ? caseRecord.ContactId
                        : (caseRecord.Account != null ? caseRecord.Account.PersonContactId : null);
                    Messaging.SingleEmailMessage userEmail =
                        Messaging.renderStoredEmailTemplate(userTemplateId, contactId, caseRecord.Id);
                    if (contactId != null) {
                        userEmail.setTargetObjectId(contactId);
                        userEmail.setWhatId(caseRecord.Id);
                        userEmail.setSaveAsActivity(true);
                    } else {
                        userEmail.setToAddresses(new List<String>{ requesterEmail });
                        userEmail.setSaveAsActivity(false);
                    }
                    if (orgWideEmailAddressId != null) {
                        userEmail.setOrgWideEmailAddressId(orgWideEmailAddressId);
                    }
                    emails.add(userEmail);
                }
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }
}