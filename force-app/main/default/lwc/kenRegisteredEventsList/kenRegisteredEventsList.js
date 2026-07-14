import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getRegisteredEvents from '@salesforce/apex/KenPortalEventController.getContactRegisteredSessions';
import basePath from '@salesforce/community/basePath';
import happeningNowIcon from '@salesforce/resourceUrl/happeningNowIcon';
import SurveyEmptyImage from '@salesforce/resourceUrl/SurveyEmptyImage';
import FORM_FACTOR from '@salesforce/client/formFactor';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenRegisteredEventsList extends NavigationMixin(LightningElement) {
    @track currentTab = 'Upcoming';
    @track processedEvents = [];
    @track showFeedbackIntro = false;
    @track pendingFeedbackSessionId = null;
    @track pendingFeedbackEventTitle = '';
    happeningIcon = happeningNowIcon;
    SurveyEmptyImageUrl = SurveyEmptyImage;

    isMobile = false;
    pageReference;

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        this.pageReference = currentPageReference;
        const requestedTab = currentPageReference?.state?.selectedTab;
        if (requestedTab && ['Upcoming', 'Cancelled', 'Completed'].includes(requestedTab)) {
            this.currentTab = requestedTab;
        }
    }

    connectedCallback() {
        this.isMobile = FORM_FACTOR === 'Small';

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

        this.fetchEvents();
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    async fetchEvents() {
        try {
            const constituentRoleId = localStorage.getItem('ConstituentRoleId');
            const data = await getRegisteredEvents({ constituentRoleId });

            if (!data) {
                this.processedEvents = [];
                return;
            }

            const now = new Date();

            this.processedEvents = data.map(item => {
                if (!item.startDate) {
                    return { ...item, status: 'Date not available' };
                }

                const [year, month, day] = item.startDate.split('-');
                const baseStart = new Date(year, month - 1, day);
                const startMs = item.startTime || 0;
                const endMs = item.endTime || 0;
                const eventStartDateTime = new Date(baseStart.getTime() + startMs);

                let baseEnd = baseStart;
                if (item.endDate) {
                    const [ey, em, ed] = item.endDate.split('-');
                    baseEnd = new Date(ey, em - 1, ed);
                }
                const eventEndDateTime = new Date(baseEnd.getTime() + endMs);

                const bookingType = item.bookingType;
                const eventStatusRaw = item.eventStatus;
                const isHostCancelled = eventStatusRaw === 'Cancelled';

                let status;
                if (isHostCancelled || bookingType === 'Cancelled') {
                    status = 'Cancelled';
                } else if (now > eventEndDateTime) {
                    status = 'Completed';
                } else if (now >= eventStartDateTime && now <= eventEndDateTime) {
                    status = 'Happening now!';
                } else if (eventStartDateTime > now) {
                    status = 'Upcoming';
                } else {
                    status = 'Completed';
                }

                const isOnline = (item.locationType || '').toLowerCase() === 'online'
                    || item.locationType === 'Online event';

                const dateRange = this.formatDateRange(item.startDate, item.endDate);
                const amountPaidText = item.isFree ? 'Free' : `₹${this.formatAmount(item.amountPaid)}`;

                let cancelBadgeText = '';
                if (status === 'Cancelled') {
                    cancelBadgeText = isHostCancelled
                        ? 'Event cancelled by host'
                        : (item.bookingDate ? `Cancelled on ${this.formatLongDate(item.bookingDate)}` : 'Cancelled');
                }

                const isUpcoming = status === 'Upcoming' || status === 'Happening now!';
                const isHappening = status === 'Happening now!';
                const isCompleted = status === 'Completed';
                const isCancelled = status === 'Cancelled';

                const feedbackAlreadySubmitted = item.feedbackSubmitted === true;

                return {
                    id: item.id,
                    eventId: item.eventId,
                    eventName: item.eventName || '',
                    sessionName: item.name || '',
                    title: item.eventName || '',
                    subtitle: '',
                    dateRange,
                    mode: this.formatMode(item.locationType),
                    location: item.location || '',
                    image: item.eventBanner || '',
                    eventLink: item.sessionLink || '',
                    participantsCount: item.participantsCount || 0,
                    amountPaidText,
                    cancelBadgeText,
                    status,
                    showJoinButton: isHappening && isOnline,
                    showViewDetailsButton: true,
                    // Only when this session actually has a feedback form configured —
                    // otherwise the form page would error with "no feedback form set up".
                    showSubmitFeedback: isCompleted && item.hasFeedbackForm === true && !feedbackAlreadySubmitted,
                    showFeedbackSubmitted: isCompleted && item.hasFeedbackForm === true && feedbackAlreadySubmitted,
                    showHappeningBadge: isHappening,
                    showCompletedBadge: isCompleted,
                    showCancelledBadge: isCancelled,
                    showParticipants: isUpcoming,
                    showInfoRow: isUpcoming || isCompleted || isCancelled,
                    showLocation: !isOnline,
                    showLinkInsteadOfLocation: isOnline && !!item.sessionLink
                };
            });
        } catch (error) {
            console.error('Error fetching events:', error);
        }
    }

    formatDateRange(startDate, endDate) {
        if (!startDate) return '';
        const start = this.parseLocalDate(startDate);
        const end = endDate ? this.parseLocalDate(endDate) : start;
        const startDay = start.getDate();
        const endDay = end.getDate();
        const sameMonthYear = start.getMonth() === end.getMonth() && start.getFullYear() === end.getFullYear();
        const monthShort = end.toLocaleString('default', { month: 'short' });
        const year = end.getFullYear();
        if (start.getTime() === end.getTime() || (sameMonthYear && startDay === endDay)) {
            return `${startDay} ${monthShort}, ${year}`;
        }
        if (sameMonthYear) {
            return `${startDay} - ${endDay} ${monthShort}, ${year}`;
        }
        const startMonth = start.toLocaleString('default', { month: 'short' });
        const startYear = start.getFullYear();
        return `${startDay} ${startMonth} ${startYear} - ${endDay} ${monthShort} ${year}`;
    }

    parseLocalDate(dateString) {
        const [y, m, d] = dateString.split('-');
        return new Date(Number(y), Number(m) - 1, Number(d));
    }

    formatLongDate(dateValue) {
        const d = new Date(dateValue);
        const day = d.getDate();
        const month = d.toLocaleString('default', { month: 'long' });
        const year = d.getFullYear();
        return `${day} ${month} ${year}`;
    }

    formatAmount(amount) {
        if (amount === null || amount === undefined) return '0';
        return Number(amount).toLocaleString('en-IN');
    }

    formatMode(locationType) {
        if (!locationType) return '';
        const lower = locationType.toLowerCase();
        if (lower === 'online' || locationType === 'Online event') return 'Online';
        if (lower === 'offline' || locationType === 'Offline event') return 'Offline';
        if (lower === 'hybrid') return 'Hybrid';
        return locationType;
    }

    formatDateForButton(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        const day = date.getDate();
        const month = date.toLocaleString('default', { month: 'short' });
        const year = date.getFullYear().toString().slice(-2);
        return `${day} ${month} ${year}`;
    }

    millisecondsToTimeString(ms) {
        if (!ms || isNaN(ms)) return '12:00 AM';
        const totalMinutes = Math.floor(ms / 60000);
        let hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        const ampm = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12 || 12;
        return `${hours}:${minutes.toString().padStart(2, '0')} ${ampm}`;
    }

    handleTabClick(event) {
        this.currentTab = event.currentTarget.dataset.tab;
    }

    get upcomingTabClass() {
        return this.currentTab === 'Upcoming' ? 'tab active' : 'tab';
    }

    get cancelledTabClass() {
        return this.currentTab === 'Cancelled' ? 'tab active' : 'tab';
    }

    get completedTabClass() {
        return this.currentTab === 'Completed' ? 'tab active' : 'tab';
    }

    get isUpcoming() {
        return this.currentTab === 'Upcoming';
    }

    get isCancelled() {
        return this.currentTab === 'Cancelled';
    }

    get isCompleted() {
        return this.currentTab === 'Completed';
    }

    get filteredEvents() {
        const filtered = this.processedEvents.filter(event => {
            if (event.status === 'Happening now!') {
                return this.currentTab === 'Upcoming';
            }
            return event.status === this.currentTab;
        });
        // Completed events: show one row per SESSION — feedback is configured and
        // submitted per session. Lead with the session name (event name as a
        // sub-line) so two sessions of the same event don't look like duplicates.
        if (this.currentTab === 'Completed') {
            return filtered.map(event => ({
                ...event,
                title: event.sessionName || event.eventName || '',
                subtitle: (event.eventName && event.sessionName && event.eventName !== event.sessionName)
                    ? event.eventName : ''
            }));
        }
        // Other tabs: dedup to one row per event; lead with the event name.
        const seen = new Set();
        return filtered
            .filter(event => {
                const key = event.eventId || event.id;
                if (seen.has(key)) return false;
                seen.add(key);
                return true;
            })
            .map(event => ({ ...event, title: event.eventName || '', subtitle: '' }));
    }

    get hasFilteredEvents() {
        return this.filteredEvents.length > 0;
    }

    get emptyStateMessage() {
        switch (this.currentTab) {
            case 'Cancelled':
                return 'No cancelled events found';
            case 'Completed':
                return 'No completed events found';
            default:
                return 'No upcoming events found';
        }
    }

    openEventLink(event) {
        const eventLink = event.currentTarget.dataset.link;
        if (eventLink) {
            window.open(eventLink, '_blank');
        }
    }

    navigateToEventsHome() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'all_events__c'
            }
        });
    }

    handleViewdetails(event) {
        const eventId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'event_detail__c'
            },
            state: {
                recordId: eventId,
            }
        });
    }

    handleSubmitFeedback(event) {
        const sessionId = event.currentTarget.dataset.id;
        const title = event.currentTarget.dataset.title || '';
        this.pendingFeedbackSessionId = sessionId;
        this.pendingFeedbackEventTitle = title;
        this.showFeedbackIntro = true;
    }

    handleCloseFeedbackIntro() {
        this.showFeedbackIntro = false;
        this.pendingFeedbackSessionId = null;
        this.pendingFeedbackEventTitle = '';
    }

    handleStartFeedback() {
        if (!this.pendingFeedbackSessionId) return;
        const sessionId = this.pendingFeedbackSessionId;
        this.showFeedbackIntro = false;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'survey_form__c' },
            state: { sessionId }
        });
    }

    handleDialogStop(event) {
        event.stopPropagation();
    }
}