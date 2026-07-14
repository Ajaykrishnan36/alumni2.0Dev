/**
 * Edge-write controller for the Giving portal (LWC).
 *
 * Community/guest users insert ONLY the custom edge records here — never the standard
 * Opportunity. Runs `without sharing` so the insert executes in system context (the
 * donor profile needs no Opportunity/Campaign write access). Every DML rejection is
 * surfaced verbatim via AuraHandledException(e.getDmlMessage(0)) — the same hard-won
 * pattern from the Jobs/Survey modules, so silent failures can't recur.
 *
 * Idempotency: a client-generated Request_Id__c (unique external id) blocks
 * double-submit — a retried call returns the existing contribution instead of inserting
 * a duplicate.
 */
public without sharing class KenGiftContributionController {

    // ---------- DTOs ----------
    public class GiftAllocationInput {
        @AuraEnabled public Id fundId { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Decimal percent { get; set; }
    }

    public class GiftPaymentInput {
        @AuraEnabled public String provider { get; set; }
        @AuraEnabled public String providerTxnId { get; set; }
        @AuraEnabled public String idempotencyKey { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String cardBrand { get; set; }
        @AuraEnabled public String lastFour { get; set; }
    }

    public class GiftRequest {
        @AuraEnabled public Id campaignId { get; set; }
        @AuraEnabled public String donorFirstName { get; set; }
        @AuraEnabled public String donorLastName { get; set; }
        @AuraEnabled public String donorEmail { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Boolean isAnonymous { get; set; }
        @AuraEnabled public String frequency { get; set; }
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String tributeType { get; set; }
        @AuraEnabled public String tributeName { get; set; }
        @AuraEnabled public String comment { get; set; }
        @AuraEnabled public String requestId { get; set; }
        @AuraEnabled public List<GiftAllocationInput> allocations { get; set; }
        @AuraEnabled public GiftPaymentInput payment { get; set; }
    }

    public class GiftResult {
        @AuraEnabled public Id contributionId { get; set; }
        @AuraEnabled public Id paymentId { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean alreadyExisted { get; set; }
    }

    // ---------- Entry point ----------
    @AuraEnabled
    public static GiftResult submitContribution(GiftRequest req) {
        if (req == null) {
            throw new AuraHandledException('Donation payload is required.');
        }
        if (String.isBlank(req.requestId)) {
            throw new AuraHandledException('A request id is required for idempotency.');
        }

        // Idempotency — a retried submit with the same Request_Id returns the existing record.
        List<Ken_Gift_Contribution__c> existing = [
            SELECT Id, Status__c,
                   (SELECT Id FROM Payments__r ORDER BY CreatedDate DESC LIMIT 1)
            FROM Ken_Gift_Contribution__c
            WHERE Request_Id__c = :req.requestId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            GiftResult dup = new GiftResult();
            dup.contributionId = existing[0].Id;
            dup.status = existing[0].Status__c;
            dup.alreadyExisted = true;
            if (existing[0].Payments__r != null && !existing[0].Payments__r.isEmpty()) {
                dup.paymentId = existing[0].Payments__r[0].Id;
            }
            return dup;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            // 1) Contribution
            Ken_Gift_Contribution__c c = new Ken_Gift_Contribution__c();
            c.Campaign__c = req.campaignId;
            c.Donor_First_Name__c = req.donorFirstName;
            c.Donor_Last_Name__c = req.donorLastName;
            c.Donor_Email__c = req.donorEmail;
            c.Amount__c = req.amount;
            c.Is_Anonymous__c = (req.isAnonymous == true);
            if (String.isNotBlank(req.frequency)) c.Frequency__c = req.frequency;
            c.Status__c = 'Pending Payment';
            c.Source__c = String.isNotBlank(req.source) ? req.source : 'Portal';
            if (String.isNotBlank(req.tributeType)) c.Tribute_Type__c = req.tributeType;
            c.Tribute_Name__c = req.tributeName;
            c.Comment__c = req.comment;
            c.Request_Id__c = req.requestId;
            insert c;

            // 2) Allocations (the roll-up + sum-equals-amount validation fires here)
            if (req.allocations != null && !req.allocations.isEmpty()) {
                List<Ken_Gift_Allocation__c> allocs = new List<Ken_Gift_Allocation__c>();
                for (GiftAllocationInput ai : req.allocations) {
                    if (ai == null) continue;
                    allocs.add(new Ken_Gift_Allocation__c(
                        Contribution__c = c.Id,
                        Fund__c = ai.fundId,
                        Amount__c = ai.amount,
                        Percent__c = ai.percent
                    ));
                }
                if (!allocs.isEmpty()) insert allocs;
            }

            // 3) Payment (if status arrives as 'Captured', the payment trigger materializes now)
            Id paymentId;
            if (req.payment != null) {
                GiftPaymentInput p = req.payment;
                Ken_Gift_Payment__c pay = new Ken_Gift_Payment__c();
                pay.Contribution__c = c.Id;
                pay.Provider__c = String.isNotBlank(p.provider) ? p.provider : 'Manual';
                pay.Provider_Txn_Id__c = p.providerTxnId;
                pay.Idempotency_Key__c = p.idempotencyKey;
                pay.Status__c = String.isNotBlank(p.status) ? p.status : 'Pending';
                pay.Amount__c = (p.amount != null) ? p.amount : req.amount;
                pay.Card_Brand__c = p.cardBrand;
                pay.Last_Four__c = p.lastFour;
                if (pay.Status__c == 'Captured') pay.Processed_At__c = System.now();
                insert pay;
                paymentId = pay.Id;
            }

            // Re-read status (the materializer may have flipped it to 'Confirmed').
            Ken_Gift_Contribution__c saved = [
                SELECT Id, Status__c FROM Ken_Gift_Contribution__c WHERE Id = :c.Id LIMIT 1
            ];

            GiftResult res = new GiftResult();
            res.contributionId = saved.Id;
            res.paymentId = paymentId;
            res.status = saved.Status__c;
            res.alreadyExisted = false;
            return res;

        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException(e.getMessage());
        }
    }
}