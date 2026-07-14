import { LightningElement, track } from 'lwc';

export default class SettingPreferences extends LightningElement {
    @track isPrivateAccount = false;
    @track showModal = false;

    handlePrivateAccountChange(event) {
        // Prevent immediate change, show modal first if turning ON
        // Actually, usually toggle changes visual state immediately. 
        // If we want to confirm "making account private", assuming it's currently public (false).
        // If it's already private (true) and we turn it off, maybe no confirmation needed?
        // Let's assume confirmation is for turning it ON based on the text "make your account private".
        
        const isChecked = event.target.checked;
        if (isChecked) {
            // Revert visual change until confirmed? Or let it slide and revert if cancelled?
            // Reverting via event.target.checked = !isChecked might be tricky in LWC without querySelector.
            // Let's just update internal state and fix it if cancelled.
            this.isPrivateAccount = isChecked;
            this.showModal = true;
        } else {
            this.isPrivateAccount = isChecked;
        }
    }

    closeModal() {
        this.showModal = false;
        this.isPrivateAccount = false; // Revert
        //Need to force update the UI component if it doesn't react automatically to the tracked property change after user interaction
        // In LWC, input checked state might detach from tracked variable after user interaction.
        // We might need to manually reset the input.
        this.resetToggle();
    }

    confirmPrivate() {
        this.showModal = false;
        // Logic to save setting would go here
    }

    resetToggle() {
        const toggle = this.template.querySelector('lightning-input[type="toggle"]');
        if (toggle) {
            toggle.checked = this.isPrivateAccount;
        }
    }
}