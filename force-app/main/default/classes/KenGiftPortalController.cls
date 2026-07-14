/**
 * Read controller for the Giving portal LWC (campaign list + detail + tiers + funds).
 * `without sharing` so portal/guest users can read portal-visible campaigns and config
 * regardless of OWD. Progress totals are computed live from Confirmed contributions
 * (the Campaign roll-up fields are populated by a later phase).
 */
public without sharing class KenGiftPortalController {

    public class CampaignTile {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public String heroImageUrl;
        @AuraEnabled public Decimal goal;
        @AuraEnabled public Decimal raised;
        @AuraEnabled public Integer donorCount;
        @AuraEnabled public Decimal percent;
        @AuraEnabled public String slug;
    }

    public class FundOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String department;
    }

    public class SuggestedTier {
        @AuraEnabled public Id id;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isDefault;
    }

    public class CampaignDetail {
        @AuraEnabled public CampaignTile campaign;
        @AuraEnabled public String story;
        @AuraEnabled public List<SuggestedTier> tiers;
        @AuraEnabled public List<FundOption> funds;
    }

    @AuraEnabled(cacheable=true)
    public static List<CampaignTile> getCampaigns() {
        List<Campaign> camps = [
            SELECT Id, Name, Ken_Giving_Category__c, Ken_Giving_Hero_Image_URL__c,
                   Ken_Giving_Goal_Amount__c, Ken_Giving_Portal_Slug__c
            FROM Campaign
            WHERE Ken_Giving_Is_Portal_Visible__c = true AND IsActive = true
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
        Map<Id, CampaignTile> byId = new Map<Id, CampaignTile>();
        for (Campaign c : camps) {
            byId.put(c.Id, buildTile(c));
        }
        applyProgress(byId);
        return byId.values();
    }

    @AuraEnabled(cacheable=true)
    public static CampaignDetail getCampaignDetail(Id campaignId) {
        if (campaignId == null) throw new AuraHandledException('Campaign id is required.');

        List<Campaign> camps = [
            SELECT Id, Name, Ken_Giving_Category__c, Ken_Giving_Hero_Image_URL__c,
                   Ken_Giving_Goal_Amount__c, Ken_Giving_Portal_Slug__c, Ken_Giving_Story__c
            FROM Campaign
            WHERE Id = :campaignId
            LIMIT 1
        ];
        if (camps.isEmpty()) throw new AuraHandledException('Campaign not found.');
        Campaign c = camps[0];

        CampaignDetail detail = new CampaignDetail();
        detail.campaign = buildTile(c);
        detail.story = c.Ken_Giving_Story__c;
        applyProgress(new Map<Id, CampaignTile>{ c.Id => detail.campaign });

        detail.tiers = new List<SuggestedTier>();
        for (Ken_Gift_Suggested_Amount__c s : [
            SELECT Id, Amount__c, Label__c, Is_Default__c
            FROM Ken_Gift_Suggested_Amount__c
            WHERE Campaign__c = :campaignId AND Is_Active__c = true
            ORDER BY Sort_Order__c ASC NULLS LAST, Amount__c ASC
        ]) {
            SuggestedTier t = new SuggestedTier();
            t.id = s.Id; t.amount = s.Amount__c; t.label = s.Label__c; t.isDefault = s.Is_Default__c;
            detail.tiers.add(t);
        }

        detail.funds = new List<FundOption>();
        for (Ken_Giving_Fund__c f : [
            SELECT Id, Name, Department__c FROM Ken_Giving_Fund__c
            WHERE Is_Active__c = true ORDER BY Name ASC
        ]) {
            FundOption fo = new FundOption();
            fo.id = f.Id; fo.name = f.Name; fo.department = f.Department__c;
            detail.funds.add(fo);
        }
        return detail;
    }

    // ---------- helpers ----------
    private static CampaignTile buildTile(Campaign c) {
        CampaignTile t = new CampaignTile();
        t.id = c.Id;
        t.name = c.Name;
        t.category = c.Ken_Giving_Category__c;
        t.heroImageUrl = c.Ken_Giving_Hero_Image_URL__c;
        t.goal = c.Ken_Giving_Goal_Amount__c != null ? c.Ken_Giving_Goal_Amount__c : 0;
        t.slug = c.Ken_Giving_Portal_Slug__c;
        t.raised = 0;
        t.donorCount = 0;
        t.percent = 0;
        return t;
    }

    private static void applyProgress(Map<Id, CampaignTile> tilesById) {
        if (tilesById.isEmpty()) return;
        Set<Id> ids = tilesById.keySet();
        for (AggregateResult ar : [
            SELECT Campaign__c cid, SUM(Amount__c) raised, COUNT(Id) cnt
            FROM Ken_Gift_Contribution__c
            WHERE Status__c = 'Confirmed' AND Campaign__c IN :ids
            GROUP BY Campaign__c
        ]) {
            Id cid = (Id) ar.get('cid');
            CampaignTile t = tilesById.get(cid);
            if (t == null) continue;
            t.raised = (Decimal) ar.get('raised');
            t.donorCount = (Integer) ar.get('cnt');
            if (t.goal != null && t.goal > 0 && t.raised != null) {
                Decimal pct = (t.raised / t.goal) * 100;
                t.percent = pct > 100 ? 100 : pct.setScale(0);
            }
        }
    }
}