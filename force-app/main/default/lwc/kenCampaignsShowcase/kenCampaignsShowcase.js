import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getPublishedCampaigns     from '@salesforce/apex/KenFundraiseController.getPublishedCampaigns';
import getFundraiseCategories    from '@salesforce/apex/KenFundraiseController.getFundraiseCategories';

const CURRENCY_SYMBOLS = { INR: '₹', USD: '$', EUR: '€', GBP: '£' };
const BATCH_SIZE = 6;

export default class KenCampaignsShowcase extends NavigationMixin(LightningElement) {
    @track _campaigns   = [];
    @track isLoading    = true;
    @track loadError    = null;

    @track searchTerm   = '';
    @track showFilters  = false;
    @track filters      = { createdOn: '', status: '', category: '' };
    @track draftFilters = { createdOn: '', status: '', category: '' };
    @track visibleCount = BATCH_SIZE;

    @track _categoryOptions = [];
    _scrollObserver = null;
    _observedSentinel = null;
    _appliedCategoryFromUrl = undefined;

    @wire(getFundraiseCategories)
    wiredCategories({ data }) {
        if (data) this._categoryOptions = data;
    }

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const categoryId = ref?.state?.category || ref?.state?.c__category || '';
        if (categoryId === this._appliedCategoryFromUrl) return;
        this._appliedCategoryFromUrl = categoryId;
        this.filters      = { ...this.filters,      category: categoryId };
        this.draftFilters = { ...this.draftFilters, category: categoryId };
        this.visibleCount = BATCH_SIZE;
    }

    @wire(getPublishedCampaigns)
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
        let campaignStatus;
        if (c.approvalStatus === 'Approved') {
            if (c.campaignStatus === 'Completed') {
                campaignStatus = 'Completed';
            } else {
                const today = new Date();
                today.setHours(0, 0, 0, 0);
                const start = c.startDate ? new Date(c.startDate) : null;
                const end   = c.endDate   ? new Date(c.endDate)   : null;
                if (end && end < today) {
                    campaignStatus = 'Completed';
                } else if (start && start <= today) {
                    campaignStatus = 'Ongoing';
                } else {
                    campaignStatus = 'Upcoming';
                }
            }
        } else {
            campaignStatus = c.approvalStatus || c.campaignStatus || '';
        }
        const statusClassMap = {
            'ongoing':   'sc-status sc-ongoing',
            'upcoming':  'sc-status sc-upcoming',
            'completed': 'sc-status sc-completed'
        };
        return {
            id:             c.id,
            title:          c.name,
            category:       c.category  || '',
            categoryId:     c.categoryId || '',
            campaignStatus,
            statusClass:    statusClassMap[campaignStatus.toLowerCase()] || 'sc-status sc-upcoming',
            dateRange:      this._formatDateRange(c.startDate, c.endDate) || '',
            createdOn:      c.createdDate || '',
            image:          c.coverImage  || '',
            goal,
            owner: { name: c.ownerName || '', avatar: c.ownerPhotoUrl || '' }
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

    _formatDate(dateStr) {
        if (!dateStr) return '';
        const [year, month, day] = dateStr.split('-');
        return `${day}-${month}-${year}`;
    }

    // ── Computed getters ─────────────────────────────────────────────────────

    _filteredCampaigns() {
        const term = this.searchTerm.trim().toLowerCase();
        return this._campaigns.filter(c => {
            const matchesSearch   = !term
                || c.title.toLowerCase().includes(term)
                || c.category.toLowerCase().includes(term)
                || c.owner?.name?.toLowerCase().includes(term);
            const matchesCreatedOn = !this.filters.createdOn || c.createdOn === this.filters.createdOn;
            const matchesStatus    = !this.filters.status    || c.campaignStatus === this.filters.status;
            const matchesCategory  = !this.filters.category  || c.categoryId === this.filters.category;
            return matchesSearch && matchesCreatedOn && matchesStatus && matchesCategory;
        });
    }

    get visibleCampaigns() {
        return this._filteredCampaigns().slice(0, this.visibleCount);
    }

    get hasMoreToShow() {
        return this._filteredCampaigns().length > this.visibleCount;
    }

    get hasNoResults() {
        return !this.isLoading && !this.loadError && this._filteredCampaigns().length === 0;
    }

    get selectedCategoryName() {
        if (!this.filters.category) return '';
        const match = (this._categoryOptions || []).find(o => o.id === this.filters.category);
        return match ? match.name : '';
    }

    get emptyStateMessage() {
        if (this.filters.category) {
            const name = this.selectedCategoryName;
            return name
                ? `There are no active campaigns for "${name}" right now.`
                : 'There are no active campaigns for this category right now.';
        }
        if (this.searchTerm || this.filters.status || this.filters.createdOn) {
            return 'No campaigns match your filters. Try adjusting or clearing them.';
        }
        return 'There are no active campaigns yet. Check back soon!';
    }

    get statusOptions() { return ['Upcoming', 'Ongoing', 'Completed']; }

    get categoryOptions() { return this._categoryOptions; }

    get statusSelectOptions() {
        return this.statusOptions.map(o => ({ label: o, value: o, selected: o === this.draftFilters.status }));
    }

    get categorySelectOptions() {
        return this.categoryOptions.map(o => ({ label: o.name, value: o.id, selected: o.id === this.draftFilters.category }));
    }

    get activeFilterCount() {
        return [this.filters.createdOn, this.filters.status, this.filters.category].filter(Boolean).length;
    }

    get hasActiveFilters() { return this.activeFilterCount > 0; }

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
        if (this.showFilters) this.syncFilterFieldValues();
        this.syncScrollObserver();
    }

    connectedCallback() {
        getPrimaryColor()
            .then(color => {
                if (color?.primaryColor)   document.documentElement.style.setProperty('--primary-color',   color.primaryColor);
                if (color?.secondaryColor) document.documentElement.style.setProperty('--secondary-color', color.secondaryColor);
            })
            .catch(() => {});
    }

    disconnectedCallback() {
        if (this._scrollObserver) this._scrollObserver.disconnect();
    }

    // ── Infinite scroll ──────────────────────────────────────────────────────

    syncScrollObserver() {
        const sentinel = this.template.querySelector('.scroll-sentinel');
        if (sentinel === this._observedSentinel) return;

        if (this._scrollObserver) this._scrollObserver.disconnect();
        this._observedSentinel = sentinel;
        if (!sentinel) return;

        this._scrollObserver = new IntersectionObserver(entries => {
            if (entries[0].isIntersecting) this.loadMore();
        });
        this._scrollObserver.observe(sentinel);
    }

    loadMore() {
        this.visibleCount = Math.min(this.visibleCount + BATCH_SIZE, this._filteredCampaigns().length);
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    handleSearch(event)    {
        this.searchTerm = event.target.value;
        this.visibleCount = BATCH_SIZE;
    }
    openFilters()          { this.draftFilters = { ...this.filters }; this.showFilters = true; }
    closeFilters()         { this.showFilters = false; }
    stopPropagation(event) { event.stopPropagation(); }

    handleDraftChange(event) {
        const { name, value } = event.target;
        this.draftFilters = { ...this.draftFilters, [name]: value };
    }

    applyFilters() {
        this.filters = { ...this.draftFilters };
        this.showFilters = false;
        this.visibleCount = BATCH_SIZE;
    }

    resetFilters() {
        const empty = { createdOn: '', status: '', category: '' };
        this.draftFilters = { ...empty };
        this.filters      = { ...empty };
        this.visibleCount = BATCH_SIZE;
    }

    syncFilterFieldValues() {
        const createdOnInput = this.template.querySelector('input[name="createdOn"]');
        const statusSelect   = this.template.querySelector('select[name="status"]');
        const categorySelect = this.template.querySelector('select[name="category"]');
        if (createdOnInput) createdOnInput.value = this.draftFilters.createdOn || '';
        if (statusSelect)   statusSelect.value   = this.draftFilters.status    || '';
        if (categorySelect) categorySelect.value = this.draftFilters.category  || '';
    }

    handleOpenCreateCampaign() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'create_campaign__c' }
        });
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
}