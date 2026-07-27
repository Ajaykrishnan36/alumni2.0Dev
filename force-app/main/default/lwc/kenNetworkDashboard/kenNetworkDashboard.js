import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSummaryStats      from '@salesforce/apex/KenNetworkDashboardController.getSummaryStats';
import getConnectionsByStatus from '@salesforce/apex/KenNetworkDashboardController.getConnectionsByStatus';
import getMonthlyTrend       from '@salesforce/apex/KenNetworkDashboardController.getMonthlyTrend';
import getAvgTatByMonth      from '@salesforce/apex/KenNetworkDashboardController.getAvgTatByMonth';
import getTopConnectors      from '@salesforce/apex/KenNetworkDashboardController.getTopConnectors';
import getTopSenders         from '@salesforce/apex/KenNetworkDashboardController.getTopSenders';
import getTopReceivers       from '@salesforce/apex/KenNetworkDashboardController.getTopReceivers';
import getYearlyGrowth       from '@salesforce/apex/KenNetworkDashboardController.getYearlyGrowth';
import getFilterOptions      from '@salesforce/apex/KenNetworkDashboardController.getFilterOptions';
import getConnectionList     from '@salesforce/apex/KenNetworkDashboardController.getConnectionList';

export default class KenNetworkDashboard extends LightningElement {

    @track statusFilter = '';
    @track yearFilter   = '';
    @track isRefreshing = false;

    // Modal state
    @track modalOpen        = false;
    @track modalTitle       = '';
    @track modalConnections = [];
    @track modalLoading     = false;

    // Loading flags
    @track loadingStatus        = true;
    @track loadingMonthlyTrend  = true;
    @track loadingAvgTat        = true;
    @track loadingTopConnectors = true;
    @track loadingTopSenders    = true;
    @track loadingTopReceivers  = true;
    @track loadingNegative      = true;
    @track loadingYearlyGrowth  = true;

    // Wire results
    _wiredSummary;
    _wiredStatus;
    _wiredMonthlyTrend;
    _wiredAvgTat;
    _wiredTopConnectors;
    _wiredTopSenders;
    _wiredTopReceivers;
    _wiredYearlyGrowth;
    _wiredFilterOptions;

    // Data
    @track summaryStats       = { total: 0, accepted: 0, pending: 0, avgTatDays: 0 };
    @track statusData         = [];
    @track monthlyTrendData   = [];
    @track avgTatData         = [];
    @track topConnectorsData  = [];
    @track topSendersData     = [];
    @track topReceiversData   = [];
    @track negativeData       = [];
    @track yearlyGrowthData   = [];
    @track filterOptions      = { statuses: [], years: [] };

    get totalConnections() { return this.summaryStats.total || 0; }
    get filter() { return { statusFilter: this.statusFilter, yearFilter: this.yearFilter }; }

    // ── Wire adapters ──────────────────────────────────────────────────────────

    @wire(getSummaryStats, { statusFilter: '$statusFilter', yearFilter: '$yearFilter' })
    wiredSummary(result) {
        this._wiredSummary = result;
        if (result.data) this.summaryStats = result.data;
    }

    @wire(getConnectionsByStatus, { yearFilter: '$yearFilter' })
    wiredStatus(result) {
        this._wiredStatus = result;
        this.loadingStatus = false;
        if (result.data) this.statusData = result.data;
    }

    @wire(getMonthlyTrend, { statusFilter: '$statusFilter', yearFilter: '$yearFilter' })
    wiredMonthlyTrend(result) {
        this._wiredMonthlyTrend = result;
        this.loadingMonthlyTrend = false;
        if (result.data) this.monthlyTrendData = result.data;
    }

    @wire(getAvgTatByMonth, { yearFilter: '$yearFilter' })
    wiredAvgTat(result) {
        this._wiredAvgTat = result;
        this.loadingAvgTat = false;
        if (result.data) this.avgTatData = result.data;
    }

    @wire(getTopConnectors, { statusFilter: '$statusFilter', yearFilter: '$yearFilter' })
    wiredTopConnectors(result) {
        this._wiredTopConnectors = result;
        this.loadingTopConnectors = false;
        if (result.data) this.topConnectorsData = result.data;
    }

    @wire(getTopSenders, { statusFilter: '$statusFilter', yearFilter: '$yearFilter' })
    wiredTopSenders(result) {
        this._wiredTopSenders = result;
        this.loadingTopSenders = false;
        if (result.data) this.topSendersData = result.data;
    }

    @wire(getTopReceivers, { statusFilter: '$statusFilter', yearFilter: '$yearFilter' })
    wiredTopReceivers(result) {
        this._wiredTopReceivers = result;
        this.loadingTopReceivers = false;
        if (result.data) this.topReceiversData = result.data;
    }

    @wire(getYearlyGrowth, { statusFilter: '$statusFilter' })
    wiredYearlyGrowth(result) {
        this._wiredYearlyGrowth = result;
        this.loadingYearlyGrowth = false;
        if (result.data) {
            this.yearlyGrowthData = result.data;
        }
    }

    @wire(getFilterOptions)
    wiredFilterOptions(result) {
        this._wiredFilterOptions = result;
        if (result.data) this.filterOptions = result.data;
    }

    // Separate wire for negative signals (Rejected + Cancelled + Blocked)
    @wire(getConnectionsByStatus, { yearFilter: '$yearFilter' })
    wiredNegative(result) {
        this.loadingNegative = false;
        if (result.data) {
            this.negativeData = result.data.filter(p =>
                ['Rejected', 'Cancelled', 'Blocked'].includes(p.label)
            );
        }
    }

    // ── Filter handlers ────────────────────────────────────────────────────────

    handleStatusChange(event) { this.statusFilter = event.target.value; }
    handleYearChange(event)   { this.yearFilter   = event.target.value; }

    clearFilters() {
        this.statusFilter = '';
        this.yearFilter   = '';
        this.template.querySelectorAll('.filter-select').forEach(s => { s.value = ''; });
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await Promise.all([
                refreshApex(this._wiredSummary),
                refreshApex(this._wiredStatus),
                refreshApex(this._wiredMonthlyTrend),
                refreshApex(this._wiredAvgTat),
                refreshApex(this._wiredTopConnectors),
                refreshApex(this._wiredTopSenders),
                refreshApex(this._wiredTopReceivers),
                refreshApex(this._wiredYearlyGrowth),
                refreshApex(this._wiredFilterOptions)
            ]);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Refreshed',
                message: 'Dashboard data updated successfully.',
                variant: 'success'
            }));
        } finally {
            this.isRefreshing = false;
        }
    }

    // ── Stat card clicks ───────────────────────────────────────────────────────

    handleStatCardClick(event) {
        const type = event.currentTarget.dataset.type;
        if (type === 'total') {
            this._loadModal('All Connections', null, '');
        } else if (type === 'accepted') {
            this._loadModal('Active Connections', 'accepted', '');
        } else if (type === 'pending') {
            this._loadModal('Pending Requests', 'pending', '');
        } else if (type === 'avgtat') {
            this._loadModal('Accepted Connections (with TAT)', 'accepted', '');
        }
    }

    // ── Drilldown from charts ──────────────────────────────────────────────────

    handleDrilldown(event) {
        const { dimension, value } = event.detail;
        let title = value;
        let dim   = dimension;

        if (dimension === 'status')    { title = `Status: ${value}`; dim = 'status'; }
        else if (dimension === 'monthly' || dimension === 'tat') { return; } // no drilldown on time charts
        else if (dimension === 'connector')  { title = `${value}'s Connections`; dim = 'connector'; }
        else if (dimension === 'initiator')  { title = `Requests Sent by ${value}`; dim = 'initiator'; }
        else if (dimension === 'recipient')  { title = `Requests Received by ${value}`; dim = 'recipient'; }
        else if (dimension === 'yearly')     { return; }

        this._loadModal(title, dim, value);
    }

    _loadModal(title, dimension, value) {
        this.modalTitle   = title;
        this.modalOpen    = true;
        this.modalLoading = true;
        this.modalConnections = [];

        getConnectionList({
            dimension: dimension,
            value: value,
            statusFilter: this.statusFilter,
            yearFilter: this.yearFilter
        })
            .then(data => { this.modalConnections = data || []; })
            .catch(() => { this.modalConnections = []; })
            .finally(() => { this.modalLoading = false; });
    }

    handleModalClose() {
        this.modalOpen = false;
        this.modalConnections = [];
    }
}