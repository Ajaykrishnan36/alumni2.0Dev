import { LightningElement, api, track } from 'lwc';
import getDownloadUrl from '@salesforce/apex/KenExportCsvController.getDownloadUrl';

const PAGE_SIZE = 20;

const APPROVAL_CLASS_MAP = {
    'Approved':         'status-badge status-approved',
    'Pending Approval': 'status-badge status-pending',
    'Rejected':         'status-badge status-rejected'
};

export default class KenSurveyListModal extends LightningElement {

    @api isOpen    = false;
    @api title     = 'Survey List';
    @api isLoading = false;
    @api modalMode = 'surveys'; // 'surveys' | 'responses'

    @track searchTerm  = '';
    @track currentPage = 1;

    // ── Survey list ────────────────────────────────────────────────────────────
    _surveyList = [];
    @api
    get surveyList() { return this._surveyList; }
    set surveyList(val) {
        this._surveyList = val || [];
        this.currentPage = 1;
        this.searchTerm  = '';
    }

    // ── Response list ──────────────────────────────────────────────────────────
    _responseList = [];
    @api
    get responseList() { return this._responseList; }
    set responseList(val) {
        this._responseList = val || [];
        this.currentPage   = 1;
        this.searchTerm    = '';
    }

    // ── Mode getters ───────────────────────────────────────────────────────────
    get isSurveyMode()   { return this.modalMode === 'surveys'; }
    get isResponseMode() { return this.modalMode === 'responses'; }
    get recordLabel()    { return this.isSurveyMode ? 'surveys' : 'responses'; }

    get activeList() {
        return this.isSurveyMode ? this._surveyList : this._responseList;
    }

    // ── Filtered list ──────────────────────────────────────────────────────────
    get filteredList() {
        const term = (this.searchTerm || '').toLowerCase().trim();
        const list = this.activeList;
        if (!term) {
            return this.isSurveyMode ? list.map(r => this._enrichSurvey(r)) : list;
        }
        if (this.isSurveyMode) {
            return list
                .filter(r =>
                    (r.name            || '').toLowerCase().includes(term) ||
                    (r.questionnaire   || '').toLowerCase().includes(term) ||
                    (r.approvalStatus  || '').toLowerCase().includes(term) ||
                    (r.targetAudience  || '').toLowerCase().includes(term)
                )
                .map(r => this._enrichSurvey(r));
        }
        return list.filter(r =>
            (r.respondentName || '').toLowerCase().includes(term) ||
            (r.surveyName     || '').toLowerCase().includes(term) ||
            (r.questionLabel  || '').toLowerCase().includes(term) ||
            (r.response       || '').toLowerCase().includes(term)
        );
    }

    _enrichSurvey(r) {
        return {
            ...r,
            approvalClass: APPROVAL_CLASS_MAP[r.approvalStatus] || 'status-badge',
            activeClass:   r.isActive ? 'active-yes' : 'active-no',
            activeLabel:   r.isActive ? 'Active' : 'Inactive'
        };
    }

    // ── Pagination ─────────────────────────────────────────────────────────────
    get recordCount()   { return this.filteredList.length; }
    get totalPages()    { return Math.max(1, Math.ceil(this.recordCount / PAGE_SIZE)); }
    get isFirstPage()   { return this.currentPage <= 1; }
    get isLastPage()    { return this.currentPage >= this.totalPages; }
    get pageInfo()      { return `Page ${this.currentPage} of ${this.totalPages}`; }

    get paginatedList() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredList.slice(start, start + PAGE_SIZE);
    }

    get hasRows() { return this.paginatedList.length > 0; }

    // ── Text helpers ───────────────────────────────────────────────────────────
    get loadingText()        { return this.isSurveyMode ? 'Loading surveys...' : 'Loading responses...'; }
    get emptyText()          { return this.isSurveyMode ? 'No surveys found'   : 'No responses found'; }
    get searchPlaceholder()  {
        return this.isSurveyMode
            ? 'Search by name, questionnaire, status or audience...'
            : 'Search by respondent, survey or question...';
    }

    // ── Event handlers ─────────────────────────────────────────────────────────
    handleSearch(event) {
        this.searchTerm  = event.target.value;
        this.currentPage = 1;
    }

    prevPage() { if (!this.isFirstPage) this.currentPage--; }
    nextPage() { if (!this.isLastPage)  this.currentPage++; }

    handleRowClick(event) {
        const recordId  = event.currentTarget.dataset.recordId;
        const objectApi = event.currentTarget.dataset.objectApi;
        if (!recordId || !objectApi) return;
        window.open('/lightning/r/' + objectApi + '/' + recordId + '/view', '_blank');
    }

    handleClose()         { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdropClick() { this.handleClose(); }
    stopPropagation(event) { event.stopPropagation(); }

    // ── CSV Export ─────────────────────────────────────────────────────────────
    handleExportCsv() {
        const list = this.filteredList;
        if (!list.length) return;
        let headers, rows;
        if (this.isSurveyMode) {
            headers = ['Survey Name', 'Questionnaire', 'Approval Status', 'Active',
                       'Target Audience', 'Start Date', 'End Date', 'Responses'];
            rows = list.map(r => [
                this._csvCell(r.name),
                this._csvCell(r.questionnaire),
                this._csvCell(r.approvalStatus),
                this._csvCell(r.isActive ? 'Yes' : 'No'),
                this._csvCell(r.targetAudience),
                this._csvCell(r.startDate),
                this._csvCell(r.endDate),
                this._csvCell(r.responseCount)
            ]);
        } else {
            headers = ['Respondent', 'Survey', 'Question', 'Response', 'Date'];
            rows = list.map(r => [
                this._csvCell(r.respondentName),
                this._csvCell(r.surveyName),
                this._csvCell(r.questionLabel),
                this._csvCell(r.response),
                this._csvCell(r.createdDate)
            ]);
        }
        const csv      = [headers.map(h => `"${h}"`), ...rows].map(row => row.join(',')).join('\n');
        const filename = (this.title || 'records').replace(/[^a-zA-Z0-9_-]/g, '_') + '.csv';
        getDownloadUrl({ csvContent: csv, filename: filename })
            .then(url => { window.location.href = url; })
            .catch(err => console.error('Export failed', err));
    }

    _csvCell(val) {
        return '"' + String(val == null ? '' : val).replace(/"/g, '""') + '"';
    }
}