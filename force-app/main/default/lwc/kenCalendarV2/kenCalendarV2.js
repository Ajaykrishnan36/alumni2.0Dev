import { LightningElement } from 'lwc';

const EVENTS = [
    { day: 12, title: 'Bangalore Alumni Meetup', location: 'The Lalit, Bangalore', tone: 'amber' },
    { day: 18, title: 'Q2 mentor sign-ups close', location: 'Mentorship portal', tone: 'violet' },
    { day: 22, title: 'AI in Career Building webinar', location: 'Online · 6:00 PM', tone: 'sky' },
    { day: 25, title: 'Annual Reunion announcement', location: 'Campus wide', tone: 'rose' },
    { day: 28, title: 'Living Earth Collaborative', location: 'Innovation Hub', tone: 'emerald' },
    { day: 31, title: 'Workshop with Tanya J', location: 'Block C · 11:00 AM', tone: 'amber' }
];

const MONTH_NAMES = ['January','February','March','April','May','June','July','August','September','October','November','December'];
const MONTH_SHORT = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];

export default class KenCalendarV2 extends LightningElement {
    monthIndex = 4; // May
    yearValue = 2026;
    todayDay = 22;

    get monthLabel() {
        return `${MONTH_NAMES[this.monthIndex]} ${this.yearValue}`;
    }

    get weekdayLabels() {
        return [
            { key: 'mon', label: 'Mon' },
            { key: 'tue', label: 'Tue' },
            { key: 'wed', label: 'Wed' },
            { key: 'thu', label: 'Thu' },
            { key: 'fri', label: 'Fri' },
            { key: 'sat', label: 'Sat' },
            { key: 'sun', label: 'Sun' }
        ];
    }

    get gridCells() {
        // May 2026: May 1 = Friday. ISO Mon-start week => leading blanks = 4
        const firstWeekday = new Date(this.yearValue, this.monthIndex, 1).getDay(); // 0=Sun..6=Sat
        // Convert to Mon-start: Mon=0..Sun=6
        const leading = (firstWeekday + 6) % 7;
        const daysInMonth = new Date(this.yearValue, this.monthIndex + 1, 0).getDate();
        const total = 42;
        const cells = [];
        const prevMonthDays = new Date(this.yearValue, this.monthIndex, 0).getDate();

        for (let i = 0; i < total; i++) {
            let dayNum;
            let inMonth = false;
            let cellClass = 'cal-cell';
            if (i < leading) {
                dayNum = prevMonthDays - (leading - 1 - i);
                cellClass += ' cal-cell--muted';
            } else if (i < leading + daysInMonth) {
                dayNum = i - leading + 1;
                inMonth = true;
            } else {
                dayNum = i - (leading + daysInMonth) + 1;
                cellClass += ' cal-cell--muted';
            }

            const isToday = inMonth && dayNum === this.todayDay;
            if (isToday) cellClass += ' cal-cell--today';

            const dayEvents = inMonth ? EVENTS.filter(e => e.day === dayNum) : [];
            const visible = dayEvents.slice(0, 3).map((e, idx) => ({
                key: `${i}-${idx}`,
                stripeClass: `cal-chip cal-chip--${e.tone}`,
                title: e.title
            }));
            const overflow = dayEvents.length > 3 ? dayEvents.length - 3 : 0;
            const showOverflow = overflow > 0;
            const overflowLabel = `+${overflow} more`;

            cells.push({
                key: `c-${i}`,
                cellClass,
                dayNum,
                visible,
                showOverflow,
                overflowLabel
            });
        }
        return cells;
    }

    get upcomingEvents() {
        return EVENTS.map((e, i) => ({
            key: `e-${i}`,
            barClass: `cal-evt__bar cal-evt__bar--${e.tone}`,
            dateLabel: `${String(e.day).padStart(2, '0')} ${MONTH_SHORT[this.monthIndex]}`,
            title: e.title,
            location: e.location
        }));
    }
}