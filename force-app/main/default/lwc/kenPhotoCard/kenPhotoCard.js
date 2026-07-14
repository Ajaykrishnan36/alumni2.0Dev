import { LightningElement, api, track } from 'lwc';

export default class KenPhotoCard extends LightningElement {
    @api photo;
    @track showMenu = false;

    constructor() {
        super();
        this.boundHandleClickOutside = this.handleClickOutside.bind(this);
        this.boundHandleProfileImageError = this.handleProfileImageError.bind(this);
    }

    renderedCallback() {
        // Attach error handler to profile image after render
        const profileImage = this.template.querySelector('[data-profile-image="true"]');
        if (profileImage && !profileImage.hasAttribute('data-error-handler-attached')) {
            profileImage.addEventListener('error', this.boundHandleProfileImageError);
            profileImage.setAttribute('data-error-handler-attached', 'true');
        }
    }

    connectedCallback() {
        document.addEventListener('click', this.boundHandleClickOutside);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.boundHandleClickOutside);
        // Remove error handler from profile image
        const profileImage = this.template.querySelector('[data-profile-image="true"]');
        if (profileImage) {
            profileImage.removeEventListener('error', this.boundHandleProfileImageError);
        }
    }

    handleClickOutside(event) {
        if (this.showMenu && !this.template.contains(event.target)) {
            this.showMenu = false;
        }
    }

    get photoImageUrl() {
        return this.photo?.imageUrl || '';
    }

    get profileImageUrl() {
        return this.photo?.profileImageUrl || '';
    }

    get personName() {
        return this.photo?.personName || '';
    }

    get isImage() {
        return this.photo?.isImage !== false;
    }

    get fileName() {
        return this.photo?.fileName || 'File';
    }

    get isOwner() {
        return !!this.photo?.isOwner;
    }

    handleMenuClick(event) {
        event.stopPropagation();
        this.showMenu = !this.showMenu;
    }

    handleMenuAction(event) {
        const action = event.currentTarget.dataset.action;
        this.showMenu = false;
        this.dispatchEvent(
            new CustomEvent('menuselect', {
                detail: {
                    photoId: this.photo.id,
                    action: action
                }
            })
        );
    }

    handleCardClick(event) {
        // Don't trigger if clicking on menu button, menu dropdown, or profile overlay
        if (
            event.target.closest('.menu-button') ||
            event.target.closest('.menu-dropdown') ||
            event.target.closest('.profile-overlay')
        ) {
            return;
        }
        // Handle photo click to open full view or details
        this.dispatchEvent(
            new CustomEvent('photoclick', {
                detail: {
                    photoId: this.photo.id
                }
            })
        );
    }

    handleOverlayClick(event) {
        event.stopPropagation();
        // Handle profile click
        this.dispatchEvent(
            new CustomEvent('profileclick', {
                detail: {
                    personName: this.personName
                }
            })
        );
    }

    handleProfileImageError(event) {
        event.target.src = '/assets/images/default-profile.png';
    }
}