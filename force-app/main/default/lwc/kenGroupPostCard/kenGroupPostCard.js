import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import toggleLikeApex from '@salesforce/apex/KenGroupFeedController.toggleLike';

export default class KenGroupPostCard extends LightningElement {
    @api post;

    @track localLiked;
    @track localLikeCount;
    @track showComments = false;
    @track menuOpen = false;
    @track isLiking = false;

    _renderedBodyFor = null;
    localLikeId = null;

    connectedCallback() {
        this.localLiked     = !!(this.post && this.post.likedByMe);
        this.localLikeCount = (this.post && this.post.likeCount) || 0;
        this.localLikeId    = (this.post && this.post.myLikeId) || null;
    }

    renderedCallback() {
        if (!this.post || !this.post.feedItemId) return;
        // Only re-paint when the post changes (this.post is set once by parent).
        if (this._renderedBodyFor === this.post.feedItemId) return;
        const bodyEl = this.template.querySelector('.post-body');
        if (bodyEl && this.post.body) {
            bodyEl.innerHTML = this.sanitize(this.post.body);
            this._renderedBodyFor = this.post.feedItemId;
        }
    }

    sanitize(html) {
        if (!html) return '';
        // Strip <script>, <iframe>, <object>, and inline event handlers / javascript: URLs.
        return html
            .replace(/<script[\s\S]*?<\/script>/gi, '')
            .replace(/<iframe[\s\S]*?<\/iframe>/gi, '')
            .replace(/<object[\s\S]*?<\/object>/gi, '')
            .replace(/ on[a-z]+="[^"]*"/gi, '')
            .replace(/ on[a-z]+='[^']*'/gi, '')
            .replace(/javascript:/gi, '');
    }

    get hasAttachments()  { return this.post && this.post.attachments && this.post.attachments.length > 0; }
    get hasPoll()         { return this.post && !!this.post.pollState; }
    get hasBody()         { return this.post && this.post.body && this.post.body.trim().length > 0; }
    get attachmentItems() {
        if (!this.hasAttachments) return [];
        return this.post.attachments.map((a, i) => ({
            ...a,
            key: a.contentDocumentId || `att-${i}`
        }));
    }

    get likeIcon()        { return this.localLiked ? 'utility:like' : 'utility:like'; }
    get likeButtonClass() { return `action-btn${this.localLiked ? ' is-active' : ''}`; }
    get likeLabel()       { return this.localLiked ? 'Liked' : 'Like'; }

    get hasLikes()        { return this.localLikeCount > 0; }
    get hasComments()     { return (this.post.commentCount || 0) > 0; }
    get likesLabel() {
        const n = this.localLikeCount;
        return n === 1 ? '1 like' : `${n} likes`;
    }
    get commentsLabel() {
        const n = this.post.commentCount || 0;
        return n === 1 ? '1 comment' : `${n} comments`;
    }

    get showMenu()        { return this.post.canEdit || this.post.canDelete; }
    get authorInitial() {
        if (!this.post.authorName) return '?';
        return this.post.authorName.charAt(0).toUpperCase();
    }
    get hasAuthorPhoto()  { return !!this.post.authorPhotoUrl; }

    handleToggleLike() {
        if (this.isLiking) return;
        this.isLiking = true;
        const previousLiked   = this.localLiked;
        const previousCount   = this.localLikeCount;
        const previousLikeId  = this.localLikeId;
        // Optimistic flip
        this.localLiked     = !previousLiked;
        this.localLikeCount = previousCount + (this.localLiked ? 1 : -1);

        toggleLikeApex({
            feedItemId:      this.post.feedItemId,
            currentlyLiked:  previousLiked,
            knownLikeId:     previousLikeId
        })
            .then(result => {
                if (!result) return;
                this.localLiked     = !!result.liked;
                this.localLikeId    = result.likeId || null;
                if (typeof result.likeCount === 'number') {
                    this.localLikeCount = result.likeCount;
                }
            })
            .catch(err => {
                // Roll back optimistic update
                this.localLiked     = previousLiked;
                this.localLikeCount = previousCount;
                this.localLikeId    = previousLikeId;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Could not update like',
                    message: this.extractError(err),
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isLiking = false;
            });
    }

    handleToggleComments() {
        this.showComments = !this.showComments;
    }

    handleToggleMenu(event) {
        event.stopPropagation();
        this.menuOpen = !this.menuOpen;
    }

    handleDelete() {
        this.menuOpen = false;
        this.dispatchEvent(new CustomEvent('deleted', {
            detail: { feedItemId: this.post.feedItemId }
        }));
    }

    extractError(err) {
        if (!err) return 'Unknown error';
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }
}