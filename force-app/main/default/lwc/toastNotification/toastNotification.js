import { LightningElement, api } from 'lwc';

export default class ToastNotification extends LightningElement {
    @api isVisible = false;
    @api toastTitle = '';
    @api toastMessage = '';
    @api toastVariant = 'success'; // success, error, warning, info

    get toastClasses() {
        return `toast toast-${this.toastVariant}`;
    }

    get isSuccess() {
        return this.toastVariant === 'success';
    }

    get isError() {
        return this.toastVariant === 'error';
    }

    get isWarning() {
        return this.toastVariant === 'warning';
    }

    get isInfo() {
        return this.toastVariant === 'info';
    }

    get hasMessage() {
        return this.toastMessage && this.toastMessage.trim().length > 0;
    }
}