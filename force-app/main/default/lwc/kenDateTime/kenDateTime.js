/**
 * Shared date/time helpers for the portal.
 *
 * Storage contract: every instant lives in a Salesforce DateTime field, in UTC.
 * Salesforce converts to the viewer's timezone on read, so display code should
 * lean on <lightning-formatted-date-time> rather than doing its own maths.
 *
 * These helpers exist for the write side. A date picker and a time picker each
 * hand back a timezone-less fragment, and the two input widgets in use disagree
 * about what their fragment means:
 *
 *   <input type="time">            -> local wall clock, "HH:mm"       (HTML spec)
 *   <lightning-input type="time">  -> UTC wall clock,   "HH:mm:ss.sssZ"
 *
 * Combining either fragment with the picked calendar date is the only way to
 * recover the real instant, and getting that pairing wrong is what produced the
 * mixed IST / UTC / local+5:30 data already in the org.
 */

const MINUTES_PER_DAY = 24 * 60;

/**
 * Normalise whatever a time input handed back into local wall-clock minutes.
 *
 * A trailing "Z" means the widget already shifted the user's pick into UTC, so
 * the browser offset has to be added back. The modulo is deliberate: a late
 * evening pick in a positive-offset zone comes back as the previous UTC day
 * (21:00 IST -> "15:30Z"), and an early morning pick wraps the other way
 * (00:30 IST -> "19:00Z"). Wrapping recovers the wall clock in both directions;
 * the caller pairs it with the local date the user actually chose, which is
 * where the correct day comes from.
 *
 * @param {string} value raw value from the input
 * @returns {number|null} minutes since local midnight, or null if unparseable
 */
function toLocalMinutes(value) {
    if (!value) {
        return null;
    }

    let raw = String(value).trim();
    if (!raw) {
        return null;
    }

    const isUtc = raw.endsWith('Z');
    if (raw.includes('T')) {
        raw = raw.split('T')[1];
    }
    raw = raw.replace('Z', '');

    const parts = raw.split(':');
    if (parts.length < 2) {
        return null;
    }

    const hours = Number(parts[0]);
    const minutes = Number(parts[1]);
    if (!Number.isFinite(hours) || !Number.isFinite(minutes)) {
        return null;
    }

    let total = hours * 60 + minutes;
    if (isUtc) {
        // getTimezoneOffset() is minutes *behind* UTC, so IST reports -330.
        total -= new Date().getTimezoneOffset();
    }
    return ((total % MINUTES_PER_DAY) + MINUTES_PER_DAY) % MINUTES_PER_DAY;
}

/**
 * Combine a local calendar date and a local time into a UTC instant.
 *
 * @param {string} dateIso local calendar date, "YYYY-MM-DD"
 * @param {string} timeValue value from either time input
 * @returns {string|null} ISO instant, e.g. "2026-08-21T06:25:00.000Z"
 */
export function toUtcInstant(dateIso, timeValue) {
    if (!dateIso) {
        return null;
    }

    const [year, month, day] = String(dateIso).split('-').map(Number);
    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
        return null;
    }

    const minutes = toLocalMinutes(timeValue);
    if (minutes === null) {
        return null;
    }

    // Constructed in local time on purpose — the Date constructor applies the
    // browser offset, which is exactly the conversion we want.
    return new Date(year, month - 1, day, Math.floor(minutes / 60), minutes % 60, 0, 0).toISOString();
}

/**
 * Split a stored UTC instant back into the local fragments the pickers expect.
 *
 * @param {string|number|Date} instant value from a DateTime field
 * @returns {{date: string, time: string}|null} local "YYYY-MM-DD" and "HH:mm"
 */
export function fromUtcInstant(instant) {
    if (instant === null || instant === undefined || instant === '') {
        return null;
    }

    const d = instant instanceof Date ? instant : new Date(instant);
    if (Number.isNaN(d.getTime())) {
        return null;
    }

    return { date: localDateKey(d), time: localTimeKey(d) };
}

/**
 * Local calendar date as "YYYY-MM-DD".
 *
 * Use this rather than toISOString().split('T')[0], which converts to UTC first
 * and so returns yesterday for any IST moment before 05:30.
 *
 * @param {Date} [d] defaults to now
 * @returns {string}
 */
export function localDateKey(d = new Date()) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

/**
 * Local wall-clock time as "HH:mm", for seeding a time input.
 *
 * @param {Date} [d] defaults to now
 * @returns {string}
 */
export function localTimeKey(d = new Date()) {
    return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/* ── Display ──────────────────────────────────────────────────────────────
 *
 * Everything below formats a stored UTC instant for the person looking at it,
 * using the timezone their device reports right now.
 *
 * Deliberately NOT <lightning-formatted-date-time>: that converts using the
 * Salesforce User record's TimeZoneSidKey, and onboarding stamps every portal
 * user Asia/Kolkata regardless of where they are. It would confidently show IST
 * to someone in London. The browser is the only source that knows the truth,
 * and it is re-read on every call so a device that changes zone mid-session —
 * or a user who travels — is picked up without a reload.
 */

/** @returns {string} the viewer's current IANA timezone, e.g. "Europe/London" */
export function viewerTimeZone() {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
}

// Locales are pinned, not left to the browser: this migration should change
// WHEN a time is shown, not how it reads. An unpinned Intl call renders 24-hour
// on a machine set to en-GB, which is a visible change nobody asked for.
// en-GB gives day-first dates ("21 Aug 2026"); en-US gives uppercase AM/PM
// ("1:30 PM") — together they match what the Apex formatters produced.
const DATE_LOCALE = 'en-GB';
const TIME_LOCALE = 'en-US';

function toDate(instant) {
    if (instant === null || instant === undefined || instant === '') {
        return null;
    }
    const d = instant instanceof Date ? instant : new Date(instant);
    return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Format a UTC instant in the viewer's timezone.
 *
 * @param {string|number|Date} instant stored UTC value
 * @param {Intl.DateTimeFormatOptions} [options]
 * @param {string} [fallback] returned when the instant is missing
 * @returns {string}
 */
export function formatInViewerZone(instant, options = {}, fallback = '', locale = DATE_LOCALE) {
    const d = toDate(instant);
    if (!d) {
        return fallback;
    }
    // No timeZone key — omitting it makes Intl use the runtime's current zone,
    // which is what we want. Passing one would pin it and defeat the purpose.
    return new Intl.DateTimeFormat(locale, options).format(d);
}

/** "21 Aug 2026" */
export function formatDate(instant, fallback = '') {
    return formatInViewerZone(instant, { day: '2-digit', month: 'short', year: 'numeric' }, fallback);
}

/** "11:55 am" */
export function formatTime(instant, fallback = '') {
    return formatInViewerZone(instant, { hour: 'numeric', minute: '2-digit', hour12: true }, fallback, TIME_LOCALE);
}

/** "21 Aug 2026, 11:55 am" */
export function formatDateTime(instant, fallback = '') {
    return formatInViewerZone(
        instant,
        { day: '2-digit', month: 'short', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true },
        fallback
    );
}

/**
 * "1:30PM" / "1PM" — the compact, space-less style some event cards use.
 * Kept as its own helper so those cards read exactly as they did before the
 * timezone migration; only the underlying instant changed, not the styling.
 *
 * @param {string|number|Date} instant
 * @param {string} [meridiem] "upper" for PM, "title" for Pm
 * @returns {string}
 */
export function formatTimeCompact(instant, meridiem = 'upper', fallback = '') {
    const d = toDate(instant);
    if (!d) {
        return fallback;
    }
    const parts = new Intl.DateTimeFormat(TIME_LOCALE, {
        hour: 'numeric', minute: '2-digit', hour12: true, timeZone: viewerTimeZone()
    }).formatToParts(d);
    const get = (t) => (parts.find((x) => x.type === t) || {}).value || '';
    const suffix = get('dayPeriod').toUpperCase();
    const mm = get('minute');
    const shown = meridiem === 'title' ? suffix.charAt(0) + suffix.charAt(1).toLowerCase() : suffix;
    return mm === '00' ? `${get('hour')}${shown}` : `${get('hour')}:${mm}${shown}`;
}

/** "13:30" — 24-hour, for the screens that always showed it that way. */
export function formatTime24(instant, fallback = '') {
    return formatInViewerZone(instant, { hour: '2-digit', minute: '2-digit', hour12: false }, fallback, 'en-GB');
}

/** "21 Aug, 2026" — with the comma the Apex label builders emitted. */
export function formatDateComma(instant, fallback = '') {
    const base = formatDate(instant, '');
    if (!base) {
        return fallback;
    }
    return base.replace(/ (\d{4})$/, ', $1');
}

/**
 * "11:55 AM - 1:30 PM", collapsing to a single time when there is no end.
 *
 * @param {string|number|Date} startInstant
 * @param {string|number|Date} [endInstant]
 * @returns {string}
 */
export function formatTimeRange(startInstant, endInstant, fallback = '') {
    const start = formatTime(startInstant, '');
    if (!start) {
        return fallback;
    }
    const end = formatTime(endInstant, '');
    return end ? `${start} - ${end}` : start;
}

/**
 * "21 Aug 2026" for a single day, "21 - 23 Aug 2026" within a month,
 * "30 Aug - 2 Sep 2026" across months.
 *
 * Compared on the viewer's calendar days, not UTC ones, so an evening event
 * does not read as spanning two days just because it crosses midnight GMT.
 */
export function formatDateRange(startInstant, endInstant, fallback = '') {
    const s = toDate(startInstant);
    if (!s) {
        return fallback;
    }
    const e = toDate(endInstant);
    if (!e || localDateKey(s) === localDateKey(e)) {
        return formatDate(s);
    }

    // formatRange collapses the shared parts itself and in the right order for
    // the locale — "Aug 21 - 23, 2026" in en-US, "21-23 Aug 2026" in en-GB.
    // Hand-concatenating the two ends produces "21 - Aug 23, 2026" instead.
    const fmt = new Intl.DateTimeFormat(DATE_LOCALE, { day: 'numeric', month: 'short', year: 'numeric' });
    if (typeof fmt.formatRange === 'function') {
        return fmt.formatRange(s, e);
    }
    return `${formatDate(s)} - ${formatDate(e)}`;
}