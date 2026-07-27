import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getMyCampaigns            from '@salesforce/apex/KenFundraiseController.getMyCampaigns';
import getFundraiseCategories    from '@salesforce/apex/KenFundraiseController.getFundraiseCategories';

const TAB_OPTIONS      = ['Approved', 'In Review', 'Rejected'];
const STATUS_OPTIONS   = ['Upcoming', 'Ongoing', 'Completed'];
const CURRENCY_SYMBOLS = { INR: '₹', USD: '$', EUR: '€', GBP: '£' };

export default class KenFundraiseTabs extends NavigationMixin(LightningElement) {
    tabs          = TAB_OPTIONS;
    statusOptions = STATUS_OPTIONS;
    canCreateFundraise = false;

    @track _campaigns   = [];
    @track isLoading    = true;
    @track loadError    = null;

    @track searchTerm   = '';
    @track filters      = { createdOn: '', status: '', category: '' };
    @track draftFilters = { createdOn: '', status: '', category: '' };
    @track activeTab    = 'Approved';
    @track showFilters  = false;

    @track _categoryOptions = [];

    @wire(getFundraiseCategories)
    wiredCategories({ data }) {
        if (data) this._categoryOptions = data;
    }

    @wire(getMyCampaigns)
    wiredCampaigns({ data, error }) {
        this.isLoading = false;
        if (data) {
            this._campaigns = data.map(c => this._mapCard(c));
        } else if (error) {
            this.loadError = error?.body?.message || 'Failed to load campaigns.';
        }
    }

    _mapCard(c) {
        const symbol = CURRENCY_SYMBOLS[c.currencyCode] || '₹';
        const goal   = c.fundraisingGoal
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
        const showBadge = c.approvalStatus === 'Approved';
        return {
            id:               c.id,
            title:            c.name,
            category:         c.category || '',
            categoryId:       c.categoryId || '',
            approvalStatus:   c.approvalStatus || '',
            campaignStatus:   primaryStatus,
            rawCampaignStatus: c.campaignStatus || '',
            dateRange:        this._formatDateRange(c.startDate, c.endDate) || '',
            createdOn:        c.createdDate || '',
            image:            c.coverImage  || '',
            goal,
            owner:            { name: c.ownerName || '', avatar: c.ownerPhotoUrl || '' },
            statusClass:      this._computeStatusClass(primaryStatus),
            showStatusBadge:  showBadge
        };
    }

    _formatDateRange(start, end) {
        if (!start && !end) return null;
        const fmt = s => {
            if (!s) return '';
            const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            const [y, m, d] = s.split('-').map(Number);
            return `${d} ${months[m - 1]} ${y}`;
        };
        if (start && end) return `${fmt(start)} – ${fmt(end)}`;
        return start ? `From ${fmt(start)}` : `Until ${fmt(end)}`;
    }

    _computeStatusClass(status) {
        const map = {
            'ongoing':   'status ongoing',
            'upcoming':  'status upcoming',
            'completed': 'status completed',
            'in review': 'status inreview',
            'approved':  'status approved',
            'rejected':  'status rejected'
        };
        return map[(status || '').toLowerCase()] || 'status inreview';
    }

    _formatDate(dateStr) {
        if (!dateStr) return '';
        const [year, month, day] = dateStr.split('-');
        return `${day}-${month}-${year}`;
    }

    // ── Computed getters ─────────────────────────────────────────────────────

    get categoryOptions() { return this._categoryOptions; }

    _categoryName(categoryId) {
        const match = (this._categoryOptions || []).find(o => o.id === categoryId);
        return match ? match.name : '';
    }

    get draftCategoryLabel() { return this._categoryName(this.draftFilters.category); }

    get filterCategoryLabel() { return this._categoryName(this.filters.category); }

    get filteredCampaigns() {
        let list = this._campaigns.filter(c => c.approvalStatus === this.activeTab);

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            list = list.filter(c =>
                c.title.toLowerCase().includes(term) ||
                c.category.toLowerCase().includes(term) ||
                c.owner?.name?.toLowerCase().includes(term)
            );
        }
        if (this.filters.status) {
            list = list.filter(c => c.rawCampaignStatus === this.filters.status);
        }
        if (this.filters.category) {
            list = list.filter(c => c.categoryId === this.filters.category);
        }
        if (this.filters.createdOn) {
            list = list.filter(c => c.createdOn === this.filters.createdOn);
        }
        return list;
    }

    get pills() {
        const pills = [];
        if (this.searchTerm)      pills.push({ key: 'search',    type: 'search',    label: `Search: "${this.searchTerm}"`,        ariaLabel: 'Remove search filter' });
        if (this.filters.status)    pills.push({ key: 'status',    type: 'status',    label: `Status: ${this.filters.status}`,      ariaLabel: 'Remove status filter' });
        if (this.filters.category)  pills.push({ key: 'category',  type: 'category',  label: `Category: ${this.filterCategoryLabel}`,  ariaLabel: 'Remove category filter' });
        if (this.filters.createdOn) pills.push({ key: 'createdOn', type: 'createdOn', label: `Created on: ${this.filters.createdOn}`, ariaLabel: 'Remove created on filter' });
        return pills;
    }

    get tabItems() {
        return this.tabs.map(label => ({
            label,
            value: label,
            selected: label === this.activeTab,
            className: `tab-btn ${label === this.activeTab ? 'active' : ''}`
        }));
    }

    get activeFilterCount() {
        return [this.filters.createdOn, this.filters.status, this.filters.category].filter(Boolean).length;
    }

    get hasActiveFilters() { return this.activeFilterCount > 0; }

    get isApprovedTab() { return this.activeTab === 'Approved'; }

    get createdOnDisplayClass() {
        return this.draftFilters.createdOn
            ? 'date-display-text date-display-text_has-value'
            : 'date-display-text';
    }

    get createdOnDisplayText() {
        return this.draftFilters.createdOn ? this._formatDate(this.draftFilters.createdOn) : 'Created on';
    }

    get formattedCreatedOn() { return this._formatDate(this.draftFilters.createdOn); }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    renderedCallback() {
        if (!this.showFilters) return;
        this.syncFilterFieldValues();
    }

    connectedCallback() {
        getPrimaryColor()
            .then(color => {
                if (color?.primaryColor)   document.documentElement.style.setProperty('--primary-color',   color.primaryColor);
                if (color?.secondaryColor) document.documentElement.style.setProperty('--secondary-color', color.secondaryColor);
                if (color?.tertiaryColor)  document.documentElement.style.setProperty('--tertiary-color',  color.tertiaryColor);
                this.canCreateFundraise = color?.createFundraise !== false;
            })
            .catch(() => {});
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleTabChange(event) {
        this.activeTab = event.target.dataset.tab;
        if (this.activeTab !== 'Approved') {
            this.filters      = { ...this.filters,      status: '' };
            this.draftFilters = { ...this.draftFilters, status: '' };
        }
    }
    handleSearch(event)    { this.searchTerm = event.target.value.trim(); }

    openFilters()          { this.draftFilters = { ...this.filters }; this.showFilters = true; }
    closeFilters()         { this.showFilters = false; }
    stopPropagation(event) { event.stopPropagation(); }

    handleDraftChange(event) {
        const { name, value } = event.target;
        this.draftFilters = { ...this.draftFilters, [name]: value };
    }

    applyFilters() { this.filters = { ...this.draftFilters }; this.showFilters = false; }

    resetDraft() { this.draftFilters = { createdOn: '', status: '', category: '' }; }

    resetAll() { this.resetDraft(); this.applyFilters(); this.searchTerm = ''; }

    removePill(event) {
        const type = event.target.dataset.name;
        if (type === 'search') { this.searchTerm = ''; return; }
        this.filters = { ...this.filters, [type]: '' };
    }

    syncFilterFieldValues() {
        const createdOnInput = this.template.querySelector('input[name="createdOn"]');
        const statusSelect   = this.template.querySelector('select[name="status"]');
        const categorySelect = this.template.querySelector('select[name="category"]');
        if (createdOnInput) createdOnInput.value = this.draftFilters.createdOn || '';
        if (statusSelect)   statusSelect.value   = this.draftFilters.status    || '';
        if (categorySelect) categorySelect.value = this.draftFilters.category  || '';
    }

    handleImageError(event) {
        event.target.style.display = 'none';
    }

    handleCardClick(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'campaign_detail__c' },
            state: { recordId: id }
        });
    }

    handleOpenCreateCampaign() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'create_campaign__c' }
        });
    }
}