import { LightningElement, api } from 'lwc';

export default class KenHomeQuickActionsV2 extends LightningElement {
    static renderMode = 'light';
    @api title = '';
    @api subtitle = '';
    @api actions = [];

    handleAction(event) {
        const key = event.currentTarget.dataset.key;
        const label = event.currentTarget.dataset.label;
        this.dispatchEvent(new CustomEvent('action', {
            detail: { key, label },
            bubbles: true,
            composed: true
        }));
    }
}