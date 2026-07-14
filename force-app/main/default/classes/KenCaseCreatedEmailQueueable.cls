/**
 * KenCaseCreatedEmailQueueable
 *
 * Sends case-created notification emails asynchronously so that the
 * case INSERT transaction completes immediately and the student sees
 * the success message without waiting for email rendering/sending.
 *
 * Enqueued from KenCaseCreatedEmailTriggerHandler.handleAfterInsert.
 */
public class KenCaseCreatedEmailQueueable implements Queueable {

    private final Set<Id> caseIds;

    public KenCaseCreatedEmailQueueable(Set<Id> caseIds) {
        this.caseIds = caseIds;
    }

    public void execute(QueueableContext ctx) {
        if (caseIds == null || caseIds.isEmpty()) return;
        if (KenSnSConstants.isCaseOwnerEmailBypassed() && KenSnSConstants.isCaseUserEmailBypassed()) return;

        List<Case> casesToNotify = [
            SELECT Id, OwnerId, SuppliedEmail, Account.PersonEmail, CreatedBy.Email,
                   ContactId, Account.PersonContactId
            FROM Case
            WHERE Id IN :caseIds
        ];
        if (casesToNotify.isEmpty()) return;

        Map<String, Id> templateIdsByDeveloperName = getTemplateIdsByDeveloperName(
            new Set<String>{
                KenSnSConstants.EMAIL_TEMPLATE_CASE_CREATED_OWNER,
                KenSnSConstants.EMAIL_TEMPLATE_CASE_CREATED_USER
            }
        );
        Id ownerTemplateId = templateIdsByDeveloperName.get(KenSnSConstants.EMAIL_TEMPLATE_CASE_CREATED_OWNER);
        Id userTemplateId  = templateIdsByDeveloperName.get(KenSnSConstants.EMAIL_TEMPLATE_CASE_CREATED_USER);
        if (ownerTemplateId == null && userTemplateId == null) return;

        Set<Id> ownerIds = new Set<Id>();
        for (Case c : casesToNotify) {
            if (c.OwnerId != null) ownerIds.add(c.OwnerId);
        }

        Map<Id, List<String>> recipientEmailsByOwnerId = KenCaseCreatedEmailTriggerHandler.getRecipientEmailsByOwnerId(ownerIds);
        Id orgWideEmailId = getOrgWideEmailAddressId();

        KenCaseCreatedEmailTriggerHandler.sendCaseCreatedEmails(
            casesToNotify,
            recipientEmailsByOwnerId,
            userTemplateId,
            ownerTemplateId,
            orgWideEmailId
        );
    }

    private static Map<String, Id> getTemplateIdsByDeveloperName(Set<String> developerNames) {
        Map<String, Id> result = new Map<String, Id>();
        for (EmailTemplate t : [
            SELECT Id, DeveloperName FROM EmailTemplate WHERE DeveloperName IN :developerNames
        ]) {
            result.put(t.DeveloperName, t.Id);
        }
        return result;
    }

    private static Id getOrgWideEmailAddressId() {
        String displayName = KenSnSConstants.getOrgWideEmailDisplayName();
        if (String.isBlank(displayName)) return null;
        List<OrgWideEmailAddress> addrs = [
            SELECT Id FROM OrgWideEmailAddress
            WHERE DisplayName = :displayName
            LIMIT 1
        ];
        return addrs.isEmpty() ? null : addrs[0].Id;
    }
}