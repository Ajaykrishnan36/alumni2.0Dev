/**
 * @description Apex counterpart to the c/kenDateTime LWC module. One place for
 *              the wire format that crosses the Apex/LWC boundary, and for the
 *              timezone arithmetic that turns a stored instant into a calendar
 *              day.
 *
 *              Storage contract, identical to the JS side: every instant lives
 *              in a Salesforce DateTime field, in UTC. The wire representation
 *              is ISO-8601 with milliseconds and a literal Z, which is what
 *              c/kenDateTime.toUtcInstant emits and fromUtcInstant reads.
 *
 *              This class exists because that format string was hand-copied
 *              into seven controllers, each as a private method nothing else
 *              could reuse. They agreed, but only by luck.
 *
 *              On timezones: the day-boundary helpers deliberately resolve in
 *              the *running user's* timezone, because that is what the Date
 *              fields they replace already did — a Salesforce Date column and
 *              Date.today() are both running-user-relative. Passing an explicit
 *              TimeZone is supported for callers that need to pin a zone.
 */
public with sharing class KenDateTimeUtil {

    /** The format c/kenDateTime speaks, e.g. "2026-08-21T06:25:00.000Z". */
    private static final String ISO_INSTANT = 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'';

    /** Time-of-day fragment for wire values that carry no date. */
    private static final String WIRE_TIME = 'HH:mm';

    private KenDateTimeUtil() {
        // Utility class; never instantiated.
    }

    /**
     * @description Renders a stored instant as the ISO-8601 UTC string the
     *              components expect. formatGmt, never format, so the running
     *              user's timezone cannot leak into the wire value.
     *
     * @param value stored DateTime, or null
     * @return      ISO-8601 string, or null
     */
    public static String formatInstant(DateTime value) {
        return value == null ? null : value.formatGmt(ISO_INSTANT);
    }

    /**
     * @description Parses an ISO-8601 UTC instant produced by
     *              c/kenDateTime.toUtcInstant.
     *
     * @param iso ISO-8601 string, or blank
     * @return    the instant, or null when absent or unparseable
     */
    public static DateTime parseInstant(String iso) {
        if (String.isBlank(iso)) {
            return null;
        }
        try {
            return (DateTime) JSON.deserialize('"' + iso + '"', DateTime.class);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Time-of-day fragment of an instant, in UTC, for wire values
     *              that carry no date of their own.
     *
     * @param value stored DateTime, or null
     * @return      "HH:mm", or null
     */
    public static String formatTimeOfDay(DateTime value) {
        return value == null ? null : value.formatGmt(WIRE_TIME);
    }

    /**
     * @description Reads an instant field only when the caller actually queried
     *              it. Touching an unqueried field throws SObjectException, and
     *              the wrappers in this codebase are built from several
     *              different SOQL statements, not all of which select every
     *              column. Returning null lets those callers keep working.
     *
     * @param record the queried record
     * @param field  API name of the DateTime field
     * @return       ISO-8601 string, or null when absent or not queried
     */
    public static String instantFrom(SObject record, String field) {
        if (record == null) {
            return null;
        }
        String apiName = KenNamespaceUtil.qualifyCustom(field);
        if (!record.getPopulatedFieldsAsMap().containsKey(apiName)) {
            return null;
        }
        return formatInstant((DateTime) record.get(apiName));
    }

    /**
     * @description Calendar day an instant falls on, in the running user's
     *              timezone. This is the derivation that replaces the retired
     *              Date columns: DateTime.date() already converts out of UTC
     *              into the running user's zone, which is the same zone the old
     *              Date column and Date.today() resolved against.
     *
     * @param instant stored DateTime, or null
     * @return        the calendar day, or null
     */
    public static Date localDate(DateTime instant) {
        return instant == null ? null : instant.date();
    }

    /**
     * @description Calendar day an instant falls on, in an explicit timezone,
     *              for callers that must not depend on who is running.
     *
     * @param instant stored DateTime, or null
     * @param tz      timezone to resolve against
     * @return        the calendar day, or null
     */
    public static Date localDate(DateTime instant, TimeZone tz) {
        if (instant == null) {
            return null;
        }
        if (tz == null) {
            return instant.date();
        }
        return Date.valueOf(instant.format('yyyy-MM-dd', tz.getID()));
    }

    /**
     * @description First instant of a calendar day, in the running user's
     *              timezone. Use as the inclusive lower bound of a day filter.
     *
     *              This is the half of a range query that replaces
     *              "Start_Date__c >= :someDate". A bare Date comparison was
     *              timezone-free; an instant comparison is not, so the boundary
     *              has to be materialised explicitly.
     *
     * @param day calendar day, or null
     * @return    midnight at the start of that day, or null
     */
    public static DateTime dayStart(Date day) {
        return day == null ? null : DateTime.newInstance(day, Time.newInstance(0, 0, 0, 0));
    }

    /**
     * @description First instant of a calendar day, in an explicit timezone.
     *
     * @param day calendar day, or null
     * @param tz  timezone to resolve against
     * @return    midnight at the start of that day, or null
     */
    public static DateTime dayStart(Date day, TimeZone tz) {
        if (day == null) {
            return null;
        }
        if (tz == null) {
            return dayStart(day);
        }
        // Offset is milliseconds east of UTC for that actual moment, so DST is
        // accounted for rather than assumed.
        DateTime naiveUtc = DateTime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0));
        return naiveUtc.addSeconds(-tz.getOffset(naiveUtc) / 1000);
    }

    /**
     * @description First instant of the *following* day, for use as an
     *              exclusive upper bound.
     *
     *              Prefer "field >= dayStart(d1) AND field < dayAfter(d2)" over
     *              a "<=" against the end of the day. An inclusive upper bound
     *              has to guess a precision — 23:59:59, or 23:59:59.999 — and
     *              silently drops anything in the gap.
     *
     * @param day calendar day, or null
     * @return    midnight starting the next day, or null
     */
    public static DateTime dayAfter(Date day) {
        return day == null ? null : dayStart(day.addDays(1));
    }

    /**
     * @description First instant of the following day, in an explicit timezone.
     *
     * @param day calendar day, or null
     * @param tz  timezone to resolve against
     * @return    midnight starting the next day, or null
     */
    public static DateTime dayAfter(Date day, TimeZone tz) {
        return day == null ? null : dayStart(day.addDays(1), tz);
    }
}