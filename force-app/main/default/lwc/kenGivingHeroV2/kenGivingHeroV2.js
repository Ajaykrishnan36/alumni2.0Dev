import { LightningElement } from 'lwc';

export default class KenGivingHeroV2 extends LightningElement {
    handleExplore() { this.dispatchEvent(new CustomEvent('explore')); }
    handleStartInitiative() { this.dispatchEvent(new CustomEvent('startinitiative')); }
    handleCsrConnect() { this.dispatchEvent(new CustomEvent('csrconnect')); }
}