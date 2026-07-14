import { LightningElement, api } from 'lwc';

export default class KenOpportunityFeaturedV2 extends LightningElement {
    @api opp = {};

    get imgStyle() { return this.opp.imgStyle; }
    get catClass() { return `opp-feat__chip opp-feat__chip--cat ${this.opp.catKey || ''}`; }
    get category() { return this.opp.category; }
    get title() { return this.opp.title; }
    get desc() { return this.opp.shortDesc; }
    get raised() { return this.opp.raisedFormatted; }
    get target() { return this.opp.targetText; }
    get contributors() { return this.opp.contributors; }
    get daysText() { return this.opp.daysText; }
    get pctText() { return `${this.opp.pctValue || 0}%`; }
    get hasProgress() { return !!this.opp.hasProgress; }
    get progressStyle() { return `width:${this.opp.pctValue || 0}%`; }

    handleDetails() { this.dispatchEvent(new CustomEvent('details', { detail: { id: this.opp.id } })); }
    handleGive() { this.dispatchEvent(new CustomEvent('give', { detail: { id: this.opp.id } })); }
}