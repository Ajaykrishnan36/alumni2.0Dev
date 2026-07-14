import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import getGroupsData from '@salesforce/apex/KenGroupsController.getGroupsData';
import defaultProfileImage from '@salesforce/resourceUrl/defaultProfileImage';

const MOBILE_BREAKPOINT = 768;

export default class KenGroups extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track hasError = false;
    @track isMobileView = false;
    @track searchTerm = '';
    @track sortBy = 'latest';
    @track showFilterPanel = false;
    @track groupTypeFilter = 'all';
    @track ownershipFilter = 'all';

    @track _groupId = null;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        this._groupId = pageRef?.state?.groupId || null;
    }

    get showGroupDetail() { return !!this._groupId; }

    @track _allGroups = [];
    @track _joinedGroups = [];
    @track _createdGroups = [];
    @track _suggestedGroups = [];

    _resizeHandler    = () => this.checkViewport();
    _filterClickHandler = null;

    connectedCallback() {
        this.checkViewport();
        if (typeof window !== 'undefined') {
            window.addEventListener('resize', this._resizeHandler);
        }
        this._filterClickHandler = (e) => {
            if (!this.showFilterPanel) return;
            const inside = e.composedPath().some(el => el?.dataset?.filterRoot === 'true');
            if (!inside) this.showFilterPanel = false;
        };
        document.addEventListener('click', this._filterClickHandler);
        this.loadData();
    }

    disconnectedCallback() {
        if (typeof window !== 'undefined') {
            window.removeEventListener('resize', this._resizeHandler);
        }
        if (this._filterClickHandler) {
            document.removeEventListener('click', this._filterClickHandler);
            this._filterClickHandler = null;
        }
    }

    checkViewport() {
        const width = typeof window !== 'undefined' ? window.innerWidth : 1024;
        this.isMobileView = width < MOBILE_BREAKPOINT;
    }

    loadData() {
        this.isLoading = true;
        this.hasError = false;
        getGroupsData()
            .then(data => {
                this._allGroups      = this.mapGroups(data.discoverGroups  || []);
                this._joinedGroups   = this.mapGroups(data.joinedGroups    || []);
                this._createdGroups  = this.mapGroups(data.createdGroups   || []);
                this._suggestedGroups = this.mapGroups(data.suggestedGroups || []);
            })
            .catch(() => { this.hasError = true; })
            .finally(() => { this.isLoading = false; });
    }

    mapGroups(rows) {
        return (rows || []).map(row => ({
            id:            row.id,
            name:          row.name,
            description:   row.description,
            image:         row.bannerImage || null,
            cardStyle:     this._getCardStyle(row.bannerImage, row.category),
            members:       row.memberCountFormatted || '0',
            memberCount:   row.memberCount || 0,
            groupType:     row.groupType || 'Private',
            status:        row.status || 'In Review',
            isInReview:    ['In Review', 'Draft'].includes(row.status || ''),
            category:      row.category,
            friendsImages: this._buildFriendImages(row.id, row.friendsImages),
            friends:       row.friendsText || null,
            isJoined:      row.isJoined  || false,
            isCreated:     row.isCreated || false,
            isFeatured:    row.isFeatured || false,
            memberRecordId: row.memberRecordId || null
        }));
    }

    _buildFriendImages(groupId, friendsImages) {
        return (friendsImages || []).map((img, index) => ({
            key: `${groupId || 'group'}-${index}`,
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

    // ── Navigate to group detail page ───────────────────────────────────────
    _navigateToGroupDetail(groupId) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'group_detail__c' },
            state: { groupId: groupId }
        });
    }

    handleGroupCardClick(event) {
        const groupId = event.currentTarget.dataset.groupId;
        if (groupId) this._navigateToGroupDetail(groupId);
    }

    handleSidebarGroupClick(event) {
        const groupId = event.detail?.groupId;
        if (groupId) this._navigateToGroupDetail(groupId);
    }

    // ── Filter getters ──────────────────────────────────────────────────────
    get activeFilterCount() {
        return (this.groupTypeFilter !== 'all' ? 1 : 0) +
               (this.ownershipFilter !== 'all' ? 1 : 0);
    }
    get hasActiveFilters() { return this.activeFilterCount > 0; }
    get filterCountLabel() { return String(this.activeFilterCount); }

    // select option helpers — fixes value not showing when panel reopens
    get filterTypeAll()     { return this.groupTypeFilter === 'all'; }
    get filterTypePrivate() { return this.groupTypeFilter === 'private'; }
    get filterTypePublic()  { return this.groupTypeFilter === 'public'; }
    get filterOwnerAll()    { return this.ownershipFilter === 'all'; }
    get filterOwnerAdmin()  { return this.ownershipFilter === 'admin'; }
    get filterOwnerAlumni() { return this.ownershipFilter === 'alumni'; }

    // ── List/filter getters ─────────────────────────────────────────────────
    get joinedGroupsList()  { return this._joinedGroups; }
    get createdGroupsList() { return this._createdGroups.slice(0, 5); }
    get suggestedGroups()   { return this._suggestedGroups; }
    get hasSuggestedGroups(){ return this._suggestedGroups.length > 0; }

    get isFilterApplied() {
        return this.groupTypeFilter !== 'all' || this.ownershipFilter !== 'all';
    }
    get showSuggestedCard() {
        return this.hasSuggestedGroups && !this.isFilterApplied;
    }

    get discoverSourceGroups() {
        if (!this.isFilterApplied) return this._allGroups;
        const byId = new Map();
        [...this._allGroups, ...this._suggestedGroups].forEach(g => {
            if (!byId.has(g.id)) byId.set(g.id, g);
        });
        return [...byId.values()];
    }
    get discoverGroupsToShow() {
        return this._applySearchAndFilters(this.discoverSourceGroups);
    }
    get firstTwoGroups()     { return this.discoverGroupsToShow.slice(0, 2); }
    get hasMoreForPreview()  { return this.discoverGroupsToShow.length > 2; }

    // Desktop layout: row 1 holds the first 3 discover cards, the suggested
    // banner sits below it (pinned to row 2), and the rest of the discover
    // cards continue underneath.
    get firstRowDiscoverGroups()  { return this.discoverGroupsToShow.slice(0, 3); }
    get restDiscoverGroups()      { return this.discoverGroupsToShow.slice(3); }
    get hasRestDiscoverGroups()   { return this.restDiscoverGroups.length > 0; }

    _applySearchAndFilters(groups) {
        const searchValue = (this.searchTerm || '').toLowerCase().trim();
        return (groups || []).filter(group => {
            const nameMatches  = !searchValue || (group.name || '').toLowerCase().includes(searchValue);
            const typeMatches  = this.groupTypeFilter === 'all' || (group.groupType || '').toLowerCase() === this.groupTypeFilter;
            const ownerMatches = this.ownershipFilter === 'all' || (this.ownershipFilter === 'admin' ? group.isFeatured : !group.isFeatured);
            return nameMatches && typeMatches && ownerMatches;
        });
    }

    // ── Navigation ──────────────────────────────────────────────────────────
    handleViewAllCreated() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'created_groups__c' } });
    }
    handleViewAllJoined() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'joined_groups__c' } });
    }
    handleDiscoverAll() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'discover_groups__c' } });
    }
    handleCreateGroup() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'create_group__c' } });
    }

    // ── Search / filter handlers ────────────────────────────────────────────
    handleSearchInput(event)           { this.searchTerm = event.target.value || ''; }
    handleSortChange(event)            { this.sortBy = event.target.value || 'latest'; }
    handleFilterWrapClick(event)        { event.stopPropagation(); }
    handleToggleFilters()              { this.showFilterPanel = !this.showFilterPanel; }
    handleGroupTypeFilterChange(event) { this.groupTypeFilter = event.target.value || 'all'; }
    handleOwnershipFilterChange(event) { this.ownershipFilter = event.target.value || 'all'; }
    handleClearFilters() {
        this.groupTypeFilter = 'all';
        this.ownershipFilter = 'all';
    }
    handleApplyFilters() { this.showFilterPanel = false; }

    // ── Join (from suggested card) ──────────────────────────────────────────
    handleJoinGroup(event) {
        const groupId = event.detail?.groupId;
        if (groupId) this._navigateToGroupDetail(groupId);
    }

    handleLeaveGroup(event) {
        // Leave is now handled inside the detail page; kept for sidebar compatibility
        const { memberRecordId } = event.detail || {};
        if (memberRecordId) this.loadData();
    }
}