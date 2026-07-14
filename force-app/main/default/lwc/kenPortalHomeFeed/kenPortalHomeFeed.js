import { LightningElement, track } from 'lwc';
import SofiaProfilePhoto from '@salesforce/resourceUrl/SofiaProfilePhoto';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const SPOTLIGHT_TRUNCATE_LEN = 80;
const META_TRUNCATE_LEN = 50;
const CONTENT_TRUNCATE_LEN = 120;

const FEED_ITEMS_JSON = [
    {
        id: 1,
        title: 'Symposium Mania',
        icon: SofiaProfilePhoto,
        tag: 'News',
        content: 'The symposium has been postponed due to unforeseen circumstances. The dates will be announced later.',
        date: '24-06-2024 | 25 minutes ago',
        hashtags: []
    },
    {
        id: 2,
        title: 'Creative thinking',
        icon: SofiaProfilePhoto,
        tag: 'Social Media',
        content: 'Embrace the power of creative thinking! 🚀 In a world filled with possibilities, unlocking creativity is the key to innovative solutions and breakthroughs. Whether in business, arts, or everyday challenges, nurturing a creative mindset is the spark that transforms ideas into reality.',
        date: '24-06-2024 | 1 hour ago',
        hashtags: ['CreativeThinking', 'InnovationMindset']
    }
];

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

const MOBILE_MAX_WIDTH = 768;

export default class KenPortalHomeFeed extends LightningElement {
    @track spotlightExpanded = false;
    @track mobileFeedShowAll = false;
    @track isMobile = false;

    spotlightDescription = 'Ruby House has achieved an incredible milestone by winning the sports competition for the third consecutive year, showcasing their unparalleled talent, teamwork, and dedication.';

    @track feedItems = FEED_ITEMS_JSON.map(processFeedItem);

    _mediaQuery;
    _boundMobileChange;

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
        return !this.isMobile || this.mobileFeedShowAll;
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
    }

    disconnectedCallback() {
        if (this._mediaQuery && this._boundMobileChange) {
            this._mediaQuery.removeEventListener('change', this._boundMobileChange);
        }
    }
}