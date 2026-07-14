import { LightningElement, api, track } from 'lwc';

export default class KenPhotoUploadPage extends LightningElement {
    @api isSaving = false;
    @track uploadedImages = [];

    get hasImages() {
        return this.uploadedImages.length > 0;
    }

    get hasNoImages() {
        return !this.hasImages;
    }

    get isPostDisabled() {
        return this.hasNoImages || this.isSaving;
    }

    get postButtonLabel() {
        return this.isSaving ? 'Posting...' : 'Post';
    }

    handleUploadClick() {
        const fileInput = this.template.querySelector('[data-file-input="true"]');
        if (fileInput) {
            fileInput.click();
        }
    }

    handleChooseFileClick(event) {
        // The "Choose File" button sits inside the clickable drag-drop area, which has
        // its own onclick calling this same file picker — without stopping propagation
        // here, the click bubbles up and opens the OS file dialog a second time.
        event.stopPropagation();
        this.handleUploadClick();
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

        return true;
    }

    addImage(file) {
        const reader = new FileReader();
        reader.onload = (e) => {
            const imageData = {
                id: String(Date.now() + Math.random()),
                file: file,
                preview: e.target.result,
                name: file.name,
                isImage: file.type.startsWith('image/')
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

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleCancel() {
        this.resetForm();
        this.dispatchEvent(new CustomEvent('back'));
    }

    handlePost() {
        if (this.uploadedImages.length === 0 || this.isSaving) {
            return;
        }

        // The parent owns the actual upload + navigation: it closes this page only once
        // the upload genuinely succeeds, so the user never sees a premature "done" state
        // that makes it look like the upload silently failed and needs retrying.
        this.dispatchEvent(
            new CustomEvent('post', {
                detail: { images: this.uploadedImages }
            })
        );
    }

    resetForm() {
        this.uploadedImages = [];
        const fileInput = this.template.querySelector('[data-file-input="true"]');
        if (fileInput) {
            fileInput.value = '';
        }
    }

    showError(message) {
        console.error(message);
        alert(message);
    }
}