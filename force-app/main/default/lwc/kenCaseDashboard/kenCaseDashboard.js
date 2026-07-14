import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSummaryStats          from '@salesforce/apex/KenCaseDashboardController.getSummaryStats';
import getCasesByStatus           from '@salesforce/apex/KenCaseDashboardController.getCasesByStatus';
import getCasesByTargetAudience  from '@salesforce/apex/KenCaseDashboardController.getCasesByTargetAudience';
import getTopServices             from '@salesforce/apex/KenCaseDashboardController.getTopServices';
import getTopServiceOfferings   from '@salesforce/apex/KenCaseDashboardController.getTopServiceOfferings';
import getCaseTrend             from '@salesforce/apex/KenCaseDashboardController.getCaseTrend';
import getTopSubmitters         from '@salesforce/apex/KenCaseDashboardController.getTopSubmitters';
import getFilterOptions         from '@salesforce/apex/KenCaseDashboardController.getFilterOptions';
import getCaseList              from '@salesforce/apex/KenCaseDashboardController.getCaseList';

const DEFAULT_STATS = { total: 0, openCases: 0, closedCases: 0, cancelled: 0 };

function toChartData(rawList) {
    return (rawList || []).map(d => ({ label: d.label, value: d.value }));
}

export default class KenCaseDashboard extends NavigationMixin(LightningElement) {

    // ── Filters ───────────────────────────────────────────────────────────────
    @track filterYear   = 'All';
    @track filterStatus = 'All';

    // ── Refresh state ─────────────────────────────────────────────────────────
    @track isRefreshing = false;
    @track _refreshKey  = 0;

    // ── Modal ─────────────────────────────────────────────────────────────────
    @track modalOpen    = false;
    @track modalTitle   = '';
    @track modalCases   = [];
    @track modalLoading = false;

    // ── Filter options ────────────────────────────────────────────────────────
    @track yearOptions   = [];
    @track statusOptions = [];

    // ── Loading flags ─────────────────────────────────────────────────────────
    @track loadingStats                = true;
    @track loadingByStatus             = true;
    @track loadingByTargetAudience    = true;
    @track loadingTrend                = true;
    @track loadingTopServices          = true;
    @track loadingTopOfferings         = true;
    @track loadingTopSubmitters        = true;

    // ── Wire result stores ────────────────────────────────────────────────────
    _wStats;
    _wByStatus;
    _wByTargetAudience;
    _wTrend;
    _wTopServices;
    _wTopOfferings;
    _wTopSubmitters;
    _wFilterOptions;

    // ── Raw data from wires ───────────────────────────────────────────────────
    _rawStats                = null;
    _rawByStatus             = [];
    _rawByTargetAudience    = [];
    _rawTrend                = [];
    _rawTopServices          = [];
    _rawTopOfferings         = [];
    _rawTopSubmitters        = [];

    // ── Wire: filter options ──────────────────────────────────────────────────
    @wire(getFilterOptions)
    wFilterOptions(result) {
        this._wFilterOptions = result;
        if (result.data) {
            const d = result.data;
            this.statusOptions = (d.statuses || []).map(s => ({ label: s, value: s }));
            this.yearOptions   = (d.years    || []).map(y => ({ label: y, value: y }));
        }
    }

    // ── Wire: summary stats ───────────────────────────────────────────────────
    @wire(getSummaryStats, { year: '$filterYear', status: '$filterStatus' })
    wStats(result) {
        this._wStats = result;
        this.loadingStats = false;
        if (result.data) this._rawStats = result.data;
    }

    // ── Wire: cases by status ─────────────────────────────────────────────────
    @wire(getCasesByStatus, { year: '$filterYear' })
    wByStatus(result) {
        this._wByStatus = result;
        this.loadingByStatus = false;
        if (result.data) this._rawByStatus = result.data;
    }

    // ── Wire: cases by service category (Cases by Portal) ────────────────────
    @wire(getCasesByTargetAudience, { year: '$filterYear', status: '$filterStatus' })
    wByTargetAudience(result) {
        this._wByTargetAudience = result;
        this.loadingByTargetAudience = false;
        if (result.data) this._rawByTargetAudience = result.data;
    }

    // ── Wire: case trend ──────────────────────────────────────────────────────
    @wire(getCaseTrend, { year: '$filterYear', status: '$filterStatus' })
    wTrend(result) {
        this._wTrend = result;
        this.loadingTrend = false;
        if (result.data) this._rawTrend = result.data;
    }

    // ── Wire: top services ────────────────────────────────────────────────────
    @wire(getTopServices, { year: '$filterYear', status: '$filterStatus' })
    wTopServices(result) {
        this._wTopServices = result;
        this.loadingTopServices = false;
        if (result.data) this._rawTopServices = result.data;
    }

    // ── Wire: top service offerings ───────────────────────────────────────────
    @wire(getTopServiceOfferings, { year: '$filterYear', status: '$filterStatus' })
    wTopOfferings(result) {
        this._wTopOfferings = result;
        this.loadingTopOfferings = false;
        if (result.data) this._rawTopOfferings = result.data;
    }

    // ── Wire: top submitters ──────────────────────────────────────────────────
    @wire(getTopSubmitters, { year: '$filterYear', status: '$filterStatus' })
    wTopSubmitters(result) {
        this._wTopSubmitters = result;
        this.loadingTopSubmitters = false;
        if (result.data) this._rawTopSubmitters = result.data;
    }

    // ── Getters ───────────────────────────────────────────────────────────────
    get stats() {
        return this._rawStats || DEFAULT_STATS;
    }

    get casesByStatusData()           { return toChartData(this._rawByStatus); }
    get casesByTargetAudienceData()  { return toChartData(this._rawByTargetAudience); }
    get caseTrendData()               { return toChartData(this._rawTrend); }
    get topServicesData()            { return toChartData(this._rawTopServices); }
    get topOfferingsData()           { return toChartData(this._rawTopOfferings); }
    get topSubmittersData()          { return toChartData(this._rawTopSubmitters); }

    // ── Filter handlers ───────────────────────────────────────────────────────
    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        if (field === 'filterYear')   this.filterYear   = value;
        if (field === 'filterStatus') this.filterStatus = value;
    }

    clearFilters() {
        this.filterYear   = 'All';
        this.filterStatus = 'All';
        this.template.querySelectorAll('.filter-select').forEach(sel => { sel.value = 'All'; });
    }

    // ── Refresh ───────────────────────────────────────────────────────────────
    handleCreateCase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName: 'new'
            }
        });
    }

    handleRefresh() {
        if (this.isRefreshing) return;
        this.isRefreshing = true;
        const wires = [
            this._wFilterOptions,
            this._wStats,
            this._wByStatus,
            this._wByTargetAudience,
            this._wTrend,
            this._wTopServices,
            this._wTopOfferings,
            this._wTopSubmitters
        ].filter(Boolean);
        Promise.all(wires.map(r => refreshApex(r)))
            .then(() => {
                this.isRefreshing = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Refreshed',
                    message: 'Dashboard data updated successfully.',
                    variant: 'success'
                }));
            })
            .catch(() => { this.isRefreshing = false; });
    }

    // ── Stat card click ───────────────────────────────────────────────────────
    handleStatCardClick(event) {
        const type = event.currentTarget.dataset.type;
        const s = this.stats;
        let title, dimension;

        if (type === 'total') {
            title     = `All Cases (${s.total})`;
            dimension = 'all';
        } else if (type === 'open') {
            title     = `Open Cases (${s.openCases})`;
            dimension = 'open';
        } else if (type === 'closed') {
            title     = `Closed Cases (${s.closedCases})`;
            dimension = 'closed';
        } else if (type === 'cancelled') {
            title     = `Cancelled / Rejected (${s.cancelled})`;
            dimension = 'cancelled';
        } else {
            return;
        }

        this.openCaseModal(title, dimension, '');
    }

    // ── Drilldown ─────────────────────────────────────────────────────────────
    handleDrilldown(event) {
        const { dimension, value } = event.detail;
        if (!dimension || !value) return;

        const titleMap = {
            status:          `Cases — Status: ${value}`,
            targetAudience: `Cases — Audience: ${value}`,
            service:         `Cases — Service: ${value}`,
            offering:        `Cases — Offering: ${value}`,
            submitter:       `Cases — Submitter: ${value}`,
            trend:           `Cases — Month: ${value}`
        };
        const title = titleMap[dimension] || `Cases — ${value}`;

        if (dimension === 'trend') {
            // Trend drills into the full list filtered by current filters only
            this.openCaseModal(title, 'all', '');
            return;
        }

        this.openCaseModal(title, dimension, value);
    }

    openCaseModal(title, dimension, dimensionValue) {
        this.modalTitle   = title;
        this.modalCases   = [];
        this.modalLoading = true;
        this.modalOpen    = true;

        getCaseList({
            dimension:      dimension,
            dimensionValue: dimensionValue,
            year:           this.filterYear,
            status:         this.filterStatus
        })
        .then(result => {
            this.modalCases   = result || [];
            this.modalLoading = false;
        })
        .catch(() => { this.modalLoading = false; });
    }

    handleModalClose() {
        this.modalOpen    = false;
        this.modalCases   = [];
        this.modalLoading = false;
    }

    // ── CSV export (shared handler for all chart cards) ───────────────────────
    handleAllCasesExportCsv() {
        this.openCaseModal('All Cases — CSV Export', 'all', '');
    }

    handleStatusExportCsv() {
        this.openCaseModal('All Cases — CSV Export', 'all', '');
    }
}