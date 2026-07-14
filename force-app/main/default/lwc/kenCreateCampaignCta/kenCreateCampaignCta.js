import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import listYourBusinessImage from '@salesforce/resourceUrl/Listyourbusiness';

export default class KenCreateCampaignCta extends NavigationMixin(LightningElement) {
    illustrationUrl = listYourBusinessImage;

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