import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import listYourBusinessImage from '@salesforce/resourceUrl/Listyourbusiness';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenCreateCampaignCta extends NavigationMixin(LightningElement) {
    illustrationUrl = listYourBusinessImage;
    canCreateFundraise = false;

    connectedCallback() {
        getPrimaryColor()
            .then((color) => {
                this.canCreateFundraise = color?.createFundraise !== false;
            })
            .catch(() => {});
    }

    handleClick() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'create_campaign__c' }
        });
    }

    handleImageError(event) {
        event.target.style.display = 'none';
    }
}