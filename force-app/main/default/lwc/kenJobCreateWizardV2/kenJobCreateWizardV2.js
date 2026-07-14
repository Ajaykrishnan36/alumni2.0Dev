import { LightningElement, track } from 'lwc';
import createContentVersion from '@salesforce/apex/KenCreateContentVersion.createContentVersion';

/* ------------------------------------------------------------------ *
 * 3-step wizard (Figma: create job / auto-filled / applicable for /
 * stages v1).  Phases:  entry → (loading) → form[1..3].
 * Raw SLDS-style HTML throughout to avoid LWR Shadow-DOM bleed.
 * ------------------------------------------------------------------ */

const STEPS = [
    { id: 1, label: 'Basic details' },
    { id: 2, label: 'Target Audience' },
    { id: 3, label: 'Stages' }
];

const ROLE_CATEGORIES   = ['Technology', 'Consulting', 'Finance', 'Marketing', 'Operations', 'Human Resources', 'Design', 'Sales', 'Product', 'Research', 'Other'];
const EMPLOYMENT_TYPES  = ['Full-Time', 'Part-Time', 'Internship', 'Contract', 'Temporary', 'Freelance'];
const WORKPLACE_TYPES   = ['Onsite', 'Hybrid', 'Remote'];
const CURRENCIES        = ['INR', 'USD', 'EUR', 'GBP', 'AUD', 'CAD', 'SGD', 'AED'];
const STATUSES          = ['Draft', 'Open', 'Closed', 'Filled', 'Withdrawn'];
const PLACEMENT_CYCLES  = ['2026 — Summer', '2026 — Lateral', '2025-26 Placement', '2024-25 Placement'];
const EXPERIENCE_LEVELS = ['Entry Level', 'Mid Level', 'Senior Level', 'Lead / Principal', 'Executive'];
const STAGE_TYPES       = ['Online (O)', 'On-site (S)', 'Hybrid (H)', 'Assessment', 'Interview', 'Other'];
const CGPA_OPERATORS    = ['Greater than', 'Less than', 'Equal to'];

export default class KenJobCreateWizardV2 extends LightningElement {
    /* ---------------- phase / step machine ---------------- */
    @track phase = 'entry';            // 'entry' | 'loading' | 'form'
    @track createMode = '';            // 'manual' | 'upload'
    @track fromUpload = false;
    @track showFetchBanner = false;
    @track step = 1;
    @track errorMsg = '';
    @track descError = '';

    /* ---------------- Step 1 — Identity ---------------- */
    @track jobId = 'HIUWEF8982';
    @track jobTitle = '';
    @track employer = '';
    @track placementCycle = '';
    @track postedBy = '';
    @track statusField = '';

    /* ---------------- Step 1 — Job Details ---------------- */
    @track fullDescription = '';
    @track roleCategory = '';
    @track employmentType = '';
    @track workplaceType = '';
    @track location = '';
    @track currency = 'INR';
    @track shortDescription = '';

    /* ---------------- Step 1 — Cover image ---------------- */
    @track bannerUrl = '';
    @track bannerName = '';
    @track coverUploading = false;
    @track coverError = '';
    MAX_COVER_BYTES = 2 * 1024 * 1024;

    /* ---------------- Step 2 — Target Audience ---------------- */
    @track audienceData = null;

    /* ---------------- Step 2 — Academic Requirements ---------------- */
    @track program = '';
    @track gradYear = '';
    @track cgpaOperator = 'Greater than';
    @track cgpaValue = '';
    @track classXPercent = '';
    @track classXIIPercent = '';
    @track attendance = '';

    /* ---------------- Step 2 — Experience Requirements ---------------- */
    @track minExperience = '';
    @track experienceLevel = '';
    @track preferredDegree = '';
    @track preferredSpecialization = '';
    @track relevantWorkExperience = '';
    @track technicalSkills = '';

    /* ---------------- Step 3 — Stages ---------------- */
    @track stages = [];
    _stageSeq = 0;

    /* ================= option getters ================= */
    get steps() { return STEPS; }
    _opts(list, current) { return list.map(v => ({ value: v, label: v, selected: v === current })); }
    get roleCategoryOptions()  { return this._opts(ROLE_CATEGORIES, this.roleCategory); }
    get employmentTypeOptions() { return this._opts(EMPLOYMENT_TYPES, this.employmentType); }
    get workplaceTypeOptions()  { return this._opts(WORKPLACE_TYPES, this.workplaceType); }
    get currencyOptions()       { return this._opts(CURRENCIES, this.currency); }
    get statusOptions()         { return this._opts(STATUSES, this.statusField); }
    get placementCycleOptions() { return this._opts(PLACEMENT_CYCLES, this.placementCycle); }
    get experienceLevelOptions() { return this._opts(EXPERIENCE_LEVELS, this.experienceLevel); }
    get cgpaOperatorOptions()   { return this._opts(CGPA_OPERATORS, this.cgpaOperator); }

    /* ================= phase flags ================= */
    get isEntry()   { return this.phase === 'entry'; }
    get isLoading() { return this.phase === 'loading'; }
    get isForm()    { return this.phase === 'form'; }

    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }

    /* ================= stepper / progress ================= */
    get stepperItems() {
        return STEPS.map((s, i) => {
            const done = this.step > s.id;
            const active = this.step === s.id;
            return {
                id: s.id,
                label: s.label,
                num: s.id,
                showCheck: done,
                stepClass: 'step' + (active ? ' step--active' : '') + (done ? ' step--done' : ''),
                showConnector: i < STEPS.length - 1
            };
        });
    }
    get progressStyle() { return `width:${(this.step / STEPS.length) * 100}%;`; }
    get stepCounter() { return `Step ${this.step} out of ${STEPS.length}`; }

    /* ================= stage rows (display index) ================= */
    get stageRows() {
        return this.stages.map((s, i) => ({
            ...s,
            index: i + 1,
            typeOptions: STAGE_TYPES.map(t => ({ value: t, label: t, selected: t === s.type }))
        }));
    }
    get hasStages() { return this.stages.length > 0; }

    /* ================= footer labels ================= */
    get primaryLabel() {
        if (this.step === 1) return 'Save and Proceed';
        if (this.step === 2) return 'Next Step';
        return 'Submit';
    }
    get showBackButton() { return this.step > 1; }
    get leftFooterIsCancel() { return this.step === 1; }

    /* ================= cover image ================= */
    get hasCover() { return !!(this.bannerUrl && this.bannerUrl.length); }
    get coverLabel() {
        if (this.coverUploading) return 'Uploading…';
        return this.bannerName ? this.bannerName : 'Upload cover image';
    }
    get coverPreviewStyle() {
        return `width:160px;height:96px;border-radius:8px;border:1px solid #E5E6E8;flex:0 0 auto;`
            + `background-image:url('${this.bannerUrl}');background-size:cover;background-position:center;`;
    }

    /* ================= entry / upload phase ================= */
    chooseManual() {
        this.createMode = 'manual';
        this.fromUpload = false;
        this.showFetchBanner = false;
        this.phase = 'form';
        this.step = 1;
    }
    chooseUpload() {
        this.createMode = 'upload';
        this.phase = 'loading';
        // Mock the 2-second "extracting…" delay, then drop into Step 1 with the
        // partial-extract banner shown and the fields we "could" read pre-filled.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this._applyMockExtract();
            this.fromUpload = true;
            this.showFetchBanner = true;
            this.phase = 'form';
            this.step = 1;
        }, 2000);
    }
    dismissBanner() { this.showFetchBanner = false; }

    _applyMockExtract() {
        // Fields we were "able" to read off the JD document.
        if (!this.jobTitle) this.jobTitle = 'Software Engineer';
        if (!this.employer) this.employer = 'Global Equity Market Neutral Fund';
        if (!this.roleCategory) this.roleCategory = 'Technology';
        if (!this.employmentType) this.employmentType = 'Full-Time';
        if (!this.workplaceType) this.workplaceType = 'Hybrid';
        if (!this.fullDescription) {
            this.fullDescription =
                '• Design, develop, and maintain software applications, services, and systems.\n'
                + '• Write clean, efficient, and well-documented code.\n'
                + '• Collaborate with product managers, designers, and other engineers to define and implement requirements.\n'
                + '• Troubleshoot, debug, and optimize code for performance and scalability.\n'
                + '• Participate in code reviews to maintain high standards of code quality.\n'
                + '• Stay up to date with emerging technologies, tools, and best practices.';
        }
        // Intentionally LEFT BLANK (these are the "could not fetch" items):
        // placementCycle, postedBy, status, headcount, salary end range, point of contact, application window.
    }

    /* ================= field handlers ================= */
    handleLocalField(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        this[field] = event.target.value;
        if (field === 'fullDescription' && (event.target.value || '').trim() !== '') this.descError = '';
        if (this.errorMsg) this.errorMsg = '';
    }

    // "Continue writing with AI" — mock assist that appends a helpful sentence.
    aiAssist(event) {
        const field = event.currentTarget.dataset.field;
        if (!field) return;
        const snippets = {
            fullDescription: '\n\nWe are looking for a passionate professional to join our team, take ownership of impactful projects, and grow with us.',
            relevantWorkExperience: '\n\nPrior experience delivering production-grade work in a fast-paced, collaborative environment is strongly preferred.',
            technicalSkills: '\n\nFamiliarity with modern tooling, version control, and agile delivery practices is a plus.'
        };
        const add = snippets[field] || '\n\n(Drafted with AI assistance.)';
        this[field] = (this[field] || '') + add;
    }

    handleAudienceChange(event) {
        const { field, value } = event.detail || {};
        if (field === 'audienceDetail') this.audienceData = value;
    }

    /* ================= cover upload (ContentVersion) ================= */
    handleCoverPhoto(event) {
        this.coverError = '';
        const file = event && event.target && event.target.files && event.target.files[0];
        if (!file) return;
        if (file.size > this.MAX_COVER_BYTES) {
            this.coverError = 'Image too large (max 2 MB). Please choose a smaller image.';
            event.target.value = '';
            return;
        }
        const fileName = file.name;
        this.coverUploading = true;
        const reader = new FileReader();
        reader.onload = () => {
            const result = String(reader.result || '');
            const idx = result.indexOf('base64,');
            const base64 = idx > -1 ? result.substring(idx + 7) : '';
            if (!base64) { this.coverUploading = false; this.coverError = 'Could not read that image.'; return; }
            createContentVersion({ title: 'JobCover_' + Date.now() + '_' + fileName, base64String: base64 })
                .then(url => {
                    this.coverUploading = false;
                    if (url && /^https?:\/\//i.test(url)) {
                        this.bannerUrl = url;
                        this.bannerName = fileName;
                    } else {
                        this.coverError = 'Cover upload failed: ' + (url || 'unknown error');
                    }
                })
                .catch(err => {
                    this.coverUploading = false;
                    this.coverError = (err && err.body && err.body.message) || 'Cover upload failed.';
                });
        };
        reader.onerror = () => { this.coverUploading = false; this.coverError = 'Could not read that image. Please try another.'; };
        reader.readAsDataURL(file);
    }
    handleRemoveCover() { this.coverError = ''; this.bannerUrl = ''; this.bannerName = ''; }

    /* ================= stages ================= */
    addStage() {
        this._stageSeq += 1;
        this.stages = this.stages.concat([{
            id: 'stg-' + this._stageSeq,
            name: '', type: '', startDate: '', startTime: '', endDate: '', endTime: ''
        }]);
    }
    handleStageField(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const val = event.target.value;
        this.stages = this.stages.map(s => (s.id === id ? { ...s, [field]: val } : s));
    }
    removeStage(event) {
        const id = event.currentTarget.dataset.id;
        this.stages = this.stages.filter(s => s.id !== id);
    }

    /* ================= validation ================= */
    _missingForStep(step) {
        const blank = (v) => v === null || v === undefined || String(v).trim() === '';
        const missing = [];
        if (step === 1) {
            if (blank(this.jobTitle)) missing.push('Job Title');
            if (blank(this.employer)) missing.push('Employer');
            if (blank(this.placementCycle)) missing.push('Placement Cycle');
            if (blank(this.statusField)) missing.push('Status');
            if (blank(this.fullDescription)) missing.push('Job Description');
        }
        // Step 2 (audience + requirements) and Step 3 (stages) are optional by design.
        return missing;
    }
    validateStep() {
        if (this.step === 1) {
            this.descError = (this.fullDescription || '').trim() === '' ? 'Please enter a job description.' : '';
        }
        const missing = this._missingForStep(this.step);
        if (missing.length) {
            this.errorMsg = 'Please fill the required field(s): ' + missing.join(', ') + '.';
            return false;
        }
        this.errorMsg = '';
        return true;
    }

    /* ================= payload (DML-ready) ================= */
    buildPayload() {
        const company = this.employer || '';
        const skillsArr = (this.technicalSkills || '')
            .split(/[\n,]/).map(s => s.trim()).filter(Boolean);

        const academicRequirements = {
            program: this.program || null,
            yearOfGraduation: this.gradYear || null,
            cgpa: (this.cgpaValue ? { operator: this.cgpaOperator, value: this.cgpaValue } : null),
            classXPercent: this.classXPercent || null,
            classXIIPercent: this.classXIIPercent || null,
            attendance: this.attendance || null
        };
        const experienceRequirements = {
            minYears: this.minExperience || null,
            level: this.experienceLevel || null,
            preferredDegree: this.preferredDegree || null,
            preferredSpecialization: this.preferredSpecialization || null
        };
        const stages = this.stages.map((s, i) => ({
            order: i + 1,
            name: s.name || null,
            type: s.type || null,
            startDate: s.startDate || null,
            startTime: s.startTime || null,
            endDate: s.endDate || null,
            endTime: s.endTime || null
        }));

        return {
            // ---- identity ----
            jobId: this.jobId || null,
            title: this.jobTitle,
            company: company,
            placementCycle: this.placementCycle || null,
            postedBy: this.postedBy || null,
            status: this.statusField || null,
            logoInitial: company ? company.charAt(0).toUpperCase() : 'J',
            bannerUrl: this.bannerUrl || null,
            // ---- job details ----
            roleCategory: this.roleCategory || null,
            employmentType: this.employmentType || null,
            workplaceType: this.workplaceType || null,
            location: this.location || null,
            currencyCode: this.currency || null,
            shortDescription: this.shortDescription || null,
            fullDescription: this.fullDescription || null,
            // ---- audience ----
            audience: this._audienceBucket(),
            audienceData: this.audienceData ? JSON.stringify(this.audienceData) : null,
            // ---- requirements (structured + serialized blob) ----
            academicRequirements,
            experienceRequirements,
            relevantWorkExperience: this.relevantWorkExperience || null,
            technicalSkills: this.technicalSkills || null,
            experienceLevel: this.experienceLevel || null,
            requirementsJson: JSON.stringify({
                placementCycle: this.placementCycle || null,
                jobStatus: this.statusField || null,
                roleCategory: this.roleCategory || null,
                employmentType: this.employmentType || null,
                workplaceType: this.workplaceType || null,
                location: this.location || null,
                currency: this.currency || null,
                academicRequirements,
                experienceRequirements,
                relevantWorkExperience: this.relevantWorkExperience || null,
                technicalSkills: this.technicalSkills || null
            }),
            skills: skillsArr,
            // ---- stages ----
            stages,
            stagesJson: JSON.stringify(stages),
            tags: []
        };
    }

    // Map the audience builder's category to a valid Audience__c picklist bucket.
    _audienceBucket() {
        const a = this.audienceData;
        if (!a || !a.category) return 'All Alumni';
        const cat = String(a.category).toLowerCase();
        if (cat.indexOf('batch') > -1) return 'Specific Batches';
        if (cat.indexOf('program') > -1) return 'Specific Programs';
        return 'All Alumni';
    }

    /* ================= navigation ================= */
    handleNext() {
        if (!this.validateStep()) return;
        if (this.step < STEPS.length) { this.step += 1; return; }
        this.dispatchEvent(new CustomEvent('submit', { detail: { payload: this.buildPayload() } }));
    }
    handleBack() { this.errorMsg = ''; if (this.step > 1) this.step -= 1; }
    handleSaveDraft() {
        this.dispatchEvent(new CustomEvent('savedraft', { detail: { payload: this.buildPayload() } }));
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) this.handleClose();
    }
    stopBubble(event) { event.stopPropagation(); }
}