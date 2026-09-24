/**
 * @description Coverage for KenDateTimeUtil.
 *
 *              The assertions that matter are the midnight-crossing ones. A
 *              00:30 IST moment belongs to the *previous* UTC day, and reading
 *              it with dateGmt() rather than a zone-aware derivation is exactly
 *              the bug that put sessions on the wrong date. Those cases are
 *              pinned against an explicit Asia/Kolkata zone so they assert real
 *              values instead of whatever the running user happens to be set to.
 */
@isTest
private class KenDateTimeUtilTest {

    private static final TimeZone IST = TimeZone.getTimeZone('Asia/Kolkata');
    private static final TimeZone UTC = TimeZone.getTimeZone('GMT');

    @isTest
    static void formatInstant_producesTheWireFormat() {
        DateTime value = DateTime.newInstanceGmt(2026, 8, 21, 6, 25, 0);
        System.assertEquals(
            '2026-08-21T06:25:00.000Z',
            KenDateTimeUtil.formatInstant(value),
            'Should match the format c/kenDateTime emits'
        );
        System.assertEquals(null, KenDateTimeUtil.formatInstant(null), 'null in, null out');
    }

    @isTest
    static void formatInstant_ignoresRunningUserTimezone() {
        // formatGmt, not format: the wire value must be identical regardless of
        // who is running, or the LWC would receive a shifted instant.
        DateTime value = DateTime.newInstanceGmt(2026, 8, 21, 23, 45, 0);
        String asDefaultUser = KenDateTimeUtil.formatInstant(value);
        System.assertEquals('2026-08-21T23:45:00.000Z', asDefaultUser, 'Must be UTC on the wire');
    }

    @isTest
    static void parseInstant_readsTheWireFormat() {
        DateTime parsed = KenDateTimeUtil.parseInstant('2026-08-21T06:25:00.000Z');
        System.assertNotEquals(null, parsed, 'Should parse');
        System.assertEquals(2026, parsed.yearGmt(), 'Year');
        System.assertEquals(8, parsed.monthGmt(), 'Month');
        System.assertEquals(21, parsed.dayGmt(), 'Day');
        System.assertEquals(6, parsed.hourGmt(), 'Hour');
        System.assertEquals(25, parsed.minuteGmt(), 'Minute');
    }

    @isTest
    static void parseInstant_toleratesJunk() {
        System.assertEquals(null, KenDateTimeUtil.parseInstant(null), 'null');
        System.assertEquals(null, KenDateTimeUtil.parseInstant(''), 'empty');
        System.assertEquals(null, KenDateTimeUtil.parseInstant('   '), 'blank');
        System.assertEquals(null, KenDateTimeUtil.parseInstant('not-a-date'), 'garbage');
    }

    @isTest
    static void roundTrip_survivesFormatThenParse() {
        DateTime original = DateTime.newInstanceGmt(2026, 12, 31, 18, 30, 0);
        DateTime back = KenDateTimeUtil.parseInstant(KenDateTimeUtil.formatInstant(original));
        System.assertEquals(original, back, 'Format then parse should be lossless');
    }

    @isTest
    static void formatTimeOfDay_returnsUtcWallClock() {
        DateTime value = DateTime.newInstanceGmt(2026, 8, 21, 6, 25, 0);
        System.assertEquals('06:25', KenDateTimeUtil.formatTimeOfDay(value), 'UTC HH:mm');
        System.assertEquals(null, KenDateTimeUtil.formatTimeOfDay(null), 'null in, null out');
    }

    @isTest
    static void instantFrom_returnsNullForUnqueriedField() {
        // Selecting only Id leaves Start_DateTime__c unpopulated. A direct get()
        // would throw; instantFrom must absorb that.
        Ken_Schedule_Sessions__c session = new Ken_Schedule_Sessions__c(Name = 'tz probe');
        insert session;
        Ken_Schedule_Sessions__c thin = [SELECT Id FROM Ken_Schedule_Sessions__c WHERE Id = :session.Id];

        System.assertEquals(
            null,
            KenDateTimeUtil.instantFrom(thin, 'Start_DateTime__c'),
            'Unqueried field should read as null, not throw'
        );
        System.assertEquals(null, KenDateTimeUtil.instantFrom(null, 'Start_DateTime__c'), 'null record');
    }

    @isTest
    static void instantFrom_readsQueriedField() {
        Ken_Schedule_Sessions__c session = new Ken_Schedule_Sessions__c(
            Name = 'tz probe',
            Start_DateTime__c = DateTime.newInstanceGmt(2026, 8, 21, 6, 25, 0)
        );
        insert session;

        Ken_Schedule_Sessions__c full = [
            SELECT Id, Start_DateTime__c FROM Ken_Schedule_Sessions__c WHERE Id = :session.Id
        ];
        System.assertEquals(
            '2026-08-21T06:25:00.000Z',
            KenDateTimeUtil.instantFrom(full, 'Start_DateTime__c'),
            'Queried field should render'
        );
    }

    @isTest
    static void localDate_crossesMidnightCorrectly() {
        // 19:00Z on the 21st is 00:30 IST on the 22nd. Deriving the day in IST
        // must give the 22nd; dateGmt() would wrongly give the 21st.
        DateTime lateEvening = DateTime.newInstanceGmt(2026, 8, 21, 19, 0, 0);

        System.assertEquals(
            Date.newInstance(2026, 8, 22),
            KenDateTimeUtil.localDate(lateEvening, IST),
            'IST viewer is already on the next day'
        );
        System.assertEquals(
            Date.newInstance(2026, 8, 21),
            KenDateTimeUtil.localDate(lateEvening, UTC),
            'UTC viewer is still on the 21st'
        );
    }

    @isTest
    static void localDate_handlesNullsAndDefaultZone() {
        System.assertEquals(null, KenDateTimeUtil.localDate(null), 'null instant');
        System.assertEquals(null, KenDateTimeUtil.localDate(null, IST), 'null instant with zone');

        DateTime value = DateTime.newInstanceGmt(2026, 8, 21, 12, 0, 0);
        System.assertEquals(
            value.date(),
            KenDateTimeUtil.localDate(value),
            'No-zone overload should follow the running user'
        );
        System.assertEquals(
            value.date(),
            KenDateTimeUtil.localDate(value, null),
            'null zone should fall back to the running user'
        );
    }

    @isTest
    static void dayStart_pinsMidnightInTheGivenZone() {
        // Midnight IST on the 22nd is 18:30Z on the 21st.
        DateTime istMidnight = KenDateTimeUtil.dayStart(Date.newInstance(2026, 8, 22), IST);
        System.assertEquals(
            '2026-08-21T18:30:00.000Z',
            KenDateTimeUtil.formatInstant(istMidnight),
            'IST midnight is 18:30Z the previous day'
        );

        DateTime utcMidnight = KenDateTimeUtil.dayStart(Date.newInstance(2026, 8, 22), UTC);
        System.assertEquals(
            '2026-08-22T00:00:00.000Z',
            KenDateTimeUtil.formatInstant(utcMidnight),
            'UTC midnight is 00:00Z'
        );
    }

    @isTest
    static void dayStart_roundTripsWithLocalDate() {
        // The pair has to be self-consistent, or a range query would exclude
        // records that fall on its own boundary.
        Date day = Date.newInstance(2026, 8, 22);
        System.assertEquals(
            day,
            KenDateTimeUtil.localDate(KenDateTimeUtil.dayStart(day, IST), IST),
            'dayStart then localDate should return the same day'
        );
    }

    @isTest
    static void dayAfter_isTheExclusiveUpperBound() {
        Date day = Date.newInstance(2026, 8, 22);
        System.assertEquals(
            KenDateTimeUtil.formatInstant(KenDateTimeUtil.dayStart(Date.newInstance(2026, 8, 23), IST)),
            KenDateTimeUtil.formatInstant(KenDateTimeUtil.dayAfter(day, IST)),
            'dayAfter(d) should equal dayStart(d + 1)'
        );

        // The last representable moment of the day must fall inside the range.
        // Built from epoch millis because Datetime has no addMilliseconds().
        DateTime lastMoment = DateTime.newInstance(KenDateTimeUtil.dayAfter(day, IST).getTime() - 1);
        System.assert(
            lastMoment >= KenDateTimeUtil.dayStart(day, IST) && lastMoment < KenDateTimeUtil.dayAfter(day, IST),
            'End of day should sit inside [dayStart, dayAfter)'
        );
        System.assertEquals(
            day,
            KenDateTimeUtil.localDate(lastMoment, IST),
            'End of day still resolves to the same calendar day'
        );
    }

    @isTest
    static void dayHelpers_handleNulls() {
        System.assertEquals(null, KenDateTimeUtil.dayStart(null), 'null day');
        System.assertEquals(null, KenDateTimeUtil.dayStart(null, IST), 'null day with zone');
        System.assertEquals(null, KenDateTimeUtil.dayAfter(null), 'null day');
        System.assertEquals(null, KenDateTimeUtil.dayAfter(null, IST), 'null day with zone');

        Date day = Date.newInstance(2026, 8, 22);
        System.assertEquals(
            KenDateTimeUtil.dayStart(day),
            KenDateTimeUtil.dayStart(day, null),
            'null zone should fall back to the running user'
        );
    }
}