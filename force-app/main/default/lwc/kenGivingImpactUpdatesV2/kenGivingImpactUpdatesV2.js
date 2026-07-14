import { LightningElement, api } from 'lwc';

export default class KenGivingImpactUpdatesV2 extends LightningElement {
    static renderMode = 'light';

    @api updates = [];

    get hasUpdates() { return (this.updates || []).length > 0; }
    get hasNoUpdates() { return !this.hasUpdates; }
}