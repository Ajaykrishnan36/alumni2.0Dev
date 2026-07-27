import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getRegistrationOptions from '@salesforce/apex/KenPortalRegisterController.getRegistrationOptions';

const MONTH_OPTIONS = [
    { label: 'January', value: '01' },
    { label: 'February', value: '02' },
    { label: 'March', value: '03' },
    { label: 'April', value: '04' },
    { label: 'May', value: '05' },
    { label: 'June', value: '06' },
    { label: 'July', value: '07' },
    { label: 'August', value: '08' },
    { label: 'September', value: '09' },
    { label: 'October', value: '10' },
    { label: 'November', value: '11' },
    { label: 'December', value: '12' }
];

function getYearOptions() {
    const currentYear = new Date().getFullYear();
    const options = [];
    for (let y = currentYear; y >= currentYear - 60; y--) {
        options.push({ label: String(y), value: String(y) });
    }
    return options;
}

const MAX_TEXT_LENGTH = 100;

export default class KenEducationInformationModal extends LightningElement {
    @api educationData = null;
    @api modalTitleOverride = '';

    @track degree = '';
    @track institution = '';
    // 'institute' => pick from the org institute list (same source as the
    // registration page); 'other' => free-text institution.
    @track institutionType = 'institute';
    @track instituteOptions = [];
    @track institutionAlias = '';
    @track startMonth = '';
    @track startYear = '';
    @track endMonth = '';
    @track endYear = '';
    @track gradingFormat = 'CGPA';
    @track cgpa = '';
    @track programPlan = '';
    @track registrationNumber = '';
    @track programOptions = [];
    @track errors = { degree: '', institution: '', programPlan: '', cgpa: '', startDate: '', endDate: '', dateRange: '' };

    monthOptions = MONTH_OPTIONS;
    yearOptions = getYearOptions();
    previousData = null;

    get modalTitle() {
        if (this.modalTitleOverride) return this.modalTitleOverride;
        return this.educationData?.id ? 'Edit Education' : 'Add Education';
    }

    get isCgpa() {
        return this.gradingFormat === 'CGPA';
    }

    get isPercentage() {
        return this.gradingFormat === 'Percentage';
    }

    get gradeFieldLabel() {
        return this.isPercentage ? 'Percentage (Optional)' : 'CGPA (Optional)';
    }

    get gradePlaceholder() {
        return this.isPercentage ? 'e.g., 85' : 'e.g., 8.9';
    }

    get degreeErrorClass() {
        return `custom-input${this.errors.degree ? ' error' : ''}`;
    }

    get institutionErrorClass() {
        return `custom-input${this.errors.institution ? ' error' : ''}`;
    }

    get isInstituteType() {
        return this.institutionType === 'institute';
    }

    get isOtherType() {
        return this.institutionType === 'other';
    }

    get instituteTabLabel() {
        const alias = (this.institutionAlias || '').trim();
        return alias ? `${alias} Institute` : 'Our Institute';
    }

    get instituteTabClass() {
        return `institution-status-button${this.isInstituteType ? ' active' : ''}`;
    }

    get otherTabClass() {
        return `institution-status-button${this.isOtherType ? ' active' : ''}`;
    }

    get cgpaErrorClass() {
        return `custom-input${this.errors.cgpa ? ' error' : ''}`;
    }

    get cgpaMax() {
        return this.isPercentage ? 100 : 10;
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            this.institutionAlias = color?.institutionAlias || '';
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {});
        getRegistrationOptions()
            .then(({ institutes, programs }) => {
                this.instituteOptions = institutes || [];
                this.programOptions = programs || [];
            })
            .catch(() => { this.instituteOptions = []; this.programOptions = []; });
        this.loadData();
        this.previousData = JSON.stringify(this.educationData || null);
    }

    // Default an existing record to the "Other" tab when its institution is not
    // one of the org institutes, so editing never blanks a free-text value.
    syncInstitutionType() {
        if (!this.institution) {
            this.institutionType = 'institute';
            return;
        }
        const match = (this.instituteOptions || []).some(
            opt => opt.value === this.institution || opt.label === this.institution
        );
        this.institutionType = match ? 'institute' : 'other';
    }

    renderedCallback() {
        const current = JSON.stringify(this.educationData || null);
        if (current !== this.previousData) {
            this.loadData();
            this.previousData = current;
        }
    }

    loadData() {
        const data = this.educationData || {};
        this.degree = data.degree || '';
        this.institution = data.institution || '';
        this.startMonth = data.startMonth || '';
        this.startYear = data.startYear || '';
        this.endMonth = data.endMonth || '';
        this.endYear = data.endYear || '';
        this.gradingFormat = data.gradingFormat || 'CGPA';
        this.cgpa = data.cgpa || '';
        this.programPlan = data.programPlan || '';
        this.registrationNumber = data.registrationNumber || '';
        this.errors = { degree: '', institution: '', programPlan: '', cgpa: '', startDate: '', endDate: '', dateRange: '' };
        if (data.institutionType === 'Our Institute') {
            this.institutionType = 'institute';
        } else if (data.institutionType === 'Other') {
            this.institutionType = 'other';
        } else {
            this.syncInstitutionType();
        }
    }

    handleInstitutionTypeChange(event) {
        const type = event.currentTarget?.dataset?.type;
        if (!type || type === this.institutionType) return;
        this.institutionType = type;
        this.institution = '';
        this.programPlan = '';
        this.registrationNumber = '';
        this.errors = { ...this.errors, institution: '', programPlan: '' };
    }

    handleInstitutionPicklistChange(event) {
        this.institution = event.detail ? event.detail.value : '';
        if (this.errors.institution) {
            this.errors = { ...this.errors, institution: '' };
        }
    }

    handleProgramPlanChange(event) {
        this.programPlan = event.detail ? event.detail.value : '';
        if (this.errors.programPlan) {
            this.errors = { ...this.errors, programPlan: '' };
        }
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }

    handleInput(event) {
        const source = event.currentTarget || event.target;
        const field = source?.dataset?.field;
        const value = event.detail?.value ?? source?.value ?? '';
        if (!field) return;

        if (field === 'degree' || field === 'institution') {
            const compact = (value || '').replace(/\s{2,}/g, ' ');
            this[field] = compact.slice(0, MAX_TEXT_LENGTH);
        } else if (field === 'cgpa') {
            this.cgpa = this.normalizeGradeInput(value);
            if (this.cgpa && !this.isValidGradeRange(this.cgpa)) {
                this.errors = {
                    ...this.errors,
                    cgpa: this.isPercentage
                        ? 'Percentage must be between 0 and 100'
                        : 'CGPA must be between 0 and 10'
                };
                return;
            }
        } else {
            this[field] = value || '';
        }

        if (this.errors[field]) {
            this.errors = { ...this.errors, [field]: '' };
        }
    }

    handleSelect(event) {
        const source = event.currentTarget || event.target;
        const field = source?.dataset?.field;
        if (!field) return;
        this[field] = event.detail?.value;
        const cleared = { dateRange: '' };
        if (field === 'startMonth' || field === 'startYear') cleared.startDate = '';
        if (field === 'endMonth' || field === 'endYear') cleared.endDate = '';
        this.errors = { ...this.errors, ...cleared };
    }

    handleGrading(event) {
        this.gradingFormat = event.target.value;
        this.cgpa = this.normalizeGradeInput(this.cgpa);
        this.errors = { ...this.errors, cgpa: '' };
    }

    normalizeGradeInput(value) {
        const cleaned = String(value || '').replace(/[^0-9.]/g, '');
        if (!cleaned) return '';
        const firstDot = cleaned.indexOf('.');
        if (firstDot === -1) return cleaned;
        const intPart = cleaned.slice(0, firstDot + 1);
        const decimalPart = cleaned.slice(firstDot + 1).replace(/\./g, '');
        return intPart + decimalPart;
    }

    isValidGradeRange(value) {
        if (!value) return true;
        const asNumber = Number(value);
        if (Number.isNaN(asNumber)) return false;
        if (this.isPercentage) return asNumber >= 0 && asNumber <= 100;
        return asNumber >= 0 && asNumber <= 10;
    }

    validate() {
        const nextErrors = { degree: '', institution: '', programPlan: '', cgpa: '', startDate: '', endDate: '', dateRange: '' };
        let isValid = true;

        if (!this.degree || !this.degree.trim()) {
            nextErrors.degree = 'Degree is required';
            isValid = false;
        } else if (this.degree.trim().length > MAX_TEXT_LENGTH) {
            nextErrors.degree = 'Degree should be 100 characters or less';
            isValid = false;
        }

        if (!this.institution || !this.institution.trim()) {
            nextErrors.institution = 'Institution is required';
            isValid = false;
        } else if (this.institution.trim().length > MAX_TEXT_LENGTH) {
            nextErrors.institution = 'Institution should be 100 characters or less';
            isValid = false;
        }

        if (this.isInstituteType && (!this.programPlan || !this.programPlan.trim())) {
            nextErrors.programPlan = 'Program plan is required';
            isValid = false;
        }

        if (!this.startMonth || !this.startYear) {
            nextErrors.startDate = 'Start date is required';
            isValid = false;
        }

        if (!this.endMonth || !this.endYear) {
            nextErrors.endDate = 'End date is required';
            isValid = false;
        }

        const gradeValue = (this.cgpa || '').trim();
        if (gradeValue && !this.isValidGradeRange(gradeValue)) {
            nextErrors.cgpa = this.isPercentage
                ? 'Percentage must be between 0 and 100'
                : 'CGPA must be between 0 and 10';
            isValid = false;
        }

        if (this.startMonth && this.startYear && this.endMonth && this.endYear) {
            const startDate = new Date(parseInt(this.startYear, 10), parseInt(this.startMonth, 10) - 1);
            const endDate = new Date(parseInt(this.endYear, 10), parseInt(this.endMonth, 10) - 1);
            if (endDate < startDate) {
                nextErrors.dateRange = 'End date must be after start date';
                isValid = false;
            }
        }

        this.errors = nextErrors;
        return isValid;
    }

    scrollToFirstError() {
        const errorFields = [
            { error: 'degree', target: 'degree' },
            { error: 'institution', target: 'institution' },
            { error: 'startDate', target: 'startMonth' },
            { error: 'endDate', target: 'endMonth' },
            { error: 'dateRange', target: 'endMonth' },
            { error: 'cgpa', target: 'cgpa' }
        ];
        for (const { error, target } of errorFields) {
            if (this.errors[error]) {
                const el = this.template.querySelector(`[data-field="${target}"]`);
                if (el) {
                    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                    break;
                }
            }
        }
    }

    handleSave() {
        if (!this.validate()) {
            this.scrollToFirstError();
            return;
        }

        this.dispatchEvent(new CustomEvent('save', {
            detail: {
                id: this.educationData?.id || null,
                degree: this.degree.trim(),
                institution: this.institution.trim(),
                institutionType: this.institutionType,
                programPlan: this.isInstituteType ? this.programPlan : null,
                registrationNumber: this.isInstituteType ? (this.registrationNumber || '').trim() : null,
                startMonth: this.startMonth || null,
                startYear: this.startYear || null,
                endMonth: this.endMonth || null,
                endYear: this.endYear || null,
                gradingFormat: this.gradingFormat || 'CGPA',
                cgpa: (this.cgpa || '').trim()
            },
            bubbles: true,
            composed: true
        }));
    }
}