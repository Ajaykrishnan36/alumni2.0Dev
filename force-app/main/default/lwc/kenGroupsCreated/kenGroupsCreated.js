import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import SurveyEmptyImage from '@salesforce/resourceUrl/SurveyEmptyImage';

export default class KenGroupsCreated extends LightningElement {
    @api groups = [];
    SurveyEmptyImageUrl = SurveyEmptyImage;

    get hasGroups() {
        return this.groups && this.groups.length > 0;
    }

    get groupCount() {
        return this.groups ? this.groups.length : 0;
    }

    handleCreate() {
        this.dispatchEvent(new CustomEvent('create'));
    }

    handleViewAll() {
        this.dispatchEvent(new CustomEvent('viewallcreated'));
    }

    handleGroupClick(event) {
        const groupId = event.currentTarget.dataset.groupId;
        this.dispatchEvent(new CustomEvent('groupclick', {
            detail: { groupId },
            bubbles: true,
            composed: true
        }));
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
}