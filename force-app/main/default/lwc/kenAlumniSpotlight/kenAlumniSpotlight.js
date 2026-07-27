import { LightningElement, track, wire } from 'lwc';
import getAlumniSpotlights from '@salesforce/apex/KenAlumniSpotlightController.getAlumniSpotlights';

const AUTO_ADVANCE_MS = 10000;

export default class KenAlumniSpotlight extends LightningElement {
    @track spotlights = [];
    @track currentIndex = 0;
    @track isLoading = true;
    @track hasError = false;

    _timer = null;

    @wire(getAlumniSpotlights)
    wiredSpotlights({ data, error }) {
        if (data) {
            this.spotlights = data;
            this.currentIndex = 0;
            this.isLoading = false;
            if (data.length > 1) this._startTimer();
        } else if (error) {
            this.hasError = true;
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        this._stopTimer();
    }

    _startTimer() {
        this._stopTimer();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setInterval(() => {
            this.currentIndex = (this.currentIndex + 1) % this.spotlights.length;
        }, AUTO_ADVANCE_MS);
    }

    _stopTimer() {
        if (this._timer) {
            clearInterval(this._timer);
            this._timer = null;
        }
    }

    // ── Getters ──────────────────────────────────────────────────────────────

    get hasSpotlights() {
        return !this.isLoading && !this.hasError && this.spotlights.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.hasError && this.spotlights.length === 0;
    }

    get current() {
        return this.spotlights[this.currentIndex] || null;
    }

    get currentTitle() {
        return this.current ? this.current.title : '';
    }

    get currentDescription() {
        return this.current ? this.current.description : '';
    }

    get hasDescription() {
        return !!(this.current && this.current.description);
    }

    get hasContentLink() {
        return !!(this.current && this.current.contentLink);
    }

    get contentLink() {
        return this.current ? this.current.contentLink : '#';
    }

    get contentLinkLabel() {
        return this.resolvedType === 'image' ? 'View Image' : 'Read More';
    }

    get resolvedType() {
        const t = (this.current && this.current.contentType ? this.current.contentType : '').toLowerCase();
        if (t === 'youtube' || t === 'blog' || t === 'image') return t;
        const link = this.contentLink || '';
        if (link.includes('youtube.com') || link.includes('youtu.be')) return 'youtube';
        if (link.match(/\.(jpg|jpeg|png|gif|webp)(\?|$)/i)) return 'image';
        return 'blog';
    }

    get isYouTube() {
        return this.resolvedType === 'youtube';
    }

    get isImage() {
        return this.resolvedType === 'image' && this.hasContentLink;
    }

    get isBlog() {
        return this.resolvedType === 'blog' && this.hasContentLink;
    }

    get youTubeThumbnailUrl() {
        const link = this.contentLink || '';
        let videoId = null;
        const watchMatch = link.match(/[?&]v=([^&#]+)/);
        const shortMatch = link.match(/youtu\.be\/([^?&#]+)/);
        if (watchMatch) videoId = watchMatch[1];
        else if (shortMatch) videoId = shortMatch[1];
        return videoId ? `https://img.youtube.com/vi/${videoId}/hqdefault.jpg` : null;
    }

    get dotItems() {
        return this.spotlights.map((s, i) => ({
            key: s.id || String(i),
            index: i,
            cssClass: i === this.currentIndex ? 'dot dot-active' : 'dot'
        }));
    }

    get showDots() {
        return this.spotlights.length > 1;
    }

    get showPrevNext() {
        return this.spotlights.length > 1;
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handlePrev() {
        this._stopTimer();
        this.currentIndex = (this.currentIndex - 1 + this.spotlights.length) % this.spotlights.length;
        this._startTimer();
    }

    handleNext() {
        this._stopTimer();
        this.currentIndex = (this.currentIndex + 1) % this.spotlights.length;
        this._startTimer();
    }

    handleDotClick(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (!isNaN(idx)) {
            this._stopTimer();
            this.currentIndex = idx;
            this._startTimer();
        }
    }
}