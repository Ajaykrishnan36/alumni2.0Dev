import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import uploadInlineImage from '@salesforce/apex/KenGroupFeedController.uploadInlineImage';

const MAX_LENGTH = 4000;

export default class KenGroupPostComposer extends LightningElement {
    @api isPosting = false;
    @api groupId;

    @track body = '';
    @track isExpanded = false;
    // Uploaded images, keyed by the preview URL that is sitting in the editor
    // right now. On submit each preview URL is swapped for sfdc://<docId>,
    // which is the only image reference Chatter will store.
    @track inlineImages = [];
    @track showPollModal = false;
    @track isUploading = false;
    @track commentsEnabled = true;

    // Allow the full default toolbar — no disabledCategories so B/I/U/S, list, align, link, etc. all show.
    enabledFormats = ['bold', 'italic', 'underline', 'strike',
        'list', 'indent', 'align', 'link', 'clean'];

    @api reset() {
        this.body = '';
        this.isExpanded = false;
        this.inlineImages = [];
        this.commentsEnabled = true;
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
        const used = [];
        const body = this.buildBody(used);
        const docIds = used.map(img => img.contentDocumentId);
        if (!text && docIds.length === 0) return;
        if (text.length > MAX_LENGTH) return;
        // The document Ids still go to Apex even though the images are inline:
        // they are what creates the ContentDocumentLink, without which other
        // members of the group have no access to the file.
        this.dispatchEvent(new CustomEvent('submit', {
            detail: { body, contentDocumentIds: docIds, commentsEnabled: this.commentsEnabled }
        }));
    }

    /**
     * Editor HTML with every uploaded image rewritten to its sfdc:// reference,
     * which is the only image form Chatter stores. Images that are not backed by
     * an upload (a paste that failed) are removed here, since Apex would strip
     * them anyway - dropping them explicitly lets us say so.
     *
     * @param collect receives the images that were actually used, so the caller
     *        can link their ContentDocuments to the post.
     */
    buildBody(collect) {
        const editor = this.template.querySelector('c-ken-rich-text-editor');
        if (!editor || !editor.resolveImages) return this.body || '';

        let dropped = 0;
        const html = editor.resolveImages(src => {
            const match = this.inlineImages.find(img => img.previewUrl === src);
            if (!match) {
                dropped++;
                return null;
            }
            if (collect.indexOf(match) === -1) collect.push(match);
            return `sfdc://${match.contentDocumentId}`;
        });

        if (dropped > 0) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Image not included',
                message: 'An image could not be uploaded and was left out. Add it again with the image button.',
                variant: 'warning'
            }));
        }
        return html;
    }

    // ─── Inline image handling ────────────────────────────────────────────

    handleImageSelect(event) {
        this.uploadImages(Array.from((event.detail && event.detail.files) || []));
    }

    async uploadImages(files) {
        if (!files || files.length === 0) return;
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
            return;
        }

        this.isUploading = true;
        let uploadedCount = 0;
        try {
            const editor = this.template.querySelector('c-ken-rich-text-editor');
            for (const file of files) {
                const base64 = await this.readAsBase64(file);
                const result = await uploadInlineImage({ fileName: file.name, base64Data: base64 });
                this.inlineImages = [...this.inlineImages, {
                    contentDocumentId: result.contentDocumentId,
                    previewUrl: result.previewUrl,
                    name: file.name
                }];
                if (editor && editor.insertImage) editor.insertImage(result.previewUrl, file.name);
                uploadedCount++;
            }
            if (uploadedCount > 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Image added',
                    message: `${uploadedCount} image${uploadedCount > 1 ? 's' : ''} added — hit Post to publish.`,
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

    // ─── Poll modal ───────────────────────────────────────────────────────

    // ─── Comments toggle ──────────────────────────────────────────────────

    handleToggleCommentsSetting() {
        this.commentsEnabled = !this.commentsEnabled;
    }

    get commentsToggleLabel() {
        return this.commentsEnabled ? 'Comments On' : 'Comments Off';
    }

    get commentsToggleClass() {
        return `pill-btn${this.commentsEnabled ? '' : ' is-off'}`;
    }

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

    get postDisabled() {
        const text = (this.plainText || '');
        if (this.isPosting || this.isUploading) return true;
        if (text.length > MAX_LENGTH) return true;
        // An image-only post is valid: plain text is empty but the body is not.
        return text.length === 0 && this.inlineImages.length === 0;
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