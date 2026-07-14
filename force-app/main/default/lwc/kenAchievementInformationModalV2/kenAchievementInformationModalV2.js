import { LightningElement, api, track } from 'lwc';

const TYPE_OPTIONS = [
    'Honour / Award',
    'Academic Achievement',
    'Publication',
    'Certification',
    'Other'
];

export default class KenAchievementInformationModalV2 extends LightningElement {
    @api recordId;
    @api initialData;

    @track form = {
        type: 'Honour / Award',
        title: '',
        org: '',
        year: '',
        description: ''
    };

    connectedCallback() {
        if (this.initialData) {
            this.form = { ...this.form, ...this.initialData };
        }
    }

    get titleLabel() { return this.recordId ? 'Edit Achievement' : 'Add Achievement'; }

    get typeOptions() {
        return TYPE_OPTIONS.map(v => ({ label: v, value: v }));
    }

    get yearOptions() {
        const current = new Date().getFullYear();
        const yrs = [];
        for (let y = current; y >= 1900; y--) {
            yrs.push({ label: String(y), value: String(y) });
        }
        return [{ label: 'Year', value: '' }, ...yrs];
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        if (field) this.form = { ...this.form, [field]: event.target.value };
    }

    cancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }
    save() {
        const f = this.form || {};
        if (!(f.title || '').trim()) {
            this.dispatchEvent(new CustomEvent('validationerror', { detail: { message: 'Please enter a title.' } }));
            return;
        }
        this.dispatchEvent(new CustomEvent('save', {
            detail: {
                id: this.recordId || (this.initialData && this.initialData.id) || null,
                type: f.type || '',
                title: (f.title || '').trim(),
                org: (f.org || '').trim(),
                year: (f.year || '').toString().trim(),
                description: (f.description || '').trim()
            }
        }));
    }
    stopProp(event) { event.stopPropagation(); }
}