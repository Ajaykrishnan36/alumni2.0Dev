import { LightningElement, api } from 'lwc';
import uploadAndNotifyCase from '@salesforce/apex/KenFileUploadController.uploadAndNotifyCase';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class KenCaseFileUploader extends LightningElement {
    @api recordId;
    selectedFile;
    fileName = '';

    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;

        this.selectedFile = file;
        this.fileName = file.name;
    }

    removeSelectedFile() {
        this.selectedFile = null;
        this.fileName = '';
    }

    async handleUpload() {
        try {
            if (!this.selectedFile) {
                this.showToast('Error', 'Please upload a file first.', 'error');
                return;
            }

            const base64 = await this.readFileAsBase64(this.selectedFile);

            await uploadAndNotifyCase({
                recordId: this.recordId,
                fileName: this.fileName,
                base64Content: base64
            });

            this.showToast('Success', 'File uploaded and email sent.', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (err) {
            this.showToast('Error', err.body?.message || err.message, 'error');
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}