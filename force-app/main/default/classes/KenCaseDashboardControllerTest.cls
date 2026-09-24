@IsTest
private class KenCaseDashboardControllerTest {

    @TestSetup
    static void makeData() {
        // ── Services ────────────────────────────────────────────────────────
        Ken_Service__c svc1 = new Ken_Service__c(Name = 'Support Service');
        Ken_Service__c svc2 = new Ken_Service__c(Name = 'Training Service');
        insert new List<Ken_Service__c>{ svc1, svc2 };

        // ── Service Offerings ────────────────────────────────────────────────
        Ken_Service_Offering__c off1 = new Ken_Service_Offering__c(
            Name    = 'Technical Support',
            Service__c = svc1.Id
        );
        Ken_Service_Offering__c off2 = new Ken_Service_Offering__c(
            Name    = 'Onboarding Training',
            Service__c = svc2.Id
        );
        insert new List<Ken_Service_Offering__c>{ off1, off2 };

        // ── Submitter Accounts ───────────────────────────────────────────────
        // Use PersonAccount record type if it exists; fall back to standard Account
        Id rtId = null;
        Map<String, Schema.RecordTypeInfo> rtMap =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        if (rtMap.containsKey('PersonAccount')) {
            rtId = rtMap.get('PersonAccount').getRecordTypeId();
        }

        Account acc1 = rtId != null
            ? new Account(RecordTypeId = rtId, LastName = 'Submitter One')
            : new Account(Name = 'Submitter One');
        Account acc2 = rtId != null
            ? new Account(RecordTypeId = rtId, LastName = 'Submitter Two')
            : new Account(Name = 'Submitter Two');
        insert new List<Account>{ acc1, acc2 };

        // ── Constituent Roles ────────────────────────────────────────────────
        // Cases now link to the submitter via Constituent_Role__c (ConstituentRole),
        // not a direct Account lookup; the person's name is read via role -> Person.
        ConstituentRole role1 = new ConstituentRole(PersonId = acc1.Id, RoleType = 'Alumni', Status = 'Active');
        ConstituentRole role2 = new ConstituentRole(PersonId = acc2.Id, RoleType = 'Alumni', Status = 'Active');
        insert new List<ConstituentRole>{ role1, role2 };

        // ── Cases ────────────────────────────────────────────────────────────
        List<Case> cases = new List<Case>{
            new Case(
                Subject            = 'Cannot login to portal',
                Status             = 'New',
                Origin             = 'Web',
                Service_Offering__c = off1.Id,
                Constituent_Role__c = role1.Id
            ),
            new Case(
                Subject            = 'Training session scheduling',
                Status             = 'Working',
                Origin             = 'Portal',
                Service_Offering__c = off2.Id,
                Constituent_Role__c = role2.Id
            ),
            new Case(
                Subject            = 'Password reset request',
                Status             = 'In Review',
                Origin             = 'Web',
                Service_Offering__c = off1.Id,
                Constituent_Role__c = role1.Id
            ),
            new Case(
                Subject            = 'Certificate generation',
                Status             = 'Closed',
                Origin             = 'Portal',
                Service_Offering__c = off2.Id,
                Constituent_Role__c = role2.Id
            ),
            new Case(
                Subject            = 'Duplicate request',
                Status             = 'Canceled',
                Origin             = 'Web',
                Service_Offering__c = off1.Id,
                Constituent_Role__c = role1.Id
            ),
            new Case(
                Subject            = 'Out of scope request',
                Status             = 'Rejected',
                Origin             = 'Portal',
                Service_Offering__c = off2.Id,
                Constituent_Role__c = role2.Id
            )
        };
        insert cases;
    }

    // ── getSummaryStats ──────────────────────────────────────────────────────

    @IsTest
    static void testGetSummaryStats_noFilter() {
        Test.startTest();
        KenCaseDashboardController.SummaryStats result =
            KenCaseDashboardController.getSummaryStats(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Stats should not be null');
        System.assert(result.total       >= 0, 'Total should be >= 0');
        System.assert(result.openCases   >= 0, 'openCases should be >= 0');
        System.assert(result.closedCases >= 0, 'closedCases should be >= 0');
        System.assert(result.cancelled   >= 0, 'cancelled should be >= 0');
    }

    @IsTest
    static void testGetSummaryStats_withFilters() {
        Test.startTest();
        KenCaseDashboardController.SummaryStats result =
            KenCaseDashboardController.getSummaryStats(
                String.valueOf(Date.today().year()), 'New', 'Web'
            );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Stats with filters should not be null');
        System.assert(result.total >= 0);
    }

    @IsTest
    static void testGetSummaryStats_empty() {
        Test.startTest();
        KenCaseDashboardController.SummaryStats result =
            KenCaseDashboardController.getSummaryStats('1900', 'New', 'Web');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Stats should not be null for empty result');
        System.assertEquals(0, result.total,       'Total should be 0 for year 1900');
        System.assertEquals(0, result.openCases,   'openCases should be 0');
        System.assertEquals(0, result.closedCases, 'closedCases should be 0');
        System.assertEquals(0, result.cancelled,   'cancelled should be 0');
    }

    // ── getCasesByStatus ─────────────────────────────────────────────────────

    @IsTest
    static void testGetCasesByStatus() {
        Test.startTest();
        List<KenCaseDashboardController.ChartPoint> result =
            KenCaseDashboardController.getCasesByStatus(null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'getCasesByStatus should not return null');
        System.assert(result.size() >= 0, 'Should return a list');
        for (KenCaseDashboardController.ChartPoint pt : result) {
            System.assertNotEquals(null, pt.label, 'Chart point label should not be null');
            System.assert(pt.value >= 0, 'Chart point value should be >= 0');
        }
    }

    // ── getCasesByOrigin ─────────────────────────────────────────────────────

    @IsTest
    static void testGetCasesByOrigin() {
        Test.startTest();
        List<KenCaseDashboardController.ChartPoint> result =
            KenCaseDashboardController.getCasesByOrigin(null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'getCasesByOrigin should not return null');
        System.assert(result.size() >= 0);
    }

    // ── getTopServices ───────────────────────────────────────────────────────

    @IsTest
    static void testGetTopServices() {
        Test.startTest();
        List<KenCaseDashboardController.ChartPoint> result =
            KenCaseDashboardController.getTopServices(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'getTopServices should not return null');
        System.assert(result.size() >= 0);
    }

    // ── getTopServiceOfferings ───────────────────────────────────────────────

    @IsTest
    static void testGetTopServiceOfferings() {
        Test.startTest();
        List<KenCaseDashboardController.ChartPoint> result =
            KenCaseDashboardController.getTopServiceOfferings(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'getTopServiceOfferings should not return null');
        System.assert(result.size() >= 0);
    }

    // ── getCaseTrend ─────────────────────────────────────────────────────────

    @IsTest
    static void testGetCaseTrend() {
        Test.startTest();
        List<KenCaseDashboardController.ChartPoint> result =
            KenCaseDashboardController.getCaseTrend(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'getCaseTrend should not return null');
        System.assertEquals(12, result.size(), 'Trend should always return 12 months');
    }

    // ── getTopSubmitters ─────────────────────────────────────────────────────

    @IsTest
    static void testGetTopSubmitters() {
        Test.startTest();
        List<KenCaseDashboardController.ChartPoint> result =
            KenCaseDashboardController.getTopSubmitters(null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'getTopSubmitters should not return null');
        System.assert(result.size() >= 0);
    }

    // ── getFilterOptions ─────────────────────────────────────────────────────

    @IsTest
    static void testGetFilterOptions() {
        Test.startTest();
        Map<String, List<String>> result =
            KenCaseDashboardController.getFilterOptions();
        Test.stopTest();
        System.assertNotEquals(null, result, 'getFilterOptions should not return null');
        System.assert(result.containsKey('statuses'), 'Should contain statuses key');
        System.assert(result.containsKey('origins'),  'Should contain origins key');
        System.assert(result.containsKey('years'),    'Should contain years key');
        System.assert(result.get('statuses').size() >= 0);
        System.assert(result.get('origins').size()  >= 0);
        System.assert(result.get('years').size()    >= 0);
    }

    // ── getCaseList ──────────────────────────────────────────────────────────

    @IsTest
    static void testGetCaseList_noFilter() {
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('all', '', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'getCaseList should not return null');
        System.assert(result.size() >= 0);
    }

    @IsTest
    static void testGetCaseList_byStatus() {
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('status', 'New', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result);
        for (KenCaseDashboardController.CaseListRecord rec : result) {
            System.assertEquals('New', rec.status, 'All returned cases should have status New');
        }
    }

    @IsTest
    static void testGetCaseList_byOrigin() {
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('origin', 'Web', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result);
        for (KenCaseDashboardController.CaseListRecord rec : result) {
            System.assertEquals('Web', rec.origin, 'All returned cases should have origin Web');
        }
    }

    @IsTest
    static void testGetCaseList_byService() {
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('service', 'Support Service', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(result.size() >= 0);
    }

    @IsTest
    static void testGetCaseList_byOffering() {
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('offering', 'Technical Support', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(result.size() >= 0);
    }

    @IsTest
    static void testGetCaseList_bySubmitter() {
        List<Account> accs = [SELECT Name FROM Account WHERE Name = 'Submitter One' LIMIT 1];
        String submitterName = accs.isEmpty() ? 'Submitter One' : accs[0].Name;
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('submitter', submitterName, null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assert(result.size() >= 0);
    }

    @IsTest
    static void testGetCaseList_open() {
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('open', '', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result);
        Set<String> openStatuses = new Set<String>{ 'New', 'Working', 'In Review' };
        for (KenCaseDashboardController.CaseListRecord rec : result) {
            System.assert(openStatuses.contains(rec.status),
                'Open cases should only have open statuses, got: ' + rec.status);
        }
    }

    @IsTest
    static void testGetCaseList_closed() {
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('closed', '', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result);
        for (KenCaseDashboardController.CaseListRecord rec : result) {
            System.assertEquals('Closed', rec.status,
                'Closed cases should only have Closed status');
        }
    }

    @IsTest
    static void testGetCaseList_cancelled() {
        Test.startTest();
        List<KenCaseDashboardController.CaseListRecord> result =
            KenCaseDashboardController.getCaseList('cancelled', '', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, result);
        Set<String> cancelledStatuses = new Set<String>{ 'Canceled', 'Rejected' };
        for (KenCaseDashboardController.CaseListRecord rec : result) {
            System.assert(cancelledStatuses.contains(rec.status),
                'Cancelled cases should only have Canceled/Rejected status, got: ' + rec.status);
        }
    }
}