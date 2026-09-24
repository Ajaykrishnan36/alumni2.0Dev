import { LightningElement, wire } from 'lwc';
import getDonorImpact from '@salesforce/apex/KenFundraiseController.getDonorImpact';

const PLACEHOLDER = '—';
const INR_TIERS = [
    { value: 10000000, suffix: 'Cr' },
    { value: 100000, suffix: 'L' }
];
const GENERIC_TIERS = [
    { value: 1000000000, suffix: 'B' },
    { value: 1000000, suffix: 'M' },
    { value: 1000, suffix: 'K' }
];

export default class KenDonorImpact extends LightningElement {
    impact;
    hasLoaded = false;

    @wire(getDonorImpact)
    wiredImpact({ data, error }) {
        if (data) {
            this.impact = data;
            this.hasLoaded = true;
        } else if (error) {
            this.impact = undefined;
            this.hasLoaded = true;
        }
    }

    get stats() {
        return [
            {
                id: 'campaigns',
                number: this.formatCount('campaignCount'),
                label: 'Campaigns launched by alumni'
            },
            {
                id: 'goal',
                number: this.formatMoney('totalGoal'),
                label: 'Goal set across alumni campaigns'
            },
            {
                id: 'raised',
                number: this.formatMoney('totalRaised'),
                label: 'Contributed by alumni so far'
            },
            {
                id: 'completed',
                number: this.formatCount('completedCampaignCount'),
                label: 'Campaigns funded and completed'
            }
        ];
    }

    formatCount(key) {
        const value = this.readValue(key);
        if (value === null) {
            return PLACEHOLDER;
        }
        return this.groupDigits(value);
    }

    formatMoney(key) {
        const value = this.readValue(key);
        if (value === null) {
            return PLACEHOLDER;
        }
        const code = this.currencyCode;
        return `${this.currencySymbol(code)}${this.abbreviate(value, code)}`;
    }

    abbreviate(value, code) {
        const tiers = code === 'INR' ? INR_TIERS : GENERIC_TIERS;
        for (let i = 0; i < tiers.length; i++) {
            const tier = tiers[i];
            if (value < tier.value) {
                continue;
            }
            const units = value / tier.value;
            const digits = units >= 10 ? 0 : 1;
            const factor = Math.pow(10, digits);
            const truncated = Math.floor(units * factor) / factor;
            const text = truncated.toFixed(digits).replace(/\.0$/, '');
            const plus = Math.abs(truncated * tier.value - value) < 0.5 ? '' : '+';
            return `${text}${tier.suffix}${plus}`;
        }
        return this.groupDigits(value);
    }

    groupDigits(value) {
        try {
            return new Intl.NumberFormat(this.numberLocale).format(value);
        } catch (e) {
            return String(value);
        }
    }

    currencySymbol(code) {
        let symbol = null;
        try {
            const parts = new Intl.NumberFormat(this.numberLocale, {
                style: 'currency',
                currency: code,
                maximumFractionDigits: 0
            }).formatToParts(1);
            const match = parts.find((part) => part.type === 'currency');
            symbol = match ? match.value : null;
        } catch (e) {
            symbol = null;
        }
        return symbol || `${code} `;
    }

    get currencyCode() {
        return (this.impact && this.impact.currencyCode) || 'INR';
    }

    get numberLocale() {
        return this.currencyCode === 'INR' ? 'en-IN' : 'en-US';
    }

    readValue(key) {
        if (!this.hasLoaded || !this.impact) {
            return null;
        }
        const value = this.impact[key];
        return value === null || value === undefined ? null : Number(value);
    }
}