import { LightningElement, api, track } from 'lwc';
import getDownloadUrl from '@salesforce/apex/KenExportCsvController.getDownloadUrl';

const PAGE_SIZE = 20;

const STATUS_CLASS_MAP = {
    'Requested':  'status-badge status-pending',
    'Accepted':   'status-badge status-approved',
    'Rejected':   'status-badge status-rejected',
    'Cancelled':  'status-badge status-cancelled',
    'Blocked':    'status-badge status-blocked'
};

export default class KenNetworkListModal extends LightningElement {

    @api isOpen    = false;
    @api title     = 'Connection List';
    @api isLoading = false;

    @track searchTerm  = '';
    @track currentPage = 1;

    _connectionList = [];
    @api
    get connectionList() { return this._connectionList; }
    set connectionList(val) {
        this._connectionList = val || [];
        this.currentPage = 1;
        this.searchTerm  = '';
    }

    // ── Filtered list ──────────────────────────────────────────────────────────

    get filteredList() {
        const term = (this.searchTerm || '').toLowerCase().trim();
        const list = this._connectionList;
        if (!term) return list;
        return list.filter(r =>
            (r.connectionName  || '').toLowerCase().includes(term) ||
            (r.initiatorName   || '').toLowerCase().includes(term) ||
            (r.recipientName   || '').toLowerCase().includes(term) ||
            (r.status          || '').toLowerCase().includes(term) ||
            (r.requestedDate   || '').toLowerCase().includes(term)
        );
    }

    get recordCount()  { return this.filteredList.length; }
    get totalPages()   { return Math.max(1, Math.ceil(this.recordCount / PAGE_SIZE)); }
    get isFirstPage()  { return this.currentPage <= 1; }
    get isLastPage()   { return this.currentPage >= this.totalPages; }
    get pageInfo()     { return `Page ${this.currentPage} of ${this.totalPages}`; }

    get paginatedList() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredList.slice(start, start + PAGE_SIZE).map(r => ({
            ...r,
            statusClass: STATUS_CLASS_MAP[r.status] || 'status-badge',
            tatDisplay:  r.tatDays != null ? r.tatDays + 'd' : '—'
        }));
    }

    get hasRows() { return this.paginatedList.length > 0; }

    // ── Event handlers ─────────────────────────────────────────────────────────

    handleSearch(event) {
        this.searchTerm  = event.target.value;
        this.currentPage = 1;
    }

    prevPage() { if (!this.isFirstPage) this.currentPage--; }
    nextPage() { if (!this.isLastPage)  this.currentPage++; }

    handleRowClick(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId) return;
        window.open('/lightning/r/Ken_Network_Connection__c/' + recordId + '/view', '_blank');
    }

    handlePersonClick(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId) return;
        window.open('/lightning/r/Account/' + recordId + '/view', '_blank');
    }

    handleExportCsv() {
        const list = this.filteredList;
        if (!list.length) return;
        const headers = ['Connection #', 'Initiator', 'Recipient', 'Status', 'Requested Date', 'Accepted Date', 'TAT (Days)'];
        const rows = list.map(r => [
            this._csv(r.connectionName),
            this._csv(r.initiatorName),
            this._csv(r.recipientName),
            this._csv(r.status),
            this._csv(r.requestedDate),
            this._csv(r.acceptedDate),
            this._csv(r.tatDays != null ? r.tatDays : '')
        ]);
        const csv      = [headers.map(h => `"${h}"`), ...rows].map(row => row.join(',')).join('\n');
        const filename = (this.title || 'connections').replace(/[^a-zA-Z0-9_-]/g, '_') + '.csv';
        getDownloadUrl({ csvContent: csv, filename: filename })
            .then(url => { window.location.href = url; })
            .catch(err => console.error('Export failed', err));
    }

    _csv(val) {
        return '"' + String(val == null ? '' : val).replace(/"/g, '""') + '"';
    }

    handleClose()          { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdropClick()  { this.handleClose(); }
    stopPropagation(event) { event.stopPropagation(); }
}