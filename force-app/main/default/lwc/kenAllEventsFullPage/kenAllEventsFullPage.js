import { LightningElement, track, wire } from 'lwc';
import getAllEvents from '@salesforce/apex/KenPortalEventController.getAllEvents';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
// import mobileHtml from './allEventsMobile.html';
// import desktopHtml from './allEvents.html';
import FORM_FACTOR from '@salesforce/client/formFactor';
export default class KenAllEventsFullPage extends NavigationMixin(LightningElement) {
    //   render() {
    //     return FORM_FACTOR === 'Small' ? mobileHtml : desktopHtml;
    // }
isMobile = false;
    @track events = [];

    @wire(getAllEvents)

    wiredEvents({ error, data }) {
        if (data) {
            console.log('Events fetched successfully11111111:', data);
            // Process API data to match expected format
            this.events = data.map(event => ({
                ...event,
                // Convert milliseconds to time strings with fallback for missing fields
                startTime: event.startTime ? this.millisecondsToTimeString(event.startTime) : '00:00',
                endTime: event.endTime ? this.millisecondsToTimeString(event.endTime) : '00:00',
                // Add default location if missing
                location: event.location || 'Bangalore, India'
            }));
            console.log('Processed events:', JSON.parse(JSON.stringify(this.events)));
        } else if (error) {
            console.error('Error fetching events:', error);
        }
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
        this.isMobile = FORM_FACTOR === 'Small';
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
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }


    // Convert milliseconds to time string (HH:MM format)
    millisecondsToTimeString(milliseconds) {
        if (!milliseconds || isNaN(milliseconds)) return '00:00';

        try {
            // Convert milliseconds to a proper date object
            // Since these are time values, we need to treat them as time of day
            const totalMinutes = Math.floor(milliseconds / (1000 * 60));
            const hours = Math.floor(totalMinutes / 60);
            const minutes = totalMinutes % 60;

            console.log('Time conversion:', { milliseconds, totalMinutes, hours, minutes });

            const hoursStr = hours.toString().padStart(2, '0');
            const minutesStr = minutes.toString().padStart(2, '0');
            return `${hoursStr}:${minutesStr}`;
        } catch (error) {
            console.error('Error converting milliseconds to time:', error);
            return '00:00';
        }
    }

    @track showFilterModal = false;
    @track filterData = {
        eventType: '',
        title: '',
        startDate: '',
        endDate: '',
        location: ''
    };
    @track activeFilters = [];
    @track filteredEvents = [];

    get hasActiveFilters() {
        return this.activeFilters.length > 0;
    }

    get activeFiltersCount() {
        return this.activeFilters.length;
    }

   get showFeaturedEvents() {
    return !this.hasActiveFilters && this.hasFeaturedEvents;
}

get showUpcomingEvents() {
    return !this.hasActiveFilters 
        && this.hasUpcomingEvents 
        && !this.upcomingEvents?.length > 0;
}

get showFilterInFeatured() {
    return !this.hasActiveFilters && this.hasFeaturedEvents;
}

get showAllEvents() {   
    // Show all events only if no filters are applied
    // and either no featured or no upcoming events are shown
    return !this.hasActiveFilters && (
        !this.showFeaturedEvents || !this.showUpcomingEvents
    );
}


    get showFilterInUpcoming() {
        return !this.hasActiveFilters && !this.hasFeaturedEvents && this.hasUpcomingEvents;
    }

    get hasFeaturedEvents() {
        return this.featuredEventsCount > 0;
    }

    get hasUpcomingEvents() {
        return this.upcomingEventsCount > 0;
    }

    get today() {
        const today = new Date();
        today.setHours(0, 0, 0, 0); // Set to start of day for accurate comparison
        return today;
    }

    get futureEvents() {
        console.log('All events:', this.events);
        console.log('Today:', this.today);

        // Show all events (removing date filter for now)
        return this.events;
    }

    get featuredEventsCount() {
        const count = this.futureEvents.filter(event => event.featuredEvents === true).length;
        console.log('Featured events count:', count);
        return count;
    }

    get upcomingEventsCount() {
        const count = this.futureEvents.filter(event => event.featuredEvents === false).length;
        console.log('Upcoming events count:', count);
        return count;
    }

    get featuredEvents() {
        const events = this.futureEvents.filter(event => event.featuredEvents === true).map(event => ({
            ...event,
            formattedDateRange: this.formatDateRange(event.startDate, event.endDate),
            formattedTimeRange: this.formatTimeRange(event.startTime, event.endTime)
        }));
        console.log('Featured events:', events);
        return events;
    }

    get upcomingEvents() {
        const now = new Date();
    
        let events = this.futureEvents
            .filter(event => {
                const eventEndDateTime = new Date(`${event.endDate}T${event.endTime}`);
                return event.featuredEvents === false && eventEndDateTime >= now;
            })
            .map(event => ({
                ...event,
                formattedDateRange: this.formatDateRange(event.startDate, event.endDate),
                formattedTimeRange: this.formatTimeRange(event.startTime, event.endTime)
            }));
    
        
    
        return events;
    }
    
    get allEvents() {
        return this.futureEvents.map(event => ({
            ...event,
            formattedDateRange: this.formatDateRange(event.startDate, event.endDate),
            formattedTimeRange: this.formatTimeRange(event.startTime, event.endTime)
        }));
    }

    formatDateRange(startDate, endDate) {
        const start = new Date(startDate);
        const end = new Date(endDate);

        const startFormatted = this.formatDate(start);
        const endFormatted = this.formatDate(end);

        if (startDate === endDate) {
            return startFormatted;
        } else {
            return `${startFormatted} - ${endFormatted}`;
        }
    }

    formatDate(date) {
        const day = date.getDate().toString().padStart(2, '0');
        const month = (date.getMonth() + 1).toString().padStart(2, '0');
        const year = date.getFullYear().toString().slice(-2);
        return `${day} ${this.getMonthName(date.getMonth())} ${year}`;
    }

    getMonthName(monthIndex) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return months[monthIndex];
    }

    formatTimeRange(startTime, endTime) {
        const startFormatted = this.formatTime(startTime);
        const endFormatted = this.formatTime(endTime);
        return `${startFormatted} - ${endFormatted}`;
    }

    formatTime(timeString) {
        const [hours, minutes] = timeString.split(':');
        const hour = parseInt(hours);
        const ampm = hour >= 12 ? 'Pm' : 'Am';
        const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
        return `${displayHour}${minutes === '00' ? '' : ':' + minutes}${ampm}`;
    }

    openFilterModal() {
        this.showFilterModal = true;
    }

    closeFilterModal() {
        this.showFilterModal = false;
        // Reset filter data when closing without applying
        this.resetFilterData();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.filterData[field] = value;
        this._applyFiltersFromData();
    }

    resetFilterData() {
        this.filterData = {
            eventType: '',
            title: '',
            startDate: '',
            endDate: '',
            location: ''
        };
        // Reset form fields
        const formFields = this.template.querySelectorAll('.form-control');
        formFields.forEach(field => {
            field.value = '';
        });
    }

    _applyFiltersFromData() {
        // Create active filters array
        this.activeFilters = [];
        let filterId = 1;

        Object.keys(this.filterData).forEach(key => {
            if (this.filterData[key]) {
                let label = '';
                switch (key) {
                    case 'eventType':
                        label = 'Event Type';
                        break;
                    case 'title':
                        label = 'Title';
                        break;
                    case 'startDate':
                        label = 'Start Date';
                        break;
                    case 'endDate':
                        label = 'End Date';
                        break;
                    case 'location':
                        label = 'Location';
                        break;
                }

                this.activeFilters.push({
                    id: filterId++,
                    field: key,
                    label: label,
                    value: this.filterData[key]
                });
            }
        });

        // Apply filtering logic to all events
        this.filteredEvents = this.allEvents.filter(event => {
            return this.activeFilters.every(filter => {
                switch (filter.field) {
                    case 'eventType':
                        return event.eventType.toLowerCase().includes(filter.value.toLowerCase());
                    case 'title':
                        return event.title.toLowerCase().includes(filter.value.toLowerCase());
                    case 'location':
                        return event.location.toLowerCase().includes(filter.value.toLowerCase());
                    case 'startDate':
                        return event.startDate === filter.value;
                    case 'endDate':
                        return event.endDate === filter.value;
                    default:
                        return true;
                }
            });
        });
    }

    applyFilters() {
        this._applyFiltersFromData();
        this.closeFilterModal();
    }

    removeFilter(event) {
        const filterId = parseInt(event.currentTarget.dataset.filterId);
        const filterToRemove = this.activeFilters.find(f => f.id === filterId);

        if (filterToRemove) {
            // Remove from active filters
            this.activeFilters = this.activeFilters.filter(f => f.id !== filterId);

            // Clear the corresponding filter data
            this.filterData[filterToRemove.field] = '';

            // Reapply remaining filters
            if (this.activeFilters.length > 0) {
                this.applyFilters();
            } else {
                // No more filters, show all events
                this.filteredEvents = [];
            }
        }
    }

    handleEventClick(event) {
        const eventId = event.currentTarget.dataset.id;
        const selectedEvent = this.events.find(e => e.id === parseInt(eventId));

        if (selectedEvent) {
            // Navigate to event details page or handle click logic
            console.log('Selected event:', selectedEvent);
            // Implement navigation logic here if needed
        }

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
  get upcomingEventsLength() {
    return this.upcomingEvents.length;
}
navigateToEventsHome(){
    this[NavigationMixin.Navigate]({
        type: 'comm__namedPage',
        attributes: {
            name: 'all_events__c'
        },
    });
}
}