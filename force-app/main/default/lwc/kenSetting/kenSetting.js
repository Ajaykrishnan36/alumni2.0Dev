import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenSetting extends LightningElement {
    @track institutionName = '';
    currentTab = 'Personal Details';

    connectedCallback() {
        // Check if a specific tab was requested via sessionStorage (e.g. from "Become a Mentor" button)
        try {
            const pendingTab = sessionStorage.getItem('ken_setting_active_tab');
            if (pendingTab) {
                this.currentTab = pendingTab;
                sessionStorage.removeItem('ken_setting_active_tab');
            }
        } catch (e) {
            // ignore storage errors
        }

        getPrimaryColor().then(color => {
            this.institutionName = color?.institutionAlias;
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            this.institutionName = 'Ken42';
            console.log('Error getting primary color');
        });
    }

    get menuItems() {
        return [
            { name: 'Personal Details', label: 'Personal Details', class: this.getItemClass('Personal Details'), isActive: this.currentTab === 'Personal Details' },
            { name: 'Preferences', label: 'Preferences', class: this.getItemClass('Preferences'), isActive: this.currentTab === 'Preferences' },
            { name: 'Events', label: 'Events', class: this.getItemClass('Events'), isActive: this.currentTab === 'Events' },
            { name: 'Groups', label: 'Groups', class: this.getItemClass('Groups'), isActive: this.currentTab === 'Groups' },
            { name: 'Mentorship', label: 'Mentorship', class: this.getItemClass('Mentorship'), isActive: this.currentTab === 'Mentorship' },
            { name: 'Jobs', label: 'Jobs', class: this.getItemClass('Jobs'), isActive: this.currentTab === 'Jobs' },
            { name: 'Account', label: 'Account', class: this.getItemClass('Account'), isActive: this.currentTab === 'Account' }
        ];
    }

    getItemClass(tabName) {
        return this.currentTab === tabName ? 'nav-item active' : 'nav-item';
    }

    handleTabChange(event) {
        this.currentTab = event.currentTarget.dataset.name;
    }

    handleMobileTabChange(event) {
        this.currentTab = event.target.value;
    }

    get isPersonalDetails() { return this.currentTab === 'Personal Details'; }
    get isPreferences() { return this.currentTab === 'Preferences'; }
    get isEvents() { return this.currentTab === 'Events'; }
    get isGroups() { return this.currentTab === 'Groups'; }
    get isMentorship() { return this.currentTab === 'Mentorship'; }
    get isJobs() { return this.currentTab === 'Jobs'; }
    get isAccount() { return this.currentTab === 'Account'; }
}