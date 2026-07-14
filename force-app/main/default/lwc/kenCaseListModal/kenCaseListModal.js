import { LightningElement, api, track } from 'lwc';
import getDownloadUrl from '@salesforce/apex/KenExportCsvController.getDownloadUrl';

const PAGE_SIZE = 20;

const STATUS_CLASS_MAP = {
    'New':                 'status-badge status-progress',
    'In Progress':         'status-badge status-pending',
    'Waiting for Student': 'status-badge status-review',
    'Response Received':   'status-badge status-review',
    'On Hold':             'status-badge status-pending',
    'Escalated':           'status-badge status-rejected',
    'Closed':              'status-badge status-approved',
    'Resolved':            'status-badge status-approved',
    'Canceled':            'status-badge status-cancelled',
    'Merged':              'status-badge status-cancelled'
};

export default class KenCaseListModal extends LightningElement {

    @api isOpen    = false;
    @api title     = 'Case List';
    @api isLoading = false;

    @track searchTerm  = '';
    @track currentPage = 1;

    _caseList = [];

    @api
    get caseList() { return this._caseList; }
    set caseList(val) {
        this._caseList   = val || [];
        this.currentPage = 1;
        this.searchTerm  = '';
    }

    // ── Getters ───────────────────────────────────────────────────────────────

    get filteredList() {
        const term = (this.searchTerm || '').toLowerCase().trim();
        if (!term) return this._caseList;
        return this._caseList.filter(r =>
            (r.caseNumber      || '').toLowerCase().includes(term) ||
            (r.subject         || '').toLowerCase().includes(term) ||
            (r.status          || '').toLowerCase().includes(term) ||
            (r.serviceName     || '').toLowerCase().includes(term) ||
            (r.serviceOffering || '').toLowerCase().includes(term) ||
            (r.origin          || '').toLowerCase().includes(term) ||
            (r.submitterName   || '').toLowerCase().includes(term)
        );
    }

    get recordCount()    { return this.filteredList.length; }
    get totalPages()     { return Math.max(1, Math.ceil(this.recordCount / PAGE_SIZE)); }
    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage >= this.totalPages; }
    get pageInfo()       { return `Page ${this.currentPage} of ${this.totalPages}`; }

    get paginatedList() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredList.slice(start, start + PAGE_SIZE).map(r => ({
            ...r,
            statusClass: STATUS_CLASS_MAP[r.status] || 'status-badge'
        }));
    }

    get hasRows() { return this.paginatedList.length > 0; }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handleSearch(event) {
        this.searchTerm  = event.target.value;
        this.currentPage = 1;
    }

    prevPage() { if (!this.isPrevDisabled) this.currentPage--; }
    nextPage() { if (!this.isNextDisabled) this.currentPage++; }

    handleExportCsv() {
        const list = this.filteredList;
        if (!list.length) return;
        const headers = ['Case #', 'Subject', 'Status', 'Service', 'Service Offering', 'Origin', 'Submitted By', 'Date'];
        const rows = list.map(r => [
            this._csvCell(r.caseNumber),
            this._csvCell(r.subject),
            this._csvCell(r.status),
            this._csvCell(r.serviceName),
            this._csvCell(r.serviceOffering),
            this._csvCell(r.origin),
            this._csvCell(r.submitterName),
            this._csvCell(r.createdDate)
        ]);
        const csv      = [headers.map(h => `"${h}"`), ...rows].map(row => row.join(',')).join('\n');
        const filename = (this.title || 'cases').replace(/[^a-zA-Z0-9_-]/g, '_') + '.csv';
        getDownloadUrl({ csvContent: csv, filename: filename })
            .then(url => { window.location.href = url; })
            .catch(err => console.error('Export failed', err));
    }

    _csvCell(val) {
        return '"' + String(val == null ? '' : val).replace(/"/g, '""') + '"';
    }

    handleRowClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId) return;
        window.open('/lightning/r/Case/' + recordId + '/view', '_blank');
    }

    handleClose()          { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdropClick()  { this.handleClose(); }
    stopPropagation(event) { event.stopPropagation(); }
}