import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';

import loginBg from '@salesforce/resourceUrl/AlumniAlt';
import getUserContactDetails from '@salesforce/apex/KenNavBarController.getUserContactDetails';
import getNavigationMenuItems from '@salesforce/apex/KenNavBarController.getNavigationMenuItems';
import ensureSessionLastLogin from '@salesforce/apex/KenConstituentRoleService.ensureSessionLastLogin';
import getAlumniRolesForPerson from '@salesforce/apex/KenAlumniOnboardingService.getAlumniRolesForPerson';

// Cache keys for sessionStorage
const PROFILE_CACHE_KEY = 'navigationMenu_profileCache';
const CACHE_DURATION_MS = 30 * 60 * 1000; // 30 minutes

import HomeIcon from '@salesforce/resourceUrl/HomeIcon';
import MyFeedIcon from '@salesforce/resourceUrl/MyFeedIcon';
import EventIcon from '@salesforce/resourceUrl/EventIcon';
import JobIcon from '@salesforce/resourceUrl/JobIcon';
import MentorshipIcon from '@salesforce/resourceUrl/MentorshipIcon';
import FundraiseIcon from '@salesforce/resourceUrl/FundraiseIcon';
import NetworkIcon from '@salesforce/resourceUrl/NetworkIcon';
import GroupIcon from '@salesforce/resourceUrl/GroupIcon';
import GalleryIcon from '@salesforce/resourceUrl/GalleryIcon';
import BusinessDirectoryIcon from '@salesforce/resourceUrl/BusinessDirectoryIcon';
import InfoHubIcon from '@salesforce/resourceUrl/InfoHubIcon';
import SurveyIcon from '@salesforce/resourceUrl/SurveyIcon';
import ServiceSupportIcon from '@salesforce/resourceUrl/ServiceSupportIcon';
import LogoutIcon from '@salesforce/resourceUrl/LogoutIcon';
import SideLogo from '@salesforce/resourceUrl/sidelogo';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import { getModuleVisibility } from 'c/kenModuleConfig';

// Maps a navigation item label to its Alumni_Module_Settings__c toggle key.
// Labels not listed here (e.g. Logout, My Feed, Info Hub) are never hidden.
const LABEL_TO_MODULE_FLAG = {
    'Home': 'home',
    'Events': 'events',
    'Jobs': 'jobs',
    'Network': 'network',
    'Mentorship': 'mentorship',
    'Fundraise': 'fundraise',
    'Groups': 'groups',
    'Gallery': 'gallery',
    'Business Directory': 'businessDirectory',
    'Feedback and Survey': 'feedbackSurvey',
    'Service and Support': 'serviceSupport'
};

const ICON_BY_LABEL = {
    'Home': HomeIcon,
    'My Feed': MyFeedIcon,
    'Events': EventIcon,
    'Jobs': JobIcon,
    'Mentorship': MentorshipIcon,
    'Fundraise': FundraiseIcon,
    'Network': NetworkIcon,
    'Groups': GroupIcon,
    'Gallery': GalleryIcon,
    'Business Directory': BusinessDirectoryIcon,
    'Info Hub': InfoHubIcon,
    'Feedback and Survey': SurveyIcon,
    'Service and Support': ServiceSupportIcon,
    'Logout': LogoutIcon
};

export default class kenNavBar extends NavigationMixin(LightningElement) {

    @api linkSetMasterLabel = 'Default Navigation';
    @api addHomeMenuItem = false;
    @api includeImageUrls = false;

    @track menuItems = [];
    @track selectedItemId = null;
    @track isMobileMenuOpen = false;
    @api isAlwaysOpen = false;

    // null until loaded; while null nothing is hidden (fail open).
    @track moduleVisibility = null;

    @api
    toggleMenu() {
        this.isMobileMenuOpen = !this.isMobileMenuOpen;
    }

    @api
    openMenu() {
        this.isMobileMenuOpen = true;
    }

    @api
    closeMenu() {
        this.isMobileMenuOpen = false;
    }

    get sidebarClass() {
        return `sidebar ${this.isMobileMenuOpen || this.isAlwaysOpen ? 'mobile-open' : ''} ${this.isAlwaysOpen ? 'embedded-mode' : ''}`;
    }

    profilePhotoUrl;
    studentName;
    graduationYear;
    sideLogoUrl = SideLogo;
    @track showRoleSwitch = false;

    publishStatus;
    isLoaded = false;

    @wire(CurrentPageReference)
    setCurrentPageReference(ref) {
        const app = ref?.state?.app;
        this.publishStatus = app === 'commeditor' ? 'Draft' : 'Live';
        setTimeout(() => this.updateSelectedItem(), 0);
    }

    @wire(getNavigationMenuItems, {
        navigationLinkSetMasterLabel: '$linkSetMasterLabel',
        publishStatus: '$publishStatus',
        addHomeMenuItem: '$addHomeMenuItem',
        includeImageUrl: false
    })
    wiredMenuItems({ error, data }) {
        if (data && !this.isLoaded) {

            const basePath = this.getCommunityBasePath();

            this.menuItems = data.map((item, index) => {
                const rawTarget = item.actionValue || '';
                const normalizedTarget = this.normalizePath(rawTarget || (item.label === 'Home' ? basePath : ''), basePath);

                const subMenu = (item.subMenu || []).map((sub, subIndex) => {
                    const rawSub = sub.actionValue || '';
                    const normalizedSub = this.normalizePath(rawSub, basePath);

                    return {
                        ...sub,
                        id: `${index}-${subIndex}`,
                        normalizedActionValue: normalizedSub,
                        iconName: ICON_BY_LABEL[sub.label] || null
                    };
                });

                return {
                    id: index,
                    label: item.label,
                    type: item.actionType,
                    target: rawTarget || basePath,
                    normalizedTarget,
                    subMenu,
                    iconName: ICON_BY_LABEL[item.label] || null
                };
            });

            this.isLoaded = true;
            this.updateSelectedItem();
        }
        else if (error) {
            this.menuItems = [];
            this.isLoaded = true;
            console.error('Navigation Menu Load Error:', error);
        }
    }

    @wire(getUserContactDetails)
    wiredUserDetails({ error, data }) {
        if (data) {
            const profileData = {
                profilePhotoUrl: data.profilePhotoUrl || loginBg,
                studentName: data.studentName || 'Student Name',
                graduationYear: data.graduationYear
            };

            // Update component properties
            this.profilePhotoUrl = profileData.profilePhotoUrl;
            this.studentName = profileData.studentName;
            this.graduationYear = profileData.graduationYear;

            // Save to cache
            this._saveProfileToCache(profileData);
        } else if (error) {
            console.error('NavigationMenu: Error fetching user details:', error);
            // Use fallback values
            this.profilePhotoUrl = loginBg;
            this.studentName = 'Student Name';
            this.graduationYear = '2025';
        }
    }

    connectedCallback() {
        this._stampSessionLogin();
        this._loadRoleSwitchVisibility();
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });

        getModuleVisibility().then(visibility => {
            this.moduleVisibility = visibility;
        }).catch(() => {
            // Fail open: leave moduleVisibility null so every module stays visible.
            console.log('Error getting module visibility');
        });

        // Load profile data from cache first
        this._loadProfileFromCache();

        this.updateSelectedItem();
        window.addEventListener('popstate', () => {
            this.updateSelectedItem();
        });

    }

    disconnectedCallback() {
        document.removeEventListener('ken_mobile_menu_toggle', this._windowMenuHandler);
    }

    /**
     * Once per browser session (and never on the login/onboarding flow pages), stamps
     * ConstituentRole.Last_Login__c and routes sessions that skipped the select-role
     * screen (SSO deep links, admin Login-As) back into the standard journey when the
     * role's registration status shows onboarding/welcome is still incomplete.
     */
    _stampSessionLogin() {
        const path = window.location.pathname || '';
        if (/(login|select-role|onboarding-form|welcome-page|verify-link)/.test(path)) {
            return;
        }
        try {
            if (sessionStorage.getItem('kenSessionLoginStamped')) {
                return;
            }
            sessionStorage.setItem('kenSessionLoginStamped', '1');
        } catch (e) {
            return;
        }
        ensureSessionLastLogin()
            .then(status => {
                if (status && status !== 'Initial Login Done') {
                    const baseMatch = path.match(/^\/[^/]+/);
                    const base = baseMatch ? baseMatch[0] : '';
                    window.location.assign(`${window.location.origin}${base}/select-role`);
                }
            })
            .catch(() => {});
    }

    /**
     * Load profile data from sessionStorage cache
     */
    _loadProfileFromCache() {
        try {
            const cachedData = sessionStorage.getItem(PROFILE_CACHE_KEY);
            if (cachedData) {
                const { data, timestamp } = JSON.parse(cachedData);

                // Check if cache is still valid (not expired)
                if (Date.now() - timestamp < CACHE_DURATION_MS) {
                    this.profilePhotoUrl = data.profilePhotoUrl || loginBg;
                    this.studentName = data.studentName || 'Student Name';
                    this.graduationYear = data.graduationYear || '2025';
                    console.log('NavigationMenu: Loaded profile from cache');
                    return true; // Cache hit
                } else {
                    // Cache expired, remove it
                    sessionStorage.removeItem(PROFILE_CACHE_KEY);
                }
            }
        } catch (e) {
            console.error('NavigationMenu: Error loading profile from cache:', e);
            sessionStorage.removeItem(PROFILE_CACHE_KEY);
        }
        return false; // Cache miss
    }

    /**
     * Save profile data to sessionStorage cache
     */
    _saveProfileToCache(profileData) {
        try {
            const cacheEntry = {
                data: profileData,
                timestamp: Date.now()
            };
            sessionStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(cacheEntry));
            console.log('NavigationMenu: Saved profile to cache');
        } catch (e) {
            console.error('NavigationMenu: Error saving profile to cache:', e);
            // If storage is full, try to clear old cache entries
            try {
                sessionStorage.removeItem(PROFILE_CACHE_KEY);
                sessionStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify({
                    data: profileData,
                    timestamp: Date.now()
                }));
            } catch (e2) {
                console.error('NavigationMenu: Failed to save profile cache after cleanup:', e2);
            }
        }
    }

    handleItemSelect(event) {
        this.selectedItemId = event.detail.selectedItemId;

        this.menuItems = this.menuItems.map(item => ({
            ...item,
            subMenu: item.subMenu.map(sub => ({ ...sub, isSelected: false }))
        }));
    }

    handleSubMenuSelect(event) {
        const { parentItemId, selectedItemId } = event.detail;
        this.selectedItemId = parentItemId;

        this.menuItems = this.menuItems.map(item => ({
            ...item,
            subMenu: item.subMenu.map(sub => ({
                ...sub,
                isSelected: item.id === parentItemId && sub.id === selectedItemId
            }))
        }));
    }

    updateSelectedItem() {

        if (!this.menuItems?.length) return;

        const basePath = this.getCommunityBasePath();
        const currentPath = this.normalizePath(window.location.pathname, basePath);
        let bestMatch = { id: null, score: -1 };

        const considerMatch = (id, target) => {
            if (!target) return;
            if (target === currentPath) {
                const score = target.length + 1000;
                if (score > bestMatch.score) bestMatch = { id, score };
            } else if (currentPath.startsWith(target + '/')) {
                const score = target.length;
                if (score > bestMatch.score) bestMatch = { id, score };
            }
        };

        this.menuItems.forEach(item => {
            considerMatch(item.id, item.normalizedTarget);
            item.subMenu.forEach(sub => considerMatch(item.id, sub.normalizedActionValue));
        });

        this.selectedItemId = bestMatch.id;
    }

    normalizePath(path, basePath = '/') {
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

        if (basePath !== '/' && normalized !== basePath && !normalized.startsWith(basePath + '/')) {
            const baseParts = basePath.split('/').filter(Boolean);
            const communityRoot = baseParts.length > 0 ? `/${baseParts[0]}` : '/';

            if (normalized === communityRoot || normalized.startsWith(communityRoot + '/')) {
                normalized = normalized.replace(communityRoot, basePath);
            } else {
                normalized = `${basePath}${normalized}`;
            }
        }

        normalized = normalized.replace(/\/+$/, '');
        if (normalized === '') normalized = basePath !== '/' ? basePath : '/';

        return normalized;
    }

    getCommunityBasePath() {
        const pathname = window?.location?.pathname || '/';
        const parts = pathname.split('/').filter(Boolean);
        if (!parts.length) return '/';

        if (parts.length >= 2 && parts[1] === 's') {
            return `/${parts[0]}/s`;
        }
        return `/${parts[0]}`;
    }

    get menuItemsToDisplay() {
        return this.menuItems.map(item => ({
            ...item,
            isSelected: item.id === this.selectedItemId
        }));
    }

    get regularMenuItems() {
        return this.menuItemsToDisplay
            .filter(item => item.label !== 'Logout')
            .filter(item => this.isModuleVisible(item.label));
    }

    // A module is hidden only when its toggle is explicitly false. Labels with
    // no toggle, and the period before visibility loads, stay visible.
    isModuleVisible(label) {
        if (!this.moduleVisibility) return true;
        const flag = LABEL_TO_MODULE_FLAG[label];
        if (!flag) return true;
        return this.moduleVisibility[flag] !== false;
    }

    get logoutMenuItems() {
        return this.menuItemsToDisplay.filter(item => item.label === 'Logout');
    }

    handleImageError(event) {
        event.target.src = loginBg;
    }

    navigateToHomePage() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'Home' }
        });
    }

    /**
     * The switch-role icon only renders when the person has more than one
     * alumni role — the same list the select-role screen offers. Cached per
     * session so the icon doesn't flicker on every page load.
     */
    _loadRoleSwitchVisibility() {
        try {
            if (sessionStorage.getItem('kenHasMultipleRoles') === '1') {
                this.showRoleSwitch = true;
            }
        } catch (e) { /* ignore */ }
        getAlumniRolesForPerson({ personId: null })
            .then(roles => {
                const multi = (roles || []).length > 1;
                this.showRoleSwitch = multi;
                try { sessionStorage.setItem('kenHasMultipleRoles', multi ? '1' : '0'); } catch (e) { /* ignore */ }
            })
            .catch(() => {
                this.showRoleSwitch = false;
            });
    }

    navigateToRoleSelect(event) {
        if (event) {
            event.stopPropagation();
        }
        const pageRef = {
            type: 'comm__namedPage',
            attributes: { name: 'select_role__c' }
        };
        const basePath = this.getCommunityBasePath();
        const fallbackUrl = `${basePath}/select-role`.replace(/\/+/g, '/');

        this[NavigationMixin.GenerateUrl](pageRef)
            .then(() => {
                this[NavigationMixin.Navigate](pageRef);
            })
            .catch(() => {
                window.location.assign(fallbackUrl);
            });
    }

    navigateToMyProfile(event) {
        if (event) {
            event.stopPropagation();
        }
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
}