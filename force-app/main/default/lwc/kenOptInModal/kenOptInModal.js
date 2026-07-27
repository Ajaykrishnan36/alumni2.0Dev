import { LightningElement, track } from 'lwc';

export default class KenOptInModal extends LightningElement {
    @track universityUpdates = true;

    handleCheckboxChange(event) {
        this.universityUpdates = event.target.checked;
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }

    handleFinish() {
        this.dispatchEvent(new CustomEvent('finish', {
            detail: { universityUpdates: this.universityUpdates },
            bubbles: true,
            composed: true
        }));
    }
}