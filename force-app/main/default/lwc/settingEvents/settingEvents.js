import { LightningElement, track } from 'lwc';

export default class SettingEvents extends LightningElement {
    @track showDropdown = false;
    selectedReminders = [];

    get reminderText() {
        if (this.selectedReminders.length === 0) {
            return 'Select';
        }
        return `${this.selectedReminders.length} selected`;
    }

    toggleDropdown() {
        this.showDropdown = !this.showDropdown;
    }

    handleReminderSelect(event) {
        // Logic to track selected items if needed
        // For visual "Select" text update
        const val = event.target.dataset.value;
        if (event.target.checked) {
            this.selectedReminders.push(val);
        } else {
            this.selectedReminders = this.selectedReminders.filter(item => item !== val);
        }
        // Force reactivity if array push/filter doesn't trigger (standard LWC tracking limitation on deep objects/arrays sometimes, but length should trigger getter)
        // Re-assignment triggers track
        this.selectedReminders = [...this.selectedReminders];
    }
}