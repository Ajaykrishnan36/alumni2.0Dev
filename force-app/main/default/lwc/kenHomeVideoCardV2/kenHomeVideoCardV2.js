import { LightningElement, api } from 'lwc';

export default class KenHomeVideoCardV2 extends LightningElement {
    static renderMode = 'light';
    @api chipLabel = '';
    @api title = '';
    @api meta = '';

    handlePlay() {
        this.dispatchEvent(new CustomEvent('play', { bubbles: true, composed: true }));
    }
}