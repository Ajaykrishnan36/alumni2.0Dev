import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';

import getFundraiseStatus from '@salesforce/apex/KenFundraiseController.getFundraiseStatus';
import approveCampaign   from '@salesforce/apex/KenFundraiseController.approveCampaign';
import rejectCampaign    from '@salesforce/apex/KenFundraiseController.rejectCampaign';
import approveDeletion   from '@salesforce/apex/KenFundraiseController.approveDeletion';
import rejectDeletion    from '@salesforce/apex/KenFundraiseController.rejectDeletion';

export default class KenFundraiseRecordActions extends NavigationMixin(LightningElement) {
    @api recordId;
    @track showRejectModal        = false;
    @track showApproveDeleteModal = false;
    @track rejectReason           = '';
    @track isLoading              = false;

    _wiredResult;

    @wire(getFundraiseStatus, { campaignId: '$recordId' })
    wiredStatus(result) {
        this._wiredResult = result;
    }

    get _data()          { return this._wiredResult?.data; }
    get approvalStatus() { return this._data?.approvalStatus || null; }
    get campaignName()   { return this._data?.name || ''; }

    get isInReview()          { return this.approvalStatus === 'In Review'; }
    get isDeletionRequested() { return this.approvalStatus === 'Deletion Requested'; }
    get isApproved()          { return this.approvalStatus === 'Approved'; }
    get isRejected()          { return this.approvalStatus === 'Rejected'; }
    get hasNoStatus() {
        if (!this._data) return false;
        return !this.isInReview && !this.isDeletionRequested && !this.isApproved && !this.isRejected;
    }

    async handleApprove() {
        this.isLoading = true;
        try {
            await approveCampaign({ campaignId: this.recordId });
            this._toast('Campaign Approved', 'The campaign has been approved and is now live.', 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast('Error', e.body?.message || 'Failed to approve.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    openRejectModal()       { this.rejectReason = ''; this.showRejectModal = true; }
    closeRejectModal()      { this.showRejectModal = false; }
    handleReasonChange(e)   { this.rejectReason = e.target.value; }

    async confirmReject() {
        this.isLoading = true;
        try {
            await rejectCampaign({ campaignId: this.recordId, reason: this.rejectReason });
            this.showRejectModal = false;
            this._toast('Campaign Rejected', 'The campaign has been rejected.', 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast('Error', e.body?.message || 'Failed to reject.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    openApproveDeleteModal()  { this.showApproveDeleteModal = true; }
    closeApproveDeleteModal() { this.showApproveDeleteModal = false; }

    async confirmApproveDeletion() {
        this.isLoading = true;
        try {
            await approveDeletion({ campaignId: this.recordId });
            this.showApproveDeleteModal = false;
            this._toast('Deleted', 'Campaign has been permanently deleted.', 'success');
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Ken_Fundraise__c', actionName: 'list' },
                state: { filterName: 'Deletion_All' }
            });
        } catch (e) {
            this._toast('Error', e.body?.message || 'Failed to delete.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleDismissDeletion() {
        this.isLoading = true;
        try {
            await rejectDeletion({ campaignId: this.recordId });
            this._toast('Request Dismissed', 'Campaign restored to Approved.', 'success');
            await refreshApex(this._wiredResult);
        } catch (e) {
            this._toast('Error', e.body?.message || 'Failed to dismiss.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}