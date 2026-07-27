import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenScheduleSetup extends LightningElement {
    @api activeDateTab = '';
    @api dateTabsWithClasses = [];
    @api sessionsByDate = {};
    @api currentSession = {};
    @api showSessionForm = false;
    @api editingSessionId = null;
    @api validationErrors = {};

    // Computed properties
    get currentDateSessions() {
        const sessions = this.sessionsByDate[this.activeDateTab] || { sessions: [] };
        return {
            ...sessions,
            sessions: sessions.sessions.map((session, index) => ({
                ...session,
                displayNumber: index + 1,
                isEditing: this.editingSessionId === session?.uniqueId,
                isExpanded: session.isExpanded !== undefined ? session.isExpanded : false,
                speakers: (session.speakers || []).map((speaker, speakerIndex) => ({
                    ...speaker,
                    displayNumber: speakerIndex + 1
                }))
            }))
        };
    }

    get showSessionsList() {
        return this.currentDateSessions.sessions && this.currentDateSessions.sessions.length > 0;
    }

    get showInitialSessionForm() {
        return !this.showSessionsList && !this.showSessionForm;
    }

    get shouldShowSessionForm() {
        return this.showSessionForm || this.editingSessionId !== null;
    }

    get currentSessionSpeakers() {
        return (this.currentSession.speakers || []).map((speaker, index) => ({
            ...speaker,
            displayNumber: index + 1
        }));
    }

    get showSpeakersList() {
        return this.currentSession.speakers && this.currentSession.speakers.length > 0;
    }

    get sessionTitleClass() {
        return this.validationErrors.sessionTitle ? 'form-input error' : 'form-input';
    }

    get sessionAgendaClass() {
        return this.validationErrors.sessionAgenda ? 'form-input error' : 'form-input';
    }

    get timeRangeError() {
        return this.validationErrors.timeRange || '';
    }

    get showVenueAddress() {
        return this.currentSession.locationType === 'onsite' ||
            this.currentSession.locationType === 'hybrid';
    }

    get showEventLink() {
        return this.currentSession.locationType === 'online' ||
            this.currentSession.locationType === 'hybrid';
    }

    get showVenueAddressOnly() {
        return this.showVenueAddress && !this.isHybridSelected;
    }

    get showEventLinkOnly() {
        return this.showEventLink && !this.isHybridSelected;
    }

    get isOnlineSelected() {
        return this.currentSession.locationType === 'online';
    }

    get isOnsiteSelected() {
        return this.currentSession.locationType === 'onsite';
    }

    get isHybridSelected() {
        return this.currentSession.locationType === 'hybrid';
    }

    // Event handlers
    handleDateTabClick(event) {
        const date = event.currentTarget.dataset.date;
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'dateTabChange', date },
            bubbles: true,
            composed: true
        }));
    }

    handleAddSession() {
        this.dispatchEvent(new CustomEvent('addsession', {
            bubbles: true,
            composed: true
        }));
    }

    handleToggleSession(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'toggleSession', sessionId },
            bubbles: true,
            composed: true
        }));
    }

    handleEditSession(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        this.dispatchEvent(new CustomEvent('editsession', {
            detail: { sessionId },
            bubbles: true,
            composed: true
        }));
    }

    handleDeleteSession(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        this.dispatchEvent(new CustomEvent('deletesession', {
            detail: { sessionId },
            bubbles: true,
            composed: true
        }));
    }

    handleSaveSession() {
        this.dispatchEvent(new CustomEvent('savesession', {
            bubbles: true,
            composed: true
        }));
    }

    handleDiscardSession() {
        this.dispatchEvent(new CustomEvent('discardsession', {
            bubbles: true,
            composed: true
        }));
    }

    handleSessionTitleChange(event) {
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'titleChange', value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }

    handleStartTimeChange(event) {
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'startTimeChange', value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }

    handleEndTimeChange(event) {
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'endTimeChange', value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }

    handleTimeInputClick(event) {
        if (typeof event.target.showPicker === 'function') {
            try {
                event.target.showPicker();
            } catch (e) {
                // showPicker() can throw (e.g. not triggered by user activation); fall back to default browser behavior
            }
        }
    }

    handleSessionAgendaChange(event) {
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'agendaChange', value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }

    handleLocationTypeChange(event) {
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'locationTypeChange', value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }

    handleVenueAddressChange(event) {
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'venueAddressChange', value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }

    handleEventLinkChange(event) {
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'eventLinkChange', value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }

    handleSessionBrochureUpload(event) {
        const file = event.target.files[0];
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'brochureUpload', file },
            bubbles: true,
            composed: true
        }));
    }

    handleChangeSessionBrochure(event) {
        const row = event.currentTarget.closest('.file-preview-figma');
        const fileInput = row && row.querySelector('.brochure-change-input');
        if (fileInput) fileInput.click();
    }

    handleRemoveSessionBrochure() {
        this.dispatchEvent(new CustomEvent('sessionchange', {
            detail: { type: 'removeBrochure' },
            bubbles: true,
            composed: true
        }));
    }

    handleAddSpeaker() {
        this.dispatchEvent(new CustomEvent('addspeaker', {
            bubbles: true,
            composed: true
        }));
    }

    handleEditSpeaker(event) {
        const speakerId = event.currentTarget.dataset.speakerId;
        this.dispatchEvent(new CustomEvent('editspeaker', {
            detail: { speakerId },
            bubbles: true,
            composed: true
        }));
    }

    handleDeleteSpeaker(event) {
        const speakerId = event.currentTarget.dataset.speakerId;
        this.dispatchEvent(new CustomEvent('deletespeaker', {
            detail: { speakerId },
            bubbles: true,
            composed: true
        }));
    }
    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
}