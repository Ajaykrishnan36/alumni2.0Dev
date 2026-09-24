import { LightningElement, api, track } from 'lwc';
import FilePreviewPlaceholder from '@salesforce/resourceUrl/FilePreviewPlaceholder';
import defaultProfileImage from '@salesforce/resourceUrl/defaultProfileImage';

const DEFAULT_AVATAR = defaultProfileImage;

export default class KenPhotoCard extends LightningElement {
    @api photo;
    @track showMenu = false;
    @track thumbnailFailed = false;
    @track imageFailed = false;

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

    // The absolute ContentDistribution link wins over the shepherd URL: the
    // latter is root-relative and does not resolve inside the Experience Cloud
    // site, so it comes back as a broken image in the portal.
    get photoImageUrl() {
        return this.photo?.publicUrl || this.photo?.imageUrl || '';
    }

    // Document art, NOT the album placeholder - that one reads "No files yet",
    // which is plainly wrong on a card where the file is sitting right there.
    get placeholderImageUrl() {
        return FilePreviewPlaceholder;
    }

    // Only attempt an <img> when there is something to point it at and the load
    // has not already failed; otherwise fall through to the placeholder.
    get showImage() {
        return this.isImage && !!this.photoImageUrl && !this.imageFailed;
    }

    handleImageError() {
        this.imageFailed = true;
    }

    // Falls back to the same silhouette the album cards use. Returning '' left
    // an empty <img> behind, which rendered as a blank white circle.
    get profileImageUrl() {
        return this.photo?.profileImageUrl || DEFAULT_AVATAR;
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

    // Catches both a document with no usable thumbnail and an image whose URL
    // would not load, so the grid never shows a broken frame.
    get showPlaceholder() {
        return !this.showImage && !this.showThumbnail;
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
        event.target.src = DEFAULT_AVATAR;
    }

    handleThumbnailError() {
        this.thumbnailFailed = true;
    }
}