import { LightningElement, track } from 'lwc';

const LABELS = [
    'STEP 1 OF 4 — BASICS',
    'STEP 2 OF 4 — TARGET AUDIENCE',
    'STEP 3 OF 4 — STAGES & TIMELINE',
    'STEP 4 OF 4 — SUMMARY'
];

export default class KenJobPostWizardV2 extends LightningElement {
    @track currentStep = 0;
    @track postTitle = '';
    @track postCompany = '';
    @track postLocation = '';
    @track postSalary = '';
    @track postDescription = '';
    @track postAudience = 'all';
    @track postTimeline = '4 weeks';
    // QA Bug #116: surface a single inline error per step instead of silently advancing.
    @track stepError = '';

    get step1() { return this.currentStep === 0; }
    get step2() { return this.currentStep === 1; }
    get step3() { return this.currentStep === 2; }
    get step4() { return this.currentStep === 3; }
    get progressStyle() {
        const pct = ((this.currentStep + 1) / 4) * 100;
        return `width:${pct}%`;
    }
    get stepLabel() { return LABELS[this.currentStep]; }
    get nextLabel() { return this.currentStep === 3 ? 'Submit for Review' : 'Continue'; }
    get backDisabled() { return this.currentStep === 0; }
    // QA Bug #117: audience list now matches Figma — Role Type, Specific Individual,
    // Group, and Saved Audience were missing from the previous 3-option list.
    get audienceOptions() {
        const opts = [
            { id: 'all',        label: 'All Alumni',         desc: 'Visible to every alumnus on the network' },
            { id: 'roleType',   label: 'Role Type',          desc: 'Target by current job role (e.g. Engineer, PM)' },
            { id: 'individual', label: 'Specific Individual',desc: 'Send to one named alumnus' },
            { id: 'group',      label: 'Group',              desc: 'Limit to members of a specific alumni group' },
            { id: 'saved',      label: 'Saved Audience',     desc: 'Reuse one of your previously saved audiences' },
            { id: 'batch',      label: 'Specific Batches',   desc: 'Limit to chosen graduation years' },
            { id: 'program',    label: 'Specific Programs',  desc: 'Limit to chosen programs/departments' }
        ];
        return opts.map(o => ({ ...o, cls: o.id === this.postAudience ? 'opt-row opt-row--active' : 'opt-row' }));
    }
    get timelineOptions() {
        const opts = ['2 weeks', '4 weeks', '6 weeks', '8 weeks'];
        return opts.map(t => ({ id: t, label: t, cls: t === this.postTimeline ? 'pill-btn pill-btn--active' : 'pill-btn' }));
    }
    get postAudienceLabel() {
        const o = this.audienceOptions.find(x => x.id === this.postAudience);
        return o ? o.label : '';
    }

    handleField(event) {
        const f = event.target.dataset.field;
        this[f] = event.target.value;
        // Clear inline error as soon as the user starts typing again.
        if (this.stepError) this.stepError = '';
    }
    handleAudiencePick(event) {
        this.postAudience = event.currentTarget.dataset.id;
        if (this.stepError) this.stepError = '';
    }
    handleTimelinePick(event) {
        this.postTimeline = event.currentTarget.dataset.id;
        if (this.stepError) this.stepError = '';
    }

    handleBack() {
        // Back is always safe — clear any pending error and step back.
        this.stepError = '';
        if (this.currentStep > 0) this.currentStep -= 1;
    }
    handleNext() {
        // QA Bug #116: validate the current step before advancing.
        const err = this._validateStep(this.currentStep);
        if (err) {
            this.stepError = err;
            return;
        }
        this.stepError = '';
        if (this.currentStep < 3) this.currentStep += 1;
        else this.handleSubmit();
    }

    /**
     * Returns the first validation error for the given step, or '' if valid.
     * Centralised so step 4 (summary) can re-check everything before submit.
     */
    _validateStep(step) {
        const req = (v) => v != null && String(v).trim().length > 0;
        if (step === 0) {
            if (!req(this.postTitle))    return 'Please enter a job title.';
            if (!req(this.postCompany))  return 'Please enter the company name.';
            if (!req(this.postLocation)) return 'Please enter a job location.';
            return '';
        }
        if (step === 1) {
            if (!req(this.postAudience)) return 'Please pick a target audience.';
            return '';
        }
        if (step === 2) {
            if (!req(this.postTimeline))    return 'Please pick a hiring timeline.';
            if (!req(this.postDescription)) return 'Please add a short job description.';
            return '';
        }
        // step 3 (summary) — re-validate everything before submit
        return this._validateStep(0) || this._validateStep(1) || this._validateStep(2);
    }

    handleSubmit() {
        // Defensive: someone could click Submit-for-Review on summary with empty fields
        // if they jumped here via Back — re-check.
        const err = this._validateStep(3);
        if (err) {
            this.stepError = err;
            return;
        }
        const company = this.postCompany || '';
        const payload = {
            title: this.postTitle,
            company: company,
            logoInitial: company ? company.charAt(0).toUpperCase() : 'J',
            location: this.postLocation,
            salaryDisplay: this.postSalary,
            audience: this.postAudience,
            timeline: this.postTimeline,
            shortDescription: this.postDescription,
            fullDescription: this.postDescription
        };
        this.dispatchEvent(new CustomEvent('submit', { detail: { payload } }));
    }
    handleSaveDraft() {
        const detail = { title: this.postTitle, company: this.postCompany };
        this.dispatchEvent(new CustomEvent('savedraft', { detail }));
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
    stopBubble(e) { e.stopPropagation(); }
}