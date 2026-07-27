import { LightningElement, api, track } from 'lwc';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';

// Same cache key as kenNavigationMenu – use same default profile image when no photo uploaded
const PROFILE_CACHE_KEY = 'navigationMenu_profileCache';
const CACHE_DURATION_MS = 30 * 60 * 1000;

const GENDER_OPTIONS = [
    { label: 'Choose', value: '' },
    { label: 'Male', value: 'Male' },
    { label: 'Female', value: 'Female' },
    { label: 'Other', value: 'Other' }
];

function yearOptions() {
    const y = new Date().getFullYear();
    const opts = [];
    for (let i = y; i >= y - 50; i--) opts.push({ label: String(i), value: String(i) });
    return opts;
}

function toYYYYMM(dateVal) {
    if (!dateVal) return '';
    const d = new Date(dateVal);
    if (isNaN(d.getTime())) return '';
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

function formatDateLabel(startDate, endDate, isCurrent) {
    if (!startDate) return '';
    const s = new Date(startDate + '-01');
    if (isNaN(s.getTime())) return '';
    const startStr = s.toLocaleString('default', { month: 'short' }) + ' ' + s.getFullYear();
    if (isCurrent) return startStr + ' - Present';
    if (!endDate) return startStr;
    const e = new Date(endDate + '-01');
    return startStr + ' - ' + e.toLocaleString('default', { month: 'short' }) + ' ' + e.getFullYear();
}

function experienceToCareerData(exp) {
    if (!exp) return null;
    return {
        id: exp.id,
        jobTitle: exp.title || '',
        organization: exp.company || '',
        employmentType: exp.employmentType || '',
        location: exp.location || '',
        startDate: exp.startDate ? exp.startDate + '-01' : null,
        endDate: exp.endDate ? exp.endDate + '-01' : null,
        roleDescription: exp.description || '',
        isCurrentJob: !!exp.isCurrent,
        jobRole: ''
    };
}

function careerDetailToExperience(detail, id) {
    return {
        id: id || `exp_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`,
        title: (detail.jobTitle || '').trim(),
        company: (detail.organization || '').trim(),
        location: (detail.location || '').trim(),
        startDate: toYYYYMM(detail.startDate),
        endDate: toYYYYMM(detail.endDate),
        isCurrent: !!detail.isCurrentJob,
        description: (detail.roleDescription || '').trim(),
        employmentType: (detail.employmentType || '').trim()
    };
}

export default class KenResumeEditDetails extends LightningElement {
    @api resumeData = {};

    @track educationModalOpen = false;
    @track editingEducationItem = null;
    @track eduDegree = '';
    @track eduSchool = '';
    @track eduStartYear = '';
    @track eduEndYear = '';
    @track eduGpa = '';
    @track showCareerModal = false;
    @track editingExperienceId = null;
    @track careerDataForModal = null;
    @track skillInput = '';
    @track defaultProfilePhotoUrl = defaultProfileImage;

    genderOptions = GENDER_OPTIONS;

    connectedCallback() {
        this._loadProfileFromCache();
    }

    _loadProfileFromCache() {
        try {
            const cachedData = sessionStorage.getItem(PROFILE_CACHE_KEY);
            if (cachedData) {
                const { data, timestamp } = JSON.parse(cachedData);
                if (Date.now() - timestamp < CACHE_DURATION_MS && data?.profilePhotoUrl) {
                    this.defaultProfilePhotoUrl = data.profilePhotoUrl;
                    return;
                }
            }
        } catch (e) { /* ignore */ }
        this.defaultProfilePhotoUrl = defaultProfileImage;
    }
    yearOptions = yearOptions();

    get personal() { return this.resumeData?.personal ?? {}; }
    get firstName() { return this.personal.firstName ?? ''; }
    get lastName() { return this.personal.lastName ?? ''; }
    get gender() { return this.personal.gender ?? ''; }
    get phone() { return this.personal.phone ?? ''; }
    get email() { return this.personal.email ?? ''; }
    get city() { return this.personal.city ?? ''; }
    get country() { return this.personal.country ?? ''; }
    get photoUrl() { return this.personal.photoUrl ?? ''; }
    get summaryVal() { return this.resumeData?.summary ?? ''; }
    /** Show user-uploaded photo if set; otherwise show default profile image from nav cache */
    get displayPhotoUrl() {
        const custom = (this.personal.photoUrl || '').trim();
        if (custom) return custom;
        return this.defaultProfilePhotoUrl || defaultProfileImage;
    }
    get hasCustomPhoto() { return !!(this.personal.photoUrl); }
    get photoActionLabel() { return this.hasCustomPhoto ? 'Change photo' : 'Upload photo'; }

    get educationList() {
        return (this.resumeData?.education ?? []).map((e) => ({
            ...e,
            yearRange: [e.startYear, e.endYear].filter(Boolean).join(' - ')
        }));
    }

    get experienceList() {
        return (this.resumeData?.experience ?? []).map((e) => ({
            ...e,
            dateLabel: formatDateLabel(e.startDate, e.endDate, e.isCurrent),
            employmentType: e.employmentType || ''
        }));
    }

    get skillsList() {
        return Array.isArray(this.resumeData?.skills) ? this.resumeData.skills : [];
    }

    get careerModalTitle() {
        return this.editingExperienceId ? 'Edit Experience' : 'Add Experience';
    }

    get educationModalTitle() {
        return this.editingEducationItem ? 'Edit Education' : 'Add Education';
    }

    handleFieldChange(event) {
        const field = event.target.dataset?.field;
        const value = event.target.value ?? '';
        this.dispatchEvent(new CustomEvent('personalchange', { detail: { path: field, value }, bubbles: true, composed: true }));
    }

    handlePhotoClick() {
        const input = this.template.querySelector('.hidden-file-input');
        if (input) input.click();
    }

    handlePhotoChange(event) {
        const file = event.target.files?.[0];
        if (!file || !file.type.startsWith('image/')) return;
        const reader = new FileReader();
        reader.onload = () => {
            this.dispatchEvent(new CustomEvent('personalchange', { detail: { path: 'photoUrl', value: reader.result }, bubbles: true, composed: true }));
        };
        reader.readAsDataURL(file);
        event.target.value = '';
    }

    handleEducationAddClick() {
        this.editingEducationItem = null;
        this.eduDegree = '';
        this.eduSchool = '';
        this.eduStartYear = '';
        this.eduEndYear = '';
        this.eduGpa = '';
        this.educationModalOpen = true;
    }

    handleEducationEdit(event) {
        const id = event.currentTarget?.dataset?.id;
        const item = (this.resumeData?.education ?? []).find((e) => e.id === id);
        if (item) {
            this.editingEducationItem = item;
            this.eduDegree = item.degree || '';
            this.eduSchool = item.school || '';
            this.eduStartYear = item.startYear || '';
            this.eduEndYear = item.endYear || '';
            this.eduGpa = item.gpa || '';
            this.educationModalOpen = true;
        }
    }

    handleEducationRemove(event) {
        const id = event.currentTarget?.dataset?.id;
        if (id) this.dispatchEvent(new CustomEvent('educationremove', { detail: { id }, bubbles: true, composed: true }));
    }

    handleEduModalChange(event) {
        const field = event.target.dataset?.field;
        const value = event.target.value ?? '';
        if (field === 'degree') this.eduDegree = value;
        else if (field === 'school') this.eduSchool = value;
        else if (field === 'startYear') this.eduStartYear = value;
        else if (field === 'endYear') this.eduEndYear = value;
        else if (field === 'gpa') this.eduGpa = value;
    }

    handleEducationModalClose() {
        this.educationModalOpen = false;
        this.editingEducationItem = null;
    }

    handleEducationModalSave() {
        const degree = (this.eduDegree || '').trim();
        const school = (this.eduSchool || '').trim();
        if (!degree || !school) return;
        const payload = {
            id: this.editingEducationItem?.id || null,
            degree,
            school,
            startYear: (this.eduStartYear || '').trim(),
            endYear: (this.eduEndYear || '').trim(),
            gpa: (this.eduGpa || '').trim()
        };
        if (payload.id) {
            this.dispatchEvent(new CustomEvent('educationedit', { detail: payload, bubbles: true, composed: true }));
        } else {
            this.dispatchEvent(new CustomEvent('educationadd', { detail: payload, bubbles: true, composed: true }));
        }
        this.handleEducationModalClose();
    }

    handleExperienceAdd() {
        this.editingExperienceId = null;
        this.careerDataForModal = null;
        this.showCareerModal = true;
    }

    handleExperienceEdit(event) {
        const id = event.currentTarget?.dataset?.id;
        const exp = (this.resumeData?.experience ?? []).find((e) => e.id === id);
        if (exp) {
            this.editingExperienceId = id;
            this.careerDataForModal = experienceToCareerData(exp);
            this.showCareerModal = true;
        }
    }

    handleExperienceRemove(event) {
        const id = event.currentTarget?.dataset?.id;
        if (id) this.dispatchEvent(new CustomEvent('experienceremove', { detail: { id }, bubbles: true, composed: true }));
    }

    handleCareerSave(event) {
        const detail = event.detail || {};
        const entry = careerDetailToExperience(detail, this.editingExperienceId || undefined);
        if (this.editingExperienceId) {
            this.dispatchEvent(new CustomEvent('experienceedit', { detail: entry, bubbles: true, composed: true }));
        } else {
            this.dispatchEvent(new CustomEvent('experienceadd', { detail: entry, bubbles: true, composed: true }));
        }
        this.showCareerModal = false;
        this.editingExperienceId = null;
        this.careerDataForModal = null;
    }

    handleCareerClose() {
        this.showCareerModal = false;
        this.editingExperienceId = null;
        this.careerDataForModal = null;
    }

    handleSkillInputChange(event) {
        this.skillInput = event.target?.value ?? '';
    }

    handleSkillKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.commitAddSkill();
        }
    }

    handleAddSkill() {
        this.commitAddSkill();
    }

    commitAddSkill() {
        const raw = (this.skillInput || '').trim();
        if (!raw) return;
        const skills = this.resumeData?.skills ?? [];
        if (skills.map((s) => String(s).toLowerCase()).includes(raw.toLowerCase())) {
            this.skillInput = '';
            return;
        }
        this.dispatchEvent(new CustomEvent('skilladd', { detail: { value: raw }, bubbles: true, composed: true }));
        this.skillInput = '';
    }

    handleRemoveSkill(event) {
        const value = event.currentTarget?.dataset?.skill;
        if (value != null) this.dispatchEvent(new CustomEvent('skillremove', { detail: { value }, bubbles: true, composed: true }));
    }

    handleAddSection(event) {
        const name = event.currentTarget?.dataset?.name || 'Custom section';
        this.dispatchEvent(new CustomEvent('customsectionadd', { detail: { name }, bubbles: true, composed: true }));
    }

    handleCreateCoverLetter() {
        this.dispatchEvent(new CustomEvent('customsectionadd', { detail: { name: 'Cover letter', isCoverLetter: true }, bubbles: true, composed: true }));
    }

    renderedCallback() {
        const list = this.resumeData?.experience ?? [];
        const containers = this.template.querySelectorAll('[data-exp-id]');
        containers.forEach((el) => {
            const id = el.getAttribute('data-exp-id');
            const exp = list.find((e) => e.id === id);
            if (exp?.description && el.innerHTML !== exp.description) el.innerHTML = exp.description;
        });
    }
}