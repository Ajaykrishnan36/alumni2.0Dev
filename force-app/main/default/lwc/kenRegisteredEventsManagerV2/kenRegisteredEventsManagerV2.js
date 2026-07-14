import { LightningElement, track } from 'lwc';
import getMyRegisteredEvents from '@salesforce/apex/KenPortalEventController.getMyRegisteredEvents';

/**
 * Registered Events — master wrapper / state machine.
 *
 * Owns the end-to-end navigation between the four registered-event views and
 * holds the selected record. Children are 100% pure-SLDS HTML (no lightning-*),
 * and communicate UP via bubbling CustomEvents:
 *   onviewdetails   → open Event Record (details)
 *   onviewsummary   → open Registration Summary
 *   onsubmitfeedback→ open Feedback / Survey
 *   onjoin          → "Join event" CTA (toast for now)
 *   onnotify        → child asks parent to surface a toast
 *   onback          → contextual back (history-stack driven)
 *
 * A small history stack makes "Back" return to wherever the user came from
 * (e.g. Summary opened from Details returns to Details; Feedback opened from the
 * list returns to the list).
 *
 * Data: the list is wired to REAL registrations via
 * KenPortalEventController.getMyRegisteredEvents() (imperative call in
 * connectedCallback). The previous hardcoded MOCK_EVENTS array was removed.
 */
const VIEW = { LIST: 'list', DETAILS: 'details', SUMMARY: 'summary', SURVEY: 'survey' };

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// "2026-07-15" -> "15 Jul, 2026"; multi-day -> "11 - 12 Oct, 2025"
const fmtDateRange = (startIso, endIso) => {
    const s = startIso ? new Date(startIso) : null;
    const e = endIso ? new Date(endIso) : null;
    const valid = (d) => d && !isNaN(d.getTime());
    if (!valid(s) && !valid(e)) return '';
    const one = (d) => `${d.getDate()} ${MONTHS[d.getMonth()]}, ${d.getFullYear()}`;
    if (valid(s) && valid(e) && s.getTime() !== e.getTime()) {
        if (s.getMonth() === e.getMonth() && s.getFullYear() === e.getFullYear()) {
            return `${s.getDate()} - ${e.getDate()} ${MONTHS[s.getMonth()]}, ${s.getFullYear()}`;
        }
        return `${one(s)} - ${one(e)}`;
    }
    return one(valid(s) ? s : e);
};

const inr = (n) => {
    const v = Number(n);
    if (!v || isNaN(v) || v <= 0) return 'Free';
    return `₹${v.toLocaleString('en-IN')}`;
};

export default class KenRegisteredEventsManagerV2 extends LightningElement {
    @track currentView = VIEW.LIST;
    @track selectedEvent = null;

    @track events = [];
    @track isLoading = true;
    _history = [];

    // Toast
    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer = null;

    connectedCallback() {
        this.loadRegisteredEvents();
    }

    loadRegisteredEvents() {
        this.isLoading = true;
        getMyRegisteredEvents()
            .then(rows => {
                this.events = Array.isArray(rows) ? rows.map(r => this._mapEvent(r)) : [];
                this.isLoading = false;
            })
            .catch(err => {
                this.events = [];
                this.isLoading = false;
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.getMyRegisteredEvents error', err);
            });
    }

    // RegisteredEventWrapper → the shape the list / record / summary children consume.
    _mapEvent(r) {
        const statusKey = r.statusKey || 'upcoming';
        const isOnline = (r.hostType || '') === 'Online';
        const format = r.hostType || (isOnline ? 'Online' : 'Offline');
        const dateLabel = fmtDateRange(r.startDate, r.endDate);
        const cancelledLabel = statusKey === 'cancelled'
            ? `Cancelled${dateLabel ? ' · ' + dateLabel : ''}`
            : '';
        let statusLabel = '';
        if (statusKey === 'cancelled') statusLabel = cancelledLabel || 'Cancelled';
        else if (statusKey === 'completed') statusLabel = 'Completed';
        return {
            id: r.id,
            statusKey,
            statusLabel,
            happening: false,
            title: r.title || '',
            image: r.imageUrl || '',
            badge: r.categories || 'Event',
            dateLabel,
            format,
            formatLong: format,
            location: r.location || (isOnline ? 'Online' : ''),
            participants: Number(r.participantsCount) || 0,
            amountPaid: inr(r.amountPaid),
            language: '',
            capacity: r.participantsCount ? `${r.participantsCount} Seats` : '',
            cancelledLabel,
            // Rich detail/summary fields aren't returned by the list query — provide
            // safe empty defaults so the record/summary views render without errors.
            about: {
                description: r.description || '',
                whatToExpect: [],
                mealsIncluded: false,
                meals: []
            },
            schedule: [],
            participantsList: [],
            sessions: [],
            payment: { sessionFee: '', totalLabel: '', totalPayable: inr(r.amountPaid) }
        };
    }

    // ── view flags ──
    get isList() { return this.currentView === VIEW.LIST; }
    get isDetails() { return this.currentView === VIEW.DETAILS; }
    get isSummary() { return this.currentView === VIEW.SUMMARY; }
    get isSurvey() { return this.currentView === VIEW.SURVEY; }

    _findEvent(id) {
        return this.events.find(e => e.id === id) || null;
    }
    _go(view, evt) {
        if (evt) this.selectedEvent = this._findEvent(evt.id) || evt;
        this._history.push(this.currentView);
        this.currentView = view;
    }

    // ── navigation handlers (bubbled from children) ──
    handleViewDetails(event) { this._go(VIEW.DETAILS, event.detail); }
    handleViewSummary(event) { this._go(VIEW.SUMMARY, event.detail); }
    handleSubmitFeedback(event) { this._go(VIEW.SURVEY, event.detail); }

    handleJoin(event) {
        const t = (event.detail && event.detail.title) || 'event';
        this._showToast(`Opening "${t}" — connecting you to the live session…`);
    }

    handleBack() {
        const prev = this._history.pop() || VIEW.LIST;
        this.currentView = prev;
        if (prev === VIEW.LIST) this.selectedEvent = null;
    }

    handleNotify(event) {
        this._showToast((event.detail && event.detail.message) || '');
    }

    // After a successful cancellation, drop back to the list and toast.
    handleCancelled(event) {
        this._showToast((event.detail && event.detail.message) || 'Registration cancelled.');
        this._history = [];
        this.currentView = VIEW.LIST;
        this.selectedEvent = null;
        // Refresh so the cancelled event moves to the Cancelled tab.
        this.loadRegisteredEvents();
    }

    _showToast(msg) {
        if (!msg) return;
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2600);
    }

    disconnectedCallback() {
        if (this._toastTimer) clearTimeout(this._toastTimer);
    }
}