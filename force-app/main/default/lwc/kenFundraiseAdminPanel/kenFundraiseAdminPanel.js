import { LightningElement, track } from 'lwc';
import getAdminFundraiseList from '@salesforce/apex/KenFundraiseController.getAdminFundraiseList';
import getDeletionRequests   from '@salesforce/apex/KenFundraiseController.getDeletionRequests';
import approveDeletion       from '@salesforce/apex/KenFundraiseController.approveDeletion';
import rejectDeletion        from '@salesforce/apex/KenFundraiseController.rejectDeletion';

const COLUMNS = [
    { label: 'Campaign Name',     fieldName: 'name',             type: 'text',   sortable: true, initialWidth: 220 },
    { label: 'Category',          fieldName: 'category',         type: 'text',   sortable: true, initialWidth: 160 },
    { label: 'Creator',           fieldName: 'ownerName',        type: 'text',   sortable: true, initialWidth: 160 },
    { label: 'Goal',              fieldName: 'fundraisingGoal',  type: 'number', sortable: true, initialWidth: 120,
      cellAttributes: { alignment: 'left' } },
    { label: 'Currency',          fieldName: 'currencyCode',     type: 'text',   initialWidth: 90 },
    { label: 'Start Date',        fieldName: 'startDate',        type: 'text',   initialWidth: 110 },
    { label: 'End Date',          fieldName: 'endDate',          type: 'text',   initialWidth: 110 },
    { label: 'Campaign Status',   fieldName: 'campaignStatus',   type: 'text',   sortable: true, initialWidth: 130 },
    { label: 'Approval Status',   fieldName: 'approvalStatus',   type: 'text',   sortable: true, initialWidth: 120 },
    { label: 'Collection Method', fieldName: 'collectionMethod', type: 'text',   initialWidth: 140 }
];

const DELETION_COLUMNS = [
    { label: 'Campaign Name',    fieldName: 'name',            type: 'text', sortable: true, initialWidth: 220 },
    { label: 'Category',         fieldName: 'category',        type: 'text', initialWidth: 160 },
    { label: 'Creator',          fieldName: 'ownerName',       type: 'text', sortable: true, initialWidth: 160 },
    { label: 'Goal',             fieldName: 'fundraisingGoal', type: 'number', initialWidth: 120,
      cellAttributes: { alignment: 'left' } },
    { label: 'Campaign Status',  fieldName: 'campaignStatus',  type: 'text', initialWidth: 130 },
    { label: 'Start Date',       fieldName: 'startDate',       type: 'text', initialWidth: 110 },
    { label: 'End Date',         fieldName: 'endDate',         type: 'text', initialWidth: 110 },
    { type: 'action', typeAttributes: { rowActions: [
        { label: 'Approve Deletion', name: 'approve' },
        { label: 'Dismiss Request',  name: 'dismiss' }
    ]}}
];

export default class KenFundraiseAdminPanel extends LightningElement {
    @track allData          = [];
    @track deletionData     = [];
    @track loading          = false;
    @track deletionLoading  = false;

    // Confirm modal state
    @track showConfirmModal = false;
    @track confirmCampaign  = null;  // { id, name }
    @track actionInProgress = false;
    @track actionError      = null;

    columns         = COLUMNS;
    deletionColumns = DELETION_COLUMNS;

    connectedCallback() {
        this.loadAll();
        this.loadDeletionRequests();
    }

    loadAll() {
        this.loading = true;
        getAdminFundraiseList()
            .then(data => { this.allData = data || []; })
            .catch(() => { this.allData = []; })
            .finally(() => { this.loading = false; });
    }

    loadDeletionRequests() {
        this.deletionLoading = true;
        getDeletionRequests()
            .then(data => { this.deletionData = data || []; })
            .catch(() => { this.deletionData = []; })
            .finally(() => { this.deletionLoading = false; });
    }

    // ── Subtab filters ────────────────────────────────────────────────────────

    get inReviewData()  { return this.allData.filter(r => r.approvalStatus === 'In Review'); }
    get approvedData()  { return this.allData.filter(r => r.approvalStatus === 'Approved'); }
    get rejectedData()  { return this.allData.filter(r => r.approvalStatus === 'Rejected'); }

    // ── Tab labels with counts ────────────────────────────────────────────────

    get allLabel()            { return `All (${this.allData.length})`; }
    get inReviewLabel()       { return `In Review (${this.inReviewData.length})`; }
    get approvedLabel()       { return `Approved (${this.approvedData.length})`; }
    get rejectedLabel()       { return `Rejected (${this.rejectedData.length})`; }
    get deletionLabel()       { return `Deletion Requests (${this.deletionData.length})`; }

    // ── Row action handler ────────────────────────────────────────────────────

    handleDeletionRowAction(event) {
        const { action, row } = event.detail;
        if (action.name === 'approve') {
            this.confirmCampaign  = { id: row.id, name: row.name };
            this.actionError      = null;
            this.showConfirmModal = true;
        } else if (action.name === 'dismiss') {
            this.runDismiss(row.id);
        }
    }

    // ── Confirm modal handlers ────────────────────────────────────────────────

    handleCancelConfirm() {
        this.showConfirmModal = false;
        this.confirmCampaign  = null;
        this.actionError      = null;
    }

    handleConfirmApprove() {
        if (!this.confirmCampaign) return;
        this.actionInProgress = true;
        this.actionError      = null;
        approveDeletion({ campaignId: this.confirmCampaign.id })
            .then(() => {
                this.showConfirmModal = false;
                this.confirmCampaign  = null;
                this.loadDeletionRequests();
                this.loadAll();
            })
            .catch(e => {
                this.actionError = e?.body?.message || 'An error occurred.';
            })
            .finally(() => { this.actionInProgress = false; });
    }

    runDismiss(campaignId) {
        rejectDeletion({ campaignId })
            .then(() => {
                this.loadDeletionRequests();
                this.loadAll();
            })
            .catch(e => {
                // eslint-disable-next-line no-console
                console.error('Dismiss failed:', e?.body?.message);
            });
    }

    stopPropagation(event) { event.stopPropagation(); }
}