import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import MENTORSHIP_EMPTY_STATE from '@salesforce/resourceUrl/MentorshipEmptyState';
import FilterIcon from '@salesforce/resourceUrl/FilterIcon';
import SortIcon from '@salesforce/resourceUrl/SortIcon';

const ARRAY_FIELDS = ['company', 'industry', 'jobFunction', 'programLastAttended', 'specialisation', 'graduationYear', 'currentCity'];

function emptyFilters() {
    const f = { showMentorsNearMe: false };
    ARRAY_FIELDS.forEach(k => { f[k] = []; });
    return f;
}

export default class KenMentorshipConnections extends LightningElement {
    FilterIcon = FilterIcon;
    SortIcon = SortIcon;

    @api mentors = [];
    @api isLoading = false;
    @api errorMessage = '';
    @api currentUserCity = '';
    @track displayedMentors = [];
    @track searchQuery = '';
    @track sortOrder = 'a-z';
    @track showFiltersPanel = false;
    @track filterDraft = emptyFilters();
    @track appliedFilters = emptyFilters();
    @track openDropdown = '';

    _previousMentors = null;
    @track isMobile = false;
    _mq;
    _mqHandler;

    @track companyOptions = [];
    @track industryOptions = [];
    @track jobFunctionOptions = [];
    @track programLastAttendedOptions = [];
    @track specialisationOptions = [];
    @track graduationYearOptions = [];
    @track currentCityOptions = [];

    // ── Source / display ─────────────────────────────────────
    get sourceMentors() {
        return Array.isArray(this.mentors) ? this.mentors : [];
    }

    get hasDisplayedMentors() {
        return this.displayedMentors.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.errorMessage && !this.hasDisplayedMentors;
    }

    get emptyStateImageUrl() {
        return MENTORSHIP_EMPTY_STATE;
    }

    // ── Sort ─────────────────────────────────────────────────
    get sortIconClass() {
        return this.sortOrder === 'z-a' ? 'sort-arrow sort-arrow-desc' : 'sort-arrow';
    }

    // ── Filter button / panel ─────────────────────────────────
    get showFilterCount() {
        return this.appliedFilterCount > 0;
    }

    get appliedFilterCount() {
        const f = this.appliedFilters;
        let count = f.showMentorsNearMe ? 1 : 0;
        ARRAY_FIELDS.forEach(k => {
            if (Array.isArray(f[k]) && f[k].length) count += 1;
        });
        return count;
    }

    get hasAppliedFilters() {
        return this.appliedFilterCount > 0;
    }

    get filtersButtonClass() {
        return this.hasAppliedFilters ? 'filter-btn filter-btn-active' : 'filter-btn';
    }

    // ── Multiselect helpers ───────────────────────────────────
    _getLabel(field, placeholder) {
        const sel = this.filterDraft[field] || [];
        if (!sel.length) return placeholder;
        if (sel.length === 1) return sel[0];
        return `${sel[0]} +${sel.length - 1}`;
    }

    _getBtnClass(field) {
        return (this.filterDraft[field] || []).length ? 'ms-btn ms-btn--active' : 'ms-btn';
    }

    _getLabelClass(field) {
        return (this.filterDraft[field] || []).length ? 'ms-btn-label ms-btn-label--selected' : 'ms-btn-label';
    }

    _getChevronClass(field) {
        return this.openDropdown === field ? 'ms-chevron ms-chevron--open' : 'ms-chevron';
    }

    _getDropdownOptions(field, options) {
        const sel = this.filterDraft[field] || [];
        return (options || []).map(opt => ({
            value: opt.value,
            label: opt.label,
            isSelected: sel.includes(opt.value),
            itemClass: sel.includes(opt.value) ? 'ms-option ms-option--selected' : 'ms-option'
        }));
    }

    // ── Per-field getters ─────────────────────────────────────
    get companyBtnLabel() { return this._getLabel('company', 'Company'); }
    get companyBtnClass() { return this._getBtnClass('company'); }
    get companyLabelClass() { return this._getLabelClass('company'); }
    get companyChevronClass() { return this._getChevronClass('company'); }
    get companyDropdownOptions() { return this._getDropdownOptions('company', this.companyOptions); }
    get isCompanyOpen() { return this.openDropdown === 'company'; }

    get industryBtnLabel() { return this._getLabel('industry', 'Industry'); }
    get industryBtnClass() { return this._getBtnClass('industry'); }
    get industryLabelClass() { return this._getLabelClass('industry'); }
    get industryChevronClass() { return this._getChevronClass('industry'); }
    get industryDropdownOptions() { return this._getDropdownOptions('industry', this.industryOptions); }
    get isIndustryOpen() { return this.openDropdown === 'industry'; }

    get jobFunctionBtnLabel() { return this._getLabel('jobFunction', 'Job function'); }
    get jobFunctionBtnClass() { return this._getBtnClass('jobFunction'); }
    get jobFunctionLabelClass() { return this._getLabelClass('jobFunction'); }
    get jobFunctionChevronClass() { return this._getChevronClass('jobFunction'); }
    get jobFunctionDropdownOptions() { return this._getDropdownOptions('jobFunction', this.jobFunctionOptions); }
    get isJobFunctionOpen() { return this.openDropdown === 'jobFunction'; }

    get programLastAttendedBtnLabel() { return this._getLabel('programLastAttended', 'Program last attended'); }
    get programLastAttendedBtnClass() { return this._getBtnClass('programLastAttended'); }
    get programLastAttendedLabelClass() { return this._getLabelClass('programLastAttended'); }
    get programLastAttendedChevronClass() { return this._getChevronClass('programLastAttended'); }
    get programLastAttendedDropdownOptions() { return this._getDropdownOptions('programLastAttended', this.programLastAttendedOptions); }
    get isProgramLastAttendedOpen() { return this.openDropdown === 'programLastAttended'; }

    get specialisationBtnLabel() { return this._getLabel('specialisation', 'Specialisation'); }
    get specialisationBtnClass() { return this._getBtnClass('specialisation'); }
    get specialisationLabelClass() { return this._getLabelClass('specialisation'); }
    get specialisationChevronClass() { return this._getChevronClass('specialisation'); }
    get specialisationDropdownOptions() { return this._getDropdownOptions('specialisation', this.specialisationOptions); }
    get isSpecialisationOpen() { return this.openDropdown === 'specialisation'; }

    get graduationYearBtnLabel() { return this._getLabel('graduationYear', 'Graduation year'); }
    get graduationYearBtnClass() { return this._getBtnClass('graduationYear'); }
    get graduationYearLabelClass() { return this._getLabelClass('graduationYear'); }
    get graduationYearChevronClass() { return this._getChevronClass('graduationYear'); }
    get graduationYearDropdownOptions() { return this._getDropdownOptions('graduationYear', this.graduationYearOptions); }
    get isGraduationYearOpen() { return this.openDropdown === 'graduationYear'; }

    get currentCityBtnLabel() { return this._getLabel('currentCity', 'Current city / Town of residence'); }
    get currentCityBtnClass() { return this._getBtnClass('currentCity'); }
    get currentCityLabelClass() { return this._getLabelClass('currentCity'); }
    get currentCityChevronClass() { return this._getChevronClass('currentCity'); }
    get currentCityDropdownOptions() { return this._getDropdownOptions('currentCity', this.currentCityOptions); }
    get isCurrentCityOpen() { return this.openDropdown === 'currentCity'; }

    // ── Lifecycle ─────────────────────────────────────────────
    connectedCallback() {
        this.applySortAndFilters();
        this.rebuildFilterOptions();
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {});
        if (typeof window !== 'undefined' && window.matchMedia) {
            this._mq = window.matchMedia('(max-width: 767px)');
            this._mqHandler = () => { this.isMobile = this._mq.matches; };
            this.isMobile = this._mq.matches;
            this._mq.addEventListener('change', this._mqHandler);
        }
    }

    renderedCallback() {
        const sourceMentors = this.sourceMentors;
        const mentorsChanged = this._previousMentors === null ||
            sourceMentors.length !== this._previousMentors.length ||
            sourceMentors !== this._previousMentors;

        if (mentorsChanged) {
            this.rebuildFilterOptions();
            this.applySortAndFilters();
            this._previousMentors = sourceMentors;
        }

        if (this.showFiltersPanel) {
            requestAnimationFrame(() => this._positionFiltersPanel());
        }
    }

    disconnectedCallback() {
        this._removeFiltersOutsideClick();
        this._removeDropdownOutsideClick();
        if (this._mq && this._mqHandler) {
            this._mq.removeEventListener('change', this._mqHandler);
        }
    }

    // ── Options building ──────────────────────────────────────
    rebuildFilterOptions() {
        const mentors = this.sourceMentors;
        this.companyOptions = this.buildOptionsFromMentors(mentors.map(m => m.company));
        this.industryOptions = this.buildOptionsFromMentors(mentors.map(m => m.industry));
        this.jobFunctionOptions = this.buildOptionsFromMentors(mentors.map(m => m.jobFunction || m.title));
        this.programLastAttendedOptions = this.buildOptionsFromMentors(mentors.map(m => m.programLastAttended || m.program));
        this.specialisationOptions = this.buildOptionsFromMentors(mentors.map(m => m.specialisation || m.specialization));
        this.graduationYearOptions = this.buildOptionsFromMentors(
            mentors.map(m => String(m.graduationYear || m.gradYear || '')).filter(Boolean),
            true
        );
        this.currentCityOptions = this.buildOptionsFromMentors(
            mentors.map(m => m.currentCity || this.extractCityFromLocation(m.location) || m.city)
        );
    }

    buildOptionsFromMentors(rawValues, numericSort = false) {
        const normalizedMap = new Map();
        rawValues
            .map(v => (v || '').toString().trim())
            .filter(Boolean)
            .forEach(v => {
                const key = v.toLowerCase();
                if (!normalizedMap.has(key)) normalizedMap.set(key, v);
            });

        const values = [...normalizedMap.values()].sort((a, b) =>
            numericSort ? Number(a) - Number(b) : a.localeCompare(b)
        );
        return values.map(v => ({ label: v, value: v }));
    }

    extractCityFromLocation(location) {
        if (!location) return '';
        const [city] = String(location).split(',');
        return (city || '').trim();
    }

    // ── Panel positioning ─────────────────────────────────────
    _positionFiltersPanel() {
        const trigger = this.template.querySelector('[data-filter-trigger]');
        const panel = this.template.querySelector('.filters-panel');
        if (!trigger || !panel) return;
        const rect = trigger.getBoundingClientRect();
        const gap = 8;
        const panelWidth = panel.offsetWidth || Math.min(420, window.innerWidth * 0.92);
        panel.style.top = `${rect.bottom + gap}px`;
        if (rect.right < panelWidth + 16) {
            panel.style.left = '16px';
            panel.style.right = 'auto';
        } else {
            panel.style.right = `${window.innerWidth - rect.right}px`;
            panel.style.left = 'auto';
        }
    }

    // ── Filter/sort logic ─────────────────────────────────────
    applySortAndFilters() {
        const mentors = this.sourceMentors;
        if (!mentors || mentors.length === 0) {
            this.displayedMentors = [];
            return;
        }
        let list = [...mentors];

        if (this.searchQuery) {
            const query = this.searchQuery.toLowerCase();
            list = list.filter(m =>
                (m.name || '').toLowerCase().includes(query) ||
                (m.title || '').toLowerCase().includes(query) ||
                (m.location || '').toLowerCase().includes(query)
            );
        }

        const af = this.appliedFilters;

        if (af.showMentorsNearMe) {
            const nearCity = (this.currentUserCity || '').toLowerCase();
            if (nearCity) {
                list = list.filter(m => (m.location || m.currentCity || m.city || '').toLowerCase().includes(nearCity));
            }
        }

        if (af.company && af.company.length) {
            list = list.filter(m => af.company.some(c => (m.company || '').toLowerCase() === c.toLowerCase()));
        }
        if (af.industry && af.industry.length) {
            list = list.filter(m => af.industry.some(c => (m.industry || '').toLowerCase() === c.toLowerCase()));
        }
        if (af.jobFunction && af.jobFunction.length) {
            list = list.filter(m => af.jobFunction.some(c => (m.jobFunction || m.title || '').toLowerCase().includes(c.toLowerCase())));
        }
        if (af.programLastAttended && af.programLastAttended.length) {
            list = list.filter(m => af.programLastAttended.some(c => (m.programLastAttended || m.program || '').toLowerCase() === c.toLowerCase()));
        }
        if (af.specialisation && af.specialisation.length) {
            list = list.filter(m => af.specialisation.some(c => (m.specialisation || m.specialization || '').toLowerCase() === c.toLowerCase()));
        }
        if (af.graduationYear && af.graduationYear.length) {
            list = list.filter(m => af.graduationYear.includes(String(m.graduationYear || m.gradYear || '')));
        }
        if (!af.showMentorsNearMe && af.currentCity && af.currentCity.length) {
            list = list.filter(m => af.currentCity.some(c => (m.location || m.currentCity || m.city || '').toLowerCase().includes(c.toLowerCase())));
        }

        list.sort((a, b) => {
            const nameA = (a.name || '').toLowerCase();
            const nameB = (b.name || '').toLowerCase();
            return this.sortOrder === 'a-z' ? nameA.localeCompare(nameB) : nameB.localeCompare(nameA);
        });

        this.displayedMentors = list;
    }

    // ── Event handlers ────────────────────────────────────────
    handleSearch(event) {
        this.searchQuery = (event.detail && event.detail.value) ? event.detail.value : '';
        this.applySortAndFilters();
    }

    handleSortClick(event) {
        event.stopPropagation();
        this.sortOrder = this.sortOrder === 'a-z' ? 'z-a' : 'a-z';
        this.applySortAndFilters();
    }

    handleFiltersClick() {
        const af = this.appliedFilters;
        this.filterDraft = { ...af };
        ARRAY_FIELDS.forEach(k => { this.filterDraft[k] = [...(af[k] || [])]; });
        this.openDropdown = '';
        this.showFiltersPanel = true;
        this._removeFiltersOutsideClick();
        this._filtersOutsideClickHandler = (event) => {
            const panel = this.template.querySelector('.filters-panel');
            const trigger = this.template.querySelector('[data-filter-trigger]');
            if (panel && trigger && !panel.contains(event.target) && !trigger.contains(event.target)) {
                this.showFiltersPanel = false;
                this.openDropdown = '';
                this._removeFiltersOutsideClick();
                this._removeDropdownOutsideClick();
            }
        };
        setTimeout(() => document.addEventListener('click', this._filtersOutsideClickHandler), 0);
    }

    _removeFiltersOutsideClick() {
        if (this._filtersOutsideClickHandler) {
            document.removeEventListener('click', this._filtersOutsideClickHandler);
            this._filtersOutsideClickHandler = null;
        }
    }

    handleFiltersPanelClick(event) {
        event.stopPropagation();
    }

    handleFiltersPanelKeydown(event) {
        if (event.key === 'Escape') {
            this.showFiltersPanel = false;
            this.openDropdown = '';
            this._removeFiltersOutsideClick();
            this._removeDropdownOutsideClick();
        }
    }

    // Toggle filter (showMentorsNearMe)
    handleFilterDraftChange(event) {
        const name = event.target.name;
        if (name === 'showMentorsNearMe') {
            const value = event.detail?.checked ?? !!event.target.checked;
            this.filterDraft = { ...this.filterDraft, [name]: value };
            this._applyDraftLive();
        }
    }

    _applyDraftLive() {
        const draft = this.filterDraft;
        const applied = { showMentorsNearMe: draft.showMentorsNearMe };
        ARRAY_FIELDS.forEach(k => { applied[k] = [...(draft[k] || [])]; });
        this.appliedFilters = applied;
        this.applySortAndFilters();
    }

    // Multiselect dropdown toggle
    handleDropdownToggle(event) {
        event.stopPropagation();
        const name = event.currentTarget.dataset.name;
        if (this.openDropdown === name) {
            this.openDropdown = '';
            this._removeDropdownOutsideClick();
        } else {
            this.openDropdown = name;
            this._removeDropdownOutsideClick();
            this._dropdownOutsideClickHandler = () => {
                this.openDropdown = '';
                this._removeDropdownOutsideClick();
            };
            setTimeout(() => document.addEventListener('click', this._dropdownOutsideClickHandler), 0);
        }
    }

    handleDropdownStopProp(event) {
        event.stopPropagation();
    }

    _removeDropdownOutsideClick() {
        if (this._dropdownOutsideClickHandler) {
            document.removeEventListener('click', this._dropdownOutsideClickHandler);
            this._dropdownOutsideClickHandler = null;
        }
    }

    handleCheckboxChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.currentTarget.value;
        const current = [...(this.filterDraft[field] || [])];
        if (event.currentTarget.checked) {
            if (!current.includes(value)) current.push(value);
        } else {
            const idx = current.indexOf(value);
            if (idx !== -1) current.splice(idx, 1);
        }
        this.filterDraft = { ...this.filterDraft, [field]: current };
        this._applyDraftLive();
    }

    handleFilterApply() {
        this._applyDraftLive();
        this.showFiltersPanel = false;
        this.openDropdown = '';
        this._removeFiltersOutsideClick();
        this._removeDropdownOutsideClick();
    }

    handleFilterClear() {
        this.filterDraft = emptyFilters();
        this.appliedFilters = emptyFilters();
        this.openDropdown = '';
        this._removeDropdownOutsideClick();
        this.applySortAndFilters();
    }

    handleMentorClick(event) {
        this.dispatchEvent(new CustomEvent('mentorclick', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }

    handleMobileBack() {
        if (window?.history?.length > 1) {
            window.history.back();
        }
    }
}