import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenEditAlbumLinkModal extends LightningElement {
    @api showModal = false;
    @track nameValue = '';

    _album;

    @api
    get album() {
        return this._album;
    }
    set album(value) {
        this._album = value;
        this.nameValue = value?.name || '';
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

    get isSaveDisabled() {
        return this.nameValue.trim().length === 0;
    }

    handleNameChange(event) {
        this.nameValue = event.target.value;
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleSave() {
        if (this.isSaveDisabled) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('save', {
                detail: {
                    albumId: this.album?.id,
                    name: this.nameValue.trim(),
                    externalLink: this.album?.externalLink || ''
                }
            })
        );
    }

    handleOverlayClick(event) {
        if (event.target.classList.contains('modal-overlay')) {
            this.handleCancel();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }
}