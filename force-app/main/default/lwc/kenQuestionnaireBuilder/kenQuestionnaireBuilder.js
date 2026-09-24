import { LightningElement, api, track } from 'lwc';

const DEFAULT_QUESTION_TYPES = [
    { label: 'Single Select', value: 'Multiple Choice' },
    { label: 'Checkbox', value: 'Yes/No' },
    { label: 'Linear scale', value: 'linear' },
    { label: 'Short answer', value: 'Short Answer' }
];

const DEFAULT_SCALE_POINTS = 5;
const MAX_SCALE_POINTS = 10;

function generateId() {
    return `q-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

function isLinearType(type) {
    const t = String(type || '').toLowerCase();
    return t === 'linear' || t === 'linear scale';
}

/**
 * Builds the points of a linear scale. Each point is an option whose value is the number the
 * respondent submits and whose text is the label the author types next to it.
 */
function buildScalePoints(count, existing) {
    const previous = existing || [];
    const points = [];
    for (let i = 0; i < count; i++) {
        const carried = previous[i];
        points.push({
            id: carried && carried.id ? carried.id : generateId(),
            value: String(i + 1),
            text: carried ? (carried.text || '') : '',
            letter: String.fromCharCode(97 + i)
        });
    }
    return points;
}

// Map any incoming type vocabulary onto the canonical combobox option values
// so a prepopulated question's type dropdown displays correctly.
function canonicalType(type) {
    const t = String(type || '').toLowerCase();
    if (t === 'multiple' || t === 'multiple choice') return 'Multiple Choice';
    if (t === 'checkbox' || t === 'yes/no') return 'Yes/No';
    if (t === 'linear' || t === 'linear scale') return 'linear';
    if (t === 'short' || t === 'short answer' || t === 'text') return 'Short Answer';
    return type;
}

function normalizeQuestion(q, idx, hideRequired, errors) {
    const type = q.type || 'Multiple Choice';
    const normalizedType = String(type).toLowerCase();
    const isMultiple = normalizedType === 'multiple' || normalizedType === 'multiple choice';
    const isShortAnswer = normalizedType === 'short' || normalizedType === 'short answer';
    const isCheckboxType = normalizedType === 'checkbox' || normalizedType === 'yes/no';
    const isLinear = normalizedType === 'linear' || normalizedType === 'linear scale';
    const showMultipleOptions = isMultiple || isCheckboxType;
    const showLinearScale = isLinear;
    const err = (errors && errors[q.id]) || {};
    let options = (q.options || []).map((opt, optIdx) => ({
        id: opt.id || generateId(),
        value: String(opt.value ?? '').trim() || (isLinear ? String(optIdx + 1) : (opt.text || '')),
        text: opt.text || '',
        letter: opt.letter || String.fromCharCode(97 + optIdx)
    }));
    if (isLinear && !options.length) {
        options = buildScalePoints(DEFAULT_SCALE_POINTS, []);
    }
    return {
        ...q,
        id: q.id || generateId(),
        number: q.number ?? idx + 1,
        type,
        required: !!q.required,
        options,
        showMultipleOptions,
        showLinearScale,
        showRequiredToggle: !hideRequired,
        isMultiple,
        isCheckboxType,
        isShortAnswer,
        nextOptionNumber: (options.length || 0) + 1,
        scalePointCount: String(isLinear ? options.length : DEFAULT_SCALE_POINTS),
        textError: err.text || '',
        optionsError: err.options || '',
        questionInputClass: err.text ? 'custom-input qb-input-error' : 'custom-input'
    };
}

/**
 * Reusable questionnaire / survey question builder.
 * Drop-in for the inline question editors that used to live in kenFeedbackForm,
 * kenCreateSurvey, kenGroupPostPoll, etc.
 *
 * Input:  questions = [{ id, text, type, required, options:[{id,value,text,letter}] }]
 * Output: fires `change` with detail { questions: [...clean serialized list...] } on every edit.
 *
 * A linear scale carries its points in `options` — value is the point the respondent submits,
 * text is that point's label.
 */
export default class KenQuestionnaireBuilder extends LightningElement {
    @track _questions = [];
    @track _errors = {};
    _questionTypes = null;
    _selfUpdate = false;

    @api hideRequired = false;
    @api hideAddButton = false;
    @api addButtonLabel = 'Add new question';
    @api questionPlaceholder = 'Enter your question here';
    draggedQuestionId = null;

    @api
    get questions() {
        return this._questions;
    }
    set questions(value) {
        // Ignore the parent feeding back the value we just emitted (keeps focus/cursor stable
        // and stops the card from re-rendering mid-edit). External seeds still apply.
        if (this._selfUpdate) {
            this._selfUpdate = false;
            return;
        }
        this._questions = Array.isArray(value)
            ? value.map(q => {
                const type = canonicalType(q.type);
                const options = isLinearType(type) && !(q.options || []).length
                    ? buildScalePoints(DEFAULT_SCALE_POINTS, [])
                    : q.options;
                return { ...q, type, options };
            })
            : [];
    }

    @api
    get questionTypes() {
        return this._questionTypes;
    }
    set questionTypes(value) {
        this._questionTypes = Array.isArray(value) && value.length ? value : null;
    }

    /** Public accessor so a parent can read the current list imperatively. */
    @api
    getQuestions() {
        return this.serialize();
    }

    /** Public helper so a parent "Add question" button can drive this builder. */
    @api
    addQuestion() {
        this.handleAddQuestion();
    }

    get questionTypeOptions() {
        return this._questionTypes || DEFAULT_QUESTION_TYPES;
    }

    get scaleNumberOptions() {
        const options = [];
        for (let i = 2; i <= MAX_SCALE_POINTS; i++) {
            options.push({ label: String(i), value: String(i) });
        }
        return options;
    }

    get normalizedQuestions() {
        return (this._questions || []).map((q, idx) => normalizeQuestion(q, idx, this.hideRequired, this._errors));
    }

    /**
     * Validate the current questions and show inline errors. Returns true when every question
     * has a label, and every Multiple-choice / Checkbox question has at least 2 non-empty options.
     * Parents call this before persisting (e.g. the feedback form's "Save Form").
     */
    @api
    validate() {
        const errors = {};
        let valid = true;
        (this._questions || []).forEach(q => {
            const qErr = {};
            if (!String(q.text || '').trim()) {
                qErr.text = 'Question is required';
                valid = false;
            }
            const t = String(q.type || '').toLowerCase();
            const needsOptions = t === 'multiple' || t === 'multiple choice' || t === 'checkbox' || t === 'yes/no';
            if (needsOptions) {
                const filled = (q.options || []).filter(o => String(o.text || '').trim()).length;
                if (filled < 2) {
                    qErr.options = 'Add at least 2 options';
                    valid = false;
                }
            }
            if (Object.keys(qErr).length) {
                errors[q.id] = qErr;
            }
        });
        this._errors = errors;
        return valid;
    }

    clearError(questionId, key) {
        if (!this._errors || !this._errors[questionId]) return;
        const next = { ...this._errors };
        const q = { ...next[questionId] };
        delete q[key];
        if (Object.keys(q).length) {
            next[questionId] = q;
        } else {
            delete next[questionId];
        }
        this._errors = next;
    }

    get showAddButton() {
        return !this.hideAddButton;
    }

    serialize() {
        return (this._questions || []).map((q, i) => {
            const linear = isLinearType(q.type);
            return {
                id: q.id || generateId(),
                text: q.text || '',
                type: q.type || 'Multiple Choice',
                required: !!q.required,
                options: (q.options || []).map((o, oi) => ({
                    id: o.id || generateId(),
                    value: linear
                        ? (String(o.value ?? '').trim() || String(oi + 1))
                        : (o.text || ''),
                    text: o.text || '',
                    letter: o.letter || String.fromCharCode(97 + oi)
                })),
                number: i + 1
            };
        });
    }

    emitChange() {
        // NOTE: event name is intentionally 'questionschange', NOT 'change' — internal
        // lightning-input/combobox 'change' events bubble out (composed) and would otherwise
        // be caught by a parent's onchange handler, clobbering the questions list.
        this._selfUpdate = true;
        this.dispatchEvent(new CustomEvent('questionschange', {
            detail: { questions: this.serialize() }
        }));
    }

    handleAddQuestion() {
        const newQ = {
            id: generateId(),
            text: '',
            type: 'Multiple Choice',
            required: false,
            options: [
                { id: generateId(), value: '', text: '', letter: 'a' },
                { id: generateId(), value: '', text: '', letter: 'b' }
            ],
            number: this._questions.length + 1
        };
        this._questions = [...this._questions, newQ];
        this.emitChange();
    }

    handleDeleteQuestion(event) {
        const questionId = event.currentTarget.dataset.questionId;
        this._questions = this._questions
            .filter(q => q.id !== questionId)
            .map((q, i) => ({ ...q, number: i + 1 }));
        this.clearError(questionId, 'text');
        this.clearError(questionId, 'options');
        this.emitChange();
    }

    handleQuestionTextChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value ?? '';
        this._questions = this._questions.map(q => q.id === questionId ? { ...q, text: value } : q);
        if (String(value).trim()) {
            this.clearError(questionId, 'text');
        }
        this.emitChange();
    }

    handleQuestionTypeChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value ?? 'Multiple Choice';
        const normalizedType = String(value).toLowerCase();
        const isMultiple = normalizedType === 'multiple' || normalizedType === 'multiple choice';
        const isCheckboxType = normalizedType === 'checkbox' || normalizedType === 'yes/no';
        const showMultipleOptions = isMultiple || isCheckboxType;
        const existing = this._questions.find(q => q.id === questionId);
        const wasLinear = isLinearType(existing?.type);
        let options = [];
        if (showMultipleOptions) {
            const kept = wasLinear ? [] : (existing?.options || []);
            options = kept.length ? kept : [
                { id: generateId(), value: '', text: '', letter: 'a' },
                { id: generateId(), value: '', text: '', letter: 'b' }
            ];
        } else if (isLinearType(value)) {
            options = buildScalePoints(
                wasLinear ? (existing?.options?.length || DEFAULT_SCALE_POINTS) : DEFAULT_SCALE_POINTS,
                wasLinear ? existing.options : []
            );
        }
        this._questions = this._questions.map(q => {
            if (q.id !== questionId) return q;
            return { ...q, type: value, options };
        });
        // Switching type changes whether options are needed — drop any stale options error.
        this.clearError(questionId, 'options');
        this.emitChange();
    }

    handleRequiredToggle(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.target.checked;
        this._questions = this._questions.map(q => q.id === questionId ? { ...q, required: value } : q);
        this.emitChange();
    }

    handleOptionTextChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const optionId = event.currentTarget.dataset.optionId;
        const value = event.detail?.value ?? event.target.value ?? '';
        this._questions = this._questions.map(q => {
            if (q.id !== questionId) return q;
            const options = (q.options || []).map(opt => opt.id === optionId ? { ...opt, text: value } : opt);
            return { ...q, options };
        });
        if (String(value).trim()) {
            this.clearError(questionId, 'options');
        }
        this.emitChange();
    }

    handleAddOptionClick(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const q = this._questions.find(qq => qq.id === questionId);
        if (!q) return;
        const options = q.options || [];
        const nextLetter = String.fromCharCode(97 + options.length);
        const newOpt = { id: generateId(), value: '', text: '', letter: nextLetter };
        this._questions = this._questions.map(qq =>
            qq.id === questionId ? { ...qq, options: [...(qq.options || []), newOpt] } : qq
        );
        this.emitChange();
    }

    handleDeleteOption(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const optionId = event.currentTarget.dataset.optionId;
        this._questions = this._questions.map(q => {
            if (q.id !== questionId) return q;
            const options = (q.options || []).filter(o => o.id !== optionId);
            return { ...q, options };
        });
        this.emitChange();
    }

    handleScalePointCountChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const count = parseInt(event.detail?.value ?? event.target.value, 10) || DEFAULT_SCALE_POINTS;
        this._questions = this._questions.map(q =>
            q.id === questionId ? { ...q, options: buildScalePoints(count, q.options) } : q
        );
        this.emitChange();
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
        const arr = [...this._questions];
        const fromIdx = arr.findIndex(q => q.id === fromId);
        const toIdx = arr.findIndex(q => q.id === toId);
        if (fromIdx === -1 || toIdx === -1) return;
        const [removed] = arr.splice(fromIdx, 1);
        arr.splice(toIdx, 0, removed);
        this._questions = arr.map((q, i) => ({ ...q, number: i + 1 }));
        this.emitChange();
    }
}