import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { publish, MessageContext } from 'lightning/messageService';
import KenLogo from '@salesforce/resourceUrl/LoginKen';
import getNavigationMenuItems from '@salesforce/apex/KenNavBarController.getNavigationMenuItems';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getUserContactDetails from '@salesforce/apex/KenNavBarController.getUserContactDetails';
import loginBg from '@salesforce/resourceUrl/AlumniAlt';

export default class KenHeader extends NavigationMixin(LightningElement) {
    @wire(MessageContext)
    messageContext;

    kenLogo = KenLogo;
    profilePhotoUrl;
    studentName;
    graduationYear;
    @api headerLabel;
    @api linkSetMasterLabel = 'Default Navigation';
    @api parentPageName = 'Home';
    @api parentPageUrl;
    @api childPageName;
    @api childPageUrl;
    @api settingsPageApiName = 'settings__c';
    @api calendarPageApiName = 'Calendar__c';
    @api chatPageApiName = '';
    @api parentPageApiName = '';

    @track dynamicHeaderLabel = '';
    @track menuItems = [];
    @track breadcrumbLabel = '';
    @track breadcrumbs = [];
    @track hasBreadcrumbVisible = false;
    publishStatus;

    @wire(CurrentPageReference)
    setCurrentPageReference(ref) {
        const app = ref?.state?.app;
        this.publishStatus = app === 'commeditor' ? 'Draft' : 'Live';
        this.updateHeaderLabel();
    }

    @wire(getNavigationMenuItems, {
        navigationLinkSetMasterLabel: '$linkSetMasterLabel',
        publishStatus: '$publishStatus',
        addHomeMenuItem: false,
        includeImageUrl: false
    })
    wiredMenuItems({ error, data }) {
        if (data) {
            const base = this.getCommunityBasePath();
            this.menuItems = data.map(item => {
                const normalizedTarget = this.normalizePath(
                    item.actionValue || (item.label === 'Home' ? base : ''),
                    base
                );
                return {
                    label: item.label,
                    normalizedTarget
                };
            });
            this.updateHeaderLabel();
        } else if (error) {
            console.error('Header navigation load error:', error);
        }
    }

    @wire(getUserContactDetails)
    wiredUserDetails({ error, data }) {
        if (data) {
            this.profilePhotoUrl = data.profilePhotoUrl || loginBg;
            this.studentName = data.studentName || 'Student Name';
            this.graduationYear = data.graduationYear;
        } else if (error) {
            console.error('Header: Error fetching user details:', error);
            this.profilePhotoUrl = loginBg;
            this.studentName = 'Student Name';
            this.graduationYear = undefined;
        }
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    get computedHeaderLabel() {
        return this.headerLabel || this.dynamicHeaderLabel || '';
    }

    get myFeedCardClass() {
        return this.hasBreadcrumbVisible 
            ? 'my-feed-card has-breadcrumb' 
            : 'my-feed-card';
    }

    handleCalendarClick() {
        // Handle calendar click
        this.dispatchEvent(new CustomEvent('calendarclick', {
            bubbles: true,
            composed: true
        }));
    }

    handleSettingsClick() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: this.settingsPageApiName || 'settings__c' }
        });
    }

    handleChatClick() {
        const basePath = this.getCommunityBasePath();
        const fallbackUrl = `${basePath}/chat`.replace(/\/+/g, '/');
        if (this.chatPageApiName) {
            const pageRef = { type: 'comm__namedPage', attributes: { name: this.chatPageApiName } };
            this[NavigationMixin.GenerateUrl](pageRef)
                .then(() => { this[NavigationMixin.Navigate](pageRef); })
                .catch(() => { window.location.assign(fallbackUrl); });
        } else {
            window.location.assign(fallbackUrl);
        }
    }

    handleNotificationClick() {
        // Handle notification click
        this.dispatchEvent(new CustomEvent('notificationclick', {
            bubbles: true,
            composed: true
        }));
    }

    @track isMobileMenuOpen = false;

    handleMenuClick() {
        console.log('KenHeader: Menu clicked (Local toggle)');
        this.isMobileMenuOpen = true;
    }

    handleCloseMenu() {
        this.isMobileMenuOpen = false;
    }

    handleMobileProfileKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.navigateToMyProfile(event);
        }
    }

    navigateToMyProfile(event) {
        if (event) {
            event.stopPropagation();
        }
        this.handleCloseMenu();
        const pageRef = {
            type: 'comm__namedPage',
            attributes: { name: 'my_profile__c' }
        };
        const basePath = this.getCommunityBasePath();
        const fallbackUrl = `${basePath}/my-profile`.replace(/\/+/g, '/');

        this[NavigationMixin.GenerateUrl](pageRef)
            .then(() => {
                this[NavigationMixin.Navigate](pageRef);
            })
            .catch(() => {
                window.location.assign(fallbackUrl);
            });
    }

    handleMobileSettingsClick() {
        this.handleCloseMenu();
        const apiName = this.settingsPageApiName || 'settings__c';
        const pageRef = { type: 'comm__namedPage', attributes: { name: apiName } };
        const basePath = this.getCommunityBasePath();
        const fallbackUrl = `${basePath}/settings`.replace(/\/+/g, '/');

        this[NavigationMixin.GenerateUrl](pageRef)
            .then(() => { this[NavigationMixin.Navigate](pageRef); })
            .catch(() => { window.location.assign(fallbackUrl); });
    }

    handleMobileCalendarClick() {
        this.handleCloseMenu();
        const apiName = this.calendarPageApiName || 'Calendar__c';
        const pageRef = { type: 'comm__namedPage', attributes: { name: apiName } };
        const basePath = this.getCommunityBasePath();
        const fallbackUrl = `${basePath}/calendar`.replace(/\/+/g, '/');

        this[NavigationMixin.GenerateUrl](pageRef)
            .then(() => { this[NavigationMixin.Navigate](pageRef); })
            .catch(() => { window.location.assign(fallbackUrl); });
    }

    handleMobileChatClick() {
        this.handleCloseMenu();
        const basePath = this.getCommunityBasePath();
        if (this.chatPageApiName) {
            const pageRef = { type: 'comm__namedPage', attributes: { name: this.chatPageApiName } };
            this[NavigationMixin.GenerateUrl](pageRef)
                .then(() => { this[NavigationMixin.Navigate](pageRef); })
                .catch(() => {
                    const fallbackUrl = `${basePath}/chat`.replace(/\/+/g, '/');
                    window.location.assign(fallbackUrl);
                });
        } else {
            const chatUrl = `${basePath}/chat`.replace(/\/+/g, '/');
            window.location.assign(chatUrl);
        }
    }

    handleBreadcrumbVisibilityChange(event) {
        this.hasBreadcrumbVisible = event.detail.isVisible;
    }

    updateHeaderLabel() {
        const base = this.getCommunityBasePath();
        const currentPath = this.normalizePath(window.location?.pathname || '/', base);

        this.updateBreadcrumbLabel(currentPath, base);

        if (!this.menuItems?.length) {
            return;
        }

        let bestMatch = { label: '', score: -1 };

        this.menuItems.forEach(item => {
            const target = item.normalizedTarget;
            if (!target) return;

            if (target === currentPath) {
                const score = target.length + 1000;
                if (score > bestMatch.score) bestMatch = { label: item.label, score };
            } else if (currentPath.startsWith(target + '/')) {
                const score = target.length;
                if (score > bestMatch.score) bestMatch = { label: item.label, score };
            }
        });

        this.dynamicHeaderLabel = bestMatch.label || '';
    }

    updateBreadcrumbLabel(currentPath, communityBasePath) {
        if (!currentPath) {
            this.breadcrumbLabel = '';
            this.breadcrumbs = [];
            return;
        }

        let pathAfterBase = currentPath;
        if (communityBasePath && currentPath.startsWith(communityBasePath)) {
            pathAfterBase = currentPath.slice(communityBasePath.length);
        }

        const segments = pathAfterBase.split('/').filter(Boolean);
        const basePath = communityBasePath || '/';

        const crumbs = [
            {
                label: 'Home',
                url: basePath,
                clickable: segments.length > 0,
                isLast: segments.length === 0
            }
        ];

        if (segments.length) {
            let cumulativePath = basePath;
            segments.forEach((seg, index) => {
                const decoded = decodeURIComponent(seg);
                const label = this.formatBreadcrumbLabel(decoded);
                cumulativePath = this.normalizePath(`${cumulativePath}/${decoded}`, basePath);

                crumbs.push({
                    label,
                    url: cumulativePath,
                    clickable: index < segments.length - 1,
                    isLast: index === segments.length - 1
                });
            });
        }

        this.breadcrumbs = crumbs.map((crumb, index) => ({
            ...crumb,
            hasNext: index < crumbs.length - 1
        }));
        this.breadcrumbLabel = crumbs.length ? crumbs[crumbs.length - 1].label : '';
        this.breadcrumbs = crumbs.map((crumb, index) => ({
            ...crumb,
            hasNext: index < crumbs.length - 1,
            cssClass: crumb.isLast ? 'breadcrumb-leaf' : 'breadcrumb-link'
        }));
    }

    formatBreadcrumbLabel(segment) {
        return segment
            .replace(/[-_]/g, ' ')
            .replace(/\s+/g, ' ')
            .trim()
            .replace(/\b\w/g, char => char.toUpperCase());
    }

    get hasBreadcrumbs() {
        return (this.breadcrumbs?.length || 0) > 1 || (this.breadcrumbs?.[0]?.label === 'Home');
    }

    getCommunityBasePath() {
        const pathname = window?.location?.pathname || '/';
        const parts = pathname.split('/').filter(Boolean);
        if (!parts.length) return '/';

        const sIndex = parts.indexOf('s');
        if (sIndex > 0) {
            // Handles typical Experience Cloud paths like /alumni/s/*
            return `/${parts.slice(0, sIndex + 1).join('/')}`;
        }

        return `/${parts[0]}`;
    }

    normalizePath(path, communityBasePath = '/') {
        if (!path) return '';

        if (/^https?:\/\//i.test(path)) {
            return '';
        }

        let normalized = path.trim();
        if (!normalized.startsWith('/')) {
            normalized = '/' + normalized;
        }

        normalized = normalized.replace(/\/+$/, '');
        if (normalized === '') normalized = '/';

        if (
            communityBasePath !== '/' &&
            normalized !== communityBasePath &&
            !normalized.startsWith(communityBasePath + '/')
        ) {
            const baseParts = communityBasePath.split('/').filter(Boolean);
            const communityRoot = baseParts.length > 0 ? `/${baseParts[0]}` : '/';

            if (normalized === communityRoot || normalized.startsWith(communityRoot + '/')) {
                normalized = normalized.replace(communityRoot, communityBasePath);
            } else {
                normalized = `${communityBasePath}${normalized}`;
            }
        }

        normalized = normalized.replace(/\/+$/, '');
        if (normalized === '') normalized = communityBasePath !== '/' ? communityBasePath : '/';

        return normalized;
    }
}