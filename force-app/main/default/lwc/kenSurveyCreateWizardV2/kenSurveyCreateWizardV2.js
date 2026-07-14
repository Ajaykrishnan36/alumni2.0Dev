// Inline create-survey wizard (no modal backdrop). 4 steps:
//   1) About Survey   2) Target Audience   3) Setup Survey (questions)   4) Summary
import { LightningElement, api, track } from 'lwc';

const STEPS = [
    { id: 1, label: 'About Survey' },
    { id: 2, label: 'Target Audience' },
    { id: 3, label: 'Setup Survey' },
    { id: 4, label: 'Summary' }
];

const QTYPES = [
    { value: 'radio', label: 'Single Choice (Radio)' },
    { value: 'checkbox', label: 'Multiple Choice (Checkbox)' },
    { value: 'linear', label: 'Linear Scale (Likert 1-5)' },
    { value: 'short', label: 'Short Text' },
    { value: 'yesno', label: 'Yes / No' }
];

export default class KenSurveyCreateWizardV2 extends LightningElement {
    // When the parent opens this wizard in EDIT mode it passes the survey's existing
    // values (from KenSurveyController.getSurveyForEdit → .data). Setting `seed` prefills
    // every step so the user edits in place; null/undefined leaves the create defaults.
    _seed;
    @api
    get seed() { return this._seed; }
    set seed(value) {
        this._seed = value;
        if (value && typeof value === 'object') {
            this._applySeed(value);
        }
    }

    _applySeed(s) {
        this.title = s.title || '';
        this.description = s.description || s.desc || '';
        this.startDate = s.startDate || '';
        this.endDate = s.endDate || '';
        const mapType = (t) => {
            const v = (t || '').toLowerCase();
            if (v === 'multiple' || v === 'radio' || v === 'single') return 'radio';
            if (v === 'checkbox' || v === 'multi') return 'checkbox';
            if (v === 'linear' || v === 'scale' || v === 'rating') return 'linear';
            if (v === 'yesno' || v === 'yes/no') return 'yesno';
            return 'short';
        };
        const qs = Array.isArray(s.questions) ? s.questions : [];
        if (qs.length) {
            this.questions = qs.map((q, i) => ({
                id: `eq${i}_${Date.now()}`,
                type: mapType(q.type),
                text: q.text || '',
                opts: Array.isArray(q.options)
                    ? q.options.map(o => (o && o.text != null ? o.text : o))
                    : (Array.isArray(q.opts) ? [...q.opts] : ['Option 1', 'Option 2']),
                required: q.required === true,
                scaleMin: q.scaleMin != null ? q.scaleMin : 1,
                scaleMax: q.scaleMax != null ? q.scaleMax : 5,
                scaleMinLabel: q.scaleMinLabel || '',
                scaleMaxLabel: q.scaleMaxLabel || ''
            }));
        }
    }

    @track currentStep = 1;
    @track title = '';
    @track description = '';
    @track category = 'Engagement';
    @track startDate = '';
    @track endDate = '';
    @track anonymousAllowed = false;
    @track estimatedResponses = 100;

    // Master state captured live from the canonical kenEventStepDetailsV2 builder via valuechange.
    @track audienceData = null;
    @track stepError = '';

    @track questions = [
        { id: 'cq1', type: 'radio', text: '', opts: ['Option 1', 'Option 2'], required: false,
          scaleMin: 1, scaleMax: 5, scaleMinLabel: '', scaleMaxLabel: '' }
    ];

    get steps() {
        return STEPS.map(s => ({
            ...s,
            isActive: s.id === this.currentStep,
            isDone: s.id < this.currentStep,
            cls: 'step' + (s.id === this.currentStep ? ' step--active' : '') + (s.id < this.currentStep ? ' step--done' : ''),
            label: s.id === this.currentStep ? `${s.id}. ${s.label}` : s.label
        }));
    }
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get backDisabled() { return this.currentStep === 1; }
    get continueLabel() {
        if (this.currentStep === 4) return 'Submit for Approval';
        return 'Continue';
    }
    get stepLabel() { return `Step ${this.currentStep} out of 4`; }
    get progressStyle() { return `width:${(this.currentStep / 4) * 100}%;`; }
    get questionTypeOptions() { return QTYPES; }

    get reviewQuestions() {
        return this.questions.map((q, i) => ({
            ...q,
            number: i + 1,
            typeLabel: (QTYPES.find(t => t.value === q.type) || { label: q.type }).label,
            hasOpts: ['radio', 'checkbox'].indexOf(q.type) >= 0 && q.opts.length > 0
        }));
    }
    get questionsWithIndex() {
        return this.questions.map((q, i) => ({
            ...q,
            number: i + 1,
            // Per-type config visibility (the bug: only radio/checkbox were handled).
            showOpts: ['radio', 'checkbox'].indexOf(q.type) >= 0,
            showScale: q.type === 'linear',
            showShort: q.type === 'short',
            showYesNo: q.type === 'yesno',
            opts: q.opts.map((o, oi) => ({ idx: oi, value: o, key: q.id + '_o' + oi }))
        }));
    }

    // === step 1 inputs ===
    handleTitle(e) { this.title = e.target.value; }
    handleDesc(e) { this.description = e.target.value; }
    handleCategory(e) { this.category = e.target.value; }
    handleStart(e) { this.startDate = e.target.value; }
    handleEnd(e) { this.endDate = e.target.value; }
    handleAnonymous(e) { this.anonymousAllowed = e.target.checked; }
    handleEstResp(e) { this.estimatedResponses = Number(e.target.value || 0); }

    // === step 2 audience: handled by the canonical kenEventStepDetailsV2 builder, which
    //     emits its full selection continuously via valuechange (see handleAudienceChange). ===
    handleAudienceChange(event) {
        const { field, value } = event.detail || {};
        if (field === 'audienceDetail') {
            this.audienceData = value;
        }
    }

    // === step 3 questions ===
    handleQText(e) {
        const id = e.currentTarget.dataset.id;
        const val = e.target.value;
        this.questions = this.questions.map(q => q.id === id ? { ...q, text: val } : q);
    }
    handleQType(e) {
        const id = e.currentTarget.dataset.id;
        const val = e.target.value;
        this.questions = this.questions.map(q => {
            if (q.id !== id) return q;
            const next = { ...q, type: val };
            const isYesNoOpts = q.opts && q.opts.length === 2 && q.opts[0] === 'Yes' && q.opts[1] === 'No';
            if (val === 'yesno') {
                next.opts = ['Yes', 'No'];          // fixed options for Yes/No
            } else if ((val === 'radio' || val === 'checkbox') && (!q.opts || q.opts.length === 0 || isYesNoOpts)) {
                next.opts = ['Option 1', 'Option 2']; // seed choices when coming from a non-choice type
            }
            if (val === 'linear') {
                if (next.scaleMin == null) next.scaleMin = 1;
                if (next.scaleMax == null) next.scaleMax = 5;
            }
            return next;
        });
    }
    handleScaleMin(e) {
        const id = e.currentTarget.dataset.id; const v = Number(e.target.value);
        this.questions = this.questions.map(q => q.id === id ? { ...q, scaleMin: v } : q);
    }
    handleScaleMax(e) {
        const id = e.currentTarget.dataset.id; const v = Number(e.target.value);
        this.questions = this.questions.map(q => q.id === id ? { ...q, scaleMax: v } : q);
    }
    handleScaleMinLabel(e) {
        const id = e.currentTarget.dataset.id; const v = e.target.value;
        this.questions = this.questions.map(q => q.id === id ? { ...q, scaleMinLabel: v } : q);
    }
    handleScaleMaxLabel(e) {
        const id = e.currentTarget.dataset.id; const v = e.target.value;
        this.questions = this.questions.map(q => q.id === id ? { ...q, scaleMaxLabel: v } : q);
    }
    handleQRequired(e) {
        const id = e.currentTarget.dataset.id;
        const val = e.target.checked;
        this.questions = this.questions.map(q => q.id === id ? { ...q, required: val } : q);
    }
    handleOptText(e) {
        const qid = e.currentTarget.dataset.qid;
        const oi = Number(e.currentTarget.dataset.oi);
        const val = e.target.value;
        this.questions = this.questions.map(q => {
            if (q.id !== qid) return q;
            const opts = [...q.opts];
            opts[oi] = val;
            return { ...q, opts };
        });
    }
    handleAddOpt(e) {
        const qid = e.currentTarget.dataset.qid;
        this.questions = this.questions.map(q => q.id === qid ? { ...q, opts: [...q.opts, `Option ${q.opts.length + 1}`] } : q);
    }
    handleAddQuestion() {
        this.questions = [...this.questions, { id: `cq${Date.now()}`, type: 'radio', text: '', opts: ['Option 1', 'Option 2'], required: false, scaleMin: 1, scaleMax: 5, scaleMinLabel: '', scaleMaxLabel: '' }];
    }
    handleRemoveQuestion(e) {
        const id = e.currentTarget.dataset.id;
        this.questions = this.questions.filter(q => q.id !== id);
    }

    // === Navigation ===
    handleBack() { this.stepError = ''; if (this.currentStep > 1) this.currentStep -= 1; }
    handleContinue() {
        this.stepError = '';
        // Step 1: title required + end-date must not precede start-date.
        if (this.currentStep === 1) {
            if (!this.title.trim()) { this.stepError = 'Please enter a survey title.'; return; }
            if (this.startDate && this.endDate && this.endDate < this.startDate) {
                this.stepError = 'End date cannot be before the start date.';
                return;
            }
        }
        // Step 2 audience is captured live via handleAudienceChange — nothing to grab here.
        // Step 3: at least one question, each with text.
        if (this.currentStep === 3) {
            if (!this.questions.length) { this.stepError = 'Add at least one question.'; return; }
            if (this.questions.some(q => !q.text.trim())) {
                this.stepError = 'Every question needs question text.';
                return;
            }
        }
        if (this.currentStep < 4) {
            this.currentStep += 1;
            return;
        }
        // Final submit — derive payload from the canonical builder's compiled audience.
        const a = this.audienceData || { roles: [], groups: [], individuals: [], groupIds: [], individualIds: [] };
        // Back-compat: deduped list of role/batch values for Target_Audience__c.
        const roleNames = [...new Set((a.roles || []).filter(Boolean))];
        this.dispatchEvent(new CustomEvent('submit', { detail: {
            title: this.title,
            desc: this.description,
            category: this.category,
            startDate: this.startDate,
            endDate: this.endDate,
            anonymous: this.anonymousAllowed,
            audience: roleNames,   // roles (back-compat → Target_Audience__c)
            audienceDetail: {
                roles: a.roles || [],
                groupIds: a.groupIds || (a.groups || []).map(g => g.id),
                individualIds: a.individualIds || (a.individuals || []).map(i => i.id)
            },
            audienceData: a,   // full compiled audience object
            questions: this.questions
        } }));
    }

    handleCancel() { this.dispatchEvent(new CustomEvent('close')); }
}