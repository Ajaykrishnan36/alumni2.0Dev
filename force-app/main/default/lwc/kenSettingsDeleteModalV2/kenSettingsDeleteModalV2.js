import { LightningElement } from 'lwc';

export default class KenSettingsDeleteModalV2 extends LightningElement {
    static renderMode = 'light';

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }
    handleConfirm() {
        this.dispatchEvent(new CustomEvent('confirm', { bubbles: true, composed: true }));
    }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
        }
    }
    handleStop(event) { event.stopPropagation(); }
}