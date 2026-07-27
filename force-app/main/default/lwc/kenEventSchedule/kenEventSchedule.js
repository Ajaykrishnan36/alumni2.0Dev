import { LightningElement, track, wire, api } from 'lwc';
import getEventSchedules from '@salesforce/apex/KenPortalEventController.getEventSchedules';
import defaultProfileImage from '@salesforce/resourceUrl/defaultProfileImage';
import CancelSessionRegistration from '@salesforce/apex/KenPortalEventController.cancelRegistrations';
import { refreshApex } from '@salesforce/apex';

export default class KenEventSchedule extends LightningElement {

    @api recordId;
    @track schedules = [];
    @track wiredEventScheduleResponse = [];
    selectedSessionId;
    showCancelConfirmation = false;

    get showSpinner() {
        return !this.schedules;
    }

    get defaultProfileImage() {
        return defaultProfileImage;
    }

    // Group schedules by date
    get groupedSchedules() {
        const map = {};
        if (!this.schedules) return [];
        this.schedules.forEach(sch => {
            if (!map[sch.sessionDate]) {
                map[sch.sessionDate] = [];
            }
            map[sch.sessionDate].push(sch);
        });
        // Return as array of { date, schedules }
        return Object.keys(map).sort().map(date => ({
            date,
            schedules: map[date]
        }));
    }

    @wire(getEventSchedules, { eventId: '$recordId' })
    wiredEventSchedules(response) {
        this.wiredEventScheduleResponse = response;
        const { error, data } = response;
        if (data) {
            this.processSchedules(data);
        } else if (error) {
            console.error('Error fetching event schedules:', error);
        }
    }

    @api async refreshSchedules() {
        try {
            await refreshApex(this.wiredEventScheduleResponse);
        } catch (error) {
            console.error('Error refreshing schedules:', error);
        }
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.schedules = this.schedules.map((item, i) => {
            const willExpand = item.id == id ? !item.expanded : false;
            return {
                ...item,
                expanded: willExpand,
                expandedIcon: willExpand ? 'utility:chevronup' : 'utility:chevrondown',
                cardClass: willExpand ? 'schedule-item-card expanded' : 'schedule-item-card'
            };
        });
    }

    handleCancelRegistration(event) {
        this.selectedSessionId = event.target.dataset.id;
        this.showCancelConfirmation = true;
    }

    handleCancelButtonMouseDown(event) {
        // Prevent event bubbling to parent div
        event.stopPropagation();
    }

    async handleFinalCancel() {
        try {
            await CancelSessionRegistration({ sessionIds: [this.selectedSessionId] });
            await this.refreshSchedules();
            this.selectedSessionId = null;
            this.showCancelConfirmation = false;
        } catch (error) {
            console.error('Error cancelling registration:', error);
        }
    }

    handleBackToSelection() {
        this.selectedSessionId = null;
        this.showCancelConfirmation = false;
    }

    processSchedules(data) {
        if (!data || data.length === 0) return [];

        const sorted = [...data].sort((a, b) => {
            const aDateTime = this.getDateTime(a.sessionDate, a.startTime);
            const bDateTime = this.getDateTime(b.sessionDate, b.startTime);
            return aDateTime - bDateTime;
        });

        this.schedules = sorted.map((item, index) => {
            // Get speaker names
            const speakerNames = item.speakers && item.speakers.length > 0
                ? item.speakers.map(s => s.name).join(', ')
                : null;

            const locationType = (item.locationType || '').toLowerCase();
            const isOnline = locationType === 'online';
            const isOffline = locationType === 'offline' || locationType === 'onsite';
            const isHybrid = locationType === 'hybrid';
            const venueAddress = item.location || item.venue || null;
            const sessionLink = item.sessionLink || null;

            return {
                ...item,
                startTime: item.startTime ? this.formatTime(item.startTime) : null,
                endTime: item.endTime ? this.formatTime(item.endTime) : null,
                sessionDate: item.sessionDate ? this.formatDate(item.sessionDate) : null,
                isCompleted: this.checkIsCompleted(item),
                sessionNumber: index + 1,
                hasSpeakers: item.speakers && item.speakers.length > 0,
                speakerNames: speakerNames,
                location: venueAddress,
                venueAddress: venueAddress,
                sessionLink: sessionLink,
                locationType: locationType,
                showVenue: (isOffline || isHybrid) && !!venueAddress,
                // Meeting link renders only for registered users (Apex also blanks
                // sessionLink for unregistered users — this is defence in depth).
                showLink: item.isRegistered === true && (isOnline || isHybrid) && !!sessionLink,
                price: item.price || item.sessionPrice || null,
                gradientId: `registeredGradient${item.id || index}`,
                expanded: false,
                expandedIcon: 'utility:chevrondown',
                cardClass: 'schedule-item-card'
            };
        });

        if (this.schedules.length > 0) {
            this.schedules = this.schedules.map((item, index) => ({
                ...item,
                expanded: index === 0 || item.expanded,
                expandedIcon: index === 0 ? 'utility:chevronup' : item.expandedIcon,
                cardClass: (index === 0 || item.expanded) ? 'schedule-item-card expanded' : 'schedule-item-card'
            }));
        }
    }

    checkIsCompleted(item) {
    if (!item.sessionDate || item.startTime == null) {
        return false;
    }

    const sessionDateObj = new Date(item.sessionDate);
    const sessionDateTime = new Date(sessionDateObj);

    sessionDateTime.setMilliseconds(item.startTime);

    return new Date() > sessionDateTime;
    }


    getDateTime(dateStr, millisFromMidnight) {
        const date = new Date(dateStr);
        return new Date(date.getTime() + millisFromMidnight);
    }

    formatTime(milliseconds) {
        const date = new Date(0);
        date.setMilliseconds(milliseconds);

        let hours = date.getUTCHours();
        const minutes = date.getUTCMinutes();

        const ampm = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12 || 12;

        const minutesStr = minutes.toString().padStart(2, '0');

        return `${hours}:${minutesStr} ${ampm}`;
    }

    formatDate(dateStr) {
        const date = new Date(dateStr);
        const day = date.getDate().toString().padStart(2, '0');
        const year = date.getFullYear().toString();
        return `${day} ${this.getMonthName(date.getMonth())} ${year}`;
    }

    getMonthName(monthIndex) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return months[monthIndex]; 
    } 
}