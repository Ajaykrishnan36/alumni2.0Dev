import { api, LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveBasicProfile from '@salesforce/apex/KenPortalOnbordingController.saveBasicProfile';
import getBasicProfile from '@salesforce/apex/KenPortalOnbordingController.getBasicProfile';
import getLearningProgramOptions from '@salesforce/apex/KenPortalOnbordingController.getLearningProgramOptions';
import getNationalityOptions from '@salesforce/apex/KenPortalOnbordingController.getNationalityOptions';
import getGenderOptions from '@salesforce/apex/KenPortalOnbordingController.getGenderOptions';
import getBloodGroupOptions from '@salesforce/apex/KenPortalOnbordingController.getBloodGroupOptions';
import basePath from '@salesforce/community/basePath';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import fetchProfilePreview from '@salesforce/apex/KenLinkedInController.fetchProfilePreview';
import syncCurrentUserFromLinkedIn from '@salesforce/apex/KenLinkedInController.syncCurrentUserFromLinkedIn';
import syncForRoleFromLinkedIn from '@salesforce/apex/KenLinkedInController.syncForRoleFromLinkedIn';
// Bundled geo data as a JS module (not a static resource / .json import):
// fetch() of a static resource fails in Experience Cloud (cross-domain CORS),
// and .json imports aren't accepted in this org's LWC config.
import GEO_DATA from './geoData';
import { validatePhoneNumber } from 'c/kenCustomPhoneInput';
import { localDateKey } from 'c/kenDateTime';
const GRADUATION_YEARS_JSON = [];

// The calendar refuses to go earlier than this, so typing must not either — before this was
// enforced, a typed 01/01/1000 sailed through a field whose own picker starts at 1900.
const MIN_DOB_ISO = '1900-01-01';
    for (let year = new Date().getFullYear(); year >= 1990; year--) {
        GRADUATION_YEARS_JSON.push({ label: String(year), value: String(year) });
    }


export default class KenBasicProfile extends LightningElement {
    @api email = '';
    // Org opt-in (Ken_Alm_Org_Parameters__c.Lock_Registration_Details__c). When on,
    // the details carried over from registration render read-only here.
    @api lockRegistrationDetails = false;

    get isRegistrationFieldLocked() {
        return this.lockRegistrationDetails === true;
    }

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
    @track dateOfBirth = '';
    @track dateOfBirthDisplay = '';
    @track dobError = '';
    @track nationality = '';
    @track languages = '';
    @track gender = '';
    @track bloodGroup = '';
    @track agreeToTerms = false;

    // Per-field validation messages, same shape as the Education step's modal:
    // the message renders inline under the field and turns its border red.
    @track errors = {};
    scrollToErrorPending = false;

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
    @track nationalityOptions = [];
    @track genderOptions = [];
    @track bloodGroupOptions = [];

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

    // The desktop and mobile markups are two full copies of the same form. Leaving both
    // in the DOM and hiding one with CSS doubled the Lightning base components on the
    // page (18 lightning-input + 8 lightning-combobox) and doubled the cost of every
    // re-render, since both copies bind the same tracked values. Render only the layout
    // in play. 600px is the same breakpoint the stylesheet uses to do the swap.
    @track isMobileLayout = false;

    @track isDobPickerOpen = false;

    // Set once the alumnus types in the date field or picks from the calendar. Both prefill
    // paths resolve asynchronously and can land afterwards; their usual "keep what the user
    // has" guard reads this.dateOfBirth, which is empty while a date is half-typed, so a
    // stored date would win and silently overwrite the entry in progress.
    _dobTouched = false;

    connectedCallback() {
        this.watchLayoutBreakpoint();

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
        this.loadNationalities();
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

        // Scroll only once the messages are in the DOM — validateInputs runs before
        // the re-render, so the targets do not exist yet at that point.
        if (this.scrollToErrorPending) {
            this.scrollToErrorPending = false;
            this.scrollToFirstError();
        }
    }
    
    /**
     * Picks the layout to render and keeps it in step with the viewport. Resizing across
     * the breakpoint swaps which copy of the form is in the DOM; the field values live in
     * tracked state rather than the inputs, so nothing the alumnus typed is lost.
     */
    watchLayoutBreakpoint() {
        if (typeof window.matchMedia !== 'function') {
            return;
        }
        this.layoutQuery = window.matchMedia('(max-width: 600px)');
        this.isMobileLayout = this.layoutQuery.matches;
        this.handleLayoutChange = (event) => {
            this.isMobileLayout = event.matches;
        };
        // Safari below 14 only has the deprecated addListener/removeListener pair.
        if (typeof this.layoutQuery.addEventListener === 'function') {
            this.layoutQuery.addEventListener('change', this.handleLayoutChange);
        } else {
            this.layoutQuery.addListener(this.handleLayoutChange);
        }
    }

    disconnectedCallback() {
        this.detachDobDismiss();
        if (this.layoutQuery && this.handleLayoutChange) {
            if (typeof this.layoutQuery.removeEventListener === 'function') {
                this.layoutQuery.removeEventListener('change', this.handleLayoutChange);
            } else {
                this.layoutQuery.removeListener(this.handleLayoutChange);
            }
            this.layoutQuery = null;
            this.handleLayoutChange = null;
        }
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
        this.languages = this.collapseSpacesAndTrim(this.languages);

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
            'currentCity',
            'languages'
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
        this.clearError(field);

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
        this.clearError(field);
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
        this.clearError('country');
        // Reset the state when it no longer belongs to the newly chosen country.
        this.buildStateOptions();
        if (this.state && !this.stateOptions.some((o) => o.value === this.state)) {
            this.state = '';
        }
    }

    handleStateChange(event) {
        this.state = event.detail.value || '';
    }

    handleNationalityChange(event) {
        this.nationality = event.detail.value || '';
    }

    handleCheckboxChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.checked;
        this.clearError(field);
    }

    handlePhoneChange(event) {
        const { e164 } = event.detail;
        const raw = e164 || '';
        // collapse multiple spaces while typing
        this.phoneE164 = this.collapseContinuousSpaces(raw);
        this.clearError('phoneE164');
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
            let saved = null;
            let persistError = null;
            try {
                saved = await syncCurrentUserFromLinkedIn({ linkedInUrl: url });
            } catch (persistErr) {
                persistError = persistErr?.body?.message || persistErr?.message || null;
            }

            const savedJobs = saved ? saved.jobsSaved || 0 : 0;
            const savedEdu = saved ? saved.educationSaved || 0 : 0;
            const rowsFailed = saved ? saved.rowsFailed || 0 : 0;
            const persisted = savedJobs > 0 || savedEdu > 0;
            const found = `Found ${preview.experiencesCount} jobs, ${preview.educationCount} education entries${preview.certificationsCount ? `, ${preview.certificationsCount} certifications` : ''}`;

            let notice;
            if (persisted && rowsFailed === 0) {
                notice = {
                    title: 'LinkedIn synced',
                    message: `Saved ${savedJobs} jobs and ${savedEdu} education entries to your profile.`,
                    variant: 'success'
                };
            } else if (persisted) {
                notice = {
                    title: 'LinkedIn partly synced',
                    message: `Saved ${savedJobs} jobs and ${savedEdu} education entries. ${rowsFailed} could not be saved${saved.firstError ? ` — ${saved.firstError}` : '.'}`,
                    variant: 'warning'
                };
            } else {
                notice = {
                    title: 'LinkedIn imported, not saved',
                    message: `${found}, but nothing could be saved to your profile${persistError ? ` — ${persistError}` : (saved && saved.firstError ? ` — ${saved.firstError}` : '')}. The next steps will still be pre-filled.`,
                    variant: 'warning'
                };
            }

            this.dispatchEvent(new CustomEvent('notify', { detail: notice }));
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

    get todayIso() {
        return localDateKey();
    }

    /**
     * Date of birth is shown as DD/MM/YYYY text with a calendar button beside it.
     * `lightning-input type="date"` cannot be used directly because it always renders
     * a month-name medium format ("Jul 2, 2003") taken from the running user's locale,
     * with no way to force a numeric day-first format. `dateOfBirth` stays in ISO
     * (yyyy-mm-dd) because that is what the Apex payload expects.
     */
    handleDobInput(event) {
        const digits = (event.target.value || '').replace(/\D/g, '').slice(0, 8);
        const masked = this.maskDobDigits(digits);

        if (masked !== event.target.value) {
            event.target.value = masked;
        }

        this._dobTouched = true;
        this.dateOfBirthDisplay = masked;
        this.dateOfBirth = this.ddMmYyyyToIso(masked);
        this.dobError = this.dobValidationError(false);
    }

    handleDobBlur() {
        this.dobError = this.dobValidationError(true);
    }

    /**
     * Builds DD/MM/YYYY as the user types, refusing impossible parts outright rather than
     * taking the digits and objecting afterwards: a day above 31 or a month above 12 is pulled
     * back into range the moment its second digit lands, so 45 and 22 can never be entered.
     * The year cannot be judged until all four digits are in, so it is left to
     * dobValidationError, which also holds it to 1900 and to today.
     */
    maskDobDigits(digits) {
        if (!digits) {
            return '';
        }
        const day = this.clampDatePart(digits.slice(0, 2), 1, 31);
        const month = this.clampDatePart(digits.slice(2, 4), 1, 12);
        const year = digits.slice(4, 8);

        if (digits.length > 4) {
            return `${day}/${month}/${year}`;
        }
        if (digits.length > 2) {
            return `${day}/${month}`;
        }
        return day;
    }

    /** A half-typed part is left alone; a complete one is held inside its bounds. */
    clampDatePart(part, low, high) {
        if (part.length < 2) {
            return part;
        }
        const value = Number(part);
        if (value < low) {
            return String(low).padStart(2, '0');
        }
        if (value > high) {
            return String(high).padStart(2, '0');
        }
        return part;
    }

    /** Lower bound for the date of birth, shared by the typed field and the calendar. */
    get minDobIso() {
        return MIN_DOB_ISO;
    }

    /**
     * The single judge of the typed date, so the field, the blur and the submit can never
     * disagree with one another. `settled` marks the moments the user has finished with the
     * field — a half-typed date is only an error once they have moved on.
     */
    dobValidationError(settled) {
        if (!this.dateOfBirthDisplay) {
            return '';
        }
        if (!this.dateOfBirth) {
            return settled || this.dateOfBirthDisplay.length === 10
                ? 'Please enter a valid date in DD/MM/YYYY format.'
                : '';
        }
        if (this.dateOfBirth > this.todayIso) {
            return 'Date of birth cannot be in the future.';
        }
        if (this.dateOfBirth < MIN_DOB_ISO) {
            return 'Date of birth cannot be earlier than 01/01/1900.';
        }
        return '';
    }

    /**
     * The text actually showing in the date field, taken from whichever of the two layouts
     * is on screen. Both carry data-field="dateOfBirth"; only one is ever in the DOM.
     */
    readVisibleDob() {
        const inputs = Array.from(this.template.querySelectorAll('[data-field="dateOfBirth"]'));
        const onScreen = inputs.find((el) => el.offsetParent !== null) || inputs[0];
        return onScreen && typeof onScreen.value === 'string' ? onScreen.value.trim() : '';
    }

    /**
     * Pulls the tracked date back in line with the field before Continue judges it.
     * dateOfBirthDisplay is only ever written from the input event, so if one of those is
     * ever missed the tracked value sits empty behind text the alumnus can plainly see —
     * and because the date is optional, an empty value is waved straight through. Reading
     * the field itself means a half-typed date is caught on what is on screen, not on what
     * the component believes is on screen.
     */
    syncDobFromInput() {
        const typed = this.readVisibleDob();
        // Only ever adopt text, never clear it: clearing the field already runs through
        // handleDobInput, so a value read back empty here would only mean the read failed,
        // and acting on it would throw away a date the alumnus actually entered.
        if (!typed || typed === this.dateOfBirthDisplay) {
            return;
        }
        this._dobTouched = true;
        this.dateOfBirthDisplay = typed;
        this.dateOfBirth = this.ddMmYyyyToIso(typed);
    }

    /**
     * The browser's own date picker steps a month at a time, so reaching a birth year
     * decades back meant a great deal of clicking. c-ken-date-picker puts the month and
     * year on dropdowns instead, which is the whole reason it exists.
     */
    handleToggleDobPicker() {
        if (this.isDobPickerOpen) {
            this.closeDobPicker();
            return;
        }
        this.isDobPickerOpen = true;
        this.attachDobDismiss();
    }

    handleCloseDobPicker() {
        this.closeDobPicker();
        const button = this.template.querySelector('.dob-calendar-button');
        if (button) {
            button.focus();
        }
    }

    closeDobPicker() {
        this.isDobPickerOpen = false;
        this.detachDobDismiss();
    }

    /**
     * Swallows presses that land inside the date field so the document-level dismiss below
     * never sees them. Testing composedPath() instead does not work here: the site runs on
     * synthetic shadow DOM, which retargets the path so it no longer contains .dob-wrapper,
     * and every press inside the calendar read as "outside" — closing the panel on mousedown,
     * before the click could reach the day.
     */
    handleDobWrapperMouseDown(event) {
        event.stopPropagation();
    }

    /** Closes the calendar on the next press outside the field. */
    attachDobDismiss() {
        if (this.dobDismissHandler) {
            return;
        }
        this.dobDismissHandler = () => this.closeDobPicker();
        // Bubble phase, not capture: the wrapper's handler must get the chance to stop the
        // event first. A capturing listener would run before it and defeat the whole thing.
        document.addEventListener('mousedown', this.dobDismissHandler);
    }

    detachDobDismiss() {
        if (!this.dobDismissHandler) {
            return;
        }
        document.removeEventListener('mousedown', this.dobDismissHandler);
        this.dobDismissHandler = null;
    }

    /** Calendar selection arrives as ISO and drives the visible DD/MM/YYYY text. */
    handleDobPicked(event) {
        this._dobTouched = true;
        this.setDateOfBirth((event.detail && event.detail.value) || '');
        this.closeDobPicker();
    }

    /** Converts a stored yyyy-mm-dd value into the DD/MM/YYYY the field displays. */
    isoToDdMmYyyy(iso) {
        const parts = String(iso || '').slice(0, 10).split('-');
        return parts.length === 3 && parts[0] && parts[1] && parts[2]
            ? `${parts[2]}/${parts[1]}/${parts[0]}`
            : '';
    }

    /** Returns yyyy-mm-dd for a complete, real DD/MM/YYYY date, otherwise ''. */
    ddMmYyyyToIso(text) {
        const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec((text || '').trim());
        if (!match) {
            return '';
        }

        const day = Number(match[1]);
        const month = Number(match[2]);
        const year = Number(match[3]);
        const parsed = new Date(year, month - 1, day);

        const isRealDate = parsed.getFullYear() === year
            && parsed.getMonth() === month - 1
            && parsed.getDate() === day;

        return isRealDate ? `${match[3]}-${match[2]}-${match[1]}` : '';
    }

    /** Keeps the visible DD/MM/YYYY text in step with an ISO value. */
    setDateOfBirth(iso) {
        this.dateOfBirth = iso || '';
        this.dateOfBirthDisplay = this.isoToDdMmYyyy(this.dateOfBirth);
        this.dobError = '';
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
    // =========================================================
    // ✅ REQUIRED-FIELD BORDER STATE
    // Turns just the input box border red for required fields left empty.
    // =========================================================
    fieldClass(field, baseClass) {
        return this.errors[field] ? baseClass + ' has-error' : baseClass;
    }

    clearError(field) {
        if (field && this.errors[field]) {
            const next = { ...this.errors };
            delete next[field];
            this.errors = next;
        }
    }

    get firstNameClass() { return this.fieldClass('firstName', 'custom-input'); }
    get lastNameClass() { return this.fieldClass('lastName', 'custom-input'); }
    get emailClass() { return this.fieldClass('email', 'custom-input'); }
    get currentCityClass() { return this.fieldClass('currentCity', 'custom-input'); }
    get programmeClass() { return this.fieldClass('programmeId', 'custom-select'); }
    get graduationYearClass() { return this.fieldClass('graduationYear', 'custom-select'); }
    get termsCheckboxClass() { return this.fieldClass('agreeToTerms', 'terms-checkbox'); }
    // dobError is tracked on its own rather than in this.errors, so it cannot go through
    // fieldClass with the rest.
    get dobClass() { return this.dobError ? 'custom-input has-error' : 'custom-input'; }
    get isCountryInvalid() { return !!this.errors.country; }
    get isPhoneInvalid() { return !!this.errors.phoneE164; }

    /**
     * The form scrolls inside .form-scroll, so a message on a field further down (the
     * terms checkbox especially) lands out of sight and Continue looks like it did
     * nothing. Bring the first offending field into view, the same way the Education
     * modal does after a failed Save.
     */
    scrollToFirstError() {
        const wrapperByField = {
            firstName: '.field-first-name',
            lastName: '.field-last-name',
            email: '.field-email',
            phoneE164: '.field-phone',
            dateOfBirth: '.field-date-of-birth',
            country: '.field-country',
            currentCity: '.field-current-city',
            graduationYear: '.field-graduation-year',
            programmeId: '.field-programme',
            agreeToTerms: '.terms-section'
        };

        // dobError is kept outside this.errors, so fold it in here: without it a bad date
        // is the one failure that never brings its own field into view, and Continue looks
        // like it did nothing at all.
        const failing = this.dobError
            ? { ...this.errors, dateOfBirth: this.dobError }
            : this.errors;

        // Take whichever errored field sits highest on the page rather than the first
        // in markup order: the desktop layout is two columns, so the earliest field in
        // the DOM is not necessarily the one the alumnus sees first. The desktop and
        // mobile markups both match these selectors, so skip the hidden one.
        let target = null;
        let targetTop = 0;
        Object.keys(wrapperByField).forEach((field) => {
            if (!failing[field]) {
                return;
            }
            const candidates = Array.from(this.template.querySelectorAll(wrapperByField[field]));
            candidates.forEach((el) => {
                if (el.offsetParent === null) {
                    return;
                }
                const top = el.getBoundingClientRect().top;
                if (target === null || top < targetTop) {
                    target = el;
                    targetTop = top;
                }
            });
        });

        if (target) {
            target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
    }

    validateInputs() {
        this.normalizeBeforeSubmit();

        const missingFields = [];
        const nextErrors = {};
        if (!this.firstName) { missingFields.push('First name'); nextErrors.firstName = 'First name is required'; }
        if (!this.lastName) { missingFields.push('Last name'); nextErrors.lastName = 'Last name is required'; }
        if (!this.email) { missingFields.push('Email'); nextErrors.email = 'Email is required'; }
        if (!this.phoneE164) { missingFields.push('Phone number'); nextErrors.phoneE164 = 'Phone number is required'; }
        if (!this.country) { missingFields.push('Country of Residence'); nextErrors.country = 'Country of residence is required'; }
        if (!this.currentCity) { missingFields.push('Current City'); nextErrors.currentCity = 'Current city is required'; }
        if (!this.graduationYear) { missingFields.push('Graduation year'); nextErrors.graduationYear = 'Graduation year is required'; }
        if (!this.programmeId && !this.programme) { missingFields.push('Batch'); nextErrors.programmeId = 'Program is required'; }
        if (!this.agreeToTerms) { missingFields.push('Agreement to terms'); nextErrors.agreeToTerms = 'Please accept the terms to continue'; }

        this.errors = nextErrors;

        if (missingFields.length > 0) {
            this.errorMessage = `Please complete required fields: ${missingFields.join(', ')}`;
            return false;
        }

        // The phone component enforces the selected country's digit range while the
        // user types, but nothing re-checked it at submit — the field was only ever
        // tested for being non-empty, so a short number saved fine. Re-check against
        // the same country rules, reading the country off the number's own dial code
        // and falling back to Country of Residence when it carries none.
        const phoneCheck = validatePhoneNumber(this.phoneE164, this.country, true);
        if (!phoneCheck.valid) {
            this.errors = { ...this.errors, phoneE164: phoneCheck.message };
            this.errorMessage = phoneCheck.message;
            return false;
        }

        const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
        if (!emailRegex.test(this.email)) {
            this.errors = { ...this.errors, email: 'Enter a valid email address' };
            this.errorMessage = 'Please enter a valid email address.';
            return false;
        }

        if (this.linkedinUrl && !this.isValidLinkedinUrl(this.linkedinUrl)) {
            this.linkedinUrlError = 'Please enter a valid URL starting with https:// or www.';
            this.errorMessage = 'Please enter a valid LinkedIn URL.';
            return false;
        }

        this.syncDobFromInput();
        const dobError = this.dobValidationError(true);
        if (dobError) {
            this.dobError = dobError;
            this.errorMessage = dobError;
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
            dateOfBirth: this.dateOfBirth || null,
            nationality: this.nationality || '',
            languages: this.languages || '',
            gender: this.gender || '',
            bloodGroup: this.bloodGroup || '',
            agreeToTerms: Boolean(this.agreeToTerms),
            profileImageUrl: profileImageUrl || ''
        };
    }

    async handleContinue() {
        this.normalizeBeforeSubmit();

        if (!this.validateInputs()) {
            this.scrollToErrorPending = true;
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

            this.dispatchEvent(new CustomEvent('continue', {
                detail: {
                    ...formData,
                    accountId: result && result.accountId ? result.accountId : null
                },
                bubbles: true
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
                bubbles: true
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

        // Same preserve-on-empty rule as the fields above: both prefill paths can
        // land after the user has already typed here (prefillProfile() is fired
        // unawaited from connectedCallback while the parent separately calls
        // setOnboardingData), and an empty server value must not wipe their input.
        this.country = data.country || this.country || '';
        this.state = data.state || this.state || '';
        this.currentCity = data.currentCity || this.currentCity || '';

        this.graduationYear = data.graduationYear || '';
        this.buildGraduationYearOptions(this.graduationYear);

        // Never overwrite a date the alumnus has already touched (see _dobTouched).
        if (!this._dobTouched) {
            this.setDateOfBirth(data.dateOfBirth || this.dateOfBirth || '');
        }
        this.nationality = data.nationality || this.nationality || '';
        this.languages = data.languages || this.languages || '';
        this.gender = data.gender || this.gender || '';
        this.bloodGroup = data.bloodGroup || this.bloodGroup || '';

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

            // Preserve on empty for the same reason as linkedinUrl above — this
            // resolves asynchronously and must not clobber what the user typed.
            this.country = data.country || this.country || '';
            this.state = data.state || this.state || '';
            this.currentCity = data.currentCity || this.currentCity || '';

            this.graduationYear = data.graduationYear || '';
            this.programme = data.programme || '';
            this.programmeId = data.programmeId || '';
            // Never overwrite a date the alumnus has already touched (see _dobTouched).
            if (!this._dobTouched) {
                this.setDateOfBirth(data.dateOfBirth || this.dateOfBirth || '');
            }
            this.nationality = data.nationality || this.nationality || '';
            this.languages = data.languages || this.languages || '';
            this.gender = data.gender || this.gender || '';
            this.bloodGroup = data.bloodGroup || this.bloodGroup || '';
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
                bubbles: true
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

    async loadNationalities() {
        try {
            const options = await getNationalityOptions();
            this.nationalityOptions = options || [];
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading nationalities', error);
            this.nationalityOptions = [];
        }
        try {
            this.genderOptions = (await getGenderOptions()) || [];
        } catch (error) {
            this.genderOptions = [];
        }
        try {
            this.bloodGroupOptions = (await getBloodGroupOptions()) || [];
        } catch (error) {
            this.bloodGroupOptions = [];
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