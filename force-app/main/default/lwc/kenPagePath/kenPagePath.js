import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getServiceName from '@salesforce/apex/KenPagePathController.getServiceName';

const BASE_PATH = '/alumni';

// Edge-case overrides for the rule-based engine.
//   parent       — explicit parent slug when strip-'-detail' rule doesn't resolve.
//                  Use null to skip the parent crumb entirely.
//   inlineDetail — true when the SAME route serves a record detail via a query
//                  param (no '-detail' suffix in the URL). The route slug itself
//                  becomes the parent crumb and the record name is appended.
//   idParams     — legacy query-param fallbacks. The convention is '?id=' (always
//                  checked first); list here is checked only if 'id' is absent.
//                  Each entry can also be migrated away as the page is updated.
const ROUTE_OVERRIDES = {
    'campaign-detail':        { parent: 'all-campaigns', idParams: ['recordId', 'campaignId', 'c__campaignId', 'fundraiseId', 'c__fundraiseId'] },
    'ticket-detail':          { parent: 'all-tickets', idParams: ['ticketId', 'c__ticketId'] },
    'news-detail':            { parent: null, idParams: ['newsId', 'c__newsId'] },
    'network':                { inlineDetail: true, idParams: ['profileId', 'c__profileId'] },
    'event-detail':           { idParams: ['eventId', 'c__eventId'] },
    'job-detail':             { idParams: ['jobId', 'c__jobId'] },
    'group-detail':           { idParams: ['groupId', 'c__groupId'] },
    'business-detail':        { idParams: ['recordId', 'businessId', 'c__businessId'] },
    'survey-detail':          { idParams: ['surveyId', 'c__surveyId'] },
    'request-service-detail': { idParams: ['serviceId', 'c__serviceId'] }
};

export default class KenBreadcrumb extends NavigationMixin(LightningElement) {
    @track breadcrumbItems = [];
    currentPageRef;
    static _stylesInjected = false;

    connectedCallback() {
        this.buildBreadcrumbs();
        this.injectBreadcrumbStyles();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (pageRef) {
            this.currentPageRef = pageRef;
            this.buildBreadcrumbs();
        }
    }

    injectBreadcrumbStyles() {
        if (KenBreadcrumb._stylesInjected) return;
        const style = document.createElement('style');
        style.id = 'breadcrumb-custom-styles';
        style.textContent = `
            .slds-breadcrumb .slds-breadcrumb__item > a,
            .slds-breadcrumb__item > a,
            [part="breadcrumb"] {
                font-size: 14px !important;
                font-weight: 400 !important;
                color: #373A45 !important;
            }
            .slds-breadcrumb__item > a:hover,
            [part="breadcrumb"]:hover {
                color: #373A45 !important;
                text-decoration: underline;
            }
        `;
        document.head.appendChild(style);
        KenBreadcrumb._stylesInjected = true;
    }

    get hasBreadcrumbs() {
        return this.breadcrumbItems && this.breadcrumbItems.length > 1;
    }

    dispatchBreadcrumbVisibility(isVisible) {
        this.dispatchEvent(new CustomEvent('breadcrumbvisibilitychange', {
            detail: { isVisible },
            bubbles: true,
            composed: true
        }));
    }

    buildBreadcrumbs() {
        const segments = this.parsePathSegments(this.getPathFromUrl());

        if (segments.length === 0) {
            this.breadcrumbItems = [];
            this.dispatchBreadcrumbVisibility(false);
            return;
        }

        const lastSlug = segments[segments.length - 1];
        const override = ROUTE_OVERRIDES[lastSlug] || {};
        const urlParams = new URLSearchParams(window.location?.search || '');

        // Convention: '?id=' is checked first. Per-route idParams act as legacy
        // fallbacks; remove a route's entry from ROUTE_OVERRIDES once it's been
        // migrated to '?id='.
        const candidates = ['id', ...(override.idParams || [])];
        let recordId = null;
        for (const p of candidates) {
            const v = urlParams.get(p) || this.currentPageRef?.state?.[p];
            if (v) { recordId = v; break; }
        }

        const isDetailSegment = this.isDetailSlug(lastSlug);
        const isInlineDetail = override.inlineDetail === true && !!recordId;
        const inDetailMode = !!recordId && (isDetailSegment || isInlineDetail);

        // Only show breadcrumbs on sub-pages or in detail mode.
        if (segments.length === 1 && !inDetailMode) {
            this.breadcrumbItems = [];
            this.dispatchBreadcrumbVisibility(false);
            return;
        }

        const items = [];
        let cumulativePath = BASE_PATH;

        items.push({
            id: 'home',
            label: 'Home',
            href: BASE_PATH,
            isClickable: true
        });

        // For *-detail routes, insert the parent crumb (strip '-detail', or override).
        if (isDetailSegment) {
            const parentSlug = this.parentSlugFor(lastSlug);
            if (parentSlug && !segments.slice(0, -1).includes(parentSlug)) {
                cumulativePath = `${cumulativePath}/${parentSlug}`;
                items.push({
                    id: 'parent',
                    label: this.labelFor(parentSlug),
                    href: cumulativePath,
                    isClickable: true,
                    segment: parentSlug
                });
            }
        }

        // Walk path segments. For *-detail routes we drop the final segment because
        // its slot is taken by the appended record-name crumb. For inline-detail we
        // keep all segments (the route slug IS the list parent) and make the last
        // one clickable so users can navigate back.
        const lastVisibleIndex = isDetailSegment ? segments.length - 1 : segments.length;
        for (let i = 0; i < lastVisibleIndex; i++) {
            const segment = segments[i];
            const isLast = i === lastVisibleIndex - 1;
            cumulativePath = `${cumulativePath}/${segment}`;
            items.push({
                id: `seg-${i}`,
                label: this.labelFor(segment),
                href: cumulativePath,
                isClickable: !isLast || isInlineDetail,
                segment
            });
        }

        // Append a record-name crumb when we're in detail mode.
        if (inDetailMode) {
            items.push({
                id: 'record',
                label: 'Loading...',
                href: (window.location?.pathname || '') + (window.location?.search || ''),
                isClickable: false,
                isRecordCrumb: true
            });
            this.fetchRecordName(recordId, items, items.length - 1);
        }

        this.breadcrumbItems = items;
        this.dispatchBreadcrumbVisibility(items.length > 1);
    }

    isDetailSlug(slug) {
        return !!slug && slug.endsWith('-detail');
    }

    parentSlugFor(slug) {
        const override = ROUTE_OVERRIDES[slug];
        if (override && Object.prototype.hasOwnProperty.call(override, 'parent')) {
            return override.parent; // may be null → explicit skip
        }
        return slug.replace(/-detail$/, '');
    }

    async fetchRecordName(recordId, items, itemIndex) {
        if (!recordId) return;
        try {
            const name = await getServiceName({ serviceId: recordId });
            if (items[itemIndex]) {
                items[itemIndex].label = name || 'Detail';
                this.breadcrumbItems = [...items];
            }
        } catch (error) {
            console.error('Error fetching record name:', error);
            if (items[itemIndex]) {
                items[itemIndex].label = 'Detail';
                this.breadcrumbItems = [...items];
            }
        }
    }

    parsePathSegments(path) {
        if (!path) return [];
        const cleanPath = path.replace(/^\/+|\/+$/g, '');
        if (!cleanPath) return [];
        // Strip Experience Cloud's '/s/' routing segment (e.g. /alumni/s/event)
        const pathParts = cleanPath.split('/').filter(p => p && p.trim() !== '' && p !== 's');
        const alumniIndex = pathParts.indexOf('alumni');
        return alumniIndex >= 0 ? pathParts.slice(alumniIndex + 1) : pathParts;
    }

    labelFor(slug) {
        if (!slug) return '';
        return slug
            .split('-')
            .map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
            .join(' ');
    }

    getPathFromUrl() {
        if (typeof window === 'undefined' || !window.location) return '';
        return window.location.pathname || '';
    }

    handleBreadcrumbClick(event) {
        event.preventDefault();
        event.stopPropagation();
        this.navigateToBreadcrumb(event.currentTarget);
    }

    handleBreadcrumbKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            event.stopPropagation();
            this.navigateToBreadcrumb(event.currentTarget);
        }
    }

    navigateToBreadcrumb(element) {
        const href = element.dataset.href || element.getAttribute('href');
        const isClickable = element.dataset.clickable === 'true';
        if (!href || !isClickable) return;

        const item = this.breadcrumbItems.find(b => b.href === href);
        if (!item || !item.isClickable) return;

        try {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: { url: href },
                replace: true
            });
        } catch (error) {
            console.warn('NavigationMixin failed, using direct navigation:', error);
            if (window.location) window.location.href = href;
        }
    }
}