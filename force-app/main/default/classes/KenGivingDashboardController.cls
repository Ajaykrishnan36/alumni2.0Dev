/**
 * Giving v2 — Dashboard + Opportunities data service.
 *
 * Backs three LWCs:
 *   - kenGivingDashboardTabV2 calls getDashboardMetrics() + getDashboardRightRail()
 *   - kenGivingOpportunitiesTabV2 calls getOpportunities()
 *
 * `without sharing` so a community alum sees aggregate giving figures regardless of OWD.
 * Every query is wrapped so a missing field / empty table degrades to zeros + empty
 * lists rather than throwing the whole page down.
 */
public without sharing class KenGivingDashboardController {

    // ========================================================== DTOs

    public class DashboardMetrics {
        @AuraEnabled public Decimal raisedAmount;
        @AuraEnabled public String  raisedDisplay;
        @AuraEnabled public Integer contributorsCount;
        @AuraEnabled public Integer privateContributorsCount;
        @AuraEnabled public Integer liveCampaignsCount;
        @AuraEnabled public String  topBatchName;
        @AuraEnabled public String  topBatchRaisedDisplay;
        @AuraEnabled public Integer topBatchAlumni;
    }

    public class ActionItem {
        @AuraEnabled public String title;
        @AuraEnabled public String subtitle;
        @AuraEnabled public String cta;        // 'View' or 'Pay'
        @AuraEnabled public Id     refId;
    }

    public class Contributor {
        @AuraEnabled public Id     id;
        @AuraEnabled public String displayName;
        @AuraEnabled public String initial;
        @AuraEnabled public String avatarColor;
        @AuraEnabled public String batchOrFund;       // e.g. "2018 · CSE · Scholarship Fund"
        @AuraEnabled public String amountDisplay;     // e.g. "₹50,000" or "Private"
        @AuraEnabled public Boolean isAnonymous;
        @AuraEnabled public Boolean hideAmount;
    }

    public class RightRail {
        @AuraEnabled public List<ActionItem> actionItems;
        @AuraEnabled public List<Contributor> recentContributors;
        @AuraEnabled public Integer privateContributorsCount;
        @AuraEnabled public List<String> corporateSupporters;
    }

    public class ImpactUpdate {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  dateLabel;       // e.g. 'MAR 2026'
        @AuraEnabled public String  metric;          // e.g. '42 students'
        @AuraEnabled public String  headline;
        @AuraEnabled public String  body;
        @AuraEnabled public String  imageUrl;
        @AuraEnabled public Id      opportunityId;
        @AuraEnabled public String  ctaLabel;
    }

    public class LeaderboardRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public Integer rank;
        @AuraEnabled public String  batchName;
        @AuraEnabled public String  contributorsLabel;
        @AuraEnabled public String  raisedDisplay;
    }

    public class OpportunityRow {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  title;
        @AuraEnabled public String  shortDescription;
        @AuraEnabled public String  category;
        @AuraEnabled public String  status;           // 'Live' / 'Approved' / …
        @AuraEnabled public String  imageUrl;
        @AuraEnabled public Decimal raisedAmount;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public String  raisedDisplay;    // formatted with ₹ + L / Cr
        @AuraEnabled public String  goalDisplay;
        @AuraEnabled public Integer contributorsCount;
        @AuraEnabled public Integer daysLeft;
        @AuraEnabled public Integer progressPercent;  // 0-100, pre-computed for the LWC
        @AuraEnabled public Boolean isFeatured;
    }

    // ========================================================== Public API

    @AuraEnabled(cacheable=true)
    public static DashboardMetrics getDashboardMetrics() {
        DashboardMetrics m = new DashboardMetrics();
        m.raisedAmount = 0; m.contributorsCount = 0; m.privateContributorsCount = 0;
        m.liveCampaignsCount = 0; m.topBatchAlumni = 0;
        m.raisedDisplay = formatInr(0);
        m.topBatchName = '—'; m.topBatchRaisedDisplay = '';

        // Raised + live campaigns from Ken_Giving_Opportunity__c
        try {
            AggregateResult[] sumRows = [
                SELECT SUM(Raised_Amount__c) total, COUNT(Id) cnt
                FROM Ken_Giving_Opportunity__c
                WHERE Status__c IN ('Live','Approved','Open')];
            if (!sumRows.isEmpty()) {
                Decimal total = (Decimal) sumRows[0].get('total');
                m.raisedAmount = (total != null) ? total : 0;
                m.liveCampaignsCount = (Integer) sumRows[0].get('cnt');
            }
            m.raisedDisplay = formatInr(m.raisedAmount);
        } catch (Exception e) { /* tolerate */ }

        // Contributor count + private count from Ken_Gift_Contribution__c
        try {
            AggregateResult[] cntRows = [
                SELECT COUNT_DISTINCT(Donor_Contact__c) c
                FROM Ken_Gift_Contribution__c
                WHERE Status__c = 'Confirmed' AND Donor_Contact__c != null];
            if (!cntRows.isEmpty() && cntRows[0].get('c') != null) {
                m.contributorsCount = (Integer) cntRows[0].get('c');
            }
            AggregateResult[] privRows = [
                SELECT COUNT(Id) c FROM Ken_Gift_Contribution__c
                WHERE Status__c = 'Confirmed' AND Is_Anonymous__c = true];
            if (!privRows.isEmpty() && privRows[0].get('c') != null) {
                m.privateContributorsCount = (Integer) privRows[0].get('c');
            }
        } catch (Exception e) { /* tolerate */ }

        // Top batch — leaderboard row #1 by raised amount
        try {
            for (Ken_Giving_Batch_Ranking__c r : [
                SELECT Batch__c, Raised_Amount__c, Raised_Display__c, Participants__c
                FROM Ken_Giving_Batch_Ranking__c
                ORDER BY Raised_Amount__c DESC NULLS LAST LIMIT 1
            ]) {
                m.topBatchName = String.isNotBlank(r.Batch__c) ? ('Batch of ' + r.Batch__c) : '—';
                m.topBatchRaisedDisplay = String.isNotBlank(r.Raised_Display__c)
                    ? r.Raised_Display__c : formatInr(r.Raised_Amount__c);
                m.topBatchAlumni = (r.Participants__c != null) ? (Integer) r.Participants__c : 0;
            }
        } catch (Exception e) { /* tolerate */ }
        return m;
    }

    @AuraEnabled(cacheable=true)
    public static RightRail getDashboardRightRail() {
        RightRail r = new RightRail();
        r.actionItems = new List<ActionItem>();
        r.recentContributors = new List<Contributor>();
        r.corporateSupporters = new List<String>();
        r.privateContributorsCount = 0;

        // Action items — surface a pledged-but-not-yet-paid contribution as "Pay",
        // and the most recent campaign update as "View" (best-effort).
        try {
            for (Ken_Gift_Contribution__c c : [
                SELECT Id, Amount__c, Opportunity__r.Name
                FROM Ken_Gift_Contribution__c
                WHERE Status__c = 'Pending Payment' AND Donor_Contact__c != null
                ORDER BY CreatedDate DESC LIMIT 1
            ]) {
                ActionItem ai = new ActionItem();
                ai.title = 'Complete pledge';
                ai.subtitle = (c.Opportunity__r != null && c.Opportunity__r.Name != null)
                    ? c.Opportunity__r.Name : 'Pledged contribution';
                ai.cta = 'Pay';
                ai.refId = c.Id;
                r.actionItems.add(ai);
            }
        } catch (Exception e) { /* tolerate */ }
        try {
            for (Ken_Giving_Opportunity__c o : [
                SELECT Id, Title__c FROM Ken_Giving_Opportunity__c
                WHERE Status__c IN ('Live','Approved','Open')
                ORDER BY LastModifiedDate DESC LIMIT 1
            ]) {
                ActionItem ai = new ActionItem();
                ai.title = 'New update';
                ai.subtitle = o.Title__c != null ? o.Title__c : 'Campaign update';
                ai.cta = 'View';
                ai.refId = o.Id;
                r.actionItems.add(ai);
            }
        } catch (Exception e) { /* tolerate */ }

        // Recent contributors — public first, plus anonymous count for the "X private not shown" line.
        try {
            Integer i = 0;
            String[] palette = new String[]{ '#7c3aed', '#0ea5e9', '#f59e0b', '#10b981', '#ef4444' };
            for (Ken_Gift_Contribution__c c : [
                SELECT Id, Amount__c, Is_Anonymous__c, Donor_First_Name__c, Donor_Last_Name__c,
                       Donor_Contact__r.Name, Donor_Contact__r.AccountId,
                       Campaign__c, Opportunity__r.Name
                FROM Ken_Gift_Contribution__c
                WHERE Status__c = 'Completed'
                ORDER BY CreatedDate DESC LIMIT 10
            ]) {
                Contributor cv = new Contributor();
                cv.id = c.Id;
                cv.isAnonymous = c.Is_Anonymous__c == true;
                cv.hideAmount = cv.isAnonymous;
                cv.amountDisplay = cv.hideAmount ? 'Private' : formatInr(c.Amount__c);
                cv.batchOrFund = (c.Opportunity__r != null && c.Opportunity__r.Name != null)
                    ? c.Opportunity__r.Name : 'Alumni Giving Fund';
                cv.avatarColor = palette[Math.mod(i, palette.size())];
                if (cv.isAnonymous) {
                    cv.displayName = 'Anonymous';
                    cv.initial = '?';
                    cv.batchOrFund = 'Identity private · ' + cv.batchOrFund;
                } else {
                    String name = (c.Donor_Contact__r != null) ? c.Donor_Contact__r.Name
                        : ((c.Donor_First_Name__c != null ? c.Donor_First_Name__c + ' ' : '')
                            + (c.Donor_Last_Name__c != null ? c.Donor_Last_Name__c : '')).trim();
                    if (String.isBlank(name)) name = 'Alum';
                    cv.displayName = name;
                    cv.initial = name.substring(0, 1).toUpperCase();
                }
                r.recentContributors.add(cv);
                if (cv.isAnonymous) r.privateContributorsCount += 1;
                i++;
            }
        } catch (Exception e) { /* tolerate */ }

        // Corporate supporters — just names, displayed as pills.
        try {
            for (Ken_Giving_Corporate_Supporter__c s : [
                SELECT Name FROM Ken_Giving_Corporate_Supporter__c ORDER BY Name LIMIT 50
            ]) {
                if (String.isNotBlank(s.Name)) r.corporateSupporters.add(s.Name);
            }
        } catch (Exception e) { /* tolerate */ }

        return r;
    }

    @AuraEnabled(cacheable=true)
    public static List<ImpactUpdate> getImpactUpdates() {
        List<ImpactUpdate> out = new List<ImpactUpdate>();
        try {
            for (Ken_Giving_Update__c u : [
                SELECT Id, Headline__c, Body__c, Image_URL__c, Metric__c,
                       Update_Date__c, Update_Date_Label__c, Opportunity__c
                FROM Ken_Giving_Update__c
                ORDER BY Update_Date__c DESC NULLS LAST, CreatedDate DESC
                LIMIT 12
            ]) {
                ImpactUpdate i = new ImpactUpdate();
                i.id = u.Id;
                i.headline = u.Headline__c;
                i.body = u.Body__c;
                i.imageUrl = u.Image_URL__c;
                i.metric = u.Metric__c;
                i.opportunityId = u.Opportunity__c;
                // Use the explicit label when present, else format the Date as "MMM YYYY".
                if (String.isNotBlank(u.Update_Date_Label__c)) {
                    i.dateLabel = u.Update_Date_Label__c;
                } else if (u.Update_Date__c != null) {
                    DateTime dt = DateTime.newInstance(u.Update_Date__c.year(), u.Update_Date__c.month(), u.Update_Date__c.day());
                    i.dateLabel = dt.format('MMM yyyy').toUpperCase();
                }
                i.ctaLabel = 'View update';
                out.add(i);
            }
        } catch (Exception e) { /* tolerate */ }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<LeaderboardRow> getLeaderboard() {
        List<LeaderboardRow> out = new List<LeaderboardRow>();
        try {
            Integer rank = 1;
            for (Ken_Giving_Batch_Ranking__c r : [
                SELECT Id, Batch__c, Participants__c, Raised_Amount__c, Raised_Display__c
                FROM Ken_Giving_Batch_Ranking__c
                ORDER BY Raised_Amount__c DESC NULLS LAST
                LIMIT 10
            ]) {
                LeaderboardRow row = new LeaderboardRow();
                row.id = r.Id;
                row.rank = rank++;
                row.batchName = String.isNotBlank(r.Batch__c) ? ('Batch of ' + r.Batch__c) : 'Unknown batch';
                Integer p = (r.Participants__c != null) ? (Integer) r.Participants__c : 0;
                row.contributorsLabel = p + ' contributor' + (p == 1 ? '' : 's');
                row.raisedDisplay = String.isNotBlank(r.Raised_Display__c)
                    ? r.Raised_Display__c : formatInr(r.Raised_Amount__c);
                out.add(row);
            }
        } catch (Exception e) { /* tolerate */ }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<OpportunityRow> getOpportunities() {
        List<OpportunityRow> rows = new List<OpportunityRow>();
        try {
            List<Ken_Giving_Opportunity__c> ops = [
                SELECT Id, Title__c, Short_Description__c, Category__c, Status__c, Image_URL__c,
                       Raised_Amount__c, Target_Amount__c, Contributors_Count__c, Days_Left__c
                FROM Ken_Giving_Opportunity__c
                WHERE Status__c IN ('Live','Approved','Open')
                ORDER BY Raised_Amount__c DESC NULLS LAST, LastModifiedDate DESC
                LIMIT 100];
            Boolean first = true;
            for (Ken_Giving_Opportunity__c o : ops) {
                OpportunityRow r = new OpportunityRow();
                r.id = o.Id;
                r.title = o.Title__c;
                r.shortDescription = o.Short_Description__c;
                r.category = String.isNotBlank(o.Category__c) ? o.Category__c : 'General';
                r.status = String.isNotBlank(o.Status__c) ? o.Status__c : 'Approved';
                r.imageUrl = o.Image_URL__c;
                r.raisedAmount = (o.Raised_Amount__c != null) ? o.Raised_Amount__c : 0;
                r.targetAmount = (o.Target_Amount__c != null) ? o.Target_Amount__c : 0;
                r.raisedDisplay = formatInr(r.raisedAmount);
                r.goalDisplay   = 'of ' + formatInr(r.targetAmount) + ' goal';
                r.contributorsCount = (o.Contributors_Count__c != null) ? (Integer) o.Contributors_Count__c : 0;
                r.daysLeft = (o.Days_Left__c != null) ? (Integer) o.Days_Left__c : 0;
                r.progressPercent = computePct(r.raisedAmount, r.targetAmount);
                r.isFeatured = first; // top-raised opp is the hero
                first = false;
                rows.add(r);
            }
        } catch (Exception e) { /* tolerate */ }
        return rows;
    }

    // ========================================================== helpers

    @TestVisible
    private static Integer computePct(Decimal raised, Decimal target) {
        if (target == null || target == 0) return 0;
        Decimal pct = (raised == null ? 0 : raised) / target * 100;
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        return Integer.valueOf(pct.setScale(0, System.RoundingMode.HALF_UP));
    }

    @TestVisible
    private static String formatInr(Decimal amt) {
        if (amt == null) amt = 0;
        if (amt >= 10000000) {            // ≥ 1 Cr
            Decimal v = (amt / 10000000).setScale(2, System.RoundingMode.HALF_UP);
            return '₹' + v.toPlainString() + ' Cr';
        } else if (amt >= 100000) {       // ≥ 1 L
            Decimal v = (amt / 100000).setScale(2, System.RoundingMode.HALF_UP);
            return '₹' + v.toPlainString() + ' L';
        }
        return '₹' + amt.setScale(0, System.RoundingMode.HALF_UP).format();
    }
}