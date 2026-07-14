import { LightningElement, api } from 'lwc';

const CAT_KEY = {
    'Scholarships': 'scholarships',
    'Infrastructure': 'infrastructure',
    'Campus Development': 'campus',
    'Batch Fund': 'batch',
    'Student Support': 'support'
};

function formatINR(n) {
    if (n == null || n === '') return '';
    const num = Number(n);
    if (isNaN(num)) return String(n);
    return '₹' + num.toLocaleString('en-IN');
}

export default class KenOpportunityCardV2 extends LightningElement {
    @api recordId;
    @api title;
    @api category;
    @api shortDesc;
    @api raised = 0;
    @api target;
    @api contributors = 0;
    @api daysLeft;
    @api image;
    @api isOngoing = false;
    @api approved = false;

    get desc() { return this.shortDesc; }
    get raisedText() { return formatINR(this.raised); }
    get targetText() { return this.target ? `of ${formatINR(this.target)} goal` : 'Ongoing fund'; }
    get pctValue() {
        const r = Number(this.raised) || 0;
        const t = Number(this.target) || 0;
        if (!t) return 0;
        return Math.min(100, Math.round((r / t) * 100));
    }
    get hasProgress() { return this.pctValue > 0; }
    get progressStyle() { return `width:${this.pctValue}%`; }
    get pctText() { return `${this.pctValue}%`; }
    get imgStyle() { return this.image ? `background-image:url('${this.image}')` : ''; }
    get useGradient() { return !this.image; }
    get coverClass() {
        return this.useGradient ? 'opp-card__cover opp-card__cover--gradient' : 'opp-card__cover';
    }
    get catKey() { return CAT_KEY[this.category] || ''; }
    get catClass() { return `opp-card__cat ${this.catKey}`; }
    get ctx() {
        if (this.isOngoing) return 'Ongoing fund';
        if (this.daysLeft != null && this.daysLeft !== '') return `${this.daysLeft} days left`;
        return '';
    }

    handleDetails(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('details', { detail: { id: this.recordId } }));
    }
    handleGive(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('give', { detail: { id: this.recordId } }));
    }
}