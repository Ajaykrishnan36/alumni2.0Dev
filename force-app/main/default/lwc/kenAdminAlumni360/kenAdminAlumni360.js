import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAlumni360 from '@salesforce/apex/KenAdminAlumni360Controller.getAlumni360';
import getEditableFields from '@salesforce/apex/KenAdminAlumni360Controller.getEditableFields';
import updateAlumniProfile from '@salesforce/apex/KenAdminAlumni360Controller.updateAlumniProfile';
import getAcademicEditData from '@salesforce/apex/KenAdminAlumni360Controller.getAcademicEditData';
import getCareerEditData from '@salesforce/apex/KenAdminAlumni360Controller.getCareerEditData';
import saveEducationRows from '@salesforce/apex/KenAdminAlumni360Controller.saveEducationRows';
import saveEmploymentRows from '@salesforce/apex/KenAdminAlumni360Controller.saveEmploymentRows';
import getPortalConfigs from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';
// The tabs Contact/Portal/Requests/Update History/Activity used to live on the
// removed Overview modal. Their data sources still live on KenAdminAlumniController.
import getAlumniDetail from '@salesforce/apex/KenAdminAlumniController.getAlumniDetail';
import getActivityTimeline from '@salesforce/apex/KenAdminAlumniController.getActivityTimeline';
import getFieldUpdateHistory from '@salesforce/apex/KenAdminAlumniController.getFieldUpdateHistory';

/**
 * kenAdminAlumni360
 *
 * Single-record Alumni 360 detail view. Opened as a full-screen overlay from
 * kenAdminAlumni's "View 360" button — recordId is passed via @api and used
 * to wire KenAdminAlumni360Controller.getAlumni360(recordId).
 *
 * Layout:
 *   - Thin sticky header with title + close button
 *   - Hero banner (bound to data.header)
 *   - 2 KPI snapshot cards (career + engagement)
 *   - Tabs: Overview, Career, Engagement, Support — every value bound to DTOs
 *   - Right rail: Needs Attention, Recent Activity, Quick Actions, Record Health
 */
export default class KenAdminAlumni360 extends LightningElement {
    // Ken_Alumni_CRM__c Id of the alumnus to render.
    @api recordId;

    @track data;
    @track error;
    @track loading = true;
    @track activeTab = 'overview';
    @track detailExtra;             // getAlumniDetail() — backs Contact tab
    @track timelineRowsRaw = [];    // getActivityTimeline() — backs Activity tab
    @track historyRowsRaw = [];     // getFieldUpdateHistory() — backs Update History tab

    // Capture each wire result so the in-screen Refresh button (and the
    // LinkedIn-sync completion handler) can rerun them via refreshApex.
    _alumni360WireResult;
    _detailWireResult;
    _timelineWireResult;
    _historyWireResult;
    @track isRefreshing = false;

    /* ---- Inline edit state ---- */
    @track editingTab = null;          // 'overview' | 'contact' when a tab is being edited
    @track edit = {};                  // working copy of editable values, keyed by field
    @track saving = false;
    _editableRaw = {};                 // last raw values from getEditableFields (the diff baseline)
    _editableWireResult;

    // Which displayed labels map to which editable field + input type. Rows whose
    // label isn't here stay read-only even in edit mode (they're derived values).
    SNAPSHOT_FIELDS = {
        'Class of':         { key: 'classOf',        type: 'text', crm: true },
        'Current employer': { key: 'currentCompany', type: 'text', crm: true }
    };
    CONTACT_FIELDS = {
        'Phone':            { key: 'phone',       type: 'tel' },
        'Email (personal)': { key: 'email',       type: 'email' },
        'Email (alumni)':   { key: 'email',       type: 'email' },
        'LinkedIn':         { key: 'linkedin',    type: 'text' },
        'Date of birth':    { key: 'dob',         type: 'date' },
        'Nationality':      { key: 'nationality', type: 'select', optionsKey: 'nationalityOptions' },
        'Languages':        { key: 'languages',   type: 'text' },
        'Address':          { key: 'address',     type: 'text', address: true }
    };

    /* ---- Child-record edit state (Education / Employment) ---- */
    @track eduEditing = false;
    @track eduRows = [];
    @track eduDeleted = [];
    @track eduSaving = false;
    @track gradeTypeOptions = [];
    _academicEditRaw = { editable: false, rows: [] };
    _academicEditWireResult;
    _eduKeySeq = 0;

    @track empEditing = false;
    @track empRows = [];
    @track empDeleted = [];
    @track empSaving = false;
    _careerEditRaw = { editable: false, rows: [] };
    _careerEditWireResult;
    _empKeySeq = 0;

    @wire(getAlumni360, { recordId: '$recordId' })
    wiredAlumni360(result) {
        this._alumni360WireResult = result;
        const { data, error } = result;
        if (data) {
            this.data = data;
            this.loading = false;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.loading = false;
        }
    }

    @wire(getAlumniDetail, { alumniId: '$recordId' })
    wiredDetail(result) {
        this._detailWireResult = result;
        if (result.data) this.detailExtra = result.data;
    }

    @wire(getActivityTimeline, { alumniId: '$recordId' })
    wiredTimeline(result) {
        this._timelineWireResult = result;
        if (result.data) this.timelineRowsRaw = result.data;
    }

    @wire(getFieldUpdateHistory, { alumniId: '$recordId' })
    wiredHistory(result) {
        this._historyWireResult = result;
        if (result.data) this.historyRowsRaw = result.data;
    }

    @wire(getEditableFields, { recordId: '$recordId' })
    wiredEditable(result) {
        this._editableWireResult = result;
        if (result.data) this._editableRaw = result.data;
    }

    @wire(getAcademicEditData, { recordId: '$recordId' })
    wiredAcademicEdit(result) {
        this._academicEditWireResult = result;
        if (result.data) {
            this._academicEditRaw = result.data;
            this.gradeTypeOptions = result.data.gradeTypeOptions || [];
        }
    }

    @wire(getCareerEditData, { recordId: '$recordId' })
    wiredCareerEdit(result) {
        this._careerEditWireResult = result;
        if (result.data) this._careerEditRaw = result.data;
    }

    /**
     * Refetches every wire driving the 360 — bound to the topbar Refresh button
     * and also called from the LinkedIn-sync `onsynccomplete` event so the
     * page rehydrates in place instead of full-reloading.
     */
    async handleRefresh() {
        if (this.isRefreshing) return;
        this.isRefreshing = true;
        try {
            await Promise.all([
                this._alumni360WireResult ? refreshApex(this._alumni360WireResult) : Promise.resolve(),
                this._detailWireResult    ? refreshApex(this._detailWireResult)    : Promise.resolve(),
                this._timelineWireResult  ? refreshApex(this._timelineWireResult)  : Promise.resolve(),
                this._historyWireResult   ? refreshApex(this._historyWireResult)   : Promise.resolve(),
                this._editableWireResult  ? refreshApex(this._editableWireResult)  : Promise.resolve(),
                this._academicEditWireResult ? refreshApex(this._academicEditWireResult) : Promise.resolve(),
                this._careerEditWireResult   ? refreshApex(this._careerEditWireResult)   : Promise.resolve()
            ]);
        } finally {
            this.isRefreshing = false;
        }
    }

    // Called by <c-ken-linked-in-sync-button onsynccomplete=...> after a
    // successful sync, so we can rehydrate without a full page reload.
    handleLinkedInSyncComplete() {
        this.handleRefresh();
    }

    // Theme tokens — keep wire so org brand colours still apply at runtime.
    // Only PRIMARY and SECONDARY are applied; the tertiary colour is
    // intentionally ignored. All tinted surfaces are derived from primary
    // (over white) in CSS, with white as the fallback.
    @wire(getPortalConfigs)
    wiredTheme({ data }) {
        if (!data) return;
        const host = this.template.host;
        if (data.primaryColor)   host.style.setProperty('--brand-primary',   data.primaryColor);
        if (data.secondaryColor) host.style.setProperty('--brand-secondary', data.secondaryColor);
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    /* ---- Tab visibility flags ---- */
    get isOverview()   { return this.activeTab === 'overview'; }
    get isAcademic()   { return this.activeTab === 'academic'; }
    get isCareer()     { return this.activeTab === 'career'; }
    get isEngagement() { return this.activeTab === 'engagement'; }
    get isSupport()    { return this.activeTab === 'support'; }
    // Ported from the removed Overview modal.
    get isContact()    { return this.activeTab === 'contact'; }
    get isPortal()     { return this.activeTab === 'portal'; }
    get isRequests()   { return this.activeTab === 'requests'; }
    get isHistory()    { return this.activeTab === 'history'; }
    get isActivity()   { return this.activeTab === 'activity'; }

    /* ---- Active-class helpers ---- */
    tabClass(id)    { return 'tab'    + (this.activeTab === id ? ' active' : ''); }
    subTabClass(id) { return 'subtab' + (this.activeTab === id ? ' active' : ''); }

    get cOverview()   { return this.tabClass('overview'); }
    get cAcademic()   { return this.tabClass('academic'); }
    get cCareer()     { return this.tabClass('career'); }
    get cEngagement() { return this.tabClass('engagement'); }
    get cSupport()    { return this.subTabClass('support'); }
    get cContact()    { return this.tabClass('contact'); }
    get cPortal()     { return this.tabClass('portal'); }
    get cRequests()   { return this.tabClass('requests'); }
    get cHistory()    { return this.tabClass('history'); }
    get cActivity()   { return this.tabClass('activity'); }

    /* ---- View-models for the ported tabs ---- */
    get detailEmail()       { return (this.detailExtra && this.detailExtra.email) || ''; }
    get detailPhone()       { return (this.detailExtra && this.detailExtra.phone) || ''; }
    get detailLinkedin()    { return (this.detailExtra && this.detailExtra.linkedinUrl) || ''; }
    get detailRegDate() {
        const d = this.detailExtra && this.detailExtra.registrationDate;
        return d ? this._formatDate(d) : '—';
    }
    get detailLastLogin() {
        const d = this.detailExtra && this.detailExtra.lastLogin;
        return d ? this._formatDate(d) : '—';
    }
    get emailVisibilityLabel() { return (this.detailExtra && this.detailExtra.hideEmail) ? 'Hidden' : 'Visible'; }
    get phoneVisibilityLabel() { return (this.detailExtra && this.detailExtra.hidePhone) ? 'Hidden' : 'Visible'; }
    get emailVisibilityPillClass() { return (this.detailExtra && this.detailExtra.hideEmail) ? 'pill neutral' : 'pill success'; }
    get phoneVisibilityPillClass() { return (this.detailExtra && this.detailExtra.hidePhone) ? 'pill neutral' : 'pill success'; }

    get timelineRows() {
        return (this.timelineRowsRaw || []).map((t, i) => ({
            ...t,
            key: 't-' + i,
            dateLabel: t.occurredOn ? this._formatDate(t.occurredOn) : ''
        }));
    }
    get hasTimelineRows() { return this.timelineRows.length > 0; }

    get historyRows() {
        return (this.historyRowsRaw || []).map((h, i) => ({
            ...h,
            key: 'h-' + i,
            dateLabel: h.changedOn ? this._formatDate(h.changedOn) : '',
            sourceTag: h.source || 'admin'
        }));
    }
    get hasHistoryRows() { return this.historyRows.length > 0; }

    // Requests tab — re-uses the Case data already on data.support.tickets so
    // every case the alumnus raised lands here too.
    get requestRows() {
        const tickets = (this.data && this.data.support && this.data.support.tickets) || [];
        return tickets.map((t) => ({
            ...t,
            openedLabel: t.opened || t.openedOn || ''
        }));
    }
    get hasRequestRows() { return this.requestRows.length > 0; }

    _formatDate(value) {
        if (!value) return '';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return '';
        return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: '2-digit' });
    }

    /* ---- Error message string for the template ---- */
    get errorMessage() {
        if (!this.error) return '';
        if (this.error.body && this.error.body.message) return this.error.body.message;
        if (this.error.message) return this.error.message;
        return 'Unknown error';
    }

    /* ---- Badges with computed CSS class so the template can render
           the right tone (emerald/amber/sky/violet/teal/rose/gray). ---- */
    get badgesView() {
        const badges = this.data && this.data.header && this.data.header.badges;
        if (!badges || !badges.length) return [];
        return badges.map(b => ({
            label: b.label,
            toneClass: 'pill ' + (b.tone || 'gray')
        }));
    }

    get hasBadges() {
        return this.badgesView.length > 0;
    }

    get hasNoEducation() {
        return !!(this.data && this.data.academic && (!this.data.academic.education || this.data.academic.education.length === 0));
    }

    /* ============================================================
       Inline edit — per-tab edit / save (SF-standard style)
       ============================================================ */
    get isEditingOverview() { return this.editingTab === 'overview'; }
    get isEditingContact()  { return this.editingTab === 'contact'; }
    get crmEditable()       { return !!(this._editableRaw && this._editableRaw.crmEditable); }
    get accountEditable()   { return !!(this._editableRaw && this._editableRaw.accountEditable); }

    /**
     * Augment the Overview "snapshot" KeyValue rows with edit metadata so the
     * template can swap the value for an input when this tab is being edited.
     */
    get overviewSnapshotRows() {
        const rows = (this.data && this.data.overview && this.data.overview.snapshot) || [];
        return rows.map((row, i) => this._decorate(row, i, this.SNAPSHOT_FIELDS, this.isEditingOverview, true));
    }

    get overviewContactRows() {
        const rows = (this.data && this.data.overview && this.data.overview.personalContact) || [];
        return rows.map((row, i) => this._decorate(row, i, this.CONTACT_FIELDS, this.isEditingOverview, false));
    }

    // Contact tab — explicit fields (email/phone/linkedin) bound to edit model.
    get contactEditEmail()    { return this.edit.email || ''; }
    get contactEditPhone()    { return this.edit.phone || ''; }
    get contactEditLinkedin() { return this.edit.linkedin || ''; }

    _decorate(row, i, map, editing) {
        const cfg = map[row.label];
        // CRM-backed fields are only editable when a real CRM row exists;
        // account-backed fields require an editable Person Account.
        const allowed = cfg && (cfg.crm ? this.crmEditable : this.accountEditable);
        const editableNow = !!(editing && allowed);
        // Picklist-backed fields supply their options via the editable payload.
        // If the org has no options (field is still Text), fall back to text.
        const rawOptions = cfg && cfg.optionsKey ? this._editableRaw[cfg.optionsKey] : null;
        const options = Array.isArray(rawOptions) ? rawOptions : [];
        const isSelect = !!(cfg && cfg.type === 'select') && options.length > 0;
        return {
            key: row.label + '-' + i,
            label: row.label,
            value: (row.value === null || row.value === undefined || row.value === '') ? '—' : row.value,
            emphasis: row.emphasis,
            editableNow,
            isAddress: !!(cfg && cfg.address),
            isSelect,
            options,
            fieldKey: cfg ? cfg.key : null,
            type: cfg ? (isSelect ? 'text' : cfg.type) : 'text',
            editValue: cfg ? (this.edit[cfg.key] == null ? '' : this.edit[cfg.key]) : ''
        };
    }

    // Address sub-fields (bound directly in the Address row when editing).
    get addrStreet()  { return this.edit.street || ''; }
    get addrCity()    { return this.edit.city || ''; }
    get addrState()   { return this.edit.state || ''; }
    get addrPostal()  { return this.edit.postalCode || ''; }
    get addrCountry() { return this.edit.country || ''; }

    handleEditOverview() { this._beginEdit('overview'); }
    handleEditContact()  { this._beginEdit('contact'); }

    _beginEdit(tab) {
        // Seed the working copy from the raw editable values.
        this.edit = Object.assign({}, this._editableRaw);
        this.editingTab = tab;
    }

    handleCancelEdit() {
        this.editingTab = null;
        this.edit = {};
    }

    handleEditChange(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) return;
        // lightning-input checkbox would use .checked; all our fields are value-based.
        this.edit = Object.assign({}, this.edit, { [key]: event.detail ? event.detail.value : event.target.value });
    }

    async handleSaveEdit() {
        if (this.saving) return;
        // Native validation on every input in the active edit pane.
        const inputs = this.template.querySelectorAll('.a360-edit-input');
        let valid = true;
        inputs.forEach(inp => { if (typeof inp.reportValidity === 'function' && !inp.reportValidity()) valid = false; });
        if (!valid) return;

        // Diff against the baseline — send only the keys that actually changed.
        const changes = {};
        Object.keys(this.edit).forEach(k => {
            if (k === 'crmEditable' || k === 'accountEditable') return;
            const before = this._editableRaw[k];
            const after = this.edit[k];
            const norm = v => (v === null || v === undefined) ? '' : String(v);
            if (norm(before) !== norm(after)) changes[k] = after === '' ? null : after;
        });

        if (Object.keys(changes).length === 0) {
            this.handleCancelEdit();
            return;
        }

        this.saving = true;
        try {
            await updateAlumniProfile({ recordId: this.recordId, changesJson: JSON.stringify(changes) });
            this.editingTab = null;
            this.edit = {};
            await this.handleRefresh();
            this.dispatchEvent(new ShowToastEvent({
                title: 'Saved', message: 'Profile updated.', variant: 'success'
            }));
        } catch (e) {
            const msg = (e && e.body && e.body.message) ? e.body.message : 'Could not save changes.';
            this.dispatchEvent(new ShowToastEvent({ title: 'Save failed', message: msg, variant: 'error' }));
        } finally {
            this.saving = false;
        }
    }

    /* ============================================================
       Education (PersonEducation) — row-level inline edit
       ============================================================ */
    get academicEditable() { return !!(this._academicEditRaw && this._academicEditRaw.editable); }
    get eduRowsEmpty() { return this.eduRows.length === 0; }

    handleEditAcademic() {
        const rows = (this._academicEditRaw && this._academicEditRaw.rows) || [];
        this.eduRows = rows.map(r => ({
            key: 'edu-' + (this._eduKeySeq++),
            id: r.id || '',
            institute: r.institute || '',
            degree: r.degree || '',
            gradeType: r.gradeType || '',
            grade: r.grade || '',
            yearOfCompletion: r.yearOfCompletion || ''
        }));
        this.eduDeleted = [];
        this.eduEditing = true;
    }

    handleAddEducation() {
        this.eduRows = [...this.eduRows, {
            key: 'edu-' + (this._eduKeySeq++), id: '',
            institute: '', degree: '', gradeType: '', grade: '', yearOfCompletion: ''
        }];
    }

    handleRemoveEducation(event) {
        const k = event.currentTarget.dataset.rowkey;
        const row = this.eduRows.find(r => r.key === k);
        if (row && row.id) this.eduDeleted = [...this.eduDeleted, row.id];
        this.eduRows = this.eduRows.filter(r => r.key !== k);
    }

    handleEduChange(event) {
        const k = event.currentTarget.dataset.rowkey;
        const field = event.currentTarget.dataset.field;
        const val = event.detail ? event.detail.value : event.target.value;
        this.eduRows = this.eduRows.map(r => r.key === k ? { ...r, [field]: val } : r);
    }

    handleCancelAcademic() {
        this.eduEditing = false;
        this.eduRows = [];
        this.eduDeleted = [];
    }

    async handleSaveAcademic() {
        if (this.eduSaving) return;
        const inputs = this.template.querySelectorAll('.a360-edu-input');
        let valid = true;
        inputs.forEach(inp => { if (typeof inp.reportValidity === 'function' && !inp.reportValidity()) valid = false; });
        if (!valid) return;

        const payload = this.eduRows.map(r => ({
            id: r.id || null, institute: r.institute, degree: r.degree,
            gradeType: r.gradeType, grade: r.grade, yearOfCompletion: r.yearOfCompletion
        }));
        this.eduSaving = true;
        try {
            await saveEducationRows({
                recordId: this.recordId,
                rowsJson: JSON.stringify(payload),
                deleteIdsJson: JSON.stringify(this.eduDeleted)
            });
            this.eduEditing = false;
            this.eduRows = [];
            this.eduDeleted = [];
            await this.handleRefresh();
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Education updated.', variant: 'success' }));
        } catch (e) {
            const msg = (e && e.body && e.body.message) ? e.body.message : 'Could not save education.';
            this.dispatchEvent(new ShowToastEvent({ title: 'Save failed', message: msg, variant: 'error' }));
        } finally {
            this.eduSaving = false;
        }
    }

    /* ============================================================
       Employment (PersonEmployment) — row-level inline edit
       ============================================================ */
    get careerEditable() { return !!(this._careerEditRaw && this._careerEditRaw.editable); }
    get empRowsEmpty() { return this.empRows.length === 0; }

    handleEditCareer() {
        const rows = (this._careerEditRaw && this._careerEditRaw.rows) || [];
        this.empRows = rows.map(r => ({
            key: 'emp-' + (this._empKeySeq++),
            id: r.id || '',
            role: r.role || '',
            company: r.company || '',
            location: r.location || '',
            startDate: r.startDate || '',
            endDate: r.endDate || '',
            current: r.current === true,
            description: r.description || ''
        }));
        this.empDeleted = [];
        this.empEditing = true;
    }

    handleAddEmployment() {
        this.empRows = [...this.empRows, {
            key: 'emp-' + (this._empKeySeq++), id: '',
            role: '', company: '', location: '', startDate: '', endDate: '', current: false, description: ''
        }];
    }

    handleRemoveEmployment(event) {
        const k = event.currentTarget.dataset.rowkey;
        const row = this.empRows.find(r => r.key === k);
        if (row && row.id) this.empDeleted = [...this.empDeleted, row.id];
        this.empRows = this.empRows.filter(r => r.key !== k);
    }

    handleEmpChange(event) {
        const k = event.currentTarget.dataset.rowkey;
        const field = event.currentTarget.dataset.field;
        let val;
        if (field === 'current') val = event.target.checked;
        else val = event.detail ? event.detail.value : event.target.value;
        this.empRows = this.empRows.map(r => r.key === k ? { ...r, [field]: val } : r);
    }

    handleCancelCareer() {
        this.empEditing = false;
        this.empRows = [];
        this.empDeleted = [];
    }

    async handleSaveCareer() {
        if (this.empSaving) return;
        const inputs = this.template.querySelectorAll('.a360-emp-input');
        let valid = true;
        inputs.forEach(inp => { if (typeof inp.reportValidity === 'function' && !inp.reportValidity()) valid = false; });
        if (!valid) return;

        const payload = this.empRows.map(r => ({
            id: r.id || null, role: r.role, company: r.company, location: r.location,
            startDate: r.startDate || null, endDate: r.endDate || null,
            current: r.current === true, description: r.description
        }));
        this.empSaving = true;
        try {
            await saveEmploymentRows({
                recordId: this.recordId,
                rowsJson: JSON.stringify(payload),
                deleteIdsJson: JSON.stringify(this.empDeleted)
            });
            this.empEditing = false;
            this.empRows = [];
            this.empDeleted = [];
            await this.handleRefresh();
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Employment updated.', variant: 'success' }));
        } catch (e) {
            const msg = (e && e.body && e.body.message) ? e.body.message : 'Could not save employment.';
            this.dispatchEvent(new ShowToastEvent({ title: 'Save failed', message: msg, variant: 'error' }));
        } finally {
            this.empSaving = false;
        }
    }

    /* ---- Handlers ---- */
    handleTab(event) {
        // Leaving a tab abandons any unsaved inline edit on it.
        if (this.editingTab) { this.editingTab = null; this.edit = {}; }
        if (this.eduEditing) this.handleCancelAcademic();
        if (this.empEditing) this.handleCancelCareer();
        this.activeTab = event.currentTarget.dataset.tab;
    }
}