import { LightningElement, api } from 'lwc';

export default class KenOpportunityDetailModalV2 extends LightningElement {
    @api detail;

    get hasDetail() { return !!this.detail; }
    get hasUpdates() { return !!(this.detail && this.detail.hasUpdates); }
    get allocation() { return (this.detail && this.detail.allocation) || []; }
    get updates() { return (this.detail && this.detail.updates) || []; }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleDonate() { this.dispatchEvent(new CustomEvent('donate', { detail: { id: this.detail && this.detail.id } })); }
    handlePledge() { this.dispatchEvent(new CustomEvent('pledge', { detail: { id: this.detail && this.detail.id } })); }
    handleInKind() { this.dispatchEvent(new CustomEvent('inkind', { detail: { id: this.detail && this.detail.id } })); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
}