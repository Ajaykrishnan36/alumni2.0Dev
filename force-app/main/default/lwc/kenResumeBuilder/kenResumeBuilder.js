import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';

// Same cache key as kenNavigationMenu so we can show user's profile in template previews
const PROFILE_CACHE_KEY = 'navigationMenu_profileCache';
const CACHE_DURATION_MS = 30 * 60 * 1000;

// ----- Template Registry (inlined for LWC - only this component uses it) -----
const TEMPLATE_REGISTRY = {
    new_york: { key: 'new_york', label: 'New York', thumbnailKey: 'newyork' },
    toronto: { key: 'toronto', label: 'Toronto', thumbnailKey: 'toronto' },
    modern: { key: 'modern', label: 'Modern', thumbnailKey: 'modern' },
    classic: { key: 'classic', label: 'Classic', thumbnailKey: 'classic' }
};

function getTemplatesList() {
    return Object.keys(TEMPLATE_REGISTRY).map((key) => ({
        key,
        label: TEMPLATE_REGISTRY[key].label,
        thumbnailKey: TEMPLATE_REGISTRY[key].thumbnailKey,
        isNewYork: key === 'new_york',
        isToronto: key === 'toronto',
        isModern: key === 'modern',
        isClassic: key === 'classic'
    }));
}

// ----- Data model helpers (inlined) -----
function generateId() {
    return `${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
}

function setIn(data, path, value) {
    const parts = path.split('.');
    const key = parts.pop();
    const result = JSON.parse(JSON.stringify(data));
    let current = result;
    for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        if (!(p in current)) current[p] = {};
        current = current[p];
    }
    current[key] = value;
    return result;
}

function createDefaultResumeData() {
    return {
        template: 'new_york',
        personal: {
            firstName: '',
            lastName: '',
            gender: '',
            phone: '',
            email: '',
            city: '',
            country: '',
            photoUrl: ''
        },
        summary: '',
        education: [],
        experience: [],
        skills: [],
        customSections: []
    };
}

function createDummyResumeData() {
    return {
        template: 'toronto',
        personal: {
            firstName: 'Jon',
            lastName: 'Doe',
            gender: 'Male',
            phone: '6019521325',
            email: 'ajay@gmail.com',
            city: 'Santa Clara',
            country: 'United States',
            photoUrl: ''
        },
        summary: 'Front-end developer with experience building scalable web apps and collaborating with design and product teams.',
        education: [
            { id: 'edu1', degree: 'B Tech, Electronics and Media Technology', school: 'Sikkim Manipal University', startYear: '2010', endYear: '2012', gpa: '7.5' }
        ],
        experience: [
            {
                id: 'exp1',
                title: 'Front-end Developer',
                company: 'Zoho',
                location: 'Chennai, Tamil Nadu, India | Onsite',
                startDate: '2021-05',
                endDate: '2025-04',
                isCurrent: false,
                description: 'Built scalable UI features, performed debugging, and collaborated with teams to deliver high-quality releases.'
            }
        ],
        skills: ['Photoshop', 'Figma', 'Autolayout', 'Wireframe', 'Prototyping', 'Mockups', 'Sitemap'],
        customSections: []
    };
}

const STEPS = [
    { number: 1, label: 'Choose Template' },
    { number: 2, label: 'Edit Details' },
    { number: 3, label: 'Preview & Save' }
];

export default class KenResumeBuilder extends LightningElement {
    @track currentStep = 1;
    @track resumeData = createDummyResumeData();
    @track previewProfile = {
        profilePhotoUrl: defaultProfileImage,
        studentName: 'Student Name',
        graduationYear: '2025'
    };

    _templatesList = getTemplatesList();

    connectedCallback() {
        this._loadProfileFromCache();
        getPrimaryColor()
            .then((color) => {
                if (color?.primaryColor) document.documentElement.style.setProperty('--primary-color', color.primaryColor);
                if (color?.secondaryColor) document.documentElement.style.setProperty('--secondary-color', color.secondaryColor);
                if (color?.tertiaryColor) document.documentElement.style.setProperty('--tertiary-color', color.tertiaryColor);
            })
            .catch(() => {});
    }

    _loadProfileFromCache() {
        try {
            const cachedData = sessionStorage.getItem(PROFILE_CACHE_KEY);
            if (cachedData) {
                const { data, timestamp } = JSON.parse(cachedData);
                if (Date.now() - timestamp < CACHE_DURATION_MS && data) {
                    this.previewProfile = {
                        profilePhotoUrl: data.profilePhotoUrl || defaultProfileImage,
                        studentName: data.studentName || 'Student Name',
                        graduationYear: data.graduationYear || '2025'
                    };
                    return;
                }
            }
        } catch (e) {
            // ignore
        }
        this.previewProfile = {
            profilePhotoUrl: defaultProfileImage,
            studentName: 'Student Name',
            graduationYear: '2025'
        };
    }

    get templatesList() {
        const selected = this.selectedTemplate;
        return this._templatesList.map((tpl) => ({
            ...tpl,
            cardClass: 'template-card' + (tpl.key === selected ? ' template-card-selected' : '')
        }));
    }

    /* Preview data for template cards (profile + dummy content) */
    get previewFullName() {
        const name = (this.previewProfile?.studentName || 'Student Name').trim();
        return name.toUpperCase() || 'YOUR NAME';
    }
    get previewRoleTitle() {
        const year = this.previewProfile?.graduationYear || '2025';
        return `Class of ${year}`;
    }
    get previewContactLine() {
        return '+1-234-567-8900 | email@example.com | City, Country';
    }
    get previewPhotoUrl() {
        return this.previewProfile?.profilePhotoUrl || defaultProfileImage;
    }
    get hasPreviewPhoto() {
        return true;
    }
    get previewSummary() {
        return 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore.';
    }
    get previewEducationList() {
        return [{ id: 'preview-edu-1', degree: 'B.S. Computer Science', school: 'University Name', yearRange: '2020 - 2024' }];
    }
    get previewExperienceList() {
        return [{ id: 'preview-exp-1', title: 'Software Developer', company: 'Company Name', dateLabel: '2022 - Present' }];
    }
    get previewSkillsText() {
        return 'Leadership · Communication · Project Management · Analytics';
    }

    get stepperItems() {
        const total = STEPS.length;
        return STEPS.map((step) => {
            const isActive = this.currentStep === step.number;
            const isCompleted = this.currentStep > step.number;
            return {
                ...step,
                isActive,
                isCompleted,
                isLast: step.number === total,
                statusClass: `step ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''}`.trim(),
                lineClass: isActive || isCompleted ? 'step-line step-line-active' : 'step-line'
            };
        });
    }

    get progressStyle() {
        const pct = Math.min(100, ((this.currentStep - 1) / (STEPS.length - 1)) * 100);
        return `width: ${pct}%`;
    }

    get stepLabel() {
        return `Step ${this.currentStep} out of 3`;
    }

    handleTemplateSelect(event) {
        const key = event.currentTarget?.dataset?.template;
        if (key) this.resumeData = setIn(this.resumeData, 'template', key);
    }

    handleTemplateKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleTemplateSelect(event);
        }
    }

    get isStep1Active() { return this.currentStep === 1; }
    get isStep2Active() { return this.currentStep === 2; }
    get isStep3Active() { return this.currentStep === 3; }

    get canProceedFromStep2() {
        const p = this.resumeData?.personal ?? {};
        const fn = (p.firstName || '').trim();
        const ln = (p.lastName || '').trim();
        return fn.length > 0 && ln.length > 0;
    }

    get nextDisabledStep2() {
        return !this.canProceedFromStep2;
    }

    get selectedTemplate() {
        return this.resumeData?.template ?? 'new_york';
    }

    handlePersonalChange(event) {
        const { path, value } = event.detail || {};
        if (!path) return;
        if (path === 'summary') {
            this.resumeData = setIn(this.resumeData, 'summary', value);
        } else {
            this.resumeData = setIn(this.resumeData, `personal.${path}`, value);
        }
    }

    handleEducationAdd(event) {
        const payload = event.detail || {};
        const id = payload.id || generateId();
        const newItem = {
            id,
            degree: payload.degree || '',
            school: payload.school || '',
            startYear: payload.startYear || '',
            endYear: payload.endYear || '',
            gpa: payload.gpa || ''
        };
        const education = [...(this.resumeData.education || []), newItem];
        this.resumeData = { ...this.resumeData, education };
    }

    handleEducationEdit(event) {
        const payload = event.detail || {};
        const education = (this.resumeData.education || []).map((e) => (e.id === payload.id ? { ...e, ...payload } : e));
        this.resumeData = { ...this.resumeData, education };
    }

    handleEducationRemove(event) {
        const id = event.detail?.id;
        if (!id) return;
        const education = (this.resumeData.education || []).filter((e) => e.id !== id);
        this.resumeData = { ...this.resumeData, education };
    }

    handleExperienceAdd(event) {
        const entry = event.detail || {};
        const id = entry.id || generateId();
        const experience = [...(this.resumeData.experience || []), { ...entry, id }];
        this.resumeData = { ...this.resumeData, experience };
    }

    handleExperienceEdit(event) {
        const entry = event.detail || {};
        const experience = (this.resumeData.experience || []).map((e) => (e.id === entry.id ? { ...e, ...entry } : e));
        this.resumeData = { ...this.resumeData, experience };
    }

    handleExperienceRemove(event) {
        const id = event.detail?.id;
        if (!id) return;
        const experience = (this.resumeData.experience || []).filter((e) => e.id !== id);
        this.resumeData = { ...this.resumeData, experience };
    }

    handleSkillAdd(event) {
        const value = (event.detail?.value || '').trim();
        if (!value) return;
        const skills = this.resumeData.skills || [];
        if (skills.map((s) => String(s).toLowerCase()).includes(value.toLowerCase())) return;
        this.resumeData = { ...this.resumeData, skills: [...skills, value] };
    }

    handleSkillRemove(event) {
        const value = event.detail?.value;
        if (value == null) return;
        const skills = (this.resumeData.skills || []).filter((s) => String(s) !== value);
        this.resumeData = { ...this.resumeData, skills };
    }

    handleCustomSectionAdd(event) {
        const detail = event.detail || {};
        const name = detail.name || 'Custom section';
        const customSections = [...(this.resumeData.customSections || []), { id: generateId(), name, items: [] }];
        this.resumeData = { ...this.resumeData, customSections };
    }

    handleNextStep() {
        if (this.currentStep === 2 && !this.canProceedFromStep2) return;
        if (this.currentStep < 3) this.currentStep++;
    }

    handlePreviousStep() {
        if (this.currentStep > 1) this.currentStep--;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel', { bubbles: true, composed: true }));
    }

    handleSaveResume() {
        this.dispatchEvent(
            new CustomEvent('saveresume', {
                detail: { resumeData: this.resumeData },
                bubbles: true,
                composed: true
            })
        );
    }
}