import { LightningElement, api, track } from 'lwc';
import getDownloadUrl from '@salesforce/apex/KenExportCsvController.getDownloadUrl';

const PAGE_SIZE = 20;

const STATUS_CLASS_MAP = {
    'Approved':         'status-badge status-approved',
    'In Progress':      'status-badge status-progress',
    'In review':        'status-badge status-review',
    'Pending Approval': 'status-badge status-pending',
    'Submitted':        'status-badge status-submitted',
    'Rejected':         'status-badge status-rejected',
    'Cancelled':        'status-badge status-cancelled',
    'Registered':       'status-badge status-approved',
    'Waitlisted':       'status-badge status-pending',
};

export default class KenEventsListModal extends LightningElement {
    @api isOpen    = false;
    @api title     = 'Event List';
    @api isLoading = false;
    @api modalMode = 'events'; // 'events' | 'bookings'

    @track searchTerm   = '';
    @track currentPage  = 1;

    _eventList = [];
    @api
    get eventList() { return this._eventList; }
    set eventList(val) {
        this._eventList  = val || [];
        this.currentPage = 1;
        this.searchTerm  = '';
    }

    _bookingList = [];
    @api
    get bookingList() { return this._bookingList; }
    set bookingList(val) {
        this._bookingList = val || [];
        this.currentPage  = 1;
        this.searchTerm   = '';
    }

    get isBookingMode() { return this.modalMode === 'bookings'; }

    get _activeList() {
        return this.isBookingMode ? this._bookingList : this._eventList;
    }

    get filteredList() {
        const term = (this.searchTerm || '').toLowerCase().trim();
        if (!term) return this._activeList;
        if (this.isBookingMode) {
            return this._activeList.filter(r =>
                (r.attendeeName  || '').toLowerCase().includes(term) ||
                (r.eventName     || '').toLowerCase().includes(term) ||
                (r.bookingStatus || '').toLowerCase().includes(term)
            );
        }
        return this._activeList.filter(r =>
            (r.name      || '').toLowerCase().includes(term) ||
            (r.eventType || '').toLowerCase().includes(term) ||
            (r.location  || '').toLowerCase().includes(term) ||
            (r.status    || '').toLowerCase().includes(term)
        );
    }

    get filteredCount() { return this.filteredList.length; }
    get recordLabel()   { return this.isBookingMode ? 'bookings' : 'events'; }
    get totalPages()    { return Math.max(1, Math.ceil(this.filteredCount / PAGE_SIZE)); }
    get isFirstPage()   { return this.currentPage <= 1; }
    get isLastPage()    { return this.currentPage >= this.totalPages; }
    get pageInfo()      { return `Page ${this.currentPage} of ${this.totalPages}`; }

    get pageRows() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredList.slice(start, start + PAGE_SIZE).map(r => ({
            ...r,
            statusClass: STATUS_CLASS_MAP[this.isBookingMode ? r.bookingStatus : r.status] || 'status-badge'
        }));
    }

    get hasRows() { return this.pageRows.length > 0; }

    get loadingText() { return this.isBookingMode ? 'Loading bookings...' : 'Loading events...'; }
    get emptyText()   { return this.isBookingMode ? 'No bookings found' : 'No events found'; }
    get searchPlaceholder() {
        return this.isBookingMode
            ? 'Search by attendee, event or status...'
            : 'Search by name, type, location or status...';
    }

    handleSearch(event) {
        this.searchTerm  = event.target.value;
        this.currentPage = 1;
    }

    prevPage() { if (!this.isFirstPage) this.currentPage--; }
    nextPage() { if (!this.isLastPage)  this.currentPage++; }

    handleExportCsv() {
        const list = this.filteredList;
        if (!list.length) return;
        let headers, rows;
        if (this.isBookingMode) {
            headers = ['Attendee Name', 'Event', 'Status', 'Date', 'Attendees'];
            rows = list.map(r => [
                this._csvCell(r.attendeeName),
                this._csvCell(r.eventName),
                this._csvCell(r.bookingStatus),
                this._csvCell(r.bookedDate),
                this._csvCell(r.attendeeCount)
            ]);
        } else {
            headers = ['Event Name', 'Type', 'Status', 'Start Date', 'Location', 'Registrations'];
            rows = list.map(r => [
                this._csvCell(r.name),
                this._csvCell(r.eventType),
                this._csvCell(r.status),
                this._csvCell(r.startDate),
                this._csvCell(r.location),
                this._csvCell(r.registrations)
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

    handleRowClick(event) {
        const recordId  = event.currentTarget.dataset.recordId;
        const objectApi = event.currentTarget.dataset.objectApi;
        if (!recordId || !objectApi) return;
        window.open('/lightning/r/' + objectApi + '/' + recordId + '/view', '_blank');
    }

    handleClose()          { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdropClick()  { this.handleClose(); }
    stopPropagation(event) { event.stopPropagation(); }
}