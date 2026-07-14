import { LightningElement, api } from 'lwc';

export default class KenExperienceCard extends LightningElement {
    @api recordId;
    @api position;
    @api company;
    @api employmentType;
    @api location;
    @api workType;
    @api duration;
    @api companyLogo;
    @api description;
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
        return this.companyLogo || '/assets/images/default-company-logo.png';
    }

    handleLogoError(event) {
        if (event && event.target) {
            event.target.style.display = 'none';
        }
    }
}