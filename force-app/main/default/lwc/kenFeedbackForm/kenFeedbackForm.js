import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const QUESTION_TYPE_OPTIONS = [
    { label: 'Single Select', value: 'Multiple Choice' },
    { label: 'Checkbox', value: 'Yes/No' },
    { label: 'Linear scale', value: 'linear' },
    { label: 'Short answer', value: 'Short Answer' }
];

function generateId() {
    return `q-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

function normalizeQuestion(q, idx) {
    const type = q.type || 'Multiple Choice';
    const normalizedType = String(type).toLowerCase();
    const isMultiple = normalizedType === 'multiple' || normalizedType === 'multiple choice';
    const isShortAnswer = normalizedType === 'short' || normalizedType === 'short answer';
    const isCheckboxType = normalizedType === 'checkbox' || normalizedType === 'yes/no';
    const isLinear = normalizedType === 'linear' || normalizedType === 'linear scale';
    const showMultipleOptions = isMultiple || isCheckboxType;
    const showLinearScale = isLinear;
    const options = (q.options || []).map((opt, optIdx) => ({
        id: opt.id || generateId(),
        text: opt.text || '',
        letter: opt.letter || String.fromCharCode(97 + optIdx)
    }));
    return {
        ...q,
        id: q.id || generateId(),
        number: q.number ?? idx + 1,
        type,
        required: !!q.required,
        options,
        showMultipleOptions,
        showLinearScale,
        isMultiple,
        isCheckboxType,
        nextOptionNumber: (options.length || 0) + 1,
        scaleMin: q.scaleMin != null ? String(q.scaleMin) : '1',
        scaleMax: q.scaleMax != null ? String(q.scaleMax) : '5',
        scaleMinLabel: q.scaleMinLabel || '',
        scaleMaxLabel: q.scaleMaxLabel || ''
    };
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
    draggedQuestionId = null;

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

    get questionTypeOptions() {
        return QUESTION_TYPE_OPTIONS;
    }

    get scaleNumberOptions() {
        return [1, 2, 3, 4, 5].map(i => ({ label: String(i), value: String(i) }));
    }

    get normalizedQuestions() {
        return (this.questions || []).map((q, idx) => normalizeQuestion(q, idx));
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
                        { id: generateId(), text: '', letter: 'a' },
                        { id: generateId(), text: '', letter: 'b' }
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
            bubbles: true,
            composed: true
        }));
    }

    handleDiscard() {
        this.dispatchEvent(new CustomEvent('discardfeedback', { bubbles: true, composed: true }));
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
                options: q.options || [],
                scaleMin: q.scaleMin,
                scaleMax: q.scaleMax,
                scaleMinLabel: q.scaleMinLabel,
                scaleMaxLabel: q.scaleMaxLabel
            }))
        };
        this.dispatchEvent(new CustomEvent('savefeedback', {
            detail: payload,
            bubbles: true,
            composed: true
        }));
    }

    handleBuilderChange(event) {
        if (!event.detail || !Array.isArray(event.detail.questions)) {
            return;
        }
        this.questions = event.detail.questions;
    }

    handleAddQuestion() {
        const newQ = {
            id: generateId(),
            text: '',
            type: 'Multiple Choice',
            required: false,
            options: [
                { id: generateId(), text: '', letter: 'a' },
                { id: generateId(), text: '', letter: 'b' }
            ],
            number: this.questions.length + 1
        };
        this.questions = [...this.questions, newQ];
    }

    handleDeleteQuestion(event) {
        const questionId = event.currentTarget.dataset.questionId;
        this.questions = this.questions.filter(q => q.id !== questionId).map((q, i) => ({ ...q, number: i + 1 }));
    }

    handleQuestionTextChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value ?? '';
        this.questions = this.questions.map(q => q.id === questionId ? { ...q, text: value } : q);
    }

    handleQuestionTypeChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value ?? 'Multiple Choice';
        const normalizedType = String(value).toLowerCase();
        const isMultiple = normalizedType === 'multiple' || normalizedType === 'multiple choice';
        const isCheckboxType = normalizedType === 'checkbox' || normalizedType === 'yes/no';
        const isLinear = normalizedType === 'linear' || normalizedType === 'linear scale';
        const showMultipleOptions = isMultiple || isCheckboxType;
        const showLinearScale = isLinear;
        let options = [];
        if (showMultipleOptions) {
            const existing = this.questions.find(q => q.id === questionId);
            options = (existing?.options && existing.options.length) ? existing.options : [
                { id: generateId(), text: '', letter: 'a' },
                { id: generateId(), text: '', letter: 'b' }
            ];
        }
        this.questions = this.questions.map(q => {
            if (q.id !== questionId) return q;
            return {
                ...q,
                type: value,
                showMultipleOptions,
                showLinearScale,
                isMultiple,
                isCheckboxType,
                options,
                nextOptionNumber: options.length + 1,
                scaleMin: '1',
                scaleMax: '5',
                scaleMinLabel: '',
                scaleMaxLabel: ''
            };
        });
    }

    handleRequiredToggle(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.target.checked;
        this.questions = this.questions.map(q => q.id === questionId ? { ...q, required: value } : q);
    }

    handleOptionTextChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const optionId = event.currentTarget.dataset.optionId;
        const value = event.detail?.value ?? event.target.value ?? '';
        this.questions = this.questions.map(q => {
            if (q.id !== questionId) return q;
            const options = (q.options || []).map(opt => opt.id === optionId ? { ...opt, text: value } : opt);
            return { ...q, options };
        });
    }

    handleAddOptionClick(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const q = this.questions.find(qq => qq.id === questionId);
        if (!q) return;
        const options = q.options || [];
        const nextLetter = String.fromCharCode(97 + options.length);
        const newOpt = { id: generateId(), text: '', letter: nextLetter };
        this.questions = this.questions.map(qq =>
            qq.id === questionId ? { ...qq, options: [...(qq.options || []), newOpt], nextOptionNumber: options.length + 2 } : qq
        );
    }

    handleDeleteOption(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const optionId = event.currentTarget.dataset.optionId;
        this.questions = this.questions.map(q => {
            if (q.id !== questionId) return q;
            const options = (q.options || []).filter(o => o.id !== optionId);
            return { ...q, options, nextOptionNumber: options.length + 1 };
        });
    }

    handleScaleMinChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value ?? '1';
        this.questions = this.questions.map(q => q.id === questionId ? { ...q, scaleMin: value } : q);
    }

    handleScaleMaxChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value ?? '5';
        this.questions = this.questions.map(q => q.id === questionId ? { ...q, scaleMax: value } : q);
    }

    handleScaleMinLabelChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value ?? '';
        this.questions = this.questions.map(q => q.id === questionId ? { ...q, scaleMinLabel: value } : q);
    }

    handleScaleMaxLabelChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value ?? '';
        this.questions = this.questions.map(q => q.id === questionId ? { ...q, scaleMaxLabel: value } : q);
    }

    handleDragStart(event) {
        this.draggedQuestionId = event.currentTarget.dataset.questionId;
        event.dataTransfer.dropEffect = 'move';
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', this.draggedQuestionId);
    }

    handleDragOver(event) {
        event.preventDefault();
        event.currentTarget.classList.add('drag-over');
    }

    handleDragEnd(event) {
        event.currentTarget.classList.remove('drag-over');
    }

    handleDrop(event) {
        event.preventDefault();
        const toId = event.currentTarget.dataset.questionId;
        const fromId = this.draggedQuestionId || event.dataTransfer.getData('text/plain');
        event.currentTarget.classList.remove('drag-over');
        if (!fromId || !toId || fromId === toId) return;
        const arr = [...this.questions];
        const fromIdx = arr.findIndex(q => q.id === fromId);
        const toIdx = arr.findIndex(q => q.id === toId);
        if (fromIdx === -1 || toIdx === -1) return;
        const [removed] = arr.splice(fromIdx, 1);
        arr.splice(toIdx, 0, removed);
        this.questions = arr.map((q, i) => ({ ...q, number: i + 1 }));
    }
}