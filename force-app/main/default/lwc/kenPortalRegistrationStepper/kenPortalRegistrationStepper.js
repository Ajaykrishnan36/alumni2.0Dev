import { LightningElement, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import sendOnboardingOtp from '@salesforce/apex/KenPortalOnbordingController.sendOnboardingOtp';
import verifyOnboardingOtp from '@salesforce/apex/KenPortalOnbordingController.verifyOnboardingOtp';
import autoVerifyOnboarding from '@salesforce/apex/KenPortalOnbordingController.autoVerifyOnboarding';
import getOnboardingState from '@salesforce/apex/KenPortalOnbordingController.getOnboardingState';
import CoverImageLeftSide from '@salesforce/resourceUrl/PortalLoginImage';
import KenLogo from '@salesforce/resourceUrl/LoginKen';
import KenPoweredbyLogo from '@salesforce/resourceUrl/kenPoweredbyLogo';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenPortalRegistrationStepper extends LightningElement {
    headerFirstName = '';
    headerLastName = '';
    @track institutionName = '';
    headerProfileImageUrl = '';
    showOtpScreen = true;
    showStepper = false;
    userEmail = '';
    roleId = '';
    onboardToken = '';
    otpInputs = [
        { id: '0', value: '' },
        { id: '1', value: '' },
        { id: '2', value: '' },
        { id: '3', value: '' }
    ];
    isLoading = false;
    otpTimerSeconds = 120;
    canResendOtp = false;
    showOtpInputs = false;
    showToast = false;
    toastTitle = '';
    toastMessage = '';
    toastVariant = 'success';
    toastTimeout;
    otpTimerInterval;
    carouselImage = CoverImageLeftSide;
    KenLogo = KenLogo;
    kenPoweredbyLogo = KenPoweredbyLogo;
    isInitializing = true;
    _isRedirecting = false;

    connectedCallback() {
        document.documentElement.style.setProperty('--primary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--secondary-color', '#FFFFFF');
        document.documentElement.style.setProperty('--tertiary-color', '#FFFFFF');
        getPrimaryColor().then(color => {
            // console.log(color,'color1234567890');
            this.institutionName = color?.institutionName?color.institutionName:'Somaiya Vidyavihar University';
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });

        const fontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Regular.woff2`;

        const style = document.createElement('style');
        style.innerText = `
            @font-face {
                font-family: 'GeneralSansCustom';
                src: url('${fontUrl}') format('woff2');
                font-weight: normal;
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);

        // hide community header while OTP screen active
        document.documentElement.classList.add('hide-community-header');

        this.roleId = this.getRoleIdFromUrl() || window.localStorage.getItem('ConstituentRoleId') || '';
        this.onboardToken = this.getTokenFromUrl() || window.sessionStorage.getItem('onboardToken') || '';
        if (this.roleId) {
            window.localStorage.setItem('ConstituentRoleId', this.roleId);
        }
        if (this.onboardToken) {
            window.sessionStorage.setItem('onboardToken', this.onboardToken);
        }
        this.initializeState();
    }

    disconnectedCallback() {
        document.documentElement.classList.remove('hide-community-header');
        this.clearOtpTimer();
        if (this.toastTimeout) {
            window.clearTimeout(this.toastTimeout);
        }
    }

    handleLogout() {
        this.dispatchEvent(new CustomEvent('logout', { bubbles: true, composed: true }));
    }

    handleComplete() {
        this.dispatchEvent(new CustomEvent('registrationcomplete', { bubbles: true, composed: true }));
    }

    handleProfileChange(event) {
        const detail = event.detail || {};
        this.headerFirstName = detail.firstName || '';
        this.headerLastName = detail.lastName || '';
        this.headerProfileImageUrl = detail.profileImageUrl || '';
    }

    get timerDisplay() {
        const minutes = Math.floor(this.otpTimerSeconds / 60);
        const seconds = this.otpTimerSeconds % 60;
        return `${minutes}:${seconds.toString().padStart(2, '0')}`;
    }

    handleEmailChange(event) {
        this.userEmail = (event.target.value || '').trim();
    }

    async handleRequestOtp() {
        this.refreshRoleId();
        if (!this.userEmail) {
            this.showError('Error', 'Please enter your email.');
            return;
        }
        this.isLoading = true;
        try {
            await sendOnboardingOtp({
                email: this.userEmail,
                accountId: null,
                roleId: this.roleId || null,
                token: this.onboardToken || null
            });
            this.showOtpInputs = true;
            this.startOtpTimer();
            this.showSuccess('Success', 'OTP sent to your email.');
        } catch (e) {
            const msg = e?.body?.message || 'Unable to send OTP.';
            this.showError('Error', msg);
        } finally {
            this.isLoading = false;
        }
    }

    async handleVerifyOtp() {
        this.refreshRoleId();
        const otpCode = this.otpInputs.map(i => i.value).join('');
        if (otpCode.length !== 4) {
            this.showError('Error', 'Please enter the complete OTP.');
            return;
        }
        this.isLoading = true;
        try {
            const loginUrl = await verifyOnboardingOtp({
                email: this.userEmail,
                otpEntered: otpCode,
                accountId: null,
                roleId: this.roleId || null,
                token: this.onboardToken || null
            });
            if (this.roleId) {
                window.localStorage.setItem('ConstituentRoleId', this.roleId);
            }
            this.showOtpScreen = false;
            this.showStepper = true;
            document.documentElement.classList.remove('hide-community-header');
            this.clearOtpTimer();
            this.showSuccess('Verified', 'Email verified. Continue onboarding.');
            if (loginUrl) {
                window.location.assign(loginUrl);
                return;
            } else {
                console.info('No loginUrl returned; staying on page.');
            }
        } catch (e) {
            const msg = e?.body?.message || 'Invalid OTP. Please try again.';
            this.otpInputs = this.otpInputs.map(i => ({ ...i, value: '' }));
            this.showError('Error', msg);
        } finally {
            this.isLoading = false;
        }
    }

    handleOtpInput(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = (event.target.value || '').replace(/[^0-9]/g, '').slice(0, 1);
        this.otpInputs[index].value = value;
        this.otpInputs = [...this.otpInputs];
        if (value && index < this.otpInputs.length - 1) {
            const next = this.template.querySelector(`[data-index="${index + 1}"]`);
            if (next) next.focus();
        }
    }

    handleOtpKeyDown(event) {
        const index = parseInt(event.target.dataset.index, 10);
        if (event.key === 'Backspace' && !event.target.value && index > 0) {
            const prev = this.template.querySelector(`[data-index="${index - 1}"]`);
            if (prev) prev.focus();
        }
    }

    handleOtpPaste(event) {
        event.preventDefault();
        const data = (event.clipboardData || window.clipboardData).getData('text') || '';
        const digits = data.replace(/[^0-9]/g, '').slice(0, this.otpInputs.length);
        this.otpInputs = this.otpInputs.map((input, idx) => ({
            ...input,
            value: digits[idx] || ''
        }));
    }

    handleEditEmail() {
        this.showOtpInputs = false;
        this.otpInputs = this.otpInputs.map(i => ({ ...i, value: '' }));
        this.clearOtpTimer();
        this.canResendOtp = false;
        this.userEmail = '';
    }

    startOtpTimer() {
        this.clearOtpTimer();
        this.otpTimerSeconds = 120;
        this.canResendOtp = false;
        this.otpTimerInterval = setInterval(() => {
            this.otpTimerSeconds--;
            if (this.otpTimerSeconds <= 0) {
                this.clearOtpTimer();
                this.canResendOtp = true;
            }
        }, 1000);
    }

    clearOtpTimer() {
        if (this.otpTimerInterval) {
            clearInterval(this.otpTimerInterval);
            this.otpTimerInterval = null;
        }
    }

    showSuccess(title, message) {
        this.toastTitle = title;
        this.toastMessage = message;
        this.toastVariant = 'success';
        this.showToast = true;
        window.clearTimeout(this.toastTimeout);
        this.toastTimeout = window.setTimeout(() => {
            this.showToast = false;
        }, 1500);
    }

    showError(title, message) {
        this.toastTitle = title;
        this.toastMessage = message;
        this.toastVariant = 'error';
        this.showToast = true;
        window.clearTimeout(this.toastTimeout);
        this.toastTimeout = window.setTimeout(() => {
            this.showToast = false;
        }, 1500);
    }

    handleBackToLogin() {
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

    getTokenFromUrl() {
        try {
            const url = new URL(window.location.href);
            return url.searchParams.get('token');
        } catch (e) {
            return null;
        }
    }

    refreshRoleId() {
        if (this.roleId) {
            return;
        }
        const fromStorage = window.localStorage.getItem('ConstituentRoleId');
        if (fromStorage) {
            this.roleId = fromStorage;
        }
    }

    async initializeState() {
        if (!this.roleId) {
            return;
        }
        this.isLoading = true;
        try {
            const state = await getOnboardingState({ accountId: null, roleId: this.roleId || null });
            if (state) {
                if (state.email) {
                    this.userEmail = state.email;
                }
                if (state.isVerified) {
                    this.showOtpScreen = false;
                    this.showStepper = true;
                    document.documentElement.classList.remove('hide-community-header');
                } else if (state.verificationRequired === false) {
                    // Verification turned off for this org — skip the OTP screen.
                    // Auto-complete verification (marks the role Verified + logs the
                    // user in) and redirect, exactly like a successful OTP would.
                    const loginUrl = await autoVerifyOnboarding({
                        email: this.userEmail || null,
                        accountId: null,
                        roleId: this.roleId || null,
                        token: this.onboardToken || null
                    });
                    if (loginUrl) {
                        // Keep the loader visible through the redirect so the OTP
                        // screen never flashes in the gap before navigation.
                        this._isRedirecting = true;
                        window.location.assign(loginUrl);
                        return;
                    }
                    // No login issued (e.g. user already exists) — just show the stepper.
                    this.showOtpScreen = false;
                    this.showStepper = true;
                    document.documentElement.classList.remove('hide-community-header');
                }
            }
        } catch (e) {
            // ignore state errors; stay on OTP
        } finally {
            this.isLoading = false;
            // While redirecting, leave the loader up — don't reveal the OTP screen.
            if (!this._isRedirecting) {
                this.isInitializing = false;
            }
        }
    }
}