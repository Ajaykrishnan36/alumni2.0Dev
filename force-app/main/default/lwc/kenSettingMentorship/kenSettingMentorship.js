import { LightningElement, track } from 'lwc';
import getMentorshipPreferences from '@salesforce/apex/KenProfileSettingsController.getMentorshipPreferences';
import saveMentorshipPreferences from '@salesforce/apex/KenProfileSettingsController.saveMentorshipPreferences';

const DAYS_OPTIONS      = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const EXPERTISE_OPTIONS = ['Project Management', 'Design', 'Development'];
const COMM_OPTIONS      = ['Email', 'SMS', 'Whatsapp', 'In-person meeting'];

export default class KenSettingMentorship extends LightningElement {
    @track isLoading = true;
    @track isSaving  = false;
    @track showSuccessPopup = false;
    @track error = null;

    @track isMentor              = false;
    @track selectedDays          = [];
    @track availabilityStartTime = '';
    @track availabilityEndTime   = '';
    @track timeError             = '';
    @track selectedExpertises    = [];
    @track commModes             = [];
    @track showDaysDropdown      = false;
    @track showExpertiseDropdown = false;

    connectedCallback() {
        this.loadData();
        this._outsideClick = (e) => {
            if (this.template && !this.template.contains(e.target)) {
                this.showDaysDropdown      = false;
                this.showExpertiseDropdown = false;
            }
        };
        document.addEventListener('click', this._outsideClick);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._outsideClick);
    }

    async loadData() {
        this.isLoading = true;
        this.error = null;
        try {
            const data = await getMentorshipPreferences();
            this.isMentor                = data?.willingToBeMentor || false;
            this.selectedDays            = data?.availabilityDays ? data.availabilityDays.split(';').map(v => v.trim()).filter(Boolean) : [];
            this.availabilityStartTime   = data?.availabilityStartTime || '';
            this.availabilityEndTime     = data?.availabilityEndTime   || '';
            this.selectedExpertises      = data?.expertiseAreas   ? data.expertiseAreas.split(';').map(v => v.trim()).filter(Boolean) : [];
            this.commModes               = this._buildCheckboxList(COMM_OPTIONS, data?.commModes);
        } catch (e) {
            this.error = e?.body?.message || 'Failed to load mentorship preferences.';
        } finally {
            this.isLoading = false;
        }
    }

    _buildCheckboxList(options, savedValue) {
        const selected = new Set(savedValue ? savedValue.split(';').map(v => v.trim()) : []);
        return options.map(o => ({ label: o, value: o, checked: selected.has(o) }));
    }

    get isNotMentor() { return !this.isMentor; }

    get timeFieldsDisabled() { return this.isNotMentor; }

    _timeToMinutes(t) {
        if (!t) return null;
        const parts = t.split(':');
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    }

    handleStartTimeChange(event) {
        this.availabilityStartTime = event.detail?.value || event.target?.value || '';
        this._validateTime();
    }

    handleEndTimeChange(event) {
        this.availabilityEndTime = event.detail?.value || event.target?.value || '';
        this._validateTime();
    }

    _validateTime() {
        if (this.availabilityStartTime && this.availabilityEndTime) {
            const start = this._timeToMinutes(this.availabilityStartTime);
            const end   = this._timeToMinutes(this.availabilityEndTime);
            this.timeError = end <= start ? 'End time must be after start time.' : '';
        } else {
            this.timeError = '';
        }
    }

    get dayOptions() {
        return DAYS_OPTIONS.map(o => ({
            label: o, value: o,
            tickClass: this.selectedDays.includes(o) ? 'item-tick tick-active' : 'item-tick'
        }));
    }
    get dayLabel()             { return this.selectedDays.length ? this.selectedDays.join(', ') : 'Please select'; }
    get dayLabelClass()        { return this.selectedDays.length ? 'selected-value' : 'select-placeholder'; }
    get daysDropdownBoxClass() { return this.isNotMentor ? 'custom-dropdown-box disabled' : 'custom-dropdown-box'; }

    get expertiseOptions() {
        return EXPERTISE_OPTIONS.map(o => ({
            label: o, value: o,
            tickClass: this.selectedExpertises.includes(o) ? 'item-tick tick-active' : 'item-tick'
        }));
    }
    get expertiseLabel()           { return this.selectedExpertises.length ? this.selectedExpertises.join(', ') : 'Please select'; }
    get expertiseLabelClass()      { return this.selectedExpertises.length ? 'selected-value' : 'select-placeholder'; }
    get expertiseDropdownBoxClass(){ return this.isNotMentor ? 'custom-dropdown-box disabled' : 'custom-dropdown-box'; }

    handleMentorToggle(event) { this.isMentor = event.target.checked; }

    toggleDaysDropdown(event)  { if (!this.isNotMentor) { event.stopPropagation(); this.showDaysDropdown = !this.showDaysDropdown; } }
    handleToggleDay(event) {
        event.stopPropagation();
        const val = event.currentTarget.dataset.value;
        if (this.selectedDays.includes(val)) {
            this.selectedDays = this.selectedDays.filter(v => v !== val);
        } else {
            this.selectedDays = [...this.selectedDays, val];
        }
    }

    toggleExpertiseDropdown(event) { if (!this.isNotMentor) { event.stopPropagation(); this.showExpertiseDropdown = !this.showExpertiseDropdown; } }
    handleToggleExpertise(event) {
        event.stopPropagation();
        const val = event.currentTarget.dataset.value;
        if (this.selectedExpertises.includes(val)) {
            this.selectedExpertises = this.selectedExpertises.filter(v => v !== val);
        } else {
            this.selectedExpertises = [...this.selectedExpertises, val];
        }
    }

    handleCommChange(event) {
        const val = event.target.dataset.value;
        this.commModes = this.commModes.map(o => o.value === val ? { ...o, checked: event.target.checked } : o);
    }

    handleDiscard() { this.loadData(); }

    async handleSave() {
        this._validateTime();
        if (this.timeError) return;
        this.isSaving = true;
        this.error = null;
        try {
            await saveMentorshipPreferences({
                requestJson: JSON.stringify({
                    willingToBeMentor:     this.isMentor,
                    availabilityDays:      this.selectedDays.join(';'),
                    availabilityStartTime: this.availabilityStartTime || '',
                    availabilityEndTime:   this.availabilityEndTime   || '',
                    expertiseAreas:        this.selectedExpertises.join(';'),
                    commModes:             this.commModes.filter(o => o.checked).map(o => o.value).join(';')
                })
            });
            this.showSuccessPopup = true;
            setTimeout(() => { this.showSuccessPopup = false; }, 3000);
        } catch (e) {
            this.error = e?.body?.message || 'Failed to save.';
        } finally {
            this.isSaving = false;
        }
    }
}