import { LightningElement, api, track } from 'lwc';

const STEPS = [
    { id: 1, label: 'Resume' },
    { id: 2, label: 'Cover Letter' },
    { id: 3, label: 'Review' }
];

const STEP_LABELS = ['STEP 1 OF 3 — RESUME', 'STEP 2 OF 3 — COVER LETTER', 'STEP 3 OF 3 — REVIEW'];

export default class KenJobApplyWizardV2 extends LightningElement {
    @api jobId;
    @api jobTitle = '';
    @api jobCompany = '';

    @track currentStep = 1;
    @track selectedResumeId = '';
    @track selectedResumeName = '';
    @track selectedResumeUrl = '';
    @track selectedResumeContentVersionId = '';
    @track coverLetter = '';
    @track applyNotes = '';

    get steps() { return STEPS; }
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get stepLabel() { return STEP_LABELS[this.currentStep - 1]; }
    get nextLabel() { return this.currentStep === 3 ? 'Submit Application' : 'Continue'; }
    get backDisabled() { return this.currentStep === 1; }
    // Can't continue past the Resume step without a chosen library resume.
    get nextDisabled() { return this.currentStep === 1 && !this.selectedResumeId; }

    handleValueChange(event) {
        const { field, value } = event.detail || {};
        if (!field) return;
        this[field] = value;
    }

    handleBack() { if (this.currentStep > 1) this.currentStep -= 1; }
    handleNext() {
        if (this.nextDisabled) return;
        if (this.currentStep < 3) this.currentStep += 1;
        else this.handleSubmit();
    }
    handleSubmit() {
        this.dispatchEvent(new CustomEvent('submit', {
            detail: {
                jobId: this.jobId,
                resumeId: this.selectedResumeId,
                resumeName: this.selectedResumeName,
                resumeUrl: this.selectedResumeUrl,
                resumeContentVersionId: this.selectedResumeContentVersionId,
                coverLetter: this.coverLetter,
                notes: this.applyNotes
            }
        }));
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
    stopBubble(e) { e.stopPropagation(); }
}