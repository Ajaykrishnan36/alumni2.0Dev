import { LightningElement, track } from 'lwc';
import CoverImage from '@salesforce/resourceUrl/PortalLoginImage';

const ALL_JOINED_GROUPS = [
    { id: 1, name: '5K Runners Group',         members: '1.2k', status: 'Private', type: 'Social',       createdOn: '2023-03-10', image: CoverImage, friends: 'Sajin and 24 friends are members', friendsImages: [CoverImage, CoverImage, CoverImage] },
    { id: 2, name: 'Batch 2018',               members: '1.2k', status: 'Private', type: 'Alumni',       createdOn: '2023-06-12', image: CoverImage, friends: 'Sajin and 24 friends are members', friendsImages: [CoverImage, CoverImage, CoverImage] },
    { id: 3, name: 'Entrepreneurs of Ken42',   members: '1.2k', status: 'Public',  type: 'Professional', createdOn: '2022-11-05', image: CoverImage, friends: 'Sajin and 24 friends are members', friendsImages: [CoverImage, CoverImage, CoverImage] },
    { id: 4, name: 'Short film Enthusiasts',   members: '1.2k', status: 'Private', type: 'Social',       createdOn: '2023-01-20', image: CoverImage, friends: 'Sajin and 24 friends are members', friendsImages: [CoverImage, CoverImage, CoverImage] },
];

export default class KenJoinedGroups extends LightningElement {
    @track searchTerm = '';
    @track showFilterPanel = false;

    // pending (in-panel) values
    @track filterStatus = '';
    @track filterType = '';
    @track filterCreatedOn = '';

    // applied values (used to actually filter)
    @track appliedStatus = '';
    @track appliedType = '';
    @track appliedCreatedOn = '';

    allGroups = ALL_JOINED_GROUPS;

    // ── select option helpers ───────────────────────────────────────
    get isStatusAll()     { return this.filterStatus === ''; }
    get isStatusPrivate() { return this.filterStatus === 'Private'; }
    get isStatusPublic()  { return this.filterStatus === 'Public'; }

    get isTypeAll()          { return this.filterType === ''; }
    get isTypeAlumni()       { return this.filterType === 'Alumni'; }
    get isTypeProfessional() { return this.filterType === 'Professional'; }
    get isTypeSocial()       { return this.filterType === 'Social'; }

    // ── badge count on filter button ────────────────────────────────
    get activeFilterCount() {
        let count = 0;
        if (this.appliedStatus)   count++;
        if (this.appliedType)     count++;
        if (this.appliedCreatedOn) count++;
        return count || null;
    }

    // ── filtered list ───────────────────────────────────────────────
    get filteredGroups() {
        const term = (this.searchTerm || '').toLowerCase().trim();
        return this.allGroups.filter(g => {
            if (term && !(g.name || '').toLowerCase().includes(term)) return false;
            if (this.appliedStatus && g.status !== this.appliedStatus) return false;
            if (this.appliedType   && g.type   !== this.appliedType)   return false;
            if (this.appliedCreatedOn && g.createdOn < this.appliedCreatedOn) return false;
            return true;
        });
    }

    get hasGroups() {
        return this.filteredGroups.length > 0;
    }

    // ── search ──────────────────────────────────────────────────────
    handleSearchInput(event) {
        this.searchTerm = event.target.value;
    }

    // ── filter panel ────────────────────────────────────────────────
    openFilterPanel() {
        // seed panel values from applied
        this.filterStatus    = this.appliedStatus;
        this.filterType      = this.appliedType;
        this.filterCreatedOn = this.appliedCreatedOn;
        this.showFilterPanel = true;
    }

    closeFilterPanel() {
        this.showFilterPanel = false;
    }

    handleStatusChange(event) {
        this.filterStatus = event.target.value;
        this._applyDraftLive();
    }

    handleTypeChange(event) {
        this.filterType = event.target.value;
        this._applyDraftLive();
    }

    handleCreatedOnChange(event) {
        this.filterCreatedOn = event.target.value;
        this._applyDraftLive();
    }

    // Mirrors filterDraft into the applied* fields used by the filteredGroups
    // getter, so picking a value filters live instead of waiting for the
    // Apply button (matches kenGroups / kenMentorshipConnections).
    _applyDraftLive() {
        this.appliedStatus    = this.filterStatus;
        this.appliedType      = this.filterType;
        this.appliedCreatedOn = this.filterCreatedOn;
    }

    handleResetFilters() {
        this.filterStatus    = '';
        this.filterType      = '';
        this.filterCreatedOn = '';
        this.appliedStatus    = '';
        this.appliedType      = '';
        this.appliedCreatedOn = '';
        this.showFilterPanel  = false;
    }

    handleApplyFilters() {
        this._applyDraftLive();
        this.showFilterPanel  = false;
    }
}