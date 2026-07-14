import { LightningElement, api, track } from 'lwc';
import getDownloadUrl from '@salesforce/apex/KenExportCsvController.getDownloadUrl';

const PAGE_SIZE = 20;

export default class KenAlumniListModal extends LightningElement {
    @api isOpen = false;
    @api title = 'Alumni List';
    @api isLoading = false;

    @track searchTerm = '';
    @track currentPage = 1;

    _alumniList = [];
    @api
    get alumniList() { return this._alumniList; }
    set alumniList(val) {
        this._alumniList = val || [];
        this.currentPage = 1;
        this.searchTerm = '';
    }

    get filteredList() {
        const term = (this.searchTerm || '').toLowerCase().trim();
        if (!term) return this._alumniList;
        return this._alumniList.filter(r =>
            (r.name || '').toLowerCase().includes(term) ||
            (r.email || '').toLowerCase().includes(term) ||
            (r.batch || '').toLowerCase().includes(term)
        );
    }

    get filteredCount() { return this.filteredList.length; }

    get totalPages() { return Math.max(1, Math.ceil(this.filteredCount / PAGE_SIZE)); }

    get pageRows() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredList.slice(start, start + PAGE_SIZE).map(r => ({
            ...r,
            statusClass: r.status === 'Active' ? 'status-badge active' : 'status-badge'
        }));
    }

    get hasRows() { return this.pageRows.length > 0; }
    get isFirstPage() { return this.currentPage <= 1; }
    get isLastPage() { return this.currentPage >= this.totalPages; }
    get pageInfo() { return `Page ${this.currentPage} of ${this.totalPages}`; }

    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.currentPage = 1;
    }

    prevPage() { if (!this.isFirstPage) this.currentPage--; }
    nextPage() { if (!this.isLastPage) this.currentPage++; }

    handleExportCsv() {
        const headers = ['Name', 'Email', 'Phone', 'Batch / Program', 'Grad Year', 'Status'];
        const rows = this.filteredList.map(a => [
            this._csvCell(a.name),
            this._csvCell(a.email),
            this._csvCell(a.phone),
            this._csvCell(a.batch),
            this._csvCell(a.graduationYear),
            this._csvCell(a.status)
        ]);
        const csv      = [headers.map(h => `"${h}"`), ...rows].map(r => r.join(',')).join('\n');
        const filename = (this.title || 'alumni').replace(/[^a-zA-Z0-9_-]/g, '_') + '.csv';
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
        window.open('/lightning/r/Account/' + recordId + '/view', '_blank');
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdropClick() {
        this.handleClose();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }
}