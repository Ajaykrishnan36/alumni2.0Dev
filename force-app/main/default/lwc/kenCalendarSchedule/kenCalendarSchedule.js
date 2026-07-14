import { LightningElement, api, track } from 'lwc';
import CalendarEmptyState from '@salesforce/resourceUrl/CalendarEmptyState';
import AlumniAlt from '@salesforce/resourceUrl/AlumniAlt';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

function normalizeDate(d) {
    if (!d) return null;
    const date = d instanceof Date ? d : new Date(d);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function sameDay(a, b) {
    if (!a || !b) return false;
    const d1 = normalizeDate(a);
    const d2 = normalizeDate(b);
    return d1.getDate() === d2.getDate() && d1.getMonth() === d2.getMonth() && d1.getFullYear() === d2.getFullYear();
}

export default class KenCalendarSchedule extends LightningElement {
    @api selectedDate;
    @api scheduleEvents = [];
    @api mentorOptions = [];
    @api menteeOptions = [];
    @api isSubmittingCallRequest = false;
    @api isRespondingCallRequest = false;
    @api callRequestError = '';

    @track currentMonth;
    @track currentYear;
    @track weekDays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    @track calendarDays = [];
    @track internalSelectedDate;
    @track showScheduleModal = false;
    @track showRequestModal = false;
    @track showRescheduleModal = false;
    @track selectedRequestEvent = null;
    @track rescheduleDate = '';
    @track rescheduleStartTime = '';
    @track rescheduleEndTime = '';

    _previousScheduleEvents = null;
    _previousSelectedDate = null;
    // Once the user clicks a day themselves we stop auto-selecting.
    _userPickedDate = false;

    get eventDates() {
        if (!this.scheduleEvents || !this.scheduleEvents.length) return [];
        const seen = new Set();
        const out = [];
        this.scheduleEvents.forEach(evt => {
            if (!evt || !evt.date) return;
            const d = normalizeDate(evt.date);
            const key = d.getTime();
            if (!seen.has(key)) {
                seen.add(key);
                out.push(d);
            }
        });
        return out;
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => { });
        const defaultDate = new Date();
        this.internalSelectedDate = this.selectedDate ? normalizeDate(this.selectedDate) : new Date(defaultDate.getFullYear(), defaultDate.getMonth(), defaultDate.getDate());
        this.currentMonth = this.internalSelectedDate.getMonth();
        this.currentYear = this.internalSelectedDate.getFullYear();
        this.generateCalendar();
    }

    renderedCallback() {
        // The schedule card list is rendered from the reactive displayEvents getter,
        // so it never needs manual recompute here. We only regenerate the calendar grid
        // (event dots + selected highlight) when scheduleEvents or selectedDate change.
        // The guard prevents an infinite render loop (generateCalendar mutates calendarDays).
        const scheduleEventsChanged = this._previousScheduleEvents === null ||
            this.scheduleEvents.length !== this._previousScheduleEvents.length ||
            this.scheduleEvents !== this._previousScheduleEvents;

        const selectedDateChanged = this.selectedDate &&
            (this._previousSelectedDate === null ||
                this.selectedDate.getTime() !== this._previousSelectedDate.getTime());

        if (scheduleEventsChanged || selectedDateChanged) {
            if (selectedDateChanged && this.selectedDate) {
                this.internalSelectedDate = normalizeDate(this.selectedDate);
                this.currentMonth = this.internalSelectedDate.getMonth();
                this.currentYear = this.internalSelectedDate.getFullYear();
            }
            // The list is day-scoped, so a default of "today" reads as empty
            // whenever the calls sit on other days (while the calendar dots show
            // them). Until the user picks a day, follow the nearest day that
            // actually has a call.
            if (scheduleEventsChanged && !this._userPickedDate && this.scheduleEvents.length) {
                const hasEventsOnSelected = this.scheduleEvents.some(
                    evt => evt && evt.date && sameDay(normalizeDate(evt.date), this.internalSelectedDate)
                );
                if (!hasEventsOnSelected) {
                    const nearest = this._nearestEventDate();
                    if (nearest) {
                        this.internalSelectedDate = nearest;
                        this.currentMonth = nearest.getMonth();
                        this.currentYear = nearest.getFullYear();
                    }
                }
            }
            this.generateCalendar();
            this._previousScheduleEvents = this.scheduleEvents;
            this._previousSelectedDate = this.selectedDate ? normalizeDate(this.selectedDate) : null;
        }
    }

    // Nearest day with a call: the next upcoming one, or the most recent past
    // one when nothing upcoming exists.
    _nearestEventDate() {
        const today = normalizeDate(new Date());
        let nextUpcoming = null;
        let latestPast = null;
        this.eventDates.forEach(d => {
            if (d >= today) {
                if (!nextUpcoming || d < nextUpcoming) nextUpcoming = d;
            } else if (!latestPast || d > latestPast) {
                latestPast = d;
            }
        });
        return nextUpcoming || latestPast;
    }

    get currentMonthYear() {
        const monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'];
        return `${monthNames[this.currentMonth]} ${this.currentYear}`;
    }

    get formattedSelectedDate() {
        const monthNames = ['January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'];
        const date = this.internalSelectedDate || (this.selectedDate ? normalizeDate(this.selectedDate) : new Date());
        return `${date.getDate()} ${monthNames[date.getMonth()]}, ${date.getFullYear()}`;
    }

    get datePickerValue() {
        const d = this.internalSelectedDate || (this.selectedDate ? normalizeDate(this.selectedDate) : new Date());
        if (!d) return '';
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${y}-${m}-${day}`;
    }

    get isScheduleCallDisabled() {
        const selected = this.internalSelectedDate || (this.selectedDate ? normalizeDate(this.selectedDate) : null);
        if (!selected) {
            return false;
        }
        const today = normalizeDate(new Date());
        return selected < today;
    }

    get scheduleCallButtonTitle() {
        return this.isScheduleCallDisabled
            ? 'You cannot schedule a call for a past date.'
            : 'Schedule A Call';
    }

    generateCalendar() {
        const firstDay = new Date(this.currentYear, this.currentMonth, 1);
        const lastDay = new Date(this.currentYear, this.currentMonth + 1, 0);
        const daysInMonth = lastDay.getDate();
        const startingDayOfWeek = firstDay.getDay();

        this.calendarDays = [];

        // Add empty cells for days before the first day of the month
        for (let i = 0; i < startingDayOfWeek; i++) {
            this.calendarDays.push({
                key: `empty-${i}`,
                day: '',
                class: 'calendar-day empty',
                dateString: ''
            });
        }

        // Add days of the month
        for (let day = 1; day <= daysInMonth; day++) {
            const date = new Date(this.currentYear, this.currentMonth, day);
            const dateString = `${day}-${this.currentMonth}-${this.currentYear}`;
            const hasEvent = this.hasEventOnDate(date);
            const isSelected = this.isSelectedDate(date);

            let dayClass = 'calendar-day';
            if (isSelected) {
                dayClass += ' selected';
            } else if (hasEvent) {
                dayClass += ' has-event';
            }

            this.calendarDays.push({
                key: `day-${day}`,
                day: day,
                class: dayClass,
                dateString: dateString,
                date: date
            });
        }
    }

    hasEventOnDate(date) {
        const dates = this.eventDates;
        return dates.some(d => d.getDate() === date.getDate() && d.getMonth() === date.getMonth() && d.getFullYear() === date.getFullYear());
    }

    isSelectedDate(date) {
        const selected = this.internalSelectedDate;
        if (!selected) return false;
        return date.getDate() === selected.getDate() && date.getMonth() === selected.getMonth() && date.getFullYear() === selected.getFullYear();
    }

    // Pure getter so the schedule list always reflects the latest scheduleEvents.
    // Previously this was cached into a tracked property and only refreshed via a
    // manual diff in renderedCallback, which left the card stale (e.g. still showing
    // "View Request" after an accept) until a full page refresh.
    get displayEvents() {
        const selected = this.internalSelectedDate;
        if (!selected || !this.scheduleEvents || this.scheduleEvents.length === 0) {
            return [];
        }
        return this.scheduleEvents
            .filter(event => {
                if (!event || !event.date) return false;
                const eventDate = normalizeDate(event.date);
                return sameDay(eventDate, selected);
            })
            .map(event => {
                const isOnlineMeeting = String(event.meetingType || '').trim().toLowerCase() === 'online';
                const hasMeetingLink = !!(event.meetingLink && String(event.meetingLink).trim());
                const isHappening = event.status === 'happening';
                const isVideo = event.status === 'video';
                return {
                    ...event,
                    isHappening,
                    isAwaiting: event.status === 'awaiting',
                    isRequest: event.status === 'request',
                    isCompleted: event.status === 'completed',
                    isVideo,
                    // Show the join-video icon (which opens the meeting link) whenever a call is
                    // live (happening) or in the video state, is an Online meeting, and has a link.
                    showJoinIcon: (isHappening || isVideo) && isOnlineMeeting && hasMeetingLink,
                    canRespond: event.canRespond === true,
                    showFeedback: event.status === 'completed' &&
                        event.hasFeedbackForm === true && event.feedbackSubmitted !== true,
                    mentorImage: event.mentorImage || AlumniAlt,
                    note: event.status === 'awaiting' ? 'Your mentor will confirm the session soon.' : null
                };
            });
    }

    get showEmptySchedule() {
        return !this.displayEvents || this.displayEvents.length === 0;
    }

    get emptyCalendarImageUrl() {
        return CalendarEmptyState;
    }

    get hasSelectedRequest() {
        return !!this.selectedRequestEvent;
    }

    get preferredSlotLabel() {
        if (!this.selectedRequestEvent) {
            return '';
        }
        const dateLabel = this.formatDateForDisplay(this.selectedRequestEvent.dateIso);
        return `${dateLabel} | ${this.selectedRequestEvent.time || ''}`;
    }

    get requestMeetingLink() {
        if (!this.selectedRequestEvent) {
            return '';
        }
        return this.selectedRequestEvent.meetingType === 'Online'
            ? (this.selectedRequestEvent.meetingLink || '')
            : (this.selectedRequestEvent.meetingLocation || '');
    }

    get requestModalDescription() {
        return this.selectedRequestEvent?.meetingDescription || this.selectedRequestEvent?.topic || '';
    }

    get requestModalTitle() {
        return this.selectedRequestEvent?.title || 'Call request';
    }

    get rescheduleModalTitle() {
        const personName = this.selectedRequestEvent?.mentor || '';
        return personName ? `Re-schedule a Call with ${personName}` : 'Re-schedule a Call';
    }

    get isRescheduleUpdateDisabled() {
        return this.isRespondingCallRequest ||
            !this.rescheduleDate ||
            !this.rescheduleStartTime ||
            !this.rescheduleEndTime;
    }

    get minimumDate() {
        const today = new Date();
        return today.toISOString().split('T')[0];
    }

    formatDateForDisplay(dateIso) {
        if (!dateIso) {
            return '';
        }
        const parts = String(dateIso).split('-').map((value) => Number(value));
        if (parts.length !== 3 || parts.some((value) => Number.isNaN(value))) {
            return dateIso;
        }
        const dt = new Date(parts[0], parts[1] - 1, parts[2]);
        const day = String(dt.getDate()).padStart(2, '0');
        const month = dt.toLocaleString('en-US', { month: 'short' });
        const year = dt.getFullYear();
        return `${day} ${month}, ${year}`;
    }

    handlePreviousMonth() {
        if (this.currentMonth === 0) {
            this.currentMonth = 11;
            this.currentYear--;
        } else {
            this.currentMonth--;
        }
        this.generateCalendar();
    }

    handleNextMonth() {
        if (this.currentMonth === 11) {
            this.currentMonth = 0;
            this.currentYear++;
        } else {
            this.currentMonth++;
        }
        this.generateCalendar();
    }

    handleDateClick(event) {
        const dateString = event.currentTarget.dataset.date;
        if (!dateString) return;

        const [day, month, year] = dateString.split('-').map(Number);
        const selectedDate = new Date(year, month, day);

        this._userPickedDate = true;
        this.internalSelectedDate = selectedDate;
        this.generateCalendar();

        this.dispatchEvent(new CustomEvent('datechange', {
            detail: { date: selectedDate },
            bubbles: true,
            composed: true
        }));
    }

    handleDatePickerChange(event) {
        const value = (event.detail && event.detail.value !== undefined) ? event.detail.value : (event.target && event.target.value);
        if (!value) return;
        const [year, month, day] = value.split('-').map(Number);
        const selectedDate = new Date(year, month - 1, day);
        this.internalSelectedDate = selectedDate;
        this.currentMonth = selectedDate.getMonth();
        this.currentYear = selectedDate.getFullYear();
        this.generateCalendar();
        this.dispatchEvent(new CustomEvent('datechange', {
            detail: { date: selectedDate },
            bubbles: true,
            composed: true
        }));
    }

    handleScheduleCall() {
        if (this.isScheduleCallDisabled) {
            return;
        }
        this.showScheduleModal = true;
    }

    handleCloseScheduleModal() {
        this.showScheduleModal = false;
    }

    handleSendRequest(event) {
        event.stopPropagation();
        const requestData = event?.detail;
        if (!requestData) {
            return;
        }
        this.dispatchEvent(new CustomEvent('sendrequest', {
            detail: requestData,
            bubbles: true,
            composed: true
        }));
    }

    handleShowToast(event) {
        event.stopPropagation();
        const toastDetail = event?.detail;
        if (!toastDetail || !toastDetail.message) {
            return;
        }
        this.dispatchEvent(new CustomEvent('showtoast', {
            detail: toastDetail,
            bubbles: true,
            composed: true
        }));
    }

    handleJoinVideoCall(event) {
        event.stopPropagation();
        const callRequestId = event?.currentTarget?.dataset?.id;
        if (!callRequestId) {
            return;
        }
        const targetEvent = (this.displayEvents || []).find((row) => String(row.id) === String(callRequestId));
        const link = targetEvent ? targetEvent.meetingLink : '';
        if (!link) {
            this.dispatchEvent(new CustomEvent('showtoast', {
                detail: { title: 'No meeting link', message: 'No video link is available for this call yet.', variant: 'error' },
                bubbles: true,
                composed: true
            }));
            return;
        }
        const url = /^https?:\/\//i.test(link) ? link : `https://${link}`;
        window.open(url, '_blank', 'noopener,noreferrer');
    }

    handleLeaveFeedback(event) {
        event.stopPropagation();
        const callRequestId = event?.currentTarget?.dataset?.id;
        if (!callRequestId) {
            return;
        }
        // Feedback is taken through the survey module (single feedback surface).
        // The parent navigates there with this call's id and a returnUrl.
        this.dispatchEvent(new CustomEvent('takefeedback', {
            detail: { recordId: callRequestId },
            bubbles: true,
            composed: true
        }));
    }

    handleViewRequest(event) {
        event.stopPropagation();
        const callRequestId = event?.currentTarget?.dataset?.id;
        if (!callRequestId) {
            return;
        }
        const targetEvent = (this.displayEvents || []).find((row) => String(row.id) === String(callRequestId));
        if (!targetEvent) {
            return;
        }
        this.selectedRequestEvent = { ...targetEvent };
        this.rescheduleDate = targetEvent.dateIso || '';
        this.rescheduleStartTime = targetEvent.startTime || '';
        this.rescheduleEndTime = targetEvent.endTime || '';
        this.showRequestModal = true;
    }

    handleCloseRequestModal() {
        this.showRequestModal = false;
        this.showRescheduleModal = false;
        this.selectedRequestEvent = null;
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleAcceptRequest() {
        if (!this.selectedRequestEvent || this.isRespondingCallRequest) {
            return;
        }
        this.dispatchEvent(new CustomEvent('respondcallrequest', {
            detail: { callRequestId: this.selectedRequestEvent.id, action: 'accept' },
            bubbles: true,
            composed: true
        }));
        this.handleCloseRequestModal();
    }

    handleDeclineRequest() {
        if (!this.selectedRequestEvent || this.isRespondingCallRequest) {
            return;
        }
        this.dispatchEvent(new CustomEvent('respondcallrequest', {
            detail: { callRequestId: this.selectedRequestEvent.id, action: 'reject' },
            bubbles: true,
            composed: true
        }));
        this.handleCloseRequestModal();
    }

    handleOpenRescheduleModal() {
        if (!this.selectedRequestEvent) {
            return;
        }
        this.showRequestModal = false;
        this.showRescheduleModal = true;
    }

    handleCloseRescheduleModal() {
        this.showRescheduleModal = false;
        this.showRequestModal = this.hasSelectedRequest;
    }

    handleRescheduleDateChange(event) {
        this.rescheduleDate = event?.detail?.value || event?.target?.value || '';
    }

    handleRescheduleStartTimeChange(event) {
        this.rescheduleStartTime = event?.detail?.value || event?.target?.value || '';
    }

    handleRescheduleEndTimeChange(event) {
        this.rescheduleEndTime = event?.detail?.value || event?.target?.value || '';
    }

    handleUpdateReschedule() {
        if (!this.selectedRequestEvent || this.isRescheduleUpdateDisabled) {
            return;
        }

        const selected = new Date(`${this.rescheduleDate}T00:00:00`);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        if (selected < today) {
            this.dispatchEvent(new CustomEvent('showtoast', {
                detail: { title: 'Error', message: 'You cannot schedule a call for a past date.', variant: 'error' },
                bubbles: true,
                composed: true
            }));
            return;
        }

        if (this.timeToMinutes(this.rescheduleEndTime) <= this.timeToMinutes(this.rescheduleStartTime)) {
            this.dispatchEvent(new CustomEvent('showtoast', {
                detail: { title: 'Error', message: 'End time must be after start time.', variant: 'error' },
                bubbles: true,
                composed: true
            }));
            return;
        }

        this.dispatchEvent(new CustomEvent('reschedulecallrequest', {
            detail: {
                callRequestId: this.selectedRequestEvent.id,
                meetingDate: this.rescheduleDate,
                startTime: this.rescheduleStartTime,
                endTime: this.rescheduleEndTime
            },
            bubbles: true,
            composed: true
        }));
        this.handleCloseRequestModal();
    }

    timeToMinutes(value) {
        if (!value) {
            return 0;
        }
        const [hour = '0', minute = '0'] = String(value).split(':');
        return Number(hour) * 60 + Number(minute);
    }

    handleRespondCallRequest(event) {
        event.stopPropagation();
        const callRequestId = event?.currentTarget?.dataset?.id;
        const action = event?.currentTarget?.dataset?.action;
        if (!callRequestId || !action || this.isRespondingCallRequest) {
            return;
        }
        this.dispatchEvent(new CustomEvent('respondcallrequest', {
            detail: { callRequestId, action },
            bubbles: true,
            composed: true
        }));
    }
}