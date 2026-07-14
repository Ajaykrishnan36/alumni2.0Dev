import { LightningElement, api, track } from 'lwc';
import AlumniAlt from '@salesforce/resourceUrl/AlumniAlt';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];

export default class KenMentorshipScheduleList extends LightningElement {
    @api scheduleEvents = [];
    @track showScheduleModal = false;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    get groupedSchedule() {
        if (!this.scheduleEvents || this.scheduleEvents.length === 0) {
            return [];
        }
        const normalized = this.scheduleEvents.map(evt => this._normalizeEvent(evt)).filter(Boolean);
        const byDate = {};
        normalized.forEach(evt => {
            const key = evt.dateValue;
            if (!byDate[key]) {
                byDate[key] = { dateValue: key, dateLabel: evt.dateLabel, events: [] };
            }
            byDate[key].events.push(evt);
        });
        return Object.values(byDate).sort((a, b) => b.dateValue.localeCompare(a.dateValue));
    }

    get isEmpty() {
        return !this.scheduleEvents || this.scheduleEvents.length === 0;
    }

    _normalizeEvent(evt) {
        if (!evt) return null;
        let dateValue, dateLabel, timeLabel;
        if (evt.date instanceof Date) {
            const d = evt.date;
            dateValue = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
            dateLabel = evt.dateLabel || `${d.getDate()} ${MONTH_NAMES[d.getMonth()]}, ${d.getFullYear()}`;
        } else if (typeof evt.date === 'string') {
            dateValue = evt.date;
            const parts = evt.date.split('-');
            if (parts.length === 3) {
                dateLabel = evt.dateLabel || `${parseInt(parts[2], 10)} ${MONTH_NAMES[parseInt(parts[1], 10) - 1]}, ${parts[0]}`;
            } else {
                dateLabel = evt.dateLabel || evt.date;
            }
        } else {
            return null;
        }
        if (evt.time) {
            timeLabel = evt.time;
        } else if (evt.startTime && evt.endTime) {
            timeLabel = `${evt.startTime} - ${evt.endTime}`;
        } else {
            timeLabel = '';
        }
        const status = this._normalizeStatus(evt.status);
        return {
            id: evt.id,
            title: evt.title,
            mentorName: evt.mentor || evt.mentorName,
            mentorAvatar: evt.mentorImage || evt.mentorAvatar || AlumniAlt,
            dateValue,
            dateLabel,
            timeLabel,
            topic: evt.topic || null,
            note: evt.status === 'awaiting' || status === 'pending' ? 'Your mentor will confirm the session soon.' : null,
            isLive: status === 'live',
            isPending: status === 'pending',
            isCompleted: status === 'completed',
            isRequested: status === 'requested',
            isUpcoming: status === 'upcoming'
        };
    }

    _normalizeStatus(status) {
        const map = {
            live: 'live',
            happening: 'live',
            pending: 'pending',
            awaiting: 'pending',
            completed: 'completed',
            requested: 'requested',
            request: 'requested',
            upcoming: 'upcoming'
        };
        return (map[status] || 'upcoming');
    }

    handleScheduleCall() {
        this.showScheduleModal = true;
    }

    handleCloseScheduleModal() {
        this.showScheduleModal = false;
    }

    handleSendRequest(event) {
        const requestData = event.detail;
        console.log('Schedule call request:', requestData);
    }

    handleLeaveFeedback(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('leavefeedback', { detail: { id }, bubbles: true, composed: true }));
    }

    handleViewRequest(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('viewrequest', { detail: { id }, bubbles: true, composed: true }));
    }
}