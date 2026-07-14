import { LightningElement, api } from 'lwc';

export default class KenSettingsPersonalV2 extends LightningElement {
    static renderMode = 'light';
    @api prefs = {};

    handleField(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.dispatchEvent(new CustomEvent('fieldchange', {
            detail: { field, value },
            bubbles: true,
            composed: true
        }));
    }
    handleSave()   { this.dispatchEvent(new CustomEvent('save',   { bubbles: true, composed: true })); }
    handleCancel() { this.dispatchEvent(new CustomEvent('cancel', { bubbles: true, composed: true })); }
}