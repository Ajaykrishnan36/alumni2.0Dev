import { LightningElement, api } from 'lwc';

export default class KenJobCreateStepDescriptionV2 extends LightningElement {
    @api fullDescription = '';
    @api requirements = '';
    @api responsibilities = '';
    @api skills = [];
    @api skillDraft = '';
    @api experienceLevel = '';
    @api qualifications = '';
    @api descError = '';

    handleField(event) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: event.target.dataset.field, value: event.target.value }
        }));
    }
    handleSkillInput(event) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'skillDraft', value: event.target.value }
        }));
    }
    handleSkillKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.dispatchEvent(new CustomEvent('skilladd'));
        }
    }
    handleRemoveSkill(event) {
        this.dispatchEvent(new CustomEvent('skillremove', { detail: { skill: event.currentTarget.dataset.skill } }));
    }
}