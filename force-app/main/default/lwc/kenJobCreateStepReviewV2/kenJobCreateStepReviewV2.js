import { LightningElement, api } from 'lwc';

export default class KenJobCreateStepReviewV2 extends LightningElement {
    @api jobId = '';
    @api jobTitle = '';
    @api employer = '';
    @api placementCycle = '';
    @api postedBy = '';
    @api statusField = '';
    @api description = '';
    @api experienceLevel = '';
    @api qualifications = '';
    @api skills = [];
    @api salary = '';
    @api deadline = '';
    @api openings = 0;
    @api benefits = '';
    @api audienceSummary = '';
    @api stage = '';

    handleEdit(event) {
        const step = parseInt(event.currentTarget.dataset.step, 10);
        this.dispatchEvent(new CustomEvent('editstep', { detail: { step } }));
    }
}