import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import uploadCategoryImage from '@salesforce/apex/KenFundraiseController.uploadCategoryImage';
import IMAGE_FIELD from '@salesforce/schema/Ken_Fundraise_Category__c.Image__c';

const MAX_BYTES = 2 * 1024 * 1024;
const FALLBACK_IMAGE =
    'data:image/svg+xml;charset=UTF-8,' +
    encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 140" width="200" height="140">' +
        '<rect width="200" height="140" fill="#F3F4F6"/>' +
        '<path d="M60 95 L85 65 L105 88 L125 60 L150 95 Z" fill="#CBD5E1"/>' +
        '<circle cx="75" cy="55" r="10" fill="#CBD5E1"/>' +
        '</svg>'
    );

export default class KenCategoryImageUploader extends LightningElement {
    @api recordId;
    isUploading = false;
    fileData = null;

    @wire(getRecord, { recordId: '$recordId', fields: [IMAGE_FIELD] })
    category;

    get previewUrl() {
        if (this.fileData) return this.fileData.base64;
        return getFieldValue(this.category.data, IMAGE_FIELD) || FALLBACK_IMAGE;
    }

    get isUploadDisabled() {
        return !this.fileData || this.isUploading;
    }

    get uploadButtonLabel() {
        return this.isUploading ? 'Uploading…' : 'Upload Image';
    }

    handleFileChange(event) {
        const fileInput = event.target;
        const file = fileInput.files[0];
        if (!file) return;

        if (!file.type || !file.type.startsWith('image/')) {
            this.showToast('Error', 'Only image files are allowed.', 'error');
            fileInput.value = null;
            return;
        }
        if (file.size > MAX_BYTES) {
            this.showToast('Error', 'File size exceeds the 2 MB limit.', 'error');
            fileInput.value = null;
            return;
        }

        const reader = new FileReader();
        reader.onload = () => {
            this.fileData = { fileName: file.name, base64: reader.result };
        };
        reader.readAsDataURL(file);
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleUpload() {
        if (!this.fileData) return;
        this.isUploading = true;
        try {
            await uploadCategoryImage({ categoryId: this.recordId, base64: this.fileData.base64 });
            this.showToast('Success', 'Category image updated.', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
            setTimeout(() => window.location.reload(), 1000);
        } catch (error) {
            this.showToast('Error', error?.body?.message || 'Failed to upload image.', 'error');
        } finally {
            this.isUploading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}