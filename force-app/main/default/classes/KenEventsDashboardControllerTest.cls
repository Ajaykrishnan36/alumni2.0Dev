@IsTest
private class KenEventsDashboardControllerTest {

    @TestSetup
    static void makeData() {
        Id paRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Alumni_Person_Account').getRecordTypeId();
        Account attendee = new Account(
            RecordTypeId = paRtId,
            LastName = 'Test Attendee',
            PersonEmail = 'attendee_evt@test.com'
        );
        insert attendee;

        Ken_Event_Master__c evt1 = new Ken_Event_Master__c(
            Name='Test Conference 2024', Event_Type__c='Conference',
            Event_Status__c='Approved', Location__c='Mumbai',
            Target_Audience_Applicable__c='Alumni;Students',
            No_Fee__c=false, Event_Fee__c=1000,
            Start_Date__c=Date.newInstance(2024,3,10), End_Date__c=Date.newInstance(2024,3,12),
            Is_Published__c=true, Is_Active__c=true
        );
        Ken_Event_Master__c evt2 = new Ken_Event_Master__c(
            Name='Test Seminar 2023', Event_Type__c='Seminar',
            Event_Status__c='Cancelled', Location__c='Delhi',
            Target_Audience_Applicable__c='Alumni',
            No_Fee__c=true,
            Start_Date__c=Date.newInstance(2023,6,15), End_Date__c=Date.newInstance(2023,6,15),
            Is_Published__c=false, Is_Active__c=false
        );
        insert new List<Ken_Event_Master__c>{ evt1, evt2 };

        Ken_Schedule_Sessions__c sess1 = new Ken_Schedule_Sessions__c(
            Name='Session 1', Event_Reference__c=evt1.Id,
            Start_Date__c=Date.newInstance(2024,3,10),
            End_Date__c=Date.newInstance(2024,3,11), No_Fee__c=false
        );
        Ken_Schedule_Sessions__c sess2 = new Ken_Schedule_Sessions__c(
            Name='Session 2', Event_Reference__c=evt2.Id,
            Start_Date__c=Date.newInstance(2023,6,15),
            End_Date__c=Date.newInstance(2023,6,16), No_Fee__c=true
        );
        insert new List<Ken_Schedule_Sessions__c>{ sess1, sess2 };

        insert new List<Ken_Event_Booking__c>{
            new Ken_Event_Booking__c(
                Schedules_Sessions__c=sess1.Id, Person_Account__c=attendee.Id,
                Type__c='Registered', Booked_for_No_of_Attendees__c=1
            ),
            new Ken_Event_Booking__c(
                Schedules_Sessions__c=sess1.Id, Person_Account__c=attendee.Id,
                Type__c='Cancelled', Booked_for_No_of_Attendees__c=1
            )
        };
    }

    // ── Filter options ──────────────────────────────────────────────────────

    @IsTest
    static void testGetFilterOptions() {
        Test.startTest();
        KenEventsDashboardController.FilterOptions opts = KenEventsDashboardController.getFilterOptions();
        Test.stopTest();
        System.assertNotEquals(null, opts);
        System.assertEquals(7, opts.statuses.size());
        System.assert(opts.eventTypes.size() >= 1, 'Event types should be populated');
        System.assert(opts.years.size() >= 1, 'Years should be populated');
    }

    // ── Summary stats ───────────────────────────────────────────────────────

    @IsTest
    static void testGetSummaryStats_noFilter() {
        Test.startTest();
        KenEventsDashboardController.SummaryStats s = KenEventsDashboardController.getSummaryStats(null, null, null);
        Test.stopTest();
        System.assert(s.totalEvents >= 2);
        System.assert(s.publishedEvents >= 1);
        System.assert(s.totalRegistrations >= 1);
        System.assert(s.cancelledBookings >= 1);
    }

    @IsTest
    static void testGetSummaryStats_withFilters() {
        Test.startTest();
        KenEventsDashboardController.SummaryStats s = KenEventsDashboardController.getSummaryStats('Conference', 'Approved', '2024');
        Test.stopTest();
        System.assert(s.totalEvents >= 1);
        System.assert(s.publishedEvents >= 1);
    }

    @IsTest
    static void testGetSummaryStats_invalidYear() {
        Test.startTest();
        KenEventsDashboardController.SummaryStats s = KenEventsDashboardController.getSummaryStats(null, null, 'notAYear');
        Test.stopTest();
        System.assertNotEquals(null, s);
    }

    // ── Chart methods ───────────────────────────────────────────────────────

    @IsTest
    static void testGetEventsByStatus() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getEventsByStatus(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetEventsByType() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getEventsByType(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetEventsByType_withFilter() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getEventsByType('Conference', null, null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetEventPricingDistribution() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getEventPricingDistribution(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetBookingStatusBreakdown() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getBookingStatusBreakdown(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetBookingStatusBreakdown_noMatchingSessions() {
        Test.startTest();
        // Seminar + Approved matches no events → sessions empty → early return
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getBookingStatusBreakdown('Seminar', 'Approved', null);
        Test.stopTest();
        System.assertEquals(0, items.size());
    }

    @IsTest
    static void testGetRegistrationTrends() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getRegistrationTrends(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetRegistrationTrends_noSessions() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getRegistrationTrends('Conference', 'Cancelled', null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetTopEventsByRegistrations() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getTopEventsByRegistrations(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
        System.assertEquals('Test Conference 2024', items[0].label);
    }

    @IsTest
    static void testGetTopEventsByRegistrations_noRegisteredBookings() {
        Test.startTest();
        // Cancelled-status event has sessions but no registered bookings
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getTopEventsByRegistrations(null, 'Cancelled', null);
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetTargetAudienceBreakdown() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getTargetAudienceBreakdown(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetMonthlyEventActivity() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getMonthlyEventActivity(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetMonthlyEventActivity_withYearFilter() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getMonthlyEventActivity(null, null, '2024');
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @IsTest
    static void testGetEventLocationDistribution() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getEventLocationDistribution(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetTopRecurringAttendees() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getTopRecurringAttendees(null, null, null);
        Test.stopTest();
        System.assert(items.size() >= 1);
    }

    @IsTest
    static void testGetTopRecurringAttendees_noSessions() {
        Test.startTest();
        List<KenEventsDashboardController.ChartItem> items = KenEventsDashboardController.getTopRecurringAttendees('Conference', 'Cancelled', null);
        Test.stopTest();
        System.assertEquals(0, items.size());
    }

    // ── getEventList — all dimensions ───────────────────────────────────────

    @IsTest
    static void testGetEventList_noFilter() {
        Test.startTest();
        List<KenEventsDashboardController.EventListRecord> recs = KenEventsDashboardController.getEventList(null, null, null, null, null);
        Test.stopTest();
        System.assert(recs.size() >= 2);
        System.assertNotEquals(null, recs[0].id);
        System.assertNotEquals(null, recs[0].name);
    }

    @IsTest
    static void testGetEventList_statusAndTypeDimensions() {
        Test.startTest();
        List<KenEventsDashboardController.EventListRecord> byStatus = KenEventsDashboardController.getEventList('status', 'Approved', null, null, null);
        List<KenEventsDashboardController.EventListRecord> byType   = KenEventsDashboardController.getEventList('type', 'Conference', null, null, null);
        Test.stopTest();
        System.assert(byStatus.size() >= 1);
        System.assert(byType.size() >= 1);
    }

    @IsTest
    static void testGetEventList_pricingDimension() {
        Test.startTest();
        List<KenEventsDashboardController.EventListRecord> paid = KenEventsDashboardController.getEventList('pricing', 'Paid', null, null, null);
        List<KenEventsDashboardController.EventListRecord> free = KenEventsDashboardController.getEventList('pricing', 'Free', null, null, null);
        Test.stopTest();
        System.assert(paid.size() >= 1);
        System.assert(free.size() >= 1);
    }

    @IsTest
    static void testGetEventList_locationAndAudienceDimensions() {
        Test.startTest();
        List<KenEventsDashboardController.EventListRecord> byLoc = KenEventsDashboardController.getEventList('location', 'Mumbai', null, null, null);
        List<KenEventsDashboardController.EventListRecord> byAud = KenEventsDashboardController.getEventList('audience', 'Alumni', null, null, null);
        Test.stopTest();
        System.assert(byLoc.size() >= 1);
        System.assert(byAud.size() >= 1);
    }

    @IsTest
    static void testGetEventList_topEventsAndTrendsDimensions() {
        Test.startTest();
        List<KenEventsDashboardController.EventListRecord> byTop    = KenEventsDashboardController.getEventList('top_events', 'Test Conference 2024', null, null, null);
        List<KenEventsDashboardController.EventListRecord> byTrend  = KenEventsDashboardController.getEventList('trends', '2024', null, null, null);
        List<KenEventsDashboardController.EventListRecord> badTrend = KenEventsDashboardController.getEventList('trends', 'notAYear', null, null, null);
        List<KenEventsDashboardController.EventListRecord> summary  = KenEventsDashboardController.getEventList('summary', 'All', null, null, null);
        Test.stopTest();
        System.assert(byTop.size() >= 1);
        System.assert(byTrend.size() >= 1);
        System.assertNotEquals(null, badTrend);
        System.assertNotEquals(null, summary);
    }

    // ── getBookingList — all dimension branches ─────────────────────────────

    @IsTest
    static void testGetBookingList_registrations() {
        Test.startTest();
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('registrations', null, null, null, null);
        Test.stopTest();
        System.assert(recs.size() >= 1);
        System.assertEquals('Registered', recs[0].bookingStatus);
        System.assertNotEquals(null, recs[0].attendeeName);
        System.assertNotEquals(null, recs[0].eventName);
        System.assert(recs[0].attendeeCount >= 1);
    }

    @IsTest
    static void testGetBookingList_cancellations() {
        Test.startTest();
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('cancellations', null, null, null, null);
        Test.stopTest();
        System.assert(recs.size() >= 1);
        System.assertEquals('Cancelled', recs[0].bookingStatus);
    }

    @IsTest
    static void testGetBookingList_topEvents() {
        Test.startTest();
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('top_events', 'Test Conference 2024', null, null, null);
        Test.stopTest();
        System.assert(recs.size() >= 1);
    }

    @IsTest
    static void testGetBookingList_topEventsNoMatch() {
        Test.startTest();
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('top_events', 'NonExistent Event XYZ', null, null, null);
        Test.stopTest();
        System.assertEquals(0, recs.size());
    }

    @IsTest
    static void testGetBookingList_trends() {
        Test.startTest();
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('trends', '2024', null, null, null);
        Test.stopTest();
        System.assert(recs.size() >= 1);
    }

    @IsTest
    static void testGetBookingList_trendsInvalidYear() {
        Test.startTest();
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('trends', 'notAYear', null, null, null);
        Test.stopTest();
        System.assertNotEquals(null, recs);
    }

    @IsTest
    static void testGetBookingList_trendsNoMatchingSessions() {
        Test.startTest();
        // Year 2099 — no sessions fall in that range
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('trends', '2099', null, null, null);
        Test.stopTest();
        System.assertEquals(0, recs.size());
    }

    @IsTest
    static void testGetBookingList_noEventsFromFilter() {
        Test.startTest();
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('registrations', null, 'NonExistentType', null, null);
        Test.stopTest();
        System.assertEquals(0, recs.size());
    }

    @IsTest
    static void testGetBookingList_withYearFilter() {
        Test.startTest();
        List<KenEventsDashboardController.BookingListRecord> recs = KenEventsDashboardController.getBookingList('registrations', null, null, null, '2024');
        Test.stopTest();
        System.assert(recs.size() >= 1);
    }
}