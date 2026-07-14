import { LightningElement, api, track } from 'lwc';

/**
 * Registered Events — List view.
 * Three tabs (Upcoming / Cancelled / Completed) + search. Pure SLDS HTML.
 * Cards expose status-specific actions and bubble events to the manager.
 */
const TABS = [
    { key: 'upcoming', label: 'Upcoming' },
    { key: 'cancelled', label: 'Cancelled' },
    { key: 'completed', label: 'Completed' }
];

export default class KenRegisteredEventsListV2 extends LightningElement {
    @api events = [];

    @track activeTab = 'upcoming';
    @track searchTerm = '';

    get tabs() {
        return TABS.map(t => ({
            ...t,
            cssClass: t.key === this.activeTab ? 'tab tab--active' : 'tab'
        }));
    }

    get _term() { return (this.searchTerm || '').trim().toLowerCase(); }

    _matches(e) {
        const t = this._term;
        if (!t) return true;
        return [e.title, e.location, e.format, e.dateLabel]
            .some(f => String(f == null ? '' : f).toLowerCase().includes(t));
    }

    // Decorate each event for the active tab with view-state flags the template
    // can switch on without extra logic.
    get visibleEvents() {
        return (this.events || [])
            .filter(e => e.statusKey === this.activeTab && this._matches(e))
            .map(e => ({
                ...e,
                isUpcoming: e.statusKey === 'upcoming',
                isCancelled: e.statusKey === 'cancelled',
                isCompleted: e.statusKey === 'completed',
                metaLine: `${e.dateLabel}  •  ${e.location || e.format}`
            }));
    }

    get hasEvents() { return this.visibleEvents.length > 0; }

    get emptyText() {
        if (this.activeTab === 'upcoming') return 'You have no upcoming registered events.';
        if (this.activeTab === 'cancelled') return 'No cancelled registrations.';
        return 'You have not completed any events yet.';
    }

    // ── handlers ──
    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.key;
    }
    handleSearch(event) {
        this.searchTerm = (event.target && event.target.value) || '';
    }

    handleViewDetails(event) {
        const id = event.currentTarget.dataset.id;
        const ev = this.events.find(e => e.id === id);
        this.dispatchEvent(new CustomEvent('viewdetails', { detail: { id, title: ev && ev.title }, bubbles: true, composed: true }));
    }
    handleJoin(event) {
        const id = event.currentTarget.dataset.id;
        const ev = this.events.find(e => e.id === id);
        this.dispatchEvent(new CustomEvent('join', { detail: { id, title: ev && ev.title }, bubbles: true, composed: true }));
    }
    handleFeedback(event) {
        const id = event.currentTarget.dataset.id;
        const ev = this.events.find(e => e.id === id);
        this.dispatchEvent(new CustomEvent('submitfeedback', { detail: { id, title: ev && ev.title }, bubbles: true, composed: true }));
    }
}