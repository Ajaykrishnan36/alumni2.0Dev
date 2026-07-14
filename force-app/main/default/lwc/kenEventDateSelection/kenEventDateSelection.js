import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { updateRecord } from 'lightning/uiRecordApi';
import getEventSchedule from '@salesforce/apex/KenEventFormController.getEventSchedule';
import START_DATE_FIELD from '@salesforce/schema/Ken_Event_Master__c.Start_Date__c';
import END_DATE_FIELD from '@salesforce/schema/Ken_Event_Master__c.End_Date__c';
import ID_FIELD from '@salesforce/schema/Ken_Event_Master__c.Id';

export default class KenEventDateSelection extends NavigationMixin(LightningElement) {
    @api eventRecordId;
    @api previouslySelectedDates = [];

    @track showSpinner = false;
    @track selectedDates = [];
    @track currentDate = new Date();
    @track calendarDays = [];

    weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ];

    connectedCallback() {
        if (this.previouslySelectedDates && this.previouslySelectedDates.length > 0) {
            this.selectedDates = [...this.previouslySelectedDates];

            if (this.selectedDates.length > 0) {
                const firstDate = new Date(this.selectedDates[0].key);
                this.currentDate = new Date(firstDate.getFullYear(), firstDate.getMonth(), 1);
            }
            this.generateCalendar();
        }
        else {
            this.selectedDates = [];
            this.generateCalendar();
        }
    }

    renderedCallback() {
        if (this.sessionDates && this.sessionDates.length > 0 &&
            this.selectedDates.length === 0 &&
            (!this.previouslySelectedDates || this.previouslySelectedDates.length === 0)) {

            this.selectedDates = [...this.sessionDates];

            if (this.selectedDates.length > 0) {
                const firstDate = new Date(this.selectedDates[0].key);
                this.currentDate = new Date(firstDate.getFullYear(), firstDate.getMonth(), 1);
            }
            this.generateCalendar();
        }
    }

    @wire(getEventSchedule, { recordId: '$eventRecordId' })
    existingSessions({ error, data }) {
        if (data) {
            if (!data || data.length === 0) {
                console.warn('No existing sessions found for this event.');
                this.sessionDates = [];
                return;
            }

            const uniqueStartDates = new Set();
            data.forEach(session => {
                if (session.startDate) {
                    uniqueStartDates.add(session.startDate);
                }
            });

            const sessionStartDates = Array.from(uniqueStartDates).map(dateStr => {
                const date = new Date(dateStr + 'T00:00:00');
                return {
                    key: this.formatDateKey(date),
                    display: this.formatDateDisplay(date),
                    date: date
                };
            });

            this.sessionDates = sessionStartDates;

            if ((!this.previouslySelectedDates || this.previouslySelectedDates.length === 0) &&
                this.sessionDates.length > 0) {
                console.log('Loading dates from existing sessions');
                this.selectedDates = [...this.sessionDates];

                if (this.selectedDates.length > 0) {
                    const firstDate = new Date(this.selectedDates[0].key);
                    this.currentDate = new Date(firstDate.getFullYear(), firstDate.getMonth(), 1);
                }
                this.generateCalendar();
            }
        } else if (error) {
            console.error('Error retrieving session dates:', error);
        }
    }

    get currentMonthYear() {
        return `${this.months[this.currentDate.getMonth()]} ${this.currentDate.getFullYear()}`;
    }

    get hasSelectedDates() {
        return this.selectedDates && this.selectedDates.length > 0;
    }

    get selectedDatesDisplay() {
        return this.selectedDates.map(date => ({
            key: date.key,
            display: date.display
        }));
    }

    get dateRangeInfo() {
        if (this.selectedDates.length === 0) {
            return null;
        } else if (this.selectedDates.length === 1) {
            return 'Single day event';
        } else {
            const sortedDates = [...this.selectedDates].sort((a, b) => new Date(a.key) - new Date(b.key));
            const firstDate = sortedDates[0].display;
            const lastDate = sortedDates[sortedDates.length - 1].display;
            return `Multi-day event with ${this.selectedDates.length} individual dates selected`;
        }
    }

    get isSaveDisabled() {
        return this.selectedDates.length === 0;
    }

    generateCalendar() {
        const year = this.currentDate.getFullYear();
        const month = this.currentDate.getMonth();

        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);

        const startDate = new Date(firstDay);
        startDate.setDate(startDate.getDate() - firstDay.getDay());

        const days = [];
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        for (let i = 0; i < 42; i++) {
            const currentDay = new Date(startDate);
            currentDay.setDate(startDate.getDate() + i);
            currentDay.setHours(0, 0, 0, 0);

            const dayKey = this.formatDateKey(currentDay);
            const isCurrentMonth = currentDay.getMonth() === month;
            const isToday = currentDay.getTime() === today.getTime();
            const isPast = currentDay < today;
            const isSelected = this.selectedDates.some(selected => selected.key === dayKey);

            let classes = 'calendar-day';
            if (!isCurrentMonth) {
                classes += ' other-month disabled';
            } else if (isPast) {
                classes += ' past-date disabled';
            } else if (isSelected) {
                classes += ' selected';
            } else if (isToday) {
                classes += ' today';
            }

            days.push({
                key: `day-${i}-${dayKey}`,
                number: currentDay.getDate(),
                date: dayKey,
                classes: classes,
                disabled: isPast || !isCurrentMonth
            });
        }

        this.calendarDays = days;
    }

    selectDate(event) {
        const selectedDateKey = event.currentTarget.dataset.date;

        const [year, month, day] = selectedDateKey.split('-').map(Number);
        const selectedDate = new Date(year, month - 1, day);

        const today = new Date();
        today.setHours(0, 0, 0, 0);

        if (selectedDate < today) {
            this.showToast('Error', 'Cannot select past dates', 'error');
            return;
        }

        const currentMonth = this.currentDate.getMonth();
        const currentYear = this.currentDate.getFullYear();
        if (selectedDate.getMonth() !== currentMonth || selectedDate.getFullYear() !== currentYear) {
            return;
        }

        const existingIndex = this.selectedDates.findIndex(date => date.key === selectedDateKey);

        if (existingIndex > -1) {
            this.selectedDates.splice(existingIndex, 1);
        } else {
            const newDate = {
                key: selectedDateKey,
                display: this.formatDateDisplay(selectedDate),
                date: selectedDate
            };
            this.selectedDates.push(newDate);
        }

        this.selectedDates.sort((a, b) => new Date(a.key) - new Date(b.key));
        this.generateCalendar();
    }

    loadExistingIndividualDates(startDate, endDate) {

        this.selectedDates = [];

        const [startYear, startMonth, startDay] = startDate.split('-').map(Number);
        const [endYear, endMonth, endDay] = endDate.split('-').map(Number);

        const start = new Date(startYear, startMonth - 1, startDay);
        const end = new Date(endYear, endMonth - 1, endDay);

        for (let date = new Date(start); date <= end; date.setDate(date.getDate() + 1)) {
            const dateKey = this.formatDateKey(date);
            const dateDisplay = this.formatDateDisplay(date);

            this.selectedDates.push({
                key: dateKey,
                display: dateDisplay,
                date: new Date(date)
            });
        }

        if (this.selectedDates.length > 0) {
            this.currentDate = new Date(this.selectedDates[0].date);
        }

        setTimeout(() => {
            this.generateCalendar();
        }, 100);
    }

    formatDateKey(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    formatDateDisplay(date) {
        return date.toLocaleDateString('en-US', {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        });
    }

    previousMonth() {
        this.currentDate.setMonth(this.currentDate.getMonth() - 1);
        this.generateCalendar();
    }

    nextMonth() {
        this.currentDate.setMonth(this.currentDate.getMonth() + 1);
        this.generateCalendar();
    }

    removeDate(event) {
        const dateToRemove = event.currentTarget.dataset.date;
        this.selectedDates = this.selectedDates.filter(date => date.key !== dateToRemove);
        this.generateCalendar();
    }

    handlePrevious() {
        this.dispatchEvent(new CustomEvent("previous", { detail: "eventSetup" }));
    }

    async handleSave() {
        if (this.selectedDates.length === 0) {
            this.showToast('Error', 'Please select at least one date', 'error');
            return;
        }

        this.showSpinner = true;

        try {
            const sortedDates = [...this.selectedDates].sort((a, b) => new Date(a.key) - new Date(b.key));
            const startDate = sortedDates[0].key;
            const endDate = sortedDates[sortedDates.length - 1].key;

            const fields = {};
            fields[ID_FIELD.fieldApiName] = this.eventRecordId;
            fields[START_DATE_FIELD.fieldApiName] = startDate;
            fields[END_DATE_FIELD.fieldApiName] = endDate;

            await updateRecord({ fields });

            this.showToast('Success', `${this.selectedDates.length} individual dates selected successfully`, 'success');

            this.dispatchEvent(new CustomEvent("dateselection", {
                detail: {
                    eventId: this.eventRecordId,
                    selectedDates: this.selectedDates,
                    startDate: startDate,
                    endDate: endDate,
                    isIndividualDates: true,
                    totalDatesSelected: this.selectedDates.length,
                    hasExistingSessions: this.sessionDates.length > 0
                }
            }));
        } catch (error) {
            this.showToast('Error', 'Error updating event dates', 'error');
            console.error('Error updating dates:', error);
        } finally {
            this.showSpinner = false;
        }
    }

    handleCancel() {
        if (this.eventRecordId) {
            this[NavigationMixin.Navigate]({
                type: "standard__recordPage",
                attributes: {
                    recordId: this.eventRecordId,
                    actionName: "view"
                }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: "standard__objectPage",
                attributes: {
                    objectApiName: "Ken_Event_Master__c",
                    actionName: "list"
                },
                state: {
                    filterName: "Recent"
                }
            });
        }
    }

    showToast(title, message, variant) {
        const toastEvent = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(toastEvent);
    }
}