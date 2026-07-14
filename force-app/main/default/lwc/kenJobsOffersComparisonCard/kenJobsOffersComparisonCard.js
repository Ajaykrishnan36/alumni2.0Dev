import { LightningElement, api } from 'lwc';

export default class KenJobsOffersComparisonCard extends LightningElement {
    @api offer;

    get hasLogoUrl() {
        return Boolean(this.offer?.logoUrl);
    }

    formatInr(value) {
        const num = Number(value);
        if (!Number.isFinite(num)) return '—';
        return `₹ ${new Intl.NumberFormat('en-IN').format(num)}`;
    }

    get totalCtcFormatted() {
        return this.formatInr(this.offer?.totalCtc);
    }

    get fixedFormatted() {
        return this.formatInr(this.offer?.breakdown?.fixed);
    }

    get variableFormatted() {
        return this.formatInr(this.offer?.breakdown?.variable);
    }

    get bonusesFormatted() {
        return this.formatInr(this.offer?.breakdown?.bonuses);
    }
}