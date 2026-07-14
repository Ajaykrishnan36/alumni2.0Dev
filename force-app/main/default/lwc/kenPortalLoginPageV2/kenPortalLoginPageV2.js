import { LightningElement, api, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import login from '@salesforce/apex/KenCommunityLoginV2Controller.login';

const VIEWS = {
    METHOD_PICKER: 'method-picker',
    LINK_STEP: 'alumni-link-step1',
    EMAIL_STEP1: 'email-step1',
    EMAIL_STEP2: 'email-step2',
    PHONE_STEP1: 'phone-step1',
    PHONE_STEP2: 'phone-step2',
    PASSWORD_STEP: 'password-step1',
    REQUEST_STEP1: 'request-access-step1',
    REQUEST_STEP2: 'request-access-step2',
    REQUEST_STEP3: 'request-access-step3',
    REQUEST_STEP4: 'request-access-step4',
    REQUEST_SUCCESS: 'request-success'
};

export default class KenPortalLoginPageV2 extends LightningElement {
    @api institutionName = 'KU';
    @api startUrl = '/alumninew/';
    @api heroImageUrl = '';
    @api institutionLogoUrl = '';
    @api poweredByLogoUrl = '';

    @track view = VIEWS.METHOD_PICKER;
    @track selectedMethod = 'link';

    // Form fields
    @track accessLink = '';
    @track emailValue = '';
    @track emailOtp = '';
    @track phoneValue = '';
    @track phoneOtp = '';
    @track usernameValue = '';
    @track passwordValue = '';
    @track showPassword = false;

    get passwordType() { return this.showPassword ? 'text' : 'password'; }
    get passwordEyeIcon() { return this.showPassword ? '🙈' : '👁'; }
    togglePassword() { this.showPassword = !this.showPassword; }

    // Request-access form
    @track reqName = '';
    @track reqEmail = '';
    @track reqPhone = '';
    @track reqGradYear = '';
    @track reqLinkedIn = '';
    @track reqCompany = '';
    @track reqRole = '';
    @track reqCity = '';

    @track errorMessage = '';
    @track noticeMessage = '';
    @track isSubmitting = false;

    // ===== view flags =====
    get isMethodPicker() { return this.view === VIEWS.METHOD_PICKER; }
    get isLinkStep() { return this.view === VIEWS.LINK_STEP; }
    get isEmailStep1() { return this.view === VIEWS.EMAIL_STEP1; }
    get isEmailStep2() { return this.view === VIEWS.EMAIL_STEP2; }
    get isPhoneStep1() { return this.view === VIEWS.PHONE_STEP1; }
    get isPhoneStep2() { return this.view === VIEWS.PHONE_STEP2; }
    get isPasswordStep() { return this.view === VIEWS.PASSWORD_STEP; }
    get isRequestStep1() { return this.view === VIEWS.REQUEST_STEP1; }
    get isRequestStep2() { return this.view === VIEWS.REQUEST_STEP2; }
    get isRequestStep3() { return this.view === VIEWS.REQUEST_STEP3; }
    get isRequestStep4() { return this.view === VIEWS.REQUEST_STEP4; }
    get isRequestSuccess() { return this.view === VIEWS.REQUEST_SUCCESS; }

    get inRequestFlow() {
        return this.isRequestStep1 || this.isRequestStep2 || this.isRequestStep3 || this.isRequestStep4 || this.isRequestSuccess;
    }

    // ===== Hero =====
    get heroTitle() {
        return 'Welcome back to the ' + this.institutionName + ' alumni network.';
    }

    get heroJoinTitle() {
        return 'Join the ' + this.institutionName + ' alumni network';
    }

    // ===== Progress =====
    get progressStyle() {
        let pct = 20;
        if (this.isMethodPicker || this.isRequestStep1) pct = 20;
        else if (this.isLinkStep || this.isEmailStep1 || this.isPhoneStep1 || this.isPasswordStep || this.isRequestStep2) pct = 40;
        else if (this.isEmailStep2 || this.isPhoneStep2 || this.isRequestStep3) pct = 60;
        else if (this.isRequestStep4) pct = 80;
        else if (this.isRequestSuccess) pct = 100;
        return 'width:' + pct + '%';
    }

    // ===== Method tile classes =====
    get linkMethodClass() {
        return this.selectedMethod === 'link' ? 'method is-active' : 'method';
    }
    get emailMethodClass() {
        return this.selectedMethod === 'email' ? 'method is-active' : 'method';
    }
    get phoneMethodClass() {
        return this.selectedMethod === 'phone' ? 'method is-active' : 'method';
    }
    get passMethodClass() {
        return this.selectedMethod === 'pass' ? 'method is-active' : 'method';
    }

    get hasError() { return !!this.errorMessage; }
    get hasNotice() { return !!this.noticeMessage; }
    get submitLabel() { return this.isSubmitting ? 'Signing in…' : 'Continue →'; }

    // ===== Handlers =====
    handleMethodSelect(event) {
        const m = event.currentTarget.dataset.method;
        this.selectedMethod = m;
        this.errorMessage = '';
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        this[field] = event.target.value;
        if (this.errorMessage) this.errorMessage = '';
    }

    handleMethodContinue() {
        this.errorMessage = '';
        this.noticeMessage = '';
        if (this.selectedMethod === 'link') this.view = VIEWS.LINK_STEP;
        else if (this.selectedMethod === 'email') this.view = VIEWS.EMAIL_STEP1;
        else if (this.selectedMethod === 'phone') this.view = VIEWS.PHONE_STEP1;
        else if (this.selectedMethod === 'pass') this.view = VIEWS.PASSWORD_STEP;
    }

    handleBackToPicker() {
        this.view = VIEWS.METHOD_PICKER;
        this.errorMessage = '';
        this.noticeMessage = '';
    }

    handleSwitchToRequest(event) {
        if (event) event.preventDefault();
        // Route to the dedicated registration page instead of the old in-login
        // multi-step wizard. basePath resolves the community prefix (e.g. /alumninew).
        try {
            window.location.assign(basePath + '/SelfRegister');
        } catch (e) {
            window.location.href = basePath + '/SelfRegister';
        }
    }

    handleForgotPassword(event) {
        if (event) event.preventDefault();
        // Dedicated V2 forgot-password page (triggers Site.forgotPassword).
        try {
            window.location.assign(basePath + '/ForgotPassword');
        } catch (e) {
            window.location.href = basePath + '/ForgotPassword';
        }
    }

    handleSwitchToLogin(event) {
        if (event) event.preventDefault();
        this.view = VIEWS.METHOD_PICKER;
        this.errorMessage = '';
        this.noticeMessage = '';
    }

    // --- Alumni Link method ---
    handleLinkSubmit() {
        if (!this.accessLink) {
            this.errorMessage = 'Please paste your access link.';
            return;
        }
        this.dispatchEvent(new CustomEvent('link-requested', { detail: { link: this.accessLink } }));
        this.noticeMessage = 'Feature coming soon. Your access link flow will be available shortly.';
    }

    // --- Email + secure link ---
    handleEmailStep1Submit() {
        if (!this.emailValue) {
            this.errorMessage = 'Please enter your registered email.';
            return;
        }
        this.dispatchEvent(new CustomEvent('email-otp-requested', { detail: { email: this.emailValue } }));
        this.view = VIEWS.EMAIL_STEP2;
        this.noticeMessage = 'Feature coming soon. OTP step is visual only for now.';
    }

    handleEmailStep2Submit() {
        this.noticeMessage = 'Feature coming soon. Email + secure link sign-in is not yet enabled.';
    }

    handleEmailBack() {
        this.view = VIEWS.EMAIL_STEP1;
        this.noticeMessage = '';
    }

    // --- Phone + OTP ---
    handlePhoneStep1Submit() {
        if (!this.phoneValue) {
            this.errorMessage = 'Please enter your mobile number.';
            return;
        }
        this.dispatchEvent(new CustomEvent('phone-otp-requested', { detail: { phone: this.phoneValue } }));
        this.view = VIEWS.PHONE_STEP2;
        this.noticeMessage = 'Feature coming soon. OTP step is visual only for now.';
    }

    handlePhoneStep2Submit() {
        this.noticeMessage = 'Feature coming soon. Phone + OTP sign-in is not yet enabled.';
    }

    handlePhoneBack() {
        this.view = VIEWS.PHONE_STEP1;
        this.noticeMessage = '';
    }

    // --- Username + Password (REAL AUTH) ---
    async handlePasswordSubmit(event) {
        if (event && event.preventDefault) event.preventDefault();
        if (this.isSubmitting) return;
        if (!this.usernameValue || !this.passwordValue) {
            this.errorMessage = 'Enter both username and password.';
            return;
        }
        this.isSubmitting = true;
        this.errorMessage = '';
        try {
            const result = await login({
                email: this.usernameValue,
                password: this.passwordValue,
                communityStartUrl: this.startUrl
            });
            if (result && result.url) {
                window.location.href = result.url;
            } else {
                this.errorMessage = 'Login succeeded but no redirect URL returned.';
                this.isSubmitting = false;
            }
        } catch (err) {
            const msg = err && err.body && err.body.message
                ? err.body.message
                : (err && err.message ? err.message : 'Unable to sign in. Check your credentials and try again.');
            this.errorMessage = msg;
            this.isSubmitting = false;
        }
    }

    // --- Request access flow ---
    handleRequestNext1() {
        this.view = VIEWS.REQUEST_STEP2;
    }

    handleRequestNext2() {
        if (!this.reqName || !this.reqEmail) {
            this.errorMessage = 'Please enter your name and email.';
            return;
        }
        this.view = VIEWS.REQUEST_STEP3;
    }

    handleRequestNext3() {
        this.view = VIEWS.REQUEST_STEP4;
    }

    handleRequestNext4() {
        this.dispatchEvent(new CustomEvent('access-request-submitted', {
            detail: {
                name: this.reqName,
                email: this.reqEmail,
                phone: this.reqPhone,
                gradYear: this.reqGradYear,
                linkedIn: this.reqLinkedIn,
                company: this.reqCompany,
                role: this.reqRole,
                city: this.reqCity
            }
        }));
        this.view = VIEWS.REQUEST_SUCCESS;
        this.noticeMessage = '';
    }

    handleRequestBack2() { this.view = VIEWS.REQUEST_STEP1; this.errorMessage = ''; }
    handleRequestBack3() { this.view = VIEWS.REQUEST_STEP2; this.errorMessage = ''; }
    handleRequestBack4() { this.view = VIEWS.REQUEST_STEP3; this.errorMessage = ''; }
}