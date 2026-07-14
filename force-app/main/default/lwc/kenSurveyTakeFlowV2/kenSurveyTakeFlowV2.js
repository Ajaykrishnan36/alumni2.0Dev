// Single-page survey-taking flow (no question paging).
// Renders all questions vertically; user submits at the bottom.
import { LightningElement, api, track } from 'lwc';

const DEFAULT_QUESTIONS = [
    { id: 'q1', type: 'rating5',  title: 'How would you rate the overall quality of this session?', hint: '1 = Dissatisfied, 5 = Satisfied' },
    { id: 'q2', type: 'rating5',  title: 'How engaged were you during the session?', hint: '1 = Disengaged, 5 = Engaged' },
    { id: 'q3', type: 'radio',    title: 'Did the session meet your expectations?', hint: 'Single choice', opts: ['Yes', 'Somewhat', 'No'] },
    { id: 'q4', type: 'long',     title: 'Any other feedback you would like to share?', hint: 'Optional' }
];

export default class KenSurveyTakeFlowV2 extends LightningElement {
    @api survey = {};
    @api questions;

    @track responses = {};
    @track anonymous = false;

    get effectiveQuestions() {
        return (this.questions && this.questions.length) ? this.questions : DEFAULT_QUESTIONS;
    }
    get totalQuestions() { return this.effectiveQuestions.length; }
    get answeredCount() {
        let c = 0;
        this.effectiveQuestions.forEach(q => {
            const a = this.responses[q.id];
            if (a !== undefined && a !== null && a !== '' && !(Array.isArray(a) && a.length === 0)) c += 1;
        });
        return c;
    }
    get progressStyle() {
        const pct = (this.answeredCount / this.totalQuestions) * 100;
        return `width:${pct}%;`;
    }
    get progressLabel() { return `${this.answeredCount} of ${this.totalQuestions} questions completed`; }
    get title() { return (this.survey && this.survey.title) || 'Survey'; }

    get renderedQuestions() {
        return this.effectiveQuestions.map((q, i) => {
            const ans = this.responses[q.id];
            const out = {
                id: q.id,
                number: i + 1,
                title: q.title,
                hint: q.hint || '',
                isRating5: false, isRadio: false, isCheckbox: false, isText: false, isYesNo: false,
                ratingOpts: null, radioOpts: null, checkboxOpts: null, textValue: '',
                _key: q.id
            };
            if (q.type === 'rating5' || q.type === 'linear') {
                out.isRating5 = true;
                out.ratingOpts = [1,2,3,4,5].map(n => ({ n, cls: ans === n ? 'rating-num rating-num--on' : 'rating-num', key: q.id + '_r' + n }));
            } else if (q.type === 'radio') {
                out.isRadio = true;
                out.radioOpts = (q.opts || []).map(o => ({ value: o, label: o, cls: ans === o ? 'opt opt--selected' : 'opt', key: q.id + '_o_' + o }));
            } else if (q.type === 'checkbox') {
                out.isCheckbox = true;
                const arr = Array.isArray(ans) ? ans : [];
                out.checkboxOpts = (q.opts || []).map(o => ({ value: o, label: o, cls: arr.indexOf(o) >= 0 ? 'opt opt--selected' : 'opt', key: q.id + '_c_' + o }));
            } else if (q.type === 'yesno') {
                out.isYesNo = true;
                out.radioOpts = ['Yes', 'No'].map(o => ({ value: o, label: o, cls: ans === o ? 'pill-btn pill-btn--on' : 'pill-btn', key: q.id + '_yn_' + o }));
            } else {
                out.isText = true;
                out.textValue = ans || '';
            }
            return out;
        });
    }

    _setAns(qid, val) { this.responses = { ...this.responses, [qid]: val }; }

    handleRating(e) {
        const qid = e.currentTarget.dataset.qid;
        const n = Number(e.currentTarget.dataset.n);
        this._setAns(qid, n);
    }
    handleRadio(e) {
        const qid = e.currentTarget.dataset.qid;
        this._setAns(qid, e.currentTarget.dataset.val);
    }
    handleCheckbox(e) {
        const qid = e.currentTarget.dataset.qid;
        const val = e.currentTarget.dataset.val;
        const cur = Array.isArray(this.responses[qid]) ? [...this.responses[qid]] : [];
        const idx = cur.indexOf(val);
        if (idx >= 0) cur.splice(idx, 1); else cur.push(val);
        this._setAns(qid, cur);
    }
    handleText(e) {
        const qid = e.currentTarget.dataset.qid;
        this._setAns(qid, e.target.value);
    }
    handleAnonymous(e) { this.anonymous = e.target.checked; }

    handleSubmit() {
        this.dispatchEvent(new CustomEvent('submit', { detail: {
            responses: this.responses,
            anonymous: this.anonymous,
            surveyId: this.survey && this.survey.id
        } }));
    }
    handleSaveDraft() {
        // Simple optimistic save — emits a draft event the parent may ignore
        this.dispatchEvent(new CustomEvent('savedraft', { detail: { responses: this.responses } }));
    }
    handleCancel() { this.dispatchEvent(new CustomEvent('close')); }
}