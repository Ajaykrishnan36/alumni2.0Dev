import { LightningElement, track } from 'lwc';
import getEventPreferences from '@salesforce/apex/KenProfileSettingsController.getEventPreferences';
import saveEventPreferences from '@salesforce/apex/KenProfileSettingsController.saveEventPreferences';

const INVITE_OPTIONS   = ['Everyone', 'Only other alumni', 'Only admin'];
const REMINDER_OPTIONS = ['One week before the event', 'One day before the event'];

export default class KenSettingEvents extends LightningElement {
    @track isLoading = true;
    @track isSaving  = false;
    @track showSuccessPopup = false;
    @track error = null;

    @track whoCanInvite         = 'Everyone';
    @track updatesEnabled       = true;
    @track reminderFrequency    = '';
    @track showReminderDropdown = false;

    connectedCallback() {
        this.loadData();
        this._outsideClick = (e) => {
            if (this.template && !this.template.contains(e.target)) {
                this.showReminderDropdown = false;
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
            const data = await getEventPreferences();
            this.whoCanInvite      = data?.whoCanInvite     || 'Everyone';
            this.updatesEnabled    = data?.receiveAlerts    !== false;
            this.reminderFrequency = data?.reminderFrequency || '';
        } catch (e) {
            this.error = e?.body?.message || 'Failed to load event preferences.';
        } finally {
            this.isLoading = false;
        }
    }

    get inviteOptions() {
        return INVITE_OPTIONS.map(o => ({ label: o, value: o, checked: this.whoCanInvite === o }));
    }

    get reminderOptions()    { return REMINDER_OPTIONS.map(o => ({ label: o, value: o })); }
    get reminderLabel()      { return this.reminderFrequency || 'Please select'; }
    get reminderLabelClass() { return this.reminderFrequency ? 'selected-value' : 'select-placeholder'; }

    handleInviteChange(event)    { this.whoCanInvite   = event.target.value; }
    handleUpdateToggle(event)    { this.updatesEnabled = event.target.checked; }

    toggleReminderDropdown(event) { event.stopPropagation(); this.showReminderDropdown = !this.showReminderDropdown; }

    handleSelectReminder(event) {
        event.stopPropagation();
        this.reminderFrequency = event.currentTarget.dataset.value;
        this.showReminderDropdown = false;
    }

    handleDiscard() { this.loadData(); }

    async handleSave() {
        this.isSaving = true;
        this.error = null;
        try {
            await saveEventPreferences({
                requestJson: JSON.stringify({
                    whoCanInvite:      this.whoCanInvite,
                    receiveAlerts:     this.updatesEnabled,
                    reminderFrequency: this.reminderFrequency
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