/**
 * KenCommunicationController
 *
 * Single class for the email communication feature. Backend for the
 * kenCommunications LWC plus the chained queueable that sends each campaign.
 *
 * Bulk email campaigns are stored as a single custom object (Ken_Email_Campaign__c) —
 * NO per-recipient custom records. Recipients are captured as an Account-Id snapshot
 * on the campaign and sent via setTargetObjectId so Salesforce logs each send as an
 * activity (EmailMessage) against the campaign, performs native open tracking
 * (EmailStatus) and bounce handling (Account.PersonEmailBouncedDate).
 *
 * Personalisation tokens in subject/body: {{FirstName}}, {{LastName}},
 * {{FullName}}, {{Email}}.
 */
public with sharing class KenCommunicationController {

    @TestVisible private static Integer BATCH_SIZE = 90;

    // ============================================================
    // DTOs
    // ============================================================

    public class SegmentationOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Datetime lastModified;
        @AuraEnabled public Integer memberCount;
    }

    public class CampaignDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String status;
        @AuraEnabled public Id segmentationId;
        @AuraEnabled public String segmentationName;
        @AuraEnabled public Integer totalRecipients;
        @AuraEnabled public Integer sentCount;
        @AuraEnabled public Integer deliveredCount;
        @AuraEnabled public Integer openedCount;
        @AuraEnabled public Integer bouncedCount;
        @AuraEnabled public Integer failedCount;
        @AuraEnabled public Datetime sentDateTime;
        @AuraEnabled public Datetime scheduledDateTime;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String fromName;
        @AuraEnabled public String fromAddress;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Decimal deliveryRate;
        @AuraEnabled public Decimal openRate;
        @AuraEnabled public Decimal bounceRate;
    }

    public class RecipientDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime sentDateTime;
        @AuraEnabled public Datetime openedDateTime;
        @AuraEnabled public String error;
    }

    // ============================================================
    // Segmentations
    // ============================================================

    @AuraEnabled(cacheable=true)
    public static List<SegmentationOption> listSegmentations(String searchTerm) {
        List<SegmentationOption> out = new List<SegmentationOption>();
        String term = String.isBlank(searchTerm) ? '' : '%' + searchTerm.trim() + '%';
        String soql = 'SELECT Id, Name, Active__c, LastModifiedDate FROM Ken_Segmentation__c';
        if (!String.isBlank(term)) soql += ' WHERE Name LIKE :term';
        soql += ' ORDER BY LastModifiedDate DESC LIMIT 100';
        for (Ken_Segmentation__c s : (List<Ken_Segmentation__c>)Database.query(soql)) {
            SegmentationOption opt = new SegmentationOption();
            opt.id = s.Id;
            opt.name = s.Name;
            opt.active = s.Active__c == true;
            opt.status = s.Active__c == true ? 'Active' : 'Draft';
            opt.lastModified = s.LastModifiedDate;
            out.add(opt);
        }
        return out;
    }

    @AuraEnabled
    public static Integer previewSegmentationCount(Id segmentationId) {
        if (segmentationId == null) return 0;
        return KenAudienceEngineService.resolveSegmentationAccountIds(segmentationId).size();
    }

    // ============================================================
    // Campaigns
    // ============================================================

    @AuraEnabled
    public static Id saveDraftCampaign(Id campaignId, String name, String subject, String body,
                                        Id segmentationId, String fromName, String fromAddress) {
        Ken_Email_Campaign__c c;
        if (campaignId != null) {
            c = new Ken_Email_Campaign__c(Id = campaignId);
        } else {
            c = new Ken_Email_Campaign__c();
            c.Status__c = 'Draft';
        }
        if (!String.isBlank(name)) c.Name = name.left(80);
        c.Subject__c = String.isBlank(subject) ? null : subject.left(255);
        c.Body__c = body;
        c.Segmentation__c = segmentationId;
        c.From_Name__c = String.isBlank(fromName) ? null : fromName.left(120);
        c.From_Address__c = String.isBlank(fromAddress) ? null : fromAddress;
        upsert c;
        return c.Id;
    }

    @AuraEnabled
    public static Id sendCampaign(Id campaignId, Datetime scheduledFor) {
        if (campaignId == null) throw new AuraHandledException('Campaign Id is required.');
        Ken_Email_Campaign__c camp = [
            SELECT Id, Subject__c, Body__c, Status__c, Segmentation__c
            FROM Ken_Email_Campaign__c WHERE Id = :campaignId LIMIT 1
        ];
        if (camp.Status__c == 'Sending' || camp.Status__c == 'Sent') {
            throw new AuraHandledException('Campaign has already been sent or is sending.');
        }
        if (String.isBlank(camp.Subject__c)) throw new AuraHandledException('Subject is required before sending.');
        if (String.isBlank(camp.Body__c)) throw new AuraHandledException('Email body is required before sending.');
        if (camp.Segmentation__c == null) throw new AuraHandledException('Pick a segmentation before sending.');

        Set<Id> accountIds = KenAudienceEngineService.resolveSegmentationAccountIds(camp.Segmentation__c);
        if (accountIds.isEmpty()) throw new AuraHandledException('The selected segmentation has no recipients.');

        List<Id> sendable = new List<Id>();
        for (Account a : [
            SELECT Id FROM Account
            WHERE Id IN :accountIds AND IsPersonAccount = true AND PersonEmail != null
        ]) {
            sendable.add(a.Id);
        }
        if (sendable.isEmpty()) {
            throw new AuraHandledException('No alumni in this segmentation have a usable email address.');
        }

        camp.Total_Recipients__c = sendable.size();
        camp.Audience_Snapshot_JSON__c = JSON.serialize(new Map<String, Object>{
            'accountIds' => sendable,
            'snapshotAt' => Datetime.now()
        }).left(131000);
        camp.Sent_Count__c = 0;
        camp.Delivered_Count__c = 0;
        camp.Bounced_Count__c = 0;
        camp.Failed_Count__c = 0;
        camp.Error_Message__c = null;

        if (scheduledFor != null && scheduledFor > Datetime.now()) {
            camp.Status__c = 'Scheduled';
            camp.Scheduled_DateTime__c = scheduledFor;
            update camp;
            return camp.Id;
        }
        camp.Status__c = 'Sending';
        update camp;
        if (!Test.isRunningTest()) {
            System.enqueueJob(new SendQueueable(camp.Id, 0));
        }
        return camp.Id;
    }

    @AuraEnabled
    public static CampaignDTO getCampaign(Id campaignId) {
        Ken_Email_Campaign__c c = [
            SELECT Id, Name, Subject__c, Body__c, Status__c, Segmentation__c, Segmentation__r.Name,
                   Total_Recipients__c, Sent_Count__c, Delivered_Count__c,
                   Bounced_Count__c, Failed_Count__c, Sent_DateTime__c, Scheduled_DateTime__c,
                   CreatedDate, From_Name__c, From_Address__c, Error_Message__c
            FROM Ken_Email_Campaign__c WHERE Id = :campaignId LIMIT 1
        ];
        CampaignDTO d = toCampaignDTO(c);
        d.openedCount = countOpeners(campaignId);
        Integer denom = d.totalRecipients == null ? 0 : d.totalRecipients;
        d.openRate = denom == 0 ? 0 : ((Decimal)d.openedCount / denom * 100).setScale(1);
        return d;
    }

    @AuraEnabled(cacheable=true)
    public static List<CampaignDTO> listCampaigns(String status, Integer limitSize) {
        Integer cap = (limitSize == null || limitSize <= 0) ? 50 : Math.min(limitSize, 200);
        String soql =
            'SELECT Id, Name, Subject__c, Body__c, Status__c, Segmentation__c, Segmentation__r.Name,' +
            ' Total_Recipients__c, Sent_Count__c, Delivered_Count__c,' +
            ' Bounced_Count__c, Failed_Count__c, Sent_DateTime__c, Scheduled_DateTime__c,' +
            ' CreatedDate, From_Name__c, From_Address__c, Error_Message__c FROM Ken_Email_Campaign__c';
        if (!String.isBlank(status)) soql += ' WHERE Status__c = :status';
        soql += ' ORDER BY CreatedDate DESC LIMIT ' + cap;
        List<CampaignDTO> out = new List<CampaignDTO>();
        for (Ken_Email_Campaign__c c : (List<Ken_Email_Campaign__c>)Database.query(soql)) {
            out.add(toCampaignDTO(c));
        }
        return out;
    }

    @AuraEnabled
    public static List<RecipientDTO> listCampaignRecipients(Id campaignId, String statusFilter, Integer limitSize) {
        if (campaignId == null) return new List<RecipientDTO>();
        Integer cap = (limitSize == null || limitSize <= 0) ? 500 : Math.min(limitSize, 2000);

        Ken_Email_Campaign__c camp = [
            SELECT Id, Sent_DateTime__c, Audience_Snapshot_JSON__c
            FROM Ken_Email_Campaign__c WHERE Id = :campaignId LIMIT 1
        ];
        Map<Id, Datetime> openedByContact = openedDateByContact(campaignId);

        List<RecipientDTO> fromActivity = recipientsFromEmailMessages(campaignId, camp.Sent_DateTime__c, openedByContact, cap);
        List<RecipientDTO> rows = !fromActivity.isEmpty()
            ? fromActivity
            : recipientsFromSnapshot(camp, openedByContact, cap);

        if (String.isBlank(statusFilter)) return rows;
        List<RecipientDTO> filtered = new List<RecipientDTO>();
        for (RecipientDTO d : rows) {
            if (statusFilter == d.status) filtered.add(d);
        }
        return filtered;
    }

    // ============================================================
    // Send pipeline — chained queueable, BATCH_SIZE slices keyed by offset
    // ============================================================

    public without sharing class SendQueueable implements Queueable {
        private final Id campaignId;
        private final Integer offset;

        public SendQueueable(Id campaignId) {
            this(campaignId, 0);
        }

        public SendQueueable(Id campaignId, Integer offset) {
            this.campaignId = campaignId;
            this.offset = (offset == null || offset < 0) ? 0 : offset;
        }

        public void execute(QueueableContext ctx) {
            if (campaignId == null) return;
            Ken_Email_Campaign__c camp;
            try {
                camp = [
                    SELECT Id, Name, Subject__c, Body__c, From_Name__c, Status__c,
                           Sent_Count__c, Delivered_Count__c, Bounced_Count__c,
                           Failed_Count__c, Total_Recipients__c, Sent_DateTime__c,
                           Audience_Snapshot_JSON__c
                    FROM Ken_Email_Campaign__c WHERE Id = :campaignId LIMIT 1
                ];
            } catch (Exception e) {
                return;
            }
            if (camp.Status__c == 'Cancelled') return;

            List<Id> accountIds = parseSnapshotAccountIds(camp.Audience_Snapshot_JSON__c);
            if (accountIds.isEmpty()) {
                finalizeCampaign(camp);
                return;
            }

            Integer endIdx = Math.min(offset + BATCH_SIZE, accountIds.size());
            if (offset >= accountIds.size()) {
                finalizeCampaign(camp);
                return;
            }
            List<Id> slice = new List<Id>();
            for (Integer i = offset; i < endIdx; i++) slice.add(accountIds[i]);

            Map<Id, Account> accts = new Map<Id, Account>([
                SELECT Id, Name, FirstName, LastName, PersonEmail, PersonContactId
                FROM Account WHERE Id IN :slice AND IsPersonAccount = true
            ]);

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            Integer skipped = 0;
            for (Id accId : slice) {
                Account a = accts.get(accId);
                if (a == null || a.PersonContactId == null || String.isBlank(a.PersonEmail)) {
                    skipped++;
                    continue;
                }
                Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
                msg.setTargetObjectId(a.PersonContactId);
                msg.setWhatId(campaignId);
                msg.setSaveAsActivity(true);
                msg.setUseSignature(false);
                msg.setTreatTargetObjectAsRecipient(true);
                msg.setSubject(personalise(camp.Subject__c, a));
                msg.setHtmlBody(personalise(camp.Body__c, a));
                if (!String.isBlank(camp.From_Name__c)) msg.setSenderDisplayName(camp.From_Name__c);
                emails.add(msg);
            }

            Integer sentDelta = 0, bouncedDelta = 0, failedDelta = skipped;
            if (!emails.isEmpty()) {
                List<Messaging.SendEmailResult> results;
                try {
                    results = Messaging.sendEmail(emails, false);
                } catch (Exception ex) {
                    failedDelta += emails.size();
                    results = null;
                }
                if (results != null) {
                    for (Messaging.SendEmailResult res : results) {
                        if (res.isSuccess()) {
                            sentDelta++;
                        } else {
                            Messaging.SendEmailError[] errs = res.getErrors();
                            String msg = (errs != null && !errs.isEmpty()) ? errs[0].getMessage() : '';
                            Boolean bounced = msg != null && (
                                msg.containsIgnoreCase('invalid') || msg.containsIgnoreCase('bounce') ||
                                msg.containsIgnoreCase('no recipient') || msg.containsIgnoreCase('not found')
                            );
                            if (bounced) { bouncedDelta++; } else { failedDelta++; }
                        }
                    }
                }
            }

            camp.Sent_Count__c      = nz(camp.Sent_Count__c)      + sentDelta;
            camp.Delivered_Count__c = nz(camp.Delivered_Count__c) + sentDelta;
            camp.Bounced_Count__c   = nz(camp.Bounced_Count__c)   + bouncedDelta;
            camp.Failed_Count__c    = nz(camp.Failed_Count__c)    + failedDelta;
            if (camp.Sent_DateTime__c == null && sentDelta > 0) camp.Sent_DateTime__c = Datetime.now();
            update camp;

            Boolean more = endIdx < accountIds.size();
            if (more && !Test.isRunningTest()) {
                System.enqueueJob(new SendQueueable(campaignId, endIdx));
            } else if (!more) {
                finalizeCampaign(camp);
            }
        }

        private void finalizeCampaign(Ken_Email_Campaign__c camp) {
            Integer total = nz(camp.Total_Recipients__c);
            Integer sent = nz(camp.Sent_Count__c);
            Integer failed = nz(camp.Failed_Count__c);
            String status;
            if (total == 0 || sent == 0) {
                status = 'Failed';
            } else if (failed == 0) {
                status = 'Sent';
            } else {
                status = 'Partially Sent';
            }
            camp.Status__c = status;
            if (camp.Sent_DateTime__c == null && sent > 0) camp.Sent_DateTime__c = Datetime.now();
            update camp;
        }
    }

    // ============================================================
    // Helpers (shared between LWC endpoints and the send queueable)
    // ============================================================

    public static List<Id> parseSnapshotAccountIds(String snapshotJson) {
        List<Id> out = new List<Id>();
        if (String.isBlank(snapshotJson)) return out;
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(snapshotJson);
            Object raw = m.get('accountIds');
            if (raw instanceof List<Object>) {
                for (Object o : (List<Object>) raw) {
                    if (o != null) out.add((Id) String.valueOf(o));
                }
            }
        } catch (Exception e) {
            // ignore malformed snapshot
        }
        return out;
    }

    @TestVisible
    private static String personalise(String tpl, Account a) {
        if (String.isBlank(tpl)) return tpl;
        String out = tpl;
        out = replaceToken(out, 'FirstName', a.FirstName);
        out = replaceToken(out, 'First Name', a.FirstName);
        out = replaceToken(out, 'LastName', a.LastName);
        out = replaceToken(out, 'Last Name', a.LastName);
        out = replaceToken(out, 'FullName', a.Name);
        out = replaceToken(out, 'Full Name', a.Name);
        out = replaceToken(out, 'Name', a.Name);
        out = replaceToken(out, 'Email', a.PersonEmail);
        return out;
    }

    private static String replaceToken(String s, String token, String value) {
        if (String.isBlank(s)) return s;
        String safe = value == null ? '' : value;
        String pat = '\\{\\{\\s*' + token.replace(' ', '\\s*') + '\\s*\\}\\}';
        return s.replaceAll(pat, safe.replace('\\', '\\\\').replace('$', '\\$'));
    }

    private static List<RecipientDTO> recipientsFromEmailMessages(
            Id campaignId, Datetime sentDt, Map<Id, Datetime> openedByContact, Integer cap) {
        List<RecipientDTO> out = new List<RecipientDTO>();
        List<EmailMessage> ems;
        try {
            ems = [
                SELECT ToAddress, MessageDate, ActivityId
                FROM EmailMessage
                WHERE RelatedToId = :campaignId
                ORDER BY MessageDate ASC
                LIMIT :cap
            ];
        } catch (Exception e) {
            return out;
        }
        if (ems.isEmpty()) return out;

        Set<Id> activityIds = new Set<Id>();
        for (EmailMessage em : ems) if (em.ActivityId != null) activityIds.add(em.ActivityId);

        Map<Id, Id> whoByActivity = new Map<Id, Id>();
        Map<Id, String> nameByActivity = new Map<Id, String>();
        Set<Id> whoIds = new Set<Id>();
        if (!activityIds.isEmpty()) {
            for (Task t : [SELECT Id, WhoId, Who.Name FROM Task WHERE Id IN :activityIds]) {
                whoByActivity.put(t.Id, t.WhoId);
                if (t.Who != null) nameByActivity.put(t.Id, t.Who.Name);
                if (t.WhoId != null) whoIds.add(t.WhoId);
            }
        }
        Map<Id, Account> acctByContact = new Map<Id, Account>();
        if (!whoIds.isEmpty()) {
            for (Account a : [
                SELECT Id, Name, PersonContactId, PersonEmailBouncedDate, PersonEmailBouncedReason
                FROM Account WHERE PersonContactId IN :whoIds
            ]) {
                acctByContact.put(a.PersonContactId, a);
            }
        }

        for (EmailMessage em : ems) {
            Id whoId = em.ActivityId != null ? whoByActivity.get(em.ActivityId) : null;
            Account a = whoId != null ? acctByContact.get(whoId) : null;
            Datetime openedAt = whoId != null ? openedByContact.get(whoId) : null;
            Boolean bounced = a != null && a.PersonEmailBouncedDate != null;
            RecipientDTO d = new RecipientDTO();
            d.id = em.Id;
            d.email = em.ToAddress;
            d.name = (em.ActivityId != null ? nameByActivity.get(em.ActivityId) : null);
            if (String.isBlank(d.name) && a != null) d.name = a.Name;
            d.sentDateTime = em.MessageDate != null ? em.MessageDate : sentDt;
            d.openedDateTime = openedAt;
            d.error = a != null ? a.PersonEmailBouncedReason : null;
            d.status = bounced ? 'Bounced' : (openedAt != null ? 'Opened' : 'Sent');
            out.add(d);
        }
        return out;
    }

    private static List<RecipientDTO> recipientsFromSnapshot(
            Ken_Email_Campaign__c camp, Map<Id, Datetime> openedByContact, Integer cap) {
        List<RecipientDTO> out = new List<RecipientDTO>();
        List<Id> accountIds = parseSnapshotAccountIds(camp.Audience_Snapshot_JSON__c);
        if (accountIds.isEmpty()) return out;
        for (Account a : [
            SELECT Id, Name, PersonEmail, PersonContactId, PersonEmailBouncedDate, PersonEmailBouncedReason
            FROM Account WHERE Id IN :accountIds
        ]) {
            Datetime openedAt = (a.PersonContactId != null) ? openedByContact.get(a.PersonContactId) : null;
            Boolean bounced = a.PersonEmailBouncedDate != null;
            RecipientDTO d = new RecipientDTO();
            d.id = a.Id;
            d.name = a.Name;
            d.email = a.PersonEmail;
            d.sentDateTime = camp.Sent_DateTime__c;
            d.openedDateTime = openedAt;
            d.error = a.PersonEmailBouncedReason;
            d.status = bounced ? 'Bounced' : (openedAt != null ? 'Opened' : 'Sent');
            out.add(d);
            if (out.size() >= cap) break;
        }
        return out;
    }

    private static Map<Id, Datetime> openedDateByContact(Id campaignId) {
        Map<Id, Datetime> out = new Map<Id, Datetime>();
        try {
            String soql = 'SELECT WhoId, TimesOpened, FirstOpenDate FROM EmailStatus WHERE Task.WhatId = :campaignId';
            for (SObject row : Database.query(soql)) {
                Id whoId = (Id) row.get('WhoId');
                if (whoId == null) continue;
                Object timesRaw = row.get('TimesOpened');
                Integer t = timesRaw == null ? 0 : Integer.valueOf(timesRaw);
                if (t <= 0) continue;
                Datetime fo = (Datetime) row.get('FirstOpenDate');
                Datetime existing = out.get(whoId);
                if (existing == null || (fo != null && fo < existing)) out.put(whoId, fo);
            }
        } catch (Exception e) {
            // Email tracking disabled — leave empty.
        }
        return out;
    }

    private static Integer countOpeners(Id campaignId) {
        return openedDateByContact(campaignId).size();
    }

    private static CampaignDTO toCampaignDTO(Ken_Email_Campaign__c c) {
        CampaignDTO d = new CampaignDTO();
        d.id = c.Id;
        d.name = c.Name;
        d.subject = c.Subject__c;
        d.body = c.Body__c;
        d.status = c.Status__c;
        d.segmentationId = c.Segmentation__c;
        d.segmentationName = c.Segmentation__r == null ? null : c.Segmentation__r.Name;
        d.totalRecipients = nz(c.Total_Recipients__c);
        d.sentCount      = nz(c.Sent_Count__c);
        d.deliveredCount = nz(c.Delivered_Count__c);
        d.openedCount    = 0;
        d.bouncedCount   = nz(c.Bounced_Count__c);
        d.failedCount    = nz(c.Failed_Count__c);
        d.sentDateTime = c.Sent_DateTime__c;
        d.scheduledDateTime = c.Scheduled_DateTime__c;
        d.createdDate = c.CreatedDate;
        d.fromName = c.From_Name__c;
        d.fromAddress = c.From_Address__c;
        d.errorMessage = c.Error_Message__c;
        Integer denom = d.totalRecipients;
        d.deliveryRate = denom == 0 ? 0 : ((Decimal)d.deliveredCount / denom * 100).setScale(1);
        d.openRate     = 0;
        d.bounceRate   = denom == 0 ? 0 : ((Decimal)d.bouncedCount   / denom * 100).setScale(1);
        return d;
    }

    private static Integer nz(Decimal d) { return d == null ? 0 : Integer.valueOf(d); }
}