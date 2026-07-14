import { LightningElement } from 'lwc';
import listYourBusinessImage from '@salesforce/resourceUrl/Listyourbusiness';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenListYourBusiness extends LightningElement {
    listYourBusinessImageUrl = listYourBusinessImage;

    handleClick() {
        // Dispatch event to navigate to business listing page
        this.dispatchEvent(new CustomEvent('listbusiness', {
            bubbles: true,
            composed: false
        }));
    }

    handleImageError(event) {
        // Fallback if image fails to load
        console.error('Failed to load List Your Business image');
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