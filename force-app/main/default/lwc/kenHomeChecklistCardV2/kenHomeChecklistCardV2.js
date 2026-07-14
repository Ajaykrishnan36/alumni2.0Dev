import { LightningElement, api } from 'lwc';

export default class KenHomeChecklistCardV2 extends LightningElement {
    static renderMode = 'light';
    @api title = '';
    @api subtitle = '';
    @api rows = [];
    @api headSymbol = '✓';
    @api headTone = 'em';

    get headIconClass() {
        return `sect__head-ico sect__head-ico--${this.headTone}`;
    }

    handleAll() {
        this.dispatchEvent(new CustomEvent('viewall', { bubbles: true, composed: true }));
    }
    handleRow(event) {
        const key = event.currentTarget.dataset.key;
        this.dispatchEvent(new CustomEvent('rowaction', {
            detail: { key },
            bubbles: true,
            composed: true
        }));
    }
}