import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getAlumniRolesForPerson from '@salesforce/apex/KenAlumniOnboardingService.getAlumniRolesForPerson';
import SideLogo from '@salesforce/resourceUrl/sidelogo';
import KenLogo from '@salesforce/resourceUrl/LoginKen';

export default class KenRoleSelect extends LightningElement {
    sideLogoUrl = SideLogo;
    kenLogo = KenLogo;
    @track accounts = [];
    accountId = '';
    isLoading = true;

    connectedCallback() {
        document.body.style.overflow = 'hidden';
        getPrimaryColor()
            .then((color) => {
                document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
                document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
                document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
            })
            .catch(() => console.log('Error getting primary color'));

        this.accountId = this.getAccountIdFromUrl() || window.localStorage.getItem('UserAccountId') || '';
        if (this.accountId) {
            window.localStorage.setItem('UserAccountId', this.accountId);
        }
        this.loadAlumniRoles();
    }

    disconnectedCallback() {
        document.body.style.overflow = '';
    }

    get selectedAccount() {
        return this.accounts.find((a) => a.selected) || null;
    }

    get isProceedDisabled() {
        return !this.selectedAccount;
    }

    get containerClass() {
        return `role-select-page-container${this.isLoading ? ' is-loading' : ''}`;
    }

    handleSelectAccount(event) {
        const id = event.currentTarget.dataset.accountId;
        this.accounts = this.accounts.map((a) => {
            const selected = a.id === id;
            return {
                ...a,
                selected,
                itemClass: selected ? 'account-item account-item-selected' : 'account-item'
            };
        });

        const selected = this.accounts.find((a) => a.id === id);
        if (selected) {
            this.persistSelection(selected);
        }
    }

    handleProceed() {
        const selected = this.selectedAccount;
        if (selected) {
            this.persistSelection(selected);
            this.redirectByRoleStatus(selected);
        }
    }

    getAccountIdFromUrl() {
        try {
            const url = new URL(window.location.href);
            return url.searchParams.get('accountId');
        } catch (e) {
            return null;
        }
    }

    async loadAlumniRoles() {
        this.isLoading = true;
        try {
            const roles = await getAlumniRolesForPerson({ personId: this.accountId || null });
            const normalized = (roles || []).map((role) => ({
                id: role.constituentRoleId,
                program: role.programPlanName || '',
                batch: role.batch || '',
                registrationNumber: role.registrationNumber || '',
                roleStatus: role.registrationStatus || '',
                selected: false,
                itemClass: 'account-item'
            }));

            if (normalized.length === 1) {
                this.persistSelection(normalized[0]);
                this.redirectByRoleStatus(normalized[0]);
                return;
            }

            this.accounts = normalized;
            this.isLoading = false;
        } catch (e) {
            console.error('Error loading alumni roles', e);
            this.accounts = [];
            this.isLoading = false;
        }
    }

    persistSelection(role) {
        try {
            if (this.accountId) {
                window.localStorage.setItem('UserAccountId', this.accountId);
            }
            if (role?.id) {
                window.localStorage.setItem('ConstituentRoleId', role.id);
            }
            if (role?.registrationNumber) {
                window.sessionStorage.setItem('RegistrationNumber', role.registrationNumber);
            }
        } catch (e) {
            // Ignore storage failures in non-browser contexts
        }
    }

    redirectByRoleStatus(role) {
        const { origin, pathname } = window.location;
        const baseMatch = pathname.match(/^\/[^/]+/);
        const basePath = baseMatch ? baseMatch[0] : '';
        const roleId = role?.id || '';
        const status = role?.roleStatus || '';

        if ((status === 'Unregistered' || status === 'Verified') && roleId) {
            window.location.assign(`${origin}${basePath}/onboarding-form?roleId=${roleId}`);
            return;
        }
        if (status === 'Registered' && roleId) {
            window.location.assign(`${origin}${basePath}/welcome-page?roleId=${roleId}`);
            return;
        }
        if (status === 'Initial Login Done') {
            this.redirectToPortalHome();
            return;
        }

        window.location.assign(`${origin}${basePath}/select-role`);
    }

    redirectToPortalHome() {
        const { origin, pathname } = window.location;
        const baseMatch = pathname.match(/^\/[^/]+/);
        const basePath = baseMatch ? baseMatch[0] : '';
        window.location.assign(`${origin}${basePath}/`);
    }
}