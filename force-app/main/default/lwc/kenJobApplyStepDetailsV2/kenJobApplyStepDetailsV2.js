import { LightningElement, api } from 'lwc';

export default class KenJobApplyStepDetailsV2 extends LightningElement {
    @api coverLetter = '';
    @api applyNotes = '';

    handleCoverLetter(event) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'coverLetter', value: event.target.value }
        }));
    }
    handleNotes(event) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'applyNotes', value: event.target.value }
        }));
    }
}