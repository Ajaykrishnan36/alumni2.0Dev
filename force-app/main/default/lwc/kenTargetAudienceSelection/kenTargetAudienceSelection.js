/**
 * Target Audience Selection (Step 4/4)
 * -------------------------------------------------------
 * This component implements the UI shown in your screenshots:
 * - Left nav: Role & Details, Groups, Specific Individuals, Saved Audience
 * - Role pills: Students, Alumni, Parents, Faculty, Staff, Organisation, Others
 * - "All" vs "Create Custom Group" options per role
 * - Custom group creation with multi-select fields (backed by Apex metadata in future)
 * - Right panel listing all selected audience groups
 *
 * Notes:
 * - This implementation is generic and metadata-driven. You can later swap out the
 *   sample options to pull from Education Cloud / Alumni Cloud attribute objects.
 * - All "picklist-like" fields are multi-select; the component uses a custom
 *   multi-select combobox (c-multi-select-picklist).
 */
import { LightningElement, wire, api } from 'lwc';
import getRoleFieldOptions from '@salesforce/apex/KenAudienceEngineService.getRoleFieldOptions';
import searchSpecificIndividuals from '@salesforce/apex/KenAudienceEngineService.searchSpecificIndividuals';
import saveAudiencePayload from '@salesforce/apex/KenAudienceEngineService.saveAudiencePayload';
import getAudienceCounts from '@salesforce/apex/KenAudienceEngineService.getAudienceCounts';
import searchSavedAudiences from '@salesforce/apex/KenAudienceEngineService.searchSavedAudiences';
import getSavedAudienceDetail from '@salesforce/apex/KenAudienceEngineService.getSavedAudienceDetail';
import activateSavedAudience from '@salesforce/apex/KenAudienceEngineService.activateSavedAudience';
import getSavedGroupsForRole from '@salesforce/apex/KenAudienceEngineService.getSavedGroupsForRole';
import getActiveRoleCategories from '@salesforce/apex/KenAudienceEngineService.getActiveRoleCategories';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import searchDistinctFieldValues from '@salesforce/apex/KenAudienceEngineService.searchDistinctFieldValues';

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

const MOCK_GROUPS = [
    { id: 'grp_debate', name: 'Debate Club', members: 128 },
    { id: 'grp_robotics', name: 'Robotics Club', members: 184 },
    { id: 'grp_alumni_dubai', name: 'Alumni Chapter - Dubai', members: 210 },
    { id: 'grp_coding', name: 'Coding Society', members: 96 },
    { id: 'grp_green', name: 'Green Campus Initiative', members: 72 }
];

function generateId(prefix) {
    return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
}

export default class KenTargetAudienceSelection extends LightningElement {
    navSection = NAV.ROLE_DETAILS;
    _selectedAudience = [];
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
    savedSearchTerm = '';
    savedAudiences = [];
    savedAudienceLoading = false;
    savedSearchTimer;
    showSavedModal = false;
    savedModalName = '';
    savedModalItems = [];
    savedAudienceId;
    segmentationId = null;
    segmentationName = '';
    segmentationNameInput = '';
    showSegmentationNameModal = false;
    showConfirmModal = false;
    confirmMessage = '';
    pendingAllRole;
    pendingAllLabel;
    confirmActionType;
    pendingCustomItem;
    pendingCustomIsEdit = false;
    pendingAddAll = false;
    pendingSaveType = null;
    pendingGroupItem = null;
    pendingIsEdit = false;
    individualsFilters = {
        program: [],
        school: [],
        department: [],
        campus: []
    };
    individualsSearchTimer;
    fieldSearchTimers = {};
    countsTimer;

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
    get selectedAudience() {
        return this._selectedAudience;
    }
    set selectedAudience(val) {
        this._selectedAudience = this.normalizeSelectedAudience(val);
        this.scheduleCountsRefresh();
    }

    popup = { visible: false, message: '', variant: 'success' };
    popupTimer;
    countsTimer;
    countsById = new Map();
    countsInFlight = false;

    /**
     * Exposed for parent wrappers (kenCommunications) that need to know which
     * segmentation the user just built. Returns null when nothing has been
     * persisted yet. The audience builder already writes Ken_Segmentation__c
     * internally via persistSegmentation(); this getter just surfaces the Id
     * so the parent can auto-select it.
     */
    @api
    getCurrentSegmentation() {
        if (!this.segmentationId) return null;
        return { id: this.segmentationId, name: this.segmentationName || '' };
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
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

    formatMembersLabel(item) {
        if (item && item.membersLabel && String(item.membersLabel).trim()) {
            return item.membersLabel;
        }
        const count = item && Number.isFinite(item.memberCount) ? item.memberCount : null;
        if (count === null) {
            return 'Audience';
        }
        return count === 1 ? '1 Member' : `${count} Members`;
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

    get addAllLabel() {
        return `Add All ${this.activeRoleLabel} to Audience`;
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

    get hasSelectedIndividuals() {
        return Object.keys(this.selectedIndividuals || {}).length > 0;
    }

    get selectedIndividualsLabel() {
        const n = Object.keys(this.selectedIndividuals || {}).length;
        return n === 1 ? '1 individual selected' : `${n} individuals selected`;
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

    get filteredGroups() {
        const term = (this.groupsSearchTerm || '').trim().toLowerCase();
        if (!term) {
            return MOCK_GROUPS;
        }
        return MOCK_GROUPS.filter((group) => group.name.toLowerCase().includes(term));
    }

    get hasGroupResults() {
        return Array.isArray(this.filteredGroups) && this.filteredGroups.length > 0;
    }

    get showGroupsEmptyState() {
        return !this.hasGroupResults && !!(this.groupsSearchTerm && this.groupsSearchTerm.trim());
    }

    get groupResultsWithState() {
        return (this.filteredGroups || []).map((group) => {
            const selected = !!this.selectedGroups[group.id];
            return {
                ...group,
                selected,
                membersLabel: `${group.members} members`,
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
        return (this.savedModalItems || []).filter((item) => item.type === 'GROUP');
    }

    get savedModalIndividuals() {
        return (this.savedModalItems || []).filter((item) => item.type === 'INDIVIDUAL');
    }

    get savedModalCustomGroups() {
        return (this.savedModalItems || []).filter((item) => item.type === 'CUSTOM');
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
    };

    handleModeChange(event) {
        const value = event.detail && event.detail.value ? event.detail.value : event.target.value;
        if (value === 'ALL') {
            this.selectAllMode();
        } else if (value === 'CUSTOM') {
            this.selectCustomMode();
        }
        this.roleState = { ...this.roleState };
    }

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
            this.toast('Please select at least one criterion before saving.', 'error');
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

    async proceedWithCustomSave(groupItem, isEdit) {
        const st = this.roleState[groupItem.role];
        if (!st) {
            return;
        }
        if (!this.segmentationId) {
            this.pendingSaveType = 'ACTIVE';
            this.pendingGroupItem = groupItem;
            this.pendingIsEdit = isEdit;
            this.segmentationNameInput = this.segmentationNameInput || '';
            this.showSegmentationNameModal = true;
            return;
        }

        this.applyGroupSave(st, groupItem, isEdit);
        try {
            await this.persistSegmentation('ACTIVE');
            this.toast(`${groupItem.title} added to audience`, 'success');
            this.loadSavedAudiences(this.savedSearchTerm);
            this.scheduleCountsRefresh();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Save audience failed', e);
            this.toast(this.reduceError(e), 'error');
        }
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

        if (!this.segmentationId) {
            this.pendingAllRole = role;
            this.pendingAllLabel = this.activeRoleLabel;
            this.pendingAddAll = true;
            this.segmentationNameInput = this.segmentationNameInput || '';
            this.showSegmentationNameModal = true;
            return;
        }

        const item = {
            id: generateId('all'),
            role: role,
            roleLabel: this.activeRoleLabel,
            title: `All ${this.activeRoleLabel}`,
            type: 'ALL',
            memberCount: null,
            membersLabel: 'Calculating...',
            criteria: []
        };
        this.selectedAudience = [...(this.selectedAudience || []), item];
        this.toast(`All ${this.activeRoleLabel} added to audience`, 'success');
        this.scheduleCountsRefresh();
    }

    // -----------------------------
    // Right panel remove
    // -----------------------------
    handleRemoveSelected(event) {
        const id = event.detail.id;
        const removed = (this.selectedAudience || []).find((i) => i.id === id);
        this.selectedAudience = (this.selectedAudience || []).filter((i) => i.id !== id);

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

    // -----------------------------
    // Footer actions (stubs)
    // -----------------------------
    handleBack() {
        this.toast('Back clicked (wire this to your wizard router)', 'info');
    }

    handleSaveForLater() {
        const st = this.roleState[this.activeRole];
        const draft = st ? st.draftGroup : null;
        let pendingItem = null;
        let pendingIsEdit = false;

        if (draft) {
            const criteria = this.buildCriteriaForRole(this.activeRole, draft.selections);
            if (criteria.length === 0) {
                this.toast('Please select at least one criterion before saving.', 'error');
                return;
            }

            pendingIsEdit = !!draft.editingId;
            const existing = pendingIsEdit ? (st.customGroups || []).find((g) => g.id === draft.editingId) : null;
            const groupName = (existing && existing.title) || draft.displayName || this.buildDefaultGroupTitle(this.activeRole, st);

            pendingItem = {
                id: pendingIsEdit ? draft.editingId : generateId('aud'),
                role: this.activeRole,
                roleLabel: this.activeRoleLabel,
                title: groupName,
                type: 'CUSTOM',
                membersLabel: '0 members',
                criteria
            };
        }

        const totalItems = (this.selectedAudience || []).length + (pendingItem ? 1 : 0);
        if (totalItems === 0) {
            this.toast('Add a custom audience before saving a template.', 'info');
            return;
        }

        if (!this.segmentationId) {
            this.pendingSaveType = 'TEMPLATE';
            this.pendingGroupItem = pendingItem;
            this.pendingIsEdit = pendingIsEdit;
            this.segmentationNameInput = this.segmentationNameInput || '';
            this.showSegmentationNameModal = true;
            return;
        }

        if (pendingItem) {
            this.applyGroupSave(st, pendingItem, pendingIsEdit);
        }
        this.persistSegmentation('TEMPLATE')
            .then(() => {
                this.toast('Saved for later.', 'success');
                this.loadSavedAudiences(this.savedSearchTerm);
            })
            .catch((e) => {
                // eslint-disable-next-line no-console
                console.warn('Save for later failed', e);
                this.toast(this.reduceError(e), 'error');
            });
    }

    handleSubmit() {
        // In your final implementation, persist selectedAudience to your target object(s).
        this.toast('Audience Saved Successfully!', 'success');
    }

    handleSegmentationNameInput(event) {
        this.segmentationNameInput = event.detail ? event.detail.value : '';
        this.clearSegmentationNameError();
    }

    closeSegmentationNameModal() {
        this.showSegmentationNameModal = false;
        this.segmentationNameInput = this.segmentationName || '';
        this.pendingSaveType = null;
        this.pendingGroupItem = null;
        this.pendingIsEdit = false;
    }

    async confirmSegmentationName() {
        this.clearSegmentationNameError();
        const name = (this.segmentationNameInput || '').trim();
        if (!name) {
            this.setSegmentationNameError('Segmentation name is required.');
            this.toast('Please enter a segmentation name.', 'error');
            return;
        }
        const pendingItem = this.pendingGroupItem;
        const pendingIsEdit = this.pendingIsEdit;
        const saveType = this.pendingSaveType || 'TEMPLATE';

        try {
            this.segmentationName = name;
            await this.persistSegmentation(saveType, pendingItem ? [pendingItem] : []);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Save audience failed', e);
            const message = this.reduceError(e).replace(/Audience name/gi, 'Segmentation name');
            this.setSegmentationNameError(message);
            this.toast(message, 'error');
            return;
        }

        this.showSegmentationNameModal = false;
        this.segmentationNameInput = this.segmentationName;
        if (pendingItem) {
            const st = this.roleState[pendingItem.role];
            if (st) {
                this.applyGroupSave(st, pendingItem, pendingIsEdit);
            }
            this.toast(`${pendingItem.title} added to audience`, 'success');
        } else if (this.pendingAddAll && this.pendingAllRole) {
            this.addAllForRole(this.pendingAllRole, this.pendingAllLabel);
        } else {
            this.toast('Segmentation saved.', 'success');
        }

        this.pendingSaveType = null;
        this.pendingGroupItem = null;
        this.pendingIsEdit = false;
        this.pendingAddAll = false;
        this.loadSavedAudiences(this.savedSearchTerm);
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

        if (!this.segmentationId) {
            this.pendingAddAll = true;
            this.segmentationNameInput = this.segmentationNameInput || '';
            this.showSegmentationNameModal = true;
            this.closeConfirmModal();
            return;
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
        this.toast(`All ${label} added to audience`, 'success');
        this.scheduleCountsRefresh();
        this.pendingAddAll = false;
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
        this.selectedIndividuals = { ...this.selectedIndividuals, [id]: true };
        this.scheduleCountsRefresh();
    }

    // Save an audience made up of the currently selected specific individuals.
    // The individuals are already in selectedAudience, so we just trigger the
    // same persist flow the role/custom "Save group" uses (name modal first).
    async handleSaveIndividuals() {
        if (!this.hasSelectedIndividuals) {
            this.toast('Select at least one individual before saving.', 'error');
            return;
        }
        if (!this.segmentationId) {
            this.pendingSaveType = 'ACTIVE';
            this.pendingGroupItem = null;
            this.pendingIsEdit = false;
            this.pendingAddAll = false;
            this.segmentationNameInput = this.segmentationNameInput || '';
            this.showSegmentationNameModal = true;
            return;
        }
        try {
            await this.persistSegmentation('ACTIVE');
            this.toast('Audience saved', 'success');
            this.loadSavedAudiences(this.savedSearchTerm);
            this.scheduleCountsRefresh();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Save individuals audience failed', e);
            this.toast(this.reduceError(e), 'error');
        }
    }

    handleToggleGroup(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        const group = (MOCK_GROUPS || []).find((item) => item.id === id);
        if (!group) {
            return;
        }

        if (this.selectedGroups[id]) {
            this.selectedAudience = (this.selectedAudience || []).filter((item) => item.id !== id);
            const next = { ...this.selectedGroups };
            delete next[id];
            this.selectedGroups = next;
            return;
        }

        const item = {
            id: group.id,
            role: 'GROUPS',
            roleLabel: 'Groups',
            title: group.name,
            type: 'GROUP',
            membersLabel: `${group.members} members`,
            criteria: []
        };
        this.selectedAudience = [...(this.selectedAudience || []), item];
        this.selectedGroups = { ...this.selectedGroups, [id]: true };
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
            })
            .catch((e) => {
                // eslint-disable-next-line no-console
                console.warn('Failed to load saved audience', e);
                this.toast('Failed to load saved audience.', 'error');
            });
    }

    closeSavedModal() {
        this.showSavedModal = false;
        this.savedModalItems = [];
        this.savedModalName = '';
        this.savedAudienceId = null;
    }

    handleAddSavedAudience() {
        const items = Array.isArray(this.savedModalItems) ? this.savedModalItems : [];
        const added = [];
        const now = Date.now();
        items.forEach((item, idx) => {
            const nextId = `saved_${item.id || item.title || 'item'}_${now}_${idx}`;
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
                this.roleState = { ...this.roleState };
            }
        });

        this.selectedAudience = [...(this.selectedAudience || []), ...added];
        activateSavedAudience({ audienceId: this.savedAudienceId })
            .then(() => {
                this.toast('Saved audience added.', 'success');
                this.loadSavedAudiences(this.savedSearchTerm);
                this.scheduleCountsRefresh();
            })
            .catch((e) => {
                // eslint-disable-next-line no-console
                console.warn('Failed to activate saved audience', e);
                this.toast('Failed to activate saved audience.', 'error');
            });

        this.closeSavedModal();
    }

    getSavedAudienceName() {
        const custom = (this.selectedAudience || []).find((item) => item.type === 'CUSTOM');
        if (custom && custom.title) {
            return custom.title;
        }
        const ts = new Date();
        return `Saved Audience ${ts.toLocaleDateString()}`;
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
                memberLabel: aud.memberCount ? `${aud.memberCount} members` : 'Audience',
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
     * Ensures names stay unique after adds/edits/removals.
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

        // Mirror updated titles into selectedAudience list
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

       async persistSegmentation(saveType, extraItems) {

    // Ensure counts are up-to-date for both current selection and any pending items being saved
    await this.ensureCountsUpToDate(extraItems || []);

    const payload = this.buildSegmentationPayload(extraItems);
    const isActive = saveType === 'ACTIVE';
    const statusValue = isActive ? 'Active' : 'Save Later';

    const segId = await saveAudiencePayload({
        audienceName: this.segmentationName,
        payloadJson: payload,
        audienceId: this.segmentationId,
        active: isActive,
        statusValue
    });

    if (!this.segmentationId) {
        this.segmentationId = segId;
    }
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

            // Update only existing selectedAudience items; pending extraItems are not yet in selectedAudience
            this.selectedAudience = baseItems.map((item) => {
                if (!countsById.has(item.id)) {
                    return item;
                }
                const count = countsById.get(item.id);
                const label = count === 1 ? '1 Member' : `${count} Members`;
                return { ...item, membersLabel: label, memberCount: count };
            });

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