import { LightningElement, api, track } from 'lwc';

const FB_TYPES = [
    { value: 'rating', label: 'Star Rating (1–5)' },
    { value: 'short', label: 'Short Text' },
    { value: 'long', label: 'Long Comment' },
    { value: 'yesno', label: 'Yes / No' }
];

let SEQ = 1;

export default class KenEventStepFeedbackV2 extends LightningElement {
    // Seed from the wizard so the form survives navigating between steps.
    @api feedbackData;

    @track enabled = true;
    @track questions = [];

    connectedCallback() {
        const d = this.feedbackData || {};
        this.enabled = d.enabled === undefined ? true : !!d.enabled;
        if (Array.isArray(d.questions) && d.questions.length) {
            this.questions = d.questions.map(q => ({
                id: q.id || `fb${SEQ++}`,
                text: q.text || '',
                type: q.type || 'rating'
            }));
        } else {
            // Sensible default so the step is never blank.
            this.questions = [
                { id: `fb${SEQ++}`, text: 'How would you rate this event overall?', type: 'rating' },
                { id: `fb${SEQ++}`, text: 'What did you like most, and what could we improve?', type: 'long' }
            ];
        }
    }

    get typeOptions() { return FB_TYPES; }
    get switchClass() { return this.enabled ? 'switch switch--on' : 'switch'; }
    get questionsWithIndex() {
        return this.questions.map((q, i) => ({
            ...q,
            number: i + 1,
            options: FB_TYPES.map(t => ({ ...t, selected: t.value === q.type }))
        }));
    }

    handleToggleEnabled() { this.enabled = !this.enabled; this._emit(); }

    handleText(e) {
        const id = e.currentTarget.dataset.id;
        const val = e.target.value;
        this.questions = this.questions.map(q => q.id === id ? { ...q, text: val } : q);
        this._emit();
    }
    handleType(e) {
        const id = e.currentTarget.dataset.id;
        const val = e.target.value;
        this.questions = this.questions.map(q => q.id === id ? { ...q, type: val } : q);
        this._emit();
    }
    handleAdd() {
        this.questions = [...this.questions, { id: `fb${SEQ++}`, text: '', type: 'rating' }];
        this._emit();
    }
    handleRemove(e) {
        const id = e.currentTarget.dataset.id;
        this.questions = this.questions.filter(q => q.id !== id);
        this._emit();
    }

    _emit() {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                field: 'feedbackForm',
                value: {
                    enabled: this.enabled,
                    questions: this.questions.map(q => ({ id: q.id, text: q.text, type: q.type }))
                }
            }
        }));
    }
}