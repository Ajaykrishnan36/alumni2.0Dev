import { LightningElement, api } from 'lwc';

export default class KenHomeForYouBarV2 extends LightningElement {
    static renderMode = 'light';
    @api subtitle = '';
    @api ctaLabel = '';
    @api chips = [];

    handleCta() {
        this.dispatchEvent(new CustomEvent('cta', { bubbles: true, composed: true }));
    }
}