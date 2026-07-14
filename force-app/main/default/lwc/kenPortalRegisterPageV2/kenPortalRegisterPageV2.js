import { LightningElement, api, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import registerAlumni from '@salesforce/apex/KenPortalRegistrationController.registerAlumni';
import verifyRegistrationOtp from '@salesforce/apex/KenPortalRegistrationController.verifyRegistrationOtp';
import resendRegistrationOtp from '@salesforce/apex/KenPortalRegistrationController.resendRegistrationOtp';
import KEN_LOGO from '@salesforce/resourceUrl/Ken_logo';

const CURRENT_YEAR = new Date().getFullYear();
const GRADUATION_YEARS = Array.from({ length: 60 }, (_, i) => `${CURRENT_YEAR - i}`);

const NAME_RE     = /^[A-Za-z][A-Za-z .'-]*$/;        // letters/space/'/-/. only, no digits
const EMAIL_RE    = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PHONE_RE    = /^[0-9]{6,15}$/;                  // digits only
const LINKEDIN_RE = /^(https?:\/\/)?([a-z0-9-]+\.)?linkedin\.com\/.+$/i;
const RESEND_COOLDOWN_SECS = 30;

export default class KenPortalRegisterPageV2 extends LightningElement {
    @api institutionName = 'Name of the Institute';
    @api heroImageUrl = '';
    @api institutionLogoUrl = '';
    @api poweredByLogoUrl = '';

    @track form = {
        firstName: '',
        lastName: '',
        email: '',
        countryCode: '+91',
        phone: '',
        universityRegNumber: '',
        graduationYear: '',
        linkedinUrl: ''
    };
    @track errors = {};
    @track isSubmitting = false;
    // Three-state view: 'form' (initial) → 'otp' (after registerAlumni) → 'submitted' (after verify).
    @track stage = 'form';
    @track serverError = '';

    // OTP state
    @track otpDigits = ['', '', '', '', '', ''];
    @track otpError = '';
    @track otpVerifying = false;
    @track resendCooldown = 0; // seconds remaining; 0 = resend enabled
    @track resending = false;
    _resendTimer = null;

    countryCodeOptions = [
        { label: '+91', value: '+91' },
        { label: '+1', value: '+1' },
        { label: '+44', value: '+44' },
        { label: '+61', value: '+61' },
        { label: '+971', value: '+971' }
    ];

    get yearOptions() {
        return [
            { label: 'Select', value: '' },
            ...GRADUATION_YEARS.map((y) => ({ label: y, value: y }))
        ];
    }

    // Hero always carries a branded gradient so the panel is never blank; a real
    // image (set in Experience Builder) overlays it when provided.
    get heroStyle() {
        // Violet brand gradient matching the login page (--brand-grad-from/to:
        // #818cf8 → #8b5cf6) so Login → Register feels seamless.
        const grad = 'linear-gradient(135deg, #818cf8 0%, #8b5cf6 100%)';
        return this.heroImageUrl
            ? `background-image: linear-gradient(135deg, rgba(129,140,248,0.85) 0%, rgba(139,92,246,0.92) 100%), url('${this.heroImageUrl}'); background-size: cover; background-position: center;`
            : `background-image: ${grad};`;
    }

    // ---- view-state getters ----
    get isStageForm()      { return this.stage === 'form'; }
    get isStageOtp()       { return this.stage === 'otp'; }
    get isStageSubmitted() { return this.stage === 'submitted'; }
    // Back-compat for any external template still keying on submitted.
    get submitted()        { return this.stage === 'submitted'; }

    // ---- per-field error text + input classes ----
    get firstNameClass() { return this.errors.firstName ? 'input input--error' : 'input'; }
    get lastNameClass()  { return this.errors.lastName ? 'input input--error' : 'input'; }
    get emailClass()     { return this.errors.email ? 'input input--error' : 'input'; }
    get phoneWrapClass() { return this.errors.phone ? 'phone phone--error' : 'phone'; }
    get regClass()       { return this.errors.universityRegNumber ? 'input input--error' : 'input'; }
    get yearClass()      { return this.errors.graduationYear ? 'select input--error' : 'select'; }
    get linkedinClass()  { return this.errors.linkedinUrl ? 'input input--error' : 'input'; }
    get submitLabel()    { return this.isSubmitting ? 'Sending code…' : 'Register'; }
    // Defaults to the bundled Kenverse logo when no override URL is configured.
    get poweredByLogo()  { return this.poweredByLogoUrl || KEN_LOGO; }

    // ---- OTP getters ----
    get otpBoxes() {
        // Stable keys + bound values so each <input> stays mounted across edits.
        return this.otpDigits.map((v, i) => ({ key: `otp-${i}`, idx: i, value: v }));
    }
    get otpIsComplete() {
        return this.otpDigits.every(d => /^[0-9]$/.test(d));
    }
    get otpSubmitDisabled() { return !this.otpIsComplete || this.otpVerifying; }
    get otpSubmitLabel()    { return this.otpVerifying ? 'Verifying…' : 'Verify & submit'; }
    get resendDisabled()    { return this.resendCooldown > 0 || this.resending; }
    get resendLabel() {
        if (this.resending) return 'Sending…';
        if (this.resendCooldown > 0) return `Resend in ${this.resendCooldown}s`;
        return 'Resend code';
    }
    get maskedEmail() {
        const e = this.form.email || '';
        const at = e.indexOf('@');
        if (at < 2) return e;
        const name = e.substring(0, at);
        const visible = name.length <= 2 ? name : name.substring(0, 2);
        return visible + '***' + e.substring(at);
    }

    // ---- input handlers ----
    handleInput(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        let value = event.target.value;
        // Live sanitisation: names reject digits/symbols, phone rejects non-digits.
        if (field === 'firstName' || field === 'lastName') value = value.replace(/[^A-Za-z .'-]/g, '');
        if (field === 'phone') value = value.replace(/[^0-9]/g, '');
        this.form = { ...this.form, [field]: value };
        if (this.errors[field]) {
            const next = { ...this.errors };
            delete next[field];
            this.errors = next;
        }
        if (this.serverError) this.serverError = '';
    }

    @api loginUrl = '/login';

    handleLoginClick(event) {
        if (event) event.preventDefault();
        // Keep the back-compat event for any parent listeners, then actually navigate.
        // In Experience Builder this LWC is standalone (no parent), so the event alone
        // was a dead click — drive the real navigation to the Login page.
        this.dispatchEvent(new CustomEvent('logininstead'));
        const target = basePath + (this.loginUrl && this.loginUrl.charAt(0) === '/' ? this.loginUrl : '/' + (this.loginUrl || 'login'));
        try { window.location.assign(target); } catch (e) { window.location.href = target; }
    }

    validateAll() {
        const e = {};
        const f = this.form;
        if (!f.firstName.trim()) e.firstName = 'First name is required.';
        else if (!NAME_RE.test(f.firstName.trim())) e.firstName = 'Name cannot contain numbers.';
        if (!f.lastName.trim()) e.lastName = 'Last name is required.';
        else if (!NAME_RE.test(f.lastName.trim())) e.lastName = 'Name cannot contain numbers.';
        if (!f.email.trim()) e.email = 'Email is required.';
        else if (!EMAIL_RE.test(f.email.trim())) e.email = 'Enter a valid email address.';
        if (!f.phone.trim()) e.phone = 'Phone number is required.';
        else if (!PHONE_RE.test(f.phone.trim())) e.phone = 'Enter digits only (6–15).';
        if (!f.universityRegNumber.trim()) e.universityRegNumber = 'Registration number is required.';
        if (!f.graduationYear) e.graduationYear = 'Select your year of graduation.';
        if (f.linkedinUrl && f.linkedinUrl.trim() && !LINKEDIN_RE.test(f.linkedinUrl.trim())) {
            e.linkedinUrl = 'Enter a valid LinkedIn profile URL.';
        }
        this.errors = e;
        return Object.keys(e).length === 0;
    }

    /**
     * Stage 1 → Stage 2 transition. registerAlumni issues an OTP email; we flip
     * to the OTP entry screen and start the resend cooldown.
     */
    handleSubmit(event) {
        if (event) event.preventDefault();
        this.serverError = '';
        if (!this.validateAll()) return;
        this.isSubmitting = true;
        registerAlumni({ input: { ...this.form } })
            .then(() => {
                this.stage = 'otp';
                this.otpDigits = ['', '', '', '', '', ''];
                this.otpError = '';
                this._startResendCooldown();
                this.dispatchEvent(new CustomEvent('register', { detail: { ...this.form } }));
                // Defer focus to next tick so the new template has mounted.
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => this._focusOtp(0), 0);
            })
            .catch((err) => {
                this.serverError = (err && err.body && err.body.message)
                    || 'Registration could not be completed. Please try again.';
            })
            .finally(() => { this.isSubmitting = false; });
    }

    // ---- OTP handlers ----
    handleOtpInput(event) {
        const idx = parseInt(event.target.dataset.idx, 10);
        if (isNaN(idx)) return;
        let v = event.target.value || '';
        v = v.replace(/[^0-9]/g, '');
        if (v.length > 1) v = v.substring(v.length - 1); // last digit wins on paste of multi-char into 1 box
        const next = this.otpDigits.slice();
        next[idx] = v;
        this.otpDigits = next;
        if (this.otpError) this.otpError = '';
        // Auto-advance focus.
        if (v && idx < this.otpDigits.length - 1) {
            this._focusOtp(idx + 1);
        }
    }
    handleOtpKeyDown(event) {
        const idx = parseInt(event.target.dataset.idx, 10);
        if (isNaN(idx)) return;
        if (event.key === 'Backspace' && !this.otpDigits[idx] && idx > 0) {
            this._focusOtp(idx - 1);
        } else if (event.key === 'ArrowLeft' && idx > 0) {
            event.preventDefault();
            this._focusOtp(idx - 1);
        } else if (event.key === 'ArrowRight' && idx < this.otpDigits.length - 1) {
            event.preventDefault();
            this._focusOtp(idx + 1);
        } else if (event.key === 'Enter' && this.otpIsComplete) {
            event.preventDefault();
            this.handleOtpSubmit();
        }
    }
    handleOtpPaste(event) {
        const text = (event.clipboardData && event.clipboardData.getData('text')) || '';
        const digits = text.replace(/[^0-9]/g, '').substring(0, this.otpDigits.length);
        if (!digits) return;
        event.preventDefault();
        const next = ['', '', '', '', '', ''];
        for (let i = 0; i < digits.length; i++) next[i] = digits[i];
        this.otpDigits = next;
        this._focusOtp(Math.min(digits.length, this.otpDigits.length - 1));
    }
    _focusOtp(idx) {
        const el = this.template.querySelector(`input[data-idx="${idx}"]`);
        if (el && el.focus) el.focus();
    }

    handleOtpSubmit(event) {
        if (event) event.preventDefault();
        this.otpError = '';
        if (!this.otpIsComplete) {
            this.otpError = 'Please enter the 6-digit code.';
            return;
        }
        this.otpVerifying = true;
        const otp = this.otpDigits.join('');
        verifyRegistrationOtp({ email: this.form.email, otp })
            .then(() => {
                this._clearResendTimer();
                this.stage = 'submitted';
                this.dispatchEvent(new CustomEvent('otpverified', { detail: { email: this.form.email } }));
            })
            .catch((err) => {
                this.otpError = (err && err.body && err.body.message) || 'Verification failed. Please try again.';
            })
            .finally(() => { this.otpVerifying = false; });
    }

    handleResendOtp(event) {
        if (event) event.preventDefault();
        if (this.resendDisabled) return;
        this.resending = true;
        this.otpError = '';
        resendRegistrationOtp({ email: this.form.email })
            .then(() => {
                this.otpDigits = ['', '', '', '', '', ''];
                this._startResendCooldown();
                this._focusOtp(0);
            })
            .catch((err) => {
                this.otpError = (err && err.body && err.body.message) || 'Could not resend the code. Please try again.';
            })
            .finally(() => { this.resending = false; });
    }

    handleEditEmail(event) {
        // Go back to the form so the user can correct a typo in email (or any field).
        if (event) event.preventDefault();
        this._clearResendTimer();
        this.otpError = '';
        this.stage = 'form';
    }

    _startResendCooldown() {
        this._clearResendTimer();
        this.resendCooldown = RESEND_COOLDOWN_SECS;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._resendTimer = setInterval(() => {
            this.resendCooldown -= 1;
            if (this.resendCooldown <= 0) this._clearResendTimer();
        }, 1000);
    }
    _clearResendTimer() {
        if (this._resendTimer) {
            clearInterval(this._resendTimer);
            this._resendTimer = null;
        }
        this.resendCooldown = 0;
    }
    disconnectedCallback() { this._clearResendTimer(); }
}