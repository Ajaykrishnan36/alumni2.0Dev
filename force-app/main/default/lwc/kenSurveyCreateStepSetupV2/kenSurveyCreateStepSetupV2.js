import { LightningElement, api } from 'lwc';

export default class KenSurveyCreateStepSetupV2 extends LightningElement {
    @api title = '';
    @api description = '';
    @api category = 'Engagement';
    @api typeValue = 'one-time';

    handleField(event) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: event.target.dataset.field, value: event.target.value }
        }));
    }
    handleType(event) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'typeValue', value: event.currentTarget.dataset.val }
        }));
    }
}