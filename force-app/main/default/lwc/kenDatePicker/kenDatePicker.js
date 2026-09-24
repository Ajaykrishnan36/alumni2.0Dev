import { LightningElement, api, track } from 'lwc';

const MONTH_NAMES = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
];
const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const DEFAULT_MIN = '1900-01-01';

const VIEW_DAYS = 'days';
const VIEW_MONTHS = 'months';
const VIEW_YEARS = 'years';

/** yyyy-mm-dd for a Date, in local time (toISOString would shift across timezones). */
function toIso(date) {
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
}

/** Parses yyyy-mm-dd into a local Date, or null when the text is not a real date. */
function fromIso(iso) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || '').trim());
    if (!match) {
        return null;
    }
    const [, year, month, day] = match.map(Number);
    const date = new Date(year, month - 1, day);
    // Rejects the likes of 2003-02-31, which Date happily rolls into March.
    return date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day
        ? date
        : null;
}

/**
 * A single-date calendar built for dates far from today — a date of birth above all.
 *
 * The browser's own picker steps one month at a time, so reaching 2003 takes a great deal
 * of clicking. Native <select> dropdowns fix the clicking but drop a century-long list over
 * the whole page. So the month and year live in grids inside the panel instead: tapping the
 * title opens years, picking a year opens months, picking a month returns to the days. Any
 * date is three taps away and nothing ever escapes the panel.
 *
 * Built from plain buttons rather than Lightning base components: this sits in a form that
 * already carries plenty of them, and it mounts and unmounts on every use.
 */
export default class KenDatePicker extends LightningElement {
    /** Earliest selectable date, yyyy-mm-dd. Defaults to 1900-01-01. */
    @api min = DEFAULT_MIN;
    /** Latest selectable date, yyyy-mm-dd. Defaults to today. */
    @api max = '';

    @track viewYear;
    @track viewMonth;
    @track view = VIEW_DAYS;

    _value = '';
    _anchored = false;
    _yearScrolled = false;

    /**
     * Currently selected date, yyyy-mm-dd. Anchoring happens here rather than in
     * connectedCallback: the panel was opening on today's month because the property had not
     * landed yet when that ran, so a field already holding 31/12/2003 opened on the wrong year.
     */
    @api
    get value() {
        return this._value;
    }

    set value(next) {
        const normalised = next || '';
        if (this._anchored && normalised === this._value) {
            // A re-render passing the same value must not throw away where the user browsed to.
            return;
        }
        this._value = normalised;
        this._anchored = true;
        this.anchorToValue();
    }

    /** Opens on the selected date, or on the newest month the bounds allow when there is none. */
    anchorToValue() {
        const anchor = fromIso(this._value) || fromIso(this.maxIso) || new Date();
        this.viewYear = anchor.getFullYear();
        this.viewMonth = anchor.getMonth();
    }

    connectedCallback() {
        if (!this._anchored) {
            this._anchored = true;
            this.anchorToValue();
        }
    }

    /** Centres the year list on the current year without scrolling the page behind it. */
    renderedCallback() {
        if (this.view !== VIEW_YEARS) {
            this._yearScrolled = false;
            return;
        }
        if (this._yearScrolled) {
            return;
        }
        const list = this.template.querySelector('.scroller');
        const current = this.template.querySelector('.cell.current');
        if (list && current) {
            list.scrollTop = current.offsetTop - (list.clientHeight / 2) + (current.offsetHeight / 2);
        }
        this._yearScrolled = true;
    }

    get maxIso() {
        return this.max || toIso(new Date());
    }

    get minIso() {
        return this.min || DEFAULT_MIN;
    }

    get minDate() {
        return fromIso(this.minIso) || new Date(1900, 0, 1);
    }

    get maxDate() {
        return fromIso(this.maxIso) || new Date();
    }

    get isDayView() {
        return this.view === VIEW_DAYS;
    }

    get isMonthView() {
        return this.view === VIEW_MONTHS;
    }

    get isYearView() {
        return this.view === VIEW_YEARS;
    }

    get title() {
        if (this.view === VIEW_YEARS) {
            return 'Select year';
        }
        if (this.view === VIEW_MONTHS) {
            return String(this.viewYear);
        }
        return `${MONTH_NAMES[this.viewMonth]} ${this.viewYear}`;
    }

    /** The steppers only make sense on the day grid. */
    get showSteppers() {
        return this.view === VIEW_DAYS;
    }

    get weekdays() {
        return WEEKDAYS.map((label, index) => ({ key: `wd-${index}`, label }));
    }

    /**
     * Six rows of seven, so the grid keeps its height as months change and the panel
     * does not jump under the pointer.
     */
    get weeks() {
        const { minDate, maxDate } = this;
        const selectedIso = fromIso(this.value) ? this.value : '';
        const todayIso = toIso(new Date());

        const firstOfMonth = new Date(this.viewYear, this.viewMonth, 1);
        const cursor = new Date(this.viewYear, this.viewMonth, 1 - firstOfMonth.getDay());

        const weeks = [];
        for (let week = 0; week < 6; week++) {
            const days = [];
            for (let day = 0; day < 7; day++) {
                const iso = toIso(cursor);
                const outside = cursor.getMonth() !== this.viewMonth;
                const disabled = cursor < minDate || cursor > maxDate;

                let cssClass = 'day';
                if (outside) cssClass += ' outside';
                if (iso === selectedIso) cssClass += ' selected';
                else if (iso === todayIso) cssClass += ' today';

                days.push({
                    key: iso,
                    iso,
                    label: String(cursor.getDate()),
                    cssClass,
                    disabled,
                    tabIndex: disabled ? -1 : 0
                });
                cursor.setDate(cursor.getDate() + 1);
            }
            weeks.push({ key: `w-${week}`, days });
        }
        return weeks;
    }

    /** Twelve months for the year on show, three to a row. */
    get monthCells() {
        const { minDate, maxDate } = this;
        const selected = fromIso(this.value);
        return MONTH_SHORT.map((label, index) => {
            // A month is out of range only when none of its days are reachable.
            const lastOfMonth = new Date(this.viewYear, index + 1, 0);
            const firstOfMonth = new Date(this.viewYear, index, 1);
            const disabled = lastOfMonth < minDate || firstOfMonth > maxDate;

            let cssClass = 'cell';
            if (selected && selected.getFullYear() === this.viewYear && selected.getMonth() === index) {
                cssClass += ' selected';
            } else if (index === this.viewMonth) {
                cssClass += ' current';
            }
            return { key: `m-${index}`, label, value: String(index), cssClass, disabled };
        });
    }

    /** Newest first, so a recent birth year is at the top rather than a long scroll down. */
    get yearCells() {
        const selected = fromIso(this.value);
        const first = this.minDate.getFullYear();
        const last = this.maxDate.getFullYear();
        const cells = [];
        for (let year = last; year >= first; year--) {
            let cssClass = 'cell';
            if (selected && selected.getFullYear() === year) {
                cssClass += ' selected';
            } else if (year === this.viewYear) {
                cssClass += ' current';
            }
            cells.push({ key: `y-${year}`, label: String(year), value: String(year), cssClass });
        }
        return cells;
    }

    get isPrevDisabled() {
        // The last day of the previous month; if even that is before min there is nowhere to go.
        return new Date(this.viewYear, this.viewMonth, 0) < this.minDate;
    }

    get isNextDisabled() {
        return new Date(this.viewYear, this.viewMonth + 1, 1) > this.maxDate;
    }

    /** Title cycles into the year list and back out again. */
    handleToggleView() {
        this.view = this.view === VIEW_DAYS ? VIEW_YEARS : VIEW_DAYS;
    }

    handleSelectYear(event) {
        this.viewYear = Number(event.currentTarget.dataset.value);
        this.view = VIEW_MONTHS;
    }

    handleSelectMonth(event) {
        this.viewMonth = Number(event.currentTarget.dataset.value);
        this.view = VIEW_DAYS;
    }

    handlePrevMonth() {
        this.shiftMonth(-1);
    }

    handleNextMonth() {
        this.shiftMonth(1);
    }

    shiftMonth(delta) {
        const shifted = new Date(this.viewYear, this.viewMonth + delta, 1);
        this.viewYear = shifted.getFullYear();
        this.viewMonth = shifted.getMonth();
    }

    handleSelectDay(event) {
        const { iso } = event.currentTarget.dataset;
        if (iso) {
            this.dispatchEvent(new CustomEvent('select', { detail: { value: iso } }));
        }
    }

    handleKeyDown(event) {
        if (event.key !== 'Escape') {
            return;
        }
        event.stopPropagation();
        // Escape steps back out of the year and month lists before closing the panel.
        if (this.view !== VIEW_DAYS) {
            this.view = VIEW_DAYS;
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }
}