import { LightningElement, api } from 'lwc';
import defaultProfileImage from '@salesforce/resourceUrl/AlumniAlt';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenConnectionRequestItem extends LightningElement {
    @api name;
    @api dateTime;
    @api profileImage;
    @api isOnline = false;
    @api requestId;

    get displayImage() {
        return this.profileImage || defaultProfileImage;
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

    handleAccept() {
        this.dispatchEvent(new CustomEvent('accept', {
            detail: { id: this.requestId }
        }));
    }

    handleDecline() {
        this.dispatchEvent(new CustomEvent('decline', {
            detail: { id: this.requestId }
        }));
    }

    handleAvatarError(event) {
        if (event && event.target) {
            event.target.src = defaultProfileImage;
        }
    }
}