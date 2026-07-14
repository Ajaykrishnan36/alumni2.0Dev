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