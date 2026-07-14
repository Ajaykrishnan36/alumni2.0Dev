import { LightningElement, api, track } from 'lwc';
import searchSavedAudiences from '@salesforce/apex/KenAudienceEngineService.searchSavedAudiences';
import getSavedAudienceDetail from '@salesforce/apex/KenAudienceEngineService.getSavedAudienceDetail';
import activateSavedAudience from '@salesforce/apex/KenAudienceEngineService.activateSavedAudience';
import getAudienceCounts from '@salesforce/apex/KenAudienceEngineService.getAudienceCounts';

export default class KenSavedAudiencePicker extends LightningElement {
    /** When true, hides the section header (title + helper + "Add New Audience" button). */
    @api hideHeader = false;
    /** Optional override for the "Add New Audience" button label. */
    @api addNewLabel = 'Add New Audience';

    @track savedAudienceSearchTerm = '';
    @track savedAudiencesList = [];
    @track savedAudienceLoading = false;

    @track showSavedReviewModal = false;
    @track savedReviewModalItems = [];
    @track savedReviewModalName = '';
    @track savedReviewAudienceId = null;
    @track savedReviewGroup1Expanded = true;
    @track savedReviewGroupsAddedExpanded = true;

    savedAudienceSearchTimer;

    connectedCallback() {
        this.loadSavedAudiences('');
    }

    /** Public refresh, parents call after they finish processing an add. */
    @api
    refresh() {
        this.loadSavedAudiences(this.savedAudienceSearchTerm || '');
    }

    get hasSavedAudiencesList() {
        return Array.isArray(this.savedAudiencesList) && this.savedAudiencesList.length > 0;
    }

    get showSavedAudienceEmptyState() {
        return !this.hasSavedAudiencesList && !this.savedAudienceLoading;
    }

    // Single source of truth for a member-count label: a numeric count always wins; stored strings
    // are only a fallback for items that have no count. Returns null when there is no numeric count.
    memberCountLabel(count, capitalized) {
        const n = Number.isFinite(count) ? count : null;
        if (n === null) {
            return null;
        }
        const unit = capitalized ? 'Member' : 'member';
        return n === 1 ? `1 ${unit}` : `${n} ${unit}s`;
    }

    get savedReviewModalGroups() {
        return (this.savedReviewModalItems || [])
            .filter((item) => item.type === 'GROUP')
            .map((grp) => ({
                ...grp,
                membersLabel: this.memberCountLabel(grp.memberCount, true) || grp.membersLabel || 'Audience'
            }));
    }

    get savedReviewModalCustomGroups() {
        return (this.savedReviewModalItems || [])
            .filter((item) => item.type === 'CUSTOM')
            .map((grp) => ({
                ...grp,
                hasCriteria: !!(grp.criteria && Array.isArray(grp.criteria) && grp.criteria.length > 0),
                membersLabel: this.memberCountLabel(grp.memberCount, true) || grp.membersLabel || 'Audience'
            }));
    }

    get hasSavedReviewModalGroups() {
        return this.savedReviewModalGroups.length > 0;
    }

    /**
     * Every item in the saved audience, normalised for display — covers ALL the types the builder
     * can produce (role "All X" = ALL, GROUP, INDIVIDUAL, CUSTOM). The old modal only rendered
     * GROUP + the first CUSTOM, so role-based or individual audiences showed as an empty modal.
     */
    get savedReviewItems() {
        return (this.savedReviewModalItems || []).map((item) => {
            const criteria = Array.isArray(item.criteria) ? item.criteria : [];
            return {
                ...item,
                displayTitle: item.title || item.name || item.roleLabel || 'Audience',
                roleLabel: item.roleLabel || item.role || '',
                membersLabel: this.memberCountLabel(item.memberCount, true) || item.membersLabel || 'Audience',
                hasCriteria: criteria.length > 0,
                criteria
            };
        });
    }

    get hasSavedReviewItems() {
        return this.savedReviewItems.length > 0;
    }

    get savedReviewFirstCustomGroup() {
        const customGroups = this.savedReviewModalCustomGroups;
        return customGroups && customGroups.length > 0 ? customGroups[0] : null;
    }

    get savedReviewFirstCustomGroupRoleLabel() {
        const group = this.savedReviewFirstCustomGroup;
        return group && group.roleLabel ? group.roleLabel : 'Students';
    }

    get savedReviewFirstCustomGroupMembersLabel() {
        const group = this.savedReviewFirstCustomGroup;
        if (!group) {
            return 'Audience';
        }
        return this.memberCountLabel(group.memberCount, true) || group.membersLabel || 'Audience';
    }

    get savedReviewGroupsAddedCount() {
        return this.savedReviewModalGroups.length;
    }

    get savedReviewGroup1CaretClass() {
        return this.savedReviewGroup1Expanded ? 'caret-icon caret-up' : 'caret-icon caret-down';
    }

    get savedReviewGroupsAddedCaretClass() {
        return this.savedReviewGroupsAddedExpanded ? 'caret-icon caret-up' : 'caret-icon caret-down';
    }

    handleAddNewAudience() {
        this.dispatchEvent(new CustomEvent('addnew'));
    }

    handleSavedAudienceSearchInput(event) {
        this.savedAudienceSearchTerm = event.target.value;
        if (this.savedAudienceSearchTimer) {
            clearTimeout(this.savedAudienceSearchTimer);
        }
        this.savedAudienceSearchTimer = setTimeout(() => {
            this.loadSavedAudiences(this.savedAudienceSearchTerm || '');
        }, 300);
    }

    async loadSavedAudiences(searchTerm) {
        this.savedAudienceLoading = true;
        try {
            const results = await searchSavedAudiences({ searchTerm: searchTerm || '' });
            this.savedAudiencesList = (results || []).map((aud) => ({
                id: aud.id,
                name: aud.name || 'Audience',
                memberLabel:
                    aud.memberCount === null || aud.memberCount === undefined
                        ? 'Audience'
                        : aud.memberCount === 1
                          ? '1 member'
                          : `${aud.memberCount} members`
            }));
        } catch (e) {
            console.warn('Saved audience search failed', e);
            this.savedAudiencesList = [];
        } finally {
            this.savedAudienceLoading = false;
        }
    }

    handleReviewSavedAudience(event) {
        const id = event.currentTarget?.dataset?.id;
        if (!id) return;
        getSavedAudienceDetail({ audienceId: id })
            .then((result) => {
                const payload = result?.payloadJson ? JSON.parse(result.payloadJson) : null;
                this.savedReviewAudienceId = id;
                this.savedReviewModalName = result?.name || 'Saved Audience';
                this.savedReviewModalItems = (payload?.items && Array.isArray(payload.items)) ? payload.items : [];
                this.savedReviewGroup1Expanded = true;
                this.savedReviewGroupsAddedExpanded = true;
                this.showSavedReviewModal = true;
                // Replace stored (possibly stale) per-item counts with live ones from the same engine
                // the list and the builder use, so the review counts match everywhere.
                this.refreshSavedReviewCounts(result?.payloadJson);
            })
            .catch((e) => {
                console.warn('Failed to load saved audience', e);
            });
    }

    async refreshSavedReviewCounts(payloadJson) {
        const items = Array.isArray(this.savedReviewModalItems) ? this.savedReviewModalItems : [];
        if (!payloadJson || items.length === 0) {
            return;
        }
        try {
            const results = await getAudienceCounts({ payloadJson });
            const countsById = new Map();
            (results || []).forEach((row) => {
                if (row && row.id) {
                    countsById.set(row.id, row.count);
                }
            });
            this.savedReviewModalItems = items.map((item) =>
                countsById.has(item.id) ? { ...item, memberCount: countsById.get(item.id) } : item
            );
        } catch (e) {
            // Keep stored values if the live count can't be fetched.
            console.warn('Failed to refresh saved audience review counts', e);
        }
    }

    closeSavedReviewModal() {
        this.showSavedReviewModal = false;
        this.savedReviewModalItems = [];
        this.savedReviewModalName = '';
        this.savedReviewAudienceId = null;
        this.savedReviewGroup1Expanded = true;
        this.savedReviewGroupsAddedExpanded = true;
    }

    handleToggleSavedReviewGroup1() {
        this.savedReviewGroup1Expanded = !this.savedReviewGroup1Expanded;
    }

    handleToggleSavedReviewGroupsAdded() {
        this.savedReviewGroupsAddedExpanded = !this.savedReviewGroupsAddedExpanded;
    }

    handleAddSavedAudienceFromModal() {
        const audienceId = this.savedReviewAudienceId;
        const name = this.savedReviewModalName;
        const items = Array.isArray(this.savedReviewModalItems) ? this.savedReviewModalItems : [];

        this.dispatchEvent(new CustomEvent('audienceadded', {
            detail: { audienceId, name, items }
        }));

        if (audienceId) {
            activateSavedAudience({ audienceId }).catch((e) => {
                console.warn('Activate saved audience failed', e);
            });
        }

        this.closeSavedReviewModal();
        this.loadSavedAudiences(this.savedAudienceSearchTerm || '');
    }
}