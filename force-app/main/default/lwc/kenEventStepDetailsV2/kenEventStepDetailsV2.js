import { LightningElement, api, track } from 'lwc';
import searchAudienceGroups from '@salesforce/apex/KenAudienceEngineService.searchAudienceGroups';
import searchSpecificIndividuals from '@salesforce/apex/KenAudienceEngineService.searchSpecificIndividuals';
import searchSavedAudiences from '@salesforce/apex/KenAudienceEngineService.searchSavedAudiences';

const AUDIENCE_CATS = [
    { id: 'roles', label: 'Role & Details' },
    { id: 'groups', label: 'Groups' },
    { id: 'individuals', label: 'Specific Individuals' }
];

const ROLE_OPTIONS = [
    { value: '2020 Alumni', label: '2020 Alumni' },
    { value: '2021 Alumni', label: '2021 Alumni' },
    { value: '2022 Alumni', label: '2022 Alumni' },
    { value: 'Faculty', label: 'Faculty' },
    { value: 'Staff', label: 'Staff' },
    { value: 'CSE', label: 'Computer Science (CSE)' },
    { value: 'ECE', label: 'Electronics (ECE)' },
    { value: 'ME', label: 'Mechanical Engineering' }
];

export default class KenEventStepDetailsV2 extends LightningElement {
    // Seed from the wizard so selections survive navigating back/forth between steps.
    @api audienceData;
    // Reused across Events/Jobs/Groups/Surveys. Hide the event-specific heading
    // when a host wizard renders its own section title.
    @api hideHeading = false;
    get showHeading() { return !this.hideHeading; }

    @track audienceCategory = 'roles';
    @track audience = [];                  // role/batch values (legacy)
    @track audiencesList = [];             // rich Role & Details audiences (Phase 1)
    @track groupSearchTerm = '';
    @track groupResults = [];
    @track selectedGroups = [];            // [{ id, name }]
    @track individualSearchTerm = '';
    @track individualResults = [];
    @track selectedIndividuals = [];       // [{ id, name }]
    @track individualSearching = false;
    @track csvFileName = '';
    @track csvEmails = [];
    @track csvError = '';

    // Step 2 opens on the saved-audience list; "Add New Audience" reveals the builder.
    @track view = 'saved';                 // 'saved' | 'builder'
    @track savedSearchTerm = '';
    @track savedResults = [];              // [{ id, name, memberCount, payloadJson }]
    @track selectedSaved = [];             // saved audiences the host has added

    // Review Saved Audience modal
    @track reviewOpen = false;
    @track reviewAudience = null;          // { id, name, memberCount }
    @track reviewModel = { groups: [], namedGroups: [], individuals: [] };
    @track collapsed = {};                 // { [sectionKey]: true } = collapsed

    _searchTimer = null;
    _indSeq = 0;                           // race guard for individual search responses

    connectedCallback() {
        const d = this.audienceData || {};
        if (d.category) this.audienceCategory = d.category;
        if (Array.isArray(d.roles)) this.audience = [...d.roles];
        if (Array.isArray(d.groups)) this.selectedGroups = [...d.groups];
        if (Array.isArray(d.individuals)) this.selectedIndividuals = [...d.individuals];
        if (Array.isArray(d.csvEmails)) this.csvEmails = [...d.csvEmails];
        if (d.csvFileName) this.csvFileName = d.csvFileName;
        if (Array.isArray(d.audiences)) this.audiencesList = [...d.audiences];
        if (Array.isArray(d.savedAudiences)) this.selectedSaved = [...d.savedAudiences];
        // Pre-load all available groups so they render as cards immediately (no search needed).
        this._loadGroups('');
        this._loadSavedAudiences('');
    }

    _loadGroups(term) {
        searchAudienceGroups({ searchTerm: term || '', limitSize: 100 })
            .then(rows => { this.groupResults = rows || []; })
            .catch(() => { this.groupResults = []; });
    }

    _loadSavedAudiences(term) {
        searchSavedAudiences({ searchTerm: term || '' })
            .then(rows => { this.savedResults = rows || []; })
            .catch(() => { this.savedResults = []; });
    }

    // --- view toggle: saved list <-> builder ---
    get isSavedView() { return this.view === 'saved'; }
    get isBuilderView() { return this.view === 'builder'; }
    handleAddNewAudience() { this.view = 'builder'; this._emitExpand(true); }
    handleBackToSaved() { this.view = 'saved'; this._emitExpand(false); }
    _emitExpand(expanded) {
        // Tell the host wizard to widen (builder) or re-centre (saved list) the content column.
        this.dispatchEvent(new CustomEvent('expandchange', { detail: { expanded } }));
    }

    // --- saved audience list ---
    handleSavedSearch(e) {
        const term = e.target.value || '';
        this.savedSearchTerm = term;
        this._debounce(() => { this._loadSavedAudiences(term); });
    }
    get hasSavedAudiences() { return (this.savedResults || []).length > 0; }
    get noSavedAudiences() { return (this.savedResults || []).length === 0; }
    get savedAudienceRows() {
        const added = new Set(this.selectedSaved.map(a => a.id));
        return (this.savedResults || []).map(a => {
            const isAdded = added.has(a.id);
            return {
                id: a.id, name: a.name,
                memberLabel: (a.memberCount != null ? a.memberCount : 0) + ' members',
                added: isAdded,
                cardCls: 'saved-card' + (isAdded ? ' saved-card--on' : '')
            };
        });
    }
    handleReviewAdd(e) {
        // Open the Review modal with the audience's parsed composition.
        const id = e.currentTarget.dataset.id;
        const row = (this.savedResults || []).find(a => a.id === id);
        if (!row) return;
        this.reviewAudience = { id: row.id, name: row.name, memberCount: row.memberCount };
        this.reviewModel = this._parsePayload(row.payloadJson);
        this.reviewOpen = true;
    }
    closeReview() { this.reviewOpen = false; this.reviewAudience = null; }
    confirmReviewAdd() {
        const a = this.reviewAudience;
        if (a && !this.selectedSaved.some(x => x.id === a.id)) {
            this.selectedSaved = [...this.selectedSaved, { id: a.id, name: a.name, memberCount: a.memberCount }];
            this._emit();
        }
        this.closeReview();
    }
    handleDownloadMembers() { /* member-list export — future enhancement */ }

    // Parse a saved-audience payload into the modal's display model.
    _parsePayload(payloadJson) {
        const groups = [], namedGroups = [], individuals = [];
        try {
            const p = JSON.parse(payloadJson || '{}');
            const items = Array.isArray(p.items) ? p.items : [];
            let gi = 0;
            items.forEach((it, idx) => {
                const type = (it.type || '').toUpperCase();
                if (type === 'GROUP') {
                    namedGroups.push({ id: it.id || ('ng' + idx), name: it.title || it.name || 'Group', membersLabel: it.membersLabel || '' });
                } else if (type === 'INDIVIDUAL') {
                    individuals.push({ id: it.id || ('ind' + idx), name: it.title || it.name || '', role: it.roleLabel || it.role || '' });
                } else {
                    gi += 1;
                    const criteria = (Array.isArray(it.criteria) ? it.criteria : []).map((c, ci) => ({
                        key: (c.key || c.label || 'c') + ci,
                        label: c.label || c.key || '',
                        chips: (Array.isArray(c.values) ? c.values : []).map((v, vi) => ({ key: 'v' + ci + vi, label: v }))
                    }));
                    groups.push({
                        id: it.id || ('g' + gi),
                        title: 'Group ' + gi,
                        roleLabel: it.roleLabel || it.role || '',
                        membersLabel: it.membersLabel || '',
                        criteria
                    });
                }
            });
        } catch (e) { /* malformed payload — show empty */ }
        return { groups, namedGroups, individuals };
    }

    toggleCollapse(e) {
        const key = e.currentTarget.dataset.key;
        this.collapsed = { ...this.collapsed, [key]: !this.collapsed[key] };
    }
    _chev(key) { return 'rev-chev' + (this.collapsed[key] ? ' rev-chev--down' : ''); }
    _body(base, key) { return base + (this.collapsed[key] ? ' rev-hidden' : ''); }

    get reviewName() { return this.reviewAudience ? this.reviewAudience.name : ''; }
    get reviewGroups() {
        return this.reviewModel.groups.map(g => {
            const key = 'group-' + g.id;
            return { ...g, key, chevClass: this._chev(key), bodyClass: this._body('rev-group__body', key) };
        });
    }
    get reviewNamedGroups() { return this.reviewModel.namedGroups; }
    get reviewIndividuals() { return this.reviewModel.individuals; }
    get hasReviewNamedGroups() { return this.reviewModel.namedGroups.length > 0; }
    get hasReviewIndividuals() { return this.reviewModel.individuals.length > 0; }
    get reviewNamedGroupCount() { return this.reviewModel.namedGroups.length; }
    get reviewIndividualCount() { return this.reviewModel.individuals.length; }
    get groupsChevClass() { return this._chev('groups'); }
    get groupsBodyClass() { return this._body('rev-sec__body', 'groups'); }
    get individualsChevClass() { return this._chev('individuals'); }
    get individualsBodyClass() { return this._body('rev-sec__body', 'individuals'); }

    handleRemoveSaved(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedSaved = this.selectedSaved.filter(a => a.id !== id);
        this._emit();
    }

    // --- category tabs ---
    get audienceCats() {
        return AUDIENCE_CATS.map(c => ({ ...c, cls: 'aud-cat' + (c.id === this.audienceCategory ? ' aud-cat--on' : '') }));
    }
    get isRolesCat() { return this.audienceCategory === 'roles'; }
    get isGroupsCat() { return this.audienceCategory === 'groups'; }
    get isIndividualsCat() { return this.audienceCategory === 'individuals'; }
    get isCsvCat() { return this.audienceCategory === 'csv'; }

    // --- roles ---
    get roleOptions() {
        return ROLE_OPTIONS.map(o => ({ ...o, checked: this.audience.indexOf(o.value) >= 0 }));
    }
    get audienceCount() { return this.audience.length || 0; }

    // --- groups ---
    get groupResultRows() {
        const sel = new Set(this.selectedGroups.map(g => g.id));
        return (this.groupResults || []).map(g => {
            const checked = sel.has(g.id);
            return {
                id: g.id, name: g.name,
                membersLabel: g.membersLabel || (g.memberCount != null ? `${g.memberCount} members` : ''),
                memberCount: g.memberCount != null ? g.memberCount : '',
                checked,
                cardCls: 'grp-card' + (checked ? ' grp-card--on' : ''),
                tickCls: 'grp-card__tick' + (checked ? ' grp-card__tick--on' : '')
            };
        });
    }
    get selectedGroupCards() {
        return this.selectedGroups.map(g => ({
            id: g.id, name: g.name,
            membersLabel: g.membersLabel || (g.memberCount != null ? `${g.memberCount} members` : '')
        }));
    }
    get hasGroupResults() { return (this.groupResults || []).length > 0; }
    get noGroupResults() { return (this.groupResults || []).length === 0; }
    get hasSelectedGroups() { return this.selectedGroups.length > 0; }

    // --- individuals ---
    get individualResultRows() {
        const sel = new Set(this.selectedIndividuals.map(p => p.id));
        return (this.individualResults || []).map(p => {
            const checked = sel.has(p.id);
            return {
                id: p.id, name: p.name, subtitle: p.subtitle || p.email || '',
                checked,
                tickCls: 'ind-option__tick' + (checked ? ' ind-option__tick--on' : '')
            };
        });
    }
    get hasIndividualResults() { return (this.individualResults || []).length > 0; }
    get hasSelectedIndividuals() { return this.selectedIndividuals.length > 0; }
    get showIndividualEmpty() {
        return this.individualSearchTerm.trim().length >= 2 && !this.individualSearching && (this.individualResults || []).length === 0;
    }

    // --- csv ---
    get hasCsv() { return this.csvEmails.length > 0; }
    get csvCountLabel() { return `${this.csvEmails.length} recipient${this.csvEmails.length === 1 ? '' : 's'} parsed`; }

    // --- role & details (rich builder) ---
    get audiencesData() { return this.audiencesList; }
    handleBuilderChange(e) {
        if (e.detail && e.detail.field === 'audiences') {
            this.audiencesList = e.detail.value || [];
            this._emit();
        }
    }

    // ===== handlers =====
    handleAudCat(e) { this.audienceCategory = e.currentTarget.dataset.id; this._emit(); }
    handleAudToggle(e) {
        const val = e.currentTarget.dataset.val;
        const cur = [...this.audience];
        const idx = cur.indexOf(val);
        if (idx >= 0) cur.splice(idx, 1); else cur.push(val);
        this.audience = cur;
        this._emit();
    }

    handleGroupSearch(e) {
        const term = e.target.value || '';
        this.groupSearchTerm = term;
        this._debounce(() => { this._loadGroups(term); });
    }
    handleGroupToggle(e) {
        const el = e.currentTarget;
        const id = el.dataset.id;
        const name = el.dataset.name;
        const membersLabel = el.dataset.members || '';
        const memberCount = el.dataset.count !== '' && el.dataset.count != null ? Number(el.dataset.count) : null;
        const idx = this.selectedGroups.findIndex(g => g.id === id);
        if (idx >= 0) this.selectedGroups = this.selectedGroups.filter(g => g.id !== id);
        else this.selectedGroups = [...this.selectedGroups, { id, name, membersLabel, memberCount }];
        this._emit();
    }
    handleRemoveGroup(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedGroups = this.selectedGroups.filter(g => g.id !== id);
        this._emit();
    }

    handleIndividualSearch(e) {
        const term = e.target.value || '';
        this.individualSearchTerm = term;
        if (term.trim().length < 2) {
            this.individualResults = [];
            this.individualSearching = false;
            this._indSeq++;                 // invalidate any in-flight request
            return;
        }
        this.individualSearching = true;
        this._debounce(() => {
            const seq = ++this._indSeq;     // tag this request
            searchSpecificIndividuals({ role: 'Alumni', searchTerm: term, filters: {}, targetObject: null, limitSize: 25 })
                .then(rows => {
                    if (seq !== this._indSeq) return;   // a newer keystroke superseded this — drop stale result
                    this.individualResults = rows || [];
                    this.individualSearching = false;
                })
                .catch(() => {
                    if (seq !== this._indSeq) return;
                    this.individualResults = [];
                    this.individualSearching = false;
                });
        });
    }
    handleIndividualToggle(e) {
        const id = e.currentTarget.dataset.id;
        const name = e.currentTarget.dataset.name;
        const subtitle = e.currentTarget.dataset.subtitle || '';
        const idx = this.selectedIndividuals.findIndex(p => p.id === id);
        if (idx >= 0) this.selectedIndividuals = this.selectedIndividuals.filter(p => p.id !== id);
        else this.selectedIndividuals = [...this.selectedIndividuals, { id, name, subtitle }];
        this._emit();
    }
    get selectedIndividualCards() {
        return this.selectedIndividuals.map(p => ({ id: p.id, name: p.name, subtitle: p.subtitle || '' }));
    }
    handleRemoveIndividual(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedIndividuals = this.selectedIndividuals.filter(p => p.id !== id);
        this._emit();
    }

    handleCsvChange(e) {
        this.csvError = '';
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        this.csvFileName = file.name;
        const reader = new FileReader();
        reader.onload = () => {
            try {
                const text = String(reader.result || '');
                const emailRe = /[^\s,;"]+@[^\s,;"]+\.[^\s,;"]+/g;
                const found = text.match(emailRe) || [];
                this.csvEmails = [...new Set(found.map(x => x.toLowerCase()))];
                if (this.csvEmails.length === 0) this.csvError = 'No valid email addresses found in the file.';
                this._emit();
            } catch (err) {
                this.csvError = 'Could not read the file.';
                this.csvEmails = [];
            }
        };
        reader.onerror = () => { this.csvError = 'Could not read the file.'; };
        reader.readAsText(file);
    }

    _debounce(fn) {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        if (this._searchTimer) clearTimeout(this._searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = setTimeout(fn, 300);
    }

    // Bubble the full audience snapshot up to the wizard's formData.
    _emit() {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: {
                field: 'audienceDetail',
                value: {
                    category: this.audienceCategory,
                    roles: [...this.audience],
                    audiences: this.audiencesList.map(a => ({ ...a })),
                    savedAudiences: this.selectedSaved.map(a => ({ ...a })),
                    savedAudienceIds: this.selectedSaved.map(a => a.id),
                    groups: this.selectedGroups.map(g => ({ id: g.id, name: g.name, membersLabel: g.membersLabel, memberCount: g.memberCount })),
                    individuals: this.selectedIndividuals.map(p => ({ id: p.id, name: p.name })),
                    groupIds: this.selectedGroups.map(g => g.id),
                    individualIds: this.selectedIndividuals.map(p => p.id),
                    csvEmails: [...this.csvEmails],
                    csvFileName: this.csvFileName
                }
            }
        }));
    }
}