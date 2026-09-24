import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

function generateId() {
    return `q-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

export default class KenFeedbackForm extends LightningElement {
    @api feedbackFormsByDate = [];
    _activeFeedbackSessionId = null;
    _activeFeedbackSession = null;
    _feedbackDataForSession = null;

    @track triggerType = 'auto';
    @track triggerWhen = '';
    @track endDate = '';
    @track endTime = '';
    @track dateError = '';
    @track questions = [];

    // Today (yyyy-mm-dd) — used as the min on the feedback end-date picker so past
    // dates can't be chosen.
    get minDate() {
        const d = new Date();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        return `${d.getFullYear()}-${mm}-${dd}`;
    }

    // True when the chosen end date/time is in the past (must be future).
    _isPastDateTime(dateStr, timeStr) {
        if (!dateStr) return false;
        const [y, m, d] = dateStr.split('-').map(Number);
        let hh = 0, mi = 0;
        if (timeStr) {
            const parts = timeStr.split(':');
            hh = Number(parts[0]) || 0;
            mi = Number(parts[1]) || 0;
        }
        const chosen = new Date(y, (m || 1) - 1, d || 1, hh, mi, 0, 0);
        return chosen.getTime() < Date.now();
    }

    _validateFutureDateTime() {
        this.dateError = this._isPastDateTime(this.endDate, this.endTime)
            ? 'Please select a future date and time'
            : '';
        return !this.dateError;
    }

    get showListView() {
        return true;
    }

    get showEditView() {
        return !!this.activeFeedbackSessionId && !!this.activeFeedbackSession;
    }

    get sessionHeader() {
        const act = this.activeFeedbackSession;
        if (!act) return null;
        const { session, dayIndex, sessionIndex, totalSessionsInDay, displayDate, displayTime } = act;
        return {
            dayLabel: `Day ${dayIndex}`,
            sessionLabel: `Session ${sessionIndex} of ${totalSessionsInDay}`,
            title: session?.title || '',
            dateTime: displayTime ? `${displayDate} • ${displayTime}` : displayDate,
            questionsCount: this.questions.length
        };
    }

    get isAutoTriggerSelected() {
        return this.triggerType === 'auto';
    }

    get triggerWhenOptions() {
        return [
            { label: 'At session end', value: 'session_end' },
            { label: 'Custom date & time', value: 'custom' }
        ];
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {});
    }

    @api get activeFeedbackSessionId() {
        return this._activeFeedbackSessionId;
    }
    set activeFeedbackSessionId(value) {
        this._activeFeedbackSessionId = value;
        if (!value) {
            this.triggerType = 'auto';
            this.triggerWhen = '';
            this.endDate = '';
            this.endTime = '';
            this.questions = [];
        }
    }

    @api get activeFeedbackSession() {
        return this._activeFeedbackSession;
    }
    set activeFeedbackSession(value) {
        this._activeFeedbackSession = value;
    }

    @api get feedbackDataForSession() {
        return this._feedbackDataForSession;
    }
    set feedbackDataForSession(value) {
        this._feedbackDataForSession = value;
        if (this._activeFeedbackSessionId && value) {
            this.triggerType = value.triggerType || 'auto';
            this.triggerWhen = value.triggerWhen || '';
            this.endDate = value.endDate || '';
            this.endTime = value.endTime || '';
            const existing = Array.isArray(value.questions) ? value.questions.map(q => ({ ...q })) : [];
            if (existing.length === 0) {
                existing.push({
                    id: generateId(),
                    text: '',
                    type: 'Multiple Choice',
                    required: false,
                    options: [
                        { id: generateId(), value: '', text: '', letter: 'a' },
                        { id: generateId(), value: '', text: '', letter: 'b' }
                    ],
                    number: 1
                });
            }
            this.questions = existing;
        }
    }

    handleFeedbackAction(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        const hasForm = event.currentTarget.dataset.hasForm === 'true';
        this.dispatchEvent(new CustomEvent('feedbackaction', {
            detail: { sessionId, hasForm },
            bubbles: true
        }));
    }

    handleDiscard() {
        this.dispatchEvent(new CustomEvent('discardfeedback', { bubbles: true }));
    }

    handleTriggerTypeChange(event) {
        this.triggerType = event.target.value || 'auto';
    }

    handleTriggerWhenChange(event) {
        this.triggerWhen = event.detail?.value ?? event.target.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.detail?.value ?? event.target.value ?? '';
        this._validateFutureDateTime();
    }

    handleEndTimeChange(event) {
        this.endTime = event.detail?.value ?? event.target.value ?? '';
        this._validateFutureDateTime();
    }

    handleSaveForm() {
        // Validate the questions (label required; Multiple/Checkbox need >=2 options) AND the
        // auto-trigger end date — run both so all inline errors surface at once, then bail if invalid.
        const builder = this.template.querySelector('c-ken-questionnaire-builder');
        const questionsValid = !builder || typeof builder.validate !== 'function' || builder.validate();
        const dateValid = this.triggerType !== 'auto' || this._validateFutureDateTime();
        if (!questionsValid || !dateValid) {
            return;
        }
        const payload = {
            sessionId: this._activeFeedbackSessionId,
            triggerType: this.triggerType,
            triggerWhen: this.triggerWhen,
            endDate: this.endDate,
            endTime: this.endTime,
            questions: this.questions.map(q => ({
                id: q.id,
                text: q.text,
                type: q.type,
                required: q.required,
                options: q.options || []
            }))
        };
        this.dispatchEvent(new CustomEvent('savefeedback', {
            detail: payload,
            bubbles: true
        }));
    }

    handleBuilderChange(event) {
        if (!event.detail || !Array.isArray(event.detail.questions)) {
            return;
        }
        this.questions = event.detail.questions;
    }
}