import { LightningElement, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
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
    showStepper = true;
    userEmail = '';
    roleId = '';
    onboardToken = '';
    isLoading = false;
    showToast = false;
    toastTitle = '';
    toastMessage = '';
    toastVariant = 'success';
    toastTimeout;
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

        // hide the community header until onboarding decides what to render
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
            if (state && state.email) {
                this.userEmail = state.email;
            }
            if (!state || !state.isVerified) {
                // Clicking the magic link is the only proof required. Complete
                // verification server-side (marks the role Verified and logs the
                // user in) and follow the redirect straight into onboarding.
                const loginUrl = await autoVerifyOnboarding({
                    email: this.userEmail || null,
                    accountId: null,
                    roleId: this.roleId || null,
                    token: this.onboardToken || null
                });
                if (loginUrl) {
                    // Hold the loader through the redirect so nothing flashes.
                    this._isRedirecting = true;
                    window.location.assign(loginUrl);
                    return;
                }
            }
            document.documentElement.classList.remove('hide-community-header');
        } catch (e) {
            // Onboarding still renders if the state call fails.
            document.documentElement.classList.remove('hide-community-header');
        } finally {
            this.isLoading = false;
            if (!this._isRedirecting) {
                this.isInitializing = false;
            }
        }
    }
}