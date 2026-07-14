import { LightningElement, api } from 'lwc';

export default class KenJobApplyStepReviewV2 extends LightningElement {
    @api jobTitle = '';
    @api jobCompany = '';
    @api resumeName = '';
    @api coverLetter = '';
    @api applyNotes = '';

    get jobLine() {
        return `${this.jobTitle} — ${this.jobCompany}`;
    }
}