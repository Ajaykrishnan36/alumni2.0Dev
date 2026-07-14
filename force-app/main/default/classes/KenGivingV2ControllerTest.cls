@isTest
private class KenGivingV2ControllerTest {

    @testSetup static void setup() {
        Contact c = new Contact(FirstName='Test', LastName='Alum', Email='t.alum@example.com');
        insert c;

        Ken_Giving_Opportunity__c o = new Ken_Giving_Opportunity__c(
            Name='Test Scholarship', Title__c='Test Scholarship', Category__c='Scholarships',
            Short_Description__c='Test', Status__c='Live', Target_Amount__c=100000,
            External_Id__c='test-scholarship');
        insert o;

        insert new Ken_Giving_Allocation__c(Opportunity__c=o.Id, Allocation_Label__c='Aid', Percent__c=80);
        insert new Ken_Giving_Suggested_Amount__c(Opportunity__c=o.Id, Amount__c=5000, Sort_Order__c=1);
        insert new Ken_Giving_Update__c(Name='U1', Opportunity__c=o.Id,
            Update_Date_Label__c='MAR 2026', Headline__c='Update', Body__c='Body');

        insert new Ken_Giving_Batch_Ranking__c(Name='2014', Batch__c='2014',
            Participants__c=50, Raised_Display__c='₹10 L', Raised_Amount__c=1000000);
        insert new Ken_Giving_Corporate_Supporter__c(Name='Infosys');
    }

    @isTest static void testGetOpportunitiesPage() {
        KenGivingV2Controller.GivingPageData d = KenGivingV2Controller.getOpportunitiesPage();
        System.assertNotEquals(null, d);
        System.assert(d.opportunities.size() >= 1);
        System.assert(d.topBatches.size() >= 1);
        System.assert(d.corporateSupporters.size() >= 1);
    }

    @isTest static void testGetOpportunityDetail() {
        Ken_Giving_Opportunity__c o = [SELECT Id FROM Ken_Giving_Opportunity__c LIMIT 1];
        KenGivingV2Controller.OpportunityDetailDTO d = KenGivingV2Controller.getOpportunityDetail(o.Id);
        System.assertNotEquals(null, d.opportunity);
        System.assert(d.allocations.size() >= 1);
        System.assert(d.suggestedAmounts.size() >= 1);
        System.assert(d.updates.size() >= 1);
    }

    @isTest static void testGetMyGiving() {
        List<KenGivingV2Controller.ContributionDTO> mine = KenGivingV2Controller.getMyGiving();
        System.assertNotEquals(null, mine);
    }

    @isTest static void testGetImpactUpdates() {
        List<KenGivingV2Controller.UpdateDTO> ups = KenGivingV2Controller.getImpactUpdates();
        System.assert(ups.size() >= 1);
    }

    @isTest static void testGetFundraiseOpportunities() {
        Ken_Giving_Opportunity__c o = [SELECT Id FROM Ken_Giving_Opportunity__c LIMIT 1];
        o.Cause__c = 'Education';
        o.Theme_Color__c = '#3061FF';
        update o;
        List<KenGivingV2Controller.OpportunityCardDTO> list1 = KenGivingV2Controller.getFundraiseOpportunities();
        System.assert(list1.size() >= 1);
    }

    @isTest static void testSubmitInitiative() {
        Map<String,Object> p = new Map<String,Object>{
            'title' => 'My Initiative',
            'category' => 'Student Support',
            'shortDesc' => 'Help students',
            'target' => 50000
        };
        Id id1 = KenGivingV2Controller.submitInitiative(p);
        System.assertNotEquals(null, id1);
        Ken_Giving_Opportunity__c r = [SELECT Status__c FROM Ken_Giving_Opportunity__c WHERE Id = :id1];
        System.assertEquals('Submitted for Review', r.Status__c);
    }
}