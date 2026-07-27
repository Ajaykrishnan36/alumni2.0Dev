import { LightningElement, track } from 'lwc';
import getAdminBusinessList from '@salesforce/apex/KenBusinessController.getAdminBusinessList';
import getAdminFeatureList from '@salesforce/apex/KenBusinessController.getAdminFeatureList';

const BIZ_COLUMNS = [
    { label: 'Business Name', fieldName: 'name', type: 'text', sortable: true, initialWidth: 200 },
    { label: 'Category', fieldName: 'category', type: 'text', sortable: true, initialWidth: 140 },
    { label: 'Owner', fieldName: 'ownerName', type: 'text', sortable: true, initialWidth: 160 },
    { label: 'Address', fieldName: 'location', type: 'text', initialWidth: 200 },
    { label: 'Approval', fieldName: 'approvalStatus', type: 'text', sortable: true, initialWidth: 110 },
    { label: 'Status', fieldName: 'status', type: 'text', initialWidth: 120 },
    { label: 'Phone', fieldName: 'phone', type: 'text', initialWidth: 140 },
    { label: 'Email', fieldName: 'email', type: 'text', initialWidth: 180 },
    { label: 'Rejection Reason', fieldName: 'rejectionReason', type: 'text', wrapText: true }
];

const FEAT_COLUMNS = [
    { label: 'Business Name', fieldName: 'name', type: 'text', sortable: true, initialWidth: 200 },
    { label: 'Category', fieldName: 'category', type: 'text', initialWidth: 140 },
    { label: 'Owner', fieldName: 'ownerName', type: 'text', sortable: true, initialWidth: 160 },
    { label: 'Feature Status', fieldName: 'featureStatus', type: 'text', sortable: true, initialWidth: 150 },
    { label: 'Subject', fieldName: 'featureSubject', type: 'text', wrapText: true, initialWidth: 200 },
    { label: 'Message', fieldName: 'featureMessage', type: 'text', wrapText: true },
    { label: 'Is Featured', fieldName: 'isCurrentlyFeatured', type: 'boolean', initialWidth: 100 },
    { label: 'Rejection Reason', fieldName: 'featureRejectionReason', type: 'text', wrapText: true, initialWidth: 200 }
];

export default class KenBusinessAdminPanel extends LightningElement {
    @track bizAllData = [];
    @track featAllData = [];
    @track bizLoading = false;
    @track featLoading = false;

    bizColumns = BIZ_COLUMNS;
    featColumns = FEAT_COLUMNS;

    connectedCallback() {
        this.bizLoading = true;
        this.featLoading = true;
        getAdminBusinessList()
            .then(data => { this.bizAllData = data || []; })
            .catch(() => { this.bizAllData = []; })
            .finally(() => { this.bizLoading = false; });
        getAdminFeatureList()
            .then(data => { this.featAllData = data || []; })
            .catch(() => { this.featAllData = []; })
            .finally(() => { this.featLoading = false; });
    }

    // Business subtab filters
    get bizPending()  { return this.bizAllData.filter(b => b.approvalStatus === 'Pending'); }
    get bizApproved() { return this.bizAllData.filter(b => b.approvalStatus === 'Approved'); }
    get bizRejected() { return this.bizAllData.filter(b => b.approvalStatus === 'Rejected'); }

    // Feature subtab filters
    get featPending()  { return this.featAllData.filter(f => f.featureStatus === 'Pending Approval'); }
    get featApproved() { return this.featAllData.filter(f => f.featureStatus === 'Approved'); }
    get featRejected() { return this.featAllData.filter(f => f.featureStatus === 'Rejected'); }

    // Tab labels with counts
    get bizAllLabel()      { return `All (${this.bizAllData.length})`; }
    get bizPendingLabel()  { return `Pending (${this.bizPending.length})`; }
    get bizApprovedLabel() { return `Approved (${this.bizApproved.length})`; }
    get bizRejectedLabel() { return `Rejected (${this.bizRejected.length})`; }

    get featAllLabel()      { return `All (${this.featAllData.length})`; }
    get featPendingLabel()  { return `Pending (${this.featPending.length})`; }
    get featApprovedLabel() { return `Approved (${this.featApproved.length})`; }
    get featRejectedLabel() { return `Rejected (${this.featRejected.length})`; }
}