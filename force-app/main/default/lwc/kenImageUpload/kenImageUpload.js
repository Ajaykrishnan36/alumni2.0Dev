import { LightningElement, api } from 'lwc';
import uploadImage from '@salesforce/apex/KenFileUploadController.uploadImage';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

/**
 * @description Reusable record-action component that lets a user pick an image,
 *              converts it to a public URL and stores that URL on the current
 *              record. Object-agnostic: the record's Id and object API name are
 *              injected by the RecordAction framework, and the target field is
 *              resolved per object in KenFileUploadController.
 */
export default class KenImageUpload extends LightningElement {
    @api recordId;
    @api objectApiName;

    fileData = null;
    isUploading = false;

    get isUploadDisabled() {
        return !this.fileData || this.isUploading;
    }

    handleFileChange(event) {
        const fileInput = event.target;
        const file = fileInput.files[0];
        if (!file) {
            this.fileData = null;
            return;
        }

        if (!file.type || !file.type.startsWith('image/')) {
            this.showToast('Error', 'Only image files are allowed.', 'error');
            fileInput.value = null;
            this.fileData = null;
            return;
        }

        const maxBytes = 2 * 1024 * 1024;
        if (file.size > maxBytes) {
            this.showToast('Error', 'File size exceeds the 2 MB limit.', 'error');
            fileInput.value = null;
            this.fileData = null;
            return;
        }

        const reader = new FileReader();
        reader.onload = () => {
            this.fileData = {
                fileName: file.name,
                base64: reader.result,
                size: file.size
            };
        };
        reader.readAsDataURL(file);
    }

    handleRemoveFile() {
        this.fileData = null;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleUpload() {
        if (this.fileData == null) {
            this.showToast('Error', 'Please select a file to upload.', 'error');
            return;
        }

        this.isUploading = true;
        try {
            await uploadImage({
                recordId: this.recordId,
                objectName: this.objectApiName,
                fileName: this.fileData.fileName,
                base64Data: this.fileData.base64
            });
            this.showToast('Success', 'Image uploaded successfully!', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
            setTimeout(() => {
                window.location.reload();
            }, 1000);
        } catch (error) {
            const message =
                error && error.body && error.body.message
                    ? error.body.message
                    : 'An error occurred while uploading the image.';
            this.showToast('Error', message, 'error');
        } finally {
            this.isUploading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}