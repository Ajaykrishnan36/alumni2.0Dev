import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPortalConfigs from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';
import getFilterOptions             from '@salesforce/apex/KenAlumniDashboardController.getFilterOptions';
import getSummaryStats              from '@salesforce/apex/KenAlumniDashboardController.getSummaryStats';
import getActiveAlumniByBatch       from '@salesforce/apex/KenAlumniDashboardController.getActiveAlumniByBatch';
import getGraduationYearDistribution from '@salesforce/apex/KenAlumniDashboardController.getGraduationYearDistribution';
import getAgeDistribution           from '@salesforce/apex/KenAlumniDashboardController.getAgeDistribution';
import getEmploymentStatus          from '@salesforce/apex/KenAlumniDashboardController.getEmploymentStatus';
import getTopSkillsAndInterests     from '@salesforce/apex/KenAlumniDashboardController.getTopSkillsAndInterests';
import getLifecycleDistribution     from '@salesforce/apex/KenAlumniDashboardController.getLifecycleDistribution';
import getProfileCompleteness       from '@salesforce/apex/KenAlumniDashboardController.getProfileCompleteness';
import getBatchDemographics         from '@salesforce/apex/KenAlumniDashboardController.getBatchDemographics';
import getGenderDistribution        from '@salesforce/apex/KenAlumniDashboardController.getGenderDistribution';
import getMultiDimensionalInsights  from '@salesforce/apex/KenAlumniDashboardController.getMultiDimensionalInsights';
import getProfessionalDistribution  from '@salesforce/apex/KenAlumniDashboardController.getProfessionalDistribution';
import getIndiaStateDistribution    from '@salesforce/apex/KenAlumniDashboardController.getIndiaStateDistribution';
import getWorldDistribution         from '@salesforce/apex/KenAlumniDashboardController.getWorldDistribution';
import getAlumniList                from '@salesforce/apex/KenAlumniDashboardController.getAlumniList';
import getReports                   from '@salesforce/apex/KenAlumniReportController.getReports';
import getRowCount                  from '@salesforce/apex/KenAlumniReportController.getRowCount';
import getReportChunk               from '@salesforce/apex/KenAlumniReportController.getReportChunk';

function mapItems(rawList) {
    return (rawList || []).map(d => ({ label: d.label, value: d.value }));
}

const DEFAULT_STATS = { totalAlumni: 0, activeAlumni: 0, activePercent: 0, avgCompleteness: 0 };
const DEFAULT_OPTS  = { batches: [], years: [] };

export default class KenAlumniDemographicsDashboard extends LightningElement {

    @wire(getPortalConfigs)
    wiredTheme({ data }) {
        if (!data) return;
        const host = this.template.host;
        if (data.primaryColor) {
            host.style.setProperty('--brand-primary',      data.primaryColor);
            host.style.setProperty('--brand-primary-soft', this._toSoft(data.primaryColor));
            // --brand-primary-hover is intentionally NOT set here — the CSS derives it
            // from --brand-primary via color-mix() so hover is always a darker shade of
            // whatever the org's theme colour is, instead of a hardcoded/unchanged value.
        }
        if (data.secondaryColor) host.style.setProperty('--brand-secondary', data.secondaryColor);
        if (data.tertiaryColor)  host.style.setProperty('--brand-tertiary',  data.tertiaryColor);
    }

    _toSoft(hex) {
        if (!hex || typeof hex !== 'string') return 'rgba(185,28,92,.10)';
        const v = hex.replace('#', '');
        if (v.length !== 3 && v.length !== 6) return 'rgba(185,28,92,.10)';
        const e = v.length === 3 ? v.split('').map(c => c + c).join('') : v;
        const r = parseInt(e.slice(0, 2), 16);
        const g = parseInt(e.slice(2, 4), 16);
        const b = parseInt(e.slice(4, 6), 16);
        return `rgba(${r},${g},${b},.10)`;
    }

    // ── Filters ───────────────────────────────────────────────────────────────
    @track filterBatch  = '';
    @track filterYear   = '';
    @track filterStatus = '';

    // ── Loading flags ──────────────────────────────────────────────────────────
    @track loadingActive       = true;
    @track loadingGradYear     = true;
    @track loadingAge          = true;
    @track loadingEmployment   = true;
    @track loadingInterests    = true;
    @track loadingLifecycle    = true;
    @track loadingCompleteness = true;
    @track loadingBatch        = true;
    @track loadingGender       = true;
    @track loadingMultiDim     = true;
    @track loadingProfessional = true;
    @track loadingIndia        = true;
    @track loadingWorld        = true;

    // ── Chart data ─────────────────────────────────────────────────────────────
    @track activeAlumniData  = [];
    @track gradYearData      = [];
    @track ageData           = [];
    @track employmentData    = [];
    @track interestsData     = [];
    @track lifecycleData     = [];
    @track completenessData  = [];
    @track batchData         = [];
    @track genderData        = [];
    @track multiDimData      = [];
    @track professionalData  = [];
    @track indiaStateData    = [];
    @track worldData         = [];

    // ── Summary & options ──────────────────────────────────────────────────────
    @track summaryStats  = DEFAULT_STATS;
    @track filterOptions = DEFAULT_OPTS;

    // ── Refresh state ──────────────────────────────────────────────────────────
    @track isRefreshing = false;

    // ── Report downloads ───────────────────────────────────────────────────────
    @track reportDownloads = [];

    // ── Modal ──────────────────────────────────────────────────────────────────
    @track modalOpen    = false;
    @track modalTitle   = '';
    @track modalAlumni  = [];
    @track modalLoading = false;

    // ── Wire result stores (for refreshApex) ───────────────────────────────────
    _wFilterOptions; _wStats;
    _wActiveAlumni; _wGradYear; _wAge; _wEmployment; _wInterests;
    _wLifecycle; _wCompleteness; _wBatch; _wGender;
    _wMultiDim; _wProfessional; _wIndia; _wWorld;

    get totalAlumni() { return this.summaryStats.totalAlumni || 0; }

    // ── Wire: filter options ───────────────────────────────────────────────────
    @wire(getFilterOptions)
    wFilterOptions(result) {
        this._wFilterOptions = result;
        if (result.data) this.filterOptions = result.data;
    }

    // ── Wire: summary stats ────────────────────────────────────────────────────
    @wire(getSummaryStats, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wStats(result) {
        this._wStats = result;
        if (result.data) this.summaryStats = result.data;
    }

    // ── Wire: chart data ───────────────────────────────────────────────────────
    @wire(getActiveAlumniByBatch, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wActiveAlumni(result) {
        this._wActiveAlumni = result;
        this.loadingActive = false;
        if (result.data) this.activeAlumniData = mapItems(result.data);
    }

    @wire(getGraduationYearDistribution, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wGradYear(result) {
        this._wGradYear = result;
        this.loadingGradYear = false;
        if (result.data) this.gradYearData = mapItems(result.data);
    }

    @wire(getAgeDistribution, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wAge(result) {
        this._wAge = result;
        this.loadingAge = false;
        if (result.data) this.ageData = mapItems(result.data);
    }

    @wire(getEmploymentStatus, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wEmployment(result) {
        this._wEmployment = result;
        this.loadingEmployment = false;
        if (result.data) this.employmentData = mapItems(result.data);
    }

    @wire(getTopSkillsAndInterests, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wInterests(result) {
        this._wInterests = result;
        this.loadingInterests = false;
        if (result.data) this.interestsData = mapItems(result.data);
    }

    @wire(getLifecycleDistribution, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wLifecycle(result) {
        this._wLifecycle = result;
        this.loadingLifecycle = false;
        if (result.data) this.lifecycleData = mapItems(result.data);
    }

    @wire(getProfileCompleteness, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wCompleteness(result) {
        this._wCompleteness = result;
        this.loadingCompleteness = false;
        if (result.data) this.completenessData = mapItems(result.data);
    }

    @wire(getBatchDemographics, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wBatch(result) {
        this._wBatch = result;
        this.loadingBatch = false;
        if (result.data) this.batchData = mapItems(result.data);
    }

    @wire(getGenderDistribution, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wGender(result) {
        this._wGender = result;
        this.loadingGender = false;
        if (result.data) this.genderData = mapItems(result.data);
    }

    @wire(getMultiDimensionalInsights, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wMultiDim(result) {
        this._wMultiDim = result;
        this.loadingMultiDim = false;
        if (result.data) this.multiDimData = mapItems(result.data);
    }

    @wire(getProfessionalDistribution, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wProfessional(result) {
        this._wProfessional = result;
        this.loadingProfessional = false;
        if (result.data) this.professionalData = mapItems(result.data);
    }

    @wire(getIndiaStateDistribution, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wIndia(result) {
        this._wIndia = result;
        this.loadingIndia = false;
        if (result.data) this.indiaStateData = mapItems(result.data);
    }

    @wire(getWorldDistribution, { filterBatch: '$filterBatch', filterYear: '$filterYear', filterStatus: '$filterStatus' })
    wWorld(result) {
        this._wWorld = result;
        this.loadingWorld = false;
        if (result.data) this.worldData = mapItems(result.data);
    }

    // ── Filter handlers ────────────────────────────────────────────────────────
    handleBatchChange(event)  { this.filterBatch  = event.target.value; }
    handleYearChange(event)   { this.filterYear   = event.target.value; }
    handleStatusChange(event) { this.filterStatus = event.target.value; }

    clearFilters() {
        this.filterBatch  = '';
        this.filterYear   = '';
        this.filterStatus = '';
        this.template.querySelectorAll('.filter-select').forEach(sel => { sel.value = ''; });
    }

    // ── Refresh ────────────────────────────────────────────────────────────────
    handleRefresh() {
        if (this.isRefreshing) return;
        this.isRefreshing = true;
        const wires = [
            this._wFilterOptions, this._wStats,
            this._wActiveAlumni, this._wGradYear, this._wAge,
            this._wEmployment, this._wInterests, this._wLifecycle,
            this._wCompleteness, this._wBatch, this._wGender,
            this._wMultiDim, this._wProfessional, this._wIndia, this._wWorld
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

    // ── Report downloads ───────────────────────────────────────────────────────
    connectedCallback() {
        getReports()
            .then((options) => {
                this.reportDownloads = (options || []).map(option => ({
                    key: option.key,
                    label: option.label,
                    buttonLabel: option.label,
                    description: `${option.description} (${option.columnCount} columns)`,
                    filePrefix: option.filePrefix,
                    isBusy: false
                }));
            })
            .catch(() => { this.reportDownloads = []; });
    }

    /**
     * Pulls the report a slice at a time and assembles the CSV in the browser.
     * Each call is its own Apex transaction, so the export is not bounded by a
     * single transaction's governor limits however many alumni the org holds.
     */
    async handleDownloadReport(event) {
        const key = event.currentTarget.dataset.key;
        const report = this.reportDownloads.find(r => r.key === key);
        if (!report || report.isBusy) return;
        this._setReport(key, { isBusy: true, buttonLabel: 'Preparing…' });

        try {
            const total = await getRowCount({ reportKey: key });
            const parts = [];
            let afterId = null;
            let fetched = 0;
            let done = false;

            while (!done) {
                const chunk = await getReportChunk({ reportKey: key, afterId });
                if (chunk.headerLine) parts.push(chunk.headerLine);
                if (chunk.csv) parts.push(chunk.csv);
                fetched += chunk.rowsInChunk || 0;
                afterId = chunk.lastId;
                done = chunk.done || !chunk.rowsInChunk || !afterId;
                this._setReport(key, { buttonLabel: this._progressLabel(fetched, total) });
            }

            this._saveCsv(parts.join('\r\n'), `${report.filePrefix}${this._stamp()}.csv`);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Download ready',
                message: `${fetched} row${fetched === 1 ? '' : 's'} exported.`,
                variant: 'success'
            }));
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: `${report.label} failed`,
                message: error?.body?.message || error?.message || 'Unexpected error.',
                variant: 'error'
            }));
        } finally {
            this._setReport(key, { isBusy: false, buttonLabel: report.label });
        }
    }

    _progressLabel(fetched, total) {
        if (!total) return `${fetched} rows…`;
        return `${Math.min(99, Math.floor((fetched / total) * 100))}%`;
    }

    _stamp() {
        const pad = n => String(n).padStart(2, '0');
        const d = new Date();
        return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
    }

    /**
     * Saves the assembled CSV. Lightning Web Security only lets
     * URL.createObjectURL accept a restricted set of MIME types and rejects
     * text/csv outright, so the permitted types are tried in turn and a data
     * URI is the last resort. The .csv extension on the download attribute is
     * what makes Excel open it, not the MIME type. The leading byte order mark
     * is what makes Excel read it as UTF-8.
     */
    _saveCsv(csv, fileName) {
        const text = '﻿' + csv;
        const types = ['text/plain;charset=utf-8', 'application/octet-stream', 'text/csv;charset=utf-8'];
        for (const type of types) {
            try {
                const url = URL.createObjectURL(new Blob([text], { type }));
                this._clickDownload(url, fileName);
                window.setTimeout(() => URL.revokeObjectURL(url), 30000);
                return;
            } catch (error) {
                // This MIME type is not permitted here; fall through to the next.
            }
        }
        this._clickDownload('data:text/csv;charset=utf-8,' + encodeURIComponent(text), fileName);
    }

    _clickDownload(url, fileName) {
        const link = document.createElement('a');
        link.href = url;
        link.download = fileName;
        link.target = '_self';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    _setReport(key, changes) {
        this.reportDownloads = this.reportDownloads.map(
            r => (r.key === key ? { ...r, ...changes } : r)
        );
    }

    // ── Stat card drill-down ───────────────────────────────────────────────────
    handleStatCardClick(event) {
        const type     = event.currentTarget.dataset.type;
        const isActive = type === 'active';
        this.modalTitle   = isActive
            ? `Active Alumni (${this.summaryStats.activeAlumni} alumni)`
            : `All Alumni (${this.summaryStats.totalAlumni} alumni)`;
        this.modalAlumni  = [];
        this.modalLoading = true;
        this.modalOpen    = true;
        getAlumniList({
            dimension:      'summary',
            dimensionValue: isActive ? 'Active' : 'All',
            filterBatch:    this.filterBatch,
            filterYear:     this.filterYear,
            filterStatus:   isActive ? 'Active' : this.filterStatus
        })
        .then(result => {
            this.modalAlumni  = result || [];
            this.modalLoading = false;
        })
        .catch(() => { this.modalLoading = false; });
    }

    // ── Drill-down ─────────────────────────────────────────────────────────────
    handleDrilldown(event) {
        const { dimension, value, count } = event.detail;
        if (!dimension || !value) return;
        this.modalTitle   = `${value} (${count || ''} alumni)`;
        this.modalAlumni  = [];
        this.modalLoading = true;
        this.modalOpen    = true;

        getAlumniList({
            dimension,
            dimensionValue: value,
            filterBatch:  this.filterBatch,
            filterYear:   this.filterYear,
            filterStatus: this.filterStatus
        })
        .then(result => {
            this.modalAlumni  = result || [];
            this.modalLoading = false;
        })
        .catch(() => { this.modalLoading = false; });
    }

    handleModalClose() {
        this.modalOpen   = false;
        this.modalAlumni = [];
    }
}