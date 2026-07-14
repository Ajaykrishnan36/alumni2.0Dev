/**
 * Target Audience Selection builder.
 * -------------------------------------------------------
 * - Left nav: Role & Details, Groups, Specific Individuals, Saved Audience
 * - Every add action (All-role, custom filter audience, group, individual, saved audience)
 *   only mutates the LOCAL selection and shows it in the right panel.
 * - The WHOLE selection is persisted as ONE Ken_Segmentation__c only when the user clicks
 *   the right-panel Save button (or the wizard auto-saves an already-named selection on Next).
 * - Saving goes through KenAudienceJunctionController.saveSegmentationForParent, which
 *   reuses/updates a segmentation owned by this record and forks a copy when the
 *   segmentation is shared with other records (or was picked from Saved Audience and edited).
 */
import { LightningElement, wire, api } from 'lwc';
import getRoleFieldOptions from '@salesforce/apex/KenAudienceEngineService.getRoleFieldOptions';
import searchSpecificIndividuals from '@salesforce/apex/KenAudienceEngineService.searchSpecificIndividuals';
import saveSegmentationForParent from '@salesforce/apex/KenAudienceJunctionController.saveSegmentationForParent';
import linkSegmentationToParent from '@salesforce/apex/KenAudienceJunctionController.linkSegmentationToParent';
import getLinkedSegmentation from '@salesforce/apex/KenAudienceJunctionController.getLinkedSegmentation';
import getAudienceCounts from '@salesforce/apex/KenAudienceEngineService.getAudienceCounts';
import searchSavedAudiences from '@salesforce/apex/KenAudienceEngineService.searchSavedAudiences';
import getSavedAudienceDetail from '@salesforce/apex/KenAudienceEngineService.getSavedAudienceDetail';
import activateSavedAudience from '@salesforce/apex/KenAudienceEngineService.activateSavedAudience';
import getSavedGroupsForRole from '@salesforce/apex/KenAudienceEngineService.getSavedGroupsForRole';
import getActiveRoleCategories from '@salesforce/apex/KenAudienceEngineService.getActiveRoleCategories';
import searchDistinctFieldValues from '@salesforce/apex/KenAudienceEngineService.searchDistinctFieldValues';
import searchAudienceGroups from '@salesforce/apex/KenAudienceEngineService.searchAudienceGroups';

const NAV = {
    ROLE_DETAILS: 'ROLE_DETAILS',
    GROUPS: 'GROUPS',
    INDIVIDUALS: 'INDIVIDUALS',
    SAVED: 'SAVED'
};

const INDIVIDUAL_FILTERS = [
    { key: 'program', label: 'Degree / Program', placeholder: 'Choose' },
    { key: 'school', label: 'School', placeholder: 'Choose' },
    { key: 'department', label: 'Department', placeholder: 'Choose' },
    { key: 'campus', label: 'Campus', placeholder: 'Choose' }
];

const DEFAULT_INDIVIDUAL_OPTION_KEY_MAP = {
    program: 'program',
    school: 'school',
    department: 'department',
    campus: 'campus'
};

const INDIVIDUAL_OPTION_KEY_BY_ROLE = {
    STUDENT: DEFAULT_INDIVIDUAL_OPTION_KEY_MAP,
    STUDENTS: DEFAULT_INDIVIDUAL_OPTION_KEY_MAP,
    ALUMNI: DEFAULT_INDIVIDUAL_OPTION_KEY_MAP,
    PARENT: DEFAULT_INDIVIDUAL_OPTION_KEY_MAP,
    PARENTS: DEFAULT_INDIVIDUAL_OPTION_KEY_MAP,
    FACULTY: DEFAULT_INDIVIDUAL_OPTION_KEY_MAP,
    OTHERS: DEFAULT_INDIVIDUAL_OPTION_KEY_MAP
};

const INDIVIDUAL_ADVANCED_FIELD_API = {
    program: 'Program_Plan__r.LearningProgram.Name',
    school: 'Program_Plan__r.Provider.Name',
    campus: 'Program_Plan__r.Provider.Campus__c',
    department: 'Program_Plan__r.LearningProgram.Program_Stream__c'
};

function generateId(prefix) {
    return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
}

export default class KenTargetAudienceSelection extends LightningElement {
    @api parentObjectType;
    @api parentRecordId;
    _surveyId = null;
    _eventId = null;
    _groupId = null;
    _selectedAudience = [];
    navSection = NAV.ROLE_DETAILS;
    activeRole;
    individualsRole;
    roleOptions = [];
    roleLabelByValue = {};
    categoryRoles = [];
    individualsSearchTerm = '';
    showIndividualsAdvanced = false;
    individualsResults = [];
    individualsLoading = false;
    selectedIndividuals = {};
    groupsSearchTerm = '';
    selectedGroups = {};
    groupResults = [];
    groupsLoading = false;
    groupsSearchTimer;
    groupsLoaded = false;
    savedSearchTerm = '';
    savedAudiences = [];
    savedAudienceLoading = false;
    savedSearchTimer;
    showSavedModal = false;
    savedModalName = '';
    savedModalItems = [];
    savedAudienceId;
    _segmentationId = null;
    _segmentationName = '';
    _pickedExisting = false;
    _lastLinkedSegId = null;
    isDirty = false;
    isSaving = false;
    lastSaveError = null;
    segmentationNameInput = '';
    showSegmentationNameModal = false;
    showConfirmModal = false;
    confirmMessage = '';
    pendingAllRole;
    pendingAllLabel;
    confirmActionType;
    pendingCustomItem;
    pendingCustomIsEdit = false;
    individualsFilters = {
        program: [],
        school: [],
        department: [],
        campus: []
    };
    individualsSearchTimer;
    fieldSearchTimers = {};
    countsTimer;
    countsById = new Map();
    countsInFlight = false;
    // True only while refreshAudienceCounts writes its results back into selectedAudience, so the
    // setter does NOT schedule another refresh (which would loop: setter -> refresh -> setter -> …).
    _applyingCounts = false;

    /**
     * Holds state per role:
     * {
     *   mode: 'ALL'|'CUSTOM',
     *   customGroups: [],
     *   draftGroup: { id, displayName, selections },
     *   nextGroupNumber: 1,
     *   options: { [fieldKey]: [{label,value}] }
     * }
     */
    roleState = {};

    /** Selected audience (across roles). */
    @api
    get selectedAudience() {
        return this._selectedAudience;
    }
    set selectedAudience(val) {
        this._selectedAudience = this.normalizeSelectedAudience(val);
        this.hydrateToggleStateFromAudience();
        // Skip when this write is the count refresh applying its own results, otherwise the refresh
        // would re-trigger itself forever (one server call per cycle now that counts are not cached).
        if (!this._applyingCounts) {
            this.scheduleCountsRefresh();
        }
    }

    hydrateToggleStateFromAudience() {
        const items = Array.isArray(this._selectedAudience) ? this._selectedAudience : [];
        const nextIndividuals = {};
        const nextGroups = {};
        const customByRole = {};
        items.forEach((item) => {
            if (!item || !item.id) return;
            if (item.type === 'INDIVIDUAL') {
                nextIndividuals[item.id] = true;
            } else if (item.type === 'GROUP') {
                nextGroups[item.id] = true;
            } else if (item.type === 'CUSTOM' && item.role) {
                if (!customByRole[item.role]) customByRole[item.role] = [];
                customByRole[item.role].push(item);
            }
        });
        this.selectedIndividuals = nextIndividuals;
        this.selectedGroups = nextGroups;
        if (this.roleState && typeof this.roleState === 'object') {
            const nextRoleState = { ...this.roleState };
            Object.keys(customByRole).forEach((role) => {
                if (!nextRoleState[role]) {
                    nextRoleState[role] = {
                        mode: 'CUSTOM',
                        customGroups: [],
                        draftGroup: null,
                        nextGroupNumber: 1,
                        fields: [],
                        options: {},
                        hasAnyGroup: false
                    };
                }
                const existing = nextRoleState[role].customGroups || [];
                const byId = new Map(existing.map((g) => [g.id, g]));
                customByRole[role].forEach((g) => byId.set(g.id, g));
                nextRoleState[role].customGroups = Array.from(byId.values());
                nextRoleState[role].hasAnyGroup = nextRoleState[role].customGroups.length > 0;
                nextRoleState[role].mode = 'CUSTOM';
                nextRoleState[role].nextGroupNumber = nextRoleState[role].customGroups.length + 1;
            });
            this.roleState = nextRoleState;
        }
    }

    @api
    get surveyId() {
        return this._surveyId;
    }
    set surveyId(value) {
        this._surveyId = value;
    }

    @api
    get eventId() {
        return this._eventId;
    }
    set eventId(value) {
        this._eventId = value;
    }

    @api
    get groupId() {
        return this._groupId;
    }
    set groupId(value) {
        this._groupId = value;
    }

    @api
    get segmentationId() {
        return this._segmentationId;
    }
    set segmentationId(value) {
        const next = value || null;
        if (next === this._segmentationId) return;
        this._segmentationId = next;
        this._lastLinkedSegId = null;
    }

    @api
    get segmentationName() {
        return this._segmentationName;
    }
    set segmentationName(value) {
        this._segmentationName = value || '';
        if (this._segmentationName && !this.segmentationNameInput) {
            this.segmentationNameInput = this._segmentationName;
        }
    }

    /**
     * When true, the current segmentation-id was SELECTED from an existing saved audience
     * (rather than created by/for this record). If the user then edits, the save must FORK
     * into a brand-new segmentation and never mutate the shared original.
     */
    @api
    get pickedExisting() {
        return this._pickedExisting;
    }
    set pickedExisting(value) {
        this._pickedExisting = !!value;
    }

    /** Marks the local selection as modified since the last successful save. */
    markDirty() {
        this.isDirty = true;
    }

    /**
     * Dispatch event when selectedAudience changes
     */
    dispatchAudienceChange() {
        this.dispatchEvent(new CustomEvent('audiencechange', {
            detail: {
                selectedAudience: this.selectedAudience,
                segmentationId: this.segmentationId,
                segmentationName: this.segmentationName,
                isDirty: this.isDirty
            },
            bubbles: true,
            composed: true
        }));
    }

    popup = { visible: false, message: '', variant: 'success' };
    popupTimer;

    connectedCallback() {
    }

    @wire(getActiveRoleCategories)
    wiredCategoryRoles({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.warn('Failed to load active AttributeCategory roles', error);
        }
        this.categoryRoles = Array.isArray(data) ? data : [];
        const roles = (this.categoryRoles || []).map((c) => ({
            value: c.code,
            label: c.name
        }));
        this.applyRoleOptions(roles);
    }

    applyRoleOptions(roles) {
        const deduped = [];
        const seen = new Set();
        (roles || []).forEach((r) => {
            if (!r || !r.value || seen.has(r.value)) {
                return;
            }
            seen.add(r.value);
            deduped.push(r);
        });

        if (!deduped.length) {
            this.roleOptions = [];
            this.roleLabelByValue = {};
            return;
        }

        this.roleOptions = deduped;
        const labels = {};
        this.roleOptions.forEach((r) => {
            labels[r.value] = r.label;
        });
        this.roleLabelByValue = labels;

        const nextState = { ...this.roleState };
        this.roleOptions.forEach((r) => {
            if (!nextState[r.value]) {
                nextState[r.value] = {
                    mode: 'ALL',
                    customGroups: [],
                    draftGroup: null,
                    nextGroupNumber: 1,
                    fields: [],
                    options: {},
                    hasAnyGroup: false
                };
            }
        });
        this.roleState = nextState;

        if (!this.activeRole || !this.roleState[this.activeRole]) {
            this.activeRole = this.roleOptions[0]?.value;
        }
        if (!this.individualsRole || !this.roleState[this.individualsRole]) {
            this.individualsRole = this.activeRole;
        }

        if (this.activeRole) {
            this.loadRoleOptions(this.activeRole);
        }
        if (this.individualsRole && this.individualsRole !== this.activeRole) {
            this.loadRoleOptions(this.individualsRole);
        }
    }

    formatRoleLabel(value) {
        if (!value) return '';
        const lower = String(value).toLowerCase();
        if (lower === 'org') return 'Organisation';
        return lower.charAt(0).toUpperCase() + lower.slice(1);
    }

    // Single source of truth for any member-count label. Whenever a numeric count exists it
    // wins — stored strings (stale saved-payload labels, "Calculating…") are never used as a
    // count. Returns null when there is no numeric count, so callers can fall back to a subtitle.
    memberCountLabel(count, capitalized) {
        const n = Number.isFinite(count) ? count : null;
        if (n === null) {
            return null;
        }
        const unit = capitalized ? 'Member' : 'member';
        return n === 1 ? `1 ${unit}` : `${n} ${unit}s`;
    }

    formatMembersLabel(item) {
        const fromCount = this.memberCountLabel(item && item.memberCount, true);
        if (fromCount !== null) {
            return fromCount;
        }
        if (item && item.membersLabel && String(item.membersLabel).trim()) {
            return item.membersLabel;
        }
        return 'Audience';
    }

    normalizeSelectedAudience(val) {
        const arr = Array.isArray(val) ? val : [];
        return arr.map((item) => ({
            ...item,
            membersLabel: this.formatMembersLabel(item)
        }));
    }

    // -----------------------------
    // Computed helpers
    // -----------------------------
    get isRoleDetails() {
        return this.navSection === NAV.ROLE_DETAILS;
    }
    get isGroups() {
        return this.navSection === NAV.GROUPS;
    }
    get isIndividuals() {
        return this.navSection === NAV.INDIVIDUALS;
    }
    get isSaved() {
        return this.navSection === NAV.SAVED;
    }

    get activeRoleLabel() {
        return this.roleLabelByValue[this.activeRole] || this.formatRoleLabel(this.activeRole);
    }
    get activeRoleLabelLower() {
        return (this.roleLabelByValue[this.activeRole] || this.formatRoleLabel(this.activeRole) || '').toLowerCase();
    }

    get isAllMode() {
        const st = this.roleState[this.activeRole];
        return st ? st.mode === 'ALL' : false;
    }
    get isCustomMode() {
        const st = this.roleState[this.activeRole];
        return st ? st.mode === 'CUSTOM' : false;
    }

    get allCardClass() {
        return this.isAllMode ? 'modeCard modeCardActive' : 'modeCard';
    }
    get customCardClass() {
        return this.isCustomMode ? 'modeCard modeCardActive' : 'modeCard';
    }

    get allRadioClass() {
        return this.isAllMode ? 'modeRadio modeRadioChecked' : 'modeRadio';
    }
    get customRadioClass() {
        return this.isCustomMode ? 'modeRadio modeRadioChecked' : 'modeRadio';
    }

    get rolesForPills() {
        // Count selected audience items per role (All + custom).
        const counts = {};
        (this.selectedAudience || []).forEach((i) => {
            counts[i.role] = (counts[i.role] || 0) + 1;
        });

        return (this.roleOptions || []).map((r) => ({
            label: r.label,
            value: r.value,
            count: counts[r.value] || 0
        }));
    }

    get draftGroup() {
        return this.roleState[this.activeRole].draftGroup;
    }

    get savedGroupsForRole() {
        return this.roleState[this.activeRole].customGroups;
    }

    get showAddAnotherForRole() {
        const st = this.roleState[this.activeRole];
        return st ? (st.mode === 'CUSTOM' && !st.draftGroup) : false;
    }

    get hasAnyGroupForRole() {
        const st = this.roleState[this.activeRole];
        return !!st.hasAnyGroup;
    }

    get fieldConfigForRole() {
        const st = this.roleState[this.activeRole];
        return st ? (st.fields || []) : [];
    }

    get individualRoleTabs() {
        return (this.roleOptions || []).map((role) => ({
            value: role.value,
            label: role.label,
            className: role.value === this.individualsRole ? 'roleTab roleTabActive' : 'roleTab'
        }));
    }

    get individualsAdvancedLabel() {
        return this.showIndividualsAdvanced ? 'Hide advanced filters' : 'Show advanced filters';
    }

    get individualFiltersForUi() {
        const st = this.roleState[this.individualsRole] || {};
        const options = st.options || {};
        const keyMap = INDIVIDUAL_OPTION_KEY_BY_ROLE[this.individualsRole] || DEFAULT_INDIVIDUAL_OPTION_KEY_MAP;
        return INDIVIDUAL_FILTERS.map((f) => ({
            ...f,
            options: options[keyMap[f.key]] || [],
            value: this.individualsFilters[f.key] || []
        }));
    }

    get hasIndividualsResults() {
        return Array.isArray(this.individualsResults) && this.individualsResults.length > 0;
    }

    get showIndividualsEmptyState() {
        const hasSearch = !!(this.individualsSearchTerm && this.individualsSearchTerm.trim());
        const hasFilters = Object.values(this.individualsFilters || {}).some(
            (values) => Array.isArray(values) && values.length > 0
        );
        return !this.hasIndividualsResults && !this.individualsLoading && !hasSearch && !hasFilters;
    }

    get individualResultsWithState() {
        return (this.individualsResults || []).map((row) => {
            const selected = !!this.selectedIndividuals[row.id];
            return {
                ...row,
                selected,
                actionIcon: selected ? 'utility:check' : 'utility:add',
                actionClass: selected ? 'selectButton selectButtonSelected' : 'selectButton',
                roleLabel: this.roleLabelByValue[this.individualsRole] || this.formatRoleLabel(this.individualsRole) || row.roleLabel
            };
        });
    }

    get hasGroupResults() {
        return Array.isArray(this.groupResults) && this.groupResults.length > 0;
    }

    get showGroupsEmptyState() {
        return !this.hasGroupResults && !this.groupsLoading && this.groupsLoaded;
    }

    get groupResultsWithState() {
        return (this.groupResults || []).map((group) => {
            const selected = !!this.selectedGroups[group.id];
            const label = this.memberCountLabel(group.memberCount, false) || group.membersLabel || '0 members';
            return {
                ...group,
                selected,
                membersLabel: label,
                actionIcon: selected ? 'utility:check' : 'utility:add',
                actionClass: selected ? 'selectButton selectButtonSelected' : 'selectButton'
            };
        });
    }

    get hasSavedAudiences() {
        return Array.isArray(this.savedAudiences) && this.savedAudiences.length > 0;
    }

    get showSavedEmptyState() {
        return !this.hasSavedAudiences && !!(this.savedSearchTerm && this.savedSearchTerm.trim());
    }

    get savedModalGroups() {
        return (this.savedModalItems || [])
            .filter((item) => item.type === 'GROUP')
            .map((item) => ({
                ...item,
                membersLabel: this.memberCountLabel(item.memberCount, false) || item.membersLabel || '0 members'
            }));
    }

    get savedModalIndividuals() {
        return (this.savedModalItems || []).filter((item) => item.type === 'INDIVIDUAL');
    }

    get savedModalCustomGroups() {
        return (this.savedModalItems || [])
            .filter((item) => item.type === 'CUSTOM')
            .map((item) => ({
                ...item,
                membersLabel: this.memberCountLabel(item.memberCount, false) || item.membersLabel || '0 members'
            }));
    }

    get hasSavedModalGroups() {
        return this.savedModalGroups.length > 0;
    }

    get hasSavedModalIndividuals() {
        return this.savedModalIndividuals.length > 0;
    }

    get hasSavedModalCustomGroups() {
        return this.savedModalCustomGroups.length > 0;
    }

    // -----------------------------
    // Navigation + role switching
    // -----------------------------
    handleNavChange(event) {
        this.navSection = event.detail.value;
        if (this.isGroups && !this.groupsLoaded && !this.groupsLoading) {
            this.runGroupsSearch();
        }
    }

    handleRoleChange(event) {
        this.activeRole = event.detail.value;
        this.loadRoleOptions(this.activeRole);

        // Ensure draft exists for new role if in custom mode and no groups exist yet.
        const st = this.roleState[this.activeRole];
        if (st && st.mode === 'CUSTOM' && st.customGroups.length === 0 && !st.draftGroup) {
            st.nextGroupNumber = 1;
        }
    }

    handleIndividualsRoleChange(event) {
        const nextRole = event.currentTarget.dataset.value;
        if (!nextRole || nextRole === this.individualsRole) {
            return;
        }
        this.individualsRole = nextRole;
        this.individualsFilters = {
            program: [],
            school: [],
            department: [],
            campus: []
        };
        this.loadRoleOptions(this.individualsRole);
        this.runIndividualsSearch();
    }

    handleIndividualsSearchInput(event) {
        this.individualsSearchTerm = event.target.value;
        this.scheduleIndividualsSearch();
    }

    handleGroupsSearchInput(event) {
        this.groupsSearchTerm = event.target.value;
        if (this.groupsSearchTimer) {
            clearTimeout(this.groupsSearchTimer);
        }
        this.groupsSearchTimer = setTimeout(() => {
            this.runGroupsSearch();
        }, 300);
    }

    async runGroupsSearch() {
        this.groupsLoading = true;
        try {
            const results = await searchAudienceGroups({
                searchTerm: this.groupsSearchTerm || '',
                limitSize: 50
            });
            this.groupResults = Array.isArray(results) ? results : [];
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Group search failed', e);
            this.groupResults = [];
        } finally {
            this.groupsLoading = false;
            this.groupsLoaded = true;
        }
    }

    handleSavedSearchInput(event) {
        this.savedSearchTerm = event.target.value;
        if (this.savedSearchTimer) {
            clearTimeout(this.savedSearchTimer);
        }
        this.savedSearchTimer = setTimeout(() => {
            this.loadSavedAudiences(this.savedSearchTerm);
        }, 300);
    }

    handleIndividualsFilterChange(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.detail ? event.detail.value : [];
        this.individualsFilters = {
            ...this.individualsFilters,
            [key]: Array.isArray(value) ? value : []
        };
        this.scheduleIndividualsSearch();
    }

    toggleIndividualsAdvanced() {
        this.showIndividualsAdvanced = !this.showIndividualsAdvanced;
    }

    selectAllMode = () => {
        const st = this.roleState[this.activeRole];
        if (st) {
            st.mode = 'ALL';
            this.roleState = { ...this.roleState };
        }
    };

    selectCustomMode = () => {
        const st = this.roleState[this.activeRole];
        if (!st) {
            return;
        }
        st.mode = 'CUSTOM';

        if (!st.draftGroup && st.customGroups.length === 0) {
            st.nextGroupNumber = 1;
        }
        this.roleState = { ...this.roleState };
    };

    // -----------------------------
    // Option loading (Apex)
    // -----------------------------
    async loadRoleOptions(role) {
        try {
            const result = await getRoleFieldOptions({ role });
            const fields = Array.isArray(result) ? result : [];
            const options = {};
            fields.forEach((f) => {
                options[f.key] = f.options || [];
            });
            const individualOptions = await this.loadIndividualAdvancedFilterOptions();
            this.roleState[role].fields = fields;
            this.roleState[role].options = { ...options, ...individualOptions };
            this.roleState = { ...this.roleState };
        } catch (e) {
            // Keep UI usable if metadata isn't configured yet.
            // Options will be empty; multiSelectPicklist will show no results.
            // eslint-disable-next-line no-console
            console.warn('Failed to load role options, using empty lists', e);
            this.roleState[role].fields = [];
            this.roleState[role].options = {};
            this.roleState = { ...this.roleState };
        }
    }

    async loadIndividualAdvancedFilterOptions() {
        const result = {};
        const entries = Object.entries(INDIVIDUAL_ADVANCED_FIELD_API);
        const responses = await Promise.all(
            entries.map(async ([key, fieldApi]) => {
                try {
                    const rows = await searchDistinctFieldValues({
                        objectApi: 'ConstituentRole',
                        fieldApi,
                        searchTerm: '',
                        limitSize: 200
                    });
                    return [key, Array.isArray(rows) ? rows : []];
                } catch (e) {
                    return [key, []];
                }
            })
        );
        responses.forEach(([key, rows]) => {
            const opts = [];
            const seen = new Set();
            rows.forEach((r) => {
                const value = r && r.value ? r.value : null;
                if (!value || seen.has(value)) return;
                seen.add(value);
                opts.push({ value, label: r.label || value });
            });
            result[key] = opts;
        });
        return result;
    }

    // -----------------------------
    // Custom group flows
    // -----------------------------
    handleDraftChange(event) {
        const { key, value } = event.detail;
        const st = this.roleState[this.activeRole];
        const draft = st.draftGroup;
        if (!draft) {
            return;
        }
        draft.selections = { ...(draft.selections || {}), [key]: value };
        // Trigger reactivity by re-assigning.
        st.draftGroup = { ...draft };
        this.roleState = { ...this.roleState };
    }

    handleFieldSearch(event) {
        const { key, value } = event.detail || {};
        const role = this.activeRole;
        const st = this.roleState[role];
        if (!st || !key) {
            return;
        }

        const field = (st.fields || []).find((f) => f.key === key);
        if (!field || !field.fieldApi || !field.objectApi) {
            return;
        }

        const timerKey = `${role}::${key}`;
        if (this.fieldSearchTimers[timerKey]) {
            clearTimeout(this.fieldSearchTimers[timerKey]);
        }

        this.fieldSearchTimers[timerKey] = setTimeout(async () => {
            try {
                const results = await searchDistinctFieldValues({
                    objectApi: field.objectApi,
                    fieldApi: field.fieldApi,
                    searchTerm: value,
                    limitSize: 50
                });
                const selected = (st.draftGroup && st.draftGroup.selections && st.draftGroup.selections[key]) || [];
                const selectedValues = Array.isArray(selected) ? selected : (selected ? [selected] : []);
                const merged = [];
                const seen = new Set();

                (results || []).forEach((opt) => {
                    if (!opt || !opt.value || seen.has(opt.value)) {
                        return;
                    }
                    seen.add(opt.value);
                    merged.push({ label: opt.label || opt.value, value: opt.value });
                });

                selectedValues.forEach((val) => {
                    if (!val || seen.has(val)) {
                        return;
                    }
                    seen.add(val);
                    merged.push({ label: val, value: val });
                });

                st.fields = (st.fields || []).map((f) => (f.key === key ? { ...f, options: merged } : f));
                this.roleState = { ...this.roleState };
            } catch (e) {
                // eslint-disable-next-line no-console
                console.warn('Field search failed', e);
            }
        }, 250);
    }

    async handleSaveGroup() {
        const st = this.roleState[this.activeRole];
        const draft = st.draftGroup;
        if (!draft) {
            return;
        }

        const criteria = this.buildCriteriaForRole(this.activeRole, draft.selections);
        if (criteria.length === 0) {
            this.toast('Please select at least one criterion before adding to audience.', 'error');
            return;
        }

        const isEdit = !!draft.editingId;
        const existing = isEdit ? (st.customGroups || []).find((g) => g.id === draft.editingId) : null;
        const groupName = (existing && existing.title) || draft.displayName || this.buildDefaultGroupTitle(this.activeRole, st);

        const groupItem = {
            id: isEdit ? draft.editingId : generateId('aud'),
            role: this.activeRole,
            roleLabel: this.activeRoleLabel,
            title: groupName,
            type: 'CUSTOM',
            memberCount: null,
            membersLabel: 'Calculating...',
            criteria
        };

        const existingAll = (this.selectedAudience || []).find(
            (i) => i.role === this.activeRole && i.type === 'ALL'
        );
        if (existingAll) {
            this.confirmMessage = `All ${this.activeRoleLabel} will be removed. Continue?`;
            this.confirmActionType = 'ADD_CUSTOM';
            this.pendingCustomItem = groupItem;
            this.pendingCustomIsEdit = isEdit;
            this.showConfirmModal = true;
            return;
        }

        await this.proceedWithCustomSave(groupItem, isEdit);
    }

    proceedWithCustomSave(groupItem, isEdit) {
        const st = this.roleState[groupItem.role];
        if (!st) {
            return;
        }
        this.markDirty();
        this.applyGroupSave(st, groupItem, isEdit);
        this.toast(`${groupItem.title} added to audience`, 'success');
    }

    handleAddAnotherGroup() {
        const st = this.roleState[this.activeRole];
        const nextNum = st.nextGroupNumber || (st.customGroups.length + 1);
        st.draftGroup = this.createDraftGroup(this.activeRole, nextNum);
        this.roleState = { ...this.roleState };
    }

    handleEditGroup(event) {
        const id = event.detail.id;
        const st = this.roleState[this.activeRole];
        const existing = (st.customGroups || []).find((g) => g.id === id);
        if (!existing) {
            return;
        }

        // Convert criteria back into selections map.
        const selections = {};
        (existing.criteria || []).forEach((c) => {
            selections[c.key] = c.values;
        });

        st.draftGroup = {
            id: generateId('draft'),
            editingId: existing.id,
            displayName: existing.title,
            selections
        };
        this.roleState = { ...this.roleState };
    }

    handleDeleteGroup(event) {
        const id = event.detail.id;
        if (!id) {
            return;
        }
        const st = this.roleState[this.activeRole];
        st.customGroups = (st.customGroups || []).filter((g) => g.id !== id);
        this.selectedAudience = (this.selectedAudience || []).filter((g) => g.id !== id);
        this.markDirty();
        if (st.customGroups.length === 0 && st.mode === 'CUSTOM' && !st.draftGroup) {
            st.nextGroupNumber = 1;
        }
        if (st.customGroups.length === 0 && !st.hasAnyGroup) {
            st.hasAnyGroup = false;
        }
        this.roleState = { ...this.roleState };
        this.renumberCustomGroups(this.activeRole);
        this.toast('Audience removed.', 'success');
    }

    createDraftGroup(role, index) {
        return {
            id: generateId('draft'),
            displayName: this.buildDefaultGroupTitle(role, { nextGroupNumber: index }),
            selections: {}
        };
    }

    buildCriteriaForRole(role, selections) {
        const st = this.roleState[role] || {};
        const fields = st.fields || [];
        return fields
            .map((f) => {
            const raw = selections ? selections[f.key] : null;
            let values = [];
            if (Array.isArray(raw)) {
                values = raw;
            } else if (raw) {
                values = [String(raw)];
            }
            return { key: f.key, label: f.label, fieldApi: f.fieldApi, objectApi: f.objectApi, joinField: f.joinField, values };
        })
            .filter((c) => Array.isArray(c.values) && c.values.length > 0);
    }

    // -----------------------------
    // "All" flow
    // -----------------------------
    handleAddAllToAudience(event) {
        event.preventDefault();
        event.stopPropagation();
        const role = this.activeRole;
        const existingAll = (this.selectedAudience || []).find((i) => i.role === role && i.type === 'ALL');
        const existingForRole = (this.selectedAudience || []).filter(
            (i) => i.role === role && i.type !== 'ALL'
        );
        if (existingAll && existingForRole.length === 0) {
            this.toast(`All ${this.activeRoleLabel} is already added.`, 'info');
            return;
        }
        if (existingForRole.length > 0) {
            this.confirmMessage = `Existing ${this.activeRoleLabel} audiences will be removed. Continue?`;
            this.pendingAllRole = role;
            this.pendingAllLabel = this.activeRoleLabel;
            this.showConfirmModal = true;
            return;
        }

        this.addAllForRole(role, this.activeRoleLabel);
    }

    // -----------------------------
    // Right panel remove
    // -----------------------------
    handleRemoveSelected(event) {
        const id = event.detail.id;
        const removed = (this.selectedAudience || []).find((i) => i.id === id);
        this.selectedAudience = (this.selectedAudience || []).filter((i) => i.id !== id);
        this.markDirty();
        this.dispatchAudienceChange();

        // If it was a saved custom group, remove from saved list too.
        if (removed && removed.type === 'CUSTOM') {
            const st = this.roleState[removed.role];
            st.customGroups = (st.customGroups || []).filter((g) => g.id !== id);
            // If user removed the only saved group and mode is CUSTOM, ensure draft group exists.
            if (st.customGroups.length === 0 && st.mode === 'CUSTOM' && !st.draftGroup) {
                st.nextGroupNumber = 1;
            }
            this.roleState = { ...this.roleState };
            this.renumberCustomGroups(removed.role);
        }
        if (removed) {
            if (this.selectedIndividuals[removed.id]) {
                const next = { ...this.selectedIndividuals };
                delete next[removed.id];
                this.selectedIndividuals = next;
            }
            if (this.selectedGroups[removed.id]) {
                const nextGroups = { ...this.selectedGroups };
                delete nextGroups[removed.id];
                this.selectedGroups = nextGroups;
            }
            this.toast(`${removed.title} removed.`, 'success');
        }
        this.scheduleCountsRefresh();
    }

    handleSegmentationNameInput(event) {
        this.segmentationNameInput = event.detail ? event.detail.value : '';
        this.clearSegmentationNameError();
    }

    closeSegmentationNameModal() {
        this.showSegmentationNameModal = false;
        this.segmentationNameInput = this.segmentationName || '';
    }

    async confirmSegmentationName() {
        this.clearSegmentationNameError();
        const name = (this.segmentationNameInput || '').trim();
        if (!name) {
            this.setSegmentationNameError('Audience name is required.');
            this.toast('Please enter an audience name.', 'error');
            return;
        }

        const saved = await this.doPersist(name);
        if (!saved) {
            const message = this.lastSaveError || 'Failed to save audience.';
            this.setSegmentationNameError(message);
            return;
        }
        this.showSegmentationNameModal = false;
    }

    clearSegmentationNameError() {
        const input = this.template.querySelector('lightning-input[data-id="segmentationName"]');
        if (input) {
            input.setCustomValidity('');
            input.reportValidity();
        }
    }

    setSegmentationNameError(message) {
        const input = this.template.querySelector('lightning-input[data-id="segmentationName"]');
        if (input) {
            input.setCustomValidity(message || 'Segmentation name is invalid.');
            input.reportValidity();
        }
    }

    closeConfirmModal() {
        this.showConfirmModal = false;
        this.confirmMessage = '';
        this.pendingAllRole = null;
        this.pendingAllLabel = null;
        this.confirmActionType = null;
        this.pendingCustomItem = null;
        this.pendingCustomIsEdit = false;
    }

    confirmAddAll() {
        const role = this.pendingAllRole;
        const label = this.pendingAllLabel;
        if (!role) {
            this.closeConfirmModal();
            return;
        }

        const existingForRole = (this.selectedAudience || []).filter(
            (i) => i.role === role && i.type !== 'ALL'
        );
        const removeIds = new Set(existingForRole.map((i) => i.id));
        this.selectedAudience = (this.selectedAudience || []).filter((i) => !removeIds.has(i.id) && i.role !== role);
        const nextIndividuals = { ...this.selectedIndividuals };
        removeIds.forEach((id) => {
            if (nextIndividuals[id]) {
                delete nextIndividuals[id];
            }
        });
        this.selectedIndividuals = nextIndividuals;

        const st = this.roleState[role];
        if (st) {
            st.customGroups = [];
            st.draftGroup = null;
            st.nextGroupNumber = 1;
            st.hasAnyGroup = false;
            this.roleState = { ...this.roleState };
        }

        this.addAllForRole(role, label);
        this.closeConfirmModal();
    }

    confirmAddCustom() {
        const item = this.pendingCustomItem;
        const isEdit = this.pendingCustomIsEdit;
        if (!item) {
            this.closeConfirmModal();
            return;
        }
        const role = item.role;
        this.selectedAudience = (this.selectedAudience || []).filter(
            (i) => !(i.role === role && i.type === 'ALL')
        );
        const st = this.roleState[role];
        if (st) {
            st.hasAnyGroup = st.customGroups.length > 0 || st.hasAnyGroup;
            this.roleState = { ...this.roleState };
        }
        this.closeConfirmModal();
        this.proceedWithCustomSave(item, isEdit);
    }

    confirmModalProceed() {
        if (this.confirmActionType === 'ADD_CUSTOM') {
            this.confirmAddCustom();
            return;
        }
        this.confirmAddAll();
    }

    addAllForRole(role, label) {
        const item = {
            id: generateId('all'),
            role: role,
            roleLabel: label,
            title: `All ${label}`,
            type: 'ALL',
            memberCount: null,
            membersLabel: 'Calculating...',
            criteria: []
        };
        this.selectedAudience = [...(this.selectedAudience || []), item];
        this.markDirty();
        this.dispatchAudienceChange();
        this.toast(`All ${label} added to audience`, 'success');
        this.scheduleCountsRefresh();
        this.pendingAllRole = null;
        this.pendingAllLabel = null;
    }

    handleToggleIndividual(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        const row = (this.individualsResults || []).find((item) => item.id === id);
        if (!row) {
            return;
        }

        if (this.selectedIndividuals[id]) {
            this.selectedAudience = (this.selectedAudience || []).filter((item) => item.id !== id);
            this.markDirty();
            this.dispatchAudienceChange();
            const next = { ...this.selectedIndividuals };
            delete next[id];
            this.selectedIndividuals = next;
            this.scheduleCountsRefresh();
            return;
        }

        const item = {
            id: row.id,
            role: this.individualsRole,
            roleLabel: this.roleLabelByValue[this.individualsRole] || this.formatRoleLabel(this.individualsRole),
            title: row.name,
            type: 'INDIVIDUAL',
            membersLabel: row.email || row.phone || 'Individual',
            email: row.email,
            phone: row.phone,
            criteria: []
        };
        this.selectedAudience = [...(this.selectedAudience || []), item];
        this.markDirty();
        this.dispatchAudienceChange();
        this.selectedIndividuals = { ...this.selectedIndividuals, [id]: true };
        this.scheduleCountsRefresh();
        this.toast(`${row.name} added to audience`, 'success');
    }

    handleToggleGroup(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        const group = (this.groupResults || []).find((item) => item.id === id);
        if (!group) {
            return;
        }

        if (this.selectedGroups[id]) {
            this.selectedAudience = (this.selectedAudience || []).filter((item) => item.id !== id);
            this.markDirty();
            this.dispatchAudienceChange();
            const next = { ...this.selectedGroups };
            delete next[id];
            this.selectedGroups = next;
            this.scheduleCountsRefresh();
            return;
        }

        const members = Number.isFinite(group.memberCount) ? group.memberCount : 0;
        const item = {
            id: group.id,
            role: 'GROUPS',
            roleLabel: 'Groups',
            title: group.name,
            type: 'GROUP',
            memberCount: members,
            membersLabel: group.membersLabel || (members === 1 ? '1 member' : `${members} members`),
            criteria: []
        };
        this.selectedAudience = [...(this.selectedAudience || []), item];
        this.markDirty();
        this.dispatchAudienceChange();
        this.selectedGroups = { ...this.selectedGroups, [id]: true };
        this.scheduleCountsRefresh();
        this.toast(`${group.name} added to audience`, 'success');
    }

    handleReviewSavedAudience(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        getSavedAudienceDetail({ audienceId: id })
            .then((result) => {
                const payload = result && result.payloadJson ? JSON.parse(result.payloadJson) : null;
                this.savedAudienceId = id;
                this.savedModalName = result ? result.name : 'Saved Audience';
                this.savedModalItems = payload && Array.isArray(payload.items) ? payload.items : [];
                this.showSavedModal = true;
                // Replace the stored (possibly stale) per-item counts with live ones from the same
                // engine the list and Selected Audience use, so review-before-add always matches.
                this.refreshSavedModalCounts(result ? result.payloadJson : null);
            })
            .catch((e) => {
                // eslint-disable-next-line no-console
                console.warn('Failed to load saved audience', e);
                this.toast('Failed to load saved audience.', 'error');
            });
    }

    async refreshSavedModalCounts(payloadJson) {
        const items = Array.isArray(this.savedModalItems) ? this.savedModalItems : [];
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
            this.savedModalItems = items.map((item) =>
                countsById.has(item.id) ? { ...item, memberCount: countsById.get(item.id) } : item
            );
        } catch (e) {
            // Keep stored values if the live count can't be fetched.
            // eslint-disable-next-line no-console
            console.warn('Failed to refresh saved audience counts', e);
        }
    }

    closeSavedModal() {
        this.showSavedModal = false;
        this.savedModalItems = [];
        this.savedModalName = '';
        this.savedAudienceId = null;
    }

    /**
     * Adds EVERY item of the reviewed saved audience to the local selection.
     * GROUP and INDIVIDUAL items must keep their ORIGINAL record ids — the count/SOQL
     * engine resolves them by id, so regenerating those ids breaks reach counting.
     * Only ALL/CUSTOM items get fresh local ids (their ids are UI-only).
     */
    expandSavedItems(items) {
        const existingIds = new Set((this.selectedAudience || []).map((i) => i.id));
        const added = [];
        const now = Date.now();
        (items || []).forEach((item, idx) => {
            const keepsRealId = item.type === 'GROUP' || item.type === 'INDIVIDUAL';
            const nextId = keepsRealId
                ? item.id
                : `saved_${item.id || item.title || 'item'}_${now}_${idx}`;
            if (existingIds.has(nextId)) {
                return;
            }
            existingIds.add(nextId);
            const nextItem = { ...item, id: nextId };
            added.push(nextItem);

            if (nextItem.type === 'INDIVIDUAL') {
                this.selectedIndividuals = { ...this.selectedIndividuals, [nextItem.id]: true };
            }
            if (nextItem.type === 'GROUP') {
                this.selectedGroups = { ...this.selectedGroups, [nextItem.id]: true };
            }
            if (nextItem.type === 'CUSTOM' && this.roleState[nextItem.role]) {
                const st = this.roleState[nextItem.role];
                st.customGroups = [...(st.customGroups || []), nextItem];
                st.hasAnyGroup = true;
                st.mode = 'CUSTOM';
                this.roleState = { ...this.roleState };
            }
        });
        return added;
    }

    handleAddSavedAudience() {
        const items = Array.isArray(this.savedModalItems) ? this.savedModalItems : [];
        const hadSelection = (this.selectedAudience || []).length > 0;
        const added = this.expandSavedItems(items);

        this.selectedAudience = [...(this.selectedAudience || []), ...added];

        const pickedId = this.savedAudienceId;
        if (pickedId && !hadSelection && !this.segmentationId) {
            // The picked saved audience becomes the base: REUSE its segmentation for the
            // junction link. Any later edit forks into a copy instead of mutating it.
            this.segmentationId = pickedId;
            this.segmentationName = this.savedModalName || this.segmentationName;
            this._pickedExisting = true;
            this.isDirty = false;
        } else if (added.length) {
            this.markDirty();
        }
        this.dispatchAudienceChange();

        if (pickedId) {
            activateSavedAudience({ audienceId: pickedId }).catch((e) => {
                // eslint-disable-next-line no-console
                console.warn('Failed to activate saved audience', e);
            });
        }
        this.toast('Saved audience added.', 'success');
        this.scheduleCountsRefresh();
        this.closeSavedModal();
    }

    scheduleIndividualsSearch() {
        if (this.individualsSearchTimer) {
            clearTimeout(this.individualsSearchTimer);
        }
        this.individualsSearchTimer = setTimeout(() => {
            this.runIndividualsSearch();
        }, 300);
    }

    async runIndividualsSearch() {
        const term = (this.individualsSearchTerm || '').trim();
        const hasFilters = Object.values(this.individualsFilters || {}).some(
            (values) => Array.isArray(values) && values.length > 0
        );

        if (!term && !hasFilters) {
            this.individualsResults = [];
            return;
        }

        this.individualsLoading = true;
        try {
            const results = await searchSpecificIndividuals({
                role: this.individualsRole,
                searchTerm: term,
                filters: this.individualsFilters,
                targetObject: 'ConstituentRole',
                limitSize: 20
            });
            this.individualsResults = Array.isArray(results) ? results : [];
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Search failed', e);
            this.individualsResults = [];
        } finally {
            this.individualsLoading = false;
        }
    }

    async loadSavedAudiences(searchTerm) {
        this.savedAudienceLoading = true;
        try {
            const results = await searchSavedAudiences({ searchTerm });
            this.savedAudiences = (results || []).map((aud) => ({
                ...aud,
                memberLabel: this.memberCountLabel(aud.memberCount, false) || 'Audience',
                roleBadges: (() => {
                    const badges = this.buildRoleBadgesFromPayload(aud.payloadJson);
                    return badges.length ? badges : null;
                })()
            }));
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Saved audience search failed', e);
            this.savedAudiences = [];
        } finally {
            this.savedAudienceLoading = false;
        }
    }

    async loadSavedGroupsForRole(role) {
        const st = this.roleState[role];
        if (!st) {
            return;
        }
        try {
            const groups = await getSavedGroupsForRole({ role });
            const existing = st.customGroups || [];
            const byId = new Map(existing.map((g) => [g.id, g]));
            (groups || []).forEach((g) => {
                if (!byId.has(g.id)) {
                    byId.set(g.id, {
                        ...g,
                        membersLabel: g.membersLabel || '0 members'
                    });
                }
            });
            st.customGroups = Array.from(byId.values());
            st.hasAnyGroup = st.customGroups.length > 0 || st.hasAnyGroup;
            this.roleState = { ...this.roleState };
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Failed to load saved groups', e);
        }
    }

    // -----------------------------
    // Toast helper
    // -----------------------------
    toast(message, variant) {
        const nextVariant = variant || 'info';
        if (this.popupTimer) {
            clearTimeout(this.popupTimer);
        }
        this.popup = {
            visible: true,
            message,
            variant: nextVariant
        };
        this.popupTimer = setTimeout(() => {
            this.popup = { ...this.popup, visible: false };
        }, 2000);
    }

    reduceError(err) {
        if (Array.isArray(err?.body)) {
            return err.body.map((e) => e.message).join(', ');
        }
        return err?.body?.message || err?.message || 'Unknown error';
    }

    buildDefaultGroupTitle(role, st) {
        const roleLabel = this.roleLabelByValue[role] || this.formatRoleLabel(role) || 'Audience';
        const nextNum = st?.nextGroupNumber || (st?.customGroups?.length + 1) || 1;
        return `${roleLabel} Audience ${nextNum}`;
    }

    /**
     * Keep custom audience titles per role sequential (Role Audience 1, 2, 3...).
     * Helpful when adding/removing so the UI doesn't show duplicate default names.
     */
    renumberCustomGroups(role) {
        const st = this.roleState[role];
        if (!st || !Array.isArray(st.customGroups)) {
            return;
        }

        const roleLabel = this.roleLabelByValue[role] || this.formatRoleLabel(role) || 'Audience';
        const renumbered = st.customGroups.map((g, idx) => ({
            ...g,
            title: `${roleLabel} Audience ${idx + 1}`
        }));

        st.customGroups = renumbered;
        st.nextGroupNumber = renumbered.length + 1;

        const byId = new Map(renumbered.map((g) => [g.id, g.title]));
        this.selectedAudience = (this.selectedAudience || []).map((item) => {
            if (item.role === role && item.type === 'CUSTOM' && byId.has(item.id)) {
                return { ...item, title: byId.get(item.id) };
            }
            return item;
        });

        this.roleState = { ...this.roleState };
        this.dispatchAudienceChange();
    }

    applyGroupSave(st, groupItem, isEdit) {
        if (isEdit) {
            st.customGroups = (st.customGroups || []).map((g) => (g.id === groupItem.id ? groupItem : g));
            this.selectedAudience = (this.selectedAudience || []).map((g) => (g.id === groupItem.id ? groupItem : g));
        } else {
            st.customGroups = [...(st.customGroups || []), groupItem];
            this.selectedAudience = [...(this.selectedAudience || []), groupItem];
            st.nextGroupNumber = (st.nextGroupNumber || 1) + 1;
        }
        this.dispatchAudienceChange();
        st.hasAnyGroup = true;
        st.draftGroup = null;
        this.roleState = { ...this.roleState };
        this.renumberCustomGroups(groupItem.role);
        this.scheduleCountsRefresh();
    }

    getRoleOrder(role) {
        const idx = (this.roleOptions || []).findIndex((r) => r.value === role);
        return idx === -1 ? null : idx + 1;
    }

    buildSegmentationPayload(extraItems) {
        const baseItems = Array.isArray(this.selectedAudience) ? this.selectedAudience : [];
        const items = [...baseItems, ...(extraItems || [])];
        const normalized = items.map((item, index) => ({
            id: item.id,
            role: item.role,
            roleLabel: item.roleLabel,
            order: this.getRoleOrder(item.role) || (index + 1),
            title: item.title,
            type: item.type,
            memberCount: (() => {
                const c = this.countsById?.get(item.id);
                if (Number.isInteger(c)) return c;
                if (Number.isInteger(item.memberCount)) return item.memberCount;
                return 0;
            })(),
            membersLabel: (() => {
                const c = this.countsById?.get(item.id);
                const finalCount = Number.isInteger(c) ? c : (Number.isInteger(item.memberCount) ? item.memberCount : 0);
                return finalCount === 1 ? '1 Member' : `${finalCount} Members`;
            })(),
            criteria: Array.isArray(item.criteria) ? item.criteria : []
        }));

        return JSON.stringify({
            name: this.segmentationName,
            updatedAt: new Date().toISOString(),
            logic: { audiences: 'AND', fields: 'AND', values: 'OR' },
            targetObject: 'ConstituentRole',
            items: normalized
        });
    }

    /**
     * Right-panel Save button: persist the WHOLE selection as one segmentation.
     * A brand-new selection needs a name first, so the name dialog opens; a known
     * segmentation saves directly (update-in-place or fork decided server-side).
     */
    handlePanelSave() {
        const items = this.selectedAudience || [];
        if (!items.length) {
            this.toast('Add at least one audience before saving.', 'info');
            return;
        }
        if (!this.segmentationId) {
            this.openSaveDialog();
            return;
        }
        this.doPersist();
    }

    /**
     * Persists the current selection as ONE segmentation via saveSegmentationForParent
     * (create / update-in-place / fork + junction link handled server-side).
     * Returns true on success.
     */
    async doPersist(nameOverride) {
        if (this.isSaving) {
            return false;
        }
        this.lastSaveError = null;
        this.isSaving = true;
        try {
            await this.ensureCountsUpToDate();
            if (nameOverride) {
                this.segmentationName = nameOverride;
            }
            const result = await saveSegmentationForParent({
                parentObjectType: this.resolvedParentType,
                parentId: this.resolvedParentId,
                segmentationId: this.segmentationId,
                audienceName: (nameOverride || this.segmentationName || '').trim(),
                payloadJson: this.buildSegmentationPayload(),
                forceFork: this._pickedExisting && this.isDirty
            });
            // The save itself succeeded server-side; if the returned id didn't survive
            // serialization, recover it from the junction rather than wiping state.
            let savedId = result && result.segmentationId ? result.segmentationId : null;
            if (!savedId && this.resolvedParentType && this.resolvedParentId) {
                try {
                    savedId = await getLinkedSegmentation({
                        parentObjectType: this.resolvedParentType,
                        parentId: this.resolvedParentId
                    });
                } catch (lookupErr) {
                    // eslint-disable-next-line no-console
                    console.warn('Failed to recover saved segmentation id', lookupErr);
                }
            }
            this.segmentationId = savedId || this.segmentationId;
            this.segmentationName = (result && result.name) || this.segmentationName;
            this.segmentationNameInput = this.segmentationName;
            if (this.resolvedParentId && this.segmentationId) {
                this._lastLinkedSegId = this.segmentationId;
            }
            this.isDirty = false;
            this._pickedExisting = false;
            this.dispatchAudienceChange();
            this.toast(
                result && result.forked
                    ? `Saved as new audience "${result.name}"`
                    : 'Audience saved successfully',
                'success'
            );
            this.loadSavedAudiences(this.savedSearchTerm);
            return true;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Save audience failed', e);
            this.lastSaveError = this.reduceError(e);
            this.toast(this.lastSaveError, 'error');
            return false;
        } finally {
            this.isSaving = false;
        }
    }

    get resolvedParentType() {
        if (this.parentObjectType) return this.parentObjectType;
        if (this._eventId) return 'Event';
        if (this._surveyId) return 'Survey';
        if (this._groupId) return 'Group';
        return null;
    }

    get resolvedParentId() {
        return this.parentRecordId || this._eventId || this._surveyId || this._groupId || null;
    }

    /**
     * Wizard "Next" hook. Saved & clean → just (re)ensure the junction link. Saved & edited →
     * auto-save the changes (forking if the segmentation is shared). Never saved → false so
     * the wizard blocks and opens the save dialog.
     */
    @api
    async persistCurrentSelection() {
        const items = this.selectedAudience || [];
        if (!items.length) {
            return false;
        }
        if (!this.segmentationId) {
            await this.recoverSegmentationFromParent();
        }
        if (!this.segmentationId) {
            return false;
        }
        if (this.isDirty) {
            return this.doPersist();
        }
        return this.ensureParentLink();
    }

    /**
     * Self-heal: the save can succeed server-side (segmentation + junction created) while
     * the client loses the returned id (serialization quirk, remount, stale state). If the
     * parent record already has a linked segmentation, adopt it instead of blocking.
     */
    async recoverSegmentationFromParent() {
        if (this.segmentationId) {
            return;
        }
        const parentType = this.resolvedParentType;
        const parentId = this.resolvedParentId;
        if (!parentType || !parentId) {
            return;
        }
        try {
            const segId = await getLinkedSegmentation({ parentObjectType: parentType, parentId });
            if (segId) {
                this.segmentationId = segId;
                this._lastLinkedSegId = segId;
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Failed to recover linked segmentation', e);
        }
    }

    async ensureParentLink() {
        if (!this.segmentationId) {
            await this.recoverSegmentationFromParent();
        }
        if (!this.segmentationId) {
            return false;
        }
        const parentType = this.resolvedParentType;
        const parentId = this.resolvedParentId;
        if (!parentType || !parentId) {
            return true;
        }
        if (this._lastLinkedSegId === this.segmentationId) {
            return true;
        }
        try {
            await linkSegmentationToParent({
                parentObjectType: parentType,
                parentId,
                segmentationId: this.segmentationId
            });
            this._lastLinkedSegId = this.segmentationId;
            return true;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Failed to link segmentation to parent', e);
            this.toast(this.reduceError(e), 'error');
            return false;
        }
    }

    /** True when the local selection has edits that are not yet saved to the segmentation. */
    @api
    get hasUnsavedChanges() {
        return !!this.isDirty;
    }

    /**
     * Wizard gate: a dirty selection must save successfully before the link is ensured,
     * so unsaved edits can never slip past the step and get lost on back-navigation.
     */
    @api
    async ensureSegmentationLink() {
        if (this.isDirty) {
            const saved = await this.doPersist();
            if (!saved) {
                return false;
            }
        }
        return this.ensureParentLink();
    }

    @api
    async ensureSurveySegmentationLink() {
        return this.ensureSegmentationLink();
    }

    @api
    async ensureEventSegmentationLink() {
        return this.ensureSegmentationLink();
    }

    @api
    async ensureGroupSegmentationLink() {
        return this.ensureSegmentationLink();
    }

    // Open the "name your audience" save dialog for the CURRENT whole selection so the
    // user can save it before proceeding (also called by the wizard when they try to
    // advance with an unsaved audience).
    @api
    openSaveDialog() {
        this.segmentationNameInput = this.segmentationName || '';
        this.showSegmentationNameModal = true;
    }

    scheduleCountsRefresh() {
        if (this.countsTimer) {
            clearTimeout(this.countsTimer);
        }
        this.countsTimer = setTimeout(() => {
            this.refreshAudienceCounts();
        }, 300);
    }

    async ensureCountsUpToDate(extraItems = []) {
        if (this.countsTimer) {
            clearTimeout(this.countsTimer);
            this.countsTimer = null;
        }
        await this.refreshAudienceCounts(extraItems);
    }

    async refreshAudienceCounts(extraItems = [], force = false) {
        if (this.countsInFlight && !force) {
            return;
        }
        this.countsInFlight = true;

        const baseItems = Array.isArray(this.selectedAudience) ? this.selectedAudience : [];
        const pendingItems = Array.isArray(extraItems) ? extraItems : [];
        const items = [...baseItems, ...pendingItems];

        if (items.length === 0) {
            this.countsInFlight = false;
            return;
        }
        const payloadJson = JSON.stringify({
            targetObject: 'ConstituentRole',
            items: items.map(i => ({
                id: i.id,
                role: i.role,
                type: i.type,
                criteria: i.criteria || []
            }))
        });
        try {
            const results = await getAudienceCounts({ payloadJson });
            const countsById = new Map();
            (results || []).forEach((row) => {
                if (row && row.id) {
                    countsById.set(row.id, row.count);
                }
            });
            this.countsById = countsById;

            // Update only existing selectedAudience items; pending extraItems are not yet in selectedAudience.
            let changed = false;
            const nextAudience = baseItems.map((item) => {
                if (!countsById.has(item.id)) {
                    return item;
                }
                const count = countsById.get(item.id);
                if (item.memberCount === count) {
                    return item;
                }
                changed = true;
                const label = this.memberCountLabel(count, true);
                return { ...item, membersLabel: label, memberCount: count };
            });
            // Write back through the setter only when a count actually changed, with the guard set so
            // the setter does not schedule another refresh (which would loop).
            if (changed) {
                this._applyingCounts = true;
                this.selectedAudience = nextAudience;
                this._applyingCounts = false;
            }

            const nextRoleState = { ...this.roleState };
            Object.keys(nextRoleState).forEach((role) => {
                const st = nextRoleState[role];
                if (!st || !Array.isArray(st.customGroups)) {
                    return;
                }
                st.customGroups = st.customGroups.map((g) => {
                    if (!countsById.has(g.id)) {
                        return g;
                    }
                    const count = countsById.get(g.id);
                    const label = count === 1 ? '1 Member' : `${count} Members`;
                    return { ...g, membersLabel: label, memberCount: count };
                });
            });
            this.roleState = nextRoleState;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Failed to refresh audience counts', e);
        } finally {
            this.countsInFlight = false;
        }
    }

    buildRoleBadgesFromPayload(payloadJson) {
        if (!payloadJson) {
            return [];
        }
        try {
            const payload = JSON.parse(payloadJson);
            const items = Array.isArray(payload.items) ? payload.items : [];
            const byRole = new Map();

            items.forEach((item) => {
                if (!item) {
                    return;
                }
                const label = item.roleLabel || item.role || 'Audience';
                const role = item.role;
                const order = item.order || this.getRoleOrder(role) || 9999;
                const existing = byRole.get(label);
                if (!existing || order < existing.order) {
                    byRole.set(label, { label, order });
                }
            });

            return Array.from(byRole.values()).sort((a, b) => {
                if (a.order !== b.order) {
                    return a.order - b.order;
                }
                return a.label.localeCompare(b.label);
            });
        } catch (e) {
            return [];
        }
    }
}