import { LightningElement, api } from 'lwc';

export default class KenGivingStartInitiativeV2 extends LightningElement {
    static renderMode = 'light';

    @api steps = [];
    @api initiatives = [];
    @api hasInitiatives = false;
    @api hasNoInitiatives = false;

    handleNew() {
        this.dispatchEvent(new CustomEvent('newinitiative'));
    }
}