import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import uploadAttachment from '@salesforce/apex/KenGroupFeedController.uploadAttachment';

const MAX_LENGTH = 4000;

export default class KenGroupPostComposer extends LightningElement {
    @api isPosting = false;
    @api groupId;

    @track body = '';
    @track isExpanded = false;
    @track attachments = [];
    @track showPollModal = false;
    @track isUploading = false;

    // Allow the full default toolbar — no disabledCategories so B/I/U/S, list, align, link, etc. all show.
    enabledFormats = ['bold', 'italic', 'underline', 'strike',
        'list', 'indent', 'align', 'link', 'clean'];

    @api reset() {
        this.body = '';
        this.isExpanded = false;
        this.attachments = [];
    }

    handleRichTextChange(event) {
        this.body = event.detail.value || '';
    }

    handleFocus() {
        this.isExpanded = true;
    }

    handleCancel() {
        this.reset();
    }

    handleSubmit() {
        const text = (this.plainText || '').trim();
        const docIds = this.attachments.map(a => a.contentDocumentId);
        if (!text && docIds.length === 0) return;
        if (text.length > MAX_LENGTH) return;
        this.dispatchEvent(new CustomEvent('submit', {
            detail: { body: this.body, contentDocumentIds: docIds }
        }));
    }

    // ─── Attachment handling (custom button + hidden file input) ──────────

    handleClickAttach() {
        this.isExpanded = true;
        const input = this.template.querySelector('input.hidden-file-input');
        if (input) input.click();
    }

    async handleFileChange(event) {
        const files = Array.from(event.target.files || []);
        if (files.length === 0) return;
        this.isExpanded = true;

        const MAX_BYTES = 4 * 1024 * 1024; // 4 MB — base64 + Apex AuraEnabled payload cap
        const tooBig = files.find(f => f.size > MAX_BYTES);
        if (tooBig) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'File too large',
                message: `${tooBig.name} is ${(tooBig.size / 1024 / 1024).toFixed(1)} MB. Max is 4 MB.`,
                variant: 'error',
                mode: 'sticky'
            }));
            event.target.value = '';
            return;
        }

        this.isUploading = true;
        let uploadedCount = 0;
        try {
            for (const file of files) {
                const base64 = await this.readAsBase64(file);
                const documentId = await uploadAttachment({ fileName: file.name, base64Data: base64 });
                this.attachments = [...this.attachments, {
                    contentDocumentId: documentId,
                    name: file.name
                }];
                uploadedCount++;
            }
            if (uploadedCount > 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Image attached',
                    message: `${uploadedCount} image${uploadedCount > 1 ? 's' : ''} ready — hit Post to publish.`,
                    variant: 'success'
                }));
            }
        } catch (err) {
            // Show the real error so we can diagnose — Apex DML failures, permission errors, etc.
            const msg = this.extractError(err);
            // eslint-disable-next-line no-console
            console.error('[KenGroupPostComposer] upload failed', err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Upload failed',
                message: msg,
                variant: 'error',
                mode: 'sticky'
            }));
        } finally {
            this.isUploading = false;
            event.target.value = '';
        }
    }

    readAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    handleRemoveAttachment(event) {
        const id = event.currentTarget.dataset.id;
        this.attachments = this.attachments.filter(a => a.contentDocumentId !== id);
    }

    // ─── Poll modal ───────────────────────────────────────────────────────

    handleOpenPoll() {
        this.showPollModal = true;
        this.isExpanded = true;
    }

    handleClosePoll() {
        this.showPollModal = false;
    }

    handlePollCreated() {
        this.showPollModal = false;
        this.reset();
        this.dispatchEvent(new CustomEvent('pollcreated'));
    }

    // ─── Derived state ────────────────────────────────────────────────────

    get plainText() {
        if (!this.body) return '';
        return this.body.replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').trim();
    }

    get charCount()    { return (this.plainText || '').length; }
    get charLimit()    { return MAX_LENGTH; }
    get counterLabel() { return `${this.charCount}/${this.charLimit}`; }
    get hasAttachments() { return this.attachments && this.attachments.length > 0; }

    get postDisabled() {
        const text = (this.plainText || '');
        if (this.isPosting || this.isUploading) return true;
        if (text.length > MAX_LENGTH) return true;
        return text.length === 0 && this.attachments.length === 0;
    }

    get composerClass() {
        return `composer${this.isExpanded ? ' is-expanded' : ''}`;
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }
}