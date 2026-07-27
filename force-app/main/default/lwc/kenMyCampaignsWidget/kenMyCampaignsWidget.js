import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMyCampaigns from '@salesforce/apex/KenFundraiseController.getMyCampaigns';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const CURRENCY_SYMBOLS = { INR: '₹', USD: '$', EUR: '€', GBP: '£' };

const STATUS_CLASS = {
    'In Review':          'status-badge status-badge_review',
    'Approved':           'status-badge status-badge_approved',
    'Rejected':           'status-badge status-badge_rejected',
    'Upcoming':           'status-badge status-badge_upcoming',
    'Ongoing':            'status-badge status-badge_ongoing',
    'Completed':          'status-badge status-badge_completed',
    'Deletion Requested': 'status-badge status-badge_deletion'
};

export default class KenMyCampaignsWidget extends NavigationMixin(LightningElement) {
    @track campaigns = [];
    @track isLoading = true;
    @track error = null;
    // When Create Campaign is disabled the CTA card below this widget is hidden,
    // so the widget stretches down to fill the space it would have left blank.
    @track canCreateFundraise = false;

    _rawData = [];

    connectedCallback() {
        getPrimaryColor()
            .then((color) => {
                this.canCreateFundraise = color?.createFundraise !== false;
            })
            .catch(() => {});
    }

    get panelClass() {
        return this.canCreateFundraise ? 'my-campaigns-panel' : 'my-campaigns-panel cta-hidden';
    }

    _statusOrder(status) {
        const order = { 'Ongoing': 0, 'Upcoming': 1, 'In Review': 2, 'Rejected': 3, 'Completed': 4 };
        return order[status] ?? 5;
    }

    @wire(getMyCampaigns)
    wiredCampaigns({ data, error }) {
        this.isLoading = false;
        if (data) {
            this._rawData = data;
            this.campaigns = data
                .map(c => this._mapCard(c))
                .sort((a, b) => this._statusOrder(a.status) - this._statusOrder(b.status));
            this.error = null;
        } else if (error) {
            this.error = error?.body?.message || 'Failed to load campaigns.';
        }
    }

    _mapCard(c) {
        const symbol = CURRENCY_SYMBOLS[c.currencyCode] || '₹';
        const goal = c.fundraisingGoal
            ? symbol + Number(c.fundraisingGoal).toLocaleString('en-IN')
            : null;

        let primaryStatus;
        if (c.approvalStatus === 'Approved') {
            if (c.campaignStatus === 'Completed') {
                primaryStatus = 'Completed';
            } else {
                const today = new Date();
                today.setHours(0, 0, 0, 0);
                const start = c.startDate ? new Date(c.startDate) : null;
                const end   = c.endDate   ? new Date(c.endDate)   : null;
                if (end && end < today) {
                    primaryStatus = 'Completed';
                } else if (start && start <= today) {
                    primaryStatus = 'Ongoing';
                } else {
                    primaryStatus = 'Upcoming';
                }
            }
        } else {
            primaryStatus = c.approvalStatus || '';
        }

        return {
            id:          c.id,
            name:        c.name,
            category:    c.category || '',
            status:      primaryStatus,
            statusClass: STATUS_CLASS[primaryStatus] || 'status-badge',
            goal,
            dateRange:   this._formatDateRange(c.startDate, c.endDate),
            coverImage:  c.coverImage || null,
            ownerName:   c.ownerName || null
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

    get hasCampaigns() {
        return this.campaigns.length > 0;
    }

    handleCardClick(event) {
        const recordId = event.currentTarget.dataset.id;
        const raw = this._rawData.find(r => r.id === recordId);
        if (!raw) return;

        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'campaign_detail__c' },
            state: { recordId: raw.id }
        });
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'created_fundraise__c' }
        });
    }

    handleImgError(event) {
        event.target.closest('.card-image-section').classList.add('no-image');
        event.target.style.display = 'none';
    }
}