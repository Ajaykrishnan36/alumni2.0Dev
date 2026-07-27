import { LightningElement, api, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getCampaignById from '@salesforce/apex/KenFundraiseController.getCampaignById';
import deleteCampaign  from '@salesforce/apex/KenFundraiseController.deleteCampaign';
import closeCampaign   from '@salesforce/apex/KenFundraiseController.closeCampaign';
import approveCampaign from '@salesforce/apex/KenFundraiseController.approveCampaign';
import rejectCampaign  from '@salesforce/apex/KenFundraiseController.rejectCampaign';
import approveDeletion from '@salesforce/apex/KenFundraiseController.approveDeletion';
import rejectDeletion  from '@salesforce/apex/KenFundraiseController.rejectDeletion';

const DEFAULT_BACK_PAGE  = 'all_campaigns__c';
const CURRENCY_SYMBOLS   = { INR: '₹', USD: '$', EUR: '€', GBP: '£' };
const MS_PER_HOUR        = 3_600_000;
const MS_PER_MIN         = 60_000;

export default class KenFundraiseViewPage extends NavigationMixin(LightningElement) {
    @api campaign;
    @track _campaignId;
    @track _showDeleteModal             = false;
    @track _showDeleteSuccessPopup      = false;
    @track _countdown                   = null;
    @track _deleteError                 = null;
    @track _isDeleting                  = false;
    @track _showAdminRejectModal        = false;
    @track _adminRejectReason           = '';
    @track _showAdminApproveDeleteModal = false;
    @track _adminActionLoading          = false;
    @track _adminActionError            = null;
    @track _showCloseModal              = false;
    @track _closeError                  = null;
    @track _isClosing                   = false;
    backPageName = DEFAULT_BACK_PAGE;
    _countdownTimer      = null;
    _successPopupTimer   = null;
    _wiredCampaignResult = null;

    @wire(CurrentPageReference)
    parseState(ref) {
        if (!ref?.state) return;
        const campaignId = ref.state.recordId || ref.state.c__campaignId;
        if (campaignId) {
            this._campaignId = campaignId;
        }
    }

    @wire(getCampaignById, { campaignId: '$_campaignId' })
    wiredCampaign(result) {
        this._wiredCampaignResult = result;
        if (result.data) {
            this.campaign = this._mapDto(result.data);
            this._scheduleCountdown();
        }
    }

    _mapDto(raw) {
        const symbol = CURRENCY_SYMBOLS[raw.currencyCode] || '₹';
        const goal = raw.fundraisingGoal
            ? symbol + Number(raw.fundraisingGoal).toLocaleString('en-IN')
            : '';
        let primaryStatus;
        if (raw.approvalStatus === 'Approved') {
            if (raw.campaignStatus === 'Completed') {
                primaryStatus = 'Completed';
            } else {
                const today = new Date();
                today.setHours(0, 0, 0, 0);
                const start = raw.startDate ? new Date(raw.startDate) : null;
                const end   = raw.endDate   ? new Date(raw.endDate)   : null;
                if (end && end < today) {
                    primaryStatus = 'Completed';
                } else if (start && start <= today) {
                    primaryStatus = 'Ongoing';
                } else {
                    primaryStatus = 'Upcoming';
                }
            }
        } else {
            primaryStatus = raw.approvalStatus || '';
        }
        return {
            id:              raw.id,
            title:           raw.name,
            category:        raw.category || '',
            description:     raw.description || '',
            campaignStatus:  primaryStatus,
            approvalStatus:  raw.approvalStatus || '',
            goal,
            image:           raw.coverImage || '',
            dateRange:       this._formatDateRange(raw.startDate, raw.endDate) || '',
            owner:           raw.ownerName ? { name: raw.ownerName, avatar: raw.ownerPhotoUrl || '' } : null,
            externalLink:    raw.externalLink || '',
            rejectionReason: raw.rejectionReason || '',
            isOwner:         !!raw.isOwner,
            isAdmin:         !!raw.isAdmin,
            rawStartDate:    raw.startDate || null
        };
    }

    _formatDateRange(start, end) {
        if (!start && !end) return null;
        const fmt = (s) => {
            if (!s) return '';
            const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            const parts = s.split('-').map(Number);
            if (parts.length < 3) return s;
            return `${parts[2]} ${months[parts[1] - 1]} ${parts[0]}`;
        };
        if (start && end) return `${fmt(start)} – ${fmt(end)}`;
        if (start) return `From ${fmt(start)}`;
        return `Until ${fmt(end)}`;
    }

    connectedCallback() {
        getPrimaryColor()
            .then((color) => {
                if (color?.primaryColor)   document.documentElement.style.setProperty('--primary-color',   color.primaryColor);
                if (color?.secondaryColor) document.documentElement.style.setProperty('--secondary-color', color.secondaryColor);
                if (color?.tertiaryColor)  document.documentElement.style.setProperty('--tertiary-color',  color.tertiaryColor);
            })
            .catch(() => {});
    }

    disconnectedCallback() {
        if (this._countdownTimer)    clearInterval(this._countdownTimer);
        if (this._successPopupTimer) clearTimeout(this._successPopupTimer);
    }

    // ── Countdown logic ──────────────────────────────────────────────────────

    _scheduleCountdown() {
        if (this._countdownTimer) clearInterval(this._countdownTimer);
        if (!this._isUpcomingSoon()) return;
        const tick = () => {
            const startMs = this._startMs();
            const diff = startMs - Date.now();
            if (diff <= 0) {
                this._countdown = null;
                clearInterval(this._countdownTimer);
                return;
            }
            const h = Math.floor(diff / MS_PER_HOUR);
            const m = Math.floor((diff % MS_PER_HOUR) / MS_PER_MIN);
            this._countdown = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
        };
        tick();
        this._countdownTimer = setInterval(tick, MS_PER_MIN);
    }

    _startMs() {
        const d = this.campaign?.rawStartDate;
        if (!d) return Infinity;
        return new Date(d).getTime();
    }

    _isUpcomingSoon() {
        const s = (this.campaign?.campaignStatus || '').toLowerCase();
        if (s !== 'upcoming') return false;
        const diff = this._startMs() - Date.now();
        return diff > 0 && diff < 86_400_000;
    }

    // ── Computed getters ─────────────────────────────────────────────────────

    get _statusLower() {
        return (this.campaign?.campaignStatus || '').toLowerCase();
    }

    get isRejected() {
        return this._statusLower === 'rejected';
    }

    get isOngoing() {
        return this._statusLower === 'ongoing';
    }

    get isCompleted() {
        return this._statusLower === 'completed';
    }

    get isDeletionRequested() {
        return this._statusLower === 'deletion requested';
    }

    // Show Edit + Delete only when owner and status is editable (In Review or Upcoming)
    get showActions() {
        if (!this.campaign?.isOwner) return false;
        const s = this._statusLower;
        return !['deletion requested', 'rejected', 'ongoing', 'completed'].includes(s);
    }

    // Close Campaign button — owner only, ongoing campaigns
    get showCloseCampaign() {
        return !!this.campaign?.isOwner && this.isOngoing;
    }

    get isDeleteDisabledSoon() {
        return this._isUpcomingSoon();
    }

    get isDeleteDisabled() {
        return this.campaign?.approvalStatus !== 'Approved' || this.isDeleteDisabledSoon;
    }

    get deleteTooltip() {
        if (this.isDeleteDisabledSoon) {
            return 'Campaign deletion is disabled because the campaign begins in under 24 hours.';
        }
        return 'Only approved campaigns can be deleted.';
    }

    get showCountdown() {
        return !!this._countdown;
    }

    get countdownLabel() {
        return `Campaign Starts in ${this._countdown || ''}`;
    }

    get showRejectionBanner() {
        const s = (this.campaign?.campaignStatus || '').toLowerCase();
        return s === 'rejected' && !!this.campaign?.rejectionReason;
    }

    get showAdminApproveReject() {
        return this.campaign?.isAdmin && this.campaign?.approvalStatus === 'In Review';
    }

    get showAdminDeletionActions() {
        return this.campaign?.isAdmin && this.campaign?.approvalStatus === 'Deletion Requested';
    }

    get hasExternalLink() {
        return !!this.campaign?.externalLink;
    }

    get hasOwner() {
        return this.campaign && this.campaign.owner && this.campaign.owner.name;
    }

    get ownerInitials() {
        const name = this.campaign?.owner?.name || '';
        return name.trim().split(/\s+/).slice(0, 2).map(w => w[0]?.toUpperCase() || '').join('');
    }

    get statusClass() {
        const s = this.campaign?.campaignStatus || '';
        const map = {
            'ongoing':            'status ongoing',
            'upcoming':           'status upcoming',
            'completed':          'status completed',
            'in review':          'status inreview',
            'approved':           'status approved',
            'rejected':           'status rejected',
            'deletion requested': 'status deletionrequested'
        };
        return map[s.toLowerCase()] || 'status inreview';
    }

    // ── Event handlers ───────────────────────────────────────────────────────

    handleDelete() {
        this._deleteError = null;
        this._showDeleteModal = true;
    }

    handleCancelDelete() {
        this._showDeleteModal = false;
        this._deleteError = null;
    }

    async handleConfirmDelete() {
        this._isDeleting = true;
        this._deleteError = null;
        try {
            await deleteCampaign({ campaignId: this.campaign.id });
            this._showDeleteModal = false;
            this.campaign = { ...this.campaign, campaignStatus: 'Deletion Requested' };
            this._showDeleteSuccessPopup = true;
            this._successPopupTimer = setTimeout(() => {
                this._showDeleteSuccessPopup = false;
            }, 3000);
        } catch (e) {
            this._deleteError = e?.body?.message || 'An error occurred. Please try again.';
        } finally {
            this._isDeleting = false;
        }
    }

    handleCloseSuccessPopup() {
        if (this._successPopupTimer) clearTimeout(this._successPopupTimer);
        this._showDeleteSuccessPopup = false;
    }

    handleEdit() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'create_campaign__c' },
            state: { recordId: this.campaign.id }
        });
    }

    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: this.backPageName || DEFAULT_BACK_PAGE }
        });
    }

    handleHeroError(event) {
        event.target.style.display = 'none';
        const placeholder = this.template.querySelector('.hero-placeholder-fallback');
        if (placeholder) placeholder.style.display = 'block';
    }

    // ── Admin action handlers ────────────────────────────────────────────────

    async handleAdminApprove() {
        this._adminActionLoading = true;
        this._adminActionError   = null;
        try {
            await approveCampaign({ campaignId: this.campaign.id });
            await refreshApex(this._wiredCampaignResult);
        } catch (e) {
            this._adminActionError = e?.body?.message || 'Failed to approve. Please try again.';
        } finally {
            this._adminActionLoading = false;
        }
    }

    openAdminRejectModal() {
        this._adminRejectReason  = '';
        this._adminActionError   = null;
        this._showAdminRejectModal = true;
    }

    closeAdminRejectModal() {
        this._showAdminRejectModal = false;
        this._adminActionError     = null;
    }

    handleAdminRejectReasonChange(e) {
        this._adminRejectReason = e.target.value;
    }

    async confirmAdminReject() {
        this._adminActionLoading = true;
        this._adminActionError   = null;
        try {
            await rejectCampaign({ campaignId: this.campaign.id, reason: this._adminRejectReason });
            this._showAdminRejectModal = false;
            await refreshApex(this._wiredCampaignResult);
        } catch (e) {
            this._adminActionError = e?.body?.message || 'Failed to reject. Please try again.';
        } finally {
            this._adminActionLoading = false;
        }
    }

    openAdminApproveDeleteModal() {
        this._adminActionError            = null;
        this._showAdminApproveDeleteModal = true;
    }

    closeAdminApproveDeleteModal() {
        this._showAdminApproveDeleteModal = false;
        this._adminActionError            = null;
    }

    async confirmAdminApproveDeletion() {
        this._adminActionLoading = true;
        this._adminActionError   = null;
        try {
            await approveDeletion({ campaignId: this.campaign.id });
            this._showAdminApproveDeleteModal = false;
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: this.backPageName || DEFAULT_BACK_PAGE }
            });
        } catch (e) {
            this._adminActionError = e?.body?.message || 'Failed to delete. Please try again.';
        } finally {
            this._adminActionLoading = false;
        }
    }

    async handleAdminDismissDeletion() {
        this._adminActionLoading = true;
        this._adminActionError   = null;
        try {
            await rejectDeletion({ campaignId: this.campaign.id });
            await refreshApex(this._wiredCampaignResult);
        } catch (e) {
            this._adminActionError = e?.body?.message || 'Failed to dismiss. Please try again.';
        } finally {
            this._adminActionLoading = false;
        }
    }

    handleCloseCampaign() {
        this._closeError = null;
        this._showCloseModal = true;
    }

    handleCancelClose() {
        this._showCloseModal = false;
        this._closeError = null;
    }

    async handleConfirmClose() {
        this._isClosing = true;
        this._closeError = null;
        try {
            await closeCampaign({ campaignId: this.campaign.id });
            this._showCloseModal = false;
            this.campaign = { ...this.campaign, campaignStatus: 'Completed' };
        } catch (e) {
            this._closeError = e?.body?.message || 'An error occurred. Please try again.';
        } finally {
            this._isClosing = false;
        }
    }

    _stopPropagation(event) {
        event.stopPropagation();
    }

    handleAvatarError(event) {
        event.target.style.display = 'none';
        const fallback = event.target.closest('.owner-row')?.querySelector('.owner-initials-fallback');
        if (fallback) fallback.style.display = 'flex';
    }
}