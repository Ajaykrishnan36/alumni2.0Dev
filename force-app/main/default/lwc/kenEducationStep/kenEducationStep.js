import { LightningElement, track } from 'lwc';
import getMyProfile from '@salesforce/apex/KenMyProfileController.getMyProfile';
import saveEducationRecord from '@salesforce/apex/KenMyProfileController.saveEducation';
import archiveEducationRecord from '@salesforce/apex/KenMyProfileController.archiveEducation';
import getBasicProfile from '@salesforce/apex/KenPortalOnbordingController.getBasicProfile';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenEducationStep extends LightningElement {
    @track educationList = [];
    @track showModal = false;
    @track selectedRecord = null;
    @track isLoading = false;
    @track loadingText = 'Loading...';
    @track hasUserChange = false;
    showActions = true;
    _seedRecordId = null;
    _completingSeed = false;

    get hasEducation() {
        return this.educationList.length > 0;
    }

    get isSaveNextDisabled() {
        return !this.hasUserChange;
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {});
        this.loadEducationData(true)
            .then(() => this._maybeImportFromLinkedIn())
            .then(() => this._maybeSeedFromProfile());
    }

    /**
     * When the alumnus reaches Step 2 with no education rows yet, seed one
     * partially-filled entry from Step 1: own-institute type, the chosen
     * Program Plan, and the graduation year as the end year. The user can
     * delete it or open it to finish the remaining fields. One-shot per
     * browser session so a deleted seed is not recreated on revisit.
     */
    async _maybeSeedFromProfile() {
        if (this.educationList && this.educationList.length > 0) return;
        try {
            if (window.sessionStorage.getItem('educationSeedApplied') === '1') return;
        } catch (e) {
            return;
        }
        // Re-confirm against the server before seeding — a failed or stale list
        // load must never produce a duplicate seed next to existing records.
        try {
            const current = await getMyProfile();
            const existing = current?.education || [];
            if (existing.length > 0) {
                this.educationList = existing.map(edu => ({ ...edu }));
                return;
            }
        } catch (e) {
            return;
        }
        let roleId = null;
        try { roleId = window.localStorage.getItem('ConstituentRoleId') || null; } catch (e) { /* ignore */ }

        let profile;
        try {
            profile = await getBasicProfile({ roleId });
        } catch (e) {
            return;
        }
        const programPlan = profile?.programmeId || null;
        const endYear = profile?.graduationYear || null;
        if (!programPlan && !endYear) return;

        this.loadingText = 'Preparing your education...';
        this.isLoading = true;
        try {
            await saveEducationRecord({
                input: {
                    id: null,
                    degree: '',
                    institution: profile?.institutionName || '',
                    institutionType: 'institute',
                    programPlan,
                    registrationNumber: null,
                    startMonth: null,
                    startYear: null,
                    endMonth: null,
                    endYear,
                    gradingFormat: 'CGPA',
                    cgpa: ''
                }
            });
            try { window.sessionStorage.setItem('educationSeedApplied', '1'); } catch (e) { /* ignore */ }
            await this.loadEducationData(false);
            const seeded = this.educationList.find(edu => !(edu.degree || '').trim());
            if (seeded) {
                this._rememberSeedId(seeded.id);
            }
            this.hasUserChange = true;
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error('Education pre-fill from profile failed', err);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * If the alumnus dropped a LinkedIn URL on Step 1 and we have the cached
     * preview, push each education row into Salesforce on Step 2 entry so the
     * list renders pre-filled. One-shot per browser session.
     */
    async _maybeImportFromLinkedIn() {
        if (this.educationList && this.educationList.length > 0) return;
        let raw;
        try { raw = window.sessionStorage.getItem('linkedinImportPreview'); } catch (e) { return; }
        if (!raw) return;
        if (window.sessionStorage.getItem('linkedinEducationApplied') === '1') return;
        let profile;
        try { profile = JSON.parse(raw); } catch (e) { return; }
        const edus = (profile && profile.education) || [];
        if (!edus.length) return;
        this.loadingText = 'Importing education from LinkedIn...';
        this.isLoading = true;
        try {
            for (const e of edus) {
                const sa = e.starts_at || {};
                const ea = e.ends_at   || {};
                await saveEducationRecord({
                    input: {
                        id: null,
                        degree: e.degree_name || e.field_of_study || '',
                        institution: e.school || '',
                        startMonth: sa.month ? String(sa.month).padStart(2, '0') : null,
                        startYear:  sa.year ? String(sa.year) : null,
                        endMonth:   ea.month ? String(ea.month).padStart(2, '0') : null,
                        endYear:    ea.year ? String(ea.year) : null,
                        gradingFormat: 'CGPA',
                        cgpa: e.grade || ''
                    }
                });
            }
            try { window.sessionStorage.setItem('linkedinEducationApplied', '1'); } catch (ex) { /* ignore */ }
            await this.loadEducationData(false);
            this.dispatchEvent(new CustomEvent('notify', {
                detail: { type: 'success', title: 'Imported from LinkedIn', message: `${edus.length} education ${edus.length === 1 ? 'entry' : 'entries'} added from LinkedIn.` },
                bubbles: true, composed: true
            }));
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error('LinkedIn education import failed', err);
        } finally {
            this.isLoading = false;
        }
    }

    async loadEducationData(showLoader = false) {
        if (showLoader) {
            this.loadingText = 'Loading education...';
            this.isLoading = true;
        }
        try {
            const profile = await getMyProfile();
            this.educationList = (profile?.education || []).map(edu => ({ ...edu }));
        } catch (e) {
            console.error('Error loading education data', e);
            this.educationList = [];
        } finally {
            if (showLoader) {
                this.isLoading = false;
            }
        }
    }

    handleAdd() {
        this.selectedRecord = null;
        this.showModal = true;
    }

    handleEdit(event) {
        const id = event.detail?.id;
        const found = this.educationList.find(edu => String(edu.id) === String(id));
        if (found) {
            this.selectedRecord = { ...found };
            this.showModal = true;
        }
    }

    // The education card component already confirms the delete via its own
    // popup, so archive immediately here — no second confirmation dialog.
    async handleDeleteRequest(event) {
        const id = event.detail?.id;
        if (!id) return;
        this.loadingText = 'Deleting education...';
        this.isLoading = true;
        try {
            await archiveEducationRecord({ recordId: id });
            this.educationList = this.educationList.filter(edu => String(edu.id) !== String(id));
            if (this._seedRecordId && String(this._seedRecordId) === String(id)) {
                this._clearSeedId();
            }
            this.hasUserChange = true;
        } catch (e) {
            const msg = e?.body?.message || 'Unable to delete education record.';
            this.dispatchNotify('error', 'Error', msg);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * The auto-seeded record must be completed before moving on. Save & Next
     * opens it in the modal instead of advancing; saving it advances, while
     * cancelling deletes the partial seed and then advances.
     */
    _rememberSeedId(recordId) {
        this._seedRecordId = recordId;
        try { window.sessionStorage.setItem('educationSeedRecordId', String(recordId)); } catch (e) { /* ignore */ }
    }

    _clearSeedId() {
        this._seedRecordId = null;
        try { window.sessionStorage.removeItem('educationSeedRecordId'); } catch (e) { /* ignore */ }
    }

    _restoreSeedId() {
        if (this._seedRecordId) return;
        try { this._seedRecordId = window.sessionStorage.getItem('educationSeedRecordId') || null; } catch (e) { /* ignore */ }
    }

    _findIncompleteSeed() {
        this._restoreSeedId();
        if (!this._seedRecordId) return null;
        const row = this.educationList.find(edu => String(edu.id) === String(this._seedRecordId));
        if (!row) {
            this._clearSeedId();
            return null;
        }
        if ((row.degree || '').trim()) {
            this._clearSeedId();
            return null;
        }
        return row;
    }

    _proceedToNextStep() {
        this.dispatchEvent(new CustomEvent('saveandnext', { bubbles: true, composed: true }));
    }

    async handleModalClose() {
        this.showModal = false;
        this.selectedRecord = null;
        if (!this._completingSeed) return;
        this._completingSeed = false;

        const seed = this._findIncompleteSeed();
        if (seed) {
            this.loadingText = 'Removing incomplete education...';
            this.isLoading = true;
            try {
                await archiveEducationRecord({ recordId: seed.id });
                this.educationList = this.educationList.filter(edu => String(edu.id) !== String(seed.id));
                this._clearSeedId();
            } catch (e) {
                const msg = e?.body?.message || 'Unable to remove the incomplete education record.';
                this.dispatchNotify('error', 'Error', msg);
                this.isLoading = false;
                return;
            }
            this.isLoading = false;
        }
        this._proceedToNextStep();
    }

    async handleModalSave(event) {
        const d = event.detail || {};
        this.showModal = false;
        this.selectedRecord = null;
        const isEdit = !!d.id;
        this.loadingText = isEdit ? 'Updating education...' : 'Saving education...';
        this.isLoading = true;
        try {
            await saveEducationRecord({
                input: {
                    id: d.id || null,
                    degree: d.degree || '',
                    institution: d.institution || '',
                    institutionType: d.institutionType || 'institute',
                    programPlan: d.programPlan || null,
                    registrationNumber: d.registrationNumber || null,
                    startMonth: d.startMonth || null,
                    startYear: d.startYear || null,
                    endMonth: d.endMonth || null,
                    endYear: d.endYear || null,
                    gradingFormat: d.gradingFormat || 'CGPA',
                    cgpa: d.cgpa || ''
                }
            });
            await this.loadEducationData(false);
            this.hasUserChange = true;
            this.isLoading = false;
            this.dispatchNotify('success', isEdit ? 'Education Updated!' : 'Education Added!', '');
            if (this._completingSeed) {
                this._completingSeed = false;
                this._clearSeedId();
                this._proceedToNextStep();
            }
        } catch (e) {
            this.isLoading = false;
            this._completingSeed = false;
            const msg = e?.body?.message || 'Unable to save education record.';
            this.dispatchNotify('error', 'Error', msg);
        }
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent('previous', { bubbles: true, composed: true }));
    }

    handleSkip() {
        this.dispatchEvent(new CustomEvent('skip', { bubbles: true, composed: true }));
    }

    handleSaveAndNext() {
        const seed = this._findIncompleteSeed();
        if (seed) {
            this._completingSeed = true;
            this.selectedRecord = { ...seed };
            this.showModal = true;
            this.dispatchNotify('info', 'Complete your education', 'Fill in the remaining details, or cancel to remove this entry.');
            return;
        }
        this._proceedToNextStep();
    }

    dispatchNotify(type, title, message) {
        this.dispatchEvent(new CustomEvent('notify', {
            detail: { type, title, message },
            bubbles: true,
            composed: true
        }));
    }
}