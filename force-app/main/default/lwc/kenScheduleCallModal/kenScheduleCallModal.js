import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getMentorAvailabilityDays from '@salesforce/apex/KenMentorshipController.getMentorAvailabilityDays';

const SLOT_MINUTES = 15;
const DAY_MINUTES = 24 * 60;

export default class KenScheduleCallModal extends LightningElement {
    @api mentorOptions = [];
    @api menteeOptions = [];
    @api isSubmitting = false;
    _initialDate = '';

    selectedParticipantType = 'mentor';
    selectedMentor = '';
    title = '';
    selectedDate = '';
    startTime = '';
    endTime = '';
    descriptionHtml = '';
    meetingType = 'Online';
    meetLink = '';
    @track _mentorAvailableDays = [];
    @track _mentorStartTime = '';
    @track _mentorEndTime   = '';
    @track dateAvailabilityError = '';
    @track timeAvailabilityError = '';
    @track validationErrors = {};
    isBoldActive = false;
    isItalicActive = false;
    isUnorderedListActive = false;
    isOrderedListActive = false;

    richTextEditor = null;

    @api
    get initialDate() {
        return this._initialDate;
    }

    set initialDate(value) {
        this._initialDate = this.normalizeDateInput(value);
        if (this._initialDate) {
            this.selectedDate = this._initialDate;
        }
    }

    get resolvedMentorOptions() {
        return Array.isArray(this.mentorOptions) ? this.mentorOptions : [];
    }

    get resolvedMenteeOptions() {
        return Array.isArray(this.menteeOptions) ? this.menteeOptions : [];
    }

    get participantTypeOptions() {
        return [
            { label: 'Mentor', value: 'mentor' },
            { label: 'Mentee', value: 'mentee' }
        ];
    }

    get participantOptions() {
        return this.selectedParticipantType === 'mentee'
            ? this.resolvedMenteeOptions
            : this.resolvedMentorOptions;
    }

    get participantLabel() {
        return this.selectedParticipantType === 'mentee' ? 'Choose Mentee' : 'Choose Mentor';
    }

    get participantPlaceholder() {
        return this.selectedParticipantType === 'mentee' ? 'Select Mentee' : 'Select Mentor';
    }

    get participantInlineError() {
        if (this.participantOptions.length > 0) {
            return '';
        }
        return this.selectedParticipantType === 'mentee'
            ? 'No mentees available for scheduling.'
            : 'No mentors available for scheduling.';
    }

    get isParticipantDisabled() {
        return this.participantOptions.length === 0;
    }

    get isOnlineSelected() {
        return this.meetingType === 'Online';
    }

    get isInPersonSelected() {
        return this.meetingType === 'In-person';
    }

    get boldButtonClass() {
        return `toolbar-button ${this.isBoldActive ? 'active' : ''}`;
    }

    get italicButtonClass() {
        return `toolbar-button ${this.isItalicActive ? 'active' : ''}`;
    }

    get unorderedListButtonClass() {
        return `toolbar-button ${this.isUnorderedListActive ? 'active' : ''}`;
    }

    get orderedListButtonClass() {
        return `toolbar-button ${this.isOrderedListActive ? 'active' : ''}`;
    }

    get sendButtonLabel() {
        return this.isSubmitting ? 'Sending...' : 'Send Request';
    }

    get minimumDate() {
        const today = new Date();
        return today.toISOString().split('T')[0];
    }

    get isSelectedDateInPast() {
        if (!this.selectedDate) {
            return false;
        }
        const selectedDate = new Date(`${this.selectedDate}T00:00:00`);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return selectedDate < today;
    }

    get isTodaySelected() {
        if (!this.selectedDate) {
            return false;
        }
        const selectedDate = new Date(`${this.selectedDate}T00:00:00`);
        const today = new Date();
        return selectedDate.getFullYear() === today.getFullYear() &&
            selectedDate.getMonth() === today.getMonth() &&
            selectedDate.getDate() === today.getDate();
    }

    get startTimeOptions() {
        const fromMinute = this.isTodaySelected ? this.getNextAvailableSlotMinute() : 0;
        return this.buildTimeOptions(fromMinute);
    }

    get endTimeOptions() {
        if (!this.startTime) {
            return [];
        }
        const startMinute = this.timeStringToMinutes(this.startTime);
        if (startMinute === null) {
            return [];
        }
        return this.buildTimeOptions(startMinute + SLOT_MINUTES);
    }

    get isEndTimeDisabled() {
        return !this.startTime;
    }

    get isSendDisabled() {
        return this.isSubmitting || this.isSelectedDateInPast || !!this.dateAvailabilityError || !!this.timeAvailabilityError;
    }

    _dayName(dateStr) {
        if (!dateStr) return '';
        const [year, month, day] = dateStr.split('-').map(Number);
        const d = new Date(year, month - 1, day);
        return ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'][d.getDay()];
    }

    _checkDateAvailability() {
        if (!this.selectedDate || this._mentorAvailableDays.length === 0) {
            this.dateAvailabilityError = '';
            return;
        }
        const dayName = this._dayName(this.selectedDate);
        this.dateAvailabilityError = this._mentorAvailableDays.includes(dayName)
            ? '' : 'Mentor is not available for the selected date';
    }

    _toMinutes(t) {
        if (!t) return null;
        const parts = t.split(':');
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    }

    _checkTimeAvailability() {
        if (!this._mentorStartTime || !this._mentorEndTime) {
            this.timeAvailabilityError = '';
            return;
        }
        const checkTime = this.startTime || this.endTime;
        if (!checkTime) {
            this.timeAvailabilityError = '';
            return;
        }
        const mentorStart = this._toMinutes(this._mentorStartTime);
        const mentorEnd   = this._toMinutes(this._mentorEndTime);
        const reqStart    = this.startTime  ? this._toMinutes(this.startTime)  : null;
        const reqEnd      = this.endTime    ? this._toMinutes(this.endTime)    : null;

        const outOfRange = (reqStart !== null && (reqStart < mentorStart || reqStart >= mentorEnd))
                        || (reqEnd   !== null && (reqEnd   > mentorEnd   || reqEnd   <= mentorStart));

        this.timeAvailabilityError = outOfRange
            ? `Mentor is available only between ${this._formatTime(this._mentorStartTime)} and ${this._formatTime(this._mentorEndTime)}`
            : '';
    }

    _formatTime(t) {
        if (!t) return '';
        const [h, m] = t.split(':').map(Number);
        const meridian = h >= 12 ? 'PM' : 'AM';
        const h12 = ((h + 11) % 12) + 1;
        return `${String(h12).padStart(2,'0')}:${String(m).padStart(2,'0')} ${meridian}`;
    }

    _loadMentorAvailability(mentorId) {
        if (!mentorId || this.selectedParticipantType !== 'mentor') {
            this._mentorAvailableDays = [];
            this._mentorStartTime     = '';
            this._mentorEndTime       = '';
            this.dateAvailabilityError = '';
            this.timeAvailabilityError = '';
            return;
        }
        getMentorAvailabilityDays({ mentorId })
            .then(result => {
                this._mentorAvailableDays = result?.availabilityDays
                    ? result.availabilityDays.split(';').map(d => d.trim()).filter(Boolean)
                    : [];
                this._mentorStartTime = result?.availabilityStartTime || '';
                this._mentorEndTime   = result?.availabilityEndTime   || '';
                this._checkDateAvailability();
                this._checkTimeAvailability();
            })
            .catch(() => {
                this._mentorAvailableDays = [];
                this._mentorStartTime     = '';
                this._mentorEndTime       = '';
                this.dateAvailabilityError = '';
                this.timeAvailabilityError = '';
            });
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {});

        const normalizedInitialDate = this.normalizeDateInput(this._initialDate);
        if (normalizedInitialDate) {
            this.selectedDate = normalizedInitialDate;
            return;
        }

        const today = new Date();
        this.selectedDate = today.toISOString().split('T')[0];
    }

    renderedCallback() {
        const editor = this.template.querySelector('.rich-text-area');
        if (editor) {
            if (editor !== this.richTextEditor) {
                this.richTextEditor = editor;
                if (this.descriptionHtml && editor.innerHTML !== this.descriptionHtml) {
                    editor.innerHTML = this.descriptionHtml;
                }
                editor.addEventListener('keyup', () => this.updateButtonStates());
                editor.addEventListener('mouseup', () => this.updateButtonStates());
            } else if (this.descriptionHtml && editor.innerHTML !== this.descriptionHtml) {
                editor.innerHTML = this.descriptionHtml;
            } else if (!this.descriptionHtml && editor.innerHTML) {
                editor.innerHTML = '';
            }
            this.ensureListFormatting();
        }
    }

    handleMentorChange(event) {
        this.selectedMentor = this.getInputValue(event);
        this._loadMentorAvailability(this.selectedMentor);
        this.clearFieldError('participantId');
    }

    handleParticipantTypeChange(event) {
        this.selectedParticipantType = this.getInputValue(event) || 'mentor';
        this.selectedMentor = '';
        this._mentorAvailableDays = [];
        this._mentorStartTime     = '';
        this._mentorEndTime       = '';
        this.dateAvailabilityError = '';
        this.timeAvailabilityError = '';
        this.clearFieldError('participantType');
        this.clearFieldError('participantId');
    }

    handleTitleChange(event) {
        this.title = this.getInputValue(event);
        this.clearFieldError('title');
    }

    handleDateChange(event) {
        this.selectedDate = this.normalizeDateInput(this.getInputValue(event));
        this.startTime = '';
        this.endTime = '';
        this._checkDateAvailability();
        this.clearFieldError('date');
    }

    handleStartTimeChange(event) {
        const nextStartTime = this.normalizeTimeInput(this.getInputValue(event));
        if (nextStartTime !== this.startTime) {
            this.startTime = nextStartTime;
            this.endTime = '';
        }
        this._checkTimeAvailability();
        this.clearFieldError('time');
    }

    handleEndTimeChange(event) {
        this.endTime = this.normalizeTimeInput(this.getInputValue(event));
        this._checkTimeAvailability();
        this.clearFieldError('time');
    }

    handleMeetingTypeChange(event) {
        this.meetingType = event.target.value;
        this.clearFieldError('meetingType');
    }

    handleMeetLinkChange(event) {
        this.meetLink = this.getInputValue(event);
        const link = (this.meetLink || '').trim();
        if (!link) {
            this.clearFieldError('meetLink');
        } else if (this.isOnlineSelected) {
            const isValid = link.startsWith('https://') || link.startsWith('www.') || link.includes('.com');
            if (!isValid) {
                this.validationErrors = { ...this.validationErrors, meetLink: 'Invalid URL.' };
            } else {
                this.clearFieldError('meetLink');
            }
        } else {
            this.clearFieldError('meetLink');
        }
    }

    handleRichTextInput(event) {
        this.descriptionHtml = event.target.innerHTML || '';
        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }

    handleDescriptionChange(event) {
        this.descriptionHtml = event.detail.value || '';
    }

    handleRichTextFocus() {
        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }

    handleRichTextBlur(event) {
        this.descriptionHtml = event.target.innerHTML || '';
    }

    handleRichTextSelection() {
        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }

    updateButtonStates() {
        if (!this.richTextEditor) return;
        
        try {
            this.isBoldActive = document.queryCommandState('bold');
            this.isItalicActive = document.queryCommandState('italic');
            
            const selection = window.getSelection();
            let isInUnorderedList = false;
            let isInOrderedList = false;
            
            if (selection.rangeCount > 0) {
                const range = selection.getRangeAt(0);
                let container = range.commonAncestorContainer;
                
                while (container && container !== this.richTextEditor) {
                    if (container.nodeType === 1) {
                        const tagName = container.tagName.toUpperCase();
                        if (tagName === 'UL') {
                            isInUnorderedList = true;
                            break;
                        } else if (tagName === 'OL') {
                            isInOrderedList = true;
                            break;
                        } else if (tagName === 'LI') {
                            const parent = container.parentElement;
                            if (parent) {
                                const parentTag = parent.tagName.toUpperCase();
                                if (parentTag === 'UL') {
                                    isInUnorderedList = true;
                                } else if (parentTag === 'OL') {
                                    isInOrderedList = true;
                                }
                            }
                            break;
                        }
                    }
                    container = container.parentElement || container.parentNode;
                }
            }
            
            if (!isInUnorderedList && !isInOrderedList) {
                const lists = this.richTextEditor.querySelectorAll('ul, ol');
                if (lists.length > 0) {
                    const selection = window.getSelection();
                    if (selection.rangeCount > 0) {
                        const range = selection.getRangeAt(0);
                        lists.forEach(list => {
                            if (list.contains(range.commonAncestorContainer)) {
                                if (list.tagName.toUpperCase() === 'UL') {
                                    isInUnorderedList = true;
                                } else if (list.tagName.toUpperCase() === 'OL') {
                                    isInOrderedList = true;
                                }
                            }
                        });
                    }
                }
            }
            
            this.isUnorderedListActive = isInUnorderedList;
            this.isOrderedListActive = isInOrderedList;
            
        } catch {}
    }

    executeCommand(command) {
        if (!this.richTextEditor) return;
        
        this.richTextEditor.focus();
        
        if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
            const selection = window.getSelection();
            if (selection.rangeCount === 0 || selection.isCollapsed) {
                const range = document.createRange();
                const textNode = this.richTextEditor.childNodes[0] || this.richTextEditor;
                range.setStart(textNode, 0);
                range.setEnd(textNode, textNode.textContent ? textNode.textContent.length : 0);
                selection.removeAllRanges();
                selection.addRange(range);
            }
        }
        
        document.execCommand(command, false, null);
        
        setTimeout(() => {
            this.descriptionHtml = this.richTextEditor.innerHTML;
            this.updateButtonStates();
            
            if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
                this.ensureListFormatting();
            }
        }, 50);
    }

    ensureListFormatting() {
        const lists = this.richTextEditor.querySelectorAll('ul, ol');
        lists.forEach(list => {
            if (!list.style.marginLeft) {
                list.style.marginLeft = '1.5rem';
                list.style.marginTop = '0.5rem';
                list.style.marginBottom = '0.5rem';
            }
        });
        
        const listItems = this.richTextEditor.querySelectorAll('li');
        listItems.forEach(li => {
            if (!li.style.marginBottom) {
                li.style.marginBottom = '0.25rem';
            }
        });
    }

    handleBold() {
        this.executeCommand('bold');
    }

    handleItalic() {
        this.executeCommand('italic');
    }

    handleUnorderedList() {
        this.executeCommand('insertUnorderedList');
    }

    handleOrderedList() {
        this.executeCommand('insertOrderedList');
    }

    handleAIContinue() {
        // Reserved for future integration.
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', {
            bubbles: true,
            composed: true
        }));
    }

    handleSendRequest() {
        if (this.isSubmitting) {
            return;
        }

        if (!this.validateRequiredFields()) {
            return;
        }
        if (this.isSelectedDateInPast) {
            this.emitToast('You cannot schedule a call for a past date.');
            return;
        }

        const normalizedMeetingDate = this.normalizeDateInput(this.selectedDate || this._initialDate);
        if (!normalizedMeetingDate) {
            this.emitToast('Please select a valid date.');
            return;
        }

        const requestData = {
            participantType: this.selectedParticipantType,
            participantId: this.selectedMentor,
            mentorId: this.selectedParticipantType === 'mentor' ? this.selectedMentor : '',
            mentor: this.selectedParticipantType === 'mentor' ? this.selectedMentor : '',
            selectedMentor: this.selectedParticipantType === 'mentor' ? this.selectedMentor : '',
            mentorValue: this.selectedParticipantType === 'mentor' ? this.selectedMentor : '',
            title: this.title,
            meetingDate: normalizedMeetingDate,
            startTime: this.startTime,
            endTime: this.endTime,
            description: this.descriptionHtml,
            meetingType: this.meetingType,
            meetLink: this.meetLink
        };

        this.dispatchEvent(new CustomEvent('sendrequest', {
            detail: requestData
        }));
        this.handleClose();
    }

    clearFieldError(field) {
        if (!field) return;
        if (!this.validationErrors || !this.validationErrors[field]) return;
        const next = { ...(this.validationErrors || {}) };
        delete next[field];
        this.validationErrors = next;
    }

    validateRequiredFields() {
        const errors = {};

        if (!this.selectedParticipantType) {
            errors.participantType = 'Please select a role.';
        }

        if (!this.selectedMentor) {
            errors.participantId = this.selectedParticipantType === 'mentee'
                ? 'Please select a mentee.'
                : 'Please select a mentor.';
        }

        // Title is mandatory (Description remains optional)
        if (!(this.title || '').trim()) {
            errors.title = 'Title is required.';
        }

        if (!this.selectedDate) {
            errors.date = 'Please select a date.';
        }

        if (!this.startTime || !this.endTime) {
            errors.time = 'Please select start and end time.';
        }

        if (!this.meetingType) {
            errors.meetingType = 'Please select meeting type.';
        }

        if (!(this.meetLink || '').trim()) {
            errors.meetLink = this.isInPersonSelected
                ? 'Please enter the address or Google Maps link.'
                : 'Please enter the meeting link.';
        } else if (this.isOnlineSelected) {
            const link = (this.meetLink || '').trim();
            const isValid = link.startsWith('https://') || link.startsWith('www.') || link.includes('.com');
            if (!isValid) {
                errors.meetLink = 'Invalid URL.';
            }
        }

        // Keep existing availability errors visible too
        if (this.dateAvailabilityError) {
            errors.date = errors.date || this.dateAvailabilityError;
        }
        if (this.timeAvailabilityError) {
            errors.time = errors.time || this.timeAvailabilityError;
        }

        this.validationErrors = errors;
        return Object.keys(errors).length === 0;
    }

    get hasTitleError() {
        return !!this.validationErrors?.title;
    }

    get hasParticipantTypeError() {
        return !!this.validationErrors?.participantType;
    }

    get hasParticipantError() {
        return !!this.validationErrors?.participantId;
    }

    get hasDateError() {
        return !!this.validationErrors?.date;
    }

    get hasTimeError() {
        return !!this.validationErrors?.time;
    }

    get hasMeetingTypeError() {
        return !!this.validationErrors?.meetingType;
    }

    get hasMeetLinkError() {
        return !!this.validationErrors?.meetLink;
    }

    get participantTypeClass() {
        return `custom-select ${this.hasParticipantTypeError ? 'has-error' : ''}`;
    }

    get participantSelectClass() {
        return `custom-select ${this.hasParticipantError ? 'has-error' : ''}`;
    }

    get titleInputClass() {
        return `custom-input ${this.hasTitleError ? 'has-error' : ''}`;
    }

    get dateInputClass() {
        return `custom-input ${this.hasDateError ? 'has-error' : ''}`;
    }

    get startTimeInputClass() {
        return `custom-input ${this.hasTimeError ? 'has-error' : ''}`;
    }

    get endTimeInputClass() {
        return `custom-input ${this.hasTimeError ? 'has-error' : ''}`;
    }

    get meetLinkInputClass() {
        return `custom-input ${this.hasMeetLinkError ? 'has-error' : ''}`;
    }

    getInputValue(event) {
        if (event?.detail && event.detail.value !== undefined) {
            return event.detail.value;
        }
        if (event?.target && event.target.value !== undefined) {
            return event.target.value;
        }
        return '';
    }

    emitToast(message, variant = 'error', title = 'Error') {
        this.dispatchEvent(new CustomEvent('showtoast', {
            detail: { title, message, variant }
        }));
    }

    normalizeTimeInput(value) {
        if (!value) {
            return '';
        }

        let raw = String(value).trim();
        if (!raw) {
            return '';
        }

        // lightning-input time values can include seconds/millis; keep local HH:mm for UI min/value handling.
        if (raw.includes('T')) {
            raw = raw.split('T')[1];
        }
        raw = raw.replace('Z', '');

        const parts = raw.split(':');
        if (parts.length < 2) {
            return '';
        }

        const hours = Number(parts[0]);
        const minutes = Number(parts[1]);
        if (Number.isNaN(hours) || Number.isNaN(minutes) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
            return '';
        }

        return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
    }

    getNextAvailableSlotMinute() {
        const now = new Date();
        let totalMinutes = (now.getHours() * 60) + now.getMinutes();
        if (now.getSeconds() > 0 || now.getMilliseconds() > 0) {
            totalMinutes += 1;
        }
        return Math.ceil(totalMinutes / SLOT_MINUTES) * SLOT_MINUTES;
    }

    buildTimeOptions(fromMinute) {
        const options = [];
        if (fromMinute === null || fromMinute === undefined || fromMinute >= DAY_MINUTES) {
            return options;
        }

        for (let minute = fromMinute; minute < DAY_MINUTES; minute += SLOT_MINUTES) {
            options.push({
                value: this.minutesToTimeValue(minute),
                label: this.minutesToTimeLabel(minute)
            });
        }
        return options;
    }

    timeStringToMinutes(value) {
        const normalized = this.normalizeTimeInput(value);
        if (!normalized) {
            return null;
        }
        const parts = normalized.split(':');
        if (parts.length !== 2) {
            return null;
        }
        const hours = Number(parts[0]);
        const minutes = Number(parts[1]);
        if (Number.isNaN(hours) || Number.isNaN(minutes)) {
            return null;
        }
        return (hours * 60) + minutes;
    }

    minutesToTimeValue(totalMinutes) {
        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
    }

    minutesToTimeLabel(totalMinutes) {
        const hours24 = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        const meridian = hours24 >= 12 ? 'PM' : 'AM';
        const hours12 = ((hours24 + 11) % 12) + 1;
        return `${String(hours12).padStart(2, '0')}:${String(minutes).padStart(2, '0')} ${meridian}`;
    }

    normalizeDateInput(value) {
        if (!value) {
            return '';
        }

        if (value instanceof Date && !Number.isNaN(value.getTime())) {
            return value.toISOString().slice(0, 10);
        }

        const asString = String(value).trim();
        if (!asString) {
            return '';
        }

        if (/^\d{4}-\d{2}-\d{2}$/.test(asString)) {
            return asString;
        }

        if (asString.includes('T')) {
            const dateOnly = asString.split('T')[0];
            if (/^\d{4}-\d{2}-\d{2}$/.test(dateOnly)) {
                return dateOnly;
            }
        }

        const parsedDate = new Date(asString);
        if (Number.isNaN(parsedDate.getTime())) {
            return '';
        }
        return parsedDate.toISOString().slice(0, 10);
    }
}