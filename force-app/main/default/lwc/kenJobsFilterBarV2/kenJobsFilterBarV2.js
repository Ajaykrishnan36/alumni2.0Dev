import { LightningElement, api, track } from 'lwc';

// Filter field definitions, IN THIS ORDER. `key` matches the filter-state object
// the parent (kenJobsV2) maintains; `optionsKey` names the @api option array supplied
// by the parent for the dropdown.
const FIELDS = [
    { key: 'jobTitle',      label: 'Job title',      optionsKey: 'jobTitleOptions',      placeholder: 'Any title' },
    { key: 'company',       label: 'Company',        optionsKey: 'companyOptions',       placeholder: 'Any company' },
    { key: 'workplaceType', label: 'Workplace type', optionsKey: 'workplaceTypeOptions', placeholder: 'Any workplace' },
    { key: 'industry',      label: 'Industry',       optionsKey: 'industryOptions',      placeholder: 'Any industry' },
    { key: 'postedBy',      label: 'Posted by',      optionsKey: 'postedByOptions',      placeholder: 'Anyone' },
    { key: 'jobLocation',   label: 'Job location',   optionsKey: 'jobLocationOptions',   placeholder: 'Any location' },
    { key: 'postedOn',      label: 'Posted On',      optionsKey: 'postedOnOptions',      placeholder: 'Any time' },
    { key: 'jobType',       label: 'Job type',       optionsKey: 'jobTypeOptions',       placeholder: 'Any type' },
    { key: 'salary',        label: 'Salary',         optionsKey: 'salaryOptions',        placeholder: 'Any salary' },
    { key: 'skills',        label: 'Skills',         optionsKey: 'skillsOptions',        placeholder: 'Any skill' }
];

export default class KenJobsFilterBarV2 extends LightningElement {
    @api viewMode = 'card';
    @api searchTerm = '';

    // Option arrays supplied by the parent (derived from loaded jobs / static ranges).
    @api companyOptions = [];
    @api jobTitleOptions = [];
    @api workplaceTypeOptions = [];
    @api industryOptions = [];
    @api postedByOptions = [];
    @api jobLocationOptions = [];
    @api postedOnOptions = [];
    @api jobTypeOptions = [];
    @api salaryOptions = [];
    @api skillsOptions = [];

    // The currently-applied filters from the parent (so the panel reflects active state).
    @api appliedFilters = {};

    @track isOpen = false;
    // Draft selections inside the open panel (committed to parent only on Apply).
    @track draft = {};

    get cardCls() { return this.viewMode === 'card' ? 'vm-btn vm-btn--active' : 'vm-btn'; }
    get listCls() { return this.viewMode === 'list' ? 'vm-btn vm-btn--active' : 'vm-btn'; }

    // Count of active applied filters → badge on the Filters button.
    get activeCount() {
        const f = this.appliedFilters || {};
        return Object.keys(f).filter(k => f[k]).length;
    }
    get hasActive() { return this.activeCount > 0; }

    get fieldRows() {
        return FIELDS.map(f => {
            const opts = (this[f.optionsKey] || []).map(v => ({
                value: v,
                label: v,
                selected: this.draft[f.key] === v
            }));
            return {
                key: f.key,
                label: f.label,
                placeholder: f.placeholder,
                isAny: !this.draft[f.key],
                options: opts
            };
        });
    }

    // ---------- search + view toggle (unchanged behaviour) ----------
    handleSearch(event) {
        this.dispatchEvent(new CustomEvent('search', { detail: { term: event.target.value } }));
    }
    handleViewMode(event) {
        const mode = event.currentTarget.dataset.mode;
        this.dispatchEvent(new CustomEvent('viewmodechange', { detail: { mode } }));
    }

    // ---------- panel ----------
    handleOpen() {
        // Seed draft from the currently-applied filters so the panel opens in sync.
        this.draft = { ...(this.appliedFilters || {}) };
        this.isOpen = true;
    }
    handleClose() { this.isOpen = false; }
    stopBubble(event) { event.stopPropagation(); }

    handleFieldChange(event) {
        const key = event.target.dataset.key;
        if (!key) return;
        this.draft = { ...this.draft, [key]: event.target.value || '' };
    }

    handleClear() {
        this.draft = {};
        // Also notify parent immediately so the list resets.
        this.dispatchEvent(new CustomEvent('applyfilters', { detail: { filters: {} } }));
    }

    handleApply() {
        const clean = {};
        Object.keys(this.draft).forEach(k => { if (this.draft[k]) clean[k] = this.draft[k]; });
        this.dispatchEvent(new CustomEvent('applyfilters', { detail: { filters: clean } }));
        this.isOpen = false;
    }
}