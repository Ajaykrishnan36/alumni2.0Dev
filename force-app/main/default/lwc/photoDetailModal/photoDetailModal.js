import { LightningElement, api, track } from 'lwc';

export default class PhotoDetailModal extends LightningElement {
    @api showModal = false;
    @api photo = null;
    @api allPhotos = [];
    @track currentPhotoIndex = 0;

    constructor() {
        super();
        this.boundHandleProfileImageError = this.handleProfileImageError.bind(this);
        this.boundHandleKeyDown = this.handleKeyDown.bind(this);
    }

    connectedCallback() {
        if (this.showModal) {
            document.addEventListener('keydown', this.boundHandleKeyDown);
        }
    }

    disconnectedCallback() {
        document.removeEventListener('keydown', this.boundHandleKeyDown);
    }

    renderedCallback() {
        // Update currentPhotoIndex when prop changes
        if (this.allPhotos && this.allPhotos.length > 0) {
            const index = this.allPhotos.findIndex(p => p.id === this.photo?.id);
            if (index !== -1 && index !== this.currentPhotoIndex) {
                this.currentPhotoIndex = index;
            }
        }
    }

    renderedCallback() {
        // Attach error handler to profile image after render
        const profileImage = this.template.querySelector('[data-profile-image="true"]');
        if (profileImage && !profileImage.hasAttribute('data-error-handler-attached')) {
            profileImage.addEventListener('error', this.boundHandleProfileImageError);
            profileImage.setAttribute('data-error-handler-attached', 'true');
        }
        
        // Update currentPhotoIndex when prop changes
        if (this.allPhotos && this.allPhotos.length > 0 && this.photo) {
            const index = this.allPhotos.findIndex(p => p.id === this.photo.id);
            if (index !== -1 && index !== this.currentPhotoIndex) {
                this.currentPhotoIndex = index;
            }
        }
    }

    get currentPhoto() {
        if (this.allPhotos && this.allPhotos.length > 0 && this.currentPhotoIndex >= 0) {
            return this.allPhotos[this.currentPhotoIndex];
        }
        return this.photo;
    }

    get photoImageUrl() {
        return this.currentPhoto?.imageUrl || '';
    }

    get profileImageUrl() {
        return this.currentPhoto?.profileImageUrl || '/assets/images/default-profile.png';
    }

    get personName() {
        return this.currentPhoto?.personName || '';
    }

    get photoTitle() {
        return this.currentPhoto?.title || 'Reunited with the ones who made the best memories.';
    }

    get photoDescription() {
        return this.currentPhoto?.description || 'Back together with the ones who made the best memories — some bonds never fade.';
    }

    get location() {
        return this.currentPhoto?.location || '';
    }

    get hasLocation() {
        return !!this.location;
    }

    get likesCount() {
        return this.currentPhoto?.likesCount || 0;
    }

    get hasPrevious() {
        return this.allPhotos && this.allPhotos.length > 0 && this.currentPhotoIndex > 0;
    }

    get hasNext() {
        return this.allPhotos && this.allPhotos.length > 0 && this.currentPhotoIndex < this.allPhotos.length - 1;
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

    handlePrevious() {
        if (this.hasPrevious) {
            this.currentPhotoIndex = this.currentPhotoIndex - 1;
            this.dispatchEvent(
                new CustomEvent('photochange', {
                    detail: {
                        index: this.currentPhotoIndex,
                        photo: this.allPhotos[this.currentPhotoIndex]
                    }
                })
            );
        }
    }

    handleNext() {
        if (this.hasNext) {
            this.currentPhotoIndex = this.currentPhotoIndex + 1;
            this.dispatchEvent(
                new CustomEvent('photochange', {
                    detail: {
                        index: this.currentPhotoIndex,
                        photo: this.allPhotos[this.currentPhotoIndex]
                    }
                })
            );
        }
    }

    handleKeyDown(event) {
        if (this.showModal) {
            if (event.key === 'Escape') {
                this.handleClose();
            } else if (event.key === 'ArrowLeft' && this.hasPrevious) {
                this.handlePrevious();
            } else if (event.key === 'ArrowRight' && this.hasNext) {
                this.handleNext();
            }
        }
    }

    handleProfileImageError(event) {
        event.target.src = '/assets/images/default-profile.png';
    }
}