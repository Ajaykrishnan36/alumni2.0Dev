import { LightningElement, api } from 'lwc';

export default class KenSurveyCreateStepQuestionsV2 extends LightningElement {
    @api questions = [];

    get questionRows() {
        return (this.questions || []).map((q, i) => ({
            ...q,
            n: i + 1,
            hasOpts: q.type === 'radio' || q.type === 'multi',
            optionItems: (q.opts || []).map((o, oi) => ({ key: `${q.id}-${oi}`, value: o }))
        }));
    }

    handleAdd() {
        this.dispatchEvent(new CustomEvent('addquestion'));
    }
    handleRemove(event) {
        this.dispatchEvent(new CustomEvent('removequestion', { detail: { id: event.currentTarget.dataset.id } }));
    }
    handleText(event) {
        this.dispatchEvent(new CustomEvent('questiontext', { detail: { id: event.currentTarget.dataset.id, value: event.target.value } }));
    }
    handleType(event) {
        this.dispatchEvent(new CustomEvent('questiontype', { detail: { id: event.currentTarget.dataset.id, value: event.target.value } }));
    }
    handleAddOption(event) {
        this.dispatchEvent(new CustomEvent('addoption', { detail: { id: event.currentTarget.dataset.id } }));
    }
}