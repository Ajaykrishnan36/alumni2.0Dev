import { LightningElement, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import processVerifiedLeadV2 from '@salesforce/apex/KenAlumniOnboardingService.processVerifiedLeadV2';
import saveOnboardingV2 from '@salesforce/apex/KenAlumniOnboardingService.saveOnboardingV2';

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

export default class KenAlumniOnboardingV2 extends LightningElement {
    @track currentStepIndex = 0;
    @track isLoading = true;
    @track loadError = '';
    @track isSaving = false;

    token = '';
    accountId = '';
    roleId = '';

    @track basic = {
        firstName: '', lastName: '', email: '',
        countryCode: '+91', phone: '', linkedin: '', twitter: ''
    };
    @track educationItems = [];
    @track employmentItems = [];
    @track engagement = ENGAGEMENT_OPTIONS.map(o => ({ ...o, selected: false }));

    // ----- inline add/edit modals -----
    @track showEducationModal = false;
    @track showEmploymentModal = false;
    @track eduDraft = { id: null, degree: '', school: '', period: '', score: '' };
    @track empDraft = { id: null, title: '', company: '', period: '', location: '' };
    _seq = 1;

    connectedCallback() {
        let token = '';
        try {
            token = new URLSearchParams(window.location.search).get('token') || '';
        } catch (e) { /* ignore */ }
        this.token = token;
        if (!token) {
            this.loadError = 'This onboarding link is invalid or has expired. Please use the link from your approval email.';
            this.isLoading = false;
            return;
        }
        processVerifiedLeadV2({ token })
            .then(ctx => {
                if (ctx) {
                    this.accountId = ctx.accountId;
                    this.roleId = ctx.roleId;
                    this.basic = {
                        ...this.basic,
                        firstName: ctx.firstName || '',
                        lastName: ctx.lastName || '',
                        email: ctx.email || ''
                    };
                }
                this.isLoading = false;
            })
            .catch(err => {
                this.loadError = this._msg(err) || 'We could not verify your onboarding link.';
                this.isLoading = false;
            });
    }

    // ----- stepper / derived -----
    get currentStepId() { return STEPS[this.currentStepIndex].id; }
    get isBasic()      { return this.currentStepId === 'basic'; }
    get isEducation()  { return this.currentStepId === 'education'; }
    get isEmployment() { return this.currentStepId === 'employment'; }
    get isEngagement() { return this.currentStepId === 'engagement'; }
    get isFirstStep()  { return this.currentStepIndex === 0; }
    get isLastStep()   { return this.currentStepIndex === STEPS.length - 1; }
    get hasEducation() { return this.educationItems.length > 0; }
    get hasEmployment(){ return this.employmentItems.length > 0; }
    get userInitial()  { return (this.basic.firstName || ' ').charAt(0).toUpperCase(); }
    get userFullName() { return `${this.basic.firstName} ${this.basic.lastName}`.trim(); }
    get nextLabel()    { return this.isLastStep ? 'Finish' : (this.isBasic ? 'Continue' : 'Save & Next'); }
    get showCancel()   { return this.isBasic; }

    get steps() {
        return STEPS.map((s, i) => ({
            ...s,
            number: i + 1,
            isComplete: i < this.currentStepIndex,
            isActive: i === this.currentStepIndex,
            stepClass: i < this.currentStepIndex ? 'step step--complete'
                : i === this.currentStepIndex ? 'step step--active' : 'step step--pending'
        }));
    }
    get engagementItems() {
        return this.engagement.map(o => ({
            ...o,
            cardClass: o.selected ? 'eng-card eng-card--selected' : 'eng-card',
            checkClass: o.selected ? 'eng-card__check eng-card__check--on' : 'eng-card__check'
        }));
    }

    // ----- basic -----
    handleBasicInput(event) {
        const f = event.target.dataset.field;
        if (f) this.basic = { ...this.basic, [f]: event.target.value };
    }

    // ----- education modal -----
    handleAddEducation() {
        this.eduDraft = { id: null, degree: '', school: '', period: '', score: '' };
        this.showEducationModal = true;
    }
    handleEditEducation(event) {
        const id = Number(event.currentTarget.dataset.id);
        const found = this.educationItems.find(it => it.id === id);
        if (found) { this.eduDraft = { ...found }; this.showEducationModal = true; }
    }
    handleDeleteEducation(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.educationItems = this.educationItems.filter(it => it.id !== id);
    }
    handleEduDraft(event) {
        const f = event.target.dataset.field;
        if (f) this.eduDraft = { ...this.eduDraft, [f]: event.target.value };
    }
    handleSaveEducation() {
        const d = this.eduDraft;
        if (!(d.degree || '').trim()) return;
        if (d.id) {
            this.educationItems = this.educationItems.map(it => it.id === d.id ? { ...d } : it);
        } else {
            this.educationItems = [...this.educationItems, { ...d, id: this._seq++ }];
        }
        this.showEducationModal = false;
    }
    handleCloseEducation() { this.showEducationModal = false; }

    // ----- employment modal -----
    handleAddEmployment() {
        this.empDraft = { id: null, title: '', company: '', period: '', location: '' };
        this.showEmploymentModal = true;
    }
    handleEditEmployment(event) {
        const id = Number(event.currentTarget.dataset.id);
        const found = this.employmentItems.find(it => it.id === id);
        if (found) { this.empDraft = { ...found }; this.showEmploymentModal = true; }
    }
    handleDeleteEmployment(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.employmentItems = this.employmentItems.filter(it => it.id !== id);
    }
    handleEmpDraft(event) {
        const f = event.target.dataset.field;
        if (f) this.empDraft = { ...this.empDraft, [f]: event.target.value };
    }
    handleSaveEmployment() {
        const d = this.empDraft;
        if (!(d.title || '').trim()) return;
        if (d.id) {
            this.employmentItems = this.employmentItems.map(it => it.id === d.id ? { ...d } : it);
        } else {
            this.employmentItems = [...this.employmentItems, { ...d, id: this._seq++ }];
        }
        this.showEmploymentModal = false;
    }
    handleCloseEmployment() { this.showEmploymentModal = false; }

    // Keep clicks inside a modal from bubbling to the backdrop (which closes it).
    handleModalStop(event) { event.stopPropagation(); }

    // ----- engagement -----
    toggleEngagement(event) {
        const id = event.currentTarget.dataset.id;
        this.engagement = this.engagement.map(o => o.id === id ? { ...o, selected: !o.selected } : o);
    }

    // ----- navigation -----
    handleSkip() {
        if (this.isLastStep) this._finish();
        else this.currentStepIndex += 1;
    }
    handlePrevious() { if (!this.isFirstStep) this.currentStepIndex -= 1; }
    handleNext() {
        if (this.isLastStep) { this._finish(); return; }
        this.currentStepIndex += 1;
    }
    handleCancel() { this._goLogin(); }
    handleLogout() { this._goLogin(); }

    _finish() {
        if (this.isSaving) return;
        this.isSaving = true;
        const payload = {
            basic: { ...this.basic },
            educationItems: [...this.educationItems],
            employmentItems: [...this.employmentItems],
            engagement: this.engagement.filter(e => e.selected).map(e => e.id)
        };
        saveOnboardingV2({ token: this.token, payloadJson: JSON.stringify(payload) })
            .then(() => {
                // Onboarding done — the temp-password email is on its way. Send the
                // user to login; their first login is then forced to the branded
                // Change Password page (Temp_Password_Reset_Completed__c = false).
                this._goLogin();
            })
            .catch(err => {
                this.loadError = this._msg(err) || 'We could not save your details. Please try again.';
                this.isSaving = false;
            });
    }

    _goHome()  { try { window.location.assign(basePath + '/home'); } catch (e) { /* ignore */ } }
    _goLogin() { try { window.location.assign(basePath + '/login'); } catch (e) { /* ignore */ } }
    _msg(err) {
        return (err && err.body && err.body.message) || (err && err.message) || '';
    }
}