/**
 * End-to-end coverage for the Giving edge-write → materialize pipeline:
 *   KenGiftContributionController (edge write)
 *   KenGiftPaymentTriggerHandler  (capture detection)
 *   KenGiftMaterializerService    (Opportunity materialization + idempotency)
 *   KenGiftContribution/Allocation validation triggers
 *
 * Proves: one captured payment yields exactly ONE Donation Opportunity, with the
 * OpportunityContactRole and cloned core allocations, and that a webhook retry never
 * creates a duplicate.
 */
@IsTest
private class KenGiftMaterializerTest {

    private static final String DONOR_EMAIL = 'uat.donor@example.com';

    private static Ken_Giving_Fund__c makeFund() {
        Ken_Giving_Fund__c f = new Ken_Giving_Fund__c(
            Name = 'UAT Fund',
            Code__c = 'UAT-' + String.valueOf(Datetime.now().getTime())
        );
        insert f;
        return f;
    }

    /** Build a contribution + two allocations (summing to amount) + a pending payment. */
    private static Ken_Gift_Payment__c buildEdgeRecords(Decimal amount, Ken_Giving_Fund__c fund) {
        Ken_Gift_Contribution__c c = new Ken_Gift_Contribution__c(
            Donor_First_Name__c = 'Uat',
            Donor_Last_Name__c = 'Donor',
            Donor_Email__c = DONOR_EMAIL,
            Amount__c = amount,
            Status__c = 'Pending Payment',
            Source__c = 'Portal',
            Request_Id__c = 'UAT-REQ-' + String.valueOf(Datetime.now().getTime())
        );
        insert c;

        insert new List<Ken_Gift_Allocation__c>{
            new Ken_Gift_Allocation__c(Contribution__c = c.Id, Fund__c = fund.Id, Amount__c = amount * 0.6),
            new Ken_Gift_Allocation__c(Contribution__c = c.Id, Fund__c = fund.Id, Amount__c = amount * 0.4)
        };

        Ken_Gift_Payment__c pay = new Ken_Gift_Payment__c(
            Contribution__c = c.Id,
            Provider__c = 'Stripe',
            Provider_Txn_Id__c = 'txn-' + String.valueOf(Datetime.now().getTime()),
            Idempotency_Key__c = 'idem-' + String.valueOf(Datetime.now().getTime()),
            Status__c = 'Pending',
            Amount__c = amount
        );
        insert pay;
        return pay;
    }

    @IsTest
    static void captureMaterializesExactlyOneOpportunity() {
        Ken_Giving_Fund__c fund = makeFund();
        Ken_Gift_Payment__c pay = buildEdgeRecords(1000, fund);
        Id contribId = pay.Contribution__c;

        Test.startTest();
        // Simulate the gateway capturing the payment.
        pay.Status__c = 'Captured';
        update pay;
        Test.stopTest();

        // ----- contribution confirmed + linked -----
        Ken_Gift_Contribution__c c = [
            SELECT Id, Status__c, Opportunity__c, Donor_Contact__c
            FROM Ken_Gift_Contribution__c WHERE Id = :contribId
        ];
        System.assertEquals('Confirmed', c.Status__c, 'Contribution should be Confirmed after capture');
        System.assertNotEquals(null, c.Opportunity__c, 'Contribution should link to its Opportunity');
        System.assertNotEquals(null, c.Donor_Contact__c, 'Donor Contact should be matched/created');

        // ----- exactly ONE Opportunity, Donation RT, Closed Won -----
        List<Opportunity> opps = [
            SELECT Id, StageName, IsWon, Amount, RecordType.DeveloperName
            FROM Opportunity WHERE Ken_Giving_Contribution__c = :contribId
        ];
        System.assertEquals(1, opps.size(), 'Exactly one Opportunity should be materialized');
        System.assertEquals('Ken_Giving_Donation', opps[0].RecordType.DeveloperName, 'Donation record type expected');
        System.assertEquals('Closed Won', opps[0].StageName, 'Stage should be Closed Won');
        System.assertEquals(true, opps[0].IsWon, 'Opportunity should be Won');
        System.assertEquals(1000, opps[0].Amount, 'Opportunity amount should equal the gift');

        // ----- OpportunityContactRole (Donor, primary) -----
        List<OpportunityContactRole> ocrs = [
            SELECT Id, Role, IsPrimary, ContactId
            FROM OpportunityContactRole WHERE OpportunityId = :opps[0].Id
        ];
        System.assertEquals(1, ocrs.size(), 'One OpportunityContactRole expected');
        System.assertEquals('Donor', ocrs[0].Role, 'Role should be Donor');
        System.assertEquals(true, ocrs[0].IsPrimary, 'Contact role should be primary');
        System.assertEquals(c.Donor_Contact__c, ocrs[0].ContactId, 'OCR should reference the matched donor Contact');

        // ----- core allocations cloned (2 lines, summing to amount) -----
        List<Ken_Gift_Opportunity_Allocation__c> coreAllocs = [
            SELECT Id, Amount__c, Fund__c, Source_Allocation__c
            FROM Ken_Gift_Opportunity_Allocation__c WHERE Opportunity__c = :opps[0].Id
        ];
        System.assertEquals(2, coreAllocs.size(), 'Both edge allocations should clone to the core');
        Decimal coreSum = 0;
        for (Ken_Gift_Opportunity_Allocation__c a : coreAllocs) {
            coreSum += a.Amount__c;
            System.assertEquals(fund.Id, a.Fund__c, 'Cloned allocation should keep the Fund');
            System.assertNotEquals(null, a.Source_Allocation__c, 'Cloned allocation should trace to its edge source');
        }
        System.assertEquals(1000, coreSum, 'Cloned allocations should sum to the gift amount');
    }

    @IsTest
    static void webhookRetryDoesNotDuplicate() {
        Ken_Giving_Fund__c fund = makeFund();
        Ken_Gift_Payment__c pay = buildEdgeRecords(500, fund);
        Id contribId = pay.Contribution__c;

        Test.startTest();
        // First capture -> materializes.
        pay.Status__c = 'Captured';
        update pay;

        // Webhook retry: the same payment is updated again (still 'Captured').
        Ken_Gift_Payment__c again = [SELECT Id, Status__c, Provider_Txn_Id__c FROM Ken_Gift_Payment__c WHERE Id = :pay.Id];
        again.Provider_Txn_Id__c = again.Provider_Txn_Id__c + '-retry';
        update again;
        Test.stopTest();

        Integer oppCount = [SELECT COUNT() FROM Opportunity WHERE Ken_Giving_Contribution__c = :contribId];
        System.assertEquals(1, oppCount, 'Idempotency: a webhook retry must NOT create a second Opportunity');

        Integer ocrCount = [
            SELECT COUNT() FROM OpportunityContactRole
            WHERE OpportunityId IN (SELECT Id FROM Opportunity WHERE Ken_Giving_Contribution__c = :contribId)
        ];
        System.assertEquals(1, ocrCount, 'Idempotency: no duplicate OpportunityContactRole');

        Integer coreAllocCount = [
            SELECT COUNT() FROM Ken_Gift_Opportunity_Allocation__c
            WHERE Opportunity__c IN (SELECT Id FROM Opportunity WHERE Ken_Giving_Contribution__c = :contribId)
        ];
        System.assertEquals(2, coreAllocCount, 'Idempotency: allocations not re-cloned on retry');
    }

    @IsTest
    static void existingContactIsReusedNotDuplicated() {
        // Pre-existing contact with the donor email -> materializer should match, not create.
        Contact existing = new Contact(FirstName = 'Existing', LastName = 'Donor', Email = DONOR_EMAIL);
        insert existing;

        Ken_Giving_Fund__c fund = makeFund();
        Ken_Gift_Payment__c pay = buildEdgeRecords(250, fund);
        Id contribId = pay.Contribution__c;

        Test.startTest();
        pay.Status__c = 'Captured';
        update pay;
        Test.stopTest();

        Ken_Gift_Contribution__c c = [SELECT Donor_Contact__c FROM Ken_Gift_Contribution__c WHERE Id = :contribId];
        System.assertEquals(existing.Id, c.Donor_Contact__c, 'Materializer should reuse the existing Contact by email');
        Integer contactCount = [SELECT COUNT() FROM Contact WHERE Email = :DONOR_EMAIL];
        System.assertEquals(1, contactCount, 'No duplicate Contact should be created for the same email');
    }

    @IsTest
    static void edgeWriteControllerInsertsAndIsIdempotent() {
        Ken_Giving_Fund__c fund = makeFund();

        KenGiftContributionController.GiftAllocationInput a1 = new KenGiftContributionController.GiftAllocationInput();
        a1.fundId = fund.Id; a1.amount = 300;
        KenGiftContributionController.GiftPaymentInput p = new KenGiftContributionController.GiftPaymentInput();
        p.provider = 'Stripe'; p.providerTxnId = 'ctrl-txn'; p.idempotencyKey = 'ctrl-idem';
        p.status = 'Captured'; p.amount = 300;

        KenGiftContributionController.GiftRequest req = new KenGiftContributionController.GiftRequest();
        req.donorFirstName = 'Ctrl'; req.donorLastName = 'Donor';
        req.donorEmail = 'ctrl.donor@example.com'; req.amount = 300;
        req.frequency = 'One-time'; req.source = 'Portal';
        req.requestId = 'CTRL-REQ-1';
        req.allocations = new List<KenGiftContributionController.GiftAllocationInput>{ a1 };
        req.payment = p;

        Test.startTest();
        KenGiftContributionController.GiftResult r1 = KenGiftContributionController.submitContribution(req);
        // Same requestId -> idempotent return, no second contribution.
        KenGiftContributionController.GiftResult r2 = KenGiftContributionController.submitContribution(req);
        Test.stopTest();

        System.assertEquals(false, r1.alreadyExisted, 'First submit should create a new contribution');
        System.assertEquals(true, r2.alreadyExisted, 'Second submit with same requestId should be a no-op');
        System.assertEquals(r1.contributionId, r2.contributionId, 'Idempotent submit returns the same contribution');

        Integer count = [SELECT COUNT() FROM Ken_Gift_Contribution__c WHERE Request_Id__c = 'CTRL-REQ-1'];
        System.assertEquals(1, count, 'Only one contribution should exist for the request id');
        Integer oppCount = [SELECT COUNT() FROM Opportunity WHERE Ken_Giving_Contribution__c = :r1.contributionId];
        System.assertEquals(1, oppCount, 'Captured controller submit should materialize exactly one Opportunity');
    }

    @IsTest
    static void validationRejectsBadData() {
        Ken_Giving_Fund__c fund = makeFund();

        // Amount <= 0 rejected.
        try {
            insert new Ken_Gift_Contribution__c(Amount__c = 0, Status__c = 'Pending Payment',
                Request_Id__c = 'BAD-1', Donor_Email__c = 'x@example.com');
            System.assert(false, 'Zero amount should be rejected');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('greater than zero'), 'Expected amount validation: ' + e.getMessage());
        }

        // Allocations that do not sum to amount are rejected.
        Ken_Gift_Contribution__c c = new Ken_Gift_Contribution__c(Amount__c = 100, Status__c = 'Pending Payment',
            Request_Id__c = 'BAD-2', Donor_Email__c = 'y@example.com');
        insert c;
        try {
            insert new Ken_Gift_Allocation__c(Contribution__c = c.Id, Fund__c = fund.Id, Amount__c = 60); // 60 != 100
            System.assert(false, 'Mismatched allocation sum should be rejected');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('sum to the donation amount'), 'Expected sum validation: ' + e.getMessage());
        }
    }
}