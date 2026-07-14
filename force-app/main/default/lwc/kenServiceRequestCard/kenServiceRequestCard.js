import { LightningElement, api } from 'lwc';
import getColors from '@salesforce/apex/KenSnSColorController.getColors';

const DEFAULT_CHIPS = ['Academics', 'Housing', 'Finance'];

export default class KenServiceRequestCard extends LightningElement {
    @api chips = DEFAULT_CHIPS;

    connectedCallback() {
        getColors().then(colors => {
            this.applyOrganizationTheme(colors);
        }).catch(() => {
            console.log('Error getting colors');
        });
    }

    applyOrganizationTheme(colors) {
        if (!this.template?.host || !colors) return;
        const primary = colors.primary || colors.primaryColor;
        const secondary = colors.secondary || colors.secondaryColor;
        if (primary && typeof primary === 'string') {
            this.template.host.style.setProperty('--primary-color', primary);
        }
        if (secondary && typeof secondary === 'string') {
            this.template.host.style.setProperty('--secondary-color', secondary);
        }
    }

    handleCardClick() {
        this.dispatchEvent(new CustomEvent('servicerequestclick'));
    }
}