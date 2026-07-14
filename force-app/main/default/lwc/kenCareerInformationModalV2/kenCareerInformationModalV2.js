import { LightningElement, api, track } from 'lwc';

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const EMPLOYMENT_TYPES = ['Full-time','Part-time','Contract','Internship','Self-employed','Freelance'];

export default class KenCareerInformationModalV2 extends LightningElement {
    @api recordId;
    @api initialData;

    @track form = {
        role: 'organization', // 'business' | 'organization'
        jobTitle: '',
        company: '',
        employmentType: '',
        location: '',
        startMonth: '', startYear: '',
        endMonth: '', endYear: '',
        currentlyWorking: false,
        description: ''
    };

    connectedCallback() {
        if (this.initialData) this.form = { ...this.form, ...this.initialData };
    }

    get isBusiness() { return this.form.role === 'business'; }
    get isOrg() { return this.form.role === 'organization'; }
    get businessClass() { return this.isBusiness ? 'seg seg--on' : 'seg'; }
    get orgClass() { return this.isOrg ? 'seg seg--on' : 'seg'; }
    get companyLabel() { return this.isBusiness ? 'Business Name*' : 'Company / Organization*'; }

    get monthOptions() { return [{label:'Month', value:''}, ...MONTHS.map((m,i)=>({label:m, value: String(i+1)}))]; }
    get yearOptions() {
        const y = new Date().getFullYear();
        const yrs = Array.from({length: 60}, (_, i) => `${y - i}`);
        return [{label:'Year', value:''}, ...yrs.map((v)=>({label:v, value:v}))];
    }
    get typeOptions() { return [{label:'Choose', value:''}, ...EMPLOYMENT_TYPES.map((v)=>({label:v, value:v}))]; }

    handleInput(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.form = { ...this.form, [field]: value };
    }
    setBusiness() { this.form = { ...this.form, role: 'business' }; }
    setOrg() { this.form = { ...this.form, role: 'organization' }; }

    handleDescription(event) {
        this.form = { ...this.form, description: event.target.innerHTML };
    }
    handleBold() { document.execCommand('bold'); }
    handleItalic() { document.execCommand('italic'); }
    handleBullets() { document.execCommand('insertUnorderedList'); }
    handleNumbered() { document.execCommand('insertOrderedList'); }
    handleAi() { this.dispatchEvent(new CustomEvent('aiwrite', { detail: { context: this.form } })); }

    cancel() { this.dispatchEvent(new CustomEvent('cancel')); }
    save() { this.dispatchEvent(new CustomEvent('save', { detail: { id: this.recordId, ...this.form } })); }
    stopProp(e) { e.stopPropagation(); }
}