import { LightningElement, api, track } from 'lwc';

const GIVE_TYPES = [
    { key: 'donation', label: 'One-time donation', desc: 'A direct, tax-receipt eligible contribution', recommended: true, icon: 'D' },
    { key: 'pledge', label: 'Pledge', desc: 'Commit now, complete payment when ready', recommended: false, icon: 'P' },
    { key: 'in-kind', label: 'In-kind contribution', desc: 'Donate equipment, services, or resources', recommended: false, icon: 'K' },
    { key: 'csr', label: 'Company or CSR introduction', desc: 'Connect us with your CSR program', recommended: false, icon: 'C' }
];

function formatINR(n) {
    if (n == null) return '';
    if (n >= 10000000) return `Rs ${(n / 10000000).toFixed(n % 10000000 === 0 ? 0 : 2)} Cr`;
    if (n >= 100000) return `Rs ${(n / 100000).toFixed(n % 100000 === 0 ? 0 : 2)} L`;
    if (n >= 1000) return `Rs ${(n / 1000).toFixed(n % 1000 === 0 ? 0 : 1)}K`;
    return `Rs ${n}`;
}

export default class KenGiveNowWizardV2 extends LightningElement {
    @api opp;
    @api userFirstName = '';

    @track step = 1;
    @track giveType = 'donation';
    @track giveAmount = 10000;
    @track giveCustom = '';
    @track giveVisibility = 'name-batch';
    @track giveNotes = '';

    connectedCallback() {
        if (this.opp && this.opp.suggestedAmounts && this.opp.suggestedAmounts[1]) {
            this.giveAmount = this.opp.suggestedAmounts[1];
        }
    }

    get title() { return this.opp ? this.opp.title : ''; }
    get progressStyle() { return `--prog:${this.step * 25}%`; }
    get stepLabel() { return `STEP ${this.step} OF 4 - Give now`; }
    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }
    get isStep4() { return this.step === 4; }

    get giveTypeCards() {
        return GIVE_TYPES.map(t => ({ ...t, cssClass: t.key === this.giveType ? 'give-type give-type--active' : 'give-type' }));
    }
    get giveAmountPills() {
        const amounts = (this.opp && this.opp.suggestedAmounts) || [5000, 10000, 25000, 50000];
        return amounts.map(a => ({
            value: a,
            label: formatINR(a),
            cssClass: a === this.giveAmount ? 'amount-pill amount-pill--active' : 'amount-pill'
        }));
    }
    get visPublicClass() { return this.giveVisibility === 'public' ? 'vis-row vis-row--active' : 'vis-row'; }
    get visBatchClass() { return this.giveVisibility === 'name-batch' ? 'vis-row vis-row--active' : 'vis-row'; }
    get visAnonClass() { return this.giveVisibility === 'anonymous' ? 'vis-row vis-row--active' : 'vis-row'; }
    get effectiveAmount() {
        const c = Number(this.giveCustom);
        return (c && c > 0) ? c : this.giveAmount;
    }
    get effectiveAmountLabel() { return formatINR(this.effectiveAmount); }
    get giveTypeLabel() {
        const t = GIVE_TYPES.find(x => x.key === this.giveType);
        return t ? t.label : '';
    }
    get visibilityLabel() {
        if (this.giveVisibility === 'public') return 'Public name';
        if (this.giveVisibility === 'name-batch') return 'Name + batch';
        return 'Anonymous';
    }

    handleSelectType(event) { this.giveType = event.currentTarget.dataset.key; }
    handleSelectAmount(event) {
        this.giveAmount = Number(event.currentTarget.dataset.value);
        this.giveCustom = '';
    }
    handleCustomAmount(event) { this.giveCustom = event.target.value; }
    handleSelectVisibility(event) { this.giveVisibility = event.currentTarget.dataset.value; }
    handleNotes(event) { this.giveNotes = event.target.value; }
    handleNext() { if (this.step < 4) this.step += 1; }
    handlePrev() { if (this.step > 1) this.step -= 1; }
    handleConfirm() {
        this.step = 4;
        this.dispatchEvent(new CustomEvent('submit', {
            detail: {
                type: this.giveType,
                amount: this.effectiveAmount,
                visibility: this.giveVisibility,
                notes: this.giveNotes
            }
        }));
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
}