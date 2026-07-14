import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const URL_PATTERN = /^https?:\/\/[^\s]+$/;

export default class KenCreateAlbumModal extends LightningElement {
    @api showModal = false;
    @track mode = 'name'; // 'name' or 'link'
    @track albumName = '';
    @track driveLink = '';

    get isNameMode() {
        return this.mode === 'name';
    }

    get isLinkMode() {
        return this.mode === 'link';
    }

    get nameTabClass() {
        return this.isNameMode ? 'mode-tab selected' : 'mode-tab';
    }

    get linkTabClass() {
        return this.isLinkMode ? 'mode-tab selected' : 'mode-tab';
    }

    get isLinkValid() {
        return URL_PATTERN.test(this.driveLink.trim());
    }

    get isFormValid() {
        return this.isNameMode
            ? this.albumName.trim().length > 0
            : this.isLinkValid;
    }

    get isFormInvalid() {
        return !this.isFormValid;
    }

    get showLinkError() {
        return this.isLinkMode && this.driveLink.trim().length > 0 && !this.isLinkValid;
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

    handleModeSelect(event) {
        this.mode = event.currentTarget.dataset.mode;
    }

    handleAlbumNameChange(event) {
        this.albumName = event.target.value;
    }

    handleDriveLinkChange(event) {
        this.driveLink = event.target.value;
    }

    handleCancel() {
        this.resetForm();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCreate() {
        if (!this.isFormValid) {
            return;
        }

        const detail = this.isNameMode
            ? { name: this.albumName.trim() }
            : { externalLink: this.driveLink.trim() };

        this.dispatchEvent(new CustomEvent('create', { detail }));

        this.resetForm();
    }

    handleOverlayClick(event) {
        if (event.target.classList.contains('modal-overlay')) {
            this.handleCancel();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    resetForm() {
        this.mode = 'name';
        this.albumName = '';
        this.driveLink = '';
    }
}