import { LightningElement, api } from 'lwc';

export default class KenEventDateBlockV2 extends LightningElement {
    @api month = '';
    @api day = '';
    @api color = '#3061FF';

    get blockStyle() {
        return `background:${this.color}`;
    }
}