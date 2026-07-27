import { LightningElement } from 'lwc';
import RegistrationSuccessGif from '@salesforce/resourceUrl/RegistrationSuccessGif';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenSuccessPage extends LightningElement {
    registrationSuccessGifUrl = RegistrationSuccessGif;

    handleGotIt() {
        // Handle navigation or event dispatch
        // You can dispatch a custom event or navigate to another page
        this.dispatchEvent(new CustomEvent('complete', { bubbles: true, composed: true }));
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