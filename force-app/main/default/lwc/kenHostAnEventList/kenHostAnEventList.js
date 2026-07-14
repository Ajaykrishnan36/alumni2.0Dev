import { LightningElement, track } from 'lwc';
import getHostedEvents from '@salesforce/apex/KenPortalEventController.getHostedEvents';
import basePath from '@salesforce/community/basePath';
import { NavigationMixin } from 'lightning/navigation';
import FORM_FACTOR from '@salesforce/client/formFactor';
import { getPortalConfigs as getPortalColors } from 'c/kenThemeConfig';

const TABS = ['In review', 'Approved', 'Rejected', 'Drafts'];

export default class KenHostAndEventList extends NavigationMixin(LightningElement) {
    currentTab = 'In review';
    isMobile = false;
    searchTerm = '';

    @track events = [];
    isLoading = false;

    get tabs() {
        return TABS.map(label => ({
            key: label,
            label: label === 'In review' ? 'In Review' : label,
            class: this.currentTab === label ? 'tab active' : 'tab'
        }));
    }

    get filteredEvents() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        return this.events.filter(ev => {
            if (ev.approvalStatus !== this.currentTab) return false;
            if (term && !(ev.title || '').toLowerCase().includes(term)) return false;
            return true;
        });
    }

    get hasFilteredEvents() {
        return this.filteredEvents.length > 0;
    }

    get emptyStateMessage() {
        switch (this.currentTab) {
            case 'Approved': return 'No approved events found';
            case 'Rejected': return 'No rejected events found';
            case 'Drafts': return 'No draft events found';
            default: return 'No events in review found';
        }
    }

    get isInReview() { return this.currentTab === 'In review'; }
    get isApproved() { return this.currentTab === 'Approved'; }
    get isRejected() { return this.currentTab === 'Rejected'; }
    get isDrafts() { return this.currentTab === 'Drafts'; }

    connectedCallback() {
        this.loadHostedEvents();
        this.isMobile = FORM_FACTOR === 'Small';

        getPortalColors()
            .then(color => {
                document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
                document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
                document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
            })
            .catch(() => {});

        const fontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Regular.woff2`;
        const style = document.createElement('style');
        style.innerText = `
            @font-face {
                font-family: 'GeneralSansCustom';
                src: url('${fontUrl}') format('woff2');
                font-weight: normal;
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);
    }

    async loadHostedEvents() {
        this.isLoading = true;
        try {
            const constituentRoleId = localStorage.getItem('ConstituentRoleId');
            const data = await getHostedEvents({ constituentRoleId });
            this.processEventData(data);
        } catch (error) {
            console.error('Error fetching hosted events:', error);
        } finally {
            this.isLoading = false;
        }
    }

    processEventData(data) {
        this.events = (data || []).map(event => {
            const capacity = (event.Max_Allowed_Participants__c !== undefined && event.Max_Allowed_Participants__c !== null)
                ? event.Max_Allowed_Participants__c
                : 0;
            const timeline = this.computeTimeline(event.Start_Date__c, event.End_Date__c);
            const offerMeals = !!event.Offer_Meals__c;
            return {
                id: event.Id,
                title: event.Name,
                image: event.Event_banner__c,
                formattedDateRange: this.formatDateRange(event.Start_Date__c, event.End_Date__c),
                mode: this.deriveMode(event),
                submittedOn: event.CreatedDate ? this.formatDate(event.CreatedDate) : '',
                rejectedOn: this.formatDate(event.Rejected_On__c || event.LastModifiedDate),
                capacity: capacity,
                participants: capacity,
                offerMeals: offerMeals,
                mealsOpted: offerMeals ? `0/${capacity}` : null,
                priceLabel: this.computePriceLabel(event),
                approvalStatus: this.getStatusText(event.Event_Status__c),
                timeline: timeline.label,
                isUpcoming: timeline.label === 'Upcoming',
                isOngoing: timeline.label === 'Ongoing',
                isCompleted: timeline.label === 'Completed',
                timelineClass: `status-pill ${timeline.cls}`,
                rejectionReason: event.Reason_For_Rejection__c
            };
        });
    }

    computePriceLabel(event) {
        if (!event.No_Fee__c && event.Event_Fee__c) return `₹${event.Event_Fee__c}`;
        const sessions = this.getSessions(event);
        const hasSessionFee = sessions.some(s => !s.No_Fee__c && s.Session_Fee__c);
        if (hasSessionFee) return 'Session wise';
        return 'Free';
    }

    getSessions(event) {
        const raw = event.Schedule_Sessions__r;
        return Array.isArray(raw) ? raw : (raw && Array.isArray(raw.records) ? raw.records : []);
    }

    // Event mode is derived from its sessions' location types: all online -> Online, all on-site -> Offline,
    // a mix (or any hybrid session) -> Hybrid. Falls back to Location__c when there are no sessions.
    deriveMode(event) {
        const sessions = this.getSessions(event);
        const types = sessions.map(s => String(s.Location_Type__c || '').toLowerCase());
        const hasOnline = types.includes('online');
        const hasOnsite = types.includes('onsite');
        const hasHybrid = types.includes('hybrid');
        if (hasHybrid || (hasOnline && hasOnsite)) return 'Hybrid';
        if (hasOnsite) return 'Offline';
        if (hasOnline) return 'Online';
        return event.Location__c || 'Online';
    }

    computeTimeline(startStr, endStr) {
        if (!startStr) return { label: 'Upcoming', cls: 'status-upcoming' };
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const start = new Date(startStr); start.setHours(0, 0, 0, 0);
        const end = endStr ? new Date(endStr) : new Date(startStr);
        end.setHours(23, 59, 59, 999);
        if (today < start) return { label: 'Upcoming', cls: 'status-upcoming' };
        if (today > end) return { label: 'Completed', cls: 'status-completed' };
        return { label: 'Ongoing', cls: 'status-ongoing' };
    }

    getStatusText(status) {
        const statusMap = {
            'Draft': 'Drafts',
            'In Progress': 'Drafts',
            'In Review': 'In review',
            'Pending Approval': 'In review',
            'Approved': 'Approved',
            'Rejected': 'Rejected',
            'Cancelled': 'Cancelled'
        };
        return statusMap[status] || 'In review';
    }

    formatDateRange(startDate, endDate) {
        if (!startDate) return '';
        if (startDate === endDate || !endDate) return this.formatDate(startDate);
        return `${this.formatDate(startDate)} - ${this.formatDate(endDate)}`;
    }

    formatDate(dateStr) {
        if (!dateStr) return '';
        const date = new Date(dateStr);
        const day = date.getDate().toString().padStart(2, '0');
        return `${day} ${this.getMonthName(date.getMonth())} ${date.getFullYear()}`;
    }

    getMonthName(monthIndex) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return months[monthIndex];
    }

    handleTabClick(event) {
        this.currentTab = event.currentTarget.dataset.tab;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleHostEvent() {
        try { sessionStorage.removeItem('currentEventId'); } catch (e) { /* ignore */ }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'host_event__c' }
        });
    }

    handleViewDetails(event) {
        const eventId = event.currentTarget.dataset.id;
        if (!eventId) return;
        if (this.currentTab === 'Drafts') {
            try { sessionStorage.setItem('currentEventId', eventId); } catch (e) { /* ignore */ }
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'host_event__c' }
            });
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'event_detail__c' },
            state: { recordId: eventId }
        });
    }
}