import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs } from 'c/kenThemeConfig';
export default class KenTabsSection extends LightningElement {
    @api activeTab = 'all';

    connectedCallback() {
        getPortalConfigs().then(colors => {
            if (colors?.primaryColor) {
                document.documentElement.style.setProperty('--primary-color', colors.primaryColor);
            }
            if (colors?.secondaryColor) {
                document.documentElement.style.setProperty('--secondary-color', colors.secondaryColor);
            }
        }).catch(() => {
            console.log('Error getting colors');
        });
    }
    get allTabClass() {
        return this.activeTab === 'all' ? 'tab-button active' : 'tab-button';
    }

    get missingTabClass() {
        return this.activeTab === 'missing' ? 'tab-button active' : 'tab-button';
    }

    handleTabClick(event) {
        const tab = event.currentTarget.dataset.tab;
        this.activeTab = tab;
        this.dispatchEvent(new CustomEvent('tabchange', {
            detail: { tab }
        }));
    }
}