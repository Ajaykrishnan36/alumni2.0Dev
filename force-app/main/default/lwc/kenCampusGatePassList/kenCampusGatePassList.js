import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getGatePassCases from '@salesforce/apex/KenGatePassController.getGatePassCases';
import getServiceIdByCategory from '@salesforce/apex/KenServiceSupportController.getServiceIdByCategory';
import closeCase from '@salesforce/apex/KenServiceSupportController.closeCase';

const FILTERS = [
    { key: 'all',      label: 'All' },
    { key: 'active',   label: 'Active' },
    { key: 'new',      label: 'New' },
    { key: 'canceled', label: 'Canceled' }
];

// Matches KenSnSConstants.SERVICE_CATEGORY_GATE_PASS
const GATE_PASS_SERVICE_CATEGORY  = 'Gate_Pass';
const SERVICE_REQUEST_DETAIL_PATH = '/service-support/request-service?serviceId=';
// Ticket detail page in S&S portal
const TICKET_DETAIL_PATH          = '/service-support/ticket-detail?caseId=';

const DEFAULT_PRIMARY = '#3061FF';

export default class KenCampusGatePassList extends NavigationMixin(LightningElement) {
    @track _allCases = [];
    @track cases = [];
    @track isLoading = true;
    @track selectedPass = null;
    @track showPassModal = false;
    @track isCanceling = false;
    @track activeFilter = 'all';
    pendingPrimary = DEFAULT_PRIMARY;

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const f = ref?.state?.filter;
        if (f && f !== this.activeFilter) {
            this.activeFilter = f;
            this._applyFilter();
        }
    }

    get filterTabs() {
        return FILTERS.map(f => ({
            ...f,
            isActive: f.key === this.activeFilter,
            tabClass: 'gpl-tab' + (f.key === this.activeFilter ? ' gpl-tab--active' : '')
        }));
    }

    handleFilterClick(event) {
        this.activeFilter = event.currentTarget.dataset.filter;
        this._applyFilter();
    }

    _applyFilter() {
        const f = this.activeFilter;
        if (!f || f === 'all') {
            this.cases = [...this._allCases];
            return;
        }
        // Filter by Case Status
        const statusMap = {
            active:   'Resolved',
            new:      'New',
            canceled: 'Canceled'
        };
        const targetStatus = statusMap[f];
        this.cases = targetStatus
            ? this._allCases.filter(r => r.status === targetStatus)
            : [...this._allCases];
    }

    connectedCallback() {
        this.loadCases();
    }

    renderedCallback() {
        if (this.pendingPrimary) {
            this.applyTheme(this.pendingPrimary);
        }
    }

    applyTheme(primary, secondary) {
        const resolved = primary || DEFAULT_PRIMARY;
        this.pendingPrimary = resolved;
        const host = this.template?.host?.style;
        if (!host) return;
        host.setProperty('--primary-color', resolved);
        host.setProperty('--brand-primary', resolved);
        if (secondary) {
            host.setProperty('--secondary-color', secondary);
            host.setProperty('--brand-secondary', secondary);
        }
        this.pendingPrimary = null;
    }

    loadCases() {
        this.isLoading = true;
        getGatePassCases()
            .then(rows => {
                const mapped = rows.map(r => {
                    const isResolved = r.status === 'Resolved';
                    const isClosed   = r.status === 'Closed';
                    const isTerminal = isClosed || r.status === 'Canceled' || r.status === 'Rejected';
                    let tsPrefix, tsDate;
                    if (isResolved && r.approvedDate) {
                        tsPrefix = 'Approved on: ';
                        tsDate   = this._formatDtShort(r.approvedDate);
                    } else if (isTerminal && r.closedDate) {
                        tsPrefix = this._statusVerb(r.status) + ': ';
                        tsDate   = this._formatDtShort(r.closedDate);
                    } else {
                        tsPrefix = 'Submitted on: ';
                        tsDate   = this._formatDtShort(r.createdDate);
                    }
                    return {
                        hasAttachments: Array.isArray(r.attachmentNames) && r.attachmentNames.length > 0,
                        ...r,
                        statusClass: this._statusClass(r.status),
                        statusLabel: this._statusLabel(r.status),
                        exitTimeFormatted:  this._formatDt(r.exitTime),
                        entryTimeFormatted: this._formatDt(r.entryTime),
                        tsPrefix,
                        tsDate,
                        qrUrl: r.qrCode ? 'https://api.qrserver.com/v1/create-qr-code/?data='
                                         + encodeURIComponent(r.qrCode) + '&size=200x200&ecc=M' : null
                    };
                });
                this._allCases = mapped;
                this._applyFilter();
            })
            .catch(() => {
                this._allCases = [];
                this.cases = [];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCreateGatePass() {
        getServiceIdByCategory({ category: GATE_PASS_SERVICE_CATEGORY })
            .then(serviceId => {
                if (serviceId) {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__webPage',
                        attributes: { url: SERVICE_REQUEST_DETAIL_PATH + serviceId }
                    });
                }
            })
            .catch(() => {});
    }

    handleViewCase(event) {
        const caseId = event.currentTarget.dataset.caseId;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: TICKET_DETAIL_PATH + caseId }
        });
    }

    handleViewPass(event) {
        event.stopPropagation();
        const caseId = event.currentTarget.dataset.caseId;
        const row = this.cases.find(r => r.caseId === caseId);
        if (row) {
            this.selectedPass = row;
            this.showPassModal = true;
        }
    }

    handleCloseModal() {
        this.showPassModal = false;
        this.selectedPass = null;
    }

    stopProp(event) {
        event.stopPropagation();
    }

    handleQrDownload(event) {
        event.stopPropagation();
        if (this.selectedPass?.qrUrl) {
            window.open(this.selectedPass.qrUrl + '&download=1', '_blank');
        }
    }

    handleCancelRequest(event) {
        event.stopPropagation();
        const caseId = event.currentTarget.dataset.caseId;
        if (!caseId) return;
        this.isCanceling = true;
        closeCase({ caseId })
            .then(() => {
                this.loadCases();
            })
            .catch(() => {})
            .finally(() => { this.isCanceling = false; });
    }

    get hasCases() {
        return Array.isArray(this.cases) && this.cases.length > 0;
    }

    get hasCasesEmpty() {
        return !this.hasCases;
    }

    get emptyMessage() {
        const labels = { active: 'active (Resolved)', new: 'new', canceled: 'canceled' };
        const f = this.activeFilter;
        return f && f !== 'all'
            ? `No ${labels[f] || f} gate passes found.`
            : 'No gate pass requests found.';
    }

    get modalQrUrl() {
        return this.selectedPass?.qrUrl || null;
    }

    get modalPassName() {
        return this.selectedPass?.gatePassName || '';
    }

    get modalExitTime() {
        return this.selectedPass?.exitTimeFormatted || '—';
    }

    get modalEntryTime() {
        return this.selectedPass?.entryTimeFormatted || '—';
    }

    get modalIsActive() {
        return this.selectedPass?.isActive;
    }

    get modalIsExpired() {
        return this.selectedPass?.isExpired;
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    _formatDtShort(value) {
        if (!value) return '—';
        try {
            const d = new Date(value);
            const day   = String(d.getDate()).padStart(2, '0');
            const month = d.toLocaleString('en-US', { month: 'short' });
            const year  = d.getFullYear();
            return `${day} ${month} ${year}`;
        } catch (e) {
            return String(value);
        }
    }

    _formatDt(value) {
        if (!value) return '—';
        try {
            const d = new Date(value);
            const day   = String(d.getDate()).padStart(2, '0');
            const month = d.toLocaleString('en-US', { month: 'short' });
            const year  = d.getFullYear();
            const h     = String(d.getHours()).padStart(2, '0');
            const m     = String(d.getMinutes()).padStart(2, '0');
            return `${day} ${month} ${year}, ${h}:${m}`;
        } catch (e) {
            return String(value);
        }
    }

    _statusLabel(status) {
        if (!status) return 'New';
        const s = status.toLowerCase();
        if (s === 'resolved') return 'Active';
        if (s === 'new')      return 'New';
        if (s.includes('progress')) return 'In Progress';
        if (s.includes('review'))   return 'In Review';
        if (s.includes('hold'))     return 'On Hold';
        if (s.includes('waiting'))  return 'Waiting';
        if (s === 'closed')   return 'Closed';
        if (s === 'canceled') return 'Canceled';
        if (s === 'rejected') return 'Rejected';
        return status;
    }

    _statusClass(status) {
        if (!status) return 'gpl-badge-new';
        const s = status.toLowerCase();
        if (s === 'resolved') return 'gpl-badge-active';
        if (s === 'new')      return 'gpl-badge-new';
        if (s.includes('progress') || s.includes('review') || s.includes('hold') || s.includes('waiting')) {
            return 'gpl-badge-inreview';
        }
        if (s === 'closed')   return 'gpl-badge-closed';
        if (s === 'canceled') return 'gpl-badge-canceled';
        if (s === 'rejected') return 'gpl-badge-rejected';
        return 'gpl-badge-new';
    }

    _statusVerb(status) {
        if (!status) return 'Updated';
        const s = status.toLowerCase();
        if (s === 'rejected') return 'Rejected on';
        if (s === 'canceled') return 'Canceled on';
        if (s === 'closed')   return 'Closed on';
        return 'Updated on';
    }
}