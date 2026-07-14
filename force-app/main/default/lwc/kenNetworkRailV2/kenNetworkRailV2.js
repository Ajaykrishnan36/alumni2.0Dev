import { LightningElement, api } from 'lwc';

export default class KenNetworkRailV2 extends LightningElement {
    @api spotlight;
    @api businesses = [];
    @api inviteUrl = '';

    handleSpotlight() { this.dispatchEvent(new CustomEvent('spotlightclick')); }
    handleCopy(event) { this.dispatchEvent(new CustomEvent('copyinvite', { detail: event.detail })); }
}