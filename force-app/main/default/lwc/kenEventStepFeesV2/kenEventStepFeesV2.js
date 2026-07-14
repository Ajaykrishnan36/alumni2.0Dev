import { LightningElement, api } from 'lwc';

export default class KenEventStepFeesV2 extends LightningElement {
    @api feeType = 'Free';
    @api currency = 'INR (₹)';
    @api baseFee = '';

    get isPaidEvent() {
        return this.feeType && this.feeType !== 'Free';
    }

    handleInput(event) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: event.currentTarget.dataset.field, value: event.target.value }
        }));
    }
}