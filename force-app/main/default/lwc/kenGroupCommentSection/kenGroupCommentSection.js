import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getComments from '@salesforce/apex/KenGroupFeedController.getComments';
import addComment from '@salesforce/apex/KenGroupFeedController.addComment';
import deleteComment from '@salesforce/apex/KenGroupFeedController.deleteComment';

const PAGE_SIZE = 5;
const MAX_LENGTH = 4000;

export default class KenGroupCommentSection extends LightningElement {
    @api feedItemId;

    @track comments = [];
    @track isLoading = false;
    @track isSubmitting = false;
    @track hasMore = false;
    @track offset = 0;
    @track newCommentBody = '';

    connectedCallback() {
        this.loadComments(true);
    }

    loadComments(reset) {
        if (!this.feedItemId) return;
        const nextOffset = reset ? 0 : this.offset;
        this.isLoading = true;
        getComments({ feedItemId: this.feedItemId, offset: nextOffset, pageSize: PAGE_SIZE })
            .then(page => {
                const incoming = page.comments || [];
                this.comments = reset ? incoming : [...this.comments, ...incoming];
                this.offset = nextOffset + incoming.length;
                this.hasMore = page.hasMore === true;
            })
            .catch(err => {
                this.toast('Could not load comments', this.extractError(err), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleLoadMore() {
        if (!this.isLoading && this.hasMore) this.loadComments(false);
    }

    handleInput(event) {
        this.newCommentBody = event.target.value || '';
    }

    handleSubmit() {
        const trimmed = (this.newCommentBody || '').trim();
        if (!trimmed || this.isSubmitting) return;
        if (trimmed.length > MAX_LENGTH) return;

        this.isSubmitting = true;
        addComment({ feedItemId: this.feedItemId, body: trimmed })
            .then(() => {
                this.newCommentBody = '';
                this.loadComments(true);
            })
            .catch(err => {
                this.toast('Could not comment', this.extractError(err), 'error');
            })
            .finally(() => {
                this.isSubmitting = false;
            });
    }

    handleDelete(event) {
        const commentId = event.currentTarget.dataset.id;
        if (!commentId) return;
        deleteComment({ commentId })
            .then(() => {
                this.comments = this.comments.filter(c => c.commentId !== commentId);
            })
            .catch(err => {
                this.toast('Could not delete', this.extractError(err), 'error');
            });
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSubmit();
        }
    }

    get hasComments()    { return this.comments && this.comments.length > 0; }
    get submitDisabled() {
        const trimmed = (this.newCommentBody || '').trim();
        return this.isSubmitting || trimmed.length === 0 || trimmed.length > MAX_LENGTH;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }
}