import { LightningElement, api, track } from 'lwc';
import submitContribution from '@salesforce/apex/KenGiftContributionController.submitContribution';

export default class KenGiftDonateWizardV2 extends LightningElement {
    @api campaignId;
    @api campaignName;

    _tiers = [];
    @api get tiers() { return this._tiers; }
    set tiers(v) {
        this._tiers = (v || []).map(t => ({ ...t, amountDisplay: this.money(t.amount) }));
        const def = this._tiers.find(t => t.isDefault);
        if (def && this.amount == null) { this.amount = Number(def.amount); this.selectedTierId = def.id; }
    }

    _funds = [];
    @api get funds() { return this._funds; }
    set funds(v) { this._funds = v || []; }

    @track step = 1;
    @track amount = null;
    @track selectedTierId = null;
    @track customAmount = '';
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track isAnonymous = false;
    @track comment = '';
    @track splitEnabled = false;
    @track allocations = [];
    @track cardName = '';
    @track cardNumber = '';
    @track cardExpiry = '';
    @track cardCvc = '';
    @track processing = false;
    @track errorMsg = '';
    @track done = false;

    // ----- step visibility -----
    get isStep1() { return this.step === 1 && !this.done; }
    get isStep2() { return this.step === 2 && !this.done; }
    get isStep3() { return this.step === 3 && !this.done; }
    get showFooter() { return !this.done && !this.processing; }

    get tierButtons() {
        return this._tiers.map(t => ({ ...t, cls: t.id === this.selectedTierId ? 'dw-tier dw-tier--on' : 'dw-tier' }));
    }
    get amountDisplay() { return this.money(this.amount); }
    get hasTiers() { return this._tiers.length > 0; }
    get hasFunds() { return this._funds.length > 0; }

    get allocationRows() {
        return this.allocations.map(a => ({
            key: a.key,
            amount: a.amount,
            funds: this._funds.map(f => ({
                id: f.id,
                name: f.department ? `${f.name} (${f.department})` : f.name,
                selected: f.id === a.fundId
            }))
        }));
    }

    money(n) {
        try {
            return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(Number(n) || 0);
        } catch (e) { return '₹' + (Number(n) || 0); }
    }

    // ----- step 1: amount -----
    handleTier(event) {
        const id = event.currentTarget.dataset.id;
        const t = this._tiers.find(x => x.id === id);
        if (t) { this.selectedTierId = id; this.amount = Number(t.amount); this.customAmount = ''; }
    }
    handleCustom(event) {
        this.customAmount = event.target.value;
        const n = Number(event.target.value);
        this.amount = (isFinite(n) && n > 0) ? n : null;
        this.selectedTierId = null;
    }

    // ----- step 2: details + optional split -----
    handleField(event) { this[event.target.dataset.field] = event.target.value; }
    handleAnon(event) { this.isAnonymous = event.target.checked; }
    handleSplitToggle(event) {
        this.splitEnabled = event.target.checked;
        if (this.splitEnabled && this.allocations.length === 0) this.addAllocation();
    }
    addAllocation() {
        this.allocations = [...this.allocations, { key: 'a' + Date.now() + Math.floor(Math.random() * 1000), fundId: '', amount: '' }];
    }
    handleAllocFund(event) {
        const k = event.currentTarget.dataset.key;
        const val = event.target.value;
        this.allocations = this.allocations.map(a => a.key === k ? { ...a, fundId: val } : a);
    }
    handleAllocAmount(event) {
        const k = event.currentTarget.dataset.key;
        const val = event.target.value;
        this.allocations = this.allocations.map(a => a.key === k ? { ...a, amount: val } : a);
    }
    handleAllocRemove(event) {
        const k = event.currentTarget.dataset.key;
        this.allocations = this.allocations.filter(a => a.key !== k);
    }

    // ----- step 3: card stub -----
    handleCard(event) { this[event.target.dataset.field] = event.target.value; }

    // ----- navigation -----
    handleNext() {
        this.errorMsg = '';
        if (this.step === 1) {
            if (!this.amount || this.amount <= 0) { this.errorMsg = 'Please choose or enter a donation amount.'; return; }
        }
        if (this.step === 2) {
            if (!this.lastName) { this.errorMsg = 'Please enter your last name.'; return; }
            if (!this.email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.email)) { this.errorMsg = 'Please enter a valid email address.'; return; }
            if (this.splitEnabled) {
                if (this.allocations.some(a => !a.fundId)) { this.errorMsg = 'Select a fund for each split line.'; return; }
                const sum = this.allocations.reduce((s, a) => s + (Number(a.amount) || 0), 0);
                if (Math.abs(sum - this.amount) > 0.001) {
                    this.errorMsg = `Fund splits (${this.money(sum)}) must total ${this.amountDisplay}.`; return;
                }
            }
        }
        if (this.step < 3) this.step += 1;
    }
    handleBack() { this.errorMsg = ''; if (this.step > 1) this.step -= 1; }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) { if (event.target.classList.contains('dw-overlay')) this.handleClose(); }
    stop(event) { event.stopPropagation(); }

    _requestId() {
        try { if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID(); } catch (e) { /* ignore */ }
        return 'req-' + Date.now() + '-' + Math.floor(Math.random() * 1e6);
    }

    // ----- submit: GATEWAY STUB then persist -----
    handleSubmit() {
        this.errorMsg = '';
        const digits = (this.cardNumber || '').replace(/\s/g, '');
        if (digits.length < 12) { this.errorMsg = 'Enter a (test) card number to simulate payment.'; return; }

        this.processing = true;
        const reqId = this._requestId();
        const last4 = digits.slice(-4);
        const allocations = this.splitEnabled
            ? this.allocations.filter(a => a.fundId && Number(a.amount) > 0).map(a => ({ fundId: a.fundId, amount: Number(a.amount) }))
            : [];

        const request = {
            campaignId: this.campaignId,
            donorFirstName: this.firstName,
            donorLastName: this.lastName,
            donorEmail: this.email,
            amount: Number(this.amount),
            isAnonymous: this.isAnonymous,
            frequency: 'One-time',
            source: 'Portal',
            comment: this.comment,
            requestId: reqId,
            allocations,
            // ===== GATEWAY SEAM =====
            // Real Stripe/Blackbaud tokenization + server-side capture goes here. For now we
            // simulate a captured charge so the materializer fires. Swap this block for the
            // provider's token/charge response (providerTxnId, status) when integrating.
            payment: {
                provider: 'Stripe',
                providerTxnId: 'sim_' + reqId,
                idempotencyKey: reqId + '_pay',
                status: 'Captured',
                amount: Number(this.amount),
                cardBrand: 'VISA',
                lastFour: last4
            }
        };

        // Simulate gateway latency, then persist via the Phase 3 edge-write controller.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            submitContribution({ req: request })
                .then(() => {
                    this.processing = false;
                    this.done = true;
                    this.dispatchEvent(new CustomEvent('success'));
                })
                .catch(err => {
                    this.processing = false;
                    // eslint-disable-next-line no-console
                    console.error('submitContribution error', err);
                    this.errorMsg = (err && err.body && err.body.message) || 'Payment could not be completed. Please try again.';
                });
        }, 1400);
    }

    handleDone() { this.dispatchEvent(new CustomEvent('close')); }
}