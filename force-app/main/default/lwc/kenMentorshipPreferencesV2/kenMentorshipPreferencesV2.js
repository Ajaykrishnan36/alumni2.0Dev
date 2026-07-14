import { LightningElement, track } from 'lwc';
import getMyPreferences from '@salesforce/apex/KenAlumniPreferencesController.getMyPreferences';
import savePreferences from '@salesforce/apex/KenAlumniPreferencesController.savePreferences';

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const EXPERTISE = ['Project Management', 'Design', 'Development'];
const COMMS = ['Email', 'SMS', 'Whatsapp', 'In-person meeting'];
const MENTEE_TYPES = ['Students', 'Recent Graduates', 'Mid-career Professionals', 'Career Switchers', 'Entrepreneurs'];

export default class KenMentorshipPreferencesV2 extends LightningElement {
    @track willing = false;
    @track days = [];
    @track startTime = '';
    @track endTime = '';
    @track expertise = [];
    @track comms = [];
    @track menteeTypes = [];
    @track unlimited = false;
    @track maxCapacity = null;

    @track loading = true;
    @track saving = false;
    @track savedOk = false;
    @track errorMsg = '';

    connectedCallback() { this.load(); }

    load() {
        this.loading = true;
        getMyPreferences()
            .then(p => {
                if (p) {
                    this.willing = p.willingToMentor === true;
                    this.days = this._split(p.availabilityDays);
                    this.startTime = this._toInputTime(p.availabilityStart);
                    this.endTime = this._toInputTime(p.availabilityEnd);
                    this.expertise = this._split(p.expertiseAreas);
                    this.comms = this._split(p.communicationModes);
                    this.menteeTypes = this._split(p.menteeTypes);
                    this.unlimited = p.unlimitedCapacity === true;
                    this.maxCapacity = p.maxCapacity;
                }
                this.loading = false;
            })
            .catch(e => { this.loading = false; this.errorMsg = this._msg(e); });
    }

    // ---- option lists for native checkbox groups (decorated with current `checked` state) ----
    _decorate(list, selected) {
        const sel = selected || [];
        return list.map(v => ({ label: v, value: v, checked: sel.indexOf(v) > -1 }));
    }
    get dayOptions()        { return this._decorate(DAYS, this.days); }
    get expertiseOptionsUi(){ return this._decorate(EXPERTISE, this.expertise); }
    get commOptions()       { return this._decorate(COMMS, this.comms); }
    get menteeTypeOptions() { return this._decorate(MENTEE_TYPES, this.menteeTypes); }

    // ---- handlers ----
    handleWilling(e) { this.willing = e.target.checked; }
    handleStart(e) { this.startTime = e.target.value; }
    handleEnd(e) { this.endTime = e.target.value; }
    handleUnlimited(e) { this.unlimited = e.target.checked; }
    handleCapacity(e) { this.maxCapacity = e.target.value ? Number(e.target.value) : null; }

    // Single generic handler for the four native checkbox groups.
    // data-group identifies the backing array; data-value carries the option.
    handleGroupToggle(e) {
        const group = e.target.dataset.group;
        const value = e.target.dataset.value;
        const checked = e.target.checked;
        const KEYS = { days: 'days', expertise: 'expertise', comms: 'comms', mentee: 'menteeTypes' };
        const key = KEYS[group];
        if (!key) return;
        const arr = (this[key] || []).slice();
        const idx = arr.indexOf(value);
        if (checked && idx === -1) arr.push(value);
        if (!checked && idx > -1) arr.splice(idx, 1);
        this[key] = arr;
    }

    get capacityDisabled() { return this.unlimited; }

    handleSave() {
        this.errorMsg = '';
        this.savedOk = false;
        // Times come from <input type="time"> already as 'HH:mm'.
        if (this.startTime && this.endTime && this.startTime >= this.endTime) {
            this.errorMsg = 'End time must be after start time.';
            return;
        }
        this.saving = true;
        const dto = {
            willingToMentor: this.willing,
            availabilityDays: this._join(this.days),
            availabilityStart: this.startTime || null,
            availabilityEnd: this.endTime || null,
            expertiseAreas: this._join(this.expertise),
            communicationModes: this._join(this.comms),
            menteeTypes: this._join(this.menteeTypes),
            unlimitedCapacity: this.unlimited,
            maxCapacity: this.unlimited ? null : this.maxCapacity
        };
        savePreferences({ dto })
            .then(() => { this.saving = false; this.savedOk = true; })
            .catch(e => { this.saving = false; this.errorMsg = this._msg(e); });
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }

    // ---- utils ----
    _split(s) { return s ? s.split(';').filter(x => x) : []; }
    _join(a) { return (a && a.length) ? a.join(';') : null; }
    _toInputTime(hhmm) { return hhmm || ''; }
    _msg(e) { return (e && e.body && e.body.message) || 'Something went wrong. Please try again.'; }
}