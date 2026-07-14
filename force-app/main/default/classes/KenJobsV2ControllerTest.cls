@isTest
private class KenJobsV2ControllerTest {

    @testSetup
    static void setup() {
        Account a = new Account(Name = 'Test University');
        insert a;

        Contact c = new Contact(FirstName = 'Test', LastName = 'Alumni', Email = 'test.alumni@example.com', AccountId = a.Id);
        insert c;

        Ken_Placement_Cycle__c cy = new Ken_Placement_Cycle__c(
            Name = 'Placement Cycle ' + Date.today().year(),
            Year__c = Date.today().year(),
            Interviews_Count__c = 3,
            Offers_Count__c = 1,
            Exams_Count__c = 2,
            Applications_Sub__c = '+2 this week',
            Interviews_Sub__c = '1 upcoming',
            Offers_Sub__c = '1 pending review',
            Exams_Sub__c = 'Scheduled'
        );
        insert cy;

        List<Ken_Placement_Stage__c> stages = new List<Ken_Placement_Stage__c>{
            new Ken_Placement_Stage__c(Name = 'Stage 1: Registered', Cycle__c = cy.Id, Stage_Label__c = 'Registered', Stage_Order__c = 1, State__c = 'done', Stage_Date__c = Date.today().addDays(-60)),
            new Ken_Placement_Stage__c(Name = 'Stage 2: Eligible',  Cycle__c = cy.Id, Stage_Label__c = 'Eligible',   Stage_Order__c = 2, State__c = 'done', Stage_Date__c = Date.today().addDays(-45)),
            new Ken_Placement_Stage__c(Name = 'Stage 3: Interview', Cycle__c = cy.Id, Stage_Label__c = 'Interview',  Stage_Order__c = 3, State__c = 'current', Stage_Date__c = Date.today())
        };
        insert stages;

        Ken_Job_Master__c j = new Ken_Job_Master__c(
            Job_Title__c = 'Developer', Company__c = 'Paypal',
            Logo_Initial__c = 'P', Logo_Color__c = '#003087',
            Salary_Display__c = '₹ 5 LPA', Status__c = 'Live',
            Placement_Cycle__c = cy.Id, Deadline__c = Date.today().addDays(15)
        );
        insert j;

        insert new Ken_Job_Tag__c(Job__c = j.Id, Tag__c = 'Information Technology');
        insert new Ken_Job_Skill__c(Job__c = j.Id, Name = 'Apex');
    }

    @isTest
    static void testGetJobsPage() {
        Test.startTest();
        KenJobsV2Controller.JobsPageData data = KenJobsV2Controller.getJobsPage();
        Test.stopTest();
        System.assertNotEquals(null, data);
        System.assertNotEquals(null, data.allJobs);
        System.assert(data.allJobs.size() >= 1, 'expected at least 1 job');
    }

    @isTest
    static void testGetJob() {
        Ken_Job_Master__c j = [SELECT Id FROM Ken_Job_Master__c LIMIT 1];
        KenJobsV2Controller.JobItem ji = KenJobsV2Controller.getJob(j.Id);
        System.assertNotEquals(null, ji);
        System.assertEquals('Paypal', ji.company);
        Boolean nullThrew = false;
        try { KenJobsV2Controller.getJob(null); } catch (AuraHandledException e) { nullThrew = true; }
        System.assert(nullThrew, 'getJob(null) should throw');
    }

    @isTest
    static void testGetApplicants() {
        Ken_Job_Master__c j = [SELECT Id FROM Ken_Job_Master__c LIMIT 1];
        List<KenJobsV2Controller.ApplicantItem> list1 = KenJobsV2Controller.getApplicants(j.Id);
        System.assertNotEquals(null, list1);
        System.assertEquals(0, KenJobsV2Controller.getApplicants(null).size());
    }

    @isTest
    static void testGetMyOffers() {
        List<KenJobsV2Controller.OfferComparisonItem> offers = KenJobsV2Controller.getMyOffers();
        System.assertNotEquals(null, offers);
    }

    @isTest
    static void testGetPlacementCycle() {
        KenJobsV2Controller.PlacementCycleDTO pc = KenJobsV2Controller.getPlacementCycle();
        System.assertNotEquals(null, pc);
        System.assertEquals(4, pc.stats.size());
    }

    @isTest
    static void testApplyAndSaveAndSlots() {
        Ken_Job_Master__c j = [SELECT Id FROM Ken_Job_Master__c LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        // Simulate currentContactId via test context — won't link User->Contact in test,
        // so just test the write methods exercise their code paths and throw appropriately.
        try {
            KenJobsV2Controller.toggleSaveJob(j.Id);
        } catch (Exception e) { /* expected if no contact mapping */ }
        try {
            Map<String,Object> p = new Map<String,Object>{ 'jobId' => j.Id, 'applicantType' => 'Alumni' };
            KenJobsV2Controller.applyToJob(p);
        } catch (Exception e) { /* expected if no contact mapping */ }

        // Direct slot insert + bookSlot
        Ken_Job_Application__c app = new Ken_Job_Application__c(
            Job__c = j.Id, Applicant__c = c.Id, Applicant_Type__c = 'Alumni',
            Status__c = 'Interview', Application_State__c = 'actionRequired'
        );
        insert app;
        Ken_Job_Slot__c slot = new Ken_Job_Slot__c(
            Application__c = app.Id, Slot_Date__c = Date.today().addDays(3),
            Period__c = 'Morning', Time_Label__c = '09:00 AM IST', Status__c = 'Available'
        );
        insert slot;

        List<KenJobsV2Controller.SlotItem> slots = KenJobsV2Controller.getInterviewSlots(app.Id);
        System.assert(slots.size() >= 1);

        Id booked = KenJobsV2Controller.bookSlot(app.Id, slot.Id);
        System.assertEquals(slot.Id, booked);
        Ken_Job_Slot__c reread = [SELECT Status__c FROM Ken_Job_Slot__c WHERE Id = :slot.Id];
        System.assertEquals('Booked', reread.Status__c);
    }

    @isTest
    static void testPostJob() {
        Map<String,Object> p = new Map<String,Object>{
            'title' => 'New Job', 'company' => 'Acme', 'logoInitial' => 'A', 'logoColor' => '#123456',
            'shortDescription' => 'short', 'fullDescription' => 'long',
            'experienceLevel' => '2-5 yrs', 'location' => 'Bangalore',
            'salaryDisplay' => '10 LPA', 'salaryMin' => 800000, 'salaryMax' => 1000000,
            'currencyCode' => 'INR', 'openings' => 2, 'timeline' => '4 weeks',
            'audience' => 'All Alumni',
            'tags' => new List<Object>{ 'Remote', 'Startup' },
            'skills' => new List<Object>{ 'Apex', 'LWC' }
        };
        Id newId = KenJobsV2Controller.postJob(p);
        System.assertNotEquals(null, newId);
        Ken_Job_Master__c j = [SELECT Status__c FROM Ken_Job_Master__c WHERE Id = :newId];
        System.assertEquals('Submitted for Review', j.Status__c);
    }
}