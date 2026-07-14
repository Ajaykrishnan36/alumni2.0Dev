import { LightningElement, api } from 'lwc';

export default class KenEventQuestionnaireV2 extends LightningElement {
    @api survey;
    @api event;

    get hasSurvey() { return !!this.survey; }
    get surveyTitle() { return this.survey ? (this.survey.title || 'Questionnaire') : 'Questionnaire'; }
    get description() { return this.survey ? (this.survey.description || '') : ''; }
    get eventTitle() { return this.event ? this.event.title : ''; }

    get audience() {
        return ((this.survey && this.survey.audience) || []).map((a, i) => ({
            ...a,
            key: a.id || `a-${i}`
        }));
    }
    get questions() {
        return ((this.survey && this.survey.questions) || []).map((q, i) => {
            const isScale = q.type === 'scale';
            const isText  = q.type === 'text';
            const responses = (q.responses || []).map((r, j) => ({
                ...r,
                key: `${q.id || i}-r-${j}`,
                barStyle: `width:${r.pct || 0}%`
            }));
            const topResponses = (q.topResponses || []).map((t, j) => ({
                key: `${q.id || i}-t-${j}`,
                text: t
            }));
            return {
                ...q,
                key: q.id || `q-${i}`,
                indexLabel: `Question ${q.index || (i + 1)}`,
                isScale,
                isText,
                responses,
                topResponses
            };
        });
    }
    get hasAudience()  { return this.audience.length > 0; }
    get hasQuestions() { return this.questions.length > 0; }

    handleBack() { this.dispatchEvent(new CustomEvent('back')); }
}