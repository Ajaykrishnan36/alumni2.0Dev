import { LightningElement, api, track } from 'lwc';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';

const PROFILE_CACHE_KEY = 'navigationMenu_profileCache';
const CACHE_DURATION_MS = 30 * 60 * 1000;

export default class KenResumePreview extends LightningElement {
    @api resumeData = {};
    @api selectedTemplate = 'new_york';
    @track defaultProfilePhotoUrl = defaultProfileImage;

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

    get isNewYork() { return this.selectedTemplate === 'new_york'; }
    get isToronto() { return this.selectedTemplate === 'toronto'; }
    get isModern() { return this.selectedTemplate === 'modern'; }
    get isClassic() { return this.selectedTemplate === 'classic'; }

    get personal() { return this.resumeData?.personal ?? {}; }
    get fullName() {
        const f = (this.personal.firstName || '').trim();
        const l = (this.personal.lastName || '').trim();
        return [f, l].filter(Boolean).join(' ').toUpperCase() || 'Your Name';
    }
    get roleTitle() {
        const exp = (this.resumeData?.experience ?? [])[0];
        return (exp?.title || '').trim() || 'Professional';
    }
    get contactLine() {
        const p = this.personal;
        const parts = [];
        if (p.phone) parts.push(p.phone);
        if (p.email) parts.push(p.email);
        if (p.city || p.country) parts.push([p.city, p.country].filter(Boolean).join(', '));
        return parts.join(' | ') || 'Phone | Email | City, Country';
    }
    get photoUrl() { return (this.personal?.photoUrl || '').trim(); }
    /** Use custom photo if set; otherwise same default profile image as Edit Details / nav */
    get displayPhotoUrl() {
        const custom = this.photoUrl;
        if (custom) return custom;
        return this.defaultProfilePhotoUrl || defaultProfileImage;
    }
    get hasPhoto() { return true; }
    get summary() { return (this.resumeData?.summary ?? '').trim(); }
    get hasSummary() { return this.summary.length > 0; }
    get educationList() {
        return (this.resumeData?.education ?? []).map((e) => ({
            ...e,
            yearRange: [e.startYear, e.endYear].filter(Boolean).join(' - ')
        }));
    }
    get hasEducation() { return this.educationList.length > 0; }
    get experienceList() {
        return (this.resumeData?.experience ?? []).map((e) => ({
            ...e,
            dateLabel: this.formatDateLabel(e.startDate, e.endDate, e.isCurrent)
        }));
    }
    get hasExperience() { return this.experienceList.length > 0; }
    get skillsText() {
        return (this.resumeData?.skills ?? []).join(' · ');
    }
    get hasSkills() { return (this.resumeData?.skills ?? []).length > 0; }

    formatDateLabel(startDate, endDate, isCurrent) {
        if (!startDate) return '';
        const s = new Date(startDate + '-01');
        if (isNaN(s.getTime())) return '';
        const startStr = s.toLocaleString('default', { month: 'short' }) + ' ' + s.getFullYear();
        if (isCurrent) return startStr + ' - Present';
        if (!endDate) return startStr;
        const e = new Date(endDate + '-01');
        return startStr + ' - ' + e.toLocaleString('default', { month: 'short' }) + ' ' + e.getFullYear();
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