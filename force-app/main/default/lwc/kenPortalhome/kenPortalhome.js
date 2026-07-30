import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import AlumniAlt from '@salesforce/resourceUrl/eventTest2';
import AlumniAlt2 from '@salesforce/resourceUrl/eventTest1';
import EMPTY_STATE from '@salesforce/resourceUrl/MentorshipEmptyState';
import EVENTS_EMPTY_STATE from '@salesforce/resourceUrl/EmptyStateEventImage';
import getHomeData from '@salesforce/apex/KenPortalHomeController.getHomeData';
import getAlbums from '@salesforce/apex/KenGalleryController.getAlbums';
import getAllBusinesses from '@salesforce/apex/KenBusinessController.getAllBusinesses';
import getReferralLink from '@salesforce/apex/KenReferralService.getReferralLink';

const QUICK_LINKS = [
    { id: 1, label: 'Host An Event', icon: '🎉', page: 'host_event__c' },
    { id: 2, label: 'Contribute Now', icon: '🌿', page: 'fundraise__c' },
    { id: 3, label: 'Post Your Business', icon: '💼', page: 'create_business__c' },
    { id: 4, label: 'Create A Group', icon: '👥', page: 'create_group__c' },
    { id: 5, label: 'Connect With Others', icon: '🤝', page: 'network__c' }
];

const MAX_RESOURCES = 4;
const MAX_BUSINESSES = 4;
const MOBILE_MAX_WIDTH = 768;

export default class KenPortalhome extends NavigationMixin(LightningElement) {
    @track upcomingEvents = [];
    @track upcomingBirthdays = [];
    @track quickLinks = QUICK_LINKS;
    @track resources = [];
    @track businesses = [];
    @track inviteLink = '';
    @track isMobile = false;

    _mediaQuery;
    _boundMobileChange;

    emptyImage = EMPTY_STATE;
    eventsEmptyImage = EVENTS_EMPTY_STATE;

    get hasEvents() {
        return this.upcomingEvents.length > 0;
    }

    get hasBirthdays() {
        return this.upcomingBirthdays.length > 0;
    }

    get hasResources() {
        return this.resources.length > 0;
    }

    get hasBusinesses() {
        return this.businesses.length > 0;
    }

    get newsletterClass() {
        return this.isMobile
            ? 'newsletter-banner newsletter-banner--mobile'
            : 'newsletter-banner';
    }

    _syncMobileFromMedia() {
        const next = this._mediaQuery ? this._mediaQuery.matches : false;
        if (next !== this.isMobile) {
            this.isMobile = next;
        }
    }

    connectedCallback() {
        if (typeof window !== 'undefined' && window.matchMedia) {
            this._mediaQuery = window.matchMedia(`(max-width: ${MOBILE_MAX_WIDTH}px)`);
            this._boundMobileChange = this._syncMobileFromMedia.bind(this);
            this._syncMobileFromMedia();
            this._mediaQuery.addEventListener('change', this._boundMobileChange);
        }

        this.loadHomeData();
        this.loadResources();
        this.loadBusinesses();
        this.loadInviteLink();
    }

    disconnectedCallback() {
        if (this._mediaQuery && this._boundMobileChange) {
            this._mediaQuery.removeEventListener('change', this._boundMobileChange);
        }
    }

    async loadHomeData() {
        try {
            const data = await getHomeData();
            this.upcomingEvents = (data?.events || []).slice(0, 1).map(ev => ({
                id: ev.id,
                title: ev.title,
                date: ev.dateLabel,
                image: ev.image || AlumniAlt
            }));
            this.upcomingBirthdays = (data?.birthdays || []).map(b => ({
                id: b.id,
                name: b.name,
                batch: b.batch || '',
                course: b.program || '',
                month: b.monthLabel,
                day: b.dayLabel,
                image: b.photoUrl || AlumniAlt2,
                isOnline: false
            }));
        } catch (e) {
            this.upcomingEvents = [];
            this.upcomingBirthdays = [];
        }
    }

    async loadResources() {
        try {
            const albums = await getAlbums();
            this.resources = (albums || []).slice(0, MAX_RESOURCES).map(a => ({
                id: a.id,
                label: a.name
            }));
        } catch (e) {
            this.resources = [];
        }
    }

    async loadBusinesses() {
        try {
            const rows = await getAllBusinesses();
            this.businesses = (rows || []).slice(0, MAX_BUSINESSES).map(b => ({
                id: b.id,
                name: b.name,
                logo: b.logo || b.featuredImage || AlumniAlt
            }));
        } catch (e) {
            this.businesses = [];
        }
    }

    async loadInviteLink() {
        try {
            this.inviteLink = (await getReferralLink()) || '';
        } catch (e) {
            this.inviteLink = '';
        }
    }

    navigateToPage(pageName) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: pageName }
        });
    }

    handleQuickLinkClick(event) {
        const linkId = event.currentTarget.dataset.link;
        const link = QUICK_LINKS.find(l => String(l.id) === String(linkId));
        if (link) {
            this.navigateToPage(link.page);
        }
    }

    handleViewAllEvents() {
        this.navigateToPage('event__c');
    }

    handleViewNewsletter() {
        this.navigateToPage('gallery__c');
    }

    handleResourceClick() {
        this.navigateToPage('gallery__c');
    }

    handleViewAllResources() {
        this.navigateToPage('gallery__c');
    }

    handleBusinessClick() {
        this.navigateToPage('business__c');
    }

    handleViewAllBusinesses() {
        this.navigateToPage('business__c');
    }

    handleCopyLink() {
        if (!this.inviteLink) return;
        navigator.clipboard.writeText(this.inviteLink).catch(() => {});
    }
}