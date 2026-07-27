import { LightningElement, api, track } from 'lwc';

export default class KenPhotoUploadModal extends LightningElement {
    @api showModal = false;
    @api preselectedAlbumId = null;
    @api providedAlbumOptions = [];
    @track uploadedImages = [];
    @track selectedAlbum = '';
    @track caption = '';
    @track location = '';
    @track taggedAlumni = '';

    get albumOptions() {
        if (this.providedAlbumOptions && this.providedAlbumOptions.length > 0) {
            return this.providedAlbumOptions;
        }
        return [
            { label: 'Select', value: '' },
            { label: 'Event Photos', value: 'event' },
            { label: 'Campus Life', value: 'campus' },
            { label: 'Reunion', value: 'reunion' },
            { label: 'Sports', value: 'sports' }
        ];
    }

    get albumOptionsWithCreate() {
        const options = [...this.albumOptions];
        // Add "Create a new folder" option at the beginning (after Select)
        if (options.length > 0 && options[0].value === '') {
            options.splice(1, 0, { label: '+ Create a new folder', value: 'create_new' });
        } else {
            options.unshift({ label: '+ Create a new folder', value: 'create_new' });
        }
        return options;
    }

    renderedCallback() {
        // Set preselected album if provided
        if (this.preselectedAlbumId && !this.selectedAlbum) {
            this.selectedAlbum = this.preselectedAlbumId;
        }
    }

    get hasImages() {
        return this.uploadedImages.length > 0;
    }

    get hasNoImages() {
        return !this.hasImages;
    }

    handleUploadClick() {
        const fileInput = this.template.querySelector('[data-file-input="true"]');
        if (fileInput) {
            fileInput.click();
        }
    }

    handleFileSelect(event) {
        const files = Array.from(event.target.files);
        if (files.length > 0) {
            this.processFiles(files);
        }
        // Reset input to allow selecting same file again
        event.target.value = '';
    }

    processFiles(files) {
        files.forEach(file => {
            if (this.validateFile(file)) {
                this.addImage(file);
            }
        });
    }

    validateFile(file) {
        // Validate file size (16 MB = 16 * 1024 * 1024 bytes)
        const maxSize = 16 * 1024 * 1024;
        if (file.size > maxSize) {
            this.showError(`${file.name}: File size exceeds 16 MB limit`);
            return false;
        }

        // Validate file type
        const validTypes = ['image/jpeg', 'image/png', 'image/jpg'];
        if (!validTypes.includes(file.type)) {
            this.showError(`${file.name}: Invalid file type. Please upload JPEG, PNG, or JPG files only.`);
            return false;
        }

        return true;
    }

    addImage(file) {
        const reader = new FileReader();
        reader.onload = (e) => {
            const imageData = {
                id: String(Date.now() + Math.random()),
                file: file,
                preview: e.target.result,
                name: file.name
            };
            this.uploadedImages = [...this.uploadedImages, imageData];
        };
        reader.readAsDataURL(file);
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const uploadArea = this.template.querySelector('[data-upload-area="true"]');
        if (uploadArea) {
            uploadArea.classList.remove('drag-over');
        }

        const files = Array.from(event.dataTransfer.files);
        if (files.length > 0) {
            this.processFiles(files);
        }
    }

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        const uploadArea = this.template.querySelector('[data-upload-area="true"]');
        if (uploadArea) {
            uploadArea.classList.add('drag-over');
        }
    }

    handleDragLeave(event) {
        event.preventDefault();
        event.stopPropagation();
        const uploadArea = this.template.querySelector('[data-upload-area="true"]');
        if (uploadArea) {
            uploadArea.classList.remove('drag-over');
        }
    }

    handleRemoveImage(event) {
        const imageId = event.currentTarget.dataset.imageId;
        this.uploadedImages = this.uploadedImages.filter(img => img.id !== imageId);
    }

    handleAlbumChange(event) {
        const value = event.detail.value;
        if (value === 'create_new') {
            // Dispatch event to create new album
            this.dispatchEvent(new CustomEvent('createnewalbum'));
            // Reset selection
            this.selectedAlbum = '';
        } else {
            this.selectedAlbum = value;
        }
    }

    handleCaptionChange(event) {
        this.caption = event.target.value;
    }

    handleLocationChange(event) {
        this.location = event.target.value;
    }

    handleTagChange(event) {
        this.taggedAlumni = event.target.value;
    }

    handleCancel() {
        this.resetForm();
        this.dispatchEvent(new CustomEvent('close'));
    }

    handlePost() {
        if (this.uploadedImages.length === 0) {
            return;
        }

        const photoData = {
            images: this.uploadedImages,
            album: this.selectedAlbum,
            caption: this.caption,
            location: this.location,
            taggedAlumni: this.taggedAlumni
        };

        this.dispatchEvent(
            new CustomEvent('post', {
                detail: photoData
            })
        );

        this.resetForm();
    }

    handleOverlayClick(event) {
        // Close modal when clicking outside
        if (event.target.classList.contains('modal-overlay')) {
            this.handleCancel();
        }
    }

    handleModalClick(event) {
        // Prevent closing when clicking inside modal
        event.stopPropagation();
    }

    resetForm() {
        this.uploadedImages = [];
        this.selectedAlbum = '';
        this.caption = '';
        this.location = '';
        this.taggedAlumni = '';
        const fileInput = this.template.querySelector('[data-file-input="true"]');
        if (fileInput) {
            fileInput.value = '';
        }
    }

    showError(message) {
        // You can implement toast notifications here
        console.error(message);
        // For now, using alert - replace with proper toast notification
        alert(message);
    }
}