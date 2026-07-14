import { LightningElement, track } from 'lwc';
import getDeletionRequests from '@salesforce/apex/KenFundraiseController.getDeletionRequests';
import approveDeletion     from '@salesforce/apex/KenFundraiseController.approveDeletion';
import rejectDeletion      from '@salesforce/apex/KenFundraiseController.rejectDeletion';

const COLUMNS = [
    { label: 'Campaign Name',   fieldName: 'name',            type: 'text', sortable: true, initialWidth: 220 },
    { label: 'Category',        fieldName: 'category',        type: 'text', initialWidth: 160 },
    { label: 'Creator',         fieldName: 'ownerName',       type: 'text', sortable: true, initialWidth: 160 },
    { label: 'Goal',            fieldName: 'fundraisingGoal', type: 'number', initialWidth: 120,
      cellAttributes: { alignment: 'left' } },
    { label: 'Campaign Status', fieldName: 'campaignStatus',  type: 'text', initialWidth: 130 },
    { label: 'Start Date',      fieldName: 'startDate',       type: 'text', initialWidth: 110 },
    { label: 'End Date',        fieldName: 'endDate',         type: 'text', initialWidth: 110 },
    { type: 'action', typeAttributes: { rowActions: [
        { label: 'Approve Deletion', name: 'approve' },
        { label: 'Dismiss Request',  name: 'dismiss' }
    ]}}
];

export default class KenFundraiseDeletionPanel extends LightningElement {
    @track data            = [];
    @track loading         = false;
    @track showConfirm     = false;
    @track confirmRow      = null;
    @track actionInProgress = false;
    @track actionError     = null;

    columns = COLUMNS;

    connectedCallback() { this.load(); }

    load() {
        this.loading = true;
        getDeletionRequests()
            .then(d => { this.data = d || []; })
            .catch(() => { this.data = []; })
            .finally(() => { this.loading = false; });
    }

    handleRowAction(event) {
        const { action, row } = event.detail;
        if (action.name === 'approve') {
            this.confirmRow   = { id: row.id, name: row.name };
            this.actionError  = null;
            this.showConfirm  = true;
        } else if (action.name === 'dismiss') {
            rejectDeletion({ campaignId: row.id })
                .then(() => this.load())
                .catch(e => console.error(e?.body?.message));
        }
    }

    handleCancel() {
        this.showConfirm = false;
        this.confirmRow  = null;
        this.actionError = null;
    }

    handleConfirm() {
        this.actionInProgress = true;
        this.actionError      = null;
        approveDeletion({ campaignId: this.confirmRow.id })
            .then(() => { this.showConfirm = false; this.confirmRow = null; this.load(); })
            .catch(e => { this.actionError = e?.body?.message || 'An error occurred.'; })
            .finally(() => { this.actionInProgress = false; });
    }

    stopProp(event) { event.stopPropagation(); }
}