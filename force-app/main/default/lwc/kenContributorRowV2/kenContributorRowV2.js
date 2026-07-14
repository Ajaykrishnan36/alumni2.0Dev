import { LightningElement, api } from 'lwc';

export default class KenContributorRowV2 extends LightningElement {
    @api contributor = {};

    get initial() { return (this.contributor.name && this.contributor.name.charAt(0)) || 'A'; }
    get name() { return this.contributor.name; }
    get batch() { return this.contributor.batch; }
    get campaign() { return this.contributor.campaign; }
    get amount() { return this.contributor.amount; }
    get hasAmount() { return !!this.contributor.amount; }
}