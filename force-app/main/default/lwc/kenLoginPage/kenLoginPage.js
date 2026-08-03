import { api, LightningElement, track, wire } from 'lwc';
import login from '@salesforce/apex/KenCommunityLoginController.login';
import resolveOtpLoginContext from '@salesforce/apex/KenCommunityOtpLoginController.resolveOtpLoginContext';
import sendLoginOtp from '@salesforce/apex/KenCommunityOtpLoginController.sendLoginOtp';
import verifyLoginOtp from '@salesforce/apex/KenCommunityOtpLoginController.verifyLoginOtp';
import linkedinLogoUrl from '@salesforce/resourceUrl/LoginLinkedinIcon';
import KenLogo from '@salesforce/resourceUrl/LoginKen';
import KenPoweredbyLogo from '@salesforce/resourceUrl/kenPoweredbyLogo';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const OTP_LENGTH = 6;
const RESEND_SECONDS = 120;

export default class LoginPage extends NavigationMixin(LightningElement) {
    email = '';
    password = '';
    startUrl = '';
    errorMessage = '';
    isLoading = false;
    passwordFieldType = 'password';
    iconName = 'utility:hide';
    linkedInProvider = '';
    googleProvider = '';
    linkedinLogo = linkedinLogoUrl;
    kenLogo = KenLogo;
    kenPoweredbyLogo = KenPoweredbyLogo;
    @track showToast = false;
    @track toastTitle = '';
    @track toastMessage = '';
    @track toastVariant = 'success'; // success, error, warning, info
    @track isRedirectingToReset = false;

    loginMethod = 'Password';
    otpDeliveryChannel = 'Email';
    @track otpMode = false;
    @track otpStep = 'identify';
    @track otpChannels = [];
    @track selectedChannel = '';
    @track otpAccountId = '';
    @track otpIdentifier = '';
    @track otpMaskedTarget = '';
    @track otpMaskedEmail = '';
    @track otpMaskedPhone = '';
    @track otpCode = ['', '', '', '', '', ''];
    @track resendSeconds = 0;
    @track mobile = '';
    @track defaultDialCountry = 'in';
    resendTimerId;

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        this.startUrl = currentPageReference.state.startURL;
    }

    handleInputChange({ target }) {
        const { id } = target.dataset;
        const { value } = target;
        this[id] = value;
        
        // Validate password field on change
        if (id === 'password') {
            this.validateField(id, value);
        }
    }

    handleOnBlur({ target }) {
        const { id } = target.dataset;
        const { value } = target;
        this.validateField(id, value);
    }

    handleForgotPassword() {
        this.dispatchEvent(new CustomEvent('forgotpassword', { detail: { email: this.email } }));
    }

    handleSignup() {
        this.dispatchEvent(new CustomEvent('signup'));
    }

    handleEnterKey(event) {
        if (event.keyCode == 13) {
            event.preventDefault();
            this.handleLogin();
        }
    }
    
    connectedCallback() {
        document.documentElement.style.setProperty('--primary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--secondary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--tertiary-color', '#FFFFFF');
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
            if (color?.linkedInSsoProvider) {
                this.linkedInProvider = color.linkedInSsoProvider;
            }
            if (color?.googleSsoProvider) {
                this.googleProvider = color.googleSsoProvider;
            }
            this.loginMethod = color?.loginMethod || 'Password';
            this.otpDeliveryChannel = color?.otpDeliveryChannel || 'Email';
            if (color?.defaultDialCountry) {
                this.defaultDialCountry = color.defaultDialCountry;
            }
            this.selectedChannel = this.orgChannels[0];
            if (this.loginMethod === 'OTP') {
                this.otpMode = true;
            }
        }).catch(() => {

        });
        this.detectSsoError();
    }

    disconnectedCallback() {
        this.stopResendTimer();
    }

    /**
     * When social sign-in (LinkedIn/Google) fails — most commonly because the
     * person has no registered account — the Auth Provider's Error URL routes
     * back here with ErrorCode/ErrorDescription. Show a friendly message instead
     * of leaving the user on Salesforce's generic "Problem Logging In" page.
     */
    detectSsoError() {
        try {
            const params = new URLSearchParams(window.location.search || '');
            const code = params.get('ErrorCode') || '';
            const description = params.get('ErrorDescription') || '';
            if (!code && !description) {
                return;
            }
            const lower = description.toLowerCase();

            // The provider authenticated the person but shared no email, so we
            // can't match them to an account. Sending them to registration would
            // be wrong — an existing alumnus just needs the password route.
            if (lower.indexOf('no_sso_email') > -1 || lower.indexOf('did not share an email') > -1) {
                this.toastTitle = 'Email not shared';
                this.toastMessage = 'That provider didn’t share your email address. Please sign in with your email and password.';
                this.toastVariant = 'error';
                this.showToast = true;
                return;
            }

            const noUser = lower.indexOf('no active user') > -1
                || lower.indexOf('register first') > -1
                || code === 'REGISTRATION_HANDLER_ERROR';
            if (noUser) {
                this.toastTitle = 'Account not found';
                this.toastMessage = 'No account is linked to that profile. Redirecting you to registration…';
                this.toastVariant = 'info';
                this.showToast = true;
                setTimeout(() => {
                    this.dispatchEvent(new CustomEvent('signup'));
                }, 2500);
                return;
            }

            // Known non-registration failures worth naming rather than echoing
            // Salesforce's raw text.
            if (code === 'OAUTH_ACCESS_DENIED' || lower.indexOf('access_denied') > -1 || lower.indexOf('cancel') > -1) {
                this.toastTitle = 'Sign-in cancelled';
                this.toastMessage = 'You cancelled the sign-in. Try again or use your email and password.';
                this.toastVariant = 'error';
                this.showToast = true;
                return;
            }
            if (lower.indexOf('inactive') > -1 || lower.indexOf('frozen') > -1) {
                this.toastTitle = 'Account inactive';
                this.toastMessage = 'Your account is not active. Please contact your alumni office.';
                this.toastVariant = 'error';
                this.showToast = true;
                return;
            }

            this.toastTitle = 'Sign-in failed';
            this.toastMessage = description || 'We couldn’t sign you in. Please try again or use your email and password.';
            this.toastVariant = 'error';
            this.showToast = true;
        } catch (e) {
            // ignore — never block the login screen on a parse error
        }
    }

    togglePasswordVisibility(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }

        if (this.passwordFieldType === 'password') {
            this.passwordFieldType = 'text';
            this.iconName = 'utility:preview';
        } else {
            this.passwordFieldType = 'password';
            this.iconName = 'utility:hide';
        }
    }

    get isPasswordVisible() {
        return this.passwordFieldType === 'text';
    }

    get passwordToggleLabel() {
        return this.isPasswordVisible ? 'Hide password' : 'Show password';
    }

    get showPasswordToggle() {
        return (this.password || '').length > 0;
    }

    handleLinkedInLogin() {
        const provider = this.linkedInProvider;
        const siteOrigin = window.location.origin;
        const path = window.location.pathname || '';
        const match = path.match(/^(.+?)\/s(\/|$)/);
        const siteBasePath = match ? match[1] : basePath.replace(/\/(s|login)(\/|$)/, '');
        const startUrl = encodeURIComponent(`${siteBasePath}/select-role`);
        const ssoUrl = `${siteOrigin}${siteBasePath}/services/auth/sso/${provider}?startURL=${startUrl}`;
        window.location.assign(ssoUrl);
    }

    // Only offer LinkedIn when an Auth Provider is actually configured. The bare
    // 'LinkedIn' provider has no Error URL, so a failed sign-in never returns here
    // with ErrorCode and detectSsoError can't show the "register first" redirect.
    get showLinkedInLogin() {
        return !!this.linkedInProvider;
    }

    get showGoogleLogin() {
        return !!this.googleProvider;
    }

    handleGoogleLogin() {
        const provider = this.googleProvider;
        const siteOrigin = window.location.origin;
        const path = window.location.pathname || '';
        const match = path.match(/^(.+?)\/s(\/|$)/);
        const siteBasePath = match ? match[1] : basePath.replace(/\/(s|login)(\/|$)/, '');
        const startUrl = encodeURIComponent(`${siteBasePath}/select-role`);
        const ssoUrl = `${siteOrigin}${siteBasePath}/services/auth/sso/${provider}?startURL=${startUrl}`;
        window.location.assign(ssoUrl);
    }

    async handleResendVerificationLink() {
        this.dispatchEvent(new CustomEvent('resendverifyemail', { detail: { email: this.email } }));
    }

    async handleLogin() {
        const isEmailValid = this.validateField('email', this.email);
        const isPasswordValid = this.validateField('password', this.password);
        
        if ((!this.email || !this.email.trim()) && (!this.password || !this.password.trim())) {
            this.showToast = true;
            this.toastTitle = 'Incomplete details';
            this.toastMessage = 'Please fill in all required fields before proceeding.';
            this.toastVariant = 'error';
            setTimeout(() => {
                this.showToast = false;
            }, 1500);
            return;
        }
    
        if (!isEmailValid || !isPasswordValid) {
            return;
        }
    
        this.isLoading = true;
        this.startUrl = '/alumni/';
    
        try {
            const result = await login({
                email: this.email,
                password: this.password,
                communityStartUrl: this.startUrl,
            });

            this.errorMessage = '';
            const requirePasswordReset = result && result.requirePasswordReset && result.pendingResetEmail;
            if (requirePasswordReset) {
                this.isRedirectingToReset = true;
                this.isLoading = true;
            } else {
                this.showToast = true;
                this.toastTitle = 'Login Successful!';
                this.toastMessage = 'Your login was successful. We\'re redirecting you to your dashboard.';
                this.toastVariant = 'success';
                this.isLoading = true;
            }

            setTimeout(() => {
                if (requirePasswordReset) {
                    try {
                        sessionStorage.setItem('AlumniPendingPasswordReset', JSON.stringify({ email: result.pendingResetEmail }));
                    } catch (e) {
                        // ignore
                    }
                } else if (result && result.accountId) {
                    try {
                        window.localStorage.setItem('UserAccountId', result.accountId);
                    } catch (e) {
                        // ignore storage errors
                    }
                }
                window.location.href = result?.url || '/';
            }, requirePasswordReset ? 100 : 1500);

        } catch (error) {
            const errMsg = error.body?.message;
            console.log(errMsg,'errormsgss');
            this.isLoading = false; // Hide loader on error
            this.showToast = true;
            this.toastVariant = 'error';
    
            if (errMsg.includes('could not connect')) {
                this.toastTitle = `Couldn't connect to your account`;
                this.toastMessage = 'We had trouble connecting to your account. Please check your details and try again.';
            } else if (errMsg.includes('User credentials not found')) {
                this.toastTitle = 'Account not found';
                this.toastMessage = 'We couldn’t find an account with those details. Please verify and try again.';
            } else if (errMsg.includes('Wrong studentId or Password')) {
                this.toastTitle = 'Incorrect password';
                this.toastMessage = 'Please try again.';
            } else if (errMsg.includes('Wrong Email or Password')) {
                this.toastTitle = 'Incorrect email or password';
                this.toastMessage = 'The email or password you entered is incorrect. Please try again, or use “Forgot password” to reset it.';
            } else {
                this.toastTitle = 'Unexpected Error';
                this.toastMessage = 'An unexpected error occurred. Please try again.' + errMsg;
            }
            
            setTimeout(() => {
                this.showToast = false;
            }, 5000);
        }
    }
    
    handleKeyUp(event) {
        if (event.keyCode === 13) {
            this.handleLogin();
        }
    }

    validateField(field, value) {
        let isValid = true;
        let message = '';
    
        if (!value || !value.trim()) {
            isValid = false;
            message = 'This field can’t be empty.';
        } else if (field === 'email' && !this.isValidEmail(value)) {
            isValid = false;
            message = 'Please enter a valid email address.';
        } else if (field === 'password' && value.trim().length === 0) {
            isValid = false;
            message = 'Please enter a valid password';
        }
    
        this.setCustomValidity(field, isValid, message);
        return isValid;
    }

    setCustomValidity(field, isValid, message) {
        const inputField = this.template.querySelector(`[data-id="${field}"]`);
        if (inputField) {
            inputField.setCustomValidity(isValid ? '' : message);
            inputField.reportValidity();
        }
    }
    
    isValidEmail(email) {
        const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
        return emailRegex.test(email);
    }

    setCustomValidity(field, isValid, message) {
        const inputField = this.template.querySelector(`[data-id=${field}]`);
        if (inputField) {
            inputField.setCustomValidity(isValid ? '' : message);
            inputField.reportValidity();
        }
    }

    navigateToDashboardPage() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Home',
            },
        });
    }

    get showPasswordLogin() {
        return this.loginMethod !== 'OTP' && !this.otpMode;
    }

    get showOtpLogin() {
        return this.loginMethod === 'OTP' || this.otpMode;
    }

    get showOtpSwitchLink() {
        return this.loginMethod === 'Both' && !this.otpMode;
    }

    get showPasswordSwitchLink() {
        return this.loginMethod === 'Both' && this.otpMode;
    }

    get isOtpIdentifyStep() {
        return this.otpStep === 'identify';
    }

    get isOtpCodeStep() {
        return this.otpStep === 'code';
    }

    get channelOptions() {
        return this.orgChannels.map((channel) => ({
            value: channel,
            label: channel === 'SMS' ? 'Mobile' : 'Email',
            checked: channel === this.selectedChannel,
            tabClass: channel === this.selectedChannel ? 'otp-segment-tab is-active' : 'otp-segment-tab',
        }));
    }

    /**
     * Channels the org offers, from OTP_Delivery_Channel__c. Drives the tabs
     * before any lookup has happened; whether this alumnus can actually use the
     * chosen one is decided server-side on send.
     */
    get orgChannels() {
        if (this.otpDeliveryChannel === 'Both') {
            return ['Email', 'SMS'];
        }
        return [this.otpDeliveryChannel === 'SMS' ? 'SMS' : 'Email'];
    }

    get showChannelTabs() {
        return this.orgChannels.length > 1;
    }

    get isSmsChannel() {
        return this.selectedChannel === 'SMS';
    }

    get identifierLabel() {
        return this.isSmsChannel ? 'Mobile number' : 'Email';
    }

    get otpIntroText() {
        return 'We\'ll send a 6-digit code to confirm it\'s you';
    }

    handleChannelSelect(event) {
        this.selectedChannel = event.currentTarget.dataset.channel;
    }

    /**
     * The shared phone input emits both formats; keep the E.164 value so the
     * server sees a country code, and fall back to the national digits.
     */
    handlePhoneChange(event) {
        const { e164, national } = event.detail || {};
        this.mobile = e164 || national || '';
    }

    async handleSendCode() {
        const channel = this.selectedChannel || this.orgChannels[0];
        const identifier = channel === 'SMS' ? this.mobile : this.email;

        if (channel === 'Email' && !this.validateField('email', this.email)) {
            return;
        }
        if (channel === 'SMS' && (this.mobile || '').length < 10) {
            this.showError('Check your mobile number', 'Please enter your 10-digit mobile number.');
            return;
        }

        this.isLoading = true;
        try {
            const context = await resolveOtpLoginContext({ identifier, channel });
            if (!context || !context.success) {
                this.showError('Can’t send a code', context?.message || 'Please try again.');
                return;
            }
            this.otpAccountId = context.accountId;
            this.otpChannels = context.availableChannels || [];
            this.otpMaskedEmail = context.maskedEmail;
            this.otpMaskedPhone = context.maskedPhone;

            if (!this.otpChannels.includes(channel)) {
                this.showError('Can’t use that method', context.message || 'Please choose another option.');
                return;
            }
            await this.requestOtp();
        } catch (error) {
            this.showError('Something went wrong', error?.body?.message || 'Please try again.');
        } finally {
            this.isLoading = false;
        }
    }

    get otpBoxes() {
        return this.otpCode.map((digit, index) => ({ key: `otp-${index}`, index, value: digit }));
    }

    get isOtpComplete() {
        return this.otpCode.every((digit) => digit !== '');
    }

    get isVerifyDisabled() {
        return !this.isOtpComplete || this.isLoading;
    }

    get canResendOtp() {
        return this.resendSeconds <= 0;
    }

    get isResendDisabled() {
        return !this.canResendOtp || this.isLoading;
    }

    get resendLabel() {
        return this.canResendOtp ? 'Resend code' : `Resend in ${this.resendSeconds}s`;
    }

    get otpSentMessage() {
        return this.otpMaskedTarget ? `We sent a 6-digit code to ${this.otpMaskedTarget}` : 'We sent you a 6-digit code';
    }

    switchToOtpLogin() {
        this.otpMode = true;
        this.resetOtpState();
    }

    switchToPasswordLogin() {
        this.otpMode = false;
        this.stopResendTimer();
        this.resetOtpState();
    }

    resetOtpState() {
        this.otpStep = 'identify';
        this.otpChannels = [];
        // Always land on a selected tab. Clearing this left both tabs looking
        // inactive while the email field was already showing.
        this.selectedChannel = this.orgChannels[0];
        this.otpAccountId = '';
        this.otpIdentifier = '';
        this.otpMaskedTarget = '';
        this.otpMaskedEmail = '';
        this.otpMaskedPhone = '';
        this.otpCode = ['', '', '', '', '', ''];
        this.resendSeconds = 0;
    }

    showError(title, message) {
        this.toastTitle = title;
        this.toastMessage = message;
        this.toastVariant = 'error';
        this.showToast = true;
        setTimeout(() => {
            this.showToast = false;
        }, 5000);
    }

    async requestOtp() {
        const result = await sendLoginOtp({
            accountId: this.otpAccountId,
            channel: this.selectedChannel,
        });
        if (!result || !result.success) {
            this.showError('Couldn’t send the code', result?.message || 'Please try again.');
            return;
        }
        this.otpIdentifier = result.identifier;
        this.otpMaskedTarget = result.maskedTarget;
        this.otpCode = ['', '', '', '', '', ''];
        this.otpStep = 'code';
        this.startResendTimer();
        setTimeout(() => this.focusOtpBox(0), 0);
    }

    async handleResendOtp() {
        if (!this.canResendOtp || this.isLoading) {
            return;
        }
        this.isLoading = true;
        try {
            await this.requestOtp();
        } catch (error) {
            this.showError('Couldn’t resend the code', error?.body?.message || 'Please try again.');
        } finally {
            this.isLoading = false;
        }
    }

    startResendTimer() {
        this.stopResendTimer();
        this.resendSeconds = RESEND_SECONDS;
        this.resendTimerId = setInterval(() => {
            this.resendSeconds -= 1;
            if (this.resendSeconds <= 0) {
                this.stopResendTimer();
            }
        }, 1000);
    }

    stopResendTimer() {
        if (this.resendTimerId) {
            clearInterval(this.resendTimerId);
            this.resendTimerId = undefined;
        }
    }

    focusOtpBox(index) {
        const box = this.template.querySelector(`[data-index="${index}"]`);
        if (box) {
            box.focus();
        }
    }

    handleOtpInput(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const digits = (event.target.value || '').replace(/[^0-9]/g, '');
        const next = [...this.otpCode];
        next[index] = digits.slice(-1);
        this.otpCode = next;
        event.target.value = next[index];
        if (next[index] && index < OTP_LENGTH - 1) {
            this.focusOtpBox(index + 1);
        }
    }

    handleOtpKeyDown(event) {
        const index = parseInt(event.target.dataset.index, 10);
        if (event.key === 'Backspace' && !this.otpCode[index] && index > 0) {
            this.focusOtpBox(index - 1);
        }
        if (event.key === 'Enter' && this.isOtpComplete) {
            this.handleVerifyOtp();
        }
    }

    handleOtpPaste(event) {
        const pasted = (event.clipboardData || window.clipboardData)?.getData('text') || '';
        const digits = pasted.replace(/[^0-9]/g, '').slice(0, OTP_LENGTH);
        if (!digits) {
            return;
        }
        event.preventDefault();
        const next = ['', '', '', '', '', ''];
        digits.split('').forEach((digit, i) => {
            next[i] = digit;
        });
        this.otpCode = next;
        this.template.querySelectorAll('[data-index]').forEach((box) => {
            const boxIndex = parseInt(box.dataset.index, 10);
            box.value = next[boxIndex];
        });
        this.focusOtpBox(Math.min(digits.length, OTP_LENGTH - 1));
    }

    async handleVerifyOtp() {
        if (!this.isOtpComplete) {
            return;
        }
        this.isLoading = true;
        try {
            const result = await verifyLoginOtp({
                accountId: this.otpAccountId,
                channel: this.selectedChannel,
                identifier: this.otpIdentifier,
                otpCode: this.otpCode.join(''),
                startUrl: '/alumni/',
            });

            if (!result || !result.success || !result.redirectUrl) {
                this.showError('Verification failed', result?.message || 'Please try again.');
                this.otpCode = ['', '', '', '', '', ''];
                this.template.querySelectorAll('[data-index]').forEach((box) => {
                    box.value = '';
                });
                this.focusOtpBox(0);
                return;
            }

            this.stopResendTimer();
            if (result.accountId) {
                try {
                    window.localStorage.setItem('UserAccountId', result.accountId);
                } catch (e) {
                    // ignore storage errors
                }
            }
            this.toastTitle = 'Login Successful!';
            this.toastMessage = 'Your login was successful. We\'re redirecting you to your dashboard.';
            this.toastVariant = 'success';
            this.showToast = true;
            setTimeout(() => {
                window.location.href = result.redirectUrl;
            }, 1500);
        } catch (error) {
            this.showError('Verification failed', error?.body?.message || 'Please try again.');
        } finally {
            this.isLoading = false;
        }
    }

}