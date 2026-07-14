// V2 wiring — calls OLD KenMyProfileController. Do not modify the OLD controller.
// If a DTO shape mismatch breaks rendering, fix it in this file's mapDto(), not in the controller.
import { LightningElement, api, track } from 'lwc';
import getMyProfile from '@salesforce/apex/KenMyProfileController.getMyProfile';
import saveEducation from '@salesforce/apex/KenMyProfileController.saveEducation';
import archiveEducation from '@salesforce/apex/KenMyProfileController.archiveEducation';
import saveExperience from '@salesforce/apex/KenMyProfileController.saveExperience';
import archiveExperience from '@salesforce/apex/KenMyProfileController.archiveExperience';
import saveAchievement from '@salesforce/apex/KenMyProfileController.saveAchievement';
import archiveAchievement from '@salesforce/apex/KenMyProfileController.archiveAchievement';
import saveAbout from '@salesforce/apex/KenMyProfileController.saveAbout';
import saveBasicInfo from '@salesforce/apex/KenMyProfileController.saveBasicInfo';
import saveContact from '@salesforce/apex/KenMyProfileController.saveContact';

const SF_ID_RE = /^[a-zA-Z0-9]{15,18}$/;
const isSfId = (v) => typeof v === 'string' && SF_ID_RE.test(v);
// NOTE: OLD KenMyProfileController.getMyProfile() is @AuraEnabled but NOT
// cacheable=true, so we call it imperatively rather than via @wire (LWR rejects
// non-cacheable methods in @wire with a 400). Never modify the OLD controller —
// keep this client-side call instead.

const TABS = [
    { id: 'about',        label: 'About Me' },
    { id: 'achievements', label: 'Achievements' },
    { id: 'payments',     label: 'Payments' }
];

// Payments controller not yet wired — return empty until backend is ready
// rather than flashing mock rows.
const PAYMENTS = [];

const BLANK_EDUCATION = {
    id: 0, degree: '', school: '', fieldOfStudy: '',
    startYear: '', endYear: '', description: '', grade: ''
};
const BLANK_EMPLOYMENT = {
    id: 0, role: '', company: '', employmentType: '', location: '',
    start: '', end: '', isCurrent: false, description: ''
};
const BLANK_ACHIEVEMENT = { id: 0, type: 'Honour / Award', title: '', org: '', year: '', description: '' };

// Values must match active PersonEmployment.EmploymentType picklist entries
// (verified against the org: Full-Time, Part-Time, Contract, Self-Employed, Temporary).
// Labels are user-facing; Apex normalizer is case-insensitive so capitalisation drift is safe.
const EMPLOYMENT_TYPE_OPTIONS = [
    { value: '',              label: 'Select type' },
    { value: 'Full-Time',     label: 'Full-time' },
    { value: 'Part-Time',     label: 'Part-time' },
    { value: 'Contract',      label: 'Contract' },
    { value: 'Temporary',     label: 'Temporary / Internship' },
    { value: 'Self-Employed', label: 'Self-Employed / Freelance' }
];

export default class KenMyProfileV2 extends LightningElement {
    @api userFirstName = '';
    @api userLastName = '';
    @api userBatch = '';

    @track activeView = 'profile';
    @track activeTab = 'about';

    // Scroll snapshots for back/restore between profile and edit/preview views.
    _scrollY = { profile: 0 };

    // Shared date formatter — '15 Jul 2026' style.
    formatDate(iso, withTime = false) {
        if (!iso) return '';
        const d = new Date(iso);
        if (isNaN(d.getTime())) return '';
        const opts = { day: '2-digit', month: 'short', year: 'numeric' };
        if (withTime) { opts.hour = '2-digit'; opts.minute = '2-digit'; opts.hour12 = true; }
        try { return d.toLocaleDateString('en-IN', opts); } catch (e) { return ''; }
    }
    // Arrays start empty so no mock flash. They stay empty if Apex returns nothing.
    @track education = [];
    @track employment = [];
    @track editingItem = { ...BLANK_EDUCATION };
    @track resumeName = '';
    @track resumeHeadline = '';
    @track resumeSummary = '';
    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer = null;
    // Block double-click while an Apex write is in flight.
    @track isSavingEducation = false;
    @track isSavingEmployment = false;
    @track isSavingAchievement = false;
    @track isSavingAbout = false;
    @track isSavingBasicInfo = false;
    @track isSavingContact = false;

    // Basic Info / Contact modal state. Editing copies live in editingBasicInfo
    // / editingContact so users can cancel without mutating the live profile.
    @track showBasicInfoModal = false;
    @track showContactModal = false;
    @track editingBasicInfo = {
        firstName: '', lastName: '', title: '', company: '', location: '',
        batch: '', expertise: '', willingToHelp: true, linkedin: ''
    };
    @track editingContact = { email: '', phone: '' };

    /* ===== OLD Apex wiring (KenMyProfileController.getMyProfile) ===== */
    @track profile = null;
    @track profileError = null;
    @track isLoading = true;
    @track contactEmail = '';
    @track contactPhone = '';
    @track contactLinkedin = '';
    @track headlineRole = '';
    @track headlineLocation = '';
    profileLoaded = false;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const view = params.get('view');
            const edit = params.get('edit');
            const VALID_TABS = ['about', 'achievements', 'payments'];
            const VALID_VIEWS = ['profile', 'editEducation', 'editEmployment', 'resumeBuilder', 'resumeEdit', 'resumePreview'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.activeTab = tab;
            if (view && VALID_VIEWS.indexOf(view) > -1) this.activeView = view;
            // Deep-link from the Home "Finish setup" checklist (e.g. ?edit=photo).
            // Remembered until the profile finishes loading, then auto-opens the modal.
            if (edit) this._pendingEdit = String(edit).toLowerCase();
        } catch (e) { /* ignore */ }
        this.loadProfile();
    }

    // Auto-open the relevant edit modal once profile data is in memory. The
    // Basic Info modal is the editor for name/company/city/batch/grad/LinkedIn
    // (and is the closest available editor for the photo deep-link).
    _pendingEdit = null;
    _applyPendingEdit() {
        const e = this._pendingEdit;
        if (!e) return;
        this._pendingEdit = null;
        if (['basic', 'photo', 'company', 'linkedin', 'city', 'location', 'grad', 'batch'].indexOf(e) > -1) {
            this.handleOpenBasicInfoModal();
        } else if (e === 'contact') {
            this.handleOpenContactModal();
        } else if (e === 'about' || e === 'interests') {
            this.activeTab = 'about';
        }
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeTab) params.set('tab', this.activeTab); else params.delete('tab');
            if (this.activeView && this.activeView !== 'profile') params.set('view', this.activeView); else params.delete('view');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    loadProfile() {
        this.isLoading = true;
        getMyProfile()
            .then(data => {
                if (data) {
                    this.applyProfile(this.mapDto(data));
                    this.profileError = null;
                }
                this.profileLoaded = true;
                this.isLoading = false;
                // Now that fields are populated, honour any ?edit= deep-link.
                this._applyPendingEdit();
            })
            .catch(err => {
                // Apex failed — surface empty state (per UX rule: never flash mock data).
                this.profileError = err;
                this.profileLoaded = true;
                this.isLoading = false;
                this.education = [];
                this.employment = [];
                this.achievements = [];
                // eslint-disable-next-line no-console
                console.error('KenMyProfileController.getMyProfile error', err);
            });
    }

    get hasEducation() { return (this.education || []).length > 0; }
    get hasEmployment() { return (this.employment || []).length > 0; }
    get hasAchievements() { return (this.achievements || []).length > 0; }
    get showEducationEmpty() { return !this.isLoading && !this.hasEducation; }
    get showEmploymentEmpty() { return !this.isLoading && !this.hasEmployment; }
    get showAchievementsEmpty() { return !this.isLoading && !this.hasAchievements; }

    // Translate OLD ProfileData DTO into the shape the existing HTML expects.
    mapDto(dto) {
        if (!dto) return null;
        const fullName = (dto.name || '').trim();
        const parts = fullName.split(/\s+/);
        const firstName = parts.shift() || '';
        const lastName = parts.join(' ');

        const education = (dto.education || []).map(e => {
            const startY = e.startYear || '';
            const endY = e.endYear || '';
            const dateLabel = (startY && endY) ? `${startY} - ${endY}`
                : (startY || endY || e.duration || '');
            return {
                id: e.id,
                degree: e.degree || '',
                school: e.institution || '',
                fieldOfStudy: e.fieldOfStudy || '',
                startYear: startY,
                endYear: endY,
                year: e.duration || [startY, endY].filter(Boolean).join(' – '),
                dateLabel,
                description: e.description || '',
                grade: e.score || (e.cgpa ? String(e.cgpa) : '')
            };
        });

        const employment = (dto.experience || []).map(x => {
            const dur = x.duration || '';
            let start = '';
            let end = '';
            if (dur.includes(' - ')) {
                [start, end] = dur.split(' - ');
            } else if (dur) {
                start = dur;
            }
            const isCurrent = !!x.isCurrentJob;
            return {
                id: x.id,
                role: x.position || '',
                company: x.company || '',
                employmentType: x.employmentType || '',
                location: x.location || '',
                start: start || '',
                end: end || (isCurrent ? 'Present' : ''),
                dateLabel: dur || [start, end || (isCurrent ? 'Present' : '')].filter(Boolean).join(' - '),
                isCurrent,
                description: x.description || ''
            };
        });

        const achievements = (dto.achievements || []).map(a => ({
            id: a.id,
            kind: a.type || '',
            title: a.title || '',
            org: a.organization || '',
            year: a.dateYear || '',
            description: a.description || ''
        }));

        return {
            accountId: dto.accountId,
            firstName,
            lastName,
            batch: dto.batch || '',
            about: dto.about || '',
            email: dto.email || '',
            phone: dto.phone || '',
            linkedin: dto.linkedin || '',
            headlineRole: dto.title || dto.expertise || '',
            headlineLocation: dto.location || '',
            education,
            employment,
            achievements
        };
    }

    applyProfile(p) {
        if (!p) return;
        this.profile = p;
        // Always assign (use empty string fallback) so that clearing a field server-side
        // also clears the local reactive value — important for instant re-render after
        // Basic Info / Contact / About edits where the user may blank a field.
        this.userFirstName = p.firstName || '';
        this.userLastName = p.lastName || '';
        this.userBatch = p.batch ? String(p.batch).replace(/^Batch\s+/i, '') : '';
        if (Array.isArray(p.education)) this.education = p.education;
        if (Array.isArray(p.employment)) this.employment = p.employment;
        if (Array.isArray(p.achievements)) this.achievements = p.achievements;
        this.resumeSummary = p.about || '';
        this.contactEmail = p.email || '';
        this.contactPhone = p.phone || '';
        this.contactLinkedin = p.linkedin || '';
        this.headlineRole = p.headlineRole || '';
        this.headlineLocation = p.headlineLocation || '';
        this.resumeName = `${p.firstName || ''} ${p.lastName || ''}`.trim();
        this.resumeHeadline = p.headlineRole || '';
    }

    refreshProfile() {
        // Imperative refetch — replaces the old refreshApex(wiredResult) pattern
        // now that we're not using @wire (OLD method isn't cacheable).
        return this.loadProfile();
    }

    // All save methods are wired imperatively below (saveEducation / saveExperience /
    // saveAchievement / saveAbout / saveBasicInfo / saveContact). After each successful
    // write we call refreshProfile() which re-fetches and reassigns this.profile,
    // so the hero card + About + Contact + lists refresh instantly without a page reload.


    /* ===== Getters ===== */
    get userFullName() { return `${this.userFirstName} ${this.userLastName}`.trim(); }
    get resumeContact() {
        return [this.contactEmail, this.contactPhone, this.contactLinkedin]
            .filter(Boolean).join('  ·  ');
    }
    get userInitial()  { return (this.userFirstName || ' ').charAt(0).toUpperCase(); }

    get isProfileView()       { return this.activeView === 'profile'; }
    get isEditEducation()     { return this.activeView === 'editEducation'; }
    get isEditEmployment()    { return this.activeView === 'editEmployment'; }
    get isResumeBuilder()     { return this.activeView === 'resumeBuilder'; }
    get isResumeEdit()        { return this.activeView === 'resumeEdit'; }
    get isResumePreview()     { return this.activeView === 'resumePreview'; }

    get tabs() {
        return TABS.map(t => ({
            ...t,
            cssClass: t.id === this.activeTab ? 'tab tab--active' : 'tab'
        }));
    }
    get isAboutTab()        { return this.activeTab === 'about'; }
    get isAchievementsTab() { return this.activeTab === 'achievements'; }
    get isPaymentsTab()     { return this.activeTab === 'payments'; }

    @track achievements = [];
    @track showAchievementModal = false;
    @track editingAchievement = { ...BLANK_ACHIEVEMENT };
    get payments() { return PAYMENTS; }
    get hasPayments() { return (this.payments || []).length > 0; }
    get showPaymentsEmpty() { return !this.isLoading && !this.hasPayments; }

    get editingTitle() {
        if (this.activeView === 'editEducation') {
            return this.editingItem.id ? 'Edit Education' : 'Add Education';
        }
        return this.editingItem.id ? 'Edit Experience' : 'Add Experience';
    }

    get employmentTypeOptions() {
        const selected = (this.editingItem && this.editingItem.employmentType) || '';
        return EMPLOYMENT_TYPE_OPTIONS.map(opt => ({
            ...opt,
            selected: opt.value === selected
        }));
    }
    get educationSaveLabel() { return this.isSavingEducation ? 'Saving...' : 'Save'; }
    get employmentSaveLabel() { return this.isSavingEmployment ? 'Saving...' : 'Save'; }

    /* ===== Handlers ===== */
    handleTab(event) { this.activeTab = event.currentTarget.dataset.id; this.syncUrl(); }

    // Parse '2018 – 2022' / '2018-2022' / '2018' into { startYear, endYear }.
    // Accepts en-dash, em-dash, hyphen, ' to ', or whitespace separators.
    _parseYearRange(raw) {
        const s = (raw || '').toString().trim();
        if (!s) return { startYear: '', endYear: '' };
        const matches = s.match(/\b(19|20)\d{2}\b/g) || [];
        return { startYear: matches[0] || '', endYear: matches[1] || '' };
    }
    // Parse 'Mar 2022' / 'March 2022' / '2022-03' / '2022' into { month, year }.
    _parseMonthYear(raw) {
        const s = (raw || '').toString().trim();
        if (!s) return { month: '', year: '' };
        if (/^present$/i.test(s)) return { month: '', year: '' };
        const MONTHS = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
        const yearMatch = s.match(/\b(19|20)\d{2}\b/);
        const year = yearMatch ? yearMatch[0] : '';
        const monthToken = (s.match(/[A-Za-z]+/) || [''])[0].slice(0, 3).toLowerCase();
        const mIdx = MONTHS.indexOf(monthToken);
        const month = mIdx >= 0 ? String(mIdx + 1) : '';
        return { month, year };
    }

    _resolveId(rawId, list) {
        // dataset.id is always a string. Match against numeric mock ids OR SF string ids.
        const found = list.find(x => String(x.id) === String(rawId));
        return found ? found.id : null;
    }

    handleAddEducation() {
        this.editingItem = { ...BLANK_EDUCATION };
        this.activeView = 'editEducation'; this.syncUrl();
    }
    handleEditEducation(event) {
        const raw = event.currentTarget.dataset.id;
        const id = this._resolveId(raw, this.education);
        const found = this.education.find(e => e.id === id);
        this.editingItem = found ? { ...found } : { ...BLANK_EDUCATION };
        this.activeView = 'editEducation'; this.syncUrl();
    }
    handleDeleteEducation(event) {
        const raw = event.currentTarget.dataset.id;
        const id = this._resolveId(raw, this.education);
        const previous = this.education;
        this.education = this.education.filter(e => e.id !== id);
        if (isSfId(id)) {
            archiveEducation({ recordId: id })
                .then(() => { this._showToast('Education removed'); })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenMyProfileController.archiveEducation error', err);
                    this.education = previous;
                    this._showToast((err && err.body && err.body.message) || 'Could not remove. Please try again.');
                });
        } else {
            this._showToast('Education removed');
        }
    }
    handleAddEmployment() {
        this.editingItem = { ...BLANK_EMPLOYMENT };
        this.activeView = 'editEmployment'; this.syncUrl();
    }
    handleEditEmployment(event) {
        const raw = event.currentTarget.dataset.id;
        const id = this._resolveId(raw, this.employment);
        const found = this.employment.find(e => e.id === id);
        this.editingItem = found ? { ...found } : { ...BLANK_EMPLOYMENT };
        this.activeView = 'editEmployment'; this.syncUrl();
    }
    handleDeleteEmployment(event) {
        const raw = event.currentTarget.dataset.id;
        const id = this._resolveId(raw, this.employment);
        const previous = this.employment;
        this.employment = this.employment.filter(e => e.id !== id);
        if (isSfId(id)) {
            archiveExperience({ recordId: id })
                .then(() => { this._showToast('Experience removed'); })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenMyProfileController.archiveExperience error', err);
                    this.employment = previous;
                    this._showToast((err && err.body && err.body.message) || 'Could not remove. Please try again.');
                });
        } else {
            this._showToast('Experience removed');
        }
    }
    handleEditField(event) {
        const f = event.target.dataset.field;
        const t = event.target;
        const isCheckbox = t && t.type === 'checkbox';
        const value = isCheckbox ? !!t.checked : t.value;
        const patch = { [f]: value };
        // If user toggles "Currently Working", clear end date so the form/Apex don't
        // try to save a stale end date alongside isCurrent=true.
        if (f === 'isCurrent' && value === true) {
            patch.end = '';
        }
        this.editingItem = { ...this.editingItem, ...patch };
    }
    handleSaveEducation() {
        if (this.isSavingEducation) return;
        const item = this.editingItem;
        if (!item.degree || !item.school) { this._showToast('Please fill in degree and school'); return; }
        // Per-year inputs in the new form; tolerate users typing 'Present' in end year.
        const rawStart = (item.startYear || '').toString().trim();
        const rawEnd = (item.endYear || '').toString().trim();
        const startYear = (rawStart.match(/\b(19|20)\d{2}\b/) || [''])[0];
        const endIsPresent = /^present$/i.test(rawEnd);
        const endYear = endIsPresent ? '' : (rawEnd.match(/\b(19|20)\d{2}\b/) || [''])[0];
        const input = {
            // Only pass id if it's a real SF id; mock ids (numeric) trigger insert path in Apex.
            id: isSfId(item.id) ? item.id : null,
            degree: item.degree || '',
            institution: item.school || '',
            fieldOfStudy: item.fieldOfStudy || '',
            description: item.description || '',
            // PersonEducation.StartDate/EndDate require month+year; default month to Jan so
            // year-only inputs still round-trip a valid date.
            startMonth: startYear ? '01' : '',
            startYear,
            endMonth: endYear ? '01' : '',
            endYear,
            gradingFormat: '',
            cgpa: item.grade || ''
        };
        this.isSavingEducation = true;
        saveEducation({ input })
            .then(() => {
                this.activeView = 'profile'; this.syncUrl();
                this._showToast('Education saved');
                return this.refreshProfile();
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMyProfileController.saveEducation error', err);
                this._showToast((err && err.body && err.body.message) || 'Could not save. Please try again.');
            })
            .finally(() => { this.isSavingEducation = false; });
    }
    handleSaveEmployment() {
        if (this.isSavingEmployment) return;
        const item = this.editingItem;
        if (!item.role || !item.company) { this._showToast('Please fill in role and company'); return; }
        const startMY = this._parseMonthYear(item.start);
        const endMY = this._parseMonthYear(item.end);
        const isCurrent = item.isCurrent === true || (item.end || '').toLowerCase() === 'present';
        const input = {
            id: isSfId(item.id) ? item.id : null,
            jobTitle: item.role || '',
            organization: item.company || '',
            employmentType: item.employmentType || '',
            location: item.location || '',
            roleDescription: item.description || '',
            startMonth: startMY.month,
            startYear: startMY.year,
            endMonth: isCurrent ? '' : endMY.month,
            endYear: isCurrent ? '' : endMY.year,
            isCurrentJob: isCurrent
        };
        this.isSavingEmployment = true;
        saveExperience({ input })
            .then(() => {
                this.activeView = 'profile'; this.syncUrl();
                this._showToast('Experience saved');
                return this.refreshProfile();
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMyProfileController.saveExperience error', err);
                this._showToast((err && err.body && err.body.message) || 'Could not save. Please try again.');
            })
            .finally(() => { this.isSavingEmployment = false; });
    }
    handleCancelEdit() { this.activeView = 'profile'; this.syncUrl(); }

    handleOpenResumeBuilder() {
        try { this._scrollY.profile = window.scrollY || 0; } catch (e) { /* ignore */ }
        this.activeView = 'resumeBuilder'; this.syncUrl();
        try { window.scrollTo({ top: 0, behavior: 'auto' }); } catch (e) { /* ignore */ }
    }
    handleOpenResumeEdit() { this.activeView = 'resumeEdit'; this.syncUrl(); }
    handleOpenResumePreview() { this.activeView = 'resumePreview'; this.syncUrl(); }
    handleCloseResume() {
        this.activeView = 'profile'; this.syncUrl();
        try {
            const y = this._scrollY.profile || 0;
            requestAnimationFrame(() => { try { window.scrollTo({ top: y, behavior: 'auto' }); } catch (e) { /* ignore */ } });
        } catch (e) { /* ignore */ }
    }
    handleResumeField(event) {
        const f = event.target.dataset.field;
        this[f] = event.target.value;
    }
    handleSaveResume() {
        // "Edit Resume Details" persists THREE things: Display name + Headline
        // (Person Account FirstName/LastName/PersonTitle via saveBasicInfo) and the
        // Summary (Account.Description via saveAbout). Previously only the summary
        // was saved, so display-name edits silently vanished.
        if (this.isSavingAbout) return;
        const fullName = (this.resumeName || '').trim();
        if (!fullName) { this._showToast('Display name is required.'); return; }

        // Person Account stores name as separate fields — split on the first space.
        const nameParts = fullName.split(/\s+/);
        const firstName = nameParts.shift() || '';
        const lastName = nameParts.join(' ');

        const aboutText = (this.resumeSummary || '').trim();
        const headline = (this.resumeHeadline || '').trim();

        // Send ONLY name + headline so saveBasicInfo's null-guards leave the other
        // CRM fields (company/location/batch/expertise/linkedin) untouched — passing
        // '' for those would wipe them.
        const basicInput = { firstName, lastName, title: headline };

        this.isSavingAbout = true;
        // Sequential writes to the same Account row (name/title, then About) avoid
        // UNABLE_TO_LOCK_ROW from concurrent updates of the same record.
        saveBasicInfo({ input: basicInput })
            .then(() => saveAbout({ aboutText }))
            .then(() => {
                // Return to the profile view so the user immediately sees the updated hero.
                this.activeView = 'profile'; this.syncUrl();
                this._showToast('Profile updated');
                return this.refreshProfile();
            })
            .then(() => { this._syncShellIdentity(); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMyProfileController saveResume error', err);
                this._showToast((err && err.body && err.body.message) || 'Could not save. Please try again.');
            })
            .finally(() => { this.isSavingAbout = false; });
    }

    // Push the freshly-saved identity into the shell sidebar + topbar (the shell is
    // a child of this component but loads its own identity once on mount, so it must
    // be told to update — otherwise the sidebar name/initials go stale until reload).
    _syncShellIdentity() {
        try {
            const shell = this.template.querySelector('c-ken42-alumni-shell-v2');
            if (shell && typeof shell.refreshIdentity === 'function') {
                shell.refreshIdentity({
                    firstName: this.userFirstName,
                    lastName: this.userLastName,
                    batch: this.userBatch
                });
            }
        } catch (e) { /* non-fatal — hero already updated via refreshProfile */ }
    }
    handleDownloadPdf() { this._showToast('Preparing PDF download...'); }

    /* ===== Basic Info modal ===== */
    handleOpenBasicInfoModal() {
        // Seed the editing copy from current profile + reactive fields so the
        // user sees what's persisted, not a stale snapshot.
        this.editingBasicInfo = {
            firstName: this.userFirstName || '',
            lastName: this.userLastName || '',
            title: this.headlineRole || '',
            company: (this.profile && this.profile.company) || '',
            location: this.headlineLocation || '',
            batch: this.userBatch || '',
            expertise: (this.profile && this.profile.expertise) || '',
            willingToHelp: this.profile ? !!this.profile.willingToHelp : true,
            linkedin: this.contactLinkedin || ''
        };
        this.showBasicInfoModal = true;
    }
    handleCloseBasicInfoModal() { this.showBasicInfoModal = false; }
    handleBasicInfoField(event) {
        const f = event.target.dataset.field;
        const t = event.target;
        const isCheckbox = t && t.type === 'checkbox';
        const value = isCheckbox ? !!t.checked : t.value;
        this.editingBasicInfo = { ...this.editingBasicInfo, [f]: value };
    }
    handleSaveBasicInfo() {
        if (this.isSavingBasicInfo) return;
        const b = this.editingBasicInfo;
        // Person Account requires LastName — surface this before the round-trip
        // so the user gets an inline message instead of a REQUIRED_FIELD_MISSING toast.
        if (!(b.lastName || '').toString().trim()) {
            this._showToast('Last name is required.');
            return;
        }
        const input = {
            firstName: (b.firstName || '').toString().trim(),
            lastName: (b.lastName || '').toString().trim(),
            title: (b.title || '').toString().trim(),
            company: (b.company || '').toString().trim(),
            location: (b.location || '').toString().trim(),
            batch: (b.batch || '').toString().trim(),
            expertise: (b.expertise || '').toString().trim(),
            willingToHelp: b.willingToHelp === true,
            linkedin: (b.linkedin || '').toString().trim()
        };
        this.isSavingBasicInfo = true;
        saveBasicInfo({ input })
            .then(() => {
                this.showBasicInfoModal = false;
                this._showToast('Profile updated');
                return this.refreshProfile();
            })
            .then(() => { this._syncShellIdentity(); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMyProfileController.saveBasicInfo error', err);
                this._showToast((err && err.body && err.body.message) || 'Could not save. Please try again.');
            })
            .finally(() => { this.isSavingBasicInfo = false; });
    }

    /* ===== Contact modal ===== */
    handleOpenContactModal() {
        this.editingContact = {
            email: this.contactEmail || '',
            phone: this.contactPhone || ''
        };
        this.showContactModal = true;
    }
    handleCloseContactModal() { this.showContactModal = false; }
    handleContactField(event) {
        const f = event.target.dataset.field;
        this.editingContact = { ...this.editingContact, [f]: event.target.value };
    }
    handleSaveContact() {
        if (this.isSavingContact) return;
        const c = this.editingContact;
        const input = {
            email: (c.email || '').toString().trim(),
            phone: (c.phone || '').toString().trim()
        };
        this.isSavingContact = true;
        saveContact({ input })
            .then(() => {
                this.showContactModal = false;
                this._showToast('Contact updated');
                return this.refreshProfile();
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMyProfileController.saveContact error', err);
                this._showToast((err && err.body && err.body.message) || 'Could not save. Please try again.');
            })
            .finally(() => { this.isSavingContact = false; });
    }

    get basicInfoSaveLabel() { return this.isSavingBasicInfo ? 'Saving...' : 'Save'; }
    get contactSaveLabel() { return this.isSavingContact ? 'Saving...' : 'Save'; }

    handleShare() { this._showToast('Profile link copied'); }
    handleViewIdCard() {
        // If the alumni's ID Card URL was generated server-side (KenAlumniIdCardQueueable),
        // open it in a new tab. Otherwise let the user know it's still being generated.
        const url = this.profile && this.profile.idCardUrl;
        if (url) {
            try { window.open(url, '_blank', 'noopener'); } catch (e) { /* ignore */ }
            return;
        }
        this._showToast('Your Alumni ID Card is still being generated. Check back shortly.');
    }

    handleAddAchievement() {
        this.editingAchievement = { ...BLANK_ACHIEVEMENT };
        this.showAchievementModal = true;
    }
    handleEditAchievement(event) {
        const raw = event.currentTarget.dataset.id;
        const id = this._resolveId(raw, this.achievements);
        const found = this.achievements.find(a => a.id === id);
        this.editingAchievement = found
            ? { id: found.id, type: found.kind || 'Honour / Award', title: found.title || '', org: found.org || '', year: found.year || '', description: found.description || '' }
            : { ...BLANK_ACHIEVEMENT };
        this.showAchievementModal = true;
    }
    handleCloseAchievementModal() { this.showAchievementModal = false; }
    handleAchievementSave(event) {
        if (this.isSavingAchievement) return;
        const d = (event && event.detail) || {};
        if (!(d.title || '').toString().trim()) {
            this._showToast('Please enter a title.');
            return;
        }
        const input = {
            // Only pass id if it's a real SF id — mock/tmp ids must go through insert.
            id: isSfId(d.id) ? d.id : null,
            type: d.type || '',
            title: (d.title || '').toString().trim(),
            organization: (d.org || '').toString().trim(),
            dateYear: d.year ? String(d.year) : '',
            description: (d.description || '').toString().trim()
        };
        this.isSavingAchievement = true;
        saveAchievement({ input })
            .then(() => {
                this.showAchievementModal = false;
                this._showToast('Achievement saved');
                return this.refreshProfile();
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMyProfileController.saveAchievement error', err);
                this._showToast((err && err.body && err.body.message) || 'Could not save. Please try again.');
            })
            .finally(() => { this.isSavingAchievement = false; });
    }
    handleDeleteAchievement(event) {
        const raw = event.currentTarget.dataset.id;
        const id = this._resolveId(raw, this.achievements);
        const previous = this.achievements;
        this.achievements = this.achievements.filter(a => a.id !== id);
        if (isSfId(id)) {
            archiveAchievement({ recordId: id })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenMyProfileController.archiveAchievement error', err);
                    this.achievements = previous;
                    this._showToast((err && err.body && err.body.message) || 'Could not remove. Please try again.');
                });
        }
    }

    _showToast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }
    handleBackdropClick(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.activeView = 'profile'; this.syncUrl();
        }
    }
    handleStopProp(event) { event.stopPropagation(); }

    disconnectedCallback() {
        if (this._toastTimer) clearTimeout(this._toastTimer);
    }
}