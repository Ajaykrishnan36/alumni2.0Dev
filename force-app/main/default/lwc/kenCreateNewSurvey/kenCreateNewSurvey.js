import { LightningElement } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenCreateNewSurvey extends LightningElement {
    handleCardClick() {
        const createSurveyEvent = new CustomEvent('createsurveyclick', {
            bubbles: true,
            composed: true
        });
        this.dispatchEvent(createSurveyEvent);
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