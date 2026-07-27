import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenEducationCard extends LightningElement {
    @api recordId;
    @api degree;
    @api institution;
    @api duration;
    @api score;
    @api logo;
    @api isMyProfile = false;
    showDeleteConfirm = false;

    handleEdit() {
        this.dispatchEvent(new CustomEvent('edit', { detail: { id: this.recordId }, bubbles: true, composed: true }));
    }

    handleDelete() {
        this.showDeleteConfirm = true;
    }

    handleConfirmDelete() {
        this.showDeleteConfirm = false;
        this.dispatchEvent(new CustomEvent('delete', { detail: { id: this.recordId }, bubbles: true, composed: true }));
    }

    handleCancelDelete() {
        this.showDeleteConfirm = false;
    }

    get displayLogo() {
        return this.logo || '/assets/images/default-education-logo.png';
    }

    get metaLine() {
        const duration = (this.duration || '').trim();
        const score = (this.score || '').toString().trim();
        if (duration && score) return `${duration} | ${score}`;
        return duration || score || '';
    }

    handleLogoError(event) {
        if (event && event.target) {
            event.target.style.display = 'none';
        }
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