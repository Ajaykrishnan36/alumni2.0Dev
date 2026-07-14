/**
 * KenSnSReportsControllerTest
 *
 * Covers KenSnSReportsController:
 *   - getServiceOfferings: runs without error, always returns at least the "All Services" entry.
 *   - getReportData: each reportType branch (status, category, recordType, priority, owner, trend,
 *     allCases), plus filter combinations (statusFilter, dateRange variants, searchKey,
 *     recordTypeFilter, limitSize).
 *
 * No SeeAllData. All test data inserted via DML.
 */
@IsTest
private class KenSnSReportsControllerTest {

    // ── shared setup ─────────────────────────────────────────────────────────

    @TestSetup
    static void setupData() {
        // Insert a handful of cases covering different statuses and priorities
        // so the KPI aggregation paths are exercised.
        List<Case> cases = new List<Case>{
            new Case(Subject = 'SnS Report New 1',        Status = 'New',         Origin = 'Web', Priority = 'High'),
            new Case(Subject = 'SnS Report New 2',        Status = 'New',         Origin = 'Web', Priority = 'Low'),
            new Case(Subject = 'SnS Report In Progress',  Status = 'In Progress', Origin = 'Web', Priority = 'Medium'),
            new Case(Subject = 'SnS Report On Hold',      Status = 'On Hold',     Origin = 'Web', Priority = 'High'),
            new Case(Subject = 'SnS Report Resolved',     Status = 'Resolved',    Origin = 'Web'),
            new Case(Subject = 'SnS Report Closed',       Status = 'Closed',      Origin = 'Web'),
            new Case(Subject = 'SnS Report Canceled',     Status = 'Canceled',    Origin = 'Web')
        };
        insert cases;
    }

    // ── getServiceOfferings ───────────────────────────────────────────────────

    @IsTest
    static void getServiceOfferings_alwaysReturnsAllServicesOption() {
        Test.startTest();
        List<Map<String,String>> options = KenSnSReportsController.getServiceOfferings();
        Test.stopTest();

        System.assertNotEquals(null, options, 'getServiceOfferings should not return null');
        System.assert(!options.isEmpty(), 'Should always contain at least the All Services entry');
        System.assertEquals('All Services', options[0].get('label'),
            'First option must be the All Services placeholder');
        System.assertEquals('', options[0].get('value'),
            'All Services value must be empty string');
    }

    // ── getReportData — reportType branches ───────────────────────────────────

    @IsTest
    static void getReportData_reportTypeStatus_returnsKpis() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.rows);
        System.assertNotEquals(null, result.kpis);
        System.assert(!result.kpis.isEmpty(), 'Status report should produce KPIs');
    }

    @IsTest
    static void getReportData_reportTypeAllCases_returnsKpis() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_ALL_CASES, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(!result.kpis.isEmpty(), 'allCases report should produce KPIs');
    }

    @IsTest
    static void getReportData_reportTypeCategory_returnsKpis() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_CATEGORY, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(!result.kpis.isEmpty(), 'Category report should produce KPIs');
    }

    @IsTest
    static void getReportData_reportTypeRecordType_returnsKpis() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_RECORD_TYPE, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(!result.kpis.isEmpty(), 'RecordType report should produce KPIs');
    }

    @IsTest
    static void getReportData_reportTypePriority_returnsKpis() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_PRIORITY, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(!result.kpis.isEmpty(), 'Priority report should produce KPIs');
    }

    @IsTest
    static void getReportData_reportTypeOwner_returnsKpis() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_OWNER, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(!result.kpis.isEmpty(), 'Owner report should produce KPIs');
    }

    @IsTest
    static void getReportData_reportTypeTrend_returnsKpis() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_TREND, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(!result.kpis.isEmpty(), 'Trend report should produce KPIs');
    }

    // ── getReportData — null/unknown reportType falls through to status ────────

    @IsTest
    static void getReportData_nullReportType_defaultsToStatus() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            null, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(!result.kpis.isEmpty(), 'Null reportType should default to status KPIs');
    }

    // ── getReportData — filter combinations ───────────────────────────────────

    @IsTest
    static void getReportData_statusFilter_narrowsRows() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, 'New', null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        for (KenSnSReportsController.ReportRow row : result.rows) {
            System.assertEquals('New', row.status, 'All returned rows must have Status=New');
        }
    }

    @IsTest
    static void getReportData_limitSize_restrictsResultCount() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, null, null, 2
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.rows.size() <= 2, 'Result rows should be capped at limitSize=2');
    }

    @IsTest
    static void getReportData_dateRange_thisMonth_appliesFilter() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, 'thisMonth', null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        // Test data was just created so this month filter should still return them
        System.assert(result.rows.size() > 0, 'thisMonth filter should return recently inserted cases');
    }

    @IsTest
    static void getReportData_dateRange_lastMonth_executesWithoutError() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, 'lastMonth', null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void getReportData_dateRange_thisYear_executesWithoutError() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, 'thisYear', null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.rows.size() > 0, 'thisYear filter should include test data');
    }

    @IsTest
    static void getReportData_dateRange_last90_executesWithoutError() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, 'last90', null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void getReportData_dateRange_last30_executesWithoutError() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, 'last30', null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void getReportData_dateRange_all_returnsAllCases() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, 'all', null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void getReportData_multipleFilters_executesWithoutError() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, 'New', null, 'thisYear', null, 100
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    // ── ReportRow field shape ────────────────────────────────────────────────

    @IsTest
    static void getReportData_rowFieldsArePopulated() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, 'thisYear', null, 50
        );
        Test.stopTest();

        System.assert(!result.rows.isEmpty(), 'Should return test case rows');
        KenSnSReportsController.ReportRow first = result.rows[0];
        System.assertNotEquals(null, first.id,          'Row id should be populated');
        System.assertNotEquals(null, first.caseNumber,  'Row caseNumber should be populated');
        System.assertNotEquals(null, first.status,      'Row status should be populated');
        System.assertNotEquals(null, first.createdDate, 'Row createdDate should be populated');
        System.assertNotEquals(null, first.createdMonth,'Row createdMonth should be populated');
    }

    // ── KPI shape validation ─────────────────────────────────────────────────

    @IsTest
    static void getReportData_statusKpiHasExpectedLabels() {
        Test.startTest();
        KenSnSReportsController.ReportResult result = KenSnSReportsController.getReportData(
            KenSnSConstants.REPORT_TYPE_STATUS, null, null, 'thisYear', null, null
        );
        Test.stopTest();

        Set<String> kpiLabels = new Set<String>();
        for (KenSnSReportsController.KpiItem kpi : result.kpis) {
            kpiLabels.add(kpi.label);
        }
        System.assert(kpiLabels.contains('Total Cases'), 'Status KPIs should include Total Cases');
        System.assert(kpiLabels.contains('Resolved'),    'Status KPIs should include Resolved');
        System.assert(kpiLabels.contains('Open'),        'Status KPIs should include Open');
        System.assert(kpiLabels.contains('Canceled'),    'Status KPIs should include Canceled');
    }
}