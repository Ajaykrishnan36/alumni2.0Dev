@IsTest
private class KenAlumniDashboardControllerTest {

    @TestSetup
    static void makeData() {
        Id paRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Alumni_Person_Account').getRecordTypeId();

        Account a1 = new Account(
            RecordTypeId=paRtId, LastName='Test Alumni One',
            PersonEmail='alumni1_dash@test.com', PersonMobilePhone='9000000001',
            Description='About me', BillingCountry='India',
            PersonBirthdate=Date.newInstance(1990,1,15)
        );
        Account a2 = new Account(
            RecordTypeId=paRtId, LastName='Test Alumni Two',
            PersonEmail='alumni2_dash@test.com', BillingCountry='USA',
            PersonBirthdate=Date.newInstance(1985,6,20)
        );
        insert new List<Account>{ a1, a2 };

        ConstituentRole cr1 = new ConstituentRole(
            PersonId=a1.Id, RoleType='Alumni',
            Graduation_Year__c='2015', Registration_Status__c='Registered',
            Email__c='alumni1_dash@test.com'
        );
        cr1.put('Status', 'Active');
        ConstituentRole cr2 = new ConstituentRole(
            PersonId=a2.Id, RoleType='Alumni',
            Graduation_Year__c='2010', Registration_Status__c='Unregistered',
            Email__c='alumni2_dash@test.com'
        );
        cr2.put('Status', 'Admitted');
        insert new List<ConstituentRole>{ cr1, cr2 };

        insert new List<Ken_Address__c>{
            new Ken_Address__c(Person_Account__c=a1.Id, Country__c='India', State__c='Maharashtra'),
            new Ken_Address__c(Person_Account__c=a2.Id, Country__c='USA',   State__c='New York')
        };

        insert new List<PersonEmployment>{
            new PersonEmployment(Name='Job 1', RelatedPersonId=a1.Id, EmploymentStatus='Employed',      Occupation='Technology', Is_Archived__c=false),
            new PersonEmployment(Name='Job 2', RelatedPersonId=a2.Id, EmploymentStatus='Self-Employed', Occupation='Finance',    Is_Archived__c=false)
        };

        insert new Ken_Alumni_Preferences__c(
            Person_Account__c=a1.Id,
            Skill_set__c='Leadership;Innovation'
        );

        insert new Ken_Alumni_CRM__c(
            Person_Account__c=a1.Id,
            Specialization__c='Engineering',
            Year_of_Graduation__c='2015',
            Profile_Photo_URL__c='https://test.com/photo.jpg'
        );
    }

    // ── Filter options ──────────────────────────────────────────────────────

    @IsTest
    static void testGetFilterOptions() {
        Test.startTest();
        KenAlumniDashboardController.FilterOptions opts = KenAlumniDashboardController.getFilterOptions();
        Test.stopTest();
        System.assertNotEquals(null, opts);
        System.assertNotEquals(null, opts.batches);
        System.assert(opts.years.size() >= 1, 'Years should be populated from test data');
    }

    // ── Summary stats ───────────────────────────────────────────────────────

    @IsTest
    static void testGetSummaryStats_noFilter() {
        Test.startTest();
        KenAlumniDashboardController.SummaryStats s = KenAlumniDashboardController.getSummaryStats(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, s);
        System.assert(s.totalAlumni >= 2);
        System.assert(s.activeAlumni >= 1);
        System.assert(s.activePercent >= 0);
        System.assert(s.avgCompleteness >= 0);
    }

    @IsTest
    static void testGetSummaryStats_withYearAndStatus() {
        Test.startTest();
        KenAlumniDashboardController.SummaryStats s = KenAlumniDashboardController.getSummaryStats(null, '2015', 'Active');
        Test.stopTest();
        System.assertNotEquals(null, s);
        System.assert(s.totalAlumni >= 1);
    }

    @IsTest
    static void testGetSummaryStats_emptyResult() {
        Test.startTest();
        KenAlumniDashboardController.SummaryStats s = KenAlumniDashboardController.getSummaryStats(null, '1800', null);
        Test.stopTest();
        System.assertEquals(0, s.totalAlumni);
        System.assertEquals(0, s.avgCompleteness);
    }

    // ── Chart methods ───────────────────────────────────────────────────────

    @IsTest
    static void testGetActiveAlumniByBatch() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getActiveAlumniByBatch(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetActiveAlumniByBatch_withFilters() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getActiveAlumniByBatch(null, '2015', null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetGraduationYearDistribution() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getGraduationYearDistribution(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetGraduationYearDistribution_withStatus() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getGraduationYearDistribution(null, null, 'Active');
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetAgeDistribution_withData() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getAgeDistribution(null, null, null);
        Test.stopTest();
        System.assertEquals(5, items.size());
        Integer total = 0;
        for (KenAlumniDashboardController.ChartItem ci : items) total += ci.value;
        System.assert(total >= 2, 'Should have counted at least 2 alumni by age');
    }

    @IsTest
    static void testGetAgeDistribution_emptySet() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getAgeDistribution(null, '1800', null);
        Test.stopTest();
        System.assertEquals(5, items.size());
        for (KenAlumniDashboardController.ChartItem ci : items) System.assertEquals(0, ci.value);
    }

    @IsTest
    static void testGetEmploymentStatus() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getEmploymentStatus(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetEmploymentStatus_empty() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getEmploymentStatus(null, '1800', null);
        Test.stopTest();
        System.assertEquals(0, items.size());
    }

    @IsTest
    static void testGetTopSkillsAndInterests() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getTopSkillsAndInterests(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetTopSkillsAndInterests_empty() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getTopSkillsAndInterests(null, '1800', null);
        Test.stopTest();
        System.assertEquals(0, items.size());
    }

    @IsTest
    static void testGetLifecycleDistribution() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getLifecycleDistribution(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetMobilityByCountry() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getMobilityByCountry(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetIndiaStateDistribution() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getIndiaStateDistribution(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetProfileCompleteness_withData() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getProfileCompleteness(null, null, null);
        Test.stopTest();
        System.assertEquals(4, items.size());
        Integer total = 0;
        for (KenAlumniDashboardController.ChartItem ci : items) total += ci.value;
        System.assert(total >= 2);
    }

    @IsTest
    static void testGetProfileCompleteness_emptySet() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getProfileCompleteness(null, '1800', null);
        Test.stopTest();
        System.assertEquals(4, items.size());
        for (KenAlumniDashboardController.ChartItem ci : items) System.assertEquals(0, ci.value);
    }

    @IsTest
    static void testGetBatchDemographics() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getBatchDemographics(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetBatchDemographics_withFilters() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getBatchDemographics(null, '2015', 'Active');
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetGenderDistribution() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getGenderDistribution(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetMultiDimensionalInsights() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getMultiDimensionalInsights(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetMultiDimensionalInsights_withFilters() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getMultiDimensionalInsights(null, '2015', 'Active');
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetProfessionalDistribution() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getProfessionalDistribution(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetWorldDistribution() {
        Test.startTest();
        List<KenAlumniDashboardController.ChartItem> items = KenAlumniDashboardController.getWorldDistribution(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    // ── getAlumniList — all dimension branches ──────────────────────────────

    @IsTest
    static void testGetAlumniList_completenessAndDefault() {
        Test.startTest();
        List<KenAlumniDashboardController.AlumniRecord> compl = KenAlumniDashboardController.getAlumniList('completeness', null, null, null, null);
        List<KenAlumniDashboardController.AlumniRecord> deflt = KenAlumniDashboardController.getAlumniList('unknown_dim', 'someValue', null, null, null);
        Test.stopTest();
        System.assert(compl.size() >= 2);
        System.assert(deflt.size() >= 2);
        System.assertNotEquals(null, compl[0].id);
        System.assertNotEquals(null, compl[0].name);
    }

    @IsTest
    static void testGetAlumniList_emptyBaseIds() {
        Test.startTest();
        List<KenAlumniDashboardController.AlumniRecord> recs = KenAlumniDashboardController.getAlumniList('country', 'India', null, '1800', null);
        Test.stopTest();
        System.assertEquals(0, recs.size());
    }

    @IsTest
    static void testGetAlumniList_batch() {
        Test.startTest();
        KenAlumniDashboardController.getAlumniList('batch', 'Not Specified', null, null, null);
        KenAlumniDashboardController.getAlumniList('batch', 'SomeBatchName', null, null, null);
        Test.stopTest();
    }

    @IsTest
    static void testGetAlumniList_year() {
        Test.startTest();
        List<KenAlumniDashboardController.AlumniRecord> byYear = KenAlumniDashboardController.getAlumniList('year', '2015', null, null, null);
        KenAlumniDashboardController.getAlumniList('year', 'Not Specified', null, null, null);
        Test.stopTest();
        System.assert(byYear.size() >= 1);
    }

    @IsTest
    static void testGetAlumniList_gender() {
        Test.startTest();
        KenAlumniDashboardController.getAlumniList('gender', 'Male', null, null, null);
        KenAlumniDashboardController.getAlumniList('gender', 'Not Specified', null, null, null);
        Test.stopTest();
    }

    @IsTest
    static void testGetAlumniList_countryAndState() {
        Test.startTest();
        List<KenAlumniDashboardController.AlumniRecord> byCountry = KenAlumniDashboardController.getAlumniList('country', 'India', null, null, null);
        List<KenAlumniDashboardController.AlumniRecord> byState   = KenAlumniDashboardController.getAlumniList('state',   'Maharashtra', null, null, null);
        Test.stopTest();
        System.assert(byCountry.size() >= 1);
        System.assert(byState.size() >= 1);
    }

    @IsTest
    static void testGetAlumniList_region() {
        Test.startTest();
        List<KenAlumniDashboardController.AlumniRecord> withState    = KenAlumniDashboardController.getAlumniList('region', 'USA / New York', null, null, null);
        List<KenAlumniDashboardController.AlumniRecord> countryOnly  = KenAlumniDashboardController.getAlumniList('region', 'India', null, null, null);
        Test.stopTest();
        System.assert(withState.size() >= 1);
        System.assert(countryOnly.size() >= 1);
    }

    @IsTest
    static void testGetAlumniList_employment() {
        Test.startTest();
        List<KenAlumniDashboardController.AlumniRecord> employed = KenAlumniDashboardController.getAlumniList('employment', 'Employed', null, null, null);
        KenAlumniDashboardController.getAlumniList('employment', 'Not Specified', null, null, null);
        Test.stopTest();
        System.assert(employed.size() >= 1);
    }

    @IsTest
    static void testGetAlumniList_profession() {
        Test.startTest();
        List<KenAlumniDashboardController.AlumniRecord> byProf = KenAlumniDashboardController.getAlumniList('profession', 'Technology', null, null, null);
        KenAlumniDashboardController.getAlumniList('profession', 'Not Specified', null, null, null);
        Test.stopTest();
        System.assert(byProf.size() >= 1);
    }

    @IsTest
    static void testGetAlumniList_lifecycleAndRegistration() {
        Test.startTest();
        KenAlumniDashboardController.getAlumniList('lifecycle',    'Ambassador',    null, null, null);
        KenAlumniDashboardController.getAlumniList('lifecycle',    'Not Specified', null, null, null);
        KenAlumniDashboardController.getAlumniList('registration', 'Registered',    null, null, null);
        KenAlumniDashboardController.getAlumniList('registration', 'Not Specified', null, null, null);
        Test.stopTest();
    }

    @IsTest
    static void testGetAlumniList_interests() {
        Test.startTest();
        List<KenAlumniDashboardController.AlumniRecord> recs = KenAlumniDashboardController.getAlumniList('interests', 'Leadership', null, null, null);
        Test.stopTest();
        System.assert(recs.size() >= 1);
    }

    @IsTest
    static void testGetAlumniList_allAgeBuckets() {
        Test.startTest();
        KenAlumniDashboardController.getAlumniList('age', 'Under 25', null, null, null);
        KenAlumniDashboardController.getAlumniList('age', '25–34', null, null, null);
        KenAlumniDashboardController.getAlumniList('age', '35–44', null, null, null);
        KenAlumniDashboardController.getAlumniList('age', '45–54', null, null, null);
        KenAlumniDashboardController.getAlumniList('age', '55+',       null, null, null);
        Test.stopTest();
    }
}