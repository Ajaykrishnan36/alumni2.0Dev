/**
 * Materializer — promotes a confirmed edge contribution into the standard core
 * (Opportunity + OpportunityContactRole + Ken_Gift_Opportunity_Allocation__c).
 *
 * Invoked from KenGiftPaymentTriggerHandler the moment a Ken_Gift_Payment__c flips to
 * 'Captured'. Runs `without sharing` (system context) so the capturing user — typically
 * the gateway/integration user — drives standard-object creation that portal donors
 * could never perform.
 *
 * IDEMPOTENCY (webhook-retry safe):
 *   - Only contributions with Opportunity__c == null AND Status__c != 'Confirmed' are
 *     processed. Once materialized, the contribution carries its Opportunity Id, so any
 *     repeat 'Captured' event (retry, a second payment) is a no-op.
 *
 * DEDUPE: donors are matched/upserted to a Contact by Donor_Email__c (case-insensitive),
 * deduped within the batch, before any Contact is created.
 *
 * NOTE: the capturing user's profile must have the `Ken_Giving_Donation` record type
 * assigned (record-type availability is enforced on insert even in system context).
 */
public without sharing class KenGiftMaterializerService {

    private static final String DONATION_RT = 'Ken_Giving_Donation';
    private static final String STAGE_WON   = 'Closed Won';

    public class GiftMaterializerException extends Exception {}

    public static void materialize(Set<Id> contributionIds) {
        if (contributionIds == null || contributionIds.isEmpty()) return;

        List<Ken_Gift_Contribution__c> contribs = [
            SELECT Id, Amount__c, Donor_Email__c, Donor_First_Name__c, Donor_Last_Name__c,
                   Donor_Contact__c, Campaign__c, Campaign__r.Name, Is_Anonymous__c,
                   Status__c, Opportunity__c
            FROM Ken_Gift_Contribution__c
            WHERE Id IN :contributionIds
        ];

        // --- Idempotency gate ---
        List<Ken_Gift_Contribution__c> toProcess = new List<Ken_Gift_Contribution__c>();
        for (Ken_Gift_Contribution__c c : contribs) {
            if (c.Opportunity__c == null && c.Status__c != 'Confirmed') {
                toProcess.add(c);
            }
        }
        if (toProcess.isEmpty()) return;

        // --- 1) Resolve donor Contacts (match by email, else create) ---
        Map<Id, Id> contactByContribution = resolveContacts(toProcess);

        // --- 2) Build Opportunities ---
        Schema.RecordTypeInfo rtInfo =
            Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(DONATION_RT);
        if (rtInfo == null) {
            throw new GiftMaterializerException(
                'Opportunity record type "' + DONATION_RT + '" not found or not accessible to the running user.');
        }
        Id rtId = rtInfo.getRecordTypeId();

        Set<Id> contactIds = new Set<Id>(contactByContribution.values());
        Map<Id, Contact> contactsById = contactIds.isEmpty()
            ? new Map<Id, Contact>()
            : new Map<Id, Contact>([SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds]);

        Date closeDate = Date.today();
        Map<Id, Opportunity> oppByContribution = new Map<Id, Opportunity>();
        List<Opportunity> opps = new List<Opportunity>();

        for (Ken_Gift_Contribution__c c : toProcess) {
            Id contactId = contactByContribution.get(c.Id);
            Contact ct = (contactId != null) ? contactsById.get(contactId) : null;

            String donorName = ((c.Donor_First_Name__c != null ? c.Donor_First_Name__c + ' ' : '')
                + (c.Donor_Last_Name__c != null ? c.Donor_Last_Name__c : '')).trim();
            if (String.isBlank(donorName)) donorName = 'Donor';
            String campaignName = (c.Campaign__r != null && c.Campaign__r.Name != null)
                ? c.Campaign__r.Name : 'Giving';

            Opportunity o = new Opportunity();
            o.RecordTypeId = rtId;
            o.Name = (donorName + ' - ' + campaignName).left(120);
            o.StageName = STAGE_WON;
            o.CloseDate = closeDate;
            o.Amount = c.Amount__c;
            o.CampaignId = c.Campaign__c;
            if (ct != null && ct.AccountId != null) o.AccountId = ct.AccountId;
            o.Ken_Giving_Contribution__c = c.Id;
            o.Ken_Giving_Is_Anonymous__c = c.Is_Anonymous__c;

            opps.add(o);
            oppByContribution.put(c.Id, o);
        }
        insert opps;

        // --- 3) OpportunityContactRole (Donor, primary) ---
        List<OpportunityContactRole> ocrs = new List<OpportunityContactRole>();
        for (Ken_Gift_Contribution__c c : toProcess) {
            Id contactId = contactByContribution.get(c.Id);
            Opportunity o = oppByContribution.get(c.Id);
            if (contactId != null && o != null) {
                ocrs.add(new OpportunityContactRole(
                    OpportunityId = o.Id,
                    ContactId = contactId,
                    Role = 'Donor',
                    IsPrimary = true
                ));
            }
        }
        if (!ocrs.isEmpty()) insert ocrs;

        // --- 4) Clone edge allocations to the core (finance reporting) ---
        List<Ken_Gift_Allocation__c> edgeAllocs = [
            SELECT Id, Contribution__c, Fund__c, Amount__c
            FROM Ken_Gift_Allocation__c
            WHERE Contribution__c IN :oppByContribution.keySet()
        ];
        List<Ken_Gift_Opportunity_Allocation__c> coreAllocs = new List<Ken_Gift_Opportunity_Allocation__c>();
        for (Ken_Gift_Allocation__c a : edgeAllocs) {
            Opportunity o = oppByContribution.get(a.Contribution__c);
            if (o == null) continue;
            coreAllocs.add(new Ken_Gift_Opportunity_Allocation__c(
                Opportunity__c = o.Id,
                Fund__c = a.Fund__c,
                Amount__c = a.Amount__c,
                Source_Allocation__c = a.Id
            ));
        }
        if (!coreAllocs.isEmpty()) insert coreAllocs;

        // --- 5) Link + confirm the contributions ---
        List<Ken_Gift_Contribution__c> updates = new List<Ken_Gift_Contribution__c>();
        for (Ken_Gift_Contribution__c c : toProcess) {
            Opportunity o = oppByContribution.get(c.Id);
            Ken_Gift_Contribution__c u = new Ken_Gift_Contribution__c(Id = c.Id);
            u.Opportunity__c = o.Id;
            u.Status__c = 'Confirmed';
            Id contactId = contactByContribution.get(c.Id);
            if (contactId != null) u.Donor_Contact__c = contactId;
            updates.add(u);
        }
        update updates;
    }

    /**
     * Match each contribution to a Contact by Donor_Email__c (case-insensitive),
     * creating new Contacts only for emails with no existing match. Deduped within the
     * batch so two contributions sharing a new email map to a single Contact.
     */
    private static Map<Id, Id> resolveContacts(List<Ken_Gift_Contribution__c> contribs) {
        Map<Id, Id> result = new Map<Id, Id>();

        Set<String> emails = new Set<String>();
        for (Ken_Gift_Contribution__c c : contribs) {
            if (c.Donor_Contact__c == null && String.isNotBlank(c.Donor_Email__c)) {
                emails.add(c.Donor_Email__c.toLowerCase());
            }
        }

        Map<String, Id> contactIdByEmail = new Map<String, Id>();
        if (!emails.isEmpty()) {
            for (Contact ct : [SELECT Id, Email FROM Contact WHERE Email IN :emails]) {
                if (String.isNotBlank(ct.Email)) {
                    String k = ct.Email.toLowerCase();
                    if (!contactIdByEmail.containsKey(k)) contactIdByEmail.put(k, ct.Id);
                }
            }
        }

        // Queue creates (deduped by email; no-email donors always get a fresh Contact).
        Map<String, Contact> newByEmail = new Map<String, Contact>();
        Map<Id, Contact> noEmailByContrib = new Map<Id, Contact>();
        for (Ken_Gift_Contribution__c c : contribs) {
            if (c.Donor_Contact__c != null) { result.put(c.Id, c.Donor_Contact__c); continue; }
            String k = String.isNotBlank(c.Donor_Email__c) ? c.Donor_Email__c.toLowerCase() : null;
            if (k != null && contactIdByEmail.containsKey(k)) continue; // resolved in final pass
            if (k != null) {
                if (!newByEmail.containsKey(k)) newByEmail.put(k, buildContact(c));
            } else {
                noEmailByContrib.put(c.Id, buildContact(c));
            }
        }

        List<Contact> toInsert = new List<Contact>();
        toInsert.addAll(newByEmail.values());
        toInsert.addAll(noEmailByContrib.values());
        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (String k : newByEmail.keySet()) {
                contactIdByEmail.put(k, newByEmail.get(k).Id);
            }
        }

        // Final resolution
        for (Ken_Gift_Contribution__c c : contribs) {
            if (result.containsKey(c.Id)) continue;
            String k = String.isNotBlank(c.Donor_Email__c) ? c.Donor_Email__c.toLowerCase() : null;
            if (k != null && contactIdByEmail.containsKey(k)) {
                result.put(c.Id, contactIdByEmail.get(k));
            } else if (noEmailByContrib.containsKey(c.Id)) {
                result.put(c.Id, noEmailByContrib.get(c.Id).Id);
            }
        }
        return result;
    }

    private static Contact buildContact(Ken_Gift_Contribution__c c) {
        return new Contact(
            FirstName = c.Donor_First_Name__c,
            LastName = String.isNotBlank(c.Donor_Last_Name__c) ? c.Donor_Last_Name__c : 'Donor',
            Email = c.Donor_Email__c
        );
    }
}