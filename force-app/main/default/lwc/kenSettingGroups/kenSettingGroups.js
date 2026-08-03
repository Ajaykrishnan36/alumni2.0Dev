import { LightningElement, track } from 'lwc';
import getGroupPreferences from '@salesforce/apex/KenProfileSettingsController.getGroupPreferences';
import saveGroupPreferences from '@salesforce/apex/KenProfileSettingsController.saveGroupPreferences';

const INVITE_OPTIONS  = ['Everyone', 'Only other alumni', 'Only admin'];
const NOTIFY_OPTIONS  = ['New posts', 'New members', 'Polls', 'Events'];

export default class KenSettingGroups extends LightningElement {
    @track isLoading = true;
    @track isSaving  = false;
    @track showSuccessPopup = false;
    @track error = null;

    @track whoCanInvite  = 'Everyone';
    @track updatesEnabled = true;
    @track notifyFor = [];

    connectedCallback() { this.loadData(); }

    async loadData() {
        this.isLoading = true;
        this.error = null;
        try {
            const data = await getGroupPreferences();
            this.whoCanInvite  = data?.whoCanInvite  || 'Everyone';
            this.updatesEnabled = data?.receiveUpdates !== false;
            this.notifyFor = this._buildCheckboxList(NOTIFY_OPTIONS, data?.notifyFor);
        } catch (e) {
            this.error = e?.body?.message || 'Failed to load group preferences.';
        } finally {
            this.isLoading = false;
        }
    }

    _buildCheckboxList(options, savedValue) {
        const selected = new Set(savedValue ? savedValue.split(';').map(v => v.trim()) : []);
        return options.map(o => ({ label: o, value: o, checked: selected.has(o) }));
    }

    get inviteOptions() {
        return INVITE_OPTIONS.map(o => ({ label: o, value: o, checked: this.whoCanInvite === o }));
    }

    handleInviteChange(event)  { this.whoCanInvite   = event.target.value; }
    handleUpdateToggle(event)  { this.updatesEnabled = event.target.checked; }

    handleNotifyForChange(event) {
        const val = event.target.dataset.value;
        this.notifyFor = this.notifyFor.map(o => o.value === val ? { ...o, checked: event.target.checked } : o);
    }

    handleDiscard() { this.loadData(); }

    async handleSave() {
        this.isSaving = true;
        this.error = null;
        try {
            await saveGroupPreferences({
                requestJson: JSON.stringify({
                    whoCanInvite:   this.whoCanInvite,
                    receiveUpdates: this.updatesEnabled,
                    notifyFor:      this.notifyFor.filter(o => o.checked).map(o => o.value).join(';')
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