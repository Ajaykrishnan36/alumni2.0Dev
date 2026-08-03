import { LightningElement, api, track } from 'lwc';

export default class KenPhotoCard extends LightningElement {
    @api photo;
    @track showMenu = false;
    @track thumbnailFailed = false;

    constructor() {
        super();
        this.boundHandleClickOutside = this.handleClickOutside.bind(this);
        this.boundHandleProfileImageError = this.handleProfileImageError.bind(this);
    }

    renderedCallback() {
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

    get thumbnailUrl() {
        return this.photo?.thumbnailUrl || '';
    }

    get showThumbnail() {
        return !this.isImage && !!this.thumbnailUrl && !this.thumbnailFailed;
    }

    get showPlaceholder() {
        return !this.isImage && !this.showThumbnail;
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
        if (
            event.target.closest('.menu-button') ||
            event.target.closest('.menu-dropdown') ||
            event.target.closest('.profile-overlay')
        ) {
            return;
        }
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

    handleThumbnailError() {
        this.thumbnailFailed = true;
    }
}