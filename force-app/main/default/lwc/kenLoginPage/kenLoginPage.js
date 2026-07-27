import { api, LightningElement, track, wire } from 'lwc';
import login from '@salesforce/apex/KenCommunityLoginController.login';
import linkedinLogoUrl from '@salesforce/resourceUrl/LoginLinkedinIcon';
import KenLogo from '@salesforce/resourceUrl/LoginKen';
import KenPoweredbyLogo from '@salesforce/resourceUrl/kenPoweredbyLogo';
import { CurrentPageReference } from 'lightning/navigation';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class LoginPage extends NavigationMixin(LightningElement) {
    email = '';
    password = '';
    startUrl = '';
    errorMessage = '';
    isLoading = false;
    passwordFieldType = 'password';
    iconName = 'utility:hide';
    linkedInProvider = 'LinkedIn';
    googleProvider = '';
    linkedinLogo = linkedinLogoUrl;
    kenLogo = KenLogo;
    kenPoweredbyLogo = KenPoweredbyLogo;
    @track showToast = false;
    @track toastTitle = '';
    @track toastMessage = '';
    @track toastVariant = 'success'; // success, error, warning, info
    @track isRedirectingToReset = false;

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
        }).catch(() => {

        });
        this.detectSsoError();
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
            const noUser = code === 'REGISTRATION_HANDLER_ERROR'
                || description.toLowerCase().indexOf('no active user') > -1
                || description.toLowerCase().indexOf('register first') > -1;
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

}