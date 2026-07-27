import { LightningElement, api } from 'lwc';

export default class StatusPopup extends LightningElement {
    @api visible = false;
    @api message = '';
    @api variant = 'success';

    get iconName() {
        if (this.variant === 'error') {
            return 'utility:error';
        }
        if (this.variant === 'warning') {
            return 'utility:warning';
        }
        return 'utility:success';
    }

    get iconWrapClass() {
        return this.variant === 'error' ? 'iconWrap error' : 'iconWrap success';
    }
}