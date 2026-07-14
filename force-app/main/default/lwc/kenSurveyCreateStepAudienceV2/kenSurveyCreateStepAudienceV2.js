import { LightningElement, api } from 'lwc';

const AUDIENCE_CHIPS = ['All Alumni', 'Batch of 2018', 'Batch of 2019', 'Mentors', 'Volunteers', 'Bangalore Chapter'];

export default class KenSurveyCreateStepAudienceV2 extends LightningElement {
    @api audience = [];
    @api startDate = '';
    @api endDate = '';
    @api anonymous = false;

    get audienceChips() {
        const sel = this.audience || [];
        return AUDIENCE_CHIPS.map(c => ({
            key: c,
            label: c,
            cls: sel.indexOf(c) >= 0 ? 'chip chip--on' : 'chip'
        }));
    }

    get toggleLabel() {
        return this.anonymous ? 'On' : 'Off';
    }
    get toggleLabelClass() {
        return this.anonymous ? 'toggle__on' : 'toggle__off';
    }

    handleToggleAudience(event) {
        this.dispatchEvent(new CustomEvent('toggleaudience', { detail: { value: event.currentTarget.dataset.val } }));
    }
    handleStart(event) {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'startDate', value: event.target.value } }));
    }
    handleEnd(event) {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'endDate', value: event.target.value } }));
    }
    handleToggleAnonymous() {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'anonymous', value: !this.anonymous } }));
    }
}