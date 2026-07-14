// NOTE: `without sharing` — alumni-portal pattern: every alumnus can browse opportunities + record contributions.
// Aligned with the 12 other portal controllers we flipped (Network, Chat, MyProfile, etc.) so cross-reference
// inserts (Contribution → Opportunity) succeed despite Account/Contact External OWD = Private.
public without sharing class KenGivingV2Controller {

    // ----- DTO classes -----

    public class AllocationDTO {
        @AuraEnabled public String label;
        @AuraEnabled public Integer percent;
    }

    public class UpdateDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String campaignId;
        @AuraEnabled public String campaignTitle;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String headline;
        @AuraEnabled public String body;
        @AuraEnabled public String image;
        @AuraEnabled public String metric;
    }

    public class OpportunityCardDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String category;
        @AuraEnabled public String shortDesc;
        @AuraEnabled public String story;
        @AuraEnabled public String whyItMatters;
        @AuraEnabled public Decimal target;
        @AuraEnabled public Decimal raised;
        @AuraEnabled public Integer contributors;
        @AuraEnabled public Integer daysLeft;
        @AuraEnabled public Boolean ongoing;
        @AuraEnabled public Boolean approved;
        @AuraEnabled public String beneficiary;
        @AuraEnabled public String department;
        @AuraEnabled public String timeline;
        @AuraEnabled public String image;
        @AuraEnabled public String cause;
        @AuraEnabled public String color;
        @AuraEnabled public String status;
        @AuraEnabled public List<AllocationDTO> allocation;
        @AuraEnabled public List<Decimal> suggestedAmounts;
        @AuraEnabled public List<UpdateDTO> updates;
    }

    public class OpportunityDetailDTO {
        @AuraEnabled public OpportunityCardDTO opportunity;
        @AuraEnabled public List<AllocationDTO> allocations;
        @AuraEnabled public List<Decimal> suggestedAmounts;
        @AuraEnabled public List<UpdateDTO> updates;
    }

    public class ContributorDTO {
        @AuraEnabled public String name;
        @AuraEnabled public String batch;
        @AuraEnabled public String campaign;
        @AuraEnabled public String amount;
        @AuraEnabled public Boolean anon;
        @AuraEnabled public Boolean hideAmount;
    }

    public class BatchRankDTO {
        @AuraEnabled public String batch;
        @AuraEnabled public Integer participants;
        @AuraEnabled public String raised;
    }

    public class ContributionDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String campaignId;
        @AuraEnabled public String campaignTitle;
        @AuraEnabled public String type;
        @AuraEnabled public String amountOrValue;
        @AuraEnabled public String dateLabel;
        @AuraEnabled public String status;
        @AuraEnabled public String visibility;
        @AuraEnabled public Boolean receipt;
        @AuraEnabled public Boolean updatesAvailable;
    }

    public class GivingPageData {
        @AuraEnabled public List<OpportunityCardDTO> opportunities;
        @AuraEnabled public OpportunityCardDTO featured;
        @AuraEnabled public List<ContributorDTO> contributors;
        @AuraEnabled public List<BatchRankDTO> topBatches;
        @AuraEnabled public List<String> corporateSupporters;
    }

    // ----- Helpers -----

    private static String formatINR(Decimal n) {
        if (n == null) return '';
        if (n >= 10000000) {
            Decimal v = n / 10000000;
            return '₹' + v.setScale(v.intValue() == v ? 0 : 2) + ' Cr';
        }
        if (n >= 100000) {
            Decimal v = n / 100000;
            return '₹' + v.setScale(v.intValue() == v ? 0 : 2) + ' L';
        }
        if (n >= 1000) {
            Decimal v = n / 1000;
            return '₹' + v.setScale(v.intValue() == v ? 0 : 1) + 'K';
        }
        return '₹' + String.valueOf(n.setScale(0));
    }

    private static String formatDateLabel(Datetime dt) {
        if (dt == null) return '';
        return dt.format('MMM dd, yyyy');
    }

    private static OpportunityCardDTO toCard(Ken_Giving_Opportunity__c o) {
        OpportunityCardDTO c = new OpportunityCardDTO();
        c.id = (o.External_Id__c != null && o.External_Id__c != '') ? o.External_Id__c : o.Id;
        c.title = o.Title__c;
        c.category = o.Category__c;
        c.shortDesc = o.Short_Description__c;
        c.story = o.Story__c;
        c.whyItMatters = o.Why_It_Matters__c;
        c.target = o.Target_Amount__c;
        c.raised = o.Raised_Amount__c;
        c.contributors = (o.Contributors_Count__c == null) ? 0 : Integer.valueOf(o.Contributors_Count__c);
        c.daysLeft = (o.Days_Left__c == null) ? null : Integer.valueOf(o.Days_Left__c);
        c.ongoing = o.Is_Ongoing__c;
        c.approved = (o.Status__c == 'Live' || o.Status__c == 'Approved');
        c.beneficiary = o.Beneficiary__c;
        c.department = o.Department__c;
        c.timeline = o.Timeline__c;
        c.image = o.Image_URL__c;
        c.cause = o.Cause__c;
        c.color = o.Theme_Color__c;
        c.status = o.Status__c;
        c.allocation = new List<AllocationDTO>();
        c.suggestedAmounts = new List<Decimal>();
        c.updates = new List<UpdateDTO>();
        return c;
    }

    private static Id currentContactId() {
        Id uid = UserInfo.getUserId();
        List<User> us = [SELECT ContactId FROM User WHERE Id = :uid LIMIT 1];
        if (us.isEmpty()) return null;
        return us[0].ContactId;
    }

    // ----- Public API -----

    @AuraEnabled(cacheable=true)
    public static GivingPageData getOpportunitiesPage() {
        GivingPageData out = new GivingPageData();
        out.opportunities = new List<OpportunityCardDTO>();
        out.contributors = new List<ContributorDTO>();
        out.topBatches = new List<BatchRankDTO>();
        out.corporateSupporters = new List<String>();

        List<Ken_Giving_Opportunity__c> opps = [
            SELECT Id, External_Id__c, Title__c, Category__c, Short_Description__c,
                   Story__c, Why_It_Matters__c, Target_Amount__c, Raised_Amount__c,
                   Contributors_Count__c, Days_Left__c, Is_Ongoing__c, Status__c,
                   Beneficiary__c, Department__c, Timeline__c, Image_URL__c,
                   Cause__c, Theme_Color__c
            FROM Ken_Giving_Opportunity__c
            WHERE Status__c IN ('Live','Approved','Closed')
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
        for (Ken_Giving_Opportunity__c o : opps) {
            out.opportunities.add(toCard(o));
        }
        if (!out.opportunities.isEmpty()) out.featured = out.opportunities[0];

        // Recent contributors (Public/Name+batch only, top 6)
        List<Ken_Giving_Contribution__c> contribs = [
            SELECT Id, Visibility__c, Amount_Display__c, Hide_Amount__c, Batch__c,
                   Campaign_Title_Snapshot__c, Contributor__r.Name,
                   Opportunity__r.Title__c
            FROM Ken_Giving_Contribution__c
            WHERE Status__c IN ('Completed','Receipt available','Acknowledged','Live')
            ORDER BY CreatedDate DESC
            LIMIT 6
        ];
        for (Ken_Giving_Contribution__c k : contribs) {
            ContributorDTO d = new ContributorDTO();
            Boolean anon = (k.Visibility__c == 'Anonymous');
            d.anon = anon;
            d.name = anon ? 'Anonymous' : (k.Contributor__r != null ? k.Contributor__r.Name : '');
            d.batch = anon ? 'Identity private' : (k.Batch__c != null ? k.Batch__c : '');
            d.campaign = (k.Campaign_Title_Snapshot__c != null && k.Campaign_Title_Snapshot__c != '')
                          ? k.Campaign_Title_Snapshot__c
                          : (k.Opportunity__r != null ? k.Opportunity__r.Title__c : '');
            d.amount = (k.Amount_Display__c == null) ? '' : k.Amount_Display__c;
            d.hideAmount = (k.Hide_Amount__c == true);
            out.contributors.add(d);
        }

        for (Ken_Giving_Batch_Ranking__c b : [
            SELECT Batch__c, Participants__c, Raised_Display__c
            FROM Ken_Giving_Batch_Ranking__c
            ORDER BY Raised_Amount__c DESC NULLS LAST
            LIMIT 8
        ]) {
            BatchRankDTO br = new BatchRankDTO();
            br.batch = b.Batch__c;
            br.participants = (b.Participants__c == null) ? 0 : Integer.valueOf(b.Participants__c);
            br.raised = b.Raised_Display__c;
            out.topBatches.add(br);
        }

        for (Ken_Giving_Corporate_Supporter__c c : [
            SELECT Name FROM Ken_Giving_Corporate_Supporter__c ORDER BY Name LIMIT 20
        ]) {
            out.corporateSupporters.add(c.Name);
        }

        return out;
    }

    @AuraEnabled(cacheable=true)
    public static OpportunityDetailDTO getOpportunityDetail(String opportunityId) {
        OpportunityDetailDTO d = new OpportunityDetailDTO();
        if (String.isBlank(opportunityId)) return d;
        Boolean isRealId = opportunityId.length() >= 15
            && opportunityId.length() <= 18
            && Pattern.matches('[a-zA-Z0-9]{15,18}', opportunityId);
        List<Ken_Giving_Opportunity__c> opps;
        if (isRealId) {
            opps = [
                SELECT Id, External_Id__c, Title__c, Category__c, Short_Description__c,
                       Story__c, Why_It_Matters__c, Target_Amount__c, Raised_Amount__c,
                       Contributors_Count__c, Days_Left__c, Is_Ongoing__c, Status__c,
                       Beneficiary__c, Department__c, Timeline__c, Image_URL__c,
                       Cause__c, Theme_Color__c
                FROM Ken_Giving_Opportunity__c
                WHERE Id = :opportunityId
                LIMIT 1
            ];
        } else {
            opps = [
                SELECT Id, External_Id__c, Title__c, Category__c, Short_Description__c,
                       Story__c, Why_It_Matters__c, Target_Amount__c, Raised_Amount__c,
                       Contributors_Count__c, Days_Left__c, Is_Ongoing__c, Status__c,
                       Beneficiary__c, Department__c, Timeline__c, Image_URL__c,
                       Cause__c, Theme_Color__c
                FROM Ken_Giving_Opportunity__c
                WHERE External_Id__c = :opportunityId
                LIMIT 1
            ];
        }
        if (opps.isEmpty()) return d;
        Id resolvedId = opps[0].Id;
        OpportunityCardDTO card = toCard(opps[0]);

        List<AllocationDTO> allocs = new List<AllocationDTO>();
        for (Ken_Giving_Allocation__c a : [
            SELECT Allocation_Label__c, Percent__c
            FROM Ken_Giving_Allocation__c
            WHERE Opportunity__c = :resolvedId
            ORDER BY CreatedDate ASC
        ]) {
            AllocationDTO ad = new AllocationDTO();
            ad.label = a.Allocation_Label__c;
            ad.percent = (a.Percent__c == null) ? 0 : Integer.valueOf(a.Percent__c);
            allocs.add(ad);
        }
        List<Decimal> sugg = new List<Decimal>();
        for (Ken_Giving_Suggested_Amount__c s : [
            SELECT Amount__c, Sort_Order__c
            FROM Ken_Giving_Suggested_Amount__c
            WHERE Opportunity__c = :resolvedId
            ORDER BY Sort_Order__c ASC
        ]) {
            sugg.add(s.Amount__c);
        }
        List<UpdateDTO> upds = new List<UpdateDTO>();
        for (Ken_Giving_Update__c u : [
            SELECT Id, Update_Date_Label__c, Headline__c, Body__c, Image_URL__c, Metric__c
            FROM Ken_Giving_Update__c
            WHERE Opportunity__c = :resolvedId
            ORDER BY Update_Date__c DESC NULLS LAST
        ]) {
            UpdateDTO ud = new UpdateDTO();
            ud.id = u.Id;
            ud.campaignId = card.id;
            ud.campaignTitle = card.title;
            ud.dateLabel = u.Update_Date_Label__c;
            ud.headline = u.Headline__c;
            ud.body = u.Body__c;
            ud.image = u.Image_URL__c;
            ud.metric = u.Metric__c;
            upds.add(ud);
        }
        card.allocation = allocs;
        card.suggestedAmounts = sugg;
        card.updates = upds;

        d.opportunity = card;
        d.allocations = allocs;
        d.suggestedAmounts = sugg;
        d.updates = upds;
        return d;
    }

    @AuraEnabled(cacheable=true)
    public static List<ContributionDTO> getMyGiving() {
        List<ContributionDTO> out = new List<ContributionDTO>();
        Id contactId = currentContactId();
        if (contactId == null) return out;
        for (Ken_Giving_Contribution__c c : [
            SELECT Id, Name, Type__c, Amount_Display__c, Status__c, Visibility__c,
                   Receipt_Available__c, Updates_Available__c, CreatedDate,
                   Campaign_Title_Snapshot__c, Opportunity__c, Opportunity__r.Title__c,
                   Opportunity__r.External_Id__c
            FROM Ken_Giving_Contribution__c
            WHERE Contributor__c = :contactId
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            ContributionDTO d = new ContributionDTO();
            d.id = c.Id;
            d.campaignId = (c.Opportunity__r != null && c.Opportunity__r.External_Id__c != null && c.Opportunity__r.External_Id__c != '')
                            ? c.Opportunity__r.External_Id__c
                            : (String) c.Opportunity__c;
            d.campaignTitle = (c.Campaign_Title_Snapshot__c != null && c.Campaign_Title_Snapshot__c != '')
                                ? c.Campaign_Title_Snapshot__c
                                : (c.Opportunity__r != null ? c.Opportunity__r.Title__c : '');
            d.type = c.Type__c;
            d.amountOrValue = c.Amount_Display__c;
            d.dateLabel = formatDateLabel(c.CreatedDate);
            d.status = c.Status__c;
            d.visibility = c.Visibility__c;
            d.receipt = c.Receipt_Available__c;
            d.updatesAvailable = c.Updates_Available__c;
            out.add(d);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<UpdateDTO> getImpactUpdates() {
        List<UpdateDTO> out = new List<UpdateDTO>();
        Map<Id, Ken_Giving_Opportunity__c> oppMap = new Map<Id, Ken_Giving_Opportunity__c>([
            SELECT Id, External_Id__c, Title__c FROM Ken_Giving_Opportunity__c
        ]);
        for (Ken_Giving_Update__c u : [
            SELECT Id, Opportunity__c, Update_Date_Label__c, Headline__c, Body__c,
                   Image_URL__c, Metric__c, Update_Date__c
            FROM Ken_Giving_Update__c
            ORDER BY Update_Date__c DESC NULLS LAST
            LIMIT 50
        ]) {
            UpdateDTO d = new UpdateDTO();
            d.id = u.Id;
            Ken_Giving_Opportunity__c o = oppMap.get(u.Opportunity__c);
            d.campaignId = (o != null && o.External_Id__c != null && o.External_Id__c != '') ? o.External_Id__c : (String) u.Opportunity__c;
            d.campaignTitle = (o != null) ? o.Title__c : '';
            d.dateLabel = u.Update_Date_Label__c;
            d.headline = u.Headline__c;
            d.body = u.Body__c;
            d.image = u.Image_URL__c;
            d.metric = u.Metric__c;
            out.add(d);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<OpportunityCardDTO> getFundraiseOpportunities() {
        List<OpportunityCardDTO> out = new List<OpportunityCardDTO>();
        for (Ken_Giving_Opportunity__c o : [
            SELECT Id, External_Id__c, Title__c, Category__c, Short_Description__c,
                   Story__c, Why_It_Matters__c, Target_Amount__c, Raised_Amount__c,
                   Contributors_Count__c, Days_Left__c, Is_Ongoing__c, Status__c,
                   Beneficiary__c, Department__c, Timeline__c, Image_URL__c,
                   Cause__c, Theme_Color__c
            FROM Ken_Giving_Opportunity__c
            WHERE (Cause__c != null OR Theme_Color__c != null)
              AND Status__c IN ('Live','Closed','Approved')
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            out.add(toCard(o));
        }
        return out;
    }

    @AuraEnabled
    public static Id submitInitiative(Map<String,Object> payload) {
        if (payload == null) {
            throw new AuraHandledException('Payload required.');
        }
        Ken_Giving_Opportunity__c o = new Ken_Giving_Opportunity__c();
        o.Title__c = (String) payload.get('title');
        if (String.isBlank(o.Title__c)) {
            throw new AuraHandledException('Title required.');
        }
        o.Name = o.Title__c.left(80);
        o.Category__c = (String) payload.get('category');
        if (String.isBlank(o.Category__c)) o.Category__c = 'Student Support';
        o.Short_Description__c = (String) payload.get('shortDesc');
        if (String.isBlank(o.Short_Description__c)) o.Short_Description__c = o.Title__c;
        o.Story__c = (String) payload.get('story');
        o.Why_It_Matters__c = (String) payload.get('whyItMatters');
        o.Beneficiary__c = (String) payload.get('beneficiary');
        o.Department__c = (String) payload.get('department');
        o.Timeline__c = (String) payload.get('timeline');
        o.Image_URL__c = (String) payload.get('image');
        Object t = payload.get('target');
        if (t != null) o.Target_Amount__c = (t instanceof Decimal) ? (Decimal) t : Decimal.valueOf(String.valueOf(t));
        Object d = payload.get('daysLeft');
        if (d != null) o.Days_Left__c = (d instanceof Integer) ? (Integer) d : Integer.valueOf(String.valueOf(d));
        Object ongoing = payload.get('ongoing');
        o.Is_Ongoing__c = (ongoing == true);
        o.Cause__c = (String) payload.get('cause');
        o.Theme_Color__c = (String) payload.get('color');
        o.Batch__c = (String) payload.get('batch');
        o.Status__c = 'Submitted for Review';
        o.Initiator__c = currentContactId();
        insert o;
        return o.Id;
    }

    @AuraEnabled
    public static Id submitContribution(Map<String,Object> payload) {
        if (payload == null) {
            throw new AuraHandledException('Payload required.');
        }
        Ken_Giving_Contribution__c c = new Ken_Giving_Contribution__c();
        Object oppRaw = payload.get('opportunityId');
        if (oppRaw == null) {
            throw new AuraHandledException('opportunityId required.');
        }
        String oppKey = String.valueOf(oppRaw);
        Id oppId;
        if (oppKey instanceof Id || oppKey.length() == 15 || oppKey.length() == 18) {
            try { oppId = (Id) oppKey; } catch (Exception e) {}
        }
        if (oppId == null) {
            // Lookup by External_Id__c
            List<Ken_Giving_Opportunity__c> match = [
                SELECT Id, Title__c FROM Ken_Giving_Opportunity__c
                WHERE External_Id__c = :oppKey LIMIT 1
            ];
            if (match.isEmpty()) {
                throw new AuraHandledException('Opportunity not found: ' + oppKey);
            }
            oppId = match[0].Id;
            c.Campaign_Title_Snapshot__c = match[0].Title__c;
        } else {
            List<Ken_Giving_Opportunity__c> match = [
                SELECT Title__c FROM Ken_Giving_Opportunity__c WHERE Id = :oppId LIMIT 1
            ];
            if (!match.isEmpty()) c.Campaign_Title_Snapshot__c = match[0].Title__c;
        }
        c.Opportunity__c = oppId;
        c.Contributor__c = currentContactId();
        if (c.Contributor__c == null) {
            throw new AuraHandledException('Current user has no linked Contact.');
        }
        c.Type__c = (String) payload.get('type');
        if (String.isBlank(c.Type__c)) c.Type__c = 'donation';
        Object amtNum = payload.get('amountNumeric');
        if (amtNum != null) {
            c.Amount_Numeric__c = (amtNum instanceof Decimal) ? (Decimal) amtNum : Decimal.valueOf(String.valueOf(amtNum));
        }
        c.Amount_Display__c = (String) payload.get('amountDisplay');
        if (String.isBlank(c.Amount_Display__c) && c.Amount_Numeric__c != null) {
            c.Amount_Display__c = '₹' + String.valueOf(c.Amount_Numeric__c.setScale(0));
        }
        if (String.isBlank(c.Amount_Display__c)) c.Amount_Display__c = '—';
        c.Visibility__c = (String) payload.get('visibility');
        if (String.isBlank(c.Visibility__c)) c.Visibility__c = 'Name + batch';
        c.Status__c = (String) payload.get('status');
        if (String.isBlank(c.Status__c)) {
            c.Status__c = (c.Type__c == 'pledge') ? 'Pledged' : 'Submitted for Review';
        }
        c.Notes__c = (String) payload.get('notes');
        c.Batch__c = (String) payload.get('batch');
        Object hide = payload.get('hideAmount');
        c.Hide_Amount__c = (hide == true);
        insert c;
        return c.Id;
    }

    @AuraEnabled
    public static Id updateContributionVisibility(Id contributionId, String visibility) {
        if (contributionId == null) {
            throw new AuraHandledException('contributionId required.');
        }
        if (String.isBlank(visibility)) {
            throw new AuraHandledException('visibility required.');
        }
        Id contactId = currentContactId();
        List<Ken_Giving_Contribution__c> rows = [
            SELECT Id, Contributor__c FROM Ken_Giving_Contribution__c
            WHERE Id = :contributionId LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Contribution not found.');
        }
        if (contactId == null || rows[0].Contributor__c != contactId) {
            throw new AuraHandledException('You can only update your own contribution.');
        }
        rows[0].Visibility__c = visibility;
        update rows[0];
        return rows[0].Id;
    }
}