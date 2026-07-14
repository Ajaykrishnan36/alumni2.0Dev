import { LightningElement, api } from 'lwc';

export default class KenJobCreateStepIdentityV2 extends LightningElement {
    @api jobId = '';
    @api jobTitle = '';
    @api employer = '';
    @api location = '';
    @api placementCycle = '';
    @api postedBy = '';
    @api statusField = '';
    @api shortDescription = '';

    handleField(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field, value } }));
    }
}