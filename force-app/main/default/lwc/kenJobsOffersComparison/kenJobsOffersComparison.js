import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

const SAMPLE_OFFERS = [
    {
        id: 'paypal-dev',
        role: 'Developer',
        company: 'Paypal',
        logoText: 'P',
        totalCtc: 800000,
        breakdown: {
            fixed: 400000,
            variable: 100000,
            bonuses: 300000
        },
        attributes: [
            { icon: 'utility:checkin', text: 'Remote' },
            { icon: 'utility:company', text: 'Startup' },
            { icon: 'utility:trending', text: 'High growth potential with clear promotion path' },
            { icon: 'utility:people', text: '15 alumni work here' }
        ],
        perks: ['Health insurance for family', 'Stock options (ESOPs)', 'Flexible working hours'],
        joining: 'Jan 01, 2026',
        bond: '2 years',
        acceptBy: 'Nov 15, 2025',
        questionLabel: 'Your question(s)',
        question: 'Which company is better for work-life balance?'
    },
    {
        id: 'hindustan-se',
        role: 'Software Engineer',
        company: 'Hindustan Unilever',
        logoText: 'H',
        totalCtc: 620000,
        breakdown: {
            fixed: 420000,
            variable: 150000,
            bonuses: 50000
        },
        attributes: [
            { icon: 'utility:checkin', text: 'Remote' },
            { icon: 'utility:company', text: 'Corporate' },
            { icon: 'utility:trending', text: 'Rapid growth with equity upside potential' },
            { icon: 'utility:people', text: '8 alumni work here' }
        ],
        perks: ['Premium health insurance', 'Significant equity package', 'Unlimited PTO'],
        joining: 'Dec 03, 2025',
        bond: 'No bond',
        acceptBy: 'Nov 11, 2025',
        questionLabel: 'Your question(s)',
        question: 'Which offer is best for long-term growth?'
    },
    {
        id: 'reliance-ds',
        role: 'Data Scientist',
        company: 'Reliance Industries',
        logoText: 'R',
        totalCtc: 1000000,
        breakdown: {
            fixed: 600000,
            variable: 200000,
            bonuses: 200000
        },
        attributes: [
            { icon: 'utility:checkin', text: 'Remote' },
            { icon: 'utility:company', text: 'Corporate' },
            { icon: 'utility:trending', text: 'Steady growth with structured career progression' },
            { icon: 'utility:people', text: '22 alumni work here' }
        ],
        perks: ['Comprehensive health coverage', 'Provident Fund', 'Annual performance bonus'],
        joining: 'Jan 03, 2026',
        bond: '3 years',
        acceptBy: 'Nov 02, 2025',
        questionLabel: 'Your question(s)',
        question: 'Which offer has the best overall value?'
    }
];

export default class KenJobsOffersComparison extends LightningElement {
    @api offers = SAMPLE_OFFERS;

    selectedOfferId = SAMPLE_OFFERS[0]?.id;
    isMobile = false;

    _mql;
    _mqlListener;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        const state = pageRef?.state;
        if (!state) {
            return;
        }

        const selectedOffers = this.parseStateJson(state.selectedOffers);
        if (Array.isArray(selectedOffers) && selectedOffers.length > 0) {
            this.offers = selectedOffers;
            if (!selectedOffers.some((offer) => offer.id === this.selectedOfferId)) {
                this.selectedOfferId = selectedOffers[0].id;
            }
        }
    }

    connectedCallback() {
        this._mql = window.matchMedia('(max-width: 767px)');
        this._mqlListener = (e) => {
            this.isMobile = e.matches;
        };

        this.isMobile = this._mql.matches;
        this._mql.addEventListener('change', this._mqlListener);
    }

    disconnectedCallback() {
        if (this._mql && this._mqlListener) {
            this._mql.removeEventListener('change', this._mqlListener);
        }
    }

    get offerOptions() {
        return (this.offers || []).map((o) => ({
            label: `${o.role} · ${o.company}`,
            value: o.id
        }));
    }

    get selectedOffer() {
        return (this.offers || []).find((o) => o.id === this.selectedOfferId) || this.offers?.[0];
    }

    handleOfferChange(event) {
        this.selectedOfferId = event.detail.value;
    }

    parseStateJson(value) {
        if (!value) {
            return null;
        }

        try {
            return JSON.parse(value);
        } catch (error) {
            return null;
        }
    }
}