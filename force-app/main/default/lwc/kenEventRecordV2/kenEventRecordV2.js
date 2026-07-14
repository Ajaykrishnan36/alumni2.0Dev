import { LightningElement, api, track } from 'lwc';

/**
 * Event Record (details) view. About / Schedule sub-tabs + a daily accordion.
 * Action buttons are status-driven. Pure SLDS HTML — no lightning-* components.
 */
export default class KenEventRecordV2 extends LightningElement {
    @track _event = {};
    @track activeTab = 'about';
    @track expandedDay = '';

    @api
    get event() { return this._event; }
    set event(val) {
        this._event = val || {};
        // Open the first schedule day by default for an at-a-glance view.
        const sched = (val && val.schedule) || [];
        this.expandedDay = sched.length ? sched[0].id : '';
    }

    // ── tab flags ──
    get isAbout() { return this.activeTab === 'about'; }
    get isSchedule() { return this.activeTab === 'schedule'; }
    get aboutTabClass() { return this.activeTab === 'about' ? 'subtab subtab--active' : 'subtab'; }
    get scheduleTabClass() { return this.activeTab === 'schedule' ? 'subtab subtab--active' : 'subtab'; }

    // ── status flags ──
    get isUpcoming() { return this._event.statusKey === 'upcoming'; }
    get isCancelled() { return this._event.statusKey === 'cancelled'; }
    get isCompleted() { return this._event.statusKey === 'completed'; }

    get about() { return this._event.about || {}; }
    get hasMeals() { return !!(this.about.mealsIncluded && (this.about.meals || []).length); }
    get whatToExpect() { return this.about.whatToExpect || []; }

    // Decorate schedule for the accordion + session status pills.
    get scheduleDays() {
        return (this._event.schedule || []).map(d => ({
            ...d,
            isOpen: d.id === this.expandedDay,
            chevClass: d.id === this.expandedDay ? 'acc__chev acc__chev--open' : 'acc__chev',
            sessions: (d.sessions || []).map(s => ({
                ...s,
                pillClass: `sess-pill sess-pill--${s.statusKey}`
            }))
        }));
    }

    // Banner style — uploaded image overlays a brand gradient fallback.
    get bannerStyle() {
        const grad = 'linear-gradient(120deg,#1b2a6b 0%,#2a4bd0 60%,#3061FF 100%)';
        return this._event.image
            ? `background-image:linear-gradient(120deg,rgba(20,30,80,.55),rgba(20,30,80,.25)),url('${String(this._event.image).replace(/'/g, "\\'")}');background-size:cover;background-position:center;`
            : `background-image:${grad};`;
    }

    // ── handlers ──
    handleAbout() { this.activeTab = 'about'; }
    handleSchedule() { this.activeTab = 'schedule'; }
    toggleDay(event) {
        const id = event.currentTarget.dataset.id;
        this.expandedDay = this.expandedDay === id ? '' : id;
    }

    handleBack() { this.dispatchEvent(new CustomEvent('back', { bubbles: true, composed: true })); }
    handleJoin() {
        this.dispatchEvent(new CustomEvent('join', { detail: { id: this._event.id, title: this._event.title }, bubbles: true, composed: true }));
    }
    handleViewSummary() {
        this.dispatchEvent(new CustomEvent('viewsummary', { detail: { id: this._event.id, title: this._event.title }, bubbles: true, composed: true }));
    }
    handleFeedback() {
        this.dispatchEvent(new CustomEvent('submitfeedback', { detail: { id: this._event.id, title: this._event.title }, bubbles: true, composed: true }));
    }
    handleBrochure() {
        this.dispatchEvent(new CustomEvent('notify', { detail: { message: 'Downloading brochure…' }, bubbles: true, composed: true }));
    }
}