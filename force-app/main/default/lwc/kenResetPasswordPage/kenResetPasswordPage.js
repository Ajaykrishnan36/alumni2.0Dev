import { api, LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import sendResetOtp from '@salesforce/apex/KenCommunityLoginController.sendResetOtp';
import verifyResetOtp from '@salesforce/apex/KenCommunityLoginController.verifyResetOtp';
import resetPassword from '@salesforce/apex/KenCommunityLoginController.resetPassword';
import basePath from '@salesforce/community/basePath';
import KenPoweredbyLogo from '@salesforce/resourceUrl/kenPoweredbyLogo';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenResetPasswordPage extends NavigationMixin(LightningElement) {
    @api startUrl = '';
    email = '';
    newPassword = '';
    confirmPassword = '';
    errorMessage = '';
    isLoading = false;
    @track isSuccessToastVisible = false;
    @track isErrorToastVisible = false;
    @track errorTitle = '';
    @track errorDescription = '';
    @track successTitle = '';
    @track successDescription = '';
    successTimeout;
    errorTimeout;
    
    @track showEmailStep = true;
    @track showOTPStep = false;
    @track showPasswordStep = false;
    
    @track otpInputs = [
        { id: '0', value: '' },
        { id: '1', value: '' },
        { id: '2', value: '' },
        { id: '3', value: '' }
    ];
    @track timerSeconds = 120; // 2 minutes
    @track canResend = false;
    timerInterval;
    
    @track hasNewPasswordError = false;
    @track hasConfirmPasswordError = false;
    connectedCallback() {
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
        this.applyDirectNewPasswordFromUrl();
    }

    applyDirectNewPasswordFromUrl() {
        try {
            const params = new URLSearchParams(window.location.search || '');
            const step = params.get('step');
            const emailParam = params.get('email');
            if (step === 'newpassword' && emailParam && emailParam.trim()) {
                this.email = emailParam.trim();
                this.showEmailStep = false;
                this.showOTPStep = false;
                this.showPasswordStep = true;
            }
        } catch (e) {
            // ignore URL parse errors
        }
    }
    newPasswordFieldType = 'password';
    confirmPasswordFieldType = 'password';
    newPasswordIconName = 'utility:hide';
    confirmPasswordIconName = 'utility:hide';
    kenPoweredbyLogo = KenPoweredbyLogo;

    get timerDisplay() {
        const minutes = Math.floor(this.timerSeconds / 60);
        const seconds = this.timerSeconds % 60;
        return `${minutes}:${seconds.toString().padStart(2, '0')}`;
    }

    get isNewPasswordVisible() {
        return this.newPasswordFieldType === 'text';
    }

    get isConfirmPasswordVisible() {
        return this.confirmPasswordFieldType === 'text';
    }

    get newPasswordToggleLabel() {
        return this.isNewPasswordVisible ? 'Hide password' : 'Show password';
    }

    get confirmPasswordToggleLabel() {
        return this.isConfirmPasswordVisible ? 'Hide password' : 'Show password';
    }

    get showNewPasswordToggle() {
        return (this.newPassword || '').length > 0;
    }

    get showConfirmPasswordToggle() {
        return (this.confirmPassword || '').length > 0;
    }

    get newPasswordToggleButtonClass() {
        return this.hasNewPasswordError 
            ? 'password-toggle-button password-toggle-button-error' 
            : 'password-toggle-button';
    }

    get confirmPasswordToggleButtonClass() {
        return this.hasConfirmPasswordError 
            ? 'password-toggle-button password-toggle-button-error' 
            : 'password-toggle-button';
    }

    renderedCallback() {
        // Force button background color to override SLDS inline styles
        const buttons = this.template.querySelectorAll('.studentportal-BlueButtonLogin button, .studentportal-BlueButtonLogin .slds-button');
        buttons.forEach(button => {
            if (button) {
                button.style.setProperty('background', '#3061FF', 'important');
                button.style.setProperty('background-color', '#3061FF', 'important');
                button.style.setProperty('color', 'white', 'important');
                button.style.setProperty('font-size', '0.875rem', 'important');
                button.style.setProperty('font-weight', '550', 'important');
                button.style.setProperty('border', 'none', 'important');
                button.style.setProperty('border-radius', '8px', 'important');
                
                // Add hover event listener
                button.addEventListener('mouseenter', () => {
                    button.style.setProperty('background', '#2551d9', 'important');
                    button.style.setProperty('background-color', '#2551d9', 'important');
                });
                button.addEventListener('mouseleave', () => {
                    button.style.setProperty('background', '#3061FF', 'important');
                    button.style.setProperty('background-color', '#3061FF', 'important');
                });
            }
        });
    }

    handleInputChange({ target }) {
        const { id } = target.dataset;
        const { value } = target;
        this[id] = value;
        
        // Validate password fields on change
        if (id === 'newPassword' || id === 'confirmPassword') {
            this.validateField(id, value);
            
            // If newPassword changes, also re-validate confirmPassword
            if (id === 'newPassword' && this.confirmPassword) {
                this.validateField('confirmPassword', this.confirmPassword);
            }
            
            // If confirmPassword changes, ensure it's validated against current newPassword
            if (id === 'confirmPassword') {
                this.validateField('confirmPassword', value);
            }
        }
    }

    handleOnBlur({ target }) {
        const { id } = target.dataset;
        const { value } = target;
        this.validateField(id, value);
    }

    handleEnterKey(event) {
        if (event.keyCode == 13) {
            event.preventDefault();
            if (this.showEmailStep) {
                this.handleSendResetEmail();
            } else if (this.showOTPStep) {
                this.handleVerifyOTP();
            } else if (this.showPasswordStep) {
                this.handleSubmitNewPassword();
            }
        }
    }

    validateField(field, value) {
        let isValid = true;
        let message = '';
    
        if (!value || !value.trim()) {
            isValid = false;
            message = 'This field cannot be empty.';
        } else if (field === 'email' && !this.isValidEmail(value)) {
            isValid = false;
            message = 'Please enter a valid email address.';
        } else if (field === 'newPassword' && value.trim().length < 8) {
            isValid = false;
            message = 'Password must be at least 8 characters long.';
        } else if (field === 'confirmPassword' && value !== this.newPassword) {
            isValid = false;
            message = 'Passwords do not match.';
        }
    
        // Track error state for password fields
        if (field === 'newPassword') {
            this.hasNewPasswordError = !isValid;
        } else if (field === 'confirmPassword') {
            this.hasConfirmPasswordError = !isValid;
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

    async handleSendResetEmail() {
        const isEmailValid = this.validateField('email', this.email);
        
        if (!isEmailValid) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        try {
            await sendResetOtp({ email: this.email });
            
            this.showEmailStep = false;
            this.showOTPStep = true;
            this.startTimer();
            this.showSuccessToast('OTP sent', 'Check your email for the verification code.');
        } catch (error) {
            const errMsg = error.body?.message || 'An error occurred. Please try again.';
            this.errorMessage = errMsg;
            this.showErrorToast('Send OTP failed', errMsg);
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
        
        const lastIndex = Math.min(pastedData.length - 1, 3);
        const lastInput = this.template.querySelector(`[data-index="${lastIndex}"]`);
        if (lastInput) {
            lastInput.focus();
        }
    }

    handleEditEmail() {
        this.showOTPStep = false;
        this.showEmailStep = true;
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
        }
    }

    async handleResendOTP() {
        if (!this.canResend) {
            return;
        }

        this.isLoading = true;
        try {
            await sendResetOtp({ email: this.email });
            
            this.otpInputs = this.otpInputs.map(input => ({ ...input, value: '' }));
            this.startTimer();
            this.showSuccessToast('OTP resent', 'We have sent a new verification code to your email.');
        } catch (error) {
            const errMsg = error.body?.message || 'Failed to resend OTP. Please try again.';
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

        this.isLoading = true;
        this.errorMessage = '';

        try {
            await verifyResetOtp({ email: this.email, otpEntered: otpCode });
            
            this.showOTPStep = false;
            this.showPasswordStep = true;
            if (this.timerInterval) {
                clearInterval(this.timerInterval);
            }
            this.showSuccessToast('OTP verified', 'Enter your new password to continue.');
        } catch (error) {
            const errMsg = error.body?.message || 'Invalid OTP. Please try again.';
            this.errorMessage = errMsg;
            this.showErrorToast('OTP verification failed', errMsg);
            this.otpInputs = this.otpInputs.map(input => ({ ...input, value: '' }));
        } finally {
            this.isLoading = false;
        }
    }

    toggleNewPasswordVisibility(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }

        if (this.newPasswordFieldType === 'password') {
            this.newPasswordFieldType = 'text';
            this.newPasswordIconName = 'utility:preview';
        } else {
            this.newPasswordFieldType = 'password';
            this.newPasswordIconName = 'utility:hide';
        }
    }

    toggleConfirmPasswordVisibility(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }

        if (this.confirmPasswordFieldType === 'password') {
            this.confirmPasswordFieldType = 'text';
            this.confirmPasswordIconName = 'utility:preview';
        } else {
            this.confirmPasswordFieldType = 'password';
            this.confirmPasswordIconName = 'utility:hide';
        }
    }

    async handleSubmitNewPassword() {
        const isNewPasswordValid = this.validateField('newPassword', this.newPassword);
        const isConfirmPasswordValid = this.validateField('confirmPassword', this.confirmPassword);
        
        if (!isNewPasswordValid || !isConfirmPasswordValid) {
            return;
        }

        if (this.newPassword !== this.confirmPassword) {
            this.errorMessage = 'Passwords do not match.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        try {
            await resetPassword({ email: this.email, newPassword: this.newPassword });
            
            this.dispatchEvent(new CustomEvent('passwordresetcomplete', {
                detail: { email: this.email },
                bubbles: true,
                composed: true
            }));
            this.showSuccessToast('Password reset', 'Your password has been updated. Signing you out...');
            window.setTimeout(() => {
                this.handleBackToLogin();
            }, 1500);
        } catch (error) {
            const errMsg = error.body?.message || 'Failed to reset password. Please try again.';
            this.errorMessage = errMsg;
            this.showErrorToast('Reset failed', errMsg);
        } finally {
            this.isLoading = false;
        }
    }

    handleBackToLogin() {
        window.location.href = `${basePath}/secur/logout.jsp`;
    }

    handleRegister() {
        window.location.href = `${basePath}/SelfRegister`;
    }

        renderedCallback() {
        // Force apply button styles directly to ensure background color is visible
        // Handle Lightning button shadow DOM with retry mechanism
        const applyButtonStyles = () => {
            const lightningButtons = this.template.querySelectorAll('lightning-button.studentportal-BlueButtonLogin');
            lightningButtons.forEach(lb => {
                if (lb) {
                    // Try to access shadow root
                    let shadowRoot = lb.shadowRoot;
                    if (!shadowRoot && lb.template) {
                        shadowRoot = lb.template.querySelector ? null : lb.shadowRoot;
                    }
                    
                    if (shadowRoot) {
                        const button = shadowRoot.querySelector('button.slds-button, button');
                        if (button) {
                            button.style.setProperty('background-color', '#3061FF', 'important');
                            button.style.setProperty('background', '#3061FF', 'important');
                            button.style.setProperty('color', 'white', 'important');
                            button.style.setProperty('font-size', '0.875rem', 'important');
                            button.style.setProperty('font-weight', '550', 'important');
                            button.style.setProperty('font-family', "'General Sans', sans-serif", 'important');
                            button.style.setProperty('border', 'none', 'important');
                            button.style.setProperty('border-radius', '8px', 'important');
                            
                            // Also set CSS custom properties
                            button.style.setProperty('--sds-c-button-brand-color-background', '#3061FF', 'important');
                        }
                    } else {
                        // If shadow root not available, try again after a short delay
                        setTimeout(() => {
                            if (lb.shadowRoot) {
                                const button = lb.shadowRoot.querySelector('button.slds-button, button');
                                if (button) {
                                    button.style.setProperty('background-color', '#3061FF', 'important');
                                    button.style.setProperty('background', '#3061FF', 'important');
                                    button.style.setProperty('color', 'white', 'important');
                                    button.style.setProperty('font-size', '0.875rem', 'important');
                                    button.style.setProperty('font-weight', '550', 'important');
                                    button.style.setProperty('font-family', "'General Sans', sans-serif", 'important');
                                    button.style.setProperty('border', 'none', 'important');
                                    button.style.setProperty('border-radius', '8px', 'important');
                                }
                            }
                        }, 100);
                    }
                }
            });
        };
        
        // Apply styles immediately and after a short delay to catch async rendering
        applyButtonStyles();
        setTimeout(applyButtonStyles, 50);
        setTimeout(applyButtonStyles, 200);
    }

    disconnectedCallback() {
        if (this.timerInterval) {
            clearInterval(this.timerInterval);
        }
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
}