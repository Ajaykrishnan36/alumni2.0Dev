import { LightningElement, api, track } from 'lwc';
import getDownloadUrl from '@salesforce/apex/KenExportCsvController.getDownloadUrl';

const PAGE_SIZE = 20;

export default class KenMentorshipListModal extends LightningElement {

    @api show      = false;
    @api title     = '';
    @api isLoading = false;

    @track _records    = [];
    @track searchTerm  = '';
    @track currentPage = 1;

    @api
    get records() { return this._records; }
    set records(val) {
        this._records   = val || [];
        this.currentPage = 1;
        this.searchTerm  = '';
    }

    // ── Filtering ─────────────────────────────────────────────────────────────
    get filtered() {
        if (!this.searchTerm) return this._records;
        const q = this.searchTerm.toLowerCase();
        return this._records.filter(r =>
            (r.name        || '').toLowerCase().includes(q) ||
            (r.mentorDisp  || '').toLowerCase().includes(q) ||
            (r.menteeDisp  || '').toLowerCase().includes(q) ||
            (r.titleDisp   || '').toLowerCase().includes(q) ||
            (r.status      || '').toLowerCase().includes(q) ||
            (r.rtLabel     || '').toLowerCase().includes(q)
        );
    }

    get filteredRecords() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filtered.slice(start, start + PAGE_SIZE);
    }

    get hasRecords()  { return this.filtered.length > 0; }
    get totalPages()  { return Math.max(1, Math.ceil(this.filtered.length / PAGE_SIZE)); }
    get isFirstPage() { return this.currentPage <= 1; }
    get isLastPage()  { return this.currentPage >= this.totalPages; }

    // ── Handlers ──────────────────────────────────────────────────────────────
    handleSearch(event) {
        this.searchTerm  = event.target.value;
        this.currentPage = 1;
    }

    handlePrev() { if (!this.isFirstPage) this.currentPage--; }
    handleNext() { if (!this.isLastPage)  this.currentPage++; }

    handleClose()         { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdropClick() { this.handleClose(); }
    stopProp(event)       { event.stopPropagation(); }

    handleRowClick(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId || recordId === 'null') return;
        window.open('/lightning/r/Ken_Mentorship__c/' + recordId + '/view', '_blank');
    }

    handlePersonClick(event) {
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId || recordId === 'null') return;
        window.open('/lightning/r/Account/' + recordId + '/view', '_blank');
    }

    handleExport() {
        const rows  = this.filtered;
        const header = ['Record #','Type','Mentor','Mentee','Status','Mode','Meet Date','Meeting Title'];
        const lines  = rows.map(r => [
            r.name, r.rtLabel, r.mentorDisp, r.menteeDisp,
            r.status, r.meetingMode || '', r.meetDateDisp, r.titleDisp
        ].map(v => '"' + (v || '').replace(/"/g, '""') + '"').join(','));
        const csv = [header.join(','), ...lines].join('\n');
        getDownloadUrl({ csvContent: csv, filename: 'mentorship_records.csv' })
            .then(url => { window.location.href = url; })
            .catch(err => console.error('Export failed', err));
    }
}