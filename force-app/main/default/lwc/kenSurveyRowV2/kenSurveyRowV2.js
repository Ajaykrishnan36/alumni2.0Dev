import { LightningElement, api } from 'lwc';

const STATUS_META = {
    Upcoming:  { label: 'Upcoming',  cls: 'row__pill pill--upcoming',  rowMod: 'row--upcoming'  },
    Ongoing:   { label: '● Ongoing', cls: 'row__pill pill--ongoing',   rowMod: 'row--ongoing'   },
    Completed: { label: 'Completed', cls: 'row__pill pill--completed', rowMod: 'row--completed' },
    Pending:   { label: 'Pending',   cls: 'row__pill pill--upcoming',  rowMod: 'row--upcoming'  },
    Rejected:  { label: 'Rejected',  cls: 'row__pill pill--rejected',  rowMod: 'row--rejected'  }
};

export default class KenSurveyRowV2 extends LightningElement {
    @api recordId;
    @api title;
    @api status;
    @api totalQuestions = 0;
    @api responses;
    @api periodStart;
    @api periodEnd;
    @api period;

    get periodLabel() {
        if (this.period) return this.period;
        if (this.periodStart && this.periodEnd) return `${this.periodStart} – ${this.periodEnd}`;
        return this.periodStart || this.periodEnd || '';
    }
    get questionsCount() { return this.totalQuestions; }
    get responsesText() {
        if (this.responses == null || this.responses === '') return '-';
        return String(this.responses);
    }
    get pillLabel() {
        const m = STATUS_META[this.status];
        return m ? m.label : this.status || '';
    }
    get pillClass() {
        const m = STATUS_META[this.status];
        return m ? m.cls : 'row__pill pill--upcoming';
    }
    get cardClass() {
        const m = STATUS_META[this.status];
        return m ? `row ${m.rowMod}` : 'row row--upcoming';
    }

    handleView(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('view', { detail: { id: this.recordId } }));
    }
    // QA Bug #119: emit 'edit' so parent can route into the survey wizard in edit mode.
    handleEdit(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('edit', { detail: { id: this.recordId } }));
    }
    handleRowClick() {
        this.dispatchEvent(new CustomEvent('view', { detail: { id: this.recordId } }));
    }
}