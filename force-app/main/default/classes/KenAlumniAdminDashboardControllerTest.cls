@IsTest
private class KenAlumniAdminDashboardControllerTest {

    @TestSetup
    static void seed() {
        // Person Account record type is required for Person fields. Discover it
        // dynamically so the test passes in any org that has Person Accounts on.
        Id paRtId = null;
        for (RecordType rt : [
            SELECT Id, DeveloperName, IsPersonType FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = true LIMIT 1
        ]) { paRtId = rt.Id; }

        List<Account> accs = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            Account a = new Account();
            if (paRtId != null) {
                a.RecordTypeId = paRtId;
                a.FirstName = 'Alum';
                a.LastName = 'Test' + i;
                a.PersonEmail = 'alum' + i + '@example.test';
                a.PersonMailingCountry = 'India';
            } else {
                a.Name = 'Alum Test ' + i;
            }
            accs.add(a);
        }
        insert accs;

        List<ConstituentRole> roles = new List<ConstituentRole>();
        // 5 alumni roles: Registered, Initial Login Done, Verified, Unregistered, Registered
        List<String> regStatuses = new List<String>{
            'Registered', 'Initial Login Done', 'Verified', 'Unregistered', 'Registered'
        };
        for (Integer i = 0; i < 5; i++) {
            ConstituentRole cr = new ConstituentRole(
                PersonId = accs[i].Id,
                RoleType = 'Alumni',
                Registration_Status__c = regStatuses[i],
                Graduation_Year__c = '2015',
                Source_Funnel__c = (i == 0) ? 'Historical Upload' : 'Student-to-Alumni Transition'
            );
            cr.put('Status', 'Active');
            roles.add(cr);
        }
        insert roles;

        List<Ken_Alumni_CRM__c> rows = new List<Ken_Alumni_CRM__c>();
        for (Integer i = 0; i < 5; i++) {
            Ken_Alumni_CRM__c a = new Ken_Alumni_CRM__c();
            a.Person_Account__c = accs[i].Id;
            a.ConstituentRole__c = roles[i].Id;
            a.Approval_Status__c = (Math.mod(i, 2) == 0) ? 'Approved' : 'Pending';
            a.Has_Logged_In_Once__c = (Math.mod(i, 2) == 0);
            a.Is_Active__c = (i == 0);
            a.Program__c = 'B.Tech CS';
            a.Year_of_Graduation__c = '2015';
            a.Registration_Number__c = 'CS' + (110000 + i);
            a.Current_Company__c = 'Acme';
            a.Current_Location__c = 'Bangalore';
            a.Industry__c = 'Technology';
            a.Registration_Date__c = Date.today().addDays(-i);
            a.Agree_to_T_C__c = true;
            rows.add(a);
        }
        insert rows;
    }

    @IsTest
    static void testGetDashboardMetrics() {
        Test.startTest();
        KenAlumniAdminDashboardController.DashboardMetrics m =
            KenAlumniAdminDashboardController.getDashboardMetrics();
        Test.stopTest();
        // 5 alumni roles seeded — actual count may be higher if triggers create more
        System.assert(m.totalAlumni >= 5);
        System.assert(m.institutionVerified >= 0 && m.institutionVerified <= m.totalAlumni);
        System.assert(m.portalRegistered >= 0 && m.portalRegistered <= m.institutionVerified);
        System.assertEquals(m.institutionVerified - m.portalRegistered, m.pendingActivation);
    }

    @IsTest
    static void testGetFunnelDataUpload() {
        Test.startTest();
        KenAlumniAdminDashboardController.FunnelData f =
            KenAlumniAdminDashboardController.getFunnelData('upload');
        Test.stopTest();
        System.assertEquals(4, f.steps.size());
        System.assertEquals('All Data Upload', f.title);
        // Funnel should be monotonically narrowing
        System.assert(f.steps[0].value >= f.steps[1].value);
        System.assert(f.steps[1].value >= f.steps[2].value);
        System.assert(f.steps[2].value >= f.steps[3].value);
    }

    @IsTest
    static void testGetFunnelDataTransition() {
        Test.startTest();
        KenAlumniAdminDashboardController.FunnelData f =
            KenAlumniAdminDashboardController.getFunnelData('transition');
        Test.stopTest();
        System.assertEquals(4, f.steps.size());
        System.assertEquals('Student-to-Alumni Transition', f.title);
    }

    @IsTest
    static void testGetFunnelDataLeads() {
        Test.startTest();
        KenAlumniAdminDashboardController.FunnelData f =
            KenAlumniAdminDashboardController.getFunnelData('leads');
        Test.stopTest();
        System.assertEquals(4, f.steps.size());
    }

    @IsTest
    static void testGetSourceDistribution() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.SourceSlice> slices =
            KenAlumniAdminDashboardController.getSourceDistribution();
        Test.stopTest();
        System.assert(!slices.isEmpty(), 'At least one slice expected.');
    }

    @IsTest
    static void testGetDataHealthBreakdown() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.HealthBar> bars =
            KenAlumniAdminDashboardController.getDataHealthBreakdown();
        Test.stopTest();
        System.assertEquals(8, bars.size(), 'Eight health rows expected.');
        for (KenAlumniAdminDashboardController.HealthBar b : bars) {
            System.assert(b.percent >= 0 && b.percent <= 100);
        }
    }

    @IsTest
    static void testGetOnboardingTrend() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.TrendPoint> series =
            KenAlumniAdminDashboardController.getOnboardingTrend();
        Test.stopTest();
        System.assertEquals(6, series.size(), 'Six months of trend points.');
    }

    @IsTest
    static void testGetEngagementSummary() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.EngagementChannel> channels =
            KenAlumniAdminDashboardController.getEngagementSummary();
        Test.stopTest();
        System.assertEquals(6, channels.size(), 'Events, Mentorship, Hiring Support, Donations, Surveys, Groups');
    }

    @IsTest
    static void testGetRecentActivity() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.ActivityItem> items =
            KenAlumniAdminDashboardController.getRecentActivity();
        Test.stopTest();
        System.assert(items.size() <= 5);
        if (!items.isEmpty()) {
            System.assertNotEquals(null, items[0].title);
        }
    }

    @IsTest
    static void testGetSuggestedActions() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.ActionItem> actions =
            KenAlumniAdminDashboardController.getSuggestedActions();
        Test.stopTest();
        System.assertNotEquals(null, actions);
    }

    @IsTest
    static void testGetCommunicationsSnapshot() {
        Test.startTest();
        KenAlumniAdminDashboardController.CommsSnapshot s =
            KenAlumniAdminDashboardController.getCommunicationsSnapshot();
        Test.stopTest();
        System.assertNotEquals(null, s);
        System.assertEquals(0, s.messagesSent);
    }

    @IsTest
    static void testGetProfileCompletenessAll() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.CompletenessBucket> buckets =
            KenAlumniAdminDashboardController.getProfileCompleteness('all');
        Test.stopTest();
        System.assertEquals(5, buckets.size());
        Integer total = 0;
        for (KenAlumniAdminDashboardController.CompletenessBucket b : buckets) total += b.count;
        System.assertEquals(5, total);
    }

    @IsTest
    static void testGetProfileCompletenessActiveOnly() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.CompletenessBucket> buckets =
            KenAlumniAdminDashboardController.getProfileCompleteness('active');
        Test.stopTest();
        System.assertEquals(5, buckets.size());
        // Active filter must not blow past the all-audience total
        Integer activeTotal = 0;
        for (KenAlumniAdminDashboardController.CompletenessBucket b : buckets) activeTotal += b.count;
        System.assert(activeTotal >= 0 && activeTotal <= 5);
    }

    @IsTest
    static void testGetAgeDistributionAll() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.AgeBucket> buckets =
            KenAlumniAdminDashboardController.getAgeDistribution('all');
        Test.stopTest();
        System.assertEquals(7, buckets.size());
    }

    @IsTest
    static void testGetAgeDistributionActiveOnly() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.AgeBucket> buckets =
            KenAlumniAdminDashboardController.getAgeDistribution('active');
        Test.stopTest();
        System.assertEquals(7, buckets.size());
    }

    @IsTest
    static void testGetEmploymentStatusAll() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.EmploymentSlice> slices =
            KenAlumniAdminDashboardController.getEmploymentStatus('all');
        Test.stopTest();
        System.assertEquals(2, slices.size());
    }

    @IsTest
    static void testGetEmploymentStatusActiveOnly() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.EmploymentSlice> slices =
            KenAlumniAdminDashboardController.getEmploymentStatus('active');
        Test.stopTest();
        System.assert(slices.size() == 2 || slices.size() == 0);
    }

    @IsTest
    static void testGetRegionalDemographicsAll() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.RegionRow> rows =
            KenAlumniAdminDashboardController.getRegionalDemographics('all');
        Test.stopTest();
        System.assertNotEquals(null, rows);
    }

    @IsTest
    static void testGetRegionalDemographicsActiveOnly() {
        Test.startTest();
        List<KenAlumniAdminDashboardController.RegionRow> rows =
            KenAlumniAdminDashboardController.getRegionalDemographics('active');
        Test.stopTest();
        System.assertNotEquals(null, rows);
    }

    @IsTest
    static void testHealthBarOnEmptyOrg() {
        delete [SELECT Id FROM Ken_Alumni_CRM__c];
        Test.startTest();
        List<KenAlumniAdminDashboardController.HealthBar> bars =
            KenAlumniAdminDashboardController.getDataHealthBreakdown();
        Test.stopTest();
        System.assertEquals(0, bars.size(), 'Empty list expected on empty org.');
    }

    @IsTest
    static void testDashboardMetricsRunsAfterDeletingCrm() {
        // Triggers may auto-create ConstituentRole rows from upstream data,
        // so we can't assert zero — just verify the method still works.
        delete [SELECT Id FROM Ken_Alumni_CRM__c];
        Test.startTest();
        KenAlumniAdminDashboardController.DashboardMetrics m =
            KenAlumniAdminDashboardController.getDashboardMetrics();
        Test.stopTest();
        System.assertNotEquals(null, m);
        System.assert(m.pendingActivation >= 0);
    }
}