import { LightningElement, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenCreateNewSurvey extends LightningElement {
    @track canCreateSurvey = false;

    handleCardClick() {
        const createSurveyEvent = new CustomEvent('createsurveyclick', {
            bubbles: true
        });
        this.dispatchEvent(createSurveyEvent);
    }
    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
            this.canCreateSurvey = color?.createSurvey !== false;
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
}