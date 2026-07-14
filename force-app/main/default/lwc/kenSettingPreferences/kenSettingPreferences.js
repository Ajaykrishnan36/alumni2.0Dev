import { LightningElement, track } from 'lwc';
import getPreferences from '@salesforce/apex/KenSettingsController.getPreferences';
import savePreferences from '@salesforce/apex/KenSettingsController.savePreferences';

const COMM_OPTIONS   = ['Email', 'SMS', 'In-app'];
const NOTIFY_OPTIONS = ['Events', 'Jobs', 'Mentorship requests', 'Fundraise', 'Groups', 'Survey', 'Service & Support', 'Updates'];
const FREQ_OPTIONS   = ['Daily', 'Weekly', 'Monthly'];

export default class KenSettingPreferences extends LightningElement {
    @track isLoading = true;
    @track isSaving  = false;
    @track showSuccessPopup = false;
    @track showModal = false;
    @track error = null;

    @track isPrivateAccount      = false;
    @track commMethods           = [];
    @track howOften              = '';
    @track notifyRealTime        = false;
    @track selectedNotifyFor     = [];
    @track showNotifyForDropdown = false;

    connectedCallback() {
        this.loadData();
        this._outsideClick = (e) => {
            if (this.template && !this.template.contains(e.target)) {
                this.showNotifyForDropdown = false;
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
            const data = await getPreferences();
            this.isPrivateAccount    = data?.isPrivateAccount || false;
            this.howOften            = data?.howOften || 'Daily';
            this.notifyRealTime      = data?.notifyRealTime || false;
            this.commMethods         = this._buildCheckboxList(COMM_OPTIONS, data?.preferredCommunication);
            this.selectedNotifyFor   = data?.notifyFor ? data.notifyFor.split(';').map(v => v.trim()).filter(Boolean) : [];
        } catch (e) {
            this.error = e?.body?.message || 'Failed to load preferences.';
        } finally {
            this.isLoading = false;
        }
    }

    _buildCheckboxList(options, savedValue) {
        const selected = new Set(savedValue ? savedValue.split(';').map(v => v.trim()) : []);
        return options.map(o => ({ label: o, value: o, checked: selected.has(o) }));
    }

    get freqOptions() {
        return FREQ_OPTIONS.map(o => ({ label: o, value: o, checked: this.howOften === o }));
    }

    get notifyForOptions() {
        return NOTIFY_OPTIONS.map(o => ({
            label: o, value: o,
            tickClass: this.selectedNotifyFor.includes(o) ? 'item-tick tick-active' : 'item-tick'
        }));
    }

    get notifyForLabel()     { return this.selectedNotifyFor.length ? this.selectedNotifyFor.join(', ') : 'Please select'; }
    get notifyForLabelClass(){ return this.selectedNotifyFor.length ? 'selected-value' : 'select-placeholder'; }

    get isNotifyRealTimeOn()  { return this.notifyRealTime === true; }
    get isNotifyRealTimeOff() { return this.notifyRealTime !== true; }

    handlePrivateAccountChange(event) {
        if (event.target.checked) {
            this.showModal = true;
            event.target.checked = false;
        } else {
            this.isPrivateAccount = false;
        }
    }

    closeModal() { this.showModal = false; }

    confirmPrivate() {
        this.showModal = false;
        this.isPrivateAccount = true;
    }

    handleCommChange(event) {
        const val = event.target.dataset.value;
        this.commMethods = this.commMethods.map(o => o.value === val ? { ...o, checked: event.target.checked } : o);
    }

    handleFreqChange(event)     { this.howOften = event.target.value; }
    handleRealTimeChange(event) { this.notifyRealTime = event.target.value === 'on'; }

    toggleNotifyForDropdown(event) { event.stopPropagation(); this.showNotifyForDropdown = !this.showNotifyForDropdown; }

    handleToggleNotifyFor(event) {
        event.stopPropagation();
        const val = event.currentTarget.dataset.value;
        if (this.selectedNotifyFor.includes(val)) {
            this.selectedNotifyFor = this.selectedNotifyFor.filter(v => v !== val);
        } else {
            this.selectedNotifyFor = [...this.selectedNotifyFor, val];
        }
    }

    handleDiscard() { this.loadData(); }

    async handleSave() {
        this.isSaving = true;
        this.error = null;
        try {
            await savePreferences({
                requestJson: JSON.stringify({
                    isPrivateAccount: this.isPrivateAccount,
                    preferredCommunication: this.commMethods.filter(o => o.checked).map(o => o.value).join(';'),
                    howOften: this.howOften,
                    notifyRealTime: this.notifyRealTime,
                    notifyFor: this.selectedNotifyFor.join(';')
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