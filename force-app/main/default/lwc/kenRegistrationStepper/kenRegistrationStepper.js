import { LightningElement, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import registrationHeaderImage from '@salesforce/resourceUrl/registrationHeader';
import saveEmploymentDetails from '@salesforce/apex/KenPortalOnbordingController.saveEmploymentDetails';
import saveEngagementPreferences from '@salesforce/apex/KenPortalOnbordingController.saveEngagementPreferences';
import getEmploymentDetails from '@salesforce/apex/KenPortalOnbordingController.getEmploymentDetails';
import getBasicProfile from '@salesforce/apex/KenPortalOnbordingController.getBasicProfile';
import getEngagementPreferences from '@salesforce/apex/KenPortalOnbordingController.getEngagementPreferences';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenRegistrationStepper extends LightningElement {
    registrationHeaderImage = registrationHeaderImage;
    @track institutionAlias = '';
    @track currentStep = 1;
    @track showOptInModal = false;
    @track userEmail = '';
    @track profile = {};
    @track isLoading = false;
    @track error;
    @track employmentData = [];
    @track profileLoaded = false;
    @track engagementData = {
        joinNetwork: '',
        speakAtEvents: '',
        featuredInStories: '',
        researchPartner: '',
        engagementActivities: []
    };
    prefillStep1Attempted = false;
    prefillStep3Attempted = false;
    prefillStep4Attempted = false;
    @track showToast = false;
    @track toastTitle = '';
    @track toastMessage = '';
    @track toastVariant = 'success';
    toastTimeout;
    roleId = '';

    get isStep1Active() {
        return this.currentStep === 1;
    }

    get isStep2Active() {
        return this.currentStep === 2;
    }

    get isStep3Active() {
        return this.currentStep === 3;
    }

    get isStep4Active() {
        return this.currentStep === 4;
    }

    get step1Class() {
        if (this.isStep1Completed) return 'step-item completed';
        return this.isStep1Active ? 'step-item active' : 'step-item';
    }

    get step2Class() {
        if (this.isStep2Completed) return 'step-item completed';
        return this.isStep2Active ? 'step-item active' : 'step-item';
    }

    get step3Class() {
        if (this.isStep3Completed) return 'step-item completed';
        return this.isStep3Active ? 'step-item active' : 'step-item';
    }

    get step4Class() {
        if (this.isStep4Completed) return 'step-item completed';
        return this.isStep4Active ? 'step-item active' : 'step-item';
    }

    get isStep1Completed() {
        return this.currentStep > 1;
    }

    get isStep2Completed() {
        return this.currentStep > 2;
    }

    get isStep3Completed() {
        return this.currentStep > 3;
    }

    get isStep4Completed() {
        return this.currentStep > 4;
    }

    get isSuccess() {
        return this.bannerVariant !== 'error';
    }

    get bannerClass() {
        return this.bannerVariant === 'error' ? 'top-dialog-error' : 'top-dialog';
    }

    connectedCallback() {
        this.roleId = this.getRoleIdFromUrl() || window.localStorage.getItem('ConstituentRoleId') || '';
        if (this.roleId) {
            window.localStorage.setItem('ConstituentRoleId', this.roleId);
        }
        this.loadProfile();
        getPrimaryColor().then(color => {
            this.institutionAlias = color?.institutionAlias;
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
        });
    }

    renderedCallback() {
        if (this.currentStep === 1 && !this.prefillStep1Attempted && this.profileLoaded) {
            this.prefillBasicProfile();
        }
        if (this.currentStep === 3 && !this.prefillStep3Attempted) {
            this.prefillEmployment();
        }
        if (this.currentStep === 4 && !this.prefillStep4Attempted) {
            this.prefillEngagement();
        }
    }

    async handleStep1Continue(event) {
        const formData = event?.detail || {};
        this.profile = { ...this.profile, ...formData };
        this.userEmail = formData.email || this.userEmail || '';
        this.dispatchProfileChange(this.profile);
        this.currentStep = 2;
    }

    // ── Step 2: Education ──────────────────────────────────────────────────────

    handleStep2Previous() {
        this.prefillStep1Attempted = false;
        this.currentStep = 1;
    }

    async handleStep2Skip() {
        this.currentStep = 3;
        this.prefillStep3Attempted = false;
        await this.loadEmploymentData();
    }

    async handleStep2SaveAndNext() {
        this.currentStep = 3;
        this.prefillStep3Attempted = false;
        await this.loadEmploymentData();
    }

    // ── Step 3: Employment ─────────────────────────────────────────────────────

    async handleStep3Previous() {
        this.prefillStep3Attempted = false;
        this.currentStep = 2;
    }

    async handleStep3Skip() {
        const step3 = this.template.querySelector('c-ken-employment-career-info');
        this.employmentData = step3?.careerInfoList ? [...step3.careerInfoList] : [];
        this.prefillStep4Attempted = false;
        this.currentStep = 4;
        this.isLoading = true;
        try {
            await this.loadEngagementData();
        } catch (e) {
            console.error('Error loading engagement preferences on skip', e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleStep3SaveAndNext(event) {
        const step3 = this.template.querySelector('c-ken-employment-career-info');
        const careerData = event?.detail?.careers || step3?.careerInfoList || [];
        this.employmentData = careerData;
        this.isLoading = true;
        try {
            await saveEmploymentDetails({
                requestJson: JSON.stringify(careerData || []),
                roleId: this.roleId || null
            });
            this.handleNotify({ detail: { type: 'success', title: 'Success', message: 'Employment details saved successfully.' } });
            this.prefillStep4Attempted = false;
            this.currentStep = 4;
            await this.loadEngagementData();
        } catch (e) {
            const msg = e?.body?.message || 'Unable to save employment details.';
            this.error = msg;
            console.error('Error saving employment details', e);
        } finally {
            this.isLoading = false;
        }
    }

    // ── Step 4: Engagement ─────────────────────────────────────────────────────

    handleStep4Previous() {
        this.prefillStep4Attempted = false;
        this.prefillStep3Attempted = false;
        this.currentStep = 3;
    }

    async handleStep4SaveAndNext(event) {
        const formData = event?.detail || {};
        this.isLoading = true;
        try {
            await saveEngagementPreferences({
                preferences: formData.preferences,
                roleId: this.roleId || null
            });
            this.handleNotify({ detail: { type: 'success', title: 'Success', message: 'Engagement details saved successfully.' } });
            setTimeout(() => {
                const rolePart = this.roleId ? `?roleId=${this.roleId}` : '';
                window.location.href = `${basePath}/welcome-page${rolePart}`;
            }, 3000);
        } catch (e) {
            const msg = e?.body?.message || 'Unable to save preferences.';
            this.error = msg;
            console.error('Error saving engagement preferences', e);
        } finally {
            this.isLoading = false;
        }
    }

    handleBasicProfileChange(event) {
        const detail = event?.detail || {};
        this.profile = { ...this.profile, ...detail };
        this.userEmail = detail.email || this.userEmail || '';
        this.dispatchProfileChange(this.profile);
    }

    handleCloseOptIn() {
        this.showOptInModal = false;
    }

    async loadProfile() {
        try {
            const data = await getBasicProfile({ roleId: this.roleId || null });
            if (data) {
                this.profile = { ...data };
                this.userEmail = data.email || this.userEmail || '';
                this.dispatchProfileChange(this.profile);
            }
            await this.loadEmploymentData();
            await this.loadEngagementData();
        } catch (e) {
            console.error('Error loading basic profile', e);
        } finally {
            this.profileLoaded = true;
            this.prefillStep1Attempted = false;
        }
    }

    async loadEmploymentData() {
        try {
            const data = await getEmploymentDetails({ roleId: this.roleId || null });
            this.employmentData = data || [];
            // If the server has nothing and we have a fresh LinkedIn preview
            // from Step 1, pre-fill the career list from it. The records get
            // persisted when the user clicks "Save & Next" on Step 3 — no
            // applied-flag here: prefilling only when the server is empty is
            // already idempotent, and an early flag would permanently block
            // the prefill when the user leaves Step 3 without saving.
            if (!this.employmentData.length) {
                const fromLinkedin = this._linkedinEmploymentRows();
                if (fromLinkedin.length) {
                    this.employmentData = fromLinkedin;
                }
            }
            const step3 = this.template.querySelector('c-ken-employment-career-info');
            if (step3 && this.employmentData.length > 0) {
                step3.careerInfoList = [...this.employmentData];
                step3.nextId = this.employmentData.length + 1;
                this.prefillStep3Attempted = true;
            }
        } catch (e) {
            console.error('Error loading employment data', e);
            this.employmentData = [];
        }
    }

    /**
     * Parse the LinkedIn preview cached on Step 1 (sessionStorage) into the
     * careerInfoList shape used by kenEmploymentCareerInfo.
     */
    _linkedinEmploymentRows() {
        try {
            const raw = window.sessionStorage.getItem('linkedinImportPreview');
            if (!raw) return [];
            const profile = JSON.parse(raw);
            const exps = (profile && profile.experiences) || [];
            return exps.map((e, idx) => {
                const sa = e.starts_at || {};
                const ea = e.ends_at   || {};
                const startDate = sa.year ? `${sa.year}-${String(sa.month || 1).padStart(2, '0')}-01` : null;
                const endDate   = ea.year ? `${ea.year}-${String(ea.month || 1).padStart(2, '0')}-01` : null;
                return {
                    id: idx + 1,
                    jobTitle: e.title || '',
                    organization: e.company || '',
                    employmentType: e.employment_type || '',
                    location: e.location || '',
                    startDate,
                    endDate,
                    roleDescription: e.description || '',
                    isCurrentJob: !endDate,
                    jobRole: ''
                };
            });
        } catch (e) {
            return [];
        }
    }

    async loadEngagementData() {
        try {
            const pref = await getEngagementPreferences({ roleId: this.roleId || null });
            if (pref) {
                const values = pref.split(';').map(v => v.trim()).filter(Boolean);
                this.engagementData = { preferences: pref, engagementActivities: values };
                const step4 = this.template.querySelector('c-ken-engagement-contributions');
                if (step4 && typeof step4.setEngagementData === 'function') {
                    step4.setEngagementData(this.engagementData);
                    this.prefillStep4Attempted = true;
                }
            }
        } catch (e) {
            console.error('Error loading engagement preferences', e);
        }
    }

    prefillBasicProfile() {
        const step1 = this.template.querySelector('c-ken-basic-profile');
        if (step1 && typeof step1.setOnboardingData === 'function') {
            step1.setOnboardingData(this.profile || {});
            this.prefillStep1Attempted = true;
        }
    }

    prefillEmployment() {
        const step3 = this.template.querySelector('c-ken-employment-career-info');
        if (step3) {
            if (typeof step3.setEmploymentData === 'function') {
                step3.setEmploymentData(this.employmentData || []);
            } else {
                step3.careerInfoList = [...this.employmentData];
                step3.nextId = (this.employmentData?.length || 0) + 1;
            }
            this.prefillStep3Attempted = true;
        }
    }

    prefillEngagement() {
        const step4 = this.template.querySelector('c-ken-engagement-contributions');
        if (step4 && typeof step4.setEngagementData === 'function') {
            step4.setEngagementData(this.engagementData);
            this.prefillStep4Attempted = true;
        }
    }

    handleFinishSetup() {
        this.showOptInModal = false;
        const rolePart = this.roleId ? `?roleId=${this.roleId}` : '';
        window.location.href = `${basePath}/welcome-page${rolePart}`;
    }

    dispatchProfileChange(profile) {
        const detail = {
            firstName: profile?.firstName || '',
            lastName: profile?.lastName || '',
            profileImageUrl: profile?.profileImageUrl || ''
        };
        this.dispatchEvent(new CustomEvent('profilechange', { detail, bubbles: true, composed: true }));
    }

    handleNotify(event) {
        const detail = event.detail || {};
        this.toastVariant = detail.type === 'error' ? 'error' : 'success';
        this.toastTitle = detail.title || (this.toastVariant === 'error' ? 'Error' : 'Success');
        this.toastMessage = detail.message || '';
        this.showToast = true;
        window.clearTimeout(this.toastTimeout);
        this.toastTimeout = window.setTimeout(() => {
            this.showToast = false;
        }, 1500);
    }

    getRoleIdFromUrl() {
        try {
            const url = new URL(window.location.href);
            return url.searchParams.get('roleId');
        } catch (e) {
            return null;
        }
    }
}