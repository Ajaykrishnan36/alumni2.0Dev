import { LightningElement, api } from 'lwc';

export default class KenJobOfferComparisonPageV2 extends LightningElement {
    @api jobs = [];

    get hasJobs() { return Array.isArray(this.jobs) && this.jobs.length > 0; }
    get jobCount() { return Array.isArray(this.jobs) ? this.jobs.length : 0; }
    get countNote() {
        const n = this.jobCount;
        return `Comparing ${n} of 3 offers · Open more offers from your tracker to expand the comparison.`;
    }
    get decoratedJobs() {
        return (this.jobs || []).map((j, idx) => {
            const offer = j.offer || {};
            return {
                key: j.id || `j-${idx}`,
                id: j.id,
                logoStyle: `background:${j.col || '#3061FF'};color:#fff;`,
                logoInitial: j.l || (j.company ? j.company.charAt(0) : '?'),
                company: j.company || '',
                title: j.title || '',
                totalCTC: offer.totalCTC || '—',
                fixed: offer.fixed || '—',
                variable: offer.variable || '—',
                bonus: offer.bonus || '—',
                joiningDate: offer.joiningDate || '—',
                bond: offer.bond || '—',
                perks: (offer.perks || []).map((p, i) => ({ key: `${j.id}-perk-${i}`, label: p }))
            };
        });
    }

    handleBack()    { this.dispatchEvent(new CustomEvent('back')); }
    handleAccept(e) {
        const id = e.currentTarget && e.currentTarget.dataset ? Number(e.currentTarget.dataset.id) : null;
        this.dispatchEvent(new CustomEvent('accept', { detail: { id } }));
    }
    handleDecline(e) {
        const id = e.currentTarget && e.currentTarget.dataset ? Number(e.currentTarget.dataset.id) : null;
        this.dispatchEvent(new CustomEvent('decline', { detail: { id } }));
    }
}