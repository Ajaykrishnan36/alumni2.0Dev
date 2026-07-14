import { LightningElement, track, wire } from 'lwc';
import getAllEvents from '@salesforce/apex/KenPortalEventController.getAllEvents';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import mobileHtml from './allEventsMobile.html';
import desktopHtml from './kenAllEvents.html';
import FORM_FACTOR from '@salesforce/client/formFactor';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import SurveyEmptyImage from '@salesforce/resourceUrl/SurveyEmptyImage';

export default class KenAllEvents extends NavigationMixin(LightningElement) {
    SurveyEmptyImageUrl = SurveyEmptyImage;
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
        this.isMobile = FORM_FACTOR === 'Small';
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
        });
        const regularFontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Regular.woff2`;
        const boldFontUrl = `${basePath}/sfsites/c/resource/GeneralSansFont/fonts/GeneralSans-Light.woff2`;
        const style = document.createElement('style');
        style.innerText = `
            @font-face {
                font-family: 'GeneralSansCustom';
                src: url('${regularFontUrl}') format('woff2');
                font-style: normal;
                font-weight: 400;
                font-display: swap;
            }
    
            @font-face {
                font-family: 'GeneralSansCustomBold';
                src: url('${boldFontUrl}') format('woff2');
                font-style: normal;
                font-weight: 400;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);
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
    @track popupTop = 0;
    @track popupRight = 0;

    get computedPopupStyle() {
        return `top: ${this.popupTop}px; right: ${this.popupRight}px;`;
    }

    @track filterData = {
        eventType: '',
        createdBy: '',
        title: '',
        startDate: '',
        endDate: ''
    };
    @track activeFilters = [];
    @track searchTerm = '';

    get hasActiveFilters() {
        return this.activeFilters.length > 0;
    }

    get hasSearch() {
        return (this.searchTerm || '').trim() !== '';
    }

    // Either a filter or a search term switches the page into the results view.
    get showResultsView() {
        return this.hasActiveFilters || this.hasSearch;
    }

    get activeFiltersCount() {
        return this.activeFilters.length;
    }

    get filteredEventsCount() {
        return this.filteredEvents ? this.filteredEvents.length : 0;
    }

    // Results = all events narrowed by the active filters AND the search term.
    get filteredEvents() {
        if (!this.showResultsView) {
            return [];
        }
        const term = (this.searchTerm || '').trim().toLowerCase();
        let list = this.allEvents;
        if (this.activeFilters.length > 0) {
            list = list.filter(event => this.activeFilters.every(filter => this._matchesFilter(event, filter)));
        }
        if (term) {
            list = list.filter(event =>
                (event.title && event.title.toLowerCase().includes(term)) ||
                (event.location && event.location.toLowerCase().includes(term)) ||
                (event.eventType && event.eventType.toLowerCase().includes(term))
            );
        }
        return list;
    }

    _matchesFilter(event, filter) {
        switch (filter.field) {
            case 'eventType':
                return event.eventType && event.eventType.toLowerCase().includes(filter.value.toLowerCase());
            case 'createdBy':
                return event.createdBy === filter.value;
            case 'title':
                return event.title && event.title.toLowerCase().includes(filter.value.toLowerCase());
            case 'startDate':
                return event.startDate === filter.value;
            case 'endDate':
                return event.endDate === filter.value;
            default:
                return true;
        }
    }

    get isEventTypeEmpty() {
        return (this.filterData.eventType || '') === '';
    }
    get isEventTypeOneDay() {
        return this.filterData.eventType === 'One-day';
    }
    get isEventTypeMultiDay() {
        return this.filterData.eventType === 'Multi-day';
    }

    get isCreatedByEmpty() {
        return (this.filterData.createdBy || '') === '';
    }
    // Label for admin-created events ("By {Institution Alias}", or "By Admin"
    // when no alias is configured), derived from the loaded events.
    get adminCreatedByLabel() {
        const adminEvent = this.events.find(e => e.createdBy && e.createdBy !== 'By Alumni');
        return adminEvent ? adminEvent.createdBy : 'By Admin';
    }
    get isCreatedByAdmin() {
        return this.filterData.createdBy === this.adminCreatedByLabel;
    }
    get isCreatedByAlumni() {
        return this.filterData.createdBy === 'By Alumni';
    }

    get showFeaturedEvents() {
        return !this.showResultsView && this.hasFeaturedEvents;
    }

    get showUpcomingEvents() {
        return !this.showResultsView && this.hasUpcomingEvents;
    }

    get showNoDataEmptyState() {
        return !this.showResultsView && !this.hasFeaturedEvents && !this.hasUpcomingEvents;
    }

    get showNoFilterResultsEmptyState() {
        return this.showResultsView && (!this.filteredEvents || this.filteredEvents.length === 0);
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
        // Only events that haven't ended yet — the same cutoff the Upcoming
        // section applies. Search/filter results derive from this list too, so
        // search can no longer surface ended events the listing hides.
        const now = new Date();
        return this.events.filter(event => {
            const eventEndDateTime = new Date(`${event.endDate}T${event.endTime}`);
            return !isNaN(eventEndDateTime.getTime()) && eventEndDateTime >= now;
        });
    }

    get featuredEventsCount() {
        const count = this.futureEvents.filter(event => event.featuredEvents === true).length;
        console.log('Featured events count:', count);
        return count;
    }

    get upcomingEventsCount() {
        const now = new Date();
        const count = this.futureEvents.filter(event => {
            if (event.featuredEvents === true) return false;
            const eventEndDateTime = new Date(`${event.endDate}T${event.endTime}`);
            return eventEndDateTime >= now;
        }).length;
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

        const events = this.futureEvents
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
            // All multi-day events show as separate sessions (comma-separated)
            return `${startFormatted}, ${endFormatted}`;
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
        this.showFilterModal = !this.showFilterModal;
        if (this.showFilterModal) {
            // Position popup after render
            setTimeout(() => this.positionPopup(), 0);
        }
    }

    positionPopup() {
        const filterBtn = this.template.querySelector('[data-filter-btn="true"]');
        const popup = this.template.querySelector('.filters-popup');
        if (filterBtn && popup) {
            const rect = filterBtn.getBoundingClientRect();
            const popupWidth = 340;
            const viewportWidth = window.innerWidth;
            const viewportHeight = window.innerHeight;
            let top = rect.bottom + 8;
            let right = viewportWidth - rect.right;
            if (top + 450 > viewportHeight) {
                top = Math.max(8, rect.top - 450 - 8);
            }
            if (right + popupWidth > viewportWidth) {
                right = 24;
            }
            this.popupTop = top;
            this.popupRight = right;
        }
    }

    closeFilterModal() {
        this.showFilterModal = false;
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.filterData[field] = value;
        this.activeFilters = this._getActiveFiltersFromData();
    }

    resetFilterData() {
        this.filterData = {
            eventType: '',
            createdBy: '',
            title: '',
            startDate: '',
            endDate: ''
        };
        // Reset form fields
        const formFields = this.template.querySelectorAll('.form-control');
        formFields.forEach(field => {
            field.value = '';
        });
    }

    // Count only the 4 filter fields: eventType, title (trimmed), startDate, endDate
    _getActiveFiltersFromData() {
        const labels = { eventType: 'Event Type', createdBy: 'Created By', title: 'Title', startDate: 'Start Date', endDate: 'End Date' };
        const list = [];
        let id = 1;
        ['eventType', 'createdBy', 'title', 'startDate', 'endDate'].forEach(key => {
            let value = this.filterData[key];
            if (key === 'title') value = (value || '').trim();
            else if (value == null) value = '';
            if (value !== '') {
                list.push({ id: id++, field: key, label: labels[key], value: String(value) });
            }
        });
        return list;
    }

    applyFilters() {
        this.activeFilters = this._getActiveFiltersFromData();
        this.closeFilterModal();
    }

    handleClearFilters() {
        this.resetFilterData();
        this.activeFilters = [];
        this.closeFilterModal();
    }

    removeFilter(event) {
        const filterId = parseInt(event.currentTarget.dataset.filterId);
        const filterToRemove = this.activeFilters.find(f => f.id === filterId);

        if (filterToRemove) {
            this.filterData[filterToRemove.field] = '';
            this.activeFilters = this.activeFilters.filter(f => f.id !== filterId);
        }
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
    }

    clearSearch() {
        this.searchTerm = '';
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
}