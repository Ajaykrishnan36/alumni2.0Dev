import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFeed from '@salesforce/apex/KenGroupFeedController.getFeed';
import createPost from '@salesforce/apex/KenGroupFeedController.createPost';
import createPostWithAttachments from '@salesforce/apex/KenGroupFeedController.createPostWithAttachments';
import deletePost from '@salesforce/apex/KenGroupFeedController.deletePost';

const PAGE_SIZE = 10;

export default class KenGroupFeed extends LightningElement {
    @api groupId;
    @api recordId;       // populated by Lightning Record Page (internal Salesforce context)
    @api isMember = false;
    @api forceMember = false;

    @track posts = [];
    @track isLoading = false;
    @track isPosting = false;
    @track hasMore = false;
    @track offset = 0;
    @track errorMessage = '';

    _loadedFor = null;

    get effectiveGroupId() { return this.groupId || this.recordId; }

    get canPost() {
        if (this.forceMember) return true;
        if (this.recordId && !this.groupId) return true; // internal record page context
        return this.isMember;
    }

    connectedCallback() {
        if (this.effectiveGroupId) this.loadFeed(true);
    }

    renderedCallback() {
        const id = this.effectiveGroupId;
        if (id && this._loadedFor !== id) {
            this._loadedFor = id;
            this.loadFeed(true);
        }
    }

    @api refresh() {
        this.loadFeed(true);
    }

    loadFeed(reset) {
        const id = this.effectiveGroupId;
        if (!id) return;
        const nextOffset = reset ? 0 : this.offset;
        this.isLoading = true;
        this.errorMessage = '';
        getFeed({ groupId: id, offset: nextOffset, pageSize: PAGE_SIZE })
            .then(page => {
                const incoming = page.posts || [];
                this.posts = reset ? incoming : [...this.posts, ...incoming];
                this.offset = nextOffset + incoming.length;
                this.hasMore = page.hasMore === true;
            })
            .catch(err => {
                this.errorMessage = this.extractError(err);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleLoadMore() {
        if (!this.isLoading && this.hasMore) this.loadFeed(false);
    }

    handleSubmit(event) {
        const detail = event.detail || {};
        const body = detail.body || '';
        const contentDocumentIds = detail.contentDocumentIds || [];
        const id = this.effectiveGroupId;
        if (!body.trim() && contentDocumentIds.length === 0) return;
        if (this.isPosting || !id) return;
        this.isPosting = true;

        const promise = contentDocumentIds.length > 0
            ? createPostWithAttachments({ groupId: id, body, contentDocumentIds })
            : createPost({ groupId: id, body });

        promise
            .then(() => {
                this.toast('Posted', 'Your post is live in the group.', 'success');
                const composer = this.template.querySelector('c-ken-group-post-composer');
                if (composer && composer.reset) composer.reset();
                this.loadFeed(true);
            })
            .catch(err => {
                this.toast('Could not post', this.extractError(err), 'error');
            })
            .finally(() => {
                this.isPosting = false;
            });
    }

    handlePollCreated() {
        this.toast('Poll posted', 'Your poll is live in the group.', 'success');
        this.loadFeed(true);
    }

    handlePostDeleted(event) {
        const feedItemId = event.detail.feedItemId;
        if (!feedItemId) return;
        deletePost({ feedItemId })
            .then(() => {
                this.posts = this.posts.filter(p => p.feedItemId !== feedItemId);
                this.toast('Deleted', 'Your post has been removed.', 'success');
            })
            .catch(err => {
                this.toast('Could not delete', this.extractError(err), 'error');
            });
    }

    get hasPosts()   { return this.posts && this.posts.length > 0; }
    get showEmpty()  { return !this.isLoading && !this.hasPosts && !this.errorMessage; }
    get showError()  { return !!this.errorMessage; }

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