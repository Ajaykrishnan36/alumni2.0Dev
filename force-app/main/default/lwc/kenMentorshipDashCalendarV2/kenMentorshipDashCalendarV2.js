// Dashboard calendar — 50% mini-calendar, 50% per-day agenda.
// Consumes ScheduleEventRow[] from the parent and surfaces session status
// (Happening now / Completed / Awaiting Approval).
import { LightningElement, api, track } from 'lwc';

const DOW = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

function startOfDay(d) {
    const x = new Date(d);
    x.setHours(0, 0, 0, 0);
    return x;
}
function sameDay(a, b) {
    return a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
function ymd(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}
function parseTime(t) {
    // Expect "HH:mm" or "HH:mm:ss.sssZ" style; tolerate either.
    if (!t || typeof t !== 'string') return null;
    const m = t.match(/^(\d{1,2}):(\d{2})/);
    if (!m) return null;
    return { h: Number(m[1]), m: Number(m[2]) };
}
function combine(dateIso, t) {
    if (!dateIso) return null;
    const d = new Date(dateIso + 'T00:00:00');
    if (isNaN(d.getTime())) return null;
    const parsed = parseTime(t);
    if (parsed) { d.setHours(parsed.h, parsed.m, 0, 0); }
    return d;
}
function safeImg(url) {
    if (!url || typeof url !== 'string') return null;
    if (/^https?:\/\//i.test(url) || url.charAt(0) === '/') return url;
    return null;
}
function initialOf(name) {
    if (!name || typeof name !== 'string') return '?';
    return name.trim().charAt(0).toUpperCase() || '?';
}

export default class KenMentorshipDashCalendarV2 extends LightningElement {
    @api sessions = [];
    @api monthLabel = '';

    @track selectedDate = new Date();
    @track viewMonth = new Date();

    connectedCallback() {
        this.selectedDate = startOfDay(new Date());
        this.viewMonth = new Date(this.selectedDate.getFullYear(), this.selectedDate.getMonth(), 1);
    }

    get headerLabel() {
        if (this.monthLabel) return this.monthLabel;
        return this.viewMonth.toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });
    }

    get dayHeaders() {
        return DOW.map((d, i) => ({ key: `dow-${i}`, label: d }));
    }

    // Set of YYYY-MM-DD strings that have at least one session.
    get sessionDays() {
        const set = new Set();
        (this.sessions || []).forEach(s => { if (s && s.dateIso) set.add(s.dateIso); });
        return set;
    }

    get calendarCells() {
        const view = this.viewMonth;
        const firstDay = new Date(view.getFullYear(), view.getMonth(), 1);
        const leading = firstDay.getDay();
        const daysInMonth = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();
        const today = startOfDay(new Date());
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const dayNum = i - leading + 1;
            if (i < leading || dayNum > daysInMonth) {
                cells.push({ key: `c-${i}`, label: '', cssClass: 'cal__cell cal__cell--empty', isEmpty: true, hasSession: false });
                continue;
            }
            const d = new Date(view.getFullYear(), view.getMonth(), dayNum);
            const isToday = sameDay(d, today);
            const isSelected = sameDay(d, this.selectedDate);
            const hasSession = this.sessionDays.has(ymd(d));
            let cls = 'cal__cell';
            if (isToday) cls += ' cal__cell--today';
            if (isSelected) cls += ' cal__cell--selected';
            if (hasSession) cls += ' cal__cell--has';
            cells.push({
                key: `c-${i}`,
                label: String(dayNum),
                cssClass: cls,
                isEmpty: false,
                hasSession,
                iso: ymd(d)
            });
        }
        return cells;
    }

    get selectedDateLabel() {
        return this.selectedDate.toLocaleDateString('en-IN', { weekday: 'long', day: '2-digit', month: 'short' });
    }

    get agendaItems() {
        const targetIso = ymd(this.selectedDate);
        const now = new Date();
        return (this.sessions || [])
            .filter(s => s && s.dateIso === targetIso)
            .map((s, i) => {
                const start = combine(s.dateIso, s.startTime);
                const end = combine(s.dateIso, s.endTime);
                const isHappening = start && end && now >= start && now <= end;
                const isPast = end && now > end;
                const status = (s.callRequestStatus || '').toLowerCase();
                const isAwaiting = status === 'requested' || status === 'pending' || status === 'awaiting approval';
                const img = safeImg(s.mentorImage);
                let badgeText = '';
                let badgeClass = '';
                let showFeedback = false;
                let showNow = false;
                if (isHappening) {
                    badgeText = 'Happening now!';
                    badgeClass = 'agenda__badge agenda__badge--now';
                    showNow = true;
                } else if (isPast) {
                    badgeText = 'Completed';
                    badgeClass = 'agenda__badge agenda__badge--completed';
                    showFeedback = true;
                } else if (isAwaiting) {
                    badgeText = 'Awaiting Approval';
                    badgeClass = 'agenda__badge agenda__badge--awaiting';
                } else {
                    badgeText = s.timeLabel || '';
                    badgeClass = 'agenda__badge agenda__badge--time';
                }
                return {
                    key: s.id || `a-${i}`,
                    id: s.id,
                    title: s.title || 'Mentorship Call',
                    mentor: s.mentor || '',
                    initial: initialOf(s.mentor),
                    avatarStyle: img
                        ? `background-image:url('${img.replace(/'/g, "\\'")}');background-size:cover;background-position:center;`
                        : `background:#67A1C8;color:#fff;`,
                    showInitial: !img,
                    timeLabel: s.timeLabel || '',
                    badgeText,
                    badgeClass,
                    showNow,
                    showFeedback
                };
            });
    }

    get hasAgenda() { return this.agendaItems.length > 0; }

    handleSchedule() {
        this.dispatchEvent(new CustomEvent('schedule'));
    }
    handleSelectDay(event) {
        const iso = event.currentTarget.dataset.iso;
        if (!iso) return;
        const d = new Date(iso + 'T00:00:00');
        if (isNaN(d.getTime())) return;
        this.selectedDate = d;
        this.dispatchEvent(new CustomEvent('datechange', { detail: { date: iso } }));
    }
    handlePrevMonth() {
        const v = this.viewMonth;
        this.viewMonth = new Date(v.getFullYear(), v.getMonth() - 1, 1);
    }
    handleNextMonth() {
        const v = this.viewMonth;
        this.viewMonth = new Date(v.getFullYear(), v.getMonth() + 1, 1);
    }
    handleLeaveFeedback(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('leavefeedback', { detail: { id } }));
    }
}