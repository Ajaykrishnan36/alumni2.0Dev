import { api, LightningElement, track } from 'lwc';
import linkedinLogoUrl from '@salesforce/resourceUrl/LoginLinkedinIcon';
import { NavigationMixin } from 'lightning/navigation';
import requestSignupOtp from '@salesforce/apex/KenPortalRegisterController.requestSignupOtp';
import verifySignupOtp from '@salesforce/apex/KenPortalRegisterController.verifySignupOtp';
import getLinkedInData from '@salesforce/apex/KenLinkedInController.getLinkedInData';
import basePath from '@salesforce/community/basePath';
import RegistrationSuccessGif from '@salesforce/resourceUrl/RegistrationSuccessGif';
import KenPoweredbyLogo from '@salesforce/resourceUrl/kenPoweredbyLogo';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getRegistrationOptions from '@salesforce/apex/KenPortalRegisterController.getRegistrationOptions';
export default class KenRegisterPage extends NavigationMixin(LightningElement) {
    @api startUrl = '';
    @api institutionLabel = ''; // org institution alias, used only in the "Please Note" copy
    referalCode = '';
    email = '';
    firstName = '';
    lastName = '';
    phone = ''; // E.164 value for API
    phoneInput = ''; // national value for UI
    regNumber = '';
    gradYear = '';
    yearOfEnrollment = '';
    @track institutionName = '';
    @track programPlan = '';
    @track instituteOptions = [];
    // Programs keyed by institute name — drives the dependent program picker.
    @track programsByInstitute = {};
    @track fromGradYear = 1980;
    @track defaultDialCountry = 'none';
    @track optionsLoaded = false;
    errorMessage = '';
    isLoading = false;
    linkedinLogo = linkedinLogoUrl;
    kenPoweredbyLogo = KenPoweredbyLogo;
    @track showOTP = false;
    @track isSuccessToastVisible = false;
    @track isErrorToastVisible = false;
    @track errorTitle = '';
    @track errorDescription = '';
    @track successTitle = 'OTP sent successfully!';
    @track successDescription = 'We have emailed a verification code. Enter it to continue your signup.';
    @track showSuccessGif = false;
    successTimeout;
    errorTimeout;
    @track otpInputs = [
        { id: '0', value: '' },
        { id: '1', value: '' },
        { id: '2', value: '' },
        { id: '3', value: '' }
    ];
    @track timerSeconds = 120;
    @track canResend = false;
    timerInterval;

    registrationSuccessGifUrl = RegistrationSuccessGif;

    collapseContinuousSpaces(value) {
        if (value === null || value === undefined) return '';
        return String(value).replace(/\s{2,}/g, ' ');
    }

    collapseSpacesAndTrim(value) {
        if (value === null || value === undefined) return '';
        return String(value).replace(/\s{2,}/g, ' ').trim();
    }

    removeSpecialChars(value) {
        if (value === null || value === undefined) return '';
        // Keep letters (incl. accented/Unicode), spaces, hyphens and apostrophes only.
        // This also strips digits and any symbol (@, #, $, !, etc.).
        return String(value).replace(/[^\p{L}\s'-]/gu, '');
    }

    normalizeBeforeSubmit() {
        // Clean values before sending to Apex
        this.firstName = this.removeSpecialChars(this.collapseSpacesAndTrim(this.firstName));
        this.lastName = this.removeSpecialChars(this.collapseSpacesAndTrim(this.lastName));

        // For email/reg/phone: trim + collapse multiple spaces
        this.email = this.collapseSpacesAndTrim(this.email);
        this.regNumber = this.collapseSpacesAndTrim(this.regNumber);

        // phone comes from custom component; still sanitize just in case
        this.phone = this.collapseSpacesAndTrim(this.phone);
        this.phoneInput = this.collapseSpacesAndTrim(this.phoneInput);
    }

    get pleaseNoteText() {
        const inst = (this.institutionLabel || '').trim();
        const instPart = inst ? `${inst} ` : '';
        return `If you have studied at more than one ${instPart}institute, register using your latest graduation details. Additional institute affiliations can be added after registration.`;
    }

    get timerDisplay() {
        const minutes = Math.floor(this.timerSeconds / 60);
        const seconds = this.timerSeconds % 60;
        return `${minutes}:${seconds.toString().padStart(2, '0')}`;
    }

    get gradOptions() {
        const options = [];
        const currentYear = new Date().getFullYear();
        const startYear = (this.fromGradYear && this.fromGradYear >= 1900) ? this.fromGradYear : 1980;
        for (let i = currentYear; i >= startYear; i--) {
            options.push({ label: i.toString(), value: i.toString() });
        }
        return options;
    }

    // Program picker is dependent on the institute: it only offers the programs
    // that institute (Learning Program Plan provider) actually runs, and stays
    // disabled until an institute is chosen.
    get programOptions() {
        if (!this.institutionName) return [];
        return this.programsByInstitute[this.institutionName] || [];
    }
    get isProgramDisabled() {
        return !this.institutionName;
    }
    get programPlaceholder() {
        return this.institutionName ? 'Select' : 'Select an institute first';
    }

    connectedCallback() {
        try {
            const params = new URL(window.location.href).searchParams;
            this.referalCode = params.get('referal') || '';
        } catch (e) { /* ignore in non-browser envs */ }

        document.documentElement.style.setProperty('--primary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--secondary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--tertiary-color', '#FFFFFF');
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
        this.restoreFormData();
        getRegistrationOptions()
            .then(({ institutes, programsByInstitute, fromGradYear, defaultDialCountry }) => {
                this.instituteOptions = institutes || [];
                this.programsByInstitute = programsByInstitute || {};
                if (fromGradYear) {
                    this.fromGradYear = fromGradYear;
                }
                if (defaultDialCountry) {
                    this.defaultDialCountry = defaultDialCountry;
                }
            })
            .catch((e) => {
                // Non-fatal — the comboboxes just stay empty.
                // eslint-disable-next-line no-console
                console.error('Error loading registration options', e);
            })
            .finally(() => {
                // Render the phone input now that the default country is known
                // (or after a failure, falling back to the 'none' default).
                this.optionsLoaded = true;
            });
    }

    restoreFormData() {
        try {
            const stored = window.sessionStorage.getItem('registerFormData');
            if (stored) {
                const data = JSON.parse(stored);
                this.email = data.email || '';
                this.firstName = data.firstName || '';
                this.lastName = data.lastName || '';
                this.phone = data.phone || '';
                this.phoneInput = data.phoneInput || data.phone || '';
                this.regNumber = data.regNumber || '';
                this.gradYear = data.gradYear || '';
                this.yearOfEnrollment = data.yearOfEnrollment || '';
                this.institutionName = data.institutionName || '';
                this.programPlan = data.programPlan || '';
            }
        } catch (e) {
            // ignore session read errors
        }
    }

    persistFormData() {
        const payload = {
            email: this.email,
            firstName: this.firstName,
            lastName: this.lastName,
            phone: this.phone,
            phoneInput: this.phoneInput,
            regNumber: this.regNumber,
            gradYear: this.gradYear,
            yearOfEnrollment: this.yearOfEnrollment,
            institutionName: this.institutionName,
            programPlan: this.programPlan
        };
        try {
            window.sessionStorage.setItem('registerFormData', JSON.stringify(payload));
        } catch (e) {
            // ignore storage errors
        }
    }

    clearFormData() {
        try {
            window.sessionStorage.removeItem('registerFormData');
        } catch (e) {
            // ignore
        }
    }

    handleInputChange({ target }) {
        const { id } = target.dataset;
        let value = target.value;

        // Allow only single continuous space (collapse 2+ to 1)
        value = this.collapseContinuousSpaces(value);

        // Strip digits and special characters for name fields
        if (id === 'firstName' || id === 'lastName') {
            value = this.removeSpecialChars(value);
        }

        // Reflect cleaned value in UI
        if (target.value !== value) {
            target.value = value;
        }

        this[id] = value;
        this.persistFormData();
    }

    handleOnBlur({ target }) {
        const { id } = target.dataset;
        const { value } = target;
        this.validateField(id, value);
        this.persistFormData();
    }

    handlePicklistChange(event) {
        const id = event.currentTarget.dataset.id;
        const value = event.detail ? event.detail.value : '';
        this[id] = value;
        // Institute drives the program list — clear any now-invalid program pick
        // so a stale selection from a different institute can't linger.
        if (id === 'institutionName') {
            this.programPlan = '';
        }
        this.persistFormData();
        this.validateField(id, value);
    }

    handleEnterKey(event) {
        if (event.keyCode == 13) {
            event.preventDefault();
            if (!this.showOTP) {
                this.handleRegister();
            } else {
                this.handleVerifyOTP();
            }
        }
    }

    validateField(field, value) {
        let isValid = true;
        let message = '';

        // Skip validation for non-input fields if any
        if(!field) return true;

        // Required check should use trimmed value
        const trimmedValue = (typeof value === 'string') ? value.trim() : value;

        if (!trimmedValue) {
            if (field !== 'regNumber') {
                isValid = false;
                message = 'This field cannot be empty.';
            }
        } else if (field === 'email' && !this.isValidEmail(trimmedValue)) {
            isValid = false;
            message = 'Please enter a valid email address.';
        } else if (field === 'phone' && (!trimmedValue || trimmedValue.length < 10)) {
            isValid = false;
            message = 'Please enter a valid phone number.';
        }

        this.setCustomValidity(field, isValid, message);
        return isValid;
    }

    handlePhoneChange(event) {
        const { e164, national } = event.detail;

        // Keep what custom component sends, but still avoid 2+ spaces just in case
        const safeE164 = this.collapseContinuousSpaces(e164 || '');
        const safeNational = this.collapseContinuousSpaces(national || '');

        this.phone = safeE164;
        this.phoneInput = safeNational;

        this.persistFormData();

        // Clear any prior error while typing; validation runs only on Register.
        const phoneComponent = this.template.querySelector('c-ken-custom-phone-input');
        if (phoneComponent && typeof phoneComponent.setCustomValidity === 'function') {
            phoneComponent.setCustomValidity('');
        }
    }

    setCustomValidity(field, isValid, message) {
        const inputField = this.template.querySelector(`[data-id="${field}"]`);
        if (inputField && typeof inputField.setCustomValidity === 'function') {
            inputField.setCustomValidity(isValid ? '' : message);
            inputField.reportValidity();
        } else if (!isValid) {
            const friendly = field === 'gradYear' ? 'Please select your year of graduation.'
                : field === 'yearOfEnrollment' ? 'Please select your year of enrollment.'
                : field === 'programPlan' ? 'Please select your program.'
                : field === 'institutionName' ? 'Please select your institute.'
                : message;
            this.showErrorToast('Missing information', friendly);
        }
    }

    isValidEmail(email) {
        const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
        return emailRegex.test(email);
    }

    async handleRegister() {
        // Final sanitize before submit
        this.normalizeBeforeSubmit();
        this.persistFormData();
        const isFirstNameValid = this.validateField('firstName', this.firstName);
        const isLastNameValid = this.validateField('lastName', this.lastName);
        const isEmailValid = this.validateField('email', this.email);
        // Validate phone component directly (selector must match HTML: c-ken-custom-phone-input)
        const phoneComponent = this.template.querySelector('c-ken-custom-phone-input');
        const isPhoneValid = phoneComponent ? phoneComponent.validate() : false;
        const isGradYearValid = this.validateField('gradYear', this.gradYear);
        const isEnrollValid = this.validateField('yearOfEnrollment', this.yearOfEnrollment);
        const isProgramValid = this.validateField('programPlan', this.programPlan);
        const isInstituteValid = this.validateField('institutionName', this.institutionName);

        if (!isFirstNameValid || !isLastNameValid || !isEmailValid || !isPhoneValid || !isGradYearValid || !isEnrollValid || !isProgramValid || !isInstituteValid) {
            // Each validateField()/phoneComponent.validate() call above already ran
            // reportValidity(), which for a real lightning-input delegates to the
            // native input's reportValidity() — that auto-scrolls its field into
            // view. With several invalid fields, each call scrolls somewhere new
            // while the form is still reflowing from the previous field's error
            // message, so the page ends up wherever the *last* call happened to
            // land rather than at the first error — it looks like the page
            // randomly "jumps down". Explicitly scroll to the first invalid
            // field last, so it deterministically wins over those native scrolls.
            const firstInvalidField = !isFirstNameValid ? 'firstName'
                : !isLastNameValid ? 'lastName'
                : !isEmailValid ? 'email'
                : !isGradYearValid ? 'gradYear'
                : !isEnrollValid ? 'yearOfEnrollment'
                : !isProgramValid ? 'programPlan'
                : !isInstituteValid ? 'institutionName'
                : null;
            const elToScroll = firstInvalidField
                ? this.template.querySelector(`[data-id="${firstInvalidField}"]`)
                : this.template.querySelector('c-ken-custom-phone-input');
            if (elToScroll && typeof elToScroll.scrollIntoView === 'function') {
                elToScroll.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            return;
        }

        if (this.yearOfEnrollment && this.gradYear
            && parseInt(this.yearOfEnrollment, 10) >= parseInt(this.gradYear, 10)) {
            this.showErrorToast('Invalid years', 'Year of enrollment must be earlier than the year of graduation.');
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        this.isErrorToastVisible = false;
        this.isSuccessToastVisible = false;

        try {
            const payload = this.buildSignupPayload();
            await requestSignupOtp({ requestJson: JSON.stringify(payload) });
            this.showOTP = true;
            this.startTimer();
            this.showSuccessToast('OTP sent successfully!', 'Check your inbox for the verification code to continue.');
            this.persistFormData();
        } catch (error) {
            const errMsg = error?.body?.message || 'Unable to send OTP. Please try again.';
            this.showErrorToast('Registration blocked', errMsg);
            this.errorMessage = errMsg;
            if (errMsg === 'An account with this email already exists. Please login.') {
                this.clearFormData();
                window.setTimeout(() => {
                    window.location.href = `${basePath}/login`;
                }, 3000);
            }
        } finally {
            this.isLoading = false;
        }
    }

    startTimer() {
        this.timerSeconds = 120;
        this.canResend = false;
        
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
        }

        this.timerInterval = setInterval(() => {
            this.timerSeconds--;
            if (this.timerSeconds <= 0) {
                clearInterval(this.timerInterval);
                this.canResend = true;
            }
        }, 1000);
    }

    handleOTPInput(event) {
        const index = parseInt(event.target.dataset.index);
        const value = event.target.value.replace(/[^0-9]/g, '');
        
        if (value) {
            this.otpInputs[index].value = value;
            this.otpInputs = [...this.otpInputs];
            
            // Auto-focus next input
            if (index < 3) {
                const nextInput = this.template.querySelector(`[data-index="${index + 1}"]`);
                if (nextInput) {
                    nextInput.focus();
                }
            }
        } else {
            this.otpInputs[index].value = '';
            this.otpInputs = [...this.otpInputs];
        }
    }

    handleOTPKeyDown(event) {
        const index = parseInt(event.target.dataset.index);
        
        if (event.key === 'Backspace' && !event.target.value && index > 0) {
            const prevInput = this.template.querySelector(`[data-index="${index - 1}"]`);
            if (prevInput) {
                prevInput.focus();
            }
        }
    }

    handleOTPPaste(event) {
        event.preventDefault();
        const pastedData = event.clipboardData.getData('text').replace(/[^0-9]/g, '').slice(0, 4);
        
        for (let i = 0; i < pastedData.length && i < 4; i++) {
            this.otpInputs[i].value = pastedData[i];
        }
        this.otpInputs = [...this.otpInputs];
        
        // Focus last filled input
        const lastIndex = Math.min(pastedData.length - 1, 3);
        const lastInput = this.template.querySelector(`[data-index="${lastIndex}"]`);
        if (lastInput) {
            lastInput.focus();
        }
    }

    handleEditEmail() {
        this.showOTP = false;
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
        }
    }

    async handleResendOTP() {
        if (!this.canResend) return;

        // sanitize email for resend
        this.email = this.collapseSpacesAndTrim(this.email);

        this.isLoading = true;
        try {
            const payload = { email: this.email };
            await requestSignupOtp({ requestJson: JSON.stringify(payload) });
            this.otpInputs = this.otpInputs.map(input => ({ ...input, value: '' }));
            this.startTimer();
            this.showSuccessToast('OTP resent', 'We have sent a new verification code to your email.');
        } catch (error) {
            const errMsg = error?.body?.message || 'Failed to resend OTP. Please try again.';
            this.errorMessage = errMsg;
            this.showErrorToast('Resend failed', errMsg);
        } finally {
            this.isLoading = false;
        }
    }

    async handleVerifyOTP() {
        const otpCode = this.otpInputs.map(input => input.value).join('');
        
        if (otpCode.length !== 4) {
            this.errorMessage = 'Please enter the complete OTP.';
            return;
        }

        this.normalizeBeforeSubmit();
        this.persistFormData();

        this.isLoading = true;
        this.errorMessage = '';

        try {
            const payload = {
                ...this.buildSignupPayload(),
                otpEntered: otpCode
            };
            await verifySignupOtp({ requestJson: JSON.stringify(payload) });
            this.dispatchEvent(new CustomEvent('registercomplete', {
                detail: { email: this.email },
                bubbles: true,
                composed: true
            }));
            this.showOTP = false;
            this.showSuccessGif = true;
            this.clearFormData();
        } catch (error) {
            const errMsg = error.body?.message || 'Invalid OTP. Please try again.';
            this.errorMessage = errMsg;
            this.showErrorToast('OTP verification failed', errMsg);
            this.otpInputs = this.otpInputs.map(input => ({ ...input, value: '' }));
        } finally {
            this.isLoading = false;
        }
    }

    handleLinkedInLogin() {
        // LinkedIn sync entry point for register. Comment out getLinkedInData()
        // after testing to avoid creating/updating Contact data.
        const email = window.prompt('Enter the Contact email that has the LinkedIn URL:');
        if (!email) return;

        this.isLoading = true;
        this.errorMessage = '';
        this.isErrorToastVisible = false;

        getLinkedInData({ accountId: null, email })
            .then(() => {
                window.alert('LinkedIn profile synced successfully (Contact data updated).');
            })
            .catch(error => {
                const errMsg = error?.body?.message || 'LinkedIn sync failed. Please try again.';
                this.errorMessage = errMsg;
                this.showErrorToast('LinkedIn sync failed', errMsg);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    buildSignupPayload() {
        return {
            email: this.email || '',
            firstName: this.firstName || '',
            lastName: this.lastName || '',
            phone: this.phone || '',
            regNumber: this.regNumber || '',
            gradYear: this.gradYear || '',
            yearOfEnrollment: this.yearOfEnrollment || '',
            institutionName: this.institutionName || '',
            programPlan: this.programPlan || '',
            referalCode: this.referalCode || ''
        };
    }

    renderedCallback() {
        // Inject dropdown styles for combobox
        this.injectDropdownStyles();
    }

    injectDropdownStyles() {
        // Check if styles are already injected
        let styleElement = document.getElementById('register-page-dropdown-styles');
        if (!styleElement) {
            styleElement = document.createElement('style');
            styleElement.id = 'register-page-dropdown-styles';
            document.head.appendChild(styleElement);
            
            styleElement.textContent = `
                .slds-listbox,
                .slds-dropdown {
                    background-color: #ffffff !important;
                }
                .slds-listbox__option,
                .slds-dropdown__item {
                    background-color: #ffffff !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option:hover,
                .slds-dropdown__item:hover {
                    background-color: #f3f4f6 !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    outline: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option[aria-selected="true"],
                .slds-dropdown__item[aria-selected="true"] {
                    background-color: #ffffff !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option *,
                .slds-dropdown__item *,
                .slds-listbox__option:hover *,
                .slds-dropdown__item:hover * {
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
            `;
        }
    }

    disconnectedCallback() {
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
        }
        if (this.successTimeout) {
            window.clearTimeout(this.successTimeout);
        }
        if (this.errorTimeout) {
            window.clearTimeout(this.errorTimeout);
        }
        
        // Clean up injected dropdown styles
        const styleElement = document.getElementById('register-page-dropdown-styles');
        if (styleElement) {
            styleElement.remove();
        }
    }

    handleBackdropClick() {
        this.isErrorToastVisible = false;
        this.isSuccessToastVisible = false;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    showSuccessToast(title, description) {
        this.successTitle = title;
        this.successDescription = description;
        this.isSuccessToastVisible = true;

        window.clearTimeout(this.successTimeout);
        this.successTimeout = window.setTimeout(() => {
            this.isSuccessToastVisible = false;
        }, 1500);
    }

    showErrorToast(title, description) {
        this.errorTitle = title;
        this.errorDescription = description;
        this.isErrorToastVisible = true;
        window.clearTimeout(this.errorTimeout);
        this.errorTimeout = window.setTimeout(() => {
            this.isErrorToastVisible = false;
        }, 1500);
    }

    handleLoginRedirect() {
        window.location.href = `${basePath}/login`;
    }

    handleGotIt() {
        this.clearFormData();
        window.location.href = `${basePath}/login`;
    }
}