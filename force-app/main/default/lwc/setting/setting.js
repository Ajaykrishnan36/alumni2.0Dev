import { LightningElement } from 'lwc';

export default class Setting extends LightningElement {
    currentTab = 'Preferences';

    get menuItems() {
        return [
            { name: 'Preferences', label: 'Preferences', class: this.getItemClass('Preferences') },
            { name: 'Events', label: 'Events', class: this.getItemClass('Events') },
            { name: 'Groups', label: 'Groups', class: this.getItemClass('Groups') },
            { name: 'Mentorship', label: 'Mentorship', class: this.getItemClass('Mentorship') },
            { name: 'Jobs', label: 'Jobs', class: this.getItemClass('Jobs') },
            { name: 'Account', label: 'Account', class: this.getItemClass('Account') }
        ];
    }

    getItemClass(tabName) {
        return this.currentTab === tabName ? 'nav-item active' : 'nav-item';
    }

    handleTabChange(event) {
        this.currentTab = event.currentTarget.dataset.name;
    }

    get isPreferences() { return this.currentTab === 'Preferences'; }
    get isEvents() { return this.currentTab === 'Events'; }
    get isGroups() { return this.currentTab === 'Groups'; }
    get isMentorship() { return this.currentTab === 'Mentorship'; }
    get isJobs() { return this.currentTab === 'Jobs'; }
    get isAccount() { return this.currentTab === 'Account'; }
}