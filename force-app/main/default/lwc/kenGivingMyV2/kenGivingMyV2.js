import { LightningElement, api } from 'lwc';

export default class KenGivingMyV2 extends LightningElement {
    static renderMode = 'light';

    @api entries = [];
    @api totals = [];
    @api visibilityOptions = [];

    get hasEntries() { return (this.entries || []).length > 0; }
    get hasNoEntries() { return !this.hasEntries; }

    handleExplore() {
        this.dispatchEvent(new CustomEvent('explore'));
    }
}