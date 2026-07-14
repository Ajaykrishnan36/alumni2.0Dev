import { LightningElement } from 'lwc';

export default class KenSettingsAccountV2 extends LightningElement {
    static renderMode = 'light';

    handleChangePass() {
        this.dispatchEvent(new CustomEvent('changepass', { bubbles: true, composed: true }));
    }
    handleToggle2FA() {
        this.dispatchEvent(new CustomEvent('toggle2fa', { bubbles: true, composed: true }));
    }
    handleDelete() {
        this.dispatchEvent(new CustomEvent('deleteaccount', { bubbles: true, composed: true }));
    }
}