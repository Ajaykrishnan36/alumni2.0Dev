import { api, LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveBasicProfile from '@salesforce/apex/KenPortalOnbordingController.saveBasicProfile';
import getBasicProfile from '@salesforce/apex/KenPortalOnbordingController.getBasicProfile';
import getLearningProgramOptions from '@salesforce/apex/KenPortalOnbordingController.getLearningProgramOptions';
import basePath from '@salesforce/community/basePath';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import fetchProfilePreview from '@salesforce/apex/KenLinkedInController.fetchProfilePreview';
import syncCurrentUserFromLinkedIn from '@salesforce/apex/KenLinkedInController.syncCurrentUserFromLinkedIn';
import syncForRoleFromLinkedIn from '@salesforce/apex/KenLinkedInController.syncForRoleFromLinkedIn';
// Bundled geo data as a JS module (not a static resource / .json import):
// fetch() of a static resource fails in Experience Cloud (cross-domain CORS),
// and .json imports aren't accepted in this org's LWC config.
import GEO_DATA from './geoData';
const GRADUATION_YEARS_JSON = [];
    for (let year = new Date().getFullYear(); year >= 1990; year--) {
        GRADUATION_YEARS_JSON.push({ label: String(year), value: String(year) });
    }


export default class KenBasicProfile extends LightningElement {
    @api email = '';
    roleId = '';
    @track firstName = '';
    @track lastName = '';
    @track linkedinUrl = '';
    @track linkedinUrlError = '';
    @track twitterUrl = '';
    @track phoneE164 = ''; // E.164 format phone number from customPhoneInput
    @track country = '';
    @track state = '';
    @track currentCity = '';
    @track graduationYear = '';
    @track programme = '';
    @track programmeId = '';
    @track agreeToTerms = false;

    @track profileImageUrl = '';
    @track selectedImageFile = null;
    @track previewImageUrl = '';
    @track imageToCrop = '';
    @track showImageCropModal = false;

    @track errorMessage = '';
    @track isSubmitting = false;

    @track isErrorToastVisible = false;
    @track errorTitle = '';
    @track errorDescription = '';
    @track isSuccessToastVisible = false;
    @track successTitle = '';
    @track successDescription = '';
    successTimeout;
    errorTimeout;

    @track graduationYearOptions = GRADUATION_YEARS_JSON;
    @track programmeOptions = [];

    // Country / State picklists are driven by the GeoData static resource.
    // The stored values stay as plain text (the country/state NAME).
    @track countryOptions = [];
    @track stateOptions = [];
    _geoCountries = [];

    showLinkedInModal = false; // Show modal by default
    @track linkedInModalUrl = '';
    @track linkedinModalUrlError = '';

    styleElement;
    @track isImportingFromLinkedin = false;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
        
        // Inject global style to remove checkbox focus outline, add margin, and style asterisk
        this.styleElement = document.createElement('style');
        this.styleElement.textContent = `
            lightning-input.terms-checkbox .slds-checkbox__faux:focus,
            lightning-input.terms-checkbox input[type="checkbox"]:focus,
            lightning-input.terms-checkbox .slds-checkbox [type="checkbox"]:focus + .slds-checkbox__faux,
            .slds-checkbox__faux:focus,
            input[type="checkbox"]:focus {
                outline: none !important;
                box-shadow: none !important;
            }
            /* Add margin to checkbox faux elements */
            .slds-checkbox__faux,
            .slds-checkbox .slds-checkbox--faux,
            .slds-checkbox .slds-checkbox_faux,
            lightning-input.terms-checkbox .slds-checkbox__faux,
            lightning-input .slds-checkbox__faux {
                margin-left: 0.5rem !important;
            }
            /* Style asterisk in terms section label to primary color */
            lightning-input.terms-checkbox .slds-form-element__label::first-letter {
                color: var(--primary-color) !important;
            }
            /* Style wrapped asterisk span */
            lightning-input.terms-checkbox .slds-form-element__label span[style*="color"] {
                color: var(--primary-color) !important;
            }
        `;
        document.head.appendChild(this.styleElement);

        this.roleId = this.getRoleIdFromUrl() || window.localStorage.getItem('ConstituentRoleId') || '';
        if (this.roleId) {
            window.localStorage.setItem('ConstituentRoleId', this.roleId);
        }

        this.loadProgrammes();
        this.loadGeoData();
        this.prefillProfile();

        // Show the existing LinkedIn import dialog once per session — the markup
        // already lives in the template behind `showLinkedInModal`, and the
        // handlers (handleDoThisLater / handleImportFromLinkedIn) are wired.
        try {
            const dismissed = window.sessionStorage.getItem('linkedinImportDismissed');
            if (!dismissed) {
                this.showLinkedInModal = true;
            }
        } catch (e) {
            this.showLinkedInModal = true;
        }
    }
    
    renderedCallback() {
        // Apply avatar background style without template style bindings
        const avatars = this.template.querySelectorAll('.profile-avatar');
        avatars.forEach(el => {
            // eslint-disable-next-line @lwc/lwc/no-inner-html
            el.style.cssText = this.avatarStyle;
        });
    }
    
    disconnectedCallback() {
        if (this.styleElement && this.styleElement.parentNode) {
            this.styleElement.parentNode.removeChild(this.styleElement);
        }
        if (this.asteriskObserver) {
            this.asteriskObserver.disconnect();
            this.asteriskObserver = null;
        }
    }

    // =========================================================
    // ✅ LIVE TYPING RULES
    // 1) Allow spaces while typing
    // 2) But DO NOT allow 2+ continuous spaces (collapse to 1)
    // 3) NO digits allowed in: firstName, lastName, country, state, currentCity
    // 4) Final submit: trim ends + collapse internal spaces
    // =========================================================

    collapseContinuousSpaces(value) {
        if (value === null || value === undefined) return '';
        return String(value).replace(/\s{2,}/g, ' ');
    }

    removeDigits(value) {
        if (value === null || value === undefined) return '';
        return String(value).replace(/[0-9]/g, '');
    }

    collapseSpacesAndTrim(value) {
        if (value === null || value === undefined) return '';
        return String(value).replace(/\s{2,}/g, ' ').trim();
    }

    removeAllSpaces(value) {
        if (value === null || value === undefined) return '';
        return String(value).replace(/\s+/g, '').trim();
    }

    normalizeBeforeSubmit() {
        // Fields that should NOT contain digits
        this.firstName = this.removeDigits(this.collapseSpacesAndTrim(this.firstName));
        this.lastName = this.removeDigits(this.collapseSpacesAndTrim(this.lastName));
        this.country = this.removeDigits(this.collapseSpacesAndTrim(this.country));
        this.state = this.removeDigits(this.collapseSpacesAndTrim(this.state));
        this.currentCity = this.removeDigits(this.collapseSpacesAndTrim(this.currentCity));

        // Email (usually disabled here, but keep safe)
        this.email = this.removeAllSpaces(this.email);

        // Other fields (digits allowed unless you want them blocked too)
        this.linkedinUrl = this.collapseSpacesAndTrim(this.linkedinUrl);
        this.twitterUrl = this.collapseSpacesAndTrim(this.twitterUrl);

        // Phone
        this.phoneE164 = this.collapseSpacesAndTrim(this.phoneE164);

        // LinkedIn modal input
        this.linkedInModalUrl = this.collapseSpacesAndTrim(this.linkedInModalUrl);
    }

    // =========================================================
    // ✅ INPUT HANDLERS
    // IMPORTANT: HTML should use oninput={handleInputChange}
    // if you want this to work while typing.
    // =========================================================
    handleInputChange(event) {
        const field = event.target.dataset.field;
        const rawValue = event.target.value ?? '';

        let value = rawValue;

        // Fields where we collapse continuous spaces while typing
        const spaceFields = new Set([
            'firstName',
            'lastName',
            'linkedinUrl',
            'twitterUrl',
            'country',
            'state',
            'currentCity'
        ]);

        if (field === 'email') {
            value = this.removeAllSpaces(rawValue);
        } else if (spaceFields.has(field)) {
            value = this.collapseContinuousSpaces(rawValue);
        }

        // Remove numbers while typing in these fields
        const noDigitFields = new Set(['firstName', 'lastName', 'country', 'state', 'currentCity']);
        if (noDigitFields.has(field)) {
            value = this.removeDigits(value);
        }

        // Reflect cleaned value back into UI instantly
        if (value !== rawValue) {
            event.target.value = value;
        }

        this[field] = value;

        // Validate LinkedIn URL format on change
        if (field === 'linkedinUrl') {
            this.linkedinUrlError = value && !this.isValidLinkedinUrl(value)
                ? 'Please enter a valid URL starting with https:// or www.'
                : '';
        }
    }

    isValidLinkedinUrl(url) {
        return /^(https?:\/\/|www\.)/i.test((url || '').trim());
    }

    handleSelectChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
    }

    // Builds the country picklist options from the bundled geo data. State options
    // follow the chosen country. Runs synchronously so options are ready on render.
    loadGeoData() {
        try {
            this._geoCountries = (GEO_DATA && GEO_DATA.countries) || [];
            this.countryOptions = this._geoCountries.map((c) => ({ label: c.name, value: c.name }));
            // If a country was already prefilled, populate its states now.
            this.buildStateOptions();
        } catch (e) {
            // Non-fatal — pickers just stay empty; saved values are still text.
            // eslint-disable-next-line no-console
            console.error('Error loading geo data', e);
        }
    }

    // State picklist stays disabled until a country is chosen.
    get isStateDisabled() {
        return !this.country;
    }

    // Rebuilds stateOptions for the currently selected country (matched by name).
    buildStateOptions() {
        const match = this._geoCountries.find((c) => c.name === this.country);
        this.stateOptions = match && match.states
            ? match.states.map((s) => ({ label: s.name, value: s.name }))
            : [];
    }

    handleCountryChange(event) {
        this.country = event.detail.value || '';
        // Reset the state when it no longer belongs to the newly chosen country.
        this.buildStateOptions();
        if (this.state && !this.stateOptions.some((o) => o.value === this.state)) {
            this.state = '';
        }
    }

    handleStateChange(event) {
        this.state = event.detail.value || '';
    }

    handleCheckboxChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.checked;
    }

    handlePhoneChange(event) {
        const { e164 } = event.detail;
        const raw = e164 || '';
        // collapse multiple spaces while typing
        this.phoneE164 = this.collapseContinuousSpaces(raw);
    }

    // =========================================================
    // ✅ LINKEDIN MODAL HANDLERS
    // =========================================================
    handleLinkedInModalUrlChange(event) {
        const raw = event.detail?.value ?? event.target?.value ?? '';
        const cleaned = this.collapseContinuousSpaces(raw);

        if (event.target && event.target.value !== cleaned) {
            event.target.value = cleaned;
        }
        this.linkedInModalUrl = cleaned;
        this.linkedinModalUrlError = cleaned && !this.isValidLinkedinUrl(cleaned)
            ? 'Please enter a URL starting with https:// or www.'
            : '';
    }

    // Inline sync icon next to the LinkedIn URL field — opens the same
    // import modal that auto-pops on first Step-1 render.
    handleOpenLinkedinSync() {
        // Pre-fill the modal field with whatever the user has typed already.
        if (this.linkedinUrl) {
            this.linkedInModalUrl = this.linkedinUrl;
        }
        this.showLinkedInModal = true;
    }

    handleDoThisLater() {
        this.showLinkedInModal = false;
        this._markLinkedinImportDismissed();
    }

    async handleImportFromLinkedIn() {
        const raw = this.collapseSpacesAndTrim(this.linkedInModalUrl || '');
        if (!raw) {
            this.dispatchEvent(new CustomEvent('notify', {
                detail: { title: 'URL required', message: 'Paste your LinkedIn profile URL first.', variant: 'warning' }
            }));
            return;
        }
        if (!this.isValidLinkedinUrl(raw)) {
            this.linkedinModalUrlError = 'Please enter a URL starting with https:// or www.';
            this.dispatchEvent(new CustomEvent('notify', {
                detail: { title: 'Invalid URL', message: 'Please enter a LinkedIn URL starting with https:// or www.', variant: 'error' }
            }));
            return;
        }
        // Normalize www. → https://www. internally for the API call only.
        // Do NOT write the normalized value back to the field so the user's
        // input stays as-is.
        const url = /^www\./i.test(raw) ? 'https://' + raw : raw;
        if (this.isImportingFromLinkedin) return;
        this.isImportingFromLinkedin = true;
        // Stash the URL onto the form FIRST — that way even if the provider
        // call fails the user still sees their LinkedIn URL filled in and can
        // hit "Save & Continue" to persist it via the regular flow.
        this.linkedinUrl = raw;
        try {
            // 1) Always grab a preview so we can populate downstream steps even if
            //    the user's Person Account isn't linked yet (sessionStorage cache).
            const preview = await fetchProfilePreview({ linkedInUrl: url });

            // If the API returned nothing meaningful, surface "No data found"
            const hasData = preview && (preview.experiencesCount > 0 || preview.educationCount > 0 || preview.rawJson);
            if (!hasData) {
                this.dispatchEvent(new CustomEvent('notify', {
                    detail: { title: 'No data found', message: 'No profile data was found for this LinkedIn URL. Please check the link and try again.', variant: 'error' }
                }));
                this.isImportingFromLinkedin = false;
                return;
            }

            try { window.sessionStorage.setItem('linkedinImportPreview', preview.rawJson || ''); } catch (e) { /* ignore */ }

            // 2) Attempt to persist immediately — writes PersonEmployment /
            //    PersonEducation rows against the running user's Person Account
            //    (User.AccountId), which is the same account the onboarding
            //    employment loader reads from.
            let persisted = false;
            try {
                await syncCurrentUserFromLinkedIn({ linkedInUrl: url });
                persisted = true;
            } catch (persistErr) {
                // If the user isn't yet linked to a Person Account we'll silently
                // fall back to the cached preview — Education/Employment steps
                // still get pre-filled from sessionStorage.
                // eslint-disable-next-line no-console
                console.warn('Live LinkedIn sync skipped:', persistErr?.body?.message || persistErr?.message);
            }

            this.dispatchEvent(new CustomEvent('notify', {
                detail: {
                    title: persisted ? 'LinkedIn synced' : 'LinkedIn imported',
                    message: persisted
                        ? `Saved ${preview.experiencesCount} jobs and ${preview.educationCount} education entries to your profile.`
                        : `Found ${preview.experiencesCount} jobs, ${preview.educationCount} education entries${preview.certificationsCount ? `, ${preview.certificationsCount} certifications` : ''}. They'll be saved when you finish signup.`,
                    variant: 'success'
                }
            }));
            this.showLinkedInModal = false;
            this._markLinkedinImportDismissed();
        } catch (err) {
            const msg = (err && err.body && err.body.message) || err.message || 'No data found.';
            this.dispatchEvent(new CustomEvent('notify', {
                detail: { title: 'No data found', message: msg, variant: 'error' }
            }));
        } finally {
            this.isImportingFromLinkedin = false;
        }
    }

    _markLinkedinImportDismissed() {
        try { window.sessionStorage.setItem('linkedinImportDismissed', '1'); } catch (e) { /* ignore */ }
    }

    // =========================================================
    // ✅ UI GETTERS
    // =========================================================
    get avatarStyle() {
        const imageUrl = this.previewImageUrl || this.profileImageUrl;
        if (imageUrl) {
            return `background-image: url(${imageUrl}); background-size: cover; background-position: center;`;
        }
        return 'background: linear-gradient(135deg, #7B2CBF 0%, #9D4EDD 100%);';
    }

    get avatarInitial() {
        const fullName = `${this.firstName || ''} ${this.lastName || ''}`.trim();
        return fullName ? fullName.charAt(0).toUpperCase() : 'U';
    }

    get showPreviewImage() {
        return !!this.previewImageUrl;
    }

    get importButtonLabel() {
        return this.isImportingFromLinkedin ? 'Importing...' : 'Import from LinkedIn';
    }

    // =========================================================
    // ✅ IMAGE UPLOAD + CROP
    // =========================================================
    handleImageUpload() {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = 'image/png,image/jpeg,image/jpg,image/svg+xml,.png,.jpg,.jpeg,.svg';
        input.onchange = (e) => {
            if (e.target.files && e.target.files[0]) {
                const file = e.target.files[0];
                const fileExtension = '.' + file.name.split('.').pop().toLowerCase();
                const isHeicFormat =
                    file.type === 'image/heic' ||
                    file.type === 'image/heif' ||
                    fileExtension === '.heic' ||
                    fileExtension === '.heif';

                if (isHeicFormat) {
                    this.showToast('Error', 'HEIC format is not supported. Please use PNG, JPG, JPEG, or SVG format.', 'error');
                    return;
                }

                const allowedFormats = ['image/png', 'image/jpeg', 'image/jpg', 'image/svg+xml'];
                const allowedExtensions = ['.png', '.jpg', '.jpeg', '.svg'];
                const isValidFormat = allowedFormats.includes(file.type) || allowedExtensions.includes(fileExtension);

                if (!isValidFormat) {
                    this.showToast('Error', 'Please select a valid image format (PNG, JPG, JPEG, or SVG)', 'error');
                    return;
                }

                const maxSize = 2 * 1024 * 1024;
                if (file.size > maxSize) {
                    this.showToast('Error', 'Image size must be under 2 MB. Please choose a smaller picture.', 'error');
                    return;
                }

                const reader = new FileReader();
                reader.onload = (event) => {
                    const dataUrl = event.target.result;
                    // SVGs are resolution-independent, so skip the dimension check.
                    if (file.type === 'image/svg+xml' || fileExtension === '.svg') {
                        this.acceptProfileImage(file, dataUrl);
                        return;
                    }
                    // Profile pictures should be roughly square. Allow "almost
                    // square" (longer side up to 1.5x the shorter) and only reject
                    // clearly non-square images like banners/panoramas.
                    const img = new Image();
                    img.onload = () => {
                        const w = img.naturalWidth;
                        const h = img.naturalHeight;
                        const ratio = (w && h) ? Math.max(w, h) / Math.min(w, h) : 1;
                        if (ratio > 1.5) {
                            this.showToast('Error', 'Please upload an almost-square image — its width and height should be roughly equal.', 'error');
                            return;
                        }
                        this.acceptProfileImage(file, dataUrl);
                    };
                    img.onerror = () => {
                        this.showToast('Error', 'That image could not be read. Please upload a valid PNG or JPG file.', 'error');
                    };
                    img.src = dataUrl;
                };
                reader.onerror = () => {
                    this.showToast('Error', 'Could not read the selected file. Please try another image.', 'error');
                };
                reader.readAsDataURL(file);
            }
        };
        input.click();
    }

    // Opens the crop (move & scale) modal on the selected image. Nothing is
    // committed to the profile until the user confirms with Upload.
    acceptProfileImage(file, dataUrl) {
        this.selectedImageFile = file;
        this.errorMessage = '';
        this.imageToCrop = dataUrl;
        this.showImageCropModal = true;
    }

    handleOpenCropModal(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.previewImageUrl) {
            this.imageToCrop = this.previewImageUrl;
            this.showImageCropModal = true;
        }
    }

    // Fired when the user confirms the crop with Upload — this is the only path
    // that commits the (cropped) image to the profile.
    handleImageUploaded(event) {
        this.profileImageUrl = event.detail.imageUrl;
        this.previewImageUrl = event.detail.imageUrl;
        this.imageToCrop = '';
        this.showImageCropModal = false;
        this.dispatchProfileChange();
    }

    handleCloseImageCrop() {
        this.showImageCropModal = false;
        this.imageToCrop = '';
    }

    // "Choose a different image" inside the crop modal — swap the crop source
    // only; still not committed until Upload.
    handleImageChanged(event) {
        const newImageUrl = event.detail.imageUrl;
        if (newImageUrl) {
            this.imageToCrop = newImageUrl;
        }
    }

    // =========================================================
    // ✅ VALIDATION + PAYLOAD
    // =========================================================
    validateInputs() {
        this.normalizeBeforeSubmit();

        const missingFields = [];
        if (!this.firstName) missingFields.push('First name');
        if (!this.lastName) missingFields.push('Last name');
        if (!this.email) missingFields.push('Email');
        if (!this.phoneE164) missingFields.push('Phone number');
        if (!this.country) missingFields.push('Country of Residence');
        if (!this.state) missingFields.push('State');
        if (!this.currentCity) missingFields.push('Current City');
        if (!this.graduationYear) missingFields.push('Graduation year');
        if (!this.programmeId && !this.programme) missingFields.push('Batch');
        if (!this.agreeToTerms) missingFields.push('Agreement to terms');

        if (missingFields.length > 0) {
            this.errorMessage = `Please complete required fields: ${missingFields.join(', ')}`;
            return false;
        }

        const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
        if (!emailRegex.test(this.email)) {
            this.errorMessage = 'Please enter a valid email address.';
            return false;
        }

        if (this.linkedinUrl && !this.isValidLinkedinUrl(this.linkedinUrl)) {
            this.linkedinUrlError = 'Please enter a valid URL starting with https:// or www.';
            this.errorMessage = 'Please enter a valid LinkedIn URL.';
            return false;
        }

        this.errorMessage = '';
        return true;
    }

    buildPayload() {
        this.normalizeBeforeSubmit();

        const phoneNumber = (this.phoneE164 || '').trim();
        const profileImageUrl = this.previewImageUrl || this.profileImageUrl || '';

        return {
            firstName: this.firstName || '',
            lastName: this.lastName || '',
            email: this.email || '',
            linkedinUrl: this.linkedinUrl || '',
            twitterUrl: this.twitterUrl || '',
            phoneNumber: phoneNumber || '',
            country: this.country || '',
            state: this.state || '',
            currentCity: this.currentCity || '',
            graduationYear: this.graduationYear || '',
            programme: this.programme || '',
            programmeId: this.programmeId || '',
            agreeToTerms: Boolean(this.agreeToTerms),
            profileImageUrl: profileImageUrl || ''
        };
    }

    async handleContinue() {
        this.normalizeBeforeSubmit();

        if (!this.validateInputs()) {
            this.dispatchNotify('error', 'Required field missing', this.errorMessage || 'Please complete required fields to continue.');
            return;
        }

        this.isSubmitting = true;
        const formData = this.buildPayload();

        try {
            const result = await saveBasicProfile({
                requestJson: JSON.stringify(formData),
                roleId: this.roleId || null
            });
            this.profileImageUrl = formData.profileImageUrl;

            const message = result && result.message ? result.message : 'Profile saved successfully.';
            this.dispatchNotify('success', 'Success', message);

            this.dispatchEvent(new CustomEvent('continue', {
                detail: {
                    ...formData,
                    accountId: result && result.accountId ? result.accountId : null
                },
                bubbles: true,
                composed: true
            }));
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error saving profile:', error);
            const message = error?.body?.message || 'Unable to save profile. Please try again.';
            this.errorMessage = message;
            this.dispatchNotify('error', 'Error', message);
        } finally {
            this.isSubmitting = false;
        }
    }

    // =========================================================
    // ✅ NAV + TOASTS
    // =========================================================
    handleCancel() {
        window.location.href = `${basePath}/login`;
    }

    getRoleIdFromUrl() {
        try {
            const url = new URL(window.location.href);
            return url.searchParams.get('roleId');
        } catch (e) {
            return null;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode: 'dismissable'
            })
        );
    }

    dispatchNotify(type, title, message) {
        this.dispatchEvent(
            new CustomEvent('notify', {
                detail: { type, title, message },
                bubbles: true,
                composed: true
            })
        );
    }

    // =========================================================
    // ✅ PREFILL / API LOAD
    // =========================================================
    @api
    setOnboardingData(data) {
        if (!data) return;

        this.firstName = data.firstName || this.firstName;
        this.lastName = data.lastName || this.lastName;
        this.email = data.email || this.email;

        // Preserve a URL the user just imported/typed — the parent calls this on
        // first step-1 render and would otherwise wipe it with an empty value
        // before the LinkedIn import (auto-opened modal) has been persisted.
        this.linkedinUrl = data.linkedinUrl || this.linkedinUrl || '';
        this.twitterUrl = data.twitterUrl || this.twitterUrl || '';
        this.phoneE164 = data.phoneNumber || this.phoneE164 || '';

        this.country = data.country || '';
        this.state = data.state || '';
        this.currentCity = data.currentCity || '';

        this.graduationYear = data.graduationYear || '';
        this.buildGraduationYearOptions(this.graduationYear);


        if (data.programme || data.programmeId) {
            this.programme = data.programme || '';
            this.programmeId = data.programmeId || '';
        }

        this.normalizeBeforeSubmit();
        this.buildStateOptions();
    }

    async prefillProfile() {
        try {
            const data = await getBasicProfile({ roleId: this.roleId || null });
            if (!data) return;

            this.firstName = data.firstName || this.firstName;
            this.lastName = data.lastName || this.lastName;
            this.email = data.email || this.email || '';

            // Preserve a value the user already typed/imported on this step:
            // getBasicProfile resolves asynchronously and must not clobber a
            // LinkedIn URL just imported via the modal with an empty server value.
            this.linkedinUrl = data.linkedinUrl || this.linkedinUrl || '';
            this.twitterUrl = data.twitterUrl || this.twitterUrl || '';
            this.phoneE164 = data.phoneNumber || this.phoneE164 || '';

            this.country = data.country || '';
            this.state = data.state || '';
            this.currentCity = data.currentCity || '';

            this.graduationYear = data.graduationYear || '';
            this.programme = data.programme || '';
            this.programmeId = data.programmeId || '';
            this.agreeToTerms = data.agreeToTerms !== undefined ? data.agreeToTerms : this.agreeToTerms;
            this.profileImageUrl = data.profileImageUrl || '';
            this.previewImageUrl = '';

            this.normalizeBeforeSubmit();
            this.buildStateOptions();
            this.dispatchProfileChange();
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error pre-filling profile', error);
        }
    }

    dispatchProfileChange() {
        this.dispatchEvent(
            new CustomEvent('profilechange', {
                detail: {
                    firstName: this.firstName,
                    lastName: this.lastName,
                    email: this.email,
                    profileImageUrl: this.previewImageUrl || this.profileImageUrl
                },
                bubbles: true,
                composed: true
            })
        );
    }

    async loadProgrammes() {
        try {
            const options = await getLearningProgramOptions();
            this.programmeOptions = options || [];
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading programmes', error);
            this.programmeOptions = [];
        }
    }
    buildGraduationYearOptions(returnedYear) {
        const currentYear = new Date().getFullYear();
        const y = parseInt(returnedYear, 10);
        const maxYear = Number.isFinite(y) ? Math.max(currentYear, y) : currentYear;

        const opts = [];
        for (let year = maxYear; year >= 1990; year--) {
            opts.push({ label: String(year), value: String(year) });
        }
        this.graduationYearOptions = opts;
    }

}