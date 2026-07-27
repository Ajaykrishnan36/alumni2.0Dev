import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSummaryStats        from '@salesforce/apex/KenMentorshipDashboardController.getSummaryStats';
import getMentorshipByStatus  from '@salesforce/apex/KenMentorshipDashboardController.getMentorshipByStatus';
import getCallByStatus        from '@salesforce/apex/KenMentorshipDashboardController.getCallByStatus';
import getMonthlyTrend        from '@salesforce/apex/KenMentorshipDashboardController.getMonthlyTrend';
import getMeetingMode         from '@salesforce/apex/KenMentorshipDashboardController.getMeetingMode';
import getTopMentors          from '@salesforce/apex/KenMentorshipDashboardController.getTopMentors';
import getTopMentees          from '@salesforce/apex/KenMentorshipDashboardController.getTopMentees';
import getYearlyGrowth        from '@salesforce/apex/KenMentorshipDashboardController.getYearlyGrowth';
import getByRecordType        from '@salesforce/apex/KenMentorshipDashboardController.getByRecordType';
import getAvailableYears      from '@salesforce/apex/KenMentorshipDashboardController.getAvailableYears';
import getMentorshipList      from '@salesforce/apex/KenMentorshipDashboardController.getMentorshipList';

export default class KenMentorshipDashboard extends LightningElement {

    @track statusFilter = '';
    @track rtFilter     = '';
    @track yearFilter   = '';
    @track isRefreshing = false;

    @track modalVisible = false;
    @track modalTitle   = '';
    @track modalRecords = [];
    @track modalLoading = false;

    // Loading flags
    @track loadingConnStatus   = true;
    @track loadingCallStatus   = true;
    @track loadingMonthlyTrend = true;
    @track loadingMeetingMode  = true;
    @track loadingTopMentors   = true;
    @track loadingTopMentees   = true;
    @track loadingYearlyGrowth  = true;
    @track loadingRecordType    = true;

    // Data
    @track summaryStats           = { total: 0, activeConnections: 0, pendingRequests: 0, callsCompleted: 0, totalCalls: 0, completionRate: 0 };
    @track mentorshipByStatusData = [];
    @track callByStatusData       = [];
    @track monthlyTrendData       = [];
    @track meetingModeData        = [];
    @track topMentorsData         = [];
    @track topMenteesData         = [];
    @track yearlyGrowthData       = [];
    @track recordTypeData         = [];
    @track availableYears         = [];

    // Wire refs for refreshApex
    _wiredSummary;
    _wiredConnStatus;
    _wiredCallStatus;
    _wiredMonthlyTrend;
    _wiredMeetingMode;
    _wiredTopMentors;
    _wiredTopMentees;
    _wiredYearlyGrowth;
    _wiredRecordType;
    _wiredYears;

    get totalMentorships() { return this.summaryStats.total || 0; }

    // ── Wire adapters ──────────────────────────────────────────────────────────

    @wire(getSummaryStats, { statusFilter: '$statusFilter', rtFilter: '$rtFilter', yearFilter: '$yearFilter' })
    wiredSummary(result) {
        this._wiredSummary = result;
        if (result.data) this.summaryStats = result.data;
    }

    @wire(getMentorshipByStatus, { statusFilter: '$statusFilter', yearFilter: '$yearFilter' })
    wiredConnStatus(result) {
        this._wiredConnStatus = result;
        this.loadingConnStatus = false;
        if (result.data) this.mentorshipByStatusData = result.data;
    }

    @wire(getCallByStatus, { statusFilter: '$statusFilter', yearFilter: '$yearFilter' })
    wiredCallStatus(result) {
        this._wiredCallStatus = result;
        this.loadingCallStatus = false;
        if (result.data) this.callByStatusData = result.data;
    }

    @wire(getMonthlyTrend, { statusFilter: '$statusFilter', rtFilter: '$rtFilter', yearFilter: '$yearFilter' })
    wiredMonthlyTrend(result) {
        this._wiredMonthlyTrend = result;
        this.loadingMonthlyTrend = false;
        if (result.data) this.monthlyTrendData = result.data;
    }

    @wire(getMeetingMode, { statusFilter: '$statusFilter', rtFilter: '$rtFilter', yearFilter: '$yearFilter' })
    wiredMeetingMode(result) {
        this._wiredMeetingMode = result;
        this.loadingMeetingMode = false;
        if (result.data) this.meetingModeData = result.data;
    }

    @wire(getTopMentors, { statusFilter: '$statusFilter', rtFilter: '$rtFilter', yearFilter: '$yearFilter' })
    wiredTopMentors(result) {
        this._wiredTopMentors = result;
        this.loadingTopMentors = false;
        if (result.data) this.topMentorsData = result.data;
    }

    @wire(getTopMentees, { statusFilter: '$statusFilter', rtFilter: '$rtFilter', yearFilter: '$yearFilter' })
    wiredTopMentees(result) {
        this._wiredTopMentees = result;
        this.loadingTopMentees = false;
        if (result.data) this.topMenteesData = result.data;
    }

    @wire(getYearlyGrowth)
    wiredYearlyGrowth(result) {
        this._wiredYearlyGrowth = result;
        this.loadingYearlyGrowth = false;
        if (result.data) this.yearlyGrowthData = result.data;
    }

    @wire(getByRecordType, { statusFilter: '$statusFilter', yearFilter: '$yearFilter' })
    wiredRecordType(result) {
        this._wiredRecordType = result;
        this.loadingRecordType = false;
        if (result.data) this.recordTypeData = result.data;
    }

    @wire(getAvailableYears)
    wiredYears(result) {
        this._wiredYears = result;
        if (result.data) this.availableYears = result.data.filter(y => y !== 'All');
    }

    // ── Filter handlers ────────────────────────────────────────────────────────

    handleRtChange(event)     { this.rtFilter     = event.target.value; }
    handleStatusChange(event) { this.statusFilter = event.target.value; }
    handleYearChange(event)   { this.yearFilter   = event.target.value; }

    clearFilters() {
        this.statusFilter = '';
        this.rtFilter     = '';
        this.yearFilter   = '';
        this.template.querySelectorAll('.filter-select').forEach(s => { s.value = ''; });
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await Promise.all([
                refreshApex(this._wiredSummary),
                refreshApex(this._wiredConnStatus),
                refreshApex(this._wiredCallStatus),
                refreshApex(this._wiredMonthlyTrend),
                refreshApex(this._wiredMeetingMode),
                refreshApex(this._wiredTopMentors),
                refreshApex(this._wiredTopMentees),
                refreshApex(this._wiredYearlyGrowth),
                refreshApex(this._wiredRecordType),
                refreshApex(this._wiredYears)
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
        if (type === 'total')   { this._loadModal('All Records', 'all', ''); }
        if (type === 'active')  { this._loadModal('Active Mentorships', 'conn_status', 'Accepted'); }
        if (type === 'pending') { this._loadModal('Pending Requests', 'conn_status', 'Requested'); }
        if (type === 'calls')   { this._loadModal('Completed Calls', 'call_status', 'Completed'); }
    }

    // ── Chart drilldown ────────────────────────────────────────────────────────

    handleDrilldown(event) {
        const { dimension, value } = event.detail;
        if (dimension === 'monthly' || dimension === 'yearly') return;

        if (dimension === 'rt') {
            const rtKey = value === 'Connection Requests' ? 'Connection_Request' : 'Call_Request';
            this._loadModal(value, 'rt_type', rtKey);
        } else if (dimension === 'conn_status') {
            this._loadModal('Connections — ' + value, 'conn_status', value);
        } else if (dimension === 'call_status') {
            this._loadModal('Calls — ' + value, 'call_status', value);
        } else if (dimension === 'mode') {
            this._loadModal('Meeting Mode — ' + value, 'mode', value);
        } else if (dimension === 'mentor') {
            this._loadModal('Mentorships by ' + value, 'mentor', value);
        } else if (dimension === 'mentee') {
            this._loadModal('Mentorships for ' + value, 'mentee', value);
        }
    }

    // ── Modal ──────────────────────────────────────────────────────────────────

    _loadModal(title, dimension, value) {
        this.modalTitle   = title;
        this.modalVisible = true;
        this.modalLoading = true;
        this.modalRecords = [];

        getMentorshipList({
            title,
            dimension,
            value,
            statusFilter : this.statusFilter,
            rtFilter     : this.rtFilter,
            yearFilter   : this.yearFilter
        })
        .then(data => {
            this.modalRecords = data.map(r => ({
                ...r,
                statusClass  : 'status-badge status-' + (r.status || '').toLowerCase().replace(/\s+/g, '-'),
                rtLabel      : r.recordType === 'Call_Request' ? 'Call Request' : 'Connection',
                rtClass      : r.recordType === 'Call_Request' ? 'rt-badge rt-call' : 'rt-badge rt-conn',
                meetDateDisp : r.meetDate ? r.meetDate.substring(0, 10) : '—',
                mentorDisp   : r.mentorName  || '—',
                menteeDisp   : r.menteeName  || '—',
                modeClass    : r.meetingMode === 'Online' ? 'mode-badge mode-online' : (r.meetingMode ? 'mode-badge mode-inperson' : ''),
                titleDisp    : r.meetingTitle || '—'
            }));
        })
        .catch(() => { this.modalRecords = []; })
        .finally(() => { this.modalLoading = false; });
    }

    handleModalClose() {
        this.modalVisible = false;
        this.modalRecords = [];
    }
}