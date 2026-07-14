@isTest
private class KenJobOfferControllerTest {

    // Offer is a master-detail child of Application, so every offer needs a parent.
    private static Id makeApplication() {
        Contact c = new Contact(LastName = 'Offer Tester');
        insert c;
        Ken_Job_Master__c job = new Ken_Job_Master__c(
            Company__c = 'Acme', Job_Title__c = 'Engineer', Status__c = 'Live');
        insert job;
        Ken_Job_Application__c app = new Ken_Job_Application__c(
            Job__c = job.Id, Applicant__c = c.Id, Applicant_Type__c = 'Alumni',
            Status__c = 'Offered', Application_State__c = 'offered');
        insert app;
        return app.Id;
    }

    private static Ken_Job_Offer__c makeOffer(Id appId, Decimal ctc, Decimal fixedC, Decimal varC,
                                              Decimal bonus, String perksJson) {
        return new Ken_Job_Offer__c(
            Application__c = appId,
            Role__c = 'Software Engineer',
            Total_CTC__c = '18 LPA',                 // legacy required text
            Location__c = 'Toronto',
            Total_CTC_Amount__c = ctc,
            Fixed_Comp_Amount__c = fixedC,
            Variable_Comp_Amount__c = varC,
            Joining_Bonus_Amount__c = bonus,
            Work_Type__c = 'Hybrid',
            Bond__c = '12-month bond',
            Bond_Months__c = 12,
            Perks_JSON__c = perksJson);
    }

    @isTest
    static void retrievesTypedCurrencyAndPerks() {
        Id appId = makeApplication();
        List<Ken_Job_Offer__c> offers = new List<Ken_Job_Offer__c>{
            makeOffer(appId, 1800000, 1500000, 200000, 100000, '["Health Insurance","Stock Options"]'),
            makeOffer(appId, 2200000, 1800000, 300000, 100000, '[{"label":"Gym"},{"label":"Meals"}]')
        };
        insert offers;

        Test.startTest();
        List<KenJobOfferController.OfferView> views =
            KenJobOfferController.getOffersForComparison(new List<Id>{ offers[0].Id, offers[1].Id });
        Test.stopTest();

        System.assertEquals(2, views.size());
        Map<Id, KenJobOfferController.OfferView> byId =
            new Map<Id, KenJobOfferController.OfferView>();
        for (KenJobOfferController.OfferView v : views) byId.put(v.id, v);

        KenJobOfferController.OfferView a = byId.get(offers[0].Id);
        System.assertEquals(1800000, a.totalCtc, 'CTC retrieved');
        System.assertEquals(1500000, a.fixedComp);
        System.assertEquals(200000, a.variableComp);
        System.assertEquals(100000, a.joiningBonus);
        // fixed + variable + bonus reconciles against CTC math the UI displays
        System.assertEquals(a.totalCtc, a.fixedComp + a.variableComp + a.joiningBonus,
            'breakdown sums to total');
        System.assertEquals('Hybrid', a.workType);
        System.assertEquals(12, a.bondMonths);
        System.assertEquals(2, a.perks.size(), 'string-array perks parsed');
        System.assertEquals('Health Insurance', a.perks[0]);

        KenJobOfferController.OfferView b = byId.get(offers[1].Id);
        System.assertEquals(2, b.perks.size(), 'object-array perks parsed via label');
        System.assertEquals('Gym', b.perks[0]);
    }

    @isTest
    static void perksCsvFallbackAndEmpty() {
        // CSV fallback (not valid JSON array) + blank handling
        System.assertEquals(0, KenJobOfferController.parsePerks(null).size());
        System.assertEquals(0, KenJobOfferController.parsePerks('   ').size());
        List<String> csv = KenJobOfferController.parsePerks('Laptop, Relocation, Bonus');
        System.assertEquals(3, csv.size());
        System.assertEquals('Relocation', csv[1]);
    }

    @isTest
    static void emptyOfferIdListReturnsEmpty() {
        System.assertEquals(0, KenJobOfferController.getOffersForComparison(null).size());
        System.assertEquals(0,
            KenJobOfferController.getOffersForComparison(new List<Id>()).size());
    }

    @isTest
    static void submitsInquiry() {
        Contact c = new Contact(LastName = 'Inquiry Tester');
        insert c;
        Id appId = makeApplication();
        Ken_Job_Offer__c o1 = makeOffer(appId, 1800000, 1500000, 200000, 100000, '["A"]');
        Ken_Job_Offer__c o2 = makeOffer(appId, 2000000, 1700000, 200000, 100000, '["B"]');
        insert new List<Ken_Job_Offer__c>{ o1, o2 };
        KenJobOfferController.testContactId = c.Id;

        Test.startTest();
        Id inqId = KenJobOfferController.submitOfferInquiry(o1.Id, o2.Id, '  Which has better growth?  ');
        Test.stopTest();

        Ken_Offer_Inquiry__c inq = [
            SELECT Offer_A__c, Offer_B__c, Question__c, Status__c, Asked_By__c
            FROM Ken_Offer_Inquiry__c WHERE Id = :inqId];
        System.assertEquals(o1.Id, inq.Offer_A__c);
        System.assertEquals(o2.Id, inq.Offer_B__c);
        System.assertEquals('Which has better growth?', inq.Question__c, 'trimmed');
        System.assertEquals('Open', inq.Status__c);
        System.assertEquals(c.Id, inq.Asked_By__c, 'stamped with running contact');
    }

    @isTest
    static void blankQuestionThrows() {
        Boolean thrown = false;
        try {
            KenJobOfferController.submitOfferInquiry(null, null, '   ');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'blank question should throw');
    }
}