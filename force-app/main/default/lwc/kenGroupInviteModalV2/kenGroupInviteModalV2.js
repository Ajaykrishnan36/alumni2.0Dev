import { LightningElement, api, track } from 'lwc';

export default class KenGroupInviteModalV2 extends LightningElement {
    @api groupName;

    @track raw = '';

    handleInput(event) {
        this.raw = event.target.value;
    }
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
    handleSend() {
        const tokens = (this.raw || '')
            .split(/[\s,;\n]+/)
            .map(t => t.trim())
            .filter(Boolean);
        if (!tokens.length) {
            this.dispatchEvent(new CustomEvent('validationerror', { detail: { message: 'Please enter at least one alumni Id or email.' } }));
            return;
        }
        // Pass tokens up; parent will split into Salesforce-Id tokens vs anything else.
        this.dispatchEvent(new CustomEvent('invite', { detail: { tokens } }));
    }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('overlay')) {
            this.handleClose();
        }
    }
    stopProp(event) { event.stopPropagation(); }
}