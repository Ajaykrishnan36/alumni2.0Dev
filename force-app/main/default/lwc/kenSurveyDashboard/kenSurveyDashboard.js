import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSummaryStats              from '@salesforce/apex/KenSurveyDashboardController.getSummaryStats';
import getSurveysByApprovalStatus   from '@salesforce/apex/KenSurveyDashboardController.getSurveysByApprovalStatus';
import getSurveysByActiveStatus     from '@salesforce/apex/KenSurveyDashboardController.getSurveysByActiveStatus';
import getTopSurveysByResponses     from '@salesforce/apex/KenSurveyDashboardController.getTopSurveysByResponses';
import getQuestionTypeDistribution  from '@salesforce/apex/KenSurveyDashboardController.getQuestionTypeDistribution';
import getResponseTrend             from '@salesforce/apex/KenSurveyDashboardController.getResponseTrend';
import getTopQuestionnaires         from '@salesforce/apex/KenSurveyDashboardController.getTopQuestionnaires';
import getFilterOptions             from '@salesforce/apex/KenSurveyDashboardController.getFilterOptions';
import getSurveyList                from '@salesforce/apex/KenSurveyDashboardController.getSurveyList';
import getResponseList              from '@salesforce/apex/KenSurveyDashboardController.getResponseList';

function mapPoints(rawList) {
    return (rawList || []).map(d => ({ label: d.label, value: d.value }));
}

const DEFAULT_STATS = { total: 0, active: 0, pending: 0, responses: 0 };

export default class KenSurveyDashboard extends NavigationMixin(LightningElement) {

    // ── Filters ───────────────────────────────────────────────────────────────
    @track filterApproval = 'All';
    @track filterActive   = 'All';
    @track filterYear     = 'All';
    @track isRefreshing   = false;

    // ── Modal ──────────────────────────────────────────────────────────────────
    @track modalOpen      = false;
    @track modalTitle     = '';
    @track modalMode      = 'surveys';
    @track modalSurveys   = [];
    @track modalResponses = [];
    @track modalLoading   = false;

    // ── Filter options ─────────────────────────────────────────────────────────
    @track approvalOptions = [];
    @track yearOptions     = [];

    // ── Loading flags ──────────────────────────────────────────────────────────
    @track loadingByApproval = true;
    @track loadingByActive   = true;
    @track loadingTrend      = true;
    @track loadingTopSurveys = true;
    @track loadingQType      = true;
    @track loadingTopQ       = true;

    // ── Raw wire results ───────────────────────────────────────────────────────
    @track _rawStats;
    @track _rawByApproval;
    @track _rawByActive;
    @track _rawTrend;
    @track _rawTopSurveys;
    @track _rawQType;
    @track _rawTopQ;
    _wFilterOptions;

    // ── Computed filter values passed to wires ─────────────────────────────────
    get _activeParam() {
        if (this.filterActive === 'Active Only')   return 'true';
        if (this.filterActive === 'Inactive Only') return 'false';
        return 'All';
    }

    // ── Wire: filter options ───────────────────────────────────────────────────
    @wire(getFilterOptions)
    wFilterOptions(result) {
        this._wFilterOptions = result;
        if (result.data) {
            const data = result.data;
            this.approvalOptions = (data.approvalStatuses || []).map(o => ({ label: o.label, value: o.value }));
            this.yearOptions     = (data.years            || []).map(o => ({ label: o.label, value: o.value }));
        }
    }

    // ── Wire: summary stats ────────────────────────────────────────────────────
    @wire(getSummaryStats, {
        approvalStatus: '$filterApproval',
        isActive:       '$_activeParam',
        year:           '$filterYear'
    })
    wStats(result) {
        this._rawStats = result;
    }

    // ── Wire: chart data ───────────────────────────────────────────────────────
    @wire(getSurveysByApprovalStatus, {
        isActive: '$_activeParam',
        year:     '$filterYear'
    })
    wByApproval(result) {
        this._rawByApproval  = result;
        this.loadingByApproval = false;
    }

    @wire(getSurveysByActiveStatus, {
        approvalStatus: '$filterApproval',
        year:           '$filterYear'
    })
    wByActive(result) {
        this._rawByActive  = result;
        this.loadingByActive = false;
    }

    @wire(getResponseTrend, {
        approvalStatus: '$filterApproval',
        isActive:       '$_activeParam',
        year:           '$filterYear'
    })
    wTrend(result) {
        this._rawTrend  = result;
        this.loadingTrend = false;
    }

    @wire(getTopSurveysByResponses, {
        approvalStatus: '$filterApproval',
        isActive:       '$_activeParam',
        year:           '$filterYear'
    })
    wTopSurveys(result) {
        this._rawTopSurveys  = result;
        this.loadingTopSurveys = false;
    }

    @wire(getQuestionTypeDistribution, {
        approvalStatus: '$filterApproval',
        isActive:       '$_activeParam',
        year:           '$filterYear'
    })
    wQType(result) {
        this._rawQType  = result;
        this.loadingQType = false;
    }

    @wire(getTopQuestionnaires, {
        approvalStatus: '$filterApproval',
        isActive:       '$_activeParam',
        year:           '$filterYear'
    })
    wTopQ(result) {
        this._rawTopQ  = result;
        this.loadingTopQ = false;
    }

    // ── Data getters ──────────────────────────────────────────────────────────
    get stats() {
        return (this._rawStats && this._rawStats.data) ? this._rawStats.data : DEFAULT_STATS;
    }
    get surveysByApprovalData()   { return this._rawByApproval   && this._rawByApproval.data   ? mapPoints(this._rawByApproval.data)   : []; }
    get surveysByActiveData()     { return this._rawByActive     && this._rawByActive.data     ? mapPoints(this._rawByActive.data)     : []; }
    get responseTrendData()       { return this._rawTrend        && this._rawTrend.data        ? mapPoints(this._rawTrend.data)        : []; }
    get topSurveysByResponsesData() { return this._rawTopSurveys && this._rawTopSurveys.data   ? mapPoints(this._rawTopSurveys.data)   : []; }
    get questionTypeData()        { return this._rawQType        && this._rawQType.data        ? mapPoints(this._rawQType.data)        : []; }
    get topQuestionnairesData()   { return this._rawTopQ         && this._rawTopQ.data         ? mapPoints(this._rawTopQ.data)         : []; }

    // ── Filter handlers ────────────────────────────────────────────────────────
    handleFilterChange(event) {
        const field = event.currentTarget.dataset.field;
        this[field] = event.target.value;
    }

    clearFilters() {
        this.filterApproval = 'All';
        this.filterActive   = 'All';
        this.filterYear     = 'All';
        this.template.querySelectorAll('.filter-select').forEach(sel => {
            sel.value = sel.options[0].value;
        });
    }

    // ── Refresh ────────────────────────────────────────────────────────────────
    handleCreateQuestionnaire() {
        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__questionnaireEditController'
            }
        });
    }

    handleCreateSurvey() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Ken_Survey__c',
                actionName: 'new'
            }
        });
    }

    handleRefresh() {
        if (this.isRefreshing) return;
        this.isRefreshing = true;
        const wires = [
            this._wFilterOptions, this._rawStats,
            this._rawByApproval, this._rawByActive, this._rawTrend,
            this._rawTopSurveys, this._rawQType, this._rawTopQ
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
        if (type === 'responses') {
            this.openResponseModal('All Responses', null);
            return;
        }
        if (type === 'total') {
            this.openSurveyModal('All Surveys', null, 'All');
        } else if (type === 'active') {
            this.openSurveyModal('Active Surveys', 'active', 'Active');
        } else if (type === 'pending') {
            this.openSurveyModal('Pending Approval Surveys', 'approval', 'Pending Approval');
        }
    }

    // ── Drill-down ─────────────────────────────────────────────────────────────
    handleDrilldown(event) {
        const { dimension, value } = event.detail;
        if (!dimension || !value) return;

        if (dimension === 'survey_responses') {
            this.openResponseModal('Responses — ' + value, value);
            return;
        }
        if (dimension === 'trend') {
            // Response trend drill-down: open response modal filtered by nothing special
            this.openResponseModal('Responses in ' + value, null);
            return;
        }
        // dimensions: approval, active, questionnaire, qtype (show surveys)
        if (dimension === 'qtype') {
            // Cannot filter surveys by qtype directly; show all filtered surveys
            this.openSurveyModal('Surveys — ' + value + ' Questions', null, 'All');
            return;
        }
        this.openSurveyModal(value + ' Surveys', dimension, value);
    }

    // ── Modal helpers ──────────────────────────────────────────────────────────
    openSurveyModal(title, dimension, dimensionValue) {
        this.modalTitle     = title;
        this.modalMode      = 'surveys';
        this.modalSurveys   = [];
        this.modalResponses = [];
        this.modalLoading   = true;
        this.modalOpen      = true;
        getSurveyList({
            dimension:      dimension || '',
            dimensionValue: dimensionValue || '',
            approvalStatus: this.filterApproval,
            isActive:       this._activeParam,
            year:           this.filterYear
        })
        .then(result => {
            this.modalSurveys  = result || [];
            this.modalLoading  = false;
        })
        .catch(() => { this.modalLoading = false; });
    }

    openResponseModal(title, surveyName) {
        this.modalTitle     = title;
        this.modalMode      = 'responses';
        this.modalSurveys   = [];
        this.modalResponses = [];
        this.modalLoading   = true;
        this.modalOpen      = true;
        getResponseList({
            surveyName:     surveyName || '',
            approvalStatus: this.filterApproval,
            isActive:       this._activeParam,
            year:           this.filterYear
        })
        .then(result => {
            this.modalResponses = result || [];
            this.modalLoading   = false;
        })
        .catch(() => { this.modalLoading = false; });
    }

    handleModalClose() {
        this.modalOpen      = false;
        this.modalMode      = 'surveys';
        this.modalSurveys   = [];
        this.modalResponses = [];
    }
}