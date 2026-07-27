import { LightningElement, track } from 'lwc';
import SofiaProfilePhoto from '@salesforce/resourceUrl/SofiaProfilePhoto';
import EMPTY_STATE from '@salesforce/resourceUrl/MentorshipEmptyState';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getAlumniSpotlights from '@salesforce/apex/KenAlumniSpotlightController.getAlumniSpotlights';
import getHomeData from '@salesforce/apex/KenPortalHomeController.getHomeData';

const SPOTLIGHT_TRUNCATE_LEN = 80;
const SPOTLIGHT_AUTO_ADVANCE_MS = 10000;
const META_TRUNCATE_LEN = 50;
const CONTENT_TRUNCATE_LEN = 120;

function processFeedItem(item) {
    const date = item.date || '';
    const content = item.content || '';
    const needsMetaToggle = date.length > META_TRUNCATE_LEN;
    const metaShort = needsMetaToggle ? date.substring(0, META_TRUNCATE_LEN) + '...' : date;
    const needsContentToggle = content.length > CONTENT_TRUNCATE_LEN;
    const contentShort = needsContentToggle ? content.substring(0, CONTENT_TRUNCATE_LEN) + '...' : content;
    return {
        ...item,
        metaExpanded: false,
        metaShort,
        metaDisplayText: metaShort,
        metaShowToggle: needsMetaToggle,
        contentExpanded: false,
        contentShort,
        contentDisplayText: contentShort,
        contentShowToggle: needsContentToggle
    };
}

function toYouTubeEmbed(url) {
    if (!url) return null;
    const watch = url.match(/[?&]v=([A-Za-z0-9_-]{6,})/);
    if (watch) return `https://www.youtube.com/embed/${watch[1]}`;
    const short = url.match(/youtu\.be\/([A-Za-z0-9_-]{6,})/);
    if (short) return `https://www.youtube.com/embed/${short[1]}`;
    if (url.includes('youtube.com/embed/')) return url;
    return null;
}

const MOBILE_MAX_WIDTH = 768;

export default class KenPortalHomeFeed extends LightningElement {
    @track spotlightExpanded = false;
    @track mobileFeedShowAll = false;
    @track isMobile = false;

    @track spotlight = null;
    @track spotlightEmbedUrl = null;
    @track feedItems = [];
    @track feedLoaded = false;

    spotlights = [];
    spotlightIndex = 0;
    _spotlightTimer = null;
    emptyImage = EMPTY_STATE;

    _mediaQuery;
    _boundMobileChange;

    get hasSpotlight() {
        return !!this.spotlight;
    }

    get hasMultipleSpotlights() {
        return this.spotlights.length > 1;
    }

    get spotlightCounter() {
        return `${this.spotlightIndex + 1} / ${this.spotlights.length}`;
    }

    get showFeedEmpty() {
        return this.feedLoaded && this.feedItems.length === 0;
    }

    get spotlightHeadline() {
        return this.spotlight ? (this.spotlight.title || this.spotlight.name) : '';
    }

    get spotlightIsVideo() {
        return !!this.spotlightEmbedUrl;
    }

    get spotlightImageUrl() {
        return this.spotlight ? this.spotlight.contentLink : null;
    }

    get spotlightDescription() {
        const raw = this.spotlight ? (this.spotlight.description || '') : '';
        return raw.replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').trim();
    }

    get hasFeedItems() {
        return this.feedItems.length > 0;
    }

    get displayFeedItems() {
        if (!this.isMobile || this.mobileFeedShowAll) {
            return this.feedItems;
        }
        return this.feedItems.length ? [this.feedItems[0]] : [];
    }

    get showFeedViewMore() {
        return this.isMobile && !this.mobileFeedShowAll;
    }

    get showSpotlightSection() {
        return this.hasSpotlight && (!this.isMobile || this.mobileFeedShowAll);
    }

    get spotlightShowToggle() {
        return (this.spotlightDescription || '').length > SPOTLIGHT_TRUNCATE_LEN;
    }

    get spotlightDisplayText() {
        const text = this.spotlightDescription || '';
        if (!this.spotlightExpanded && text.length > SPOTLIGHT_TRUNCATE_LEN) {
            return text.substring(0, SPOTLIGHT_TRUNCATE_LEN) + '...';
        }
        return text;
    }

    toggleSpotlightExpand() {
        this.spotlightExpanded = !this.spotlightExpanded;
    }

    toggleItemMetaExpand(event) {
        const id = event.currentTarget.dataset.itemId;
        this.feedItems = this.feedItems.map((item) => {
            if (String(item.id) === id) {
                const metaExpanded = !item.metaExpanded;
                const metaDisplayText = metaExpanded ? (item.date || '') : item.metaShort;
                return { ...item, metaExpanded, metaDisplayText };
            }
            return item;
        });
    }

    toggleItemContentExpand(event) {
        const id = event.currentTarget.dataset.itemId;
        this.feedItems = this.feedItems.map((item) => {
            if (String(item.id) === id) {
                const contentExpanded = !item.contentExpanded;
                const contentDisplayText = contentExpanded ? (item.content || '') : item.contentShort;
                return { ...item, contentExpanded, contentDisplayText };
            }
            return item;
        });
    }

    handleViewMoreFeed() {
        this.mobileFeedShowAll = true;
    }

    _syncMobileFromMedia() {
        const next = this._mediaQuery ? this._mediaQuery.matches : false;
        if (next !== this.isMobile) {
            this.isMobile = next;
            if (!this.isMobile) {
                this.mobileFeedShowAll = false;
            }
        }
    }

    connectedCallback() {
        if (typeof window !== 'undefined' && window.matchMedia) {
            this._mediaQuery = window.matchMedia(`(max-width: ${MOBILE_MAX_WIDTH}px)`);
            this._boundMobileChange = this._syncMobileFromMedia.bind(this);
            this._syncMobileFromMedia();
            this._mediaQuery.addEventListener('change', this._boundMobileChange);
        }

        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });

        this.loadSpotlight();
        this.loadFeed();
    }

    async loadSpotlight() {
        try {
            const rows = await getAlumniSpotlights();
            this.spotlights = rows || [];
            this.spotlightIndex = 0;
            this._applySpotlight();
            this._startSpotlightTimer();
        } catch (e) {
            this.spotlights = [];
            this.spotlight = null;
        }
    }

    _startSpotlightTimer() {
        this._stopSpotlightTimer();
        if (this.spotlights.length < 2) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._spotlightTimer = setInterval(() => {
            this.spotlightIndex = (this.spotlightIndex + 1) % this.spotlights.length;
            this._applySpotlight();
        }, SPOTLIGHT_AUTO_ADVANCE_MS);
    }

    _stopSpotlightTimer() {
        if (this._spotlightTimer) {
            clearInterval(this._spotlightTimer);
            this._spotlightTimer = null;
        }
    }

    _applySpotlight() {
        const row = this.spotlights[this.spotlightIndex] || null;
        this.spotlight = row;
        this.spotlightEmbedUrl = row ? toYouTubeEmbed(row.contentLink) : null;
        this.spotlightExpanded = false;
    }

    handleSpotlightPrev() {
        if (!this.hasMultipleSpotlights) return;
        this.spotlightIndex = (this.spotlightIndex - 1 + this.spotlights.length) % this.spotlights.length;
        this._applySpotlight();
        this._startSpotlightTimer();
    }

    handleSpotlightNext() {
        if (!this.hasMultipleSpotlights) return;
        this.spotlightIndex = (this.spotlightIndex + 1) % this.spotlights.length;
        this._applySpotlight();
        this._startSpotlightTimer();
    }

    async loadFeed() {
        try {
            const data = await getHomeData();
            const posts = (data && data.feed) || [];
            this.feedItems = posts.map((p) => processFeedItem({
                id: p.id,
                title: p.authorName || 'Alumni',
                icon: p.authorPhotoUrl || SofiaProfilePhoto,
                tag: p.groupName || '',
                content: p.body || '',
                date: p.dateLabel || '',
                hashtags: []
            }));
        } catch (e) {
            this.feedItems = [];
        } finally {
            this.feedLoaded = true;
        }
    }

    disconnectedCallback() {
        if (this._mediaQuery && this._boundMobileChange) {
            this._mediaQuery.removeEventListener('change', this._boundMobileChange);
        }
        this._stopSpotlightTimer();
    }
}