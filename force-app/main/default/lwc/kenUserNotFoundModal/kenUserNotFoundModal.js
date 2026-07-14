import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenUserNotFoundModal extends LightningElement {
    @api showModal = false;
    @api userName = '';
    @api batch = '';
    @api profileImage = '';

    @track displayImage = '';

    connectedCallback() {
        this.displayImage = this.profileImage || '/assets/images/default-profile.png';
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    get profileImageUrl() {
        return this.displayImage || '/assets/images/default-profile.png';
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleOverlayClick(event) {
        if (event.target.classList.contains('modal-overlay')) {
            this.handleClose();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleImageError() {
        this.displayImage = '/assets/images/default-profile.png';
    }

    handleCopyLink() {
        // Generate invite link
        const inviteLink = `${window.location.origin}/alumni/invite?user=${encodeURIComponent(this.userName)}`;
        
        // Copy to clipboard
        navigator.clipboard.writeText(inviteLink).then(() => {
            // Show success message (you can add a toast notification here)
            console.log('Link copied to clipboard');
        }).catch(err => {
            console.error('Failed to copy link:', err);
        });
    }
}