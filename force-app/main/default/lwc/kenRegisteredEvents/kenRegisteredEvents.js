import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRegisteredEvents from '@salesforce/apex/KenPortalEventController.getContactRegisteredSessions';
import basePath from '@salesforce/community/basePath';
import FORM_FACTOR from '@salesforce/client/formFactor';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import SurveyEmptyImage from '@salesforce/resourceUrl/SurveyEmptyImage';
export default class KenRegisteredEvents extends NavigationMixin(LightningElement) {
    @track activeTab = 'upcoming';
    SurveyEmptyImageUrl = SurveyEmptyImage;
    @track allEvents = [];
    @track hostEventVisible = false;

    get containerClass() {
        return `registered-event-container${this.hostEventVisible ? ' with-host' : ''}`;
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
            this.hostEventVisible = color?.showHostEvent === true;
        }).catch(() => {
            console.log('Error getting primary color');
        });
        const regularFontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Regular.woff2`;
        const boldFontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Light.woff2`;
        const style = document.createElement('style');
        style.innerText = `
            @font-face {
                font-family: 'GeneralSansCustom';
                src: url('${regularFontUrl}') format('woff2');
                font-style: normal;
                font-display: swap;
            }
    
            @font-face {
                font-family: 'GeneralSansCustomBold';
                src: url('${boldFontUrl}') format('woff2');
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);

        this.fetchEvents();
    }

    async fetchEvents() {
        try {
            const constituentRoleId = localStorage.getItem('ConstituentRoleId');
            const data = await getRegisteredEvents({ constituentRoleId });

            if (!data) {
                return;
            }

            const filteredSessions = data.filter(item => item.bookingType === 'Registered');

            this.allEvents = filteredSessions.map(item => ({
                id: item.id,
                eventId: item.eventId || '',
                eventDate: item.startDate || '1970-01-01',
                eventName: item.name || '',
                imageUrl: item.eventBanner || '',
                startTime: item.startTime ? this.millisecondsToTimeString(item.startTime) : '00:00',
                endTime: item.endTime ? this.millisecondsToTimeString(item.endTime) : '00:00',
                location: item.location || ''
            }));
        } catch (error) {
            console.error('Error fetching events:', error);
        }
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

    get today() {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return today;
    }

    get upcomingEvents() {
        return this.allEvents.filter(event => {
            const eventDate = new Date(event.eventDate);
            eventDate.setHours(0, 0, 0, 0);
            return eventDate >= this.today;
        });
    }

    get pastEvents() {
        return this.allEvents.filter(event => {
            const eventDate = new Date(event.eventDate);
            eventDate.setHours(0, 0, 0, 0);
            return eventDate < this.today;
        });
    }

    get groupedUpcomingEvents() {
        return this.groupEventsByDate(this.upcomingEvents);
    }

    get groupedPastEvents() {
        return this.groupEventsByDate(this.pastEvents);
    }

    get hasUpcomingEvents() {
        return Array.isArray(this.upcomingEvents) && this.upcomingEvents.length > 0;
    }

    get hasPastEvents() {
        return Array.isArray(this.pastEvents) && this.pastEvents.length > 0;
    }

    get limitedUpcomingEvents() {
        if (!this.upcomingEvents || !Array.isArray(this.upcomingEvents)) {
            return [];
        }

        const grouped = this.groupEventsByDate(this.upcomingEvents);
        const limitedEvents = this.limitEventsToThree(grouped);

         if (FORM_FACTOR === 'Large') {
            return limitedEvents.slice(0, 3);
        } else  {
            return limitedEvents.slice(0, 2);
        } 
    }

 get limitedPastEvents() {

    if (!this.pastEvents || !Array.isArray(this.pastEvents)) {
        return [];
    }

    const grouped = this.groupEventsByDate(this.pastEvents);

    const limitedEvents = this.limitEventsToThree(grouped);

    if (FORM_FACTOR === 'Large') {
        return limitedEvents.slice(0, 3);
    } else  {
        return limitedEvents.slice(0, 2);
    } 
}

    // get limitedPastEvents() {   
    //     const grouped = this.groupEventsByDate(this.pastEvents);
    //     return this.limitEventsToThree(grouped);
    // }

    limitEventsToThree(groupedEvents) {
        let eventCount = 0;
        const limited = [];

        for (const dateGroup of groupedEvents) {
            if (eventCount >= 3) break;

            const limitedEvents = [];
            for (const event of dateGroup.events) {
                if (eventCount >= 3) break;
                limitedEvents.push(event);
                eventCount++;
            }

            if (limitedEvents.length > 0) {
                limited.push({
                    ...dateGroup,
                    events: limitedEvents
                });
            }
        }

        return limited;
    }

    get isUpcomingActive() {
        return this.activeTab === 'upcoming';
    }

    get isPastActive() {
        return this.activeTab === 'past';
    }

    get upcomingTabClass() {
        return `tab-button ${this.isUpcomingActive ? 'active' : ''}`;
    }

    get pastTabClass() {
        return `tab-button ${this.isPastActive ? 'active' : ''}`;
    }

    // Group events by date
    groupEventsByDate(events) {
        const grouped = {};

        events.forEach(event => {
            if (!grouped[event.eventDate]) {
                grouped[event.eventDate] = [];
            }
            grouped[event.eventDate].push(event);
        });

        // Convert to array and format dates
        return Object.keys(grouped).map(date => ({
            date: date,
            formattedDate: this.formatDate(date),
            events: grouped[date]
        })).sort((a, b) => new Date(a.date) - new Date(b.date));
    }

    // Format date to "18th December 2023" format
    formatDate(dateString) {
        const date = new Date(dateString);
        const day = date.getDate();
        const month = date.toLocaleString('en-US', { month: 'long' });
        const year = date.getFullYear();

        // Add ordinal suffix to day
        const suffix = this.getOrdinalSuffix(day);

        return `${day}${suffix} ${month} ${year}`;
    }

    // Get ordinal suffix (st, nd, rd, th)
    getOrdinalSuffix(day) {
        if (day > 3 && day < 21) return 'th';
        switch (day % 10) {
            case 1: return 'st';
            case 2: return 'nd';
            case 3: return 'rd';
            default: return 'th';
        }
    }

    // Tab switching methods
    switchToUpcoming() {
        this.activeTab = 'upcoming';
    }

    switchToPast() {
        this.activeTab = 'past';
    }

    handleViewMore() {
        const state = {};
        if (this.isPastActive) {
            state.selectedTab = 'Completed';
        }

        const navConfig = {
            type: 'comm__namedPage',
            attributes: {
                name: 'registered_events__c'
            },
        };

        if (Object.keys(state).length) {
            navConfig.state = state;
        }

        this[NavigationMixin.Navigate](navConfig);
    }

    handleEventClick(event) {
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
}