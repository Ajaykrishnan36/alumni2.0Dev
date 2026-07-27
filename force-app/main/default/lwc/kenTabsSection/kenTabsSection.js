import { LightningElement, api, track } from 'lwc';
import getColors from '@salesforce/apex/KenSnSColorController.getColors'; 
export default class KenTabsSection extends LightningElement {
    @api activeTab = 'all';

    connectedCallback() {
        getColors().then(colors => {
            if (colors?.primary) {
                document.documentElement.style.setProperty('--primary-color', colors.primary);
            }
            if (colors?.secondary) {
                document.documentElement.style.setProperty('--secondary-color', colors.secondary);
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