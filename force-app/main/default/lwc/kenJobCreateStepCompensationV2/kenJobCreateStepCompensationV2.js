import { LightningElement, api } from 'lwc';

export default class KenJobCreateStepCompensationV2 extends LightningElement {
    @api salaryMin = '';
    @api salaryMax = '';
    @api currency = 'INR';
    @api benefitHealth = false;
    @api benefitRemote = false;
    @api benefitFlex = false;
    @api benefitStock = false;
    @api benefitLeave = false;
    @api benefitTraining = false;
    @api deadline = '';
    @api openings = 1;

    // Today's date (yyyy-mm-dd) for the deadline date input's `min` so the native
    // picker disallows past dates. JS-level guard lives in the wizard's validateStep.
    get todayStr() {
        const d = new Date();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        return `${d.getFullYear()}-${mm}-${dd}`;
    }

    handleField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field, value } }));
    }
}