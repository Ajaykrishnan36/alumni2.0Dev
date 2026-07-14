import { LightningElement, api, track } from 'lwc';

/**
 * Feedback / Survey view — "Alumni Engagement Survey".
 * Anonymous toggle, a live progress bar, a multi-select question and a free-text
 * question. Pure SLDS HTML — native checkboxes/textarea, no lightning-*.
 */
const TOTAL_QUESTIONS = 5;

const Q1_OPTIONS = [
    'Networking & Reunions',
    'Career & Professional Development',
    'Workshops & Skill Building',
    'Mentorship Programs',
    'Fundraising & Giving Back',
    'Cultural & Social Events'
];

export default class KenEventFeedbackV2 extends LightningElement {
    @api event = {};

    @track anonymous = false;
    @track q1Selected = [];
    @track q2Text = '';
    @track submitted = false;

    get q1Options() {
        return Q1_OPTIONS.map(o => ({
            label: o,
            checked: this.q1Selected.indexOf(o) > -1
        }));
    }

    // ── progress ──
    get completedCount() {
        let n = 0;
        if (this.q1Selected.length > 0) n += 1;
        if ((this.q2Text || '').trim().length > 0) n += 1;
        return n;
    }
    get totalQuestions() { return TOTAL_QUESTIONS; }
    get progressLabel() { return `${this.completedCount} of ${TOTAL_QUESTIONS} questions completed`; }
    get progressStyle() { return `width:${Math.round((this.completedCount / TOTAL_QUESTIONS) * 100)}%`; }
    get anonToggleClass() { return this.anonymous ? 'toggle toggle--on' : 'toggle'; }
    get submitDisabled() { return this.completedCount === 0; }

    // ── handlers ──
    toggleAnonymous() { this.anonymous = !this.anonymous; }

    handleQ1(event) {
        const val = event.target.value;
        const checked = event.target.checked;
        const set = new Set(this.q1Selected);
        if (checked) set.add(val); else set.delete(val);
        this.q1Selected = Array.from(set);
    }
    handleQ2(event) { this.q2Text = event.target.value; }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('back', { bubbles: true, composed: true }));
    }
    handleSubmit() {
        if (this.submitDisabled) {
            this.dispatchEvent(new CustomEvent('notify', { detail: { message: 'Please answer at least one question.' }, bubbles: true, composed: true }));
            return;
        }
        this.submitted = true;
        this.dispatchEvent(new CustomEvent('notify', {
            detail: { message: this.anonymous ? 'Anonymous feedback submitted — thank you!' : 'Feedback submitted — thank you!' },
            bubbles: true, composed: true
        }));
    }
    handleBack() {
        this.dispatchEvent(new CustomEvent('back', { bubbles: true, composed: true }));
    }
}