import { LightningElement, api, track } from 'lwc';
import getActiveRoleCategories from '@salesforce/apex/KenAudienceEngineService.getActiveRoleCategories';
import getRoleFieldOptions from '@salesforce/apex/KenAudienceEngineService.getRoleFieldOptions';
import getAudienceCounts from '@salesforce/apex/KenAudienceEngineService.getAudienceCounts';
import searchDistinctFieldValues from '@salesforce/apex/KenAudienceEngineService.searchDistinctFieldValues';

/* ============================================================ *
 *  Role & Details audience builder (Phase 1).
 *  Role chips    → getActiveRoleCategories()  (constituent roles from onboarding)
 *  Attribute fields → getRoleFieldOptions(role) (AttributeCategory → Definition, per role)
 *  Field values  → field.options OR searchDistinctFieldValues() for `search`-type fields
 *  Each field is a multi-select dropdown with chips. Add to Audience builds a
 *  criteria set, fetches the live member count, and lists it in Selected Audience.
 * ============================================================ */
export default class KenEventAudienceBuilderV2 extends LightningElement {
    @api
    get audiences() { return this._audiences; }
    set audiences(val) { this._audiences = Array.isArray(val) ? [...val] : []; this.selectedAudiences = [...this._audiences]; }
    _audiences = [];

    @track roleChips = [];
    @track activeRole = '';
    @track activeRoleName = '';
    @track mode = 'all';                 // 'all' | 'custom'
    @track roleFields = [];              // FieldConfigDTO[] for the active role
    @track audienceName = '';
    @track selectedAudiences = [];       // [{ id, name, roleCode, roleName, count, criteria, isAll }]
    @track loadingFields = false;

    // per-field multi-select state
    @track fieldValues = {};             // { [key]: [{ value, label }] }
    @track fieldOptions = {};            // { [key]: [{ value, label }] }
    @track fieldOpen = {};               // { [key]: bool }
    @track fieldSearch = {};             // { [key]: term }
    _fieldMeta = {};                     // { [key]: { objectApi, fieldApi, type } }

    _aSeq = 0;
    _searchTimer = null;

    connectedCallback() {
        this._loadRoles();
        this._closeMenus = (e) => {
            // close any open field menus when clicking outside this component
            if (!this.template.contains(e.target)) {
                if (Object.keys(this.fieldOpen).some(k => this.fieldOpen[k])) this.fieldOpen = {};
            }
        };
        window.addEventListener('click', this._closeMenus);
    }
    disconnectedCallback() {
        if (this._closeMenus) window.removeEventListener('click', this._closeMenus);
    }

    _loadRoles() {
        getActiveRoleCategories()
            .then(rows => {
                this.roleChips = (rows || []).map(r => ({ code: r.code, name: r.name }));
                if (!this.activeRole && this.roleChips.length) this._selectRole(this.roleChips[0].code, this.roleChips[0].name);
            })
            .catch(() => { this.roleChips = []; });
    }

    /* ---------------- role chips ---------------- */
    get roleChipRows() {
        return this.roleChips.map(r => {
            const n = this.selectedAudiences.filter(a => a.roleCode === r.code).length;
            return {
                code: r.code, name: r.name, count: n, hasCount: n > 0,
                cls: 'ab-chip' + (r.code === this.activeRole ? ' ab-chip--on' : '')
            };
        });
    }
    handlePickRole(e) {
        this._selectRole(e.currentTarget.dataset.code, e.currentTarget.dataset.name);
    }
    _selectRole(code, name) {
        this.activeRole = code;
        this.activeRoleName = name;
        this._resetFieldState();
        this._loadFields(code);
    }

    /* ---------------- mode (All vs Custom) ---------------- */
    get isAllMode() { return this.mode === 'all'; }
    get isCustomMode() { return this.mode === 'custom'; }
    get allOptionCls() { return 'ab-opt' + (this.mode === 'all' ? ' ab-opt--on' : ''); }
    get customOptionCls() { return 'ab-opt' + (this.mode === 'custom' ? ' ab-opt--on' : ''); }
    get allLabel() { return 'All ' + (this.activeRoleName || 'Members'); }
    get allDesc() { return 'Includes everyone in the ' + (this.activeRoleName || 'role') + ' across all years, programs, and campuses.'; }
    pickAll() { this.mode = 'all'; }
    pickCustom() { this.mode = 'custom'; }
    get noFields() { return this.isCustomMode && !this.loadingFields && (this.roleFields || []).length === 0; }

    /* ---------------- per-role attribute fields ---------------- */
    _resetFieldState() {
        this.fieldValues = {}; this.fieldOptions = {}; this.fieldOpen = {}; this.fieldSearch = {}; this._fieldMeta = {};
    }
    _loadFields(role) {
        this.loadingFields = true;
        getRoleFieldOptions({ role })
            .then(rows => {
                this.roleFields = rows || [];
                const meta = {};
                const opts = {};
                this.roleFields.forEach(f => {
                    meta[f.key] = { objectApi: f.objectApi, fieldApi: f.fieldApi, type: f.type };
                    if (Array.isArray(f.options) && f.options.length) {
                        opts[f.key] = f.options.map(o => ({ value: o.value, label: o.label }));
                    } else if (f.type === 'search') {
                        opts[f.key] = [];
                        this._fetchValues(f.key, f.objectApi, f.fieldApi);
                    } else {
                        opts[f.key] = [];
                    }
                });
                this._fieldMeta = meta;
                this.fieldOptions = opts;
                this.loadingFields = false;
            })
            .catch(() => { this.roleFields = []; this.loadingFields = false; });
    }
    _fetchValues(key, objectApi, fieldApi) {
        // Fetch all distinct values upfront (no search box) — the dropdown scrolls if long.
        searchDistinctFieldValues({ objectApi, fieldApi, searchTerm: '', limitSize: 200 })
            .then(rows => {
                this.fieldOptions = { ...this.fieldOptions, [key]: (rows || []).map(o => ({ value: o.value, label: o.label })) };
            })
            .catch(() => { /* keep prior options */ });
    }

    get fieldRows() {
        return (this.roleFields || []).map(f => {
            const sel = this.fieldValues[f.key] || [];
            const selSet = new Set(sel.map(s => s.value));
            const opts = (this.fieldOptions[f.key] || []).map(o => ({
                value: o.value, label: o.label,
                cls: 'ab-msopt' + (selSet.has(o.value) ? ' ab-msopt--on' : '')
            }));
            return {
                key: f.key, label: f.label,
                placeholder: f.placeholder || 'Choose',
                isSearch: f.type === 'search',
                open: !!this.fieldOpen[f.key],
                searchTerm: this.fieldSearch[f.key] || '',
                chips: sel,
                hasChips: sel.length > 0,
                options: opts,
                hasOptions: opts.length > 0
            };
        });
    }
    toggleFieldMenu(e) {
        e.stopPropagation();
        const key = e.currentTarget.dataset.key;
        const open = !this.fieldOpen[key];
        // Only one field dropdown open at a time — opening one closes the rest.
        this.fieldOpen = open ? { [key]: true } : {};
    }
    stopMenuClick(e) { e.stopPropagation(); }
    toggleFieldValue(e) {
        e.stopPropagation();
        const key = e.currentTarget.dataset.key;
        const value = e.currentTarget.dataset.value;
        const label = e.currentTarget.dataset.label;
        const arr = [...(this.fieldValues[key] || [])];
        const idx = arr.findIndex(x => x.value === value);
        if (idx >= 0) arr.splice(idx, 1); else arr.push({ value, label });
        this.fieldValues = { ...this.fieldValues, [key]: arr };
    }
    removeFieldChip(e) {
        e.stopPropagation();
        const key = e.currentTarget.dataset.key;
        const value = e.currentTarget.dataset.value;
        this.fieldValues = { ...this.fieldValues, [key]: (this.fieldValues[key] || []).filter(x => x.value !== value) };
    }

    /* ---------------- add / remove audience ---------------- */
    handleAudienceName(e) { this.audienceName = e.target.value; }
    get canAdd() { return !!this.activeRole; }
    get addDisabled() { return !this.canAdd; }

    _buildCriteria() {
        if (this.mode === 'all') return [];
        return (this.roleFields || [])
            .filter(f => (this.fieldValues[f.key] || []).length > 0)
            .map(f => ({
                key: f.key, label: f.label, fieldApi: f.fieldApi,
                values: (this.fieldValues[f.key] || []).map(x => x.value)
            }));
    }
    _targetObject() {
        const f = (this.roleFields || []).find(x => x.objectApi);
        return f ? f.objectApi : null;
    }
    handleAddToAudience() {
        if (!this.activeRole) return;
        this._aSeq += 1;
        const id = 'aud-' + this._aSeq;
        const criteria = this._buildCriteria();
        const isAll = this.mode === 'all' || criteria.length === 0;
        const name = (this.audienceName && this.audienceName.trim())
            || (isAll ? this.allLabel : (this.activeRoleName + ' — Custom'));
        const audience = { id, name, roleCode: this.activeRole, roleName: this.activeRoleName, count: null, criteria, isAll };
        this.selectedAudiences = [...this.selectedAudiences, audience];
        this._resetForm();
        this._emit();
        this._fetchCount(audience);
    }
    _fetchCount(audience) {
        const payload = {
            targetObject: this._targetObject(),
            items: [{ id: audience.id, type: audience.roleCode, criteria: audience.criteria }]
        };
        getAudienceCounts({ payloadJson: JSON.stringify(payload) })
            .then(rows => {
                const hit = (rows || []).find(r => r.id === audience.id);
                const c = hit && hit.count != null ? hit.count : 0;
                this.selectedAudiences = this.selectedAudiences.map(a => a.id === audience.id ? { ...a, count: c } : a);
                this._emit();
            })
            .catch(() => { /* leave count null → shows "—" */ });
    }
    handleRemoveAudience(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedAudiences = this.selectedAudiences.filter(a => a.id !== id);
        this._emit();
    }
    _resetForm() { this.audienceName = ''; this.mode = 'all'; this._resetFieldState(); if (this.activeRole) this._loadFields(this.activeRole); }

    /* ---------------- selected audience panel ---------------- */
    get hasSelectedAudiences() { return this.selectedAudiences.length > 0; }
    get selectedAudienceCards() {
        return this.selectedAudiences.map(a => ({
            id: a.id, name: a.name, roleName: a.roleName,
            memberLabel: a.count == null ? '—' : (a.count + ' Members')
        }));
    }

    _emit() {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'audiences', value: this.selectedAudiences.map(a => ({ ...a })) }
        }));
    }
}