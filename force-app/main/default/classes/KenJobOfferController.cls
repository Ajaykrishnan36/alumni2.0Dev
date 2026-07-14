/**
 * Epic 3 — Offer Comparison Engine.
 *
 *  - getOffersForComparison(): pulls the typed currency architecture (Total/Fixed/Variable/
 *    Joining Bonus *_Amount__c) plus Work_Type__c, Bond (text + months) and a parsed Perks list.
 *  - submitOfferInquiry(): logs a Ken_Offer_Inquiry__c against the A/B comparison, status Open,
 *    stamped with the running user's Contact.
 *
 * `without sharing` so a community alum can compare their own offers and raise an inquiry
 * regardless of OWD.
 */
public without sharing class KenJobOfferController {

    public class OfferView {
        @AuraEnabled public Id id;
        @AuraEnabled public String role;
        @AuraEnabled public String location;
        @AuraEnabled public String company;       // from Application -> Job
        @AuraEnabled public String logoInitial;    // avatar letter
        @AuraEnabled public String logoColor;      // avatar background hex
        @AuraEnabled public Decimal totalCtc;
        @AuraEnabled public Decimal fixedComp;
        @AuraEnabled public Decimal variableComp;
        @AuraEnabled public Decimal joiningBonus;
        @AuraEnabled public String workType;
        @AuraEnabled public String bond;          // raw text (e.g. "None")
        @AuraEnabled public Decimal bondMonths;    // numeric duration for "N months" display
        @AuraEnabled public List<String> perks;
    }

    @AuraEnabled(cacheable=true)
    public static List<OfferView> getOffersForComparison(List<Id> offerIds) {
        List<OfferView> out = new List<OfferView>();
        if (offerIds == null || offerIds.isEmpty()) return out;
        for (Ken_Job_Offer__c o : [
            SELECT Id, Role__c, Location__c, Total_CTC_Amount__c, Fixed_Comp_Amount__c,
                   Variable_Comp_Amount__c, Joining_Bonus_Amount__c, Work_Type__c,
                   Bond__c, Bond_Months__c, Perks_JSON__c,
                   Application__r.Job__r.Company__c, Application__r.Job__r.Logo_Initial__c,
                   Application__r.Job__r.Logo_Color__c
            FROM Ken_Job_Offer__c
            WHERE Id IN :offerIds
        ]) {
            OfferView v = new OfferView();
            v.id = o.Id;
            v.role = o.Role__c;
            v.location = o.Location__c;
            Ken_Job_Master__c job = (o.Application__r != null) ? o.Application__r.Job__r : null;
            if (job != null) {
                v.company = job.Company__c;
                v.logoInitial = job.Logo_Initial__c;
                v.logoColor = job.Logo_Color__c;
            }
            v.totalCtc = o.Total_CTC_Amount__c;
            v.fixedComp = o.Fixed_Comp_Amount__c;
            v.variableComp = o.Variable_Comp_Amount__c;
            v.joiningBonus = o.Joining_Bonus_Amount__c;
            v.workType = o.Work_Type__c;
            v.bond = o.Bond__c;
            v.bondMonths = o.Bond_Months__c;
            v.perks = parsePerks(o.Perks_JSON__c);
            out.add(v);
        }
        return out;
    }

    @AuraEnabled
    public static Id submitOfferInquiry(Id offerIdA, Id offerIdB, String questionText) {
        if (String.isBlank(questionText)) throw new AuraHandledException('Please enter a question.');
        Ken_Offer_Inquiry__c inq = new Ken_Offer_Inquiry__c(
            Offer_A__c = offerIdA,
            Offer_B__c = offerIdB,
            Question__c = questionText.trim(),
            Status__c = 'Open',
            Asked_By__c = currentContactId()
        );
        try {
            insert inq;
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
        return inq.Id;
    }

    // Tolerant: accepts a JSON array (["A","B"]), array of objects ([{"label":"A"}]) or CSV.
    @TestVisible
    private static List<String> parsePerks(String j) {
        List<String> perks = new List<String>();
        if (String.isBlank(j)) return perks;
        try {
            for (Object o : (List<Object>) JSON.deserializeUntyped(j)) {
                if (o == null) continue;
                if (o instanceof Map<String,Object>) {
                    Map<String,Object> m = (Map<String,Object>) o;
                    Object v = m.containsKey('label') ? m.get('label') : (m.containsKey('name') ? m.get('name') : m.values()[0]);
                    if (v != null) perks.add(String.valueOf(v));
                } else {
                    perks.add(String.valueOf(o));
                }
            }
        } catch (Exception e) {
            for (String p : j.split(',')) if (String.isNotBlank(p)) perks.add(p.trim());
        }
        return perks;
    }

    @TestVisible private static Id testContactId; // test seam — avoids provisioning a portal user

    private static Id currentContactId() {
        if (Test.isRunningTest() && testContactId != null) return testContactId;
        for (User u : [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]) {
            return u.ContactId;
        }
        return null;
    }
}