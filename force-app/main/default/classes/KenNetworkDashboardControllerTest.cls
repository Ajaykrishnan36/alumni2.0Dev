@IsTest
private class KenNetworkDashboardControllerTest {

    @TestSetup
    static void makeData() {
        // Insert 4 Accounts
        List<Account> accts = new List<Account>{
            new Account(Name = 'Alice'),
            new Account(Name = 'Bob'),
            new Account(Name = 'Carol'),
            new Account(Name = 'Dave')
        };
        insert accts;

        Id aliceId = accts[0].Id;
        Id bobId   = accts[1].Id;
        Id carolId = accts[2].Id;
        Id daveId  = accts[3].Id;

        DateTime now = DateTime.now();

        List<Ken_Network_Connection__c> conns = new List<Ken_Network_Connection__c>{
            // 1. Alice→Bob, Accepted
            new Ken_Network_Connection__c(
                Initiator__c       = aliceId,
                Recipient__c       = bobId,
                Status__c          = 'Accepted',
                Requested_Date__c  = now.addDays(-10),
                Accepted_Date__c   = now.addDays(-5)
            ),
            // 2. Alice→Carol, Accepted
            new Ken_Network_Connection__c(
                Initiator__c       = aliceId,
                Recipient__c       = carolId,
                Status__c          = 'Accepted',
                Requested_Date__c  = now.addDays(-10),
                Accepted_Date__c   = now.addDays(-5)
            ),
            // 3. Bob→Carol, Requested
            new Ken_Network_Connection__c(
                Initiator__c       = bobId,
                Recipient__c       = carolId,
                Status__c          = 'Requested',
                Requested_Date__c  = now.addDays(-3)
            ),
            // 4. Carol→Dave, Rejected
            new Ken_Network_Connection__c(
                Initiator__c       = carolId,
                Recipient__c       = daveId,
                Status__c          = 'Rejected',
                Requested_Date__c  = now.addDays(-7)
            ),
            // 5. Dave→Alice, Cancelled
            new Ken_Network_Connection__c(
                Initiator__c       = daveId,
                Recipient__c       = aliceId,
                Status__c          = 'Cancelled',
                Requested_Date__c  = now.addDays(-2)
            ),
            // 6. Bob→Dave, Blocked
            new Ken_Network_Connection__c(
                Initiator__c       = bobId,
                Recipient__c       = daveId,
                Status__c          = 'Blocked',
                Requested_Date__c  = now.addDays(-1)
            ),
            // 7. Alice→Dave, Requested
            new Ken_Network_Connection__c(
                Initiator__c       = aliceId,
                Recipient__c       = daveId,
                Status__c          = 'Requested',
                Requested_Date__c  = now.addDays(-4)
            ),
            // 8. Carol→Alice, Accepted
            new Ken_Network_Connection__c(
                Initiator__c       = carolId,
                Recipient__c       = aliceId,
                Status__c          = 'Accepted',
                Requested_Date__c  = now.addDays(-10),
                Accepted_Date__c   = now.addDays(-5)
            )
        };
        insert conns;
    }

    // 1. getSummaryStats — no filters
    @IsTest
    static void testGetSummaryStats_noFilter() {
        Test.startTest();
        KenNetworkDashboardController.SummaryStats stats =
            KenNetworkDashboardController.getSummaryStats(null, null);
        Test.stopTest();

        System.assertNotEquals(null, stats, 'Stats should not be null');
        System.assert(stats.total    >= 8, 'Expected total >= 8, got ' + stats.total);
        System.assert(stats.accepted >= 3, 'Expected accepted >= 3, got ' + stats.accepted);
        System.assert(stats.pending  >= 2, 'Expected pending >= 2, got ' + stats.pending);
        System.assert(stats.avgTatDays >= 0, 'Expected avgTatDays >= 0');
    }

    // 2. getSummaryStats — with filters
    @IsTest
    static void testGetSummaryStats_withFilters() {
        Test.startTest();
        KenNetworkDashboardController.SummaryStats stats =
            KenNetworkDashboardController.getSummaryStats(
                'Accepted',
                String.valueOf(Date.today().year())
            );
        Test.stopTest();

        System.assertNotEquals(null, stats, 'Stats should not be null');
        System.assert(stats.total >= 3, 'Expected total >= 3, got ' + stats.total);
    }

    // 3. getSummaryStats — empty result (year 1900)
    @IsTest
    static void testGetSummaryStats_empty() {
        Test.startTest();
        KenNetworkDashboardController.SummaryStats stats =
            KenNetworkDashboardController.getSummaryStats(null, '1900');
        Test.stopTest();

        System.assertNotEquals(null, stats, 'Stats should not be null');
        System.assertEquals(0, stats.total, 'Expected total == 0 for year 1900');
    }

    // 4. getConnectionsByStatus
    @IsTest
    static void testGetConnectionsByStatus() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getConnectionsByStatus(null);
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assert(pts.size() >= 1, 'Expected at least 1 status group');
    }

    // 5. getMonthlyTrend — no filters
    @IsTest
    static void testGetMonthlyTrend_noFilter() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getMonthlyTrend(null, null);
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assertEquals(12, pts.size(), 'Expected 12 months');
    }

    // 6. getMonthlyTrend — year 1900 (all zeros)
    @IsTest
    static void testGetMonthlyTrend_empty() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getMonthlyTrend(null, '1900');
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assertEquals(12, pts.size(), 'Expected 12 months');
        for (KenNetworkDashboardController.ChartPoint p : pts) {
            System.assertEquals(0, p.value, 'Expected 0 for month ' + p.label);
        }
    }

    // 7. getAvgTatByMonth
    @IsTest
    static void testGetAvgTatByMonth() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getAvgTatByMonth(null);
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assertEquals(12, pts.size(), 'Expected 12 months');
    }

    // 8. getAvgTatByMonth — year 1900 (all zeros)
    @IsTest
    static void testGetAvgTatByMonth_empty() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getAvgTatByMonth('1900');
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assertEquals(12, pts.size(), 'Expected 12 months');
        for (KenNetworkDashboardController.ChartPoint p : pts) {
            System.assertEquals(0, p.value, 'Expected 0 for month ' + p.label);
        }
    }

    // 9. getTopConnectors
    @IsTest
    static void testGetTopConnectors() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getTopConnectors(null, null);
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assert(pts.size() >= 1, 'Expected at least 1 connector');
    }

    // 10. getTopSenders
    @IsTest
    static void testGetTopSenders() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getTopSenders(null, null);
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assert(pts.size() >= 1, 'Expected at least 1 sender');
        System.assert(pts[0].value >= 1, 'Expected value >= 1 for top sender');
    }

    // 11. getTopReceivers
    @IsTest
    static void testGetTopReceivers() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getTopReceivers(null, null);
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assert(pts.size() >= 1, 'Expected at least 1 receiver');
    }

    // 12. getYearlyGrowth
    @IsTest
    static void testGetYearlyGrowth() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getYearlyGrowth(null);
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
        System.assert(pts.size() >= 1, 'Expected at least 1 year');
    }

    // 13. getFilterOptions
    @IsTest
    static void testGetFilterOptions() {
        Test.startTest();
        Map<String, List<String>> opts =
            KenNetworkDashboardController.getFilterOptions();
        Test.stopTest();

        System.assertNotEquals(null, opts, 'Result should not be null');
        System.assert(opts.containsKey('statuses'), 'Expected key statuses');
        System.assert(opts.containsKey('years'),    'Expected key years');
        System.assertEquals(5, opts.get('statuses').size(), 'Expected 5 statuses');
        System.assert(opts.get('years').size() >= 1, 'Expected at least 1 year');
    }

    // 14. getConnectionList — no filters
    @IsTest
    static void testGetConnectionList_noFilter() {
        Test.startTest();
        List<KenNetworkDashboardController.ConnectionRecord> recs =
            KenNetworkDashboardController.getConnectionList(null, null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, recs, 'Result should not be null');
        System.assert(recs.size() >= 8, 'Expected at least 8 records, got ' + recs.size());
        System.assertNotEquals(null, recs[0].id, 'Expected id to be set');
    }

    // 15. getConnectionList — by status
    @IsTest
    static void testGetConnectionList_byStatus() {
        Test.startTest();
        List<KenNetworkDashboardController.ConnectionRecord> recs =
            KenNetworkDashboardController.getConnectionList('status', 'Accepted', null, null);
        Test.stopTest();

        System.assertNotEquals(null, recs, 'Result should not be null');
        for (KenNetworkDashboardController.ConnectionRecord r : recs) {
            System.assertEquals('Accepted', r.status, 'Expected status Accepted');
        }
    }

    // 16. getConnectionList — accepted dimension
    @IsTest
    static void testGetConnectionList_accepted() {
        Test.startTest();
        List<KenNetworkDashboardController.ConnectionRecord> recs =
            KenNetworkDashboardController.getConnectionList('accepted', '', null, null);
        Test.stopTest();

        System.assertNotEquals(null, recs, 'Result should not be null');
        for (KenNetworkDashboardController.ConnectionRecord r : recs) {
            System.assertEquals('Accepted', r.status, 'Expected status Accepted');
        }
    }

    // 17. getConnectionList — pending dimension
    @IsTest
    static void testGetConnectionList_pending() {
        Test.startTest();
        List<KenNetworkDashboardController.ConnectionRecord> recs =
            KenNetworkDashboardController.getConnectionList('pending', '', null, null);
        Test.stopTest();

        System.assertNotEquals(null, recs, 'Result should not be null');
        for (KenNetworkDashboardController.ConnectionRecord r : recs) {
            System.assertEquals('Requested', r.status, 'Expected status Requested');
        }
    }

    // 18. getConnectionList — negative dimension
    @IsTest
    static void testGetConnectionList_negative() {
        Set<String> negativeStatuses = new Set<String>{ 'Rejected', 'Cancelled', 'Blocked' };
        Test.startTest();
        List<KenNetworkDashboardController.ConnectionRecord> recs =
            KenNetworkDashboardController.getConnectionList('negative', '', null, null);
        Test.stopTest();

        System.assertNotEquals(null, recs, 'Result should not be null');
        for (KenNetworkDashboardController.ConnectionRecord r : recs) {
            System.assert(negativeStatuses.contains(r.status),
                'Expected negative status, got ' + r.status);
        }
    }

    // 19. getConnectionList — by initiator
    @IsTest
    static void testGetConnectionList_byInitiator() {
        Account alice = [SELECT Name FROM Account WHERE Name = 'Alice' LIMIT 1];
        Test.startTest();
        List<KenNetworkDashboardController.ConnectionRecord> recs =
            KenNetworkDashboardController.getConnectionList('initiator', alice.Name, null, null);
        Test.stopTest();

        System.assertNotEquals(null, recs, 'Result should not be null');
        System.assert(recs.size() >= 1, 'Expected at least 1 record for Alice as initiator');
    }

    // 20. getConnectionList — by connector
    @IsTest
    static void testGetConnectionList_byConnector() {
        Account alice = [SELECT Name FROM Account WHERE Name = 'Alice' LIMIT 1];
        Test.startTest();
        List<KenNetworkDashboardController.ConnectionRecord> recs =
            KenNetworkDashboardController.getConnectionList('connector', alice.Name, null, null);
        Test.stopTest();

        System.assertNotEquals(null, recs, 'Result should not be null');
        System.assert(recs.size() >= 1, 'Expected at least 1 record for Alice as connector');
    }

    // 21. invalid year branch — should not throw, returns defaults
    @IsTest
    static void testInvalidYearBranch() {
        Test.startTest();
        KenNetworkDashboardController.SummaryStats stats =
            KenNetworkDashboardController.getSummaryStats(null, 'notAYear');
        List<KenNetworkDashboardController.ChartPoint> trend =
            KenNetworkDashboardController.getMonthlyTrend(null, 'notAYear');
        List<KenNetworkDashboardController.ChartPoint> tat =
            KenNetworkDashboardController.getAvgTatByMonth('notAYear');
        Test.stopTest();

        System.assertNotEquals(null, stats,  'SummaryStats should not be null for invalid year');
        System.assertNotEquals(null, trend,  'MonthlyTrend should not be null for invalid year');
        System.assertNotEquals(null, tat,    'AvgTatByMonth should not be null for invalid year');
    }

    // 22. getConnectionsByStatus — with year filter
    @IsTest
    static void testGetConnectionsByStatus_withYear() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getConnectionsByStatus(
                String.valueOf(Date.today().year())
            );
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
    }

    // 23. getTopConnectors — with status and year filters
    @IsTest
    static void testGetTopConnectors_withFilters() {
        Test.startTest();
        List<KenNetworkDashboardController.ChartPoint> pts =
            KenNetworkDashboardController.getTopConnectors(
                'Accepted',
                String.valueOf(Date.today().year())
            );
        Test.stopTest();

        System.assertNotEquals(null, pts, 'Result should not be null');
    }
}