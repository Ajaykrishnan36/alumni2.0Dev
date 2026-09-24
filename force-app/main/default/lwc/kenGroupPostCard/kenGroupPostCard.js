import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import toggleLikeApex from "@salesforce/apex/KenGroupFeedController.toggleLike";
import { setSafeHtml } from "c/kenHtmlSanitizer";

export default class KenGroupPostCard extends LightningElement {
  @api post;

  @track localLiked;
  @track localLikeCount;
  @track showComments = false;
  @track menuOpen = false;
  @track isLiking = false;
  @track showShareSheet = false;

  _renderedBodyFor = null;
  localLikeId = null;

  connectedCallback() {
    this.localLiked = !!(this.post && this.post.likedByMe);
    this.localLikeCount = (this.post && this.post.likeCount) || 0;
    this.localLikeId = (this.post && this.post.myLikeId) || null;
  }

  renderedCallback() {
    if (!this.post || !this.post.feedItemId) return;
    // Only re-paint when the post changes (this.post is set once by parent).
    if (this._renderedBodyFor === this.post.feedItemId) return;
    const bodyEl = this.template.querySelector(".post-body");
    if (bodyEl && this.post.body) {
      setSafeHtml(bodyEl, this.post.body);
      this._renderedBodyFor = this.post.feedItemId;
    }
  }

  get hasAttachments() {
    return (
      this.post && this.post.attachments && this.post.attachments.length > 0
    );
  }
  get hasPoll() {
    return this.post && !!this.post.pollState;
  }
  get hasBody() {
    return this.post && this.post.body && this.post.body.trim().length > 0;
  }
  get attachmentItems() {
    if (!this.hasAttachments) return [];
    return this.post.attachments.map((a, i) => ({
      ...a,
      key: a.contentDocumentId || `att-${i}`
    }));
  }

  get likeIcon() {
    return this.localLiked ? "utility:like" : "utility:like";
  }
  get likeButtonClass() {
    return `action-btn${this.localLiked ? " is-active" : ""}`;
  }
  get likeLabel() {
    return this.localLiked ? "Liked" : "Like";
  }

  get hasLikes() {
    return this.localLikeCount > 0;
  }
  get hasComments() {
    return (this.post.commentCount || 0) > 0;
  }
  get likesLabel() {
    const n = this.localLikeCount;
    return n === 1 ? "1 like" : `${n} likes`;
  }
  get commentsLabel() {
    const n = this.post.commentCount || 0;
    return n === 1 ? "1 comment" : `${n} comments`;
  }

  get commentsDisabled() {
    return this.post && this.post.commentsEnabled === false;
  }
  get commentsDisabledTitle() {
    return this.commentsDisabled ? "Comments are turned off for this post" : "";
  }

  get shareCaption() {
    if (!this.post || !this.post.body) return "";
    return sanitizeRichText(this.post.body)
      .replace(/<[^>]*>/g, " ")
      .replace(/&nbsp;/gi, " ")
      .replace(/&amp;/gi, "&")
      .replace(/&lt;/gi, "<")
      .replace(/&gt;/gi, ">")
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/gi, "'")
      .replace(/\s+/g, " ")
      .trim();
  }
  get shareImage() {
    return this.attachmentItems.find((a) => a.isImage) || null;
  }
  // Photos pasted/dragged straight into the post text are rendered as an <img> inline in
  // post.body rather than as a gallery attachment — attachmentItems won't see those at all.
  // Fall back to pulling the first inline image's already-resolved URL, plus the
  // ContentDocumentId stamped onto it server-side as data-doc-id, out of the body.
  get shareInlineImage() {
    if (this.shareImage || !this.post || !this.post.body) return null;
    const match = sanitizeRichText(this.post.body).match(
      /<img\b[^>]*\ssrc="([^"]+)"[^>]*\sdata-doc-id="([^"]+)"/i
    );
    return match ? { url: match[1], contentDocumentId: match[2] } : null;
  }
  get shareImageUrl() {
    return this.shareImage
      ? this.shareImage.downloadUrl
      : this.shareInlineImage
        ? this.shareInlineImage.url
        : null;
  }
  get shareImageFileName() {
    return this.shareImage
      ? this.shareImage.fileName
      : this.shareInlineImage
        ? "shared-image.jpg"
        : null;
  }
  // ContentDocumentId identifies the image for both the public-link mint (Facebook/LinkedIn/X)
  // and the byte-relay download — works uniformly for a gallery attachment or an inline image.
  get shareContentDocumentId() {
    return this.shareImage
      ? this.shareImage.contentDocumentId
      : this.shareInlineImage
        ? this.shareInlineImage.contentDocumentId
        : null;
  }

  get showMenu() {
    return this.post.canEdit || this.post.canDelete;
  }
  get authorInitial() {
    if (!this.post.authorName) return "?";
    return this.post.authorName.charAt(0).toUpperCase();
  }
  get hasAuthorPhoto() {
    return !!this.post.authorPhotoUrl;
  }

  handleToggleLike() {
    if (this.isLiking) return;
    this.isLiking = true;
    const previousLiked = this.localLiked;
    const previousCount = this.localLikeCount;
    const previousLikeId = this.localLikeId;
    // Optimistic flip
    this.localLiked = !previousLiked;
    this.localLikeCount = previousCount + (this.localLiked ? 1 : -1);

    toggleLikeApex({
      feedItemId: this.post.feedItemId,
      currentlyLiked: previousLiked,
      knownLikeId: previousLikeId
    })
      .then((result) => {
        if (!result) return;
        this.localLiked = !!result.liked;
        this.localLikeId = result.likeId || null;
        if (typeof result.likeCount === "number") {
          this.localLikeCount = result.likeCount;
        }
      })
      .catch((err) => {
        // Roll back optimistic update
        this.localLiked = previousLiked;
        this.localLikeCount = previousCount;
        this.localLikeId = previousLikeId;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Could not update like",
            message: this.extractError(err),
            variant: "error"
          })
        );
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
    this.dispatchEvent(
      new CustomEvent("deleted", {
        detail: { feedItemId: this.post.feedItemId }
      })
    );
  }

  handleOpenShare() {
    this.showShareSheet = true;
  }

  handleCloseShare() {
    this.showShareSheet = false;
  }

  extractError(err) {
    if (!err) return "Unknown error";
    if (err.body && err.body.message) return err.body.message;
    if (err.message) return err.message;
    return JSON.stringify(err);
  }
}