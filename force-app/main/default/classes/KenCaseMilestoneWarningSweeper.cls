public without sharing class KenCaseMilestoneWarningSweeper implements Schedulable {
    @TestVisible
    private static final String JOB_NAME_PREFIX = 'Ken Case Milestone Warning Sweeper';
    @TestVisible
    private static final String JOB_NAME_LIKE = 'Ken Case Milestone Warning Sweeper%';

    // 4 fixed scheduled jobs fire every hour at minutes 0/15/30/45 — combined cadence = 15 minutes.
    @TestVisible
    private static final List<Integer> SCHEDULE_MINUTES = new List<Integer>{0, 15, 30, 45};

    // Lead time before TargetDate that we look ahead. With WINDOW_MINUTES = 15 and
    // WARNING_LEAD_MINUTES = 60, each run catches milestones whose TargetDate falls
    // in [now + 60, now + 75) — so warnings go out 60-75 minutes before SLA breach,
    // exactly once per milestone (the four 15-min windows tile [60,75), [75,90), ... non-overlappingly).
    @TestVisible
    private static final Integer WARNING_LEAD_MINUTES = 60;
    @TestVisible
    private static final Integer WINDOW_MINUTES = 15;

    private static final String WARNING_TEMPLATE_DEVELOPER_NAME = KenSnSConstants.EMAIL_TEMPLATE_CASE_MILESTONE_WARNING;

    @TestVisible
    private static List<CaseMilestone> milestoneQueryOverride;

    /**
     * Idempotent reset of the sweeper schedule. Aborts every existing sweeper
     * cron job, then schedules 4 fresh recurring jobs at minutes 0/15/30/45 of
     * every hour. Always leaves exactly 4 active scheduled jobs in the org.
     */
    public static List<Id> resetSchedule() {
        for (CronTrigger ct : [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :JOB_NAME_LIKE
                AND State NOT IN ('COMPLETE', 'DELETED', 'ERROR')
        ]) {
            try {
                System.abortJob(ct.Id);
            } catch (Exception ignored) {
                // already aborted/completed in a race — safe to ignore
            }
        }

        List<Id> jobIds = new List<Id>();
        for (Integer minute : SCHEDULE_MINUTES) {
            String cron = '0 ' + minute + ' * * * ?';
            String paddedMinute = minute < 10 ? '0' + String.valueOf(minute) : String.valueOf(minute);
            String name = JOB_NAME_PREFIX + ' :' + paddedMinute;
            jobIds.add(System.schedule(name, cron, new KenCaseMilestoneWarningSweeper()));
        }
        return jobIds;
    }

    public void execute(SchedulableContext context) {
        if (KenSnSConstants.isMilestoneWarningEmailBypassed()) return;
        sendWarningsForWindow(System.now());
    }

    @TestVisible
    static void sendWarningsForWindow(Datetime referenceTime) {
        Datetime targetStart = referenceTime.addMinutes(WARNING_LEAD_MINUTES);
        Datetime targetEnd = referenceTime.addMinutes(WARNING_LEAD_MINUTES + WINDOW_MINUTES);

        List<CaseMilestone> dueMilestones;
        if (Test.isRunningTest() && milestoneQueryOverride != null) {
            dueMilestones = milestoneQueryOverride;
        } else {
            dueMilestones = [
                SELECT Id, CaseId, TargetDate
                FROM CaseMilestone
                WHERE TargetDate >= :targetStart
                    AND TargetDate < :targetEnd
                    AND IsCompleted = false
                    AND IsViolated = false
            ];
        }
        if (dueMilestones == null || dueMilestones.isEmpty()) {
            return;
        }

        Set<Id> caseIds = new Set<Id>();
        for (CaseMilestone milestone : dueMilestones) {
            if (milestone.CaseId != null) {
                caseIds.add(milestone.CaseId);
            }
        }
        if (caseIds.isEmpty()) {
            return;
        }

        Map<Id, Case> openCasesById = new Map<Id, Case>([
            SELECT Id, OwnerId, IsClosed, IsEscalated
            FROM Case
            WHERE Id IN :caseIds
        ]);

        Set<Id> ownerIds = new Set<Id>();
        for (Case caseRecord : openCasesById.values()) {
            if (!caseRecord.IsClosed && !caseRecord.IsEscalated && caseRecord.OwnerId != null) {
                ownerIds.add(caseRecord.OwnerId);
            }
        }
        if (ownerIds.isEmpty()) {
            return;
        }

        Id templateId = getTemplateIdByDeveloperName(WARNING_TEMPLATE_DEVELOPER_NAME);
        if (templateId == null) {
            return;
        }

        Map<Id, List<String>> recipientEmailsByOwnerId =
            KenCaseEscalationEmailTriggerHandler.getRecipientEmailsByOwnerId(ownerIds);
        if (recipientEmailsByOwnerId.isEmpty()) {
            return;
        }

        Id orgWideEmailAddressId = getOrgWideEmailAddressId();

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (CaseMilestone milestone : dueMilestones) {
            Case parent = openCasesById.get(milestone.CaseId);
            if (parent == null || parent.IsClosed || parent.IsEscalated || parent.OwnerId == null) {
                continue;
            }
            List<String> recipientEmails = recipientEmailsByOwnerId.get(parent.OwnerId);
            if (recipientEmails == null || recipientEmails.isEmpty()) {
                continue;
            }
            Messaging.SingleEmailMessage email =
                Messaging.renderStoredEmailTemplate(templateId, null, parent.Id);
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

    private static Id getTemplateIdByDeveloperName(String developerName) {
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
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
}