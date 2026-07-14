import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMyApplications from '@salesforce/apex/KenJobDashboardController.getMyApplications';
import acceptOffer from '@salesforce/apex/KenJobDashboardController.acceptOffer';

export default class KenJobDashboardV2 extends LightningElement {
    @track active = [];
    @track closed = [];
    @track cycles = [];
    @track errorMsg = '';
    @track tab = 'active';
    @track cycle = 'all';
    loading = true;
    _wired;

    @wire(getMyApplications)
    wired(result) {
        this._wired = result;
        const { data, error } = result;
        if (data) {
            this.active = data.active || [];
            this.closed = data.closed || [];
            this.cycles = data.cycles || [];
            this.loading = false;
        } else if (error) {
            this.loading = false;
            this.errorMsg = (error && error.body && error.body.message) || 'Could not load applications.';
        }
    }

    // ---- tabs ----
    get isActiveTab() { return this.tab === 'active'; }
    get activeTabCls() { return this.tab === 'active' ? 'tab tab--on' : 'tab'; }
    get closedTabCls() { return this.tab === 'closed' ? 'tab tab--on' : 'tab'; }
    selectActive() { this.tab = 'active'; }
    selectClosed() { this.tab = 'closed'; }

    get activeCount() { return this.activeRows.length; }
    get closedCount() { return this.closedRows.length; }

    // ---- cycle filter ----
    get cycleOptions() {
        return [{ label: 'All cycles', value: 'all' },
            ...this.cycles.map(c => ({ label: c, value: c }))];
    }
    handleCycle(e) { this.cycle = e.detail.value; }

    _filter(rows) {
        if (this.cycle === 'all') return rows;
        return rows.filter(r => r.placementCycle === this.cycle);
    }
    get activeRows() { return this._filter(this.active); }
    get closedRows() { return this._filter(this.closed); }
    get rows() { return this.isActiveTab ? this.activeRows : this.closedRows; }
    get isEmpty() { return !this.loading && this.rows.length === 0; }

    // ---- row actions ----
    handleAccept(e) {
        const id = e.currentTarget.dataset.id;
        this.errorMsg = '';
        acceptOffer({ applicationId: id })
            .then(() => refreshApex(this._wired))
            .catch(err => {
                this.errorMsg = (err && err.body && err.body.message) || 'Could not accept the offer.';
            });
    }
    handleReview(e) {
        const id = e.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('reviewoffer', { detail: { applicationId: id } }));
    }
}