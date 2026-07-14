import { LightningElement, api, track } from 'lwc';

const STEPS = [
    { id: 'basic', label: 'Basic profile' },
    { id: 'education', label: 'Education' },
    { id: 'employment', label: 'Employment and Career Information' },
    { id: 'engagement', label: 'Engagement & Contributions' }
];

const ENGAGEMENT_OPTIONS = [
    { id: 'learn',     label: 'Learn from fellow alumni' },
    { id: 'reconnect', label: 'Reconnect with my friends' },
    { id: 'giveback',  label: 'Give back to the community' },
    { id: 'hiring',    label: 'Interested in hiring new talent' },
    { id: 'newjob',    label: 'Looking to find a new job' },
    { id: 'grow',      label: 'Grow my professional network' }
];

export default class KenOnboardingV2 extends LightningElement {
    @api userFirstName = '';
    @api userLastName = '';
    @api userEmail = '';
    @api institutionLogoUrl = '';

    @track currentStepIndex = 0;

    @track basic = {
        firstName: '',
        lastName: '',
        email: '',
        countryCode: '+91',
        phone: '',
        linkedin: '',
        twitter: ''
    };

    @track educationItems = [];

    @track employmentItems = [];

    @track engagement = ENGAGEMENT_OPTIONS.map((opt) => ({ ...opt, selected: false }));

    get currentStepId() { return STEPS[this.currentStepIndex].id; }
    get isBasic() { return this.currentStepId === 'basic'; }
    get isEducation() { return this.currentStepId === 'education'; }
    get isEmployment() { return this.currentStepId === 'employment'; }
    get isEngagement() { return this.currentStepId === 'engagement'; }
    get isFirstStep() { return this.currentStepIndex === 0; }
    get isLastStep() { return this.currentStepIndex === STEPS.length - 1; }
    get hasEducation() { return this.educationItems.length > 0; }
    get hasEmployment() { return this.employmentItems.length > 0; }

    get userInitial() { return (this.basic.firstName || ' ').charAt(0).toUpperCase(); }
    get userFullName() { return `${this.basic.firstName} ${this.basic.lastName}`.trim(); }
    get engagementItems() {
        return this.engagement.map((opt) => ({
            ...opt,
            cardClass: opt.selected ? 'eng-card eng-card--selected' : 'eng-card',
            checkClass: opt.selected ? 'eng-card__check eng-card__check--on' : 'eng-card__check'
        }));
    }

    get steps() {
        return STEPS.map((s, i) => ({
            ...s,
            number: i + 1,
            isActive: i === this.currentStepIndex,
            isComplete: i < this.currentStepIndex,
            isPending: i > this.currentStepIndex,
            stepClass: i < this.currentStepIndex
                ? 'step step--complete'
                : i === this.currentStepIndex
                    ? 'step step--active'
                    : 'step step--pending'
        }));
    }

    get nextLabel() { return this.isLastStep ? 'Finish' : (this.isBasic ? 'Continue' : 'Save & Next'); }
    get showCancel() { return this.isBasic; }

    handleBasicInput(event) {
        const field = event.target.dataset.field;
        if (field) this.basic = { ...this.basic, [field]: event.target.value };
    }

    handleEditEducation(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.dispatchEvent(new CustomEvent('editeducation', { detail: { id } }));
    }
    handleDeleteEducation(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.educationItems = this.educationItems.filter((it) => it.id !== id);
    }
    handleAddEducation() {
        this.dispatchEvent(new CustomEvent('addeducation'));
    }

    handleAddEmployment() {
        this.dispatchEvent(new CustomEvent('addemployment'));
    }

    toggleEngagement(event) {
        const id = event.currentTarget.dataset.id;
        this.engagement = this.engagement.map((opt) =>
            opt.id === id ? { ...opt, selected: !opt.selected } : opt
        );
    }

    handleSkip() {
        if (this.isLastStep) this._fireFinish();
        else this.currentStepIndex += 1;
    }
    handlePrevious() {
        if (!this.isFirstStep) this.currentStepIndex -= 1;
    }
    handleNext() {
        if (this.isLastStep) {
            this._fireFinish();
            return;
        }
        this.dispatchEvent(new CustomEvent('stepcomplete', {
            detail: { step: this.currentStepId, data: this._snapshot() }
        }));
        this.currentStepIndex += 1;
    }
    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
    handleLogout() {
        this.dispatchEvent(new CustomEvent('logout'));
    }

    _fireFinish() {
        this.dispatchEvent(new CustomEvent('finish', { detail: this._snapshot() }));
    }
    _snapshot() {
        return {
            basic: { ...this.basic },
            educationItems: [...this.educationItems],
            employmentItems: [...this.employmentItems],
            engagement: this.engagement.filter((e) => e.selected).map((e) => e.id)
        };
    }
}