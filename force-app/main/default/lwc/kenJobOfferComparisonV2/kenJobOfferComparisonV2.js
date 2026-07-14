import { LightningElement, api, track } from 'lwc';
import getOffersForComparison from '@salesforce/apex/KenJobOfferController.getOffersForComparison';
import submitOfferInquiry from '@salesforce/apex/KenJobOfferController.submitOfferInquiry';

export default class KenJobOfferComparisonV2 extends LightningElement {
    @track offers = [];
    @track errorMsg = '';
    @track question = '';
    @track submitting = false;
    @track inquirySent = false;
    loading = true;

    _idsRaw;
    _ids = [];

    // Accepts a comma-separated string (Experience Builder) or an array (programmatic).
    @api
    get offerIds() { return this._idsRaw; }
    set offerIds(v) {
        this._idsRaw = v;
        if (Array.isArray(v)) {
            this._ids = v.filter(Boolean);
        } else if (typeof v === 'string') {
            this._ids = v.split(',').map(s => s.trim()).filter(Boolean);
        } else {
            this._ids = [];
        }
        this.load();
    }

    load() {
        if (!this._ids || !this._ids.length) { this.loading = false; this.offers = []; return; }
        this.loading = true;
        getOffersForComparison({ offerIds: this._ids })
            .then(data => {
                this.offers = (data || []).map(o => this._decorate(o));
                this.loading = false;
            })
            .catch(e => {
                this.loading = false;
                this.errorMsg = (e && e.body && e.body.message) || 'Could not load offers.';
            });
    }

    _decorate(o) {
        const perks = o.perks || [];
        const company = o.company || o.role || 'Offer';
        const initial = (o.logoInitial && o.logoInitial.trim())
            ? o.logoInitial.trim().charAt(0).toUpperCase()
            : company.charAt(0).toUpperCase();
        const color = (o.logoColor && o.logoColor.trim()) ? o.logoColor.trim() : '#4f46e5';
        return {
            ...o,
            companyFmt: company,
            logoLetter: initial,
            logoStyle: 'background:' + color + ';',
            roleFmt: o.role || 'Offer',
            locationFmt: o.location || '—',
            totalCtcFmt: this._money(o.totalCtc),
            fixedFmt: this._money(o.fixedComp),
            variableFmt: this._money(o.variableComp),
            bonusFmt: this._money(o.joiningBonus),
            workTypeFmt: o.workType || '—',
            bondFmt: this._bond(o),
            perkItems: perks.map((p, i) => ({ key: o.id + '_p' + i, label: p })),
            hasPerks: perks.length > 0
        };
    }

    _money(v) {
        if (v === null || v === undefined) return '—';
        try {
            return new Intl.NumberFormat(undefined, {
                style: 'currency', currency: 'USD', maximumFractionDigits: 0
            }).format(v);
        } catch (e) {
            return '' + v;
        }
    }

    _bond(o) {
        if (o.bondMonths !== null && o.bondMonths !== undefined && o.bondMonths !== 0) {
            return o.bondMonths + (o.bondMonths === 1 ? ' month' : ' months');
        }
        return o.bond || 'None';
    }

    get hasOffers() { return this.offers && this.offers.length > 0; }
    get gridStyle() {
        const cols = this.offers.length || 1;
        return 'grid-template-columns: repeat(' + cols + ', minmax(220px, 1fr));';
    }

    handleQuestion(e) { this.question = e.target.value; }
    get submitDisabled() { return this.submitting || !(this.question && this.question.trim()); }

    handleSubmitInquiry() {
        const q = (this.question || '').trim();
        if (!q) return;
        this.submitting = true;
        this.errorMsg = '';
        const a = this.offers[0] ? this.offers[0].id : null;
        const b = this.offers[1] ? this.offers[1].id : null;
        submitOfferInquiry({ offerIdA: a, offerIdB: b, questionText: q })
            .then(() => {
                this.submitting = false;
                this.inquirySent = true;
                this.question = '';
            })
            .catch(e => {
                this.submitting = false;
                this.errorMsg = (e && e.body && e.body.message) || 'Could not submit your question.';
            });
    }
}