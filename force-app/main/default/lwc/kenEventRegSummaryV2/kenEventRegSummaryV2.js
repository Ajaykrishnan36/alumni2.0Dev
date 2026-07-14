import { LightningElement, api, track } from 'lwc';

/**
 * Registration Summary view. Participant table + sessions/payment right rail,
 * plus the two-step cancellation modal flow. Pure SLDS HTML.
 */
export default class KenEventRegSummaryV2 extends LightningElement {
    @track _event = {};

    // Modal flow: '' → 'warn' (bulk-booking warning) → 'select' (pick sessions).
    @track modalStage = '';
    @track cancelAll = false;
    @track cancelItems = [];

    @api
    get event() { return this._event; }
    set event(val) {
        this._event = val || {};
        this._buildCancelItems(val);
    }

    _buildCancelItems(val) {
        const sessions = (val && val.sessions) || [];
        const items = sessions.map(s => ({
            id: s.id,
            label: s.title,
            sub: s.dayLabel,
            price: s.price,
            checked: false
        }));
        // Meals line, when the event includes meals.
        if (val && val.about && val.about.mealsIncluded) {
            items.push({ id: 'meals', label: 'Meals', sub: 'One breakfast and fifty other', price: '₹100', checked: false });
        }
        this.cancelItems = items;
    }

    // ── participant table decoration ──
    get participants() {
        return (this._event.participantsList || []).map(p => ({
            ...p,
            typePillClass: `type-pill type-pill--${p.typeKey}`,
            mealsToggleClass: p.meals ? 'toggle toggle--on' : 'toggle',
            surveyIsFill: p.survey === 'Fill',
            surveyIsDone: p.survey === 'Completed',
            surveyIsNa: p.survey === 'N/A'
        }));
    }

    get sessions() { return this._event.sessions || []; }
    get payment() { return this._event.payment || {}; }
    get isCancelled() { return this._event.statusKey === 'cancelled'; }

    // ── modal state ──
    get isWarn() { return this.modalStage === 'warn'; }
    get isSelect() { return this.modalStage === 'select'; }
    get hasModal() { return !!this.modalStage; }

    get selectItems() {
        return this.cancelItems.map(i => ({
            ...i,
            checked: this.cancelAll ? true : i.checked
        }));
    }
    get cancelDisabled() {
        return !this.cancelAll && !this.cancelItems.some(i => i.checked);
    }

    // ── handlers ──
    handleBack() { this.dispatchEvent(new CustomEvent('back', { bubbles: true, composed: true })); }

    openCancel() { this.modalStage = 'warn'; }
    closeModal() { this.modalStage = ''; this.cancelAll = false; this.cancelItems = this.cancelItems.map(i => ({ ...i, checked: false })); }
    confirmWarn() { this.modalStage = 'select'; }

    toggleAll(event) {
        this.cancelAll = event.target.checked;
    }
    toggleItem(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.cancelItems = this.cancelItems.map(i => i.id === id ? { ...i, checked } : i);
        if (!checked) this.cancelAll = false;
    }

    doCancel() {
        this.modalStage = '';
        this.dispatchEvent(new CustomEvent('cancelled', {
            detail: { id: this._event.id, message: 'Your cancellation request has been submitted.' },
            bubbles: true, composed: true
        }));
    }

    notify(message) {
        this.dispatchEvent(new CustomEvent('notify', { detail: { message }, bubbles: true, composed: true }));
    }
    handleInvoice() { this.notify('Downloading invoice…'); }
    handleShare() { this.notify('Share link copied.'); }
    handleSurvey() { this.notify('Opening custom survey…'); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) this.closeModal();
    }
    stop(event) { event.stopPropagation(); }
}