import { LightningElement, api } from 'lwc';

export default class KenStatusPopupV2 extends LightningElement {
    @api header = 'Password Updated!';
    @api content = '';
    @api showContent = false;
    @api autoDismissMs = 0;
    @api dismissible = false;

    _dismissTimer = null;

    connectedCallback() {
        if (this.autoDismissMs && this.autoDismissMs > 0) {
            this._dismissTimer = setTimeout(() => this._fireDismiss(), this.autoDismissMs);
        }
    }

    disconnectedCallback() {
        if (this._dismissTimer) clearTimeout(this._dismissTimer);
    }

    handleClose() {
        this._fireDismiss();
    }

    handleOverlayClick(event) {
        if (event.target === event.currentTarget && this.dismissible) {
            this._fireDismiss();
        }
    }

    _fireDismiss() {
        if (this._dismissTimer) {
            clearTimeout(this._dismissTimer);
            this._dismissTimer = null;
        }
        this.dispatchEvent(new CustomEvent('dismiss'));
    }
}