import { LightningElement, api } from 'lwc';

export default class KenSurveyDetailModalV2 extends LightningElement {
    @api survey = {};

    get title() { return this.survey.title; }
    get desc() { return this.survey.desc; }
    get questionsCount() { return this.survey.questionsCount; }
    get minutes() { return this.survey.minutes; }
    get audience() { return this.survey.audience; }
    get responsesCount() { return this.survey.responsesCount; }
    get pillLabel() {
        const s = this.survey.status;
        if (s === 'approved') return 'Approved';
        if (s === 'in-review') return 'In Review';
        if (s === 'rejected') return 'Rejected';
        return s || '';
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleStart() { this.dispatchEvent(new CustomEvent('start', { detail: { id: this.survey.id } })); }
    // QA Bug #119: bubble Edit + View Details to parent kenSurveysV2.
    handleEdit() { this.dispatchEvent(new CustomEvent('edit', { detail: { id: this.survey.id } })); }
    handleViewDetails() { this.dispatchEvent(new CustomEvent('viewdetails', { detail: { id: this.survey.id } })); }
    handleBackdrop(event) {
        if (event.target === event.currentTarget) this.handleClose();
    }
    handleStop(event) { event.stopPropagation(); }
}