import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const DRAFT_KEY = 'ken_manual_job_flow_draft_v1';
const INITIAL_AUDIENCE = [
    { id: 'aud-1', name: 'Computer Science 24-25', members: 128, selected: false },
    { id: 'aud-2', name: 'Faculty and Staff 24-25', members: 184, selected: false }
];
const INITIAL_STAGES = [
    {
        id: 'stage-1',
        number: 1,
        name: 'Pre-Placement Talk (PPT)',
        type: 'O',
        startDate: '2025-05-05',
        startTime: '14:00',
        endDate: '2025-05-05',
        endTime: '14:00'
    },
    {
        id: 'stage-2',
        number: 2,
        name: 'Aptitude Test',
        type: 'S',
        startDate: '2025-05-05',
        startTime: '14:00',
        endDate: '2025-05-05',
        endTime: '14:00'
    }
];

function cloneRecords(records) {
    return records.map((item) => ({ ...item }));
}

function defaultForm() {
    return {
        jobId: 'HUIVEF8982',
        jobTitle: '',
        employer: '',
        placementCycle: '',
        postedBy: '',
        status: '',
        jobDescription: '',
        roleCategory: '',
        employmentType: '',
        workplaceType: '',
        location: '',
        headcount: '',
        notes: '',
        currencyType: '',
        salaryStart: '',
        salaryEnd: '',
        isPoc: 'no',
        pocName: '',
        pocContact: '',
        pocEmail: '',
        applicationOpenDate: '',
        applicationCloseDate: '',
        receiveApplicants: false
    };
}

export default class KenManualJobFlow extends LightningElement {
    manualJobStep = 1;
    formData = defaultForm();
    fieldErrors = {};
    audienceError = '';

    savedAudience = cloneRecords(INITIAL_AUDIENCE);
    audienceSearchText = '';
    showAudienceModal = false;
    newAudienceName = '';
    newAudienceMembers = '';

    stages = cloneRecords(INITIAL_STAGES);
    showStageModal = false;
    stageModalTitle = 'Add Stage';
    editingStageId;
    stageForm = {
        name: '',
        type: 'O',
        startDate: '',
        startTime: '',
        endDate: '',
        endTime: ''
    };

    connectedCallback() {
        this.loadDraft();
    }

    get isStep1() {
        return this.manualJobStep === 1;
    }

    get isStep2() {
        return this.manualJobStep === 2;
    }

    get isStep3() {
        return this.manualJobStep === 3;
    }

    get step1Class() {
        return `manual-step${this.manualJobStep === 1 ? ' active' : ''}${this.manualJobStep > 1 ? ' done' : ''}`;
    }

    get step2Class() {
        return `manual-step${this.manualJobStep === 2 ? ' active' : ''}${this.manualJobStep > 2 ? ' done' : ''}`;
    }

    get step3Class() {
        return `manual-step${this.manualJobStep === 3 ? ' active' : ''}`;
    }

    get stepStatusLabel() {
        return `Step ${this.manualJobStep} out of 3`;
    }

    get step1Marker() {
        return this.manualJobStep > 1 ? '✓' : '1';
    }

    get step2Marker() {
        return this.manualJobStep > 2 ? '✓' : '2';
    }

    get hasStages() {
        return this.stages.length > 0;
    }

    get progressStyle() {
        return `width: ${(this.manualJobStep / 3) * 100}%;`;
    }

    get yesChecked() {
        return this.formData.isPoc === 'yes';
    }

    get noChecked() {
        return this.formData.isPoc === 'no';
    }

    get filteredAudience() {
        const query = this.audienceSearchText.trim().toLowerCase();
        const source = query
            ? this.savedAudience.filter((audience) => audience.name.toLowerCase().includes(query))
            : this.savedAudience;

        return source.map((audience) => ({
            ...audience,
            buttonClass: audience.selected ? 'outlined-btn small selected' : 'outlined-btn small',
            buttonLabel: audience.selected ? 'Added' : 'Review & Add'
        }));
    }

    get selectedAudienceCount() {
        return this.savedAudience.filter((audience) => audience.selected).length;
    }

    get decoratedStages() {
        return this.stages.map((stage, index) => ({
            ...stage,
            number: index + 1,
            startDateLabel: this.formatDate(stage.startDate),
            endDateLabel: this.formatDate(stage.endDate),
            startTimeLabel: this.formatTime(stage.startTime),
            endTimeLabel: this.formatTime(stage.endTime)
        }));
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        if (!field) {
            return;
        }

        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.formData = {
            ...this.formData,
            [field]: value
        };

        if (this.fieldErrors[field]) {
            this.clearFieldError(field);
        }
    }

    handlePocChange(event) {
        const value = event.target.value;
        this.formData = {
            ...this.formData,
            isPoc: value
        };
    }

    handleAudienceSearch(event) {
        this.audienceSearchText = event.target.value;
    }

    handleAudienceToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.savedAudience = this.savedAudience.map((audience) =>
            audience.id === id ? { ...audience, selected: !audience.selected } : audience
        );
        if (this.selectedAudienceCount > 0) {
            this.audienceError = '';
        }
    }

    openAudienceModal() {
        this.newAudienceName = '';
        this.newAudienceMembers = '';
        this.showAudienceModal = true;
    }

    closeAudienceModal() {
        this.showAudienceModal = false;
    }

    handleNewAudienceInput(event) {
        const field = event.target.dataset.field;
        if (field === 'name') {
            this.newAudienceName = event.target.value;
        }
        if (field === 'members') {
            this.newAudienceMembers = event.target.value;
        }
    }

    saveAudience() {
        const name = this.newAudienceName.trim();
        const members = Number(this.newAudienceMembers);

        if (!name || !members || members < 1) {
            this.showToast('Please enter audience name and valid members count.', 'error');
            return;
        }

        this.savedAudience = [
            {
                id: `aud-${Date.now()}`,
                name,
                members,
                selected: true
            },
            ...this.savedAudience
        ];

        this.closeAudienceModal();
    }

    openAddStageModal() {
        this.stageModalTitle = 'Add Stage';
        this.editingStageId = undefined;
        this.stageForm = {
            name: '',
            type: 'O',
            startDate: '',
            startTime: '',
            endDate: '',
            endTime: ''
        };
        this.showStageModal = true;
    }

    openEditStageModal(event) {
        const id = event.currentTarget.dataset.id;
        const stage = this.stages.find((item) => item.id === id);
        if (!stage) {
            return;
        }

        this.stageModalTitle = 'Edit Stage';
        this.editingStageId = id;
        this.stageForm = {
            name: stage.name,
            type: stage.type,
            startDate: stage.startDate,
            startTime: stage.startTime,
            endDate: stage.endDate,
            endTime: stage.endTime
        };
        this.showStageModal = true;
    }

    closeStageModal() {
        this.showStageModal = false;
    }

    handleStageInput(event) {
        const field = event.target.dataset.field;
        if (!field) {
            return;
        }

        this.stageForm = {
            ...this.stageForm,
            [field]: event.target.value
        };
    }

    saveStage() {
        const { name, type, startDate, startTime, endDate, endTime } = this.stageForm;

        if (!name.trim() || !type || !startDate || !startTime || !endDate || !endTime) {
            this.showToast('Please complete all stage fields.', 'error');
            return;
        }

        const stageStart = new Date(`${startDate}T${startTime}`);
        const stageEnd = new Date(`${endDate}T${endTime}`);
        if (stageEnd < stageStart) {
            this.showToast('Stage end date/time must be after start date/time.', 'error');
            return;
        }

        if (this.editingStageId) {
            this.stages = this.stages.map((stage) =>
                stage.id === this.editingStageId
                    ? { ...stage, ...this.stageForm, name: name.trim() }
                    : stage
            );
        } else {
            this.stages = [
                ...this.stages,
                {
                    id: `stage-${Date.now()}`,
                    ...this.stageForm,
                    name: name.trim()
                }
            ];
        }

        this.closeStageModal();
    }

    deleteStage(event) {
        const id = event.currentTarget.dataset.id;
        this.stages = this.stages.filter((stage) => stage.id !== id);
    }

    handleManualPrevious() {
        if (this.manualJobStep > 1) {
            this.manualJobStep -= 1;
        }
        this.audienceError = '';
    }

    handleManualNext() {
        if (this.manualJobStep === 1 && !this.validateStep1()) {
            return;
        }

        if (this.manualJobStep === 2 && this.selectedAudienceCount === 0) {
            this.audienceError = 'Please add at least one target audience.';
            this.scrollToAudienceSection();
            return;
        }
        this.audienceError = '';

        if (this.manualJobStep < 3) {
            this.manualJobStep += 1;
        }
    }

    handleManualCancel() {
        this.resetFlow();
    }

    handleSaveDraft() {
        this.persistDraft();
        this.showToast('Draft saved successfully.', 'success');
    }

    handleManualSubmit() {
        if (!this.validateStep1()) {
            this.manualJobStep = 1;
            return;
        }

        if (this.selectedAudienceCount === 0) {
            this.manualJobStep = 2;
            this.audienceError = 'Please add at least one target audience.';
            this.scrollToAudienceSection();
            return;
        }

        this.persistDraft();
        this.showToast('Job flow submitted successfully.', 'success');
        this.resetFlow();
    }

    validateStep1() {
        const errors = {};
        const requiredFieldMessages = {
            jobTitle: 'Job title is required.',
            employer: 'Employer is required.',
            placementCycle: 'Placement cycle is required.',
            status: 'Status is required.',
            employmentType: 'Employment type is required.',
            workplaceType: 'Work place type is required.',
            location: 'Location is required.',
            currencyType: 'Currency type is required.',
            salaryStart: 'Salary start range is required.',
            salaryEnd: 'Salary end range is required.',
            pocName: 'POC name is required.',
            pocContact: 'Contact number is required.',
            pocEmail: 'Email ID is required.',
            applicationOpenDate: 'Application open date is required.',
            applicationCloseDate: 'Last date to apply is required.',
            receiveApplicants: 'Please enable receive applicants.'
        };

        Object.keys(requiredFieldMessages).forEach((field) => {
            if (field === 'receiveApplicants') {
                if (!this.formData.receiveApplicants) {
                    errors.receiveApplicants = requiredFieldMessages[field];
                }
                return;
            }

            if (!String(this.formData[field] ?? '').trim()) {
                errors[field] = requiredFieldMessages[field];
            }
        });

        const openDate = new Date(this.formData.applicationOpenDate);
        const closeDate = new Date(this.formData.applicationCloseDate);
        if (!errors.applicationOpenDate && !errors.applicationCloseDate && openDate > closeDate) {
            errors.applicationCloseDate = 'Last date to apply must be after application open date.';
        }

        const salaryStart = Number(this.formData.salaryStart);
        const salaryEnd = Number(this.formData.salaryEnd);
        if (!errors.salaryStart && !errors.salaryEnd && salaryStart > salaryEnd) {
            errors.salaryEnd = 'Salary end range must be greater than or equal to start range.';
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!errors.pocEmail && !emailRegex.test(this.formData.pocEmail)) {
            errors.pocEmail = 'Please enter a valid POC email ID.';
        }

        this.fieldErrors = errors;
        const firstErrorField = Object.keys(errors)[0];
        if (firstErrorField) {
            this.scrollToField(firstErrorField);
            return false;
        }

        return true;
    }

    persistDraft() {
        const payload = {
            manualJobStep: this.manualJobStep,
            formData: this.formData,
            savedAudience: this.savedAudience,
            stages: this.stages
        };

        try {
            window.localStorage.setItem(DRAFT_KEY, JSON.stringify(payload));
        } catch (error) {
            // no-op
        }
    }

    loadDraft() {
        try {
            const raw = window.localStorage.getItem(DRAFT_KEY);
            if (!raw) {
                return;
            }

            const parsed = JSON.parse(raw);
            if (parsed && parsed.formData) {
                this.manualJobStep = Number(parsed.manualJobStep) || 1;
                this.formData = { ...defaultForm(), ...parsed.formData };
                this.savedAudience = Array.isArray(parsed.savedAudience) ? parsed.savedAudience : cloneRecords(INITIAL_AUDIENCE);
                this.stages = Array.isArray(parsed.stages) ? parsed.stages : cloneRecords(INITIAL_STAGES);
            }
        } catch (error) {
            // no-op
        }
    }

    resetFlow() {
        this.manualJobStep = 1;
        this.formData = defaultForm();
        this.savedAudience = cloneRecords(INITIAL_AUDIENCE);
        this.stages = cloneRecords(INITIAL_STAGES);
        this.audienceSearchText = '';
        this.audienceError = '';
        this.fieldErrors = {};
        this.showAudienceModal = false;
        this.showStageModal = false;
    }

    clearFieldError(field) {
        const nextErrors = { ...this.fieldErrors };
        delete nextErrors[field];
        this.fieldErrors = nextErrors;
    }

    scrollToField(field) {
        const target = this.template.querySelector(`[data-field="${field}"]`);
        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'center' });
            target.focus();
            return;
        }

        if (field === 'receiveApplicants') {
            const checkboxSection = this.template.querySelector('.checkbox-row');
            if (checkboxSection) {
                checkboxSection.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        }
    }

    scrollToAudienceSection() {
        const target = this.template.querySelector('.audience-grid');
        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
    }

    showToast(message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: variant === 'success' ? 'Success' : 'Validation',
                message,
                variant
            })
        );
    }

    formatDate(dateValue) {
        if (!dateValue) {
            return '-';
        }
        const [year, month, day] = dateValue.split('-');
        return `${day}-${month}-${year}`;
    }

    formatTime(timeValue) {
        if (!timeValue) {
            return '-';
        }

        const [hoursRaw, minutes] = timeValue.split(':');
        const hours = Number(hoursRaw);
        const suffix = hours >= 12 ? 'PM' : 'AM';
        const hour12 = hours % 12 || 12;
        return `${hour12}:${minutes} ${suffix}`;
    }
}