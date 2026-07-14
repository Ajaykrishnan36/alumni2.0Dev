import { LightningElement, api, track } from 'lwc';

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

export default class KenEducationInformationModalV2 extends LightningElement {
    @api recordId;
    @api initialData;

    @track form = {
        degree: '', institution: '',
        startMonth: '', startYear: '',
        endMonth: '', endYear: '',
        gradingFormat: 'cgpa',
        score: ''
    };

    connectedCallback() {
        if (this.initialData) this.form = { ...this.form, ...this.initialData };
    }

    get monthOptions() { return [{label:'Month', value:''}, ...MONTHS.map((m,i)=>({label:m, value: String(i+1)}))]; }
    get yearOptions() {
        const y = new Date().getFullYear();
        const yrs = Array.from({length: 60}, (_, i) => `${y - i}`);
        return [{label:'Year', value:''}, ...yrs.map((v)=>({label:v, value:v}))];
    }
    get isCgpa() { return this.form.gradingFormat === 'cgpa'; }
    get isPct() { return this.form.gradingFormat === 'pct'; }
    get cgpaDotClass() { return this.isCgpa ? 'radio__dot radio__dot--on' : 'radio__dot'; }
    get pctDotClass() { return this.isPct ? 'radio__dot radio__dot--on' : 'radio__dot'; }
    get scoreLabel() { return this.isCgpa ? 'CGPA (Optional)' : 'Percentage (Optional)'; }
    get scorePlaceholder() { return this.isCgpa ? 'e.g., 8.9' : 'e.g., 85'; }

    handleInput(event) {
        const field = event.target.dataset.field;
        if (field) this.form = { ...this.form, [field]: event.target.value };
    }
    setCgpa() { this.form = { ...this.form, gradingFormat: 'cgpa' }; }
    setPct()  { this.form = { ...this.form, gradingFormat: 'pct'  }; }
    cancel() { this.dispatchEvent(new CustomEvent('cancel')); }
    save() {
        this.dispatchEvent(new CustomEvent('save', { detail: { id: this.recordId, ...this.form } }));
    }
    stopProp(event) { event.stopPropagation(); }
}