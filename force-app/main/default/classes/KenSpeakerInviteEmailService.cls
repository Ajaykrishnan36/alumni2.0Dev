/**
 * KenSpeakerInviteEmailService
 * ----------------------------
 * Sends the "invite to speak" email to event speakers once their event is
 * approved. Mirrors the org's other transactional sends: a stored EmailTemplate
 * rendered with custom {Token} merge fields, the "Alumni Management" org-wide
 * address, and a bypass switch on Alumni_Email_Settings__c.
 *
 * Only speakers flagged Send_Invite__c (with an email, not yet sent) are emailed.
 */
public without sharing class KenSpeakerInviteEmailService {

    private static final String SPEAKER_RT = 'Speaker_Enrollment';
    private static final String TEMPLATE_DEV_NAME = 'Speaker_Invite';
    private static final String ORG_WIDE_NAME = 'Alumni Management';

    /** Enqueue (async) from the event-approval trigger. */
    public static void enqueueForEvents(Set<Id> eventIds) {
        if (eventIds == null || eventIds.isEmpty() || isBypassed()) {
            return;
        }
        // If we're already in an async context, send inline; otherwise queue it.
        if (System.isQueueable() || System.isFuture() || System.isBatch()) {
            sendInvitesForEvents(eventIds);
        } else {
            System.enqueueJob(new InviteQueueable(eventIds));
        }
    }

    private static Boolean isBypassed() {
        Alumni_Email_Settings__c s = Alumni_Email_Settings__c.getOrgDefaults();
        return s != null && s.Bypass_Speaker_Invite_Email__c == true;
    }

    public static void sendInvitesForEvents(Set<Id> eventIds) {
        if (eventIds == null || eventIds.isEmpty() || isBypassed()) {
            return;
        }

        List<Ken_Events_Sessions_Enrollment__c> speakers = [
            SELECT Id, Speaker_Name__c, Speaker_Email__c,
                   Event_Reference__r.Name, Schedule_Sessions__r.Name
            FROM Ken_Events_Sessions_Enrollment__c
            WHERE RecordType.DeveloperName = :SPEAKER_RT
              AND Event_Reference__c IN :eventIds
              AND Send_Invite__c = true
              AND Invite_Email_Sent__c = false
              AND Speaker_Email__c != null
        ];
        if (speakers.isEmpty()) {
            return;
        }

        List<EmailTemplate> tpls = [
            SELECT Id, Subject, HtmlValue, Body
            FROM EmailTemplate WHERE DeveloperName = :TEMPLATE_DEV_NAME LIMIT 1
        ];
        if (tpls.isEmpty()) {
            return;
        }
        EmailTemplate tpl = tpls[0];

        List<OrgWideEmailAddress> owe = [
            SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = :ORG_WIDE_NAME LIMIT 1
        ];
        Id oweId = owe.isEmpty() ? null : owe[0].Id;
        String alias = getInstitutionAlias();
        String tplBody = String.isNotBlank(tpl.HtmlValue) ? tpl.HtmlValue : tpl.Body;

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Ken_Events_Sessions_Enrollment__c> toMark = new List<Ken_Events_Sessions_Enrollment__c>();

        for (Ken_Events_Sessions_Enrollment__c sp : speakers) {
            String eventName = sp.Event_Reference__r != null ? sp.Event_Reference__r.Name : '';
            String sessionName = sp.Schedule_Sessions__r != null ? sp.Schedule_Sessions__r.Name : '';
            String speakerName = String.isNotBlank(sp.Speaker_Name__c) ? sp.Speaker_Name__c : 'there';

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { sp.Speaker_Email__c });
            mail.setSubject(mergeTokens(tpl.Subject, speakerName, eventName, sessionName, alias));
            mail.setHtmlBody(mergeTokens(tplBody, speakerName, eventName, sessionName, alias));
            if (oweId != null) {
                mail.setOrgWideEmailAddressId(oweId);
            }
            mail.setSaveAsActivity(false);
            emails.add(mail);
            toMark.add(new Ken_Events_Sessions_Enrollment__c(Id = sp.Id, Invite_Email_Sent__c = true));
        }

        if (emails.isEmpty()) {
            return;
        }
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
        List<Ken_Events_Sessions_Enrollment__c> sentOk = new List<Ken_Events_Sessions_Enrollment__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                sentOk.add(toMark[i]);
            }
        }
        if (!sentOk.isEmpty()) {
            update sentOk;
        }
    }

    private static String mergeTokens(String input, String speaker, String eventName, String session, String alias) {
        if (input == null) {
            return '';
        }
        return input
            .replace('{Speaker_Name}', speaker == null ? '' : speaker)
            .replace('{Event_Name}', eventName == null ? '' : eventName)
            .replace('{Session_Name}', session == null ? '' : session)
            .replace('{Institution_Alias}', alias == null ? '' : alias);
    }

    private static String getInstitutionAlias() {
        try {
            Alumni_Org_Parameters__c p = Alumni_Org_Parameters__c.getInstance();
            if (p != null && String.isNotBlank(p.Institution_Alias__c)) {
                return p.Institution_Alias__c;
            }
        } catch (Exception e) {
            /* fall through */
        }
        return 'the Alumni Office';
    }

    public class InviteQueueable implements Queueable {
        private Set<Id> eventIds;
        public InviteQueueable(Set<Id> ids) {
            this.eventIds = ids;
        }
        public void execute(QueueableContext ctx) {
            KenSpeakerInviteEmailService.sendInvitesForEvents(eventIds);
        }
    }
}