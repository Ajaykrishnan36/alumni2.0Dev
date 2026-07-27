import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFilterOptions              from '@salesforce/apex/KenEventsDashboardController.getFilterOptions';
import getSummaryStats               from '@salesforce/apex/KenEventsDashboardController.getSummaryStats';
import getEventsByStatus             from '@salesforce/apex/KenEventsDashboardController.getEventsByStatus';
import getEventsByType               from '@salesforce/apex/KenEventsDashboardController.getEventsByType';
import getEventPricingDistribution   from '@salesforce/apex/KenEventsDashboardController.getEventPricingDistribution';
import getBookingStatusBreakdown     from '@salesforce/apex/KenEventsDashboardController.getBookingStatusBreakdown';
import getRegistrationTrends         from '@salesforce/apex/KenEventsDashboardController.getRegistrationTrends';
import getTopEventsByRegistrations   from '@salesforce/apex/KenEventsDashboardController.getTopEventsByRegistrations';
import getTargetAudienceBreakdown    from '@salesforce/apex/KenEventsDashboardController.getTargetAudienceBreakdown';
import getMonthlyEventActivity       from '@salesforce/apex/KenEventsDashboardController.getMonthlyEventActivity';
import getEventLocationDistribution  from '@salesforce/apex/KenEventsDashboardController.getEventLocationDistribution';
import getTopRecurringAttendees      from '@salesforce/apex/KenEventsDashboardController.getTopRecurringAttendees';
import getEventList                  from '@salesforce/apex/KenEventsDashboardController.getEventList';
import getBookingList                from '@salesforce/apex/KenEventsDashboardController.getBookingList';

function mapItems(rawList) {
    return (rawList || []).map(d => ({ label: d.label, value: d.value }));
}

const DEFAULT_STATS = { totalEvents: 0, totalRegistrations: 0, publishedEvents: 0, cancelledBookings: 0 };
const DEFAULT_OPTS  = { eventTypes: [], statuses: [], years: [] };

export default class KenEventsDashboard extends NavigationMixin(LightningElement) {

    // ── Filters ───────────────────────────────────────────────────────────────
    @track filterType   = '';
    @track filterStatus = '';
    @track filterYear   = '';

    // ── Loading flags ──────────────────────────────────────────────────────────
    @track loadingByStatus      = true;
    @track loadingByType        = true;
    @track loadingPricing       = true;
    @track loadingBookingStatus = true;
    @track loadingTrends        = true;
    @track loadingTopEvents     = true;
    @track loadingAudience      = true;
    @track loadingMonthly       = true;
    @track loadingLocation      = true;
    @track loadingRecurring     = true;

    // ── Chart data ─────────────────────────────────────────────────────────────
    @track eventsByStatusData = [];
    @track eventsByTypeData   = [];
    @track pricingData        = [];
    @track bookingStatusData  = [];
    @track trendsData         = [];
    @track topEventsData      = [];
    @track audienceData       = [];
    @track monthlyData        = [];
    @track locationData       = [];
    @track recurringData      = [];

    // ── Summary & options ──────────────────────────────────────────────────────
    @track summaryStats  = DEFAULT_STATS;
    @track filterOptions = DEFAULT_OPTS;

    // ── Refresh state ──────────────────────────────────────────────────────────
    @track isRefreshing = false;

    // ── Modal ──────────────────────────────────────────────────────────────────
    @track modalOpen     = false;
    @track modalTitle    = '';
    @track modalMode     = 'events';
    @track modalEvents   = [];
    @track modalBookings = [];
    @track modalLoading  = false;

    // ── Wire result stores ─────────────────────────────────────────────────────
    _wFilterOptions;
    _wStats; _wByStatus; _wByType; _wPricing;
    _wBookingStatus; _wTrends; _wTopEvents;
    _wAudience; _wMonthly; _wLocation; _wRecurring;

    get totalEvents() { return this.summaryStats.totalEvents || 0; }

    // ── Wire: filter options ───────────────────────────────────────────────────
    @wire(getFilterOptions)
    wFilterOptions(result) {
        this._wFilterOptions = result;
        if (result.data) this.filterOptions = result.data;
    }

    // ── Wire: summary stats ────────────────────────────────────────────────────
    @wire(getSummaryStats, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wStats(result) {
        this._wStats = result;
        if (result.data) this.summaryStats = result.data;
    }

    // ── Wire: chart data ───────────────────────────────────────────────────────
    @wire(getEventsByStatus, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wByStatus(result) {
        this._wByStatus = result;
        this.loadingByStatus = false;
        if (result.data) this.eventsByStatusData = mapItems(result.data);
    }

    @wire(getEventsByType, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wByType(result) {
        this._wByType = result;
        this.loadingByType = false;
        if (result.data) this.eventsByTypeData = mapItems(result.data);
    }

    @wire(getEventPricingDistribution, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wPricing(result) {
        this._wPricing = result;
        this.loadingPricing = false;
        if (result.data) this.pricingData = mapItems(result.data);
    }

    @wire(getBookingStatusBreakdown, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wBookingStatus(result) {
        this._wBookingStatus = result;
        this.loadingBookingStatus = false;
        if (result.data) this.bookingStatusData = mapItems(result.data);
    }

    @wire(getRegistrationTrends, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wTrends(result) {
        this._wTrends = result;
        this.loadingTrends = false;
        if (result.data) this.trendsData = mapItems(result.data);
    }

    @wire(getTopEventsByRegistrations, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wTopEvents(result) {
        this._wTopEvents = result;
        this.loadingTopEvents = false;
        if (result.data) this.topEventsData = mapItems(result.data);
    }

    @wire(getTargetAudienceBreakdown, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wAudience(result) {
        this._wAudience = result;
        this.loadingAudience = false;
        if (result.data) this.audienceData = mapItems(result.data);
    }

    @wire(getMonthlyEventActivity, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wMonthly(result) {
        this._wMonthly = result;
        this.loadingMonthly = false;
        if (result.data) this.monthlyData = mapItems(result.data);
    }

    @wire(getEventLocationDistribution, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wLocation(result) {
        this._wLocation = result;
        this.loadingLocation = false;
        if (result.data) this.locationData = mapItems(result.data);
    }

    @wire(getTopRecurringAttendees, { filterType: '$filterType', filterStatus: '$filterStatus', filterYear: '$filterYear' })
    wRecurring(result) {
        this._wRecurring = result;
        this.loadingRecurring = false;
        if (result.data) this.recurringData = mapItems(result.data);
    }

    // ── Filter handlers ────────────────────────────────────────────────────────
    handleTypeChange(event)   { this.filterType   = event.target.value; }
    handleStatusChange(event) { this.filterStatus = event.target.value; }
    handleYearChange(event)   { this.filterYear   = event.target.value; }

    clearFilters() {
        this.filterType   = '';
        this.filterStatus = '';
        this.filterYear   = '';
        this.template.querySelectorAll('.filter-select').forEach(sel => { sel.value = ''; });
    }

    // ── Refresh ────────────────────────────────────────────────────────────────
    handleCreateEvent() {
        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__kenEventHandler'
            }
        });
    }

    handleRefresh() {
        if (this.isRefreshing) return;
        this.isRefreshing = true;
        const wires = [
            this._wFilterOptions, this._wStats,
            this._wByStatus, this._wByType, this._wPricing,
            this._wBookingStatus, this._wTrends, this._wTopEvents,
            this._wAudience, this._wMonthly, this._wLocation, this._wRecurring
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

    // ── Stat card click ────────────────────────────────────────────────────────
    handleStatCardClick(event) {
        const type = event.currentTarget.dataset.type;

        if (type === 'registrations' || type === 'cancellations') {
            this.modalTitle    = type === 'registrations'
                ? `Total Registrations (${this.summaryStats.totalRegistrations})`
                : `Cancelled Bookings (${this.summaryStats.cancelledBookings})`;
            this.modalMode     = 'bookings';
            this.modalEvents   = [];
            this.modalBookings = [];
            this.modalLoading  = true;
            this.modalOpen     = true;
            getBookingList({
                dimension:      type,
                dimensionValue: '',
                filterType:     this.filterType,
                filterStatus:   this.filterStatus,
                filterYear:     this.filterYear
            })
            .then(result => {
                this.modalBookings = result || [];
                this.modalLoading  = false;
            })
            .catch(() => { this.modalLoading = false; });
            return;
        }

        const isPublished = type === 'published';
        this.modalTitle    = isPublished
            ? `Published Events (${this.summaryStats.publishedEvents})`
            : `All Events (${this.summaryStats.totalEvents})`;
        this.modalMode     = 'events';
        this.modalEvents   = [];
        this.modalBookings = [];
        this.modalLoading  = true;
        this.modalOpen     = true;
        getEventList({
            dimension:      'summary',
            dimensionValue: isPublished ? 'Published' : 'All',
            filterType:     this.filterType,
            filterStatus:   isPublished ? 'Approved' : this.filterStatus,
            filterYear:     this.filterYear
        })
        .then(result => {
            this.modalEvents  = result || [];
            this.modalLoading = false;
        })
        .catch(() => { this.modalLoading = false; });
    }

    // ── Drill-down ─────────────────────────────────────────────────────────────
    handleDrilldown(event) {
        const { dimension, value, count } = event.detail;
        if (!dimension || !value) return;

        if (dimension === 'top_events' || dimension === 'trends') {
            this.modalTitle    = dimension === 'trends'
                ? `Registrations in ${value}`
                : `Registrations — ${value}`;
            this.modalMode     = 'bookings';
            this.modalEvents   = [];
            this.modalBookings = [];
            this.modalLoading  = true;
            this.modalOpen     = true;
            getBookingList({
                dimension,
                dimensionValue: value,
                filterType:     this.filterType,
                filterStatus:   this.filterStatus,
                filterYear:     this.filterYear
            })
            .then(result => {
                this.modalBookings = result || [];
                this.modalLoading  = false;
            })
            .catch(() => { this.modalLoading = false; });
            return;
        }

        this.modalTitle    = `${value} (${count != null ? count : ''} events)`;
        this.modalMode     = 'events';
        this.modalEvents   = [];
        this.modalBookings = [];
        this.modalLoading  = true;
        this.modalOpen     = true;
        getEventList({
            dimension,
            dimensionValue: value,
            filterType:   this.filterType,
            filterStatus: this.filterStatus,
            filterYear:   this.filterYear
        })
        .then(result => {
            this.modalEvents  = result || [];
            this.modalLoading = false;
        })
        .catch(() => { this.modalLoading = false; });
    }

    handleModalClose() {
        this.modalOpen     = false;
        this.modalMode     = 'events';
        this.modalEvents   = [];
        this.modalBookings = [];
    }
}