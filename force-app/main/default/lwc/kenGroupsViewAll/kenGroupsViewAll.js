import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getGroupsData from '@salesforce/apex/KenGroupsController.getGroupsData';
import defaultProfileImage from '@salesforce/resourceUrl/defaultProfileImage';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenGroupsViewAll extends NavigationMixin(LightningElement) {
    /** Set in Experience Builder: 'created' | 'joined' | 'discover' */
    @api viewType = 'discover';

    @track isLoading = true;
    @track _allGroups = [];
    @track _joinedGroups = [];
    @track _createdGroups = [];

    @track searchTerm     = '';
    @track typeFilter     = 'all';
    @track statusFilter   = 'all';
    @track ownershipFilter = 'all';
    @track showFilterPanel = false;
    canCreateGroups = false;

    _filterClickHandler = null;

    connectedCallback() {
        getPrimaryColor().then(color => {
            if (color) {
                document.documentElement.style.setProperty('--primary-color', color.primaryColor);
                document.documentElement.style.setProperty('--secondary-color', color.secondaryColor);
                document.documentElement.style.setProperty('--tertiary-color', color.tertiaryColor);
                this.canCreateGroups = color.createGroups !== false;
            }
        }).catch(() => {});

        this._filterClickHandler = (e) => {
            if (!this.showFilterPanel) return;
            const inside = e.composedPath().some(el => el?.dataset?.filterRoot === 'true');
            if (!inside) this.showFilterPanel = false;
        };
        document.addEventListener('click', this._filterClickHandler);

        this.loadData();
    }

    disconnectedCallback() {
        if (this._filterClickHandler) {
            document.removeEventListener('click', this._filterClickHandler);
            this._filterClickHandler = null;
        }
    }

    loadData() {
        this.isLoading = true;
        getGroupsData()
            .then(data => {
                this._allGroups     = this.mapGroups(data.discoverGroups || []);
                this._joinedGroups  = this.mapGroups(data.joinedGroups   || []);
                this._createdGroups = this.mapGroups(data.createdGroups  || []);
            })
            .catch(() => {})
            .finally(() => { this.isLoading = false; });
    }

    mapGroups(rows) {
        return (rows || []).map(row => ({
            id:          row.id,
            name:        row.name,
            cardStyle:   this._getCardStyle(row.bannerImage, row.category),
            members:     row.memberCountFormatted || '0',
            memberCount: row.memberCount || 0,
            groupType:   row.groupType || 'Private',
            status:      row.status || '',
            isInReview:  ['In Review', 'Draft'].includes(row.status || ''),
            category:    row.category,
            friendsImages: this._buildFriendImages(row.id, row.friendsImages),
            friends:     row.friendsText || null,
            isFeatured:  row.isFeatured || false
        }));
    }

    _buildFriendImages(groupId, friendsImages) {
        return (friendsImages || []).map((img, index) => ({
            key: `${groupId || 'g'}-${index}`,
            url: (typeof img === 'string' && img.trim()) ? img : defaultProfileImage
        }));
    }

    _getCardStyle(bannerImage, category) {
        const gradients = {
            Professional: 'linear-gradient(135deg, #1a237e 0%, #1565c0 100%)',
            Sports:       'linear-gradient(135deg, #1b5e20 0%, #388e3c 100%)',
            Batch:        'linear-gradient(135deg, #4a148c 0%, #7b1fa2 100%)',
            Interest:     'linear-gradient(135deg, #bf360c 0%, #e64a19 100%)',
            Academic:     'linear-gradient(135deg, #01579b 0%, #0288d1 100%)',
            Social:       'linear-gradient(135deg, #880e4f 0%, #c2185b 100%)',
            Other:        'linear-gradient(135deg, #263238 0%, #546e7a 100%)'
        };
        const gradient = gradients[category] || gradients.Other;
        return bannerImage
            ? `background: url('${bannerImage}') center/cover no-repeat, ${gradient};`
            : `background: ${gradient};`;
    }

    // ── View type helpers ──────────────────────────────────────────────────
    get isCreatedView()  { return this.viewType === 'created'; }
    get isDiscoverView() { return this.viewType === 'discover'; }
    get showCreatedCreate() { return this.isCreatedView && this.canCreateGroups; }

    get title() {
        if (this.viewType === 'created') return 'Created Groups';
        if (this.viewType === 'joined')  return 'Groups Joined';
        return 'Discover Groups';
    }

    get sourceGroups() {
        if (this.viewType === 'created') return this._createdGroups;
        if (this.viewType === 'joined')  return this._joinedGroups;
        return this._allGroups;
    }

    get filteredGroups() {
        const search = (this.searchTerm || '').toLowerCase().trim();
        return this.sourceGroups.filter(g => {
            const nameMatch   = !search || (g.name || '').toLowerCase().includes(search);
            const typeMatch   = this.typeFilter === 'all' || (g.groupType || '').toLowerCase() === this.typeFilter;
            const statusMatch = !this.isCreatedView  || this.statusFilter   === 'all' || (g.status || '') === this.statusFilter;
            const ownerMatch  = !this.isDiscoverView || this.ownershipFilter === 'all'
                || (this.ownershipFilter === 'admin' ? g.isFeatured : !g.isFeatured);
            return nameMatch && typeMatch && statusMatch && ownerMatch;
        });
    }

    get isEmpty() {
        return !this.isLoading && this.filteredGroups.length === 0;
    }

    // ── Filter count & option helpers ──────────────────────────────────────
    get activeFilterCount() {
        return (this.typeFilter      !== 'all' ? 1 : 0) +
               (this.statusFilter    !== 'all' ? 1 : 0) +
               (this.ownershipFilter !== 'all' ? 1 : 0);
    }
    get hasActiveFilters()  { return this.activeFilterCount > 0; }
    get filterCountLabel()  { return String(this.activeFilterCount); }

    // Type options
    get filterTypeAll()     { return this.typeFilter === 'all'; }
    get filterTypePrivate() { return this.typeFilter === 'private'; }
    get filterTypePublic()  { return this.typeFilter === 'public'; }

    // Status options (created view)
    get filterStatusAll()       { return this.statusFilter === 'all'; }
    get filterStatusDraft()     { return this.statusFilter === 'Draft'; }
    get filterStatusInReview()  { return this.statusFilter === 'In Review'; }
    get filterStatusApproved()  { return this.statusFilter === 'Approved'; }
    get filterStatusRejected()  { return this.statusFilter === 'Rejected'; }

    // Ownership options (discover view)
    get filterOwnerAll()    { return this.ownershipFilter === 'all'; }
    get filterOwnerAdmin()  { return this.ownershipFilter === 'admin'; }
    get filterOwnerAlumni() { return this.ownershipFilter === 'alumni'; }

    // ── Navigation ─────────────────────────────────────────────────────────
    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'group__c' }
        });
    }

    handleCreateGroup() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'create_group__c' }
        });
    }

    handleGroupCardClick(event) {
        const groupId = event.currentTarget.dataset.groupId;
        if (groupId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'group_detail__c' },
                state: { groupId: groupId }
            });
        }
    }

    // ── Filter handlers ────────────────────────────────────────────────────
    handleSearchInput(event)    { this.searchTerm     = event.target.value || ''; }
    handleTypeFilter(event)     { this.typeFilter      = event.target.value || 'all'; }
    handleStatusFilter(event)   { this.statusFilter    = event.target.value || 'all'; }
    handleOwnershipFilter(event){ this.ownershipFilter = event.target.value || 'all'; }
    handleFilterWrapClick(event) { event.stopPropagation(); }
    handleToggleFilters()        { this.showFilterPanel = !this.showFilterPanel; }
    handleClearFilters() {
        this.typeFilter      = 'all';
        this.statusFilter    = 'all';
        this.ownershipFilter = 'all';
    }
    handleApplyFilters() { this.showFilterPanel = false; }
}