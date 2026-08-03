import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getPortalConfigs from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';
import getAlumniRecords from '@salesforce/apex/KenAdminAlumniController.getAlumniRecords';
import getAlumniDetail from '@salesforce/apex/KenAdminAlumniController.getAlumniDetail';
import getMergeCandidates from '@salesforce/apex/KenAdminAlumniController.getMergeCandidates';
import getMergeSuggestions from '@salesforce/apex/KenAdminAlumniController.getMergeSuggestions';
import getContactIssue from '@salesforce/apex/KenAdminAlumniController.getContactIssue';
import getActivityTimeline from '@salesforce/apex/KenAdminAlumniController.getActivityTimeline';
import getFieldUpdateHistory from '@salesforce/apex/KenAdminAlumniController.getFieldUpdateHistory';
import saveContactEmail from '@salesforce/apex/KenAdminAlumniController.saveContactEmail';
import saveContactPhone from '@salesforce/apex/KenAdminAlumniController.saveContactPhone';
import getTabCounts from '@salesforce/apex/KenAdminAlumniController.getTabCounts';
import getIssueChipCounts from '@salesforce/apex/KenAdminAlumniController.getIssueChipCounts';
import convertLeads from '@salesforce/apex/KenAdminAlumniController.convertLeads';
import rejectLead from '@salesforce/apex/KenAdminAlumniController.rejectLead';
import mergeLeadIntoMaster from '@salesforce/apex/KenAdminAlumniController.mergeLeadIntoMaster';
import getMergeFieldComparison from '@salesforce/apex/KenAdminAlumniController.getMergeFieldComparison';
import getMergeFieldComparisonMulti from '@salesforce/apex/KenAdminAlumniController.getMergeFieldComparisonMulti';
import mergeCandidatesIntoOne from '@salesforce/apex/KenAdminAlumniController.mergeCandidatesIntoOne';
import getFilterOptions from '@salesforce/apex/KenAdminAlumniController.getFilterOptions';
import getAssignableOwners from '@salesforce/apex/KenAdminAlumniController.getAssignableOwners';
import changeLeadOwner from '@salesforce/apex/KenAdminAlumniController.changeLeadOwner';
import logCommunication from '@salesforce/apex/KenAdminAlumniController.logCommunication';
import getCommunicationLog from '@salesforce/apex/KenAdminAlumniController.getCommunicationLog';

const PAGE_SIZE = 25;

// ---- URL state contract -----------------------------------------------
// The whole screen is addressable, so a refresh (or a pasted link) reopens
// exactly what was on screen instead of dropping back to the default view:
//
//   ?page=list&tab=leads                      master list, Leads tab
//   ?page=list&tab=issues&chip=bounce         list + data-issue chip
//   ?page=alumni360&alumni=<id>&sub=career    Alumni 360 on its Career tab
//   ?page=lead&alumni=<leadId>&sub=merge      lead workspace, Merge & Lookup
//   ?page=referral&alumni=<leadId>&sub=owner  referral workspace, Change Owner
//   ?page=issues&alumni=<id>                  fix-contact panel
//   ?page=map                                 alumni distribution map
//
// Params are written straight onto the address bar with history.replaceState
// rather than NavigationMixin: this component lives inside the FlexiPage
// tabset on the Alumni Management home page, and a real Lightning navigation
// would reload that page and throw the user back to the Dashboard sub-tab.
// Reads accept the `c__`-prefixed names too, since that is what LEX itself
// produces when a link carries custom params.
const URL_KEYS = ['page', 'alumni', 'tab', 'sub', 'chip'];
const VALID_PAGES = ['list', 'alumni360', 'lead', 'referral', 'issues', 'map'];
const VALID_TABS = ['all', 'recent', 'registered', 'oldportal', 'issues', 'leads', 'referrals'];
const VALID_CHIPS = ['all', 'mail', 'phone', 'invmail', 'bounce', 'invphone'];
const VALID_LEAD_SUBS = ['merge', 'activity', 'comm', 'owner', 'history'];

const EMPTY_FILTERS = {
    // Legacy keys kept so any other consumer of `selectedFilters` keeps working.
    program: '', graduationYear: '', source: '',
    company: '', industry: '', location: '', country: '',
    // New Master-records filter set
    institute: '', role: '', domain: '', intake: '', skill: '', status: '', preference: '', employmentType: '', gender: '',
    // Checkbox multi-select — array-valued, unlike every other key above.
    language: []
};

export default class KenAdminAlumni extends NavigationMixin(LightningElement) {
    @track activeTab = 'all';
    @track activeModal = null;
    @track activeInnerTab = 'overview';
    // Lead / Referral workspace canvas tab — which pane the right side shows.
    // Defaults to 'merge' since reaching a master record is the goal state.
    @track activeLeadTab = 'merge';

    // Communication composer state (logs a Task/Activity per the agreed model).
    @track commChannel = 'email';
    @track commSubject = '';
    @track commBody = '';
    @track isLoggingComm = false;
    @track commLogRaw = [];

    // Owner reassignment state.
    @track ownerSearchTerm = '';
    @track ownerOptions = [];
    @track ownerOptionsLoading = false;
    @track selectedNewOwnerId = '';
    @track ownerReason = '';
    @track isReassigning = false;
    _ownerSearchDebounce;
    _ownerSearchSeq = 0;
    @track activeIssueChip = 'all';
    @track personName = '';
    @track personInitials = '';

    @track searchTerm = '';
    @track activePortalStatus = '';
    @track activeDashboardFilter = '';
    @track portalStatusOpen = false;

    @track showFiltersPopup = false;
    @track showMapModal = false;
    mapModalHeight = 560;
    @track selectedFilters = { ...EMPTY_FILTERS };
    @track appliedFiltersJson = '';
    @track filterOptionsRaw = {};
    @track currentPage = 1;
    @track selectedAlumniId = null;
    @track showAlumni360 = false;

    // mergeSearchTerm mirrors the input and is written on every keystroke;
    // mergeAppliedTerm is the debounced copy the wire reacts to.
    @track mergeSearchTerm = '';
    @track mergeAppliedTerm = '';
    @track mergeGradYear = '';
    @track capturedGradYear = '';
    @track capturedRegNumber = '';
    @track capturedDateLabel = '';
    @track capturedSource = '';
    @track capturedReferredBy = '';
    @track capturedExistingAccountId = '';
    @track capturedExistingAccountName = '';
    @track capturedIsNewRole = false;

    _searchDebounce;
    _mergeSearchDebounce;

    @track alumniList;
    @track alumniListLoading = true;
    @track alumniDetail;
    @track alumniDetailLoading = false;
    @track mergeCandidates = [];
    @track mergeCandidatesLoading = false;
    @track isRejecting = false;
    @track isMerging = false;
    @track selectedCandidateIds = [];

    // Merge review step — shown after a candidate is picked, before the merge
    // actually runs. Lets the admin see (and, per field, override) what the
    // master record will look like post-merge instead of it happening silently.
    @track mergeReviewActive = false;
    @track mergeReviewLoading = false;
    @track mergeReviewMasterName = '';
    @track mergeReviewRows = [];
    _mergeReviewMasterRoleId = null;

    // N-way review — shown when 2+ candidates are checked at once. The admin
    // resolves each field across all N candidates, then picks exactly ONE of
    // them via mergeMultiTargetId as the surviving record those resolved
    // values actually get written to — the other candidates are left
    // untouched (reconciling those is still a separate, open question).
    @track mergeMultiReviewActive = false;
    @track mergeMultiReviewLoading = false;
    @track mergeMultiReviewMasterNames = [];
    @track mergeMultiReviewRows = [];
    @track mergeMultiTargetId = '';
    @track isMergingMulti = false;
    _mergeMultiReviewMasterRoleIds = [];

    @track contactIssue;
    @track issueEmailValue = '';
    @track issuePhoneValue = '';
    @track issueEmailError = null;
    @track issuePhoneError = null;
    @track isSavingEmail = false;
    @track isSavingPhone = false;

    @track timelineRowsRaw = [];
    @track historyRowsRaw = [];
    @track tabCounts = {};
    @track issueChipCounts = {};
    @track selectedLeadIds = [];
    @track isConverting = false;
    _wiredListResult;
    _wiredCountsResult;
    _wiredIssueChipCountsResult;

    @wire(getPortalConfigs)
    wiredTheme({ data }) {
        if (!data) return;
        const host = this.template.host;
        if (data.primaryColor) {
            host.style.setProperty('--brand-primary',      data.primaryColor);
            host.style.setProperty('--brand-primary-soft', this._toSoft(data.primaryColor));
        }
        if (data.secondaryColor) host.style.setProperty('--brand-secondary', data.secondaryColor);
        if (data.tertiaryColor)  host.style.setProperty('--brand-tertiary',  data.tertiaryColor);
    }

    _toSoft(hex) {
        if (!hex || typeof hex !== 'string') return 'rgba(185,28,92,.10)';
        const v = hex.replace('#', '');
        if (v.length !== 3 && v.length !== 6) return 'rgba(185,28,92,.10)';
        const e = v.length === 3 ? v.split('').map(c => c + c).join('') : v;
        const r = parseInt(e.slice(0, 2), 16);
        const g = parseInt(e.slice(2, 4), 16);
        const b = parseInt(e.slice(4, 6), 16);
        return `rgba(${r},${g},${b},.10)`;
    }

    @wire(getAlumniRecords, { tabKey: '$activeTab', searchTerm: '$searchTerm', issueType: '$activeIssueChip', portalStatus: '$activePortalStatus', pageSize: PAGE_SIZE, pageNumber: '$currentPage', dashboardFilter: '$activeDashboardFilter', filtersJson: '$appliedFiltersJson' })
    wiredList(result) {
        this._wiredListResult = result;
        const { data, error } = result;
        if (data) {
            this.alumniList = data;
            this.alumniListLoading = false;
        } else if (error) {
            this.alumniList = { rows: [], totalRecords: 0 };
            this.alumniListLoading = false;
        } else {
            this.alumniListLoading = true;
        }
    }

    @wire(getTabCounts, { dashboardFilter: '$activeDashboardFilter' })
    wiredCounts(result) {
        this._wiredCountsResult = result;
        if (result.data) this.tabCounts = result.data;
    }

    @wire(getIssueChipCounts, { dashboardFilter: '$activeDashboardFilter' })
    wiredIssueChipCounts(result) {
        this._wiredIssueChipCountsResult = result;
        if (result.data) this.issueChipCounts = result.data;
    }

    @wire(getFilterOptions, { tabKey: '$activeTab', dashboardFilter: '$activeDashboardFilter' })
    wiredFilterOptions({ data, error }) {
        if (data) {
            this.filterOptionsRaw = data;
        } else if (error) {
            this.filterOptionsRaw = {};
            // eslint-disable-next-line no-console
            console.error('Filter options failed to load', error);
        }
    }

    @wire(getActivityTimeline, { alumniId: '$detailWireId' })
    wiredTimeline(result) {
        this._wiredTimelineResult = result;
        if (result.data) this.timelineRowsRaw = result.data;
    }

    @wire(getFieldUpdateHistory, { alumniId: '$detailWireId' })
    wiredHistory({ data }) {
        if (data) this.historyRowsRaw = data;
    }

    @wire(getCommunicationLog, { alumniId: '$detailWireId' })
    wiredCommLog(result) {
        this._wiredCommLogResult = result;
        if (result.data) this.commLogRaw = result.data;
    }

    @wire(getContactIssue, { alumniId: '$issueWireId' })
    wiredIssue({ data }) {
        if (data) {
            this.contactIssue = data;
            if (!this._userEditedEmail) this.issueEmailValue = data.email || '';
            if (!this._userEditedPhone) this.issuePhoneValue = data.phone || '';
        }
    }

    @wire(getAlumniDetail, { alumniId: '$detailWireId' })
    wiredDetail(result) {
        this._wiredDetailResult = result;
        const { data, error } = result;
        if (data) {
            this.alumniDetail = data;
            this.alumniDetailLoading = false;
        } else if (error) {
            this.alumniDetail = null;
            this.alumniDetailLoading = false;
        } else if (this.selectedAlumniId) {
            this.alumniDetailLoading = true;
        }
    }

    @wire(getMergeCandidates, { searchTerm: '$mergeWireSearch', gradYear: '$mergeWireYear', leadId: '$mergeWireLeadId' })
    wiredMerge({ data, error }) {
        if (data) {
            this.mergeCandidates = data;
            this.mergeCandidatesLoading = false;
        } else if (error) {
            this.mergeCandidates = [];
            this.mergeCandidatesLoading = false;
        } else if (this.mergeAppliedTerm) {
            this.mergeCandidatesLoading = true;
        }
    }

    // Reactive wire params: returning `undefined` (not null) tells LWC to skip
    // the Apex call entirely. Returning null still invokes Apex with alumniId=null,
    // which throws "List has no rows for assignment to SObject" server-side.
    get detailWireId() {
        // Fires getAlumniDetail / getActivityTimeline / getFieldUpdateHistory for
        // the alumni modal AND the lead/referral workspace — leads are
        // ConstituentRole rows, so the same detail resolver fills the rail and
        // the activity/history panes with no extra Apex.
        const wants = this.activeModal === 'alumni'
            || this.activeModal === 'lead'
            || this.activeModal === 'referral';
        return (wants && this.selectedAlumniId) ? this.selectedAlumniId : undefined;
    }

    get issueWireId() {
        return (this.activeModal === 'issues' && this.selectedAlumniId) ? this.selectedAlumniId : undefined;
    }

    get mergeWireSearch() {
        // Must return undefined (not '') to skip the wire when there's no term —
        // otherwise it fires with an empty search, and the empty result silently
        // overwrites the auto-loaded suggestions in mergeCandidates.
        if (this.activeModal !== 'lead' && this.activeModal !== 'referral') return undefined;
        return this.mergeAppliedTerm || undefined;
    }

    get mergeWireYear() {
        return (this.activeModal === 'lead' || this.activeModal === 'referral') ? this.mergeGradYear : undefined;
    }

    // Lead context for the candidate search — lets Apex stamp match % on the
    // search results the same way getMergeSuggestions does for suggestions.
    get mergeWireLeadId() {
        if (this.activeModal !== 'lead' && this.activeModal !== 'referral') return undefined;
        return this.selectedAlumniId || undefined;
    }

    get isNewRoleLead() {
        return this.capturedIsNewRole;
    }
    get leadEyebrowState() {
        return this.capturedIsNewRole ? 'NEW ROLE' : 'SELF-DECLARED LEAD';
    }
    get leadEyebrowStatus() {
        return this.capturedIsNewRole ? 'PENDING APPROVAL' : 'UNMERGED';
    }

    /* ---- URL state — every screen is addressable, see URL_KEYS above ---- */

    // The 360's own tab, tracked separately from activeInnerTab (which belongs
    // to the legacy alumni modal, a different surface).
    @track alumni360Tab = 'overview';
    _lastUrlSignature = null;
    _lastUrlState = null;
    _restoringFromUrl = false;

    _urlSignature(s) {
        return URL_KEYS.map((k) => k + '=' + (s[k] || '')).join('&');
    }

    // Reads straight from the address bar rather than CurrentPageReference:
    // the writes below use history.replaceState, which the Lightning router
    // does not observe, so its page reference would go stale immediately.
    _readUrlState() {
        const out = {};
        let params;
        try {
            params = new URLSearchParams(window.location.search);
        } catch (e) {
            params = null;
        }
        URL_KEYS.forEach((key) => {
            const raw = !params ? null
                : (params.get('c__' + key) !== null ? params.get('c__' + key) : params.get(key));
            // Strip surrounding quotes so a hand-typed ?alumni='0Rl…' resolves too.
            out[key] = raw == null ? '' : String(raw).replace(/^['"]|['"]$/g, '').trim();
        });
        return out;
    }

    _applyUrlState(s) {
        this._restoringFromUrl = true;
        try {
            if (VALID_TABS.includes(s.tab)) this.activeTab = s.tab;
            if (VALID_CHIPS.includes(s.chip)) this.activeIssueChip = s.chip;

            const page = VALID_PAGES.includes(s.page) ? s.page : 'list';
            this.activeModal = null;
            this.showAlumni360 = false;
            this.showMapModal = false;

            if (page === 'map') {
                this.handleMapViewOpen();
                return;
            }
            if (page === 'list' || !s.alumni) {
                this.selectedAlumniId = null;
                return;
            }

            this.selectedAlumniId = s.alumni;
            if (page === 'alumni360') {
                this.alumni360Tab = s.sub || 'overview';
                this.activeInnerTab = 'overview';
                this.showAlumni360 = true;
            } else if (page === 'lead' || page === 'referral') {
                this._openWorkspaceFromUrl(page, s.sub);
            } else if (page === 'issues') {
                this._userEditedEmail = false;
                this._userEditedPhone = false;
                this.issueEmailError = null;
                this.issuePhoneError = null;
                this.contactIssue = null;
                this.activeModal = 'issues';
            }
        } finally {
            this._restoringFromUrl = false;
        }
    }

    /**
     * Reopen a lead/referral workspace with no clicked row to read from. The
     * rail fills from the getAlumniDetail wire (it keys off selectedAlumniId),
     * so only the row-captured extras need clearing and the merge suggestions
     * fetching — the same call handleRow makes.
     */
    _openWorkspaceFromUrl(kind, sub) {
        this.mergeSearchTerm = '';
        this.mergeAppliedTerm = '';
        this.mergeGradYear = '';
        this.selectedCandidateIds = [];
        this.capturedGradYear = '—';
        this.capturedRegNumber = '';
        this.capturedSource = '';
        this.capturedDateLabel = '';
        this.capturedReferredBy = '';
        this.capturedExistingAccountId = '';
        this.capturedExistingAccountName = '';
        this.capturedIsNewRole = false;
        this.activeLeadTab = VALID_LEAD_SUBS.includes(sub) ? sub : 'merge';
        this.activeModal = kind;
        this._loadMergeSuggestions(this.selectedAlumniId);
        if (this.activeLeadTab === 'owner') this._loadOwners('');
    }

    _currentUrlState() {
        let page = 'list';
        let sub = '';
        if (this.showMapModal) {
            page = 'map';
        } else if (this.showAlumni360) {
            page = 'alumni360';
            sub = this.alumni360Tab || 'overview';
        } else if (this.activeModal === 'lead' || this.activeModal === 'referral') {
            page = this.activeModal;
            sub = this.activeLeadTab || 'merge';
        } else if (this.activeModal === 'issues') {
            page = 'issues';
        }
        const onRecord = page !== 'list' && page !== 'map';
        return {
            page,
            alumni: onRecord ? (this.selectedAlumniId || '') : '',
            tab: this.activeTab || 'all',
            sub,
            chip: this.activeTab === 'issues' ? (this.activeIssueChip || 'all') : ''
        };
    }

    /**
     * Mirror the current screen into the address bar. replace:true keeps the
     * history usable — switching tabs shouldn't take three Backs to undo — and
     * the URL still survives a refresh, which is the point.
     */
    _syncUrl() {
        if (this._restoringFromUrl) return;
        const next = this._currentUrlState();
        const signature = this._urlSignature(next);
        if (signature === this._lastUrlSignature) return;

        // Moving between screens (list → 360, list → lead workspace, opening a
        // different record) PUSHES, so browser Back steps back through them —
        // Back from the 360 lands on the list it was opened from. Changing a
        // tab or chip within the same screen REPLACES, so Back isn't clogged
        // with every tab click on the way through.
        const prev = this._lastUrlState;
        const isScreenChange = !!prev && (prev.page !== next.page || prev.alumni !== next.alumni);
        this._lastUrlSignature = signature;
        this._lastUrlState = next;

        try {
            const params = new URLSearchParams(window.location.search);
            URL_KEYS.forEach((key) => {
                params.delete(key);
                params.delete('c__' + key);
                if (next[key]) params.set('c__' + key, next[key]);
            });
            const query = params.toString();
            const url = window.location.pathname + (query ? '?' + query : '') + window.location.hash;
            if (isScreenChange) {
                window.history.pushState(window.history.state, '', url);
            } else {
                window.history.replaceState(window.history.state, '', url);
            }
        } catch (e) {
            // A blocked History API only costs deep-linking, never the screen.
        }
    }

    // Browser Back/Forward moves between the entries pushed above; re-apply
    // whatever the address bar now says. Landing on a URL with none of our
    // params resets to the list, which is the right answer for stepping back
    // past the point where this screen was first opened.
    _handlePopState() {
        const incoming = this._readUrlState();
        const signature = this._urlSignature(incoming);
        if (signature === this._lastUrlSignature) return;
        this._lastUrlSignature = signature;
        this._lastUrlState = incoming;
        this._applyUrlState(incoming);
    }

    // The 360 reports its own tab clicks so ?sub= tracks them.
    handleAlumni360TabChange(e) {
        this.alumni360Tab = (e.detail && e.detail.tab) || 'overview';
        this._syncUrl();
    }

    /* ---- Derived list view-model ---- */
    get rows() {
        const raw = this.alumniList && this.alumniList.rows ? this.alumniList.rows : [];
        const tab = this.activeTab;
        const issuesTab = (tab === 'issues');
        const leadsTab = (tab === 'leads');
        const sel = new Set(this.selectedLeadIds || []);
        return raw.map(r => {
            const initials = this._initials(r.name);
            const emailMissing = r.emailWarning === 'missing' || !r.email;
            const pct = r.completenessPct == null ? 0 : r.completenessPct;
            let rowModalKind;
            if (issuesTab) {
                rowModalKind = 'issues';
            } else if (tab === 'leads') {
                rowModalKind = 'lead';
            } else if (tab === 'referrals') {
                rowModalKind = 'referral';
            } else {
                rowModalKind = 'alumni';
            }
            return {
                ...r,
                initials,
                emailDisplay: emailMissing ? 'email missing' : r.email,
                emailClass: emailMissing ? 'em warn' : 'em',
                hasLocation: !!r.location,
                hasCompany: !!r.company,
                masterPillClass: 'pill ' + this._statusPill(r.masterRecordStatus),
                portalPillClass: 'pill ' + this._portalPill(r.portalStatus),
                sourcePillClass: 'pill ' + this._sourcePill(r.source),
                sourceLabel: this._sourceLabel(r.source),
                matchPillClass: 'pill ' + this._matchPill(r.matchMerge),
                completenessStyle: 'width:' + pct + '%',
                completenessFillClass: 'f ' + this._completenessTier(pct),
                completenessLabel: pct + '%',
                lastUpdatedLabel: this._formatDate(r.lastUpdated),
                rowModalKind,
                selectable: leadsTab,
                selected: leadsTab && sel.has(r.alumniId)
            };
        });
    }

    get selectedLeadCount() { return (this.selectedLeadIds || []).length; }
    get hasSelectedLeads()  { return this.selectedLeadCount > 0; }
    get convertButtonLabel() {
        const n = this.selectedLeadCount;
        return n > 0 ? `Convert Selected (${n})` : 'Convert Selected';
    }
    get isConvertDisabled() { return !this.hasSelectedLeads || this.isConverting; }
    get allLeadsSelected() {
        const ids = (this.rows || []).map(r => r.alumniId);
        if (ids.length === 0) return false;
        const sel = new Set(this.selectedLeadIds || []);
        return ids.every(id => sel.has(id));
    }

    get timelineRows() {
        return (this.timelineRowsRaw || []).map((t, i) => ({
            key: 'tl-' + i + '-' + (t.occurredAt || ''),
            title: t.title,
            actor: t.actor || 'System',
            dateLabel: this._formatDate(t.occurredAt),
            nodeClass: 'ltl-ev ' + this._timelineTier(t.kind),
            body: t.body,
            hasBody: !!t.body
        }));
    }
    // Maps the server-side event kind to a coloured node tier.
    _timelineTier(kind) {
        if (kind === 'communication') return 'rose';
        if (kind === 'owner' || kind === 'match') return 'violet';
        if (kind === 'status') return 'brand';
        return 'plain';
    }
    get hasTimelineRows() { return this.timelineRows.length > 0; }

    get historyRows() {
        return (this.historyRowsRaw || []).map((h, i) => ({
            key: 'h-' + i + '-' + (h.occurredAt || ''),
            field: h.field,
            previousValue: h.previousValue || '—',
            newValue: h.newValue || '—',
            sourceTag: h.sourceTag || 'System',
            updatedBy: h.updatedBy || 'System',
            dateLabel: this._formatDate(h.occurredAt)
        }));
    }
    get hasHistoryRows() { return this.historyRows.length > 0; }

    get hasRows()      { return !this.alumniListLoading && this.rows.length > 0; }
    get isEmpty()      { return !this.alumniListLoading && this.rows.length === 0; }
    get isLoading()    { return this.alumniListLoading; }
    get activeTabCount(){ return this.alumniList ? this.alumniList.totalRecords : 0; }

    _tc(key, isActive) {
        if (isActive && this.alumniList) return this.activeTabCount;
        const v = this.tabCounts ? this.tabCounts[key] : null;
        return (v == null) ? '—' : v;
    }
    get countAll()          { return this._tc('all',          this.isAll); }
    get countRecent()       { return this._tc('recent',       this.isRecent); }
    get countRegistered()   { return this._tc('registered',   this.isRegistered); }
    get countUnregistered() { return this._tc('unregistered', this.isUnregistered); }
    get countOldPortal()    { return this._tc('oldPortal',    this.isOldPortal); }
    get countIssues()       { return this._tc('issues',       this.isIssues); }
    get countLeads()        { return this._tc('leads',        this.isLeads); }
    get countReferrals()    { return this._tc('referrals',    this.isReferrals); }

    get masterCountAll()          { return 'All Master Records · ' + this.activeTabCount; }
    get masterCountRecent()       { return 'Recently Joined · ' + this.activeTabCount; }
    get masterCountRegistered()   { return 'Registered Alumni · ' + this.activeTabCount; }
    get masterCountUnregistered() { return 'Un-registered Alumni · ' + this.activeTabCount; }
    get masterCountOldPortal()    { return 'Old Portal Records · ' + this.activeTabCount; }
    get masterCountIssues()       { return 'Data Issues · ' + this.activeTabCount; }
    get masterCountLeads()        { return 'Leads · ' + this.activeTabCount; }
    get masterCountReferrals()    { return 'Referrals · ' + this.activeTabCount; }

    get showingLabel() { return 'Showing ' + this.rows.length + ' records'; }

    /* ---- Pagination ---- */
    get totalPages() {
        const total = this.alumniList ? this.alumniList.totalRecords : 0;
        return Math.max(1, Math.ceil(total / PAGE_SIZE));
    }
    get pageRangeLabel() {
        if (!this.alumniList || this.alumniList.totalRecords === 0) return 'No records';
        const start = (this.currentPage - 1) * PAGE_SIZE + 1;
        const end = Math.min(this.currentPage * PAGE_SIZE, this.alumniList.totalRecords);
        return start + '–' + end + ' of ' + this.alumniList.totalRecords;
    }
    get pageNumberLabel() { return 'Page ' + this.currentPage + ' of ' + this.totalPages; }
    get isFirstPage() { return this.currentPage <= 1; }
    get isLastPage()  { return this.currentPage >= this.totalPages; }
    get showPagination() { return this.alumniList && this.alumniList.totalRecords > PAGE_SIZE; }

    /* ---- Detail view-model ---- */
    get detail() { return this.alumniDetail || {}; }
    get detailLoading() { return this.alumniDetailLoading && !this.alumniDetail; }

    get detailName()       { return this.detail.name || this.personName; }
    get detailProgram()    { return this.detail.program || ''; }
    get detailBatch()      { return this.detail.batch || ''; }
    get detailLocation()   { return this.detail.location || ''; }
    get detailEmail()      { return this.detail.email || ''; }
    get detailPhone()      { return this.detail.phone || ''; }
    get detailLinkedin()   { return this.detail.linkedinUrl || ''; }
    get detailCompany()    { return this.detail.company || ''; }
    get detailRole()       { return this.detail.role || ''; }
    get detailIndustry()   { return this.detail.industry || ''; }
    get detailRegNumber()  { return this.detail.registrationNumber || ''; }
    get detailSource()     { return this.detail.source || ''; }
    get detailEngagement() { return this.detail.engagementScore || ''; }
    get detailLastLogin()  { return this.detail.lastLogin ? this._formatDate(this.detail.lastLogin) : '—'; }
    get detailRegistrationDate() { return this.detail.registrationDate ? this._formatDate(this.detail.registrationDate) : '—'; }
    get detailCompleteness() { return (this.detail.completenessPct != null ? this.detail.completenessPct : 0) + '%'; }
    get detailSub() {
        const parts = [];
        if (this.detail.program) parts.push(this.detail.program);
        if (this.detail.batch)   parts.push("'" + this.detail.batch);
        const top = parts.join(' ');
        const loc = this.detail.location || '';
        return [top, loc].filter(x => x).join(' · ');
    }

    get showVerifiedChip()   { return this.detail.approvalStatus === 'Approved'; }
    get showRegisteredChip() { return this.detail.hasLoggedInOnce === true; }
    get showCompleteChip()   { return (this.detail.completenessPct || 0) >= 80; }

    get detailInterests()    { return this.detail.interests || []; }
    get hasDetailInterests() { return this.detailInterests.length > 0; }
    get engagementScoreLabel() { return this.detail.engagementScore || 'Low'; }

    get emailVisibilityLabel() { return this.detail.hideEmail ? 'Hidden' : 'Visible'; }
    get phoneVisibilityLabel() { return this.detail.hidePhone ? 'Hidden' : 'Visible'; }
    get emailVisibilityPillClass() { return this.detail.hideEmail ? 'pill neutral' : 'pill success'; }
    get phoneVisibilityPillClass() { return this.detail.hidePhone ? 'pill neutral' : 'pill success'; }

    /* ---- Merge view-model ---- */
    get mergeRows() {
        return (this.mergeCandidates || []).map(c => ({
            ...c,
            matchLabel: c.matchPercent == null ? '' : c.matchPercent + '% match',
            detail: 'Batch \'' + (c.batch || '—') + ' · ' + (c.registrationNumber || '—') + ' · ' + (c.source || '—')
                + ' · ID ' + c.alumniId
                + (c.matchedOn ? ' · Matched by ' + c.matchedOn : ''),
            selected: this.selectedCandidateIds.includes(c.alumniId)
        }));
    }
    get hasMergeRows() { return !this.mergeCandidatesLoading && this.mergeRows.length > 0; }
    get isMergeEmpty() { return !this.mergeCandidatesLoading && this.mergeRows.length === 0; }
    get isMergeLoading() { return this.mergeCandidatesLoading; }
    get hasSelectedCandidates() { return this.selectedCandidateIds.length > 0; }
    get isCompareDisabled() { return !this.hasSelectedCandidates; }
    // The lead/referral unmerged modal is normally narrow (720px) — widen it
    // only while the N-way compare is showing, since its column count grows
    // with however many candidates are checked.
    get unmergedModalClass() {
        return this.mergeMultiReviewActive ? 'modal modal-wide' : 'modal modal-narrow';
    }

    /* ---- Lead / Referral workspace (Phase 1 shell) ---- */
    // The workspace is always the wide shell so the split rail + canvas (and the
    // N-way compare) have room; only the legacy new-role card stays narrow.
    get leadModalClass() {
        return this.isNewRoleLead ? 'modal modal-narrow' : 'modal modal-wide lead-modal';
    }

    get isLeadTabMerge()    { return this.activeLeadTab === 'merge'; }
    get isLeadTabActivity() { return this.activeLeadTab === 'activity'; }
    get isLeadTabHistory()  { return this.activeLeadTab === 'history'; }
    ltClass(id) { return 't' + (this.activeLeadTab === id ? ' active' : ''); }
    get ltMerge()    { return this.ltClass('merge'); }
    get ltActivity() { return this.ltClass('activity'); }
    get ltHistory()  { return this.ltClass('history'); }
    get timelineCount() { return this.timelineRows.length; }

    // Rail view-model — reuses the shared detail getters (getAlumniDetail),
    // falling back to the row-captured values while the detail wire loads.
    get railName()    { return this.detailName || this.personName; }
    get railInitials(){ return this.personInitials || this._initials(this.railName); }
    get railSubLine() {
        const parts = [];
        if (this.detailProgram) parts.push(this.detailProgram);
        if (this.detailBatch)   parts.push("'" + this.detailBatch);
        const top = parts.join(' ');
        return [top, this.detailLocation].filter(x => x).join(' · ');
    }
    get railEmail()   { return this.detailEmail; }
    get railPhone()   { return this.detailPhone; }
    get railLinkedin(){ return this.detailLinkedin; }
    get railStatusLabel() { return this.detail.approvalStatus || 'Unregistered'; }
    get railCreated() { return this.detailRegistrationDate; }
    // Lead-form captured fields (from getAlumniDetail → leadDetailOf).
    get railInstitute()        { return this.detail.institute || '—'; }
    get railProgram()          { return this.detail.program || '—'; }
    get railYearOfEnrollment() { return this.detail.yearOfEnrollment || '—'; }

    handleLeadTab(e) {
        const lt = e.currentTarget.dataset.lt || 'merge';
        this.activeLeadTab = lt;
        // The Change Owner tab needs its picker populated on first open.
        if (lt === 'owner' && (!this.ownerOptions || this.ownerOptions.length === 0)) {
            this.selectedNewOwnerId = '';
            this.ownerReason = '';
            this.ownerSearchTerm = '';
            this._loadOwners('');
        }
        this._syncUrl();
    }
    handleShowMergeTab() {
        this.activeLeadTab = 'merge';
        this._syncUrl();
    }

    /* ---- Communication (logs a Task/Activity) ---- */
    get isLeadTabComm()  { return this.activeLeadTab === 'comm'; }
    get isLeadTabOwner() { return this.activeLeadTab === 'owner'; }
    get ltComm() { return this.ltClass('comm'); }
    get ltOwner() { return this.ltClass('owner'); }
    get commCount() { return this.commLogRows.length; }

    _chanClass(id) { return 'comm-channel' + (this.commChannel === id ? ' on' : ''); }
    get chanEmail() { return this._chanClass('email'); }
    get chanSms()   { return this._chanClass('sms'); }
    get chanCall()  { return this._chanClass('call'); }
    get chanNote()  { return this._chanClass('note'); }

    get commSubjectLabel() { return this.commChannel === 'email' ? 'Subject' : 'Summary'; }
    get commBodyLabel() {
        if (this.commChannel === 'call') return 'Call notes';
        if (this.commChannel === 'note') return 'Note';
        return 'Message';
    }
    get commChannelLabel() {
        const m = { email: 'email', sms: 'SMS', call: 'call', note: 'note' };
        return m[this.commChannel] || 'note';
    }
    get commLogButtonLabel() { return 'Log ' + this.commChannelLabel; }
    get isCommDisabled() { return !this.commBody || !this.commBody.trim() || this.isLoggingComm; }

    get commLogRows() {
        return (this.commLogRaw || []).map((c, i) => ({
            key: 'cm-' + i + '-' + (c.occurredAt || ''),
            channel: c.channel,
            title: c.title || c.channel,
            body: c.body,
            hasBody: !!c.body,
            status: c.status,
            actor: c.actor || 'System',
            dateLabel: this._formatDate(c.occurredAt),
            iconClass: 'ci ' + this._commIcon(c.channel)
        }));
    }
    get hasCommLog() { return this.commLogRows.length > 0; }
    _commIcon(channel) {
        const c = (channel || '').toLowerCase();
        if (c === 'email') return 'mail';
        if (c === 'sms')  return 'sms';
        if (c === 'call') return 'call';
        return 'note';
    }

    handleOpenComm() { this.activeLeadTab = 'comm'; }
    handleCommChannel(e) { this.commChannel = e.currentTarget.dataset.ch || 'email'; }
    handleCommSubjectInput(e) { this.commSubject = e.target.value; }
    handleCommBodyInput(e) { this.commBody = e.target.value; }
    handleLogComm() {
        if (this.isCommDisabled || !this.selectedAlumniId) return;
        this.isLoggingComm = true;
        logCommunication({
            alumniId: this.selectedAlumniId,
            channel: this.commChannel,
            subject: this.commSubject,
            body: this.commBody,
            outcome: ''
        })
            .then((res) => {
                this.isLoggingComm = false;
                if (res && res.success) {
                    this.commSubject = '';
                    this.commBody = '';
                    this.showConvertSuccess(res.message || 'Logged to activity.');
                    if (this._wiredCommLogResult)  refreshApex(this._wiredCommLogResult);
                    if (this._wiredTimelineResult) refreshApex(this._wiredTimelineResult);
                } else if (res) {
                    this.showConvertSuccess(res.message || 'Could not log.', 'error');
                }
            })
            .catch((err) => {
                this.isLoggingComm = false;
                this.showConvertSuccess((err && err.body && err.body.message) || 'Could not log.', 'error');
            });
    }

    /* ---- Owner & change ---- */
    get ownerName()     { return this.detail.ownerName || 'Unassigned'; }
    get ownerTypeLabel(){ return this.detail.ownerType || ''; }
    get ownerInitials() { return this.detail.ownerInitials || '—'; }
    get ownerIsQueue()  { return this.detail.ownerType === 'Queue'; }
    get isReassignDisabled() { return !this.selectedNewOwnerId || this.isReassigning; }
    get ownerOptionRows() {
        return (this.ownerOptions || []).map((o) => ({
            ...o,
            itemClass: 'owner-opt' + (o.id === this.selectedNewOwnerId ? ' on' : ''),
            showCheck: o.id === this.selectedNewOwnerId,
            avatarClass: 'avatar-circle' + (o.ownerType === 'Queue' ? ' owner-queue' : '')
        }));
    }
    get hasOwnerOptions() { return this.ownerOptions.length > 0; }

    handleOpenOwner() {
        this.activeLeadTab = 'owner';
        this.selectedNewOwnerId = '';
        this.ownerReason = '';
        this.ownerSearchTerm = '';
        this._loadOwners('');
    }
    // The input is bound to ownerSearchTerm, so the tracked value must be
    // updated synchronously on every keystroke. Assigning it only inside the
    // debounce (or not at all) lets any re-render triggered by the in-flight
    // Apex call push the stale value back into the DOM and eat the characters
    // the user just typed.
    handleOwnerSearch(e) {
        const value = e.target.value || '';
        this.ownerSearchTerm = value;
        if (this._ownerSearchDebounce) clearTimeout(this._ownerSearchDebounce);
        this._ownerSearchDebounce = setTimeout(() => this._loadOwners(value), 300);
    }
    handleSelectNewOwner(e) {
        this.selectedNewOwnerId = e.currentTarget.dataset.id || '';
    }
    handleOwnerReasonInput(e) { this.ownerReason = e.target.value; }
    // Overlapping searches resolve in whatever order the server answers, so a
    // slow response for an earlier term would otherwise replace the results for
    // the term the user actually finished typing. Only the newest request wins.
    _loadOwners(term) {
        const seq = ++this._ownerSearchSeq;
        this.ownerOptionsLoading = true;
        getAssignableOwners({ searchTerm: term })
            .then((data) => {
                if (seq !== this._ownerSearchSeq) return;
                this.ownerOptions = data || [];
                this.ownerOptionsLoading = false;
            })
            .catch(() => {
                if (seq !== this._ownerSearchSeq) return;
                this.ownerOptions = [];
                this.ownerOptionsLoading = false;
            });
    }
    handleReassign() {
        if (this.isReassignDisabled || !this.selectedAlumniId) return;
        this.isReassigning = true;
        changeLeadOwner({
            alumniId: this.selectedAlumniId,
            newOwnerId: this.selectedNewOwnerId,
            reason: this.ownerReason
        })
            .then((res) => {
                this.isReassigning = false;
                if (res && res.success) {
                    this.selectedNewOwnerId = '';
                    this.ownerReason = '';
                    this.showConvertSuccess(res.message || 'Owner changed.');
                    if (this._wiredDetailResult)   refreshApex(this._wiredDetailResult);
                    if (this._wiredTimelineResult) refreshApex(this._wiredTimelineResult);
                    if (this._wiredListResult)     refreshApex(this._wiredListResult);
                    this.activeLeadTab = 'activity';
                } else if (res) {
                    this.showConvertSuccess(res.message || 'Could not change owner.', 'error');
                }
            })
            .catch((err) => {
                this.isReassigning = false;
                this.showConvertSuccess((err && err.body && err.body.message) || 'Could not change owner.', 'error');
            });
    }

    // Verify a single lead from the workspace — reuses the existing convertLeads
    // Apex (same path the multi-select "Convert Selected" button uses).
    handleVerifyLead() {
        if (!this.selectedAlumniId || this.isConverting) return;
        this.isConverting = true;
        convertLeads({ alumniIds: [this.selectedAlumniId] })
            .then((res) => {
                const converted = (res && typeof res.converted === 'number') ? res.converted : 1;
                this.isConverting = false;
                this.showConvertSuccess(
                    converted === 1 ? '1 lead marked as Verified.' : `${converted} leads marked as Verified.`
                );
                if (this._wiredListResult)   refreshApex(this._wiredListResult);
                if (this._wiredCountsResult) refreshApex(this._wiredCountsResult);
                this.handleClose();
            })
            .catch(() => { this.isConverting = false; });
    }
    // The eyebrow/name/source + Captured Fields block is only useful before
    // comparing — once the N-way table is open it's redundant (the lead's own
    // data already shows as the "New Lead" column) and just eats space that
    // could go to the comparison itself.
    get showCapturedHeader() {
        return !this.mergeMultiReviewActive;
    }
    get compareButtonLabel() {
        return this.selectedCandidateIds.length > 1
            ? 'Compare ' + this.selectedCandidateIds.length + ' selected'
            : 'Compare';
    }
    get isAllCandidatesSelected() {
        return this.mergeRows.length > 0 && this.selectedCandidateIds.length === this.mergeRows.length;
    }

    handleToggleCandidate(e) {
        const id = e.currentTarget.dataset.id;
        if (e.target.checked) {
            if (!this.selectedCandidateIds.includes(id)) this.selectedCandidateIds = [...this.selectedCandidateIds, id];
        } else {
            this.selectedCandidateIds = this.selectedCandidateIds.filter((x) => x !== id);
        }
    }
    handleToggleSelectAllCandidates(e) {
        this.selectedCandidateIds = e.target.checked ? this.mergeRows.map((r) => r.alumniId) : [];
    }

    /* ---- Computed flags for tab visibility ---- */
    get isAll()          { return this.activeTab === 'all'; }
    get isRecent()       { return this.activeTab === 'recent'; }
    get isRegistered()   { return this.activeTab === 'registered'; }
    get isUnregistered() { return this.activeTab === 'unregistered'; }
    get isOldPortal()    { return this.activeTab === 'oldportal'; }
    get isIssues()       { return this.activeTab === 'issues'; }
    get isLeads()        { return this.activeTab === 'leads'; }
    get isReferrals()    { return this.activeTab === 'referrals'; }

    // Status filter is redundant on tabs that already hard-filter by registration status.
    get showStatusFilter() {
        return this.activeTab !== 'registered' && this.activeTab !== 'unregistered';
    }
    // Source filter is redundant on tabs that already hard-filter by source funnel.
    get showSourceFilter() {
        return this.activeTab !== 'oldportal' && this.activeTab !== 'referrals' && this.activeTab !== 'leads';
    }

    get cAll()          { return this.tabClass('all'); }
    get cRecent()       { return this.tabClass('recent'); }
    get cRegistered()   { return this.tabClass('registered'); }
    get cUnregistered() { return this.tabClass('unregistered'); }
    get cOldPortal()    { return this.tabClass('oldportal'); }
    get cIssues()       { return this.tabClass('issues'); }
    get cLeads()        { return this.tabClass('leads'); }
    get cReferrals()    { return this.tabClass('referrals'); }
    tabClass(id) { return 'alumni-tab' + (this.activeTab === id ? ' active' : ''); }

    get showAlumniModal()   { return this.activeModal === 'alumni'; }
    get showLeadModal()     { return this.activeModal === 'lead'; }
    get showReferralModal() { return this.activeModal === 'referral'; }
    get showIssuesModal()   { return this.activeModal === 'issues'; }
    // Leads and Referrals share ONE workspace — both surface a Lead Id, so the
    // same rail/tabs/merge flow serves both; only the eyebrow label differs.
    get showWorkspaceModal() { return this.activeModal === 'lead' || this.activeModal === 'referral'; }
    get recordKindLabel()    { return this.activeModal === 'referral' ? 'Referral' : 'Lead'; }
    get overlayClass()      { return 'modal-overlay' + (this.activeModal ? ' show' : ''); }

    get issue()              { return this.contactIssue || {}; }
    get issueEmailMissing()  { return this.issue.emailMissing === true; }
    get issueEmailBounced()  { return this.issue.emailBounced === true; }
    get issuePhoneMissing()  { return this.issue.phoneMissing === true; }
    get issueEmailFootnote() {
        if (this.issue.bounceNote) return this.issue.bounceNote;
        return 'Updating will clear the bounce flag and re-queue for next campaign.';
    }
    get issueDetailSub() {
        const parts = [];
        if (this.issue.program) parts.push(this.issue.program);
        if (this.issue.batch)   parts.push("'" + this.issue.batch);
        if (this.issue.registrationNumber) parts.push(this.issue.registrationNumber);
        const top = parts.join(' ');
        const loc = this.issue.location || '';
        return [top, loc].filter(x => x).join(' · ');
    }
    get issuesRemainingLabel() {
        const n = this.issue.issuesRemaining == null ? 0 : this.issue.issuesRemaining;
        return n + (n === 1 ? ' issue remaining' : ' of issues remaining');
    }

    get isOverview()   { return this.activeInnerTab === 'overview'; }
    get isEducation()  { return this.activeInnerTab === 'education'; }
    get isContact()    { return this.activeInnerTab === 'contact'; }
    get isCareer()     { return this.activeInnerTab === 'career'; }
    get isPortal()     { return this.activeInnerTab === 'portal'; }
    get isEngagement() { return this.activeInnerTab === 'engagement'; }
    get isRequests()   { return this.activeInnerTab === 'requests'; }
    get isHistory()    { return this.activeInnerTab === 'history'; }
    get isActivity()   { return this.activeInnerTab === 'activity'; }

    get mtOverview()   { return this.mtClass('overview'); }
    get mtEducation()  { return this.mtClass('education'); }
    get mtContact()    { return this.mtClass('contact'); }
    get mtCareer()     { return this.mtClass('career'); }
    get mtPortal()     { return this.mtClass('portal'); }
    get mtEngagement() { return this.mtClass('engagement'); }
    get mtRequests()   { return this.mtClass('requests'); }
    get mtHistory()    { return this.mtClass('history'); }
    get mtActivity()   { return this.mtClass('activity'); }
    mtClass(id) { return 'mt' + (this.activeInnerTab === id ? ' active' : ''); }

    get chAll()    { return this.chipClass('all'); }
    get chMail()   { return this.chipClass('mail'); }
    get chPhone()  { return this.chipClass('phone'); }
    get chInvMail(){ return this.chipClass('invmail'); }
    get chBounce() { return this.chipClass('bounce'); }
    get chInvPhone(){ return this.chipClass('invphone'); }
    chipClass(id) { return 'issue-chip' + (this.activeIssueChip === id ? ' active' : ''); }

    _icc(key) {
        const v = this.issueChipCounts ? this.issueChipCounts[key] : null;
        return (v == null) ? '—' : v;
    }
    get countChipAll()      { return this._icc('all'); }
    get countChipMail()     { return this._icc('missingEmail'); }
    get countChipPhone()    { return this._icc('missingPhone'); }
    get countChipInvMail()  { return this._icc('invalidEmail'); }
    get countChipBounce()   { return this._icc('bouncedEmail'); }
    get countChipInvPhone() { return this._icc('invalidPhone'); }

    /* ---- Handlers ---- */
    handleTab(e) {
        this.activeTab = e.currentTarget.dataset.tab;
        this.currentPage = 1;
        this.selectedLeadIds = [];
        // Drop any Portal Status selection when moving to a tab that hides the
        // dropdown, so a hidden filter can't silently constrain the new results.
        if (!this.showPortalDropdown && this.activePortalStatus) {
            this.activePortalStatus = '';
        }
        this._syncUrl();
    }

    handleLeadCheckboxClick(e) {
        e.stopPropagation();
    }
    handleLeadSelect(e) {
        e.stopPropagation();
        const id = e.target.dataset.id;
        if (!id) return;
        const set = new Set(this.selectedLeadIds || []);
        if (e.target.checked) set.add(id); else set.delete(id);
        this.selectedLeadIds = Array.from(set);
    }
    handleSelectAllLeads(e) {
        e.stopPropagation();
        const ids = (this.rows || []).map(r => r.alumniId);
        this.selectedLeadIds = e.target.checked ? ids : [];
    }
    handleConvertSelected() {
        if (!this.hasSelectedLeads || this.isConverting) return;
        const count = this.selectedLeadIds.length;
        this.isConverting = true;
        convertLeads({ alumniIds: this.selectedLeadIds })
            .then((res) => {
                const converted = (res && typeof res.converted === 'number') ? res.converted : count;
                this.selectedLeadIds = [];
                this.isConverting = false;
                this.showConvertSuccess(
                    converted === 1
                        ? '1 lead marked as Verified.'
                        : `${converted} leads marked as Verified.`
                );
                if (this._wiredListResult)   refreshApex(this._wiredListResult);
                if (this._wiredCountsResult) refreshApex(this._wiredCountsResult);
            })
            .catch(() => {
                this.isConverting = false;
            });
    }

    handleRejectLead() {
        if (!this.selectedAlumniId || this.isRejecting) return;
        this.isRejecting = true;
        rejectLead({ leadId: this.selectedAlumniId })
            .then((res) => {
                this.isRejecting = false;
                const msg = res && res.message ? res.message : '';
                if (res && res.success) {
                    this.showConvertSuccess(msg || 'Lead rejected as not an alumnus.');
                    if (this._wiredListResult)   refreshApex(this._wiredListResult);
                    if (this._wiredCountsResult) refreshApex(this._wiredCountsResult);
                    this.handleClose();
                } else if (msg) {
                    this.showConvertSuccess(msg, 'error');
                }
            })
            .catch(() => {
                this.isRejecting = false;
            });
    }

    handleViewExistingProfile() {
        if (!this.capturedExistingAccountId) return;
        this.selectedAlumniId = this.capturedExistingAccountId;
        this.activeModal = null;
        this.activeInnerTab = 'overview';
        this.alumni360Tab = 'overview';
        this.showAlumni360 = true;
        this._syncUrl();
    }

    handleApproveRole() {
        if (!this.selectedAlumniId || this.isConverting) return;
        this.isConverting = true;
        convertLeads({ alumniIds: [this.selectedAlumniId] })
            .then(() => {
                this.isConverting = false;
                this.showConvertSuccess('New role approved — verified and added to the alumnus.');
                if (this._wiredListResult)   refreshApex(this._wiredListResult);
                if (this._wiredCountsResult) refreshApex(this._wiredCountsResult);
                this.handleClose();
            })
            .catch(() => { this.isConverting = false; });
    }

    // Single shared entry point for the candidate list's one "Compare" button.
    // One candidate checked reuses the existing, tested review-and-merge flow.
    // Two or more open a read-only side-by-side view instead — there's no
    // commit action for reconciling multiple existing masters yet.
    handleCompareSelected() {
        const ids = [...this.selectedCandidateIds];
        if (!ids.length || !this.selectedAlumniId) return;
        if (ids.length === 1) {
            this._openSingleReview(ids[0]);
        } else {
            this._openMultiReview(ids);
        }
    }

    // "Compare" (single candidate) opens the review screen so the admin can see
    // (and, per field, override) what the master record will look like
    // post-merge before anything is written — nothing is saved until
    // handleConfirmMerge fires.
    _openSingleReview(masterRoleId) {
        if (this.mergeReviewLoading) return;
        const candidate = (this.mergeCandidates || []).find((c) => c.alumniId === masterRoleId);
        this._mergeReviewMasterRoleId = masterRoleId;
        this.mergeReviewMasterName = candidate ? candidate.name : '';
        this.mergeReviewLoading = true;
        this.mergeReviewActive = true;
        getMergeFieldComparison({ leadId: this.selectedAlumniId, masterRoleId })
            .then((rows) => {
                this.mergeReviewRows = (rows || []).map((r) => this._toReviewRow(r));
                this.mergeReviewLoading = false;
            })
            .catch(() => {
                this.mergeReviewLoading = false;
                this.mergeReviewRows = [];
            });
    }

    // "Compare" (2+ candidates) — side by side against the incoming lead, per
    // field. Which candidate actually gets written to is chosen afterward via
    // the "Merge into" picker (handleMultiTargetChange); the ones not picked
    // are left untouched.
    _openMultiReview(masterRoleIds) {
        if (this.mergeMultiReviewLoading) return;
        this._mergeMultiReviewMasterRoleIds = masterRoleIds;
        // label carries the record Id alongside the name — several candidates
        // routinely share the exact name (that's how they surfaced), so the
        // name alone can't identify which record is being picked.
        this.mergeMultiReviewMasterNames = masterRoleIds.map((id) => {
            const c = (this.mergeCandidates || []).find((cand) => cand.alumniId === id);
            const nm = c ? c.name : id;
            return { key: id, name: nm, label: nm + ' (' + id + ')' };
        });
        this.mergeMultiReviewLoading = true;
        this.mergeMultiReviewActive = true;
        getMergeFieldComparisonMulti({ leadId: this.selectedAlumniId, masterRoleIds })
            .then((rows) => {
                // Referred By is left out of this view specifically — with several
                // candidates in play at once it's rarely meaningful to reconcile
                // and mostly just adds noise.
                this.mergeMultiReviewRows = (rows || [])
                    .filter((r) => r.fieldKey !== 'Referred_By__c')
                    .map((r) => this._toMultiReviewRow(r));
                this.mergeMultiReviewLoading = false;
            })
            .catch(() => {
                this.mergeMultiReviewLoading = false;
                this.mergeMultiReviewRows = [];
            });
    }

    // Every column (incoming + one per selected candidate) is a selectable pill,
    // same mechanic as the single-candidate review's existing/incoming pills —
    // exactly one selected per row, always clickable even when blank, since
    // explicitly picking a blank value to clear a field is a valid choice.
    // raw (alongside the display value) is what actually gets sent to
    // mergeCandidatesIntoOne — the Id for lookup fields, plain text otherwise.
    _toMultiReviewRow(r) {
        const incomingValue = r.incomingValue || '—';
        const existingValues = (r.existingValues || []).map((v) => v || '—');
        const existingRaws = r.existingRaws || [];
        const sources = [
            { key: 'incoming', value: incomingValue, raw: r.incomingRaw },
            ...existingValues.map((value, idx) => ({ key: 'existing-' + idx, value, raw: existingRaws[idx] }))
        ];
        // Default mirrors the single-candidate rule's spirit: the first existing
        // column with a real value wins; only fall back to incoming if every
        // existing column is blank.
        const firstNonBlankExisting = sources.slice(1).find((s) => s.value !== '—');
        const selectedKey = firstNonBlankExisting ? firstNonBlankExisting.key : 'incoming';
        return {
            fieldKey: r.fieldKey,
            label: r.label,
            selectedKey,
            sources: sources.map((s) => this._multiSource(s.key, s.value, s.raw, s.key === selectedKey)),
            mergedValue: sources.find((s) => s.key === selectedKey).value
        };
    }
    _multiSource(key, value, raw, isSelected) {
        return { key, value, raw, pillClass: 'multi-compare-col side-pill' + (isSelected ? ' selected' : '') };
    }

    handlePickMultiSide(e) {
        const fieldKey = e.currentTarget.dataset.field;
        const sourceKey = e.currentTarget.dataset.source;
        this.mergeMultiReviewRows = this.mergeMultiReviewRows.map((row) => {
            if (row.fieldKey !== fieldKey) return row;
            const picked = row.sources.find((s) => s.key === sourceKey);
            return {
                ...row,
                selectedKey: sourceKey,
                mergedValue: picked ? picked.value : row.mergedValue,
                sources: row.sources.map((s) => this._multiSource(s.key, s.value, s.raw, s.key === sourceKey))
            };
        });
    }

    handleBackFromMultiReview() {
        this.mergeMultiReviewActive = false;
        this.mergeMultiReviewRows = [];
        this.mergeMultiReviewMasterNames = [];
        this._mergeMultiReviewMasterRoleIds = [];
        this.mergeMultiTargetId = '';
    }

    // "Merge into" starts empty on purpose — the compare screen exists
    // precisely because it isn't obvious yet which of the N candidates should
    // survive, so nothing is pre-picked for the admin.
    handleMultiTargetChange(e) {
        this.mergeMultiTargetId = e.target.value;
    }
    get multiTargetOptions() {
        // <select> in LWC markup can't bind `value` directly — each <option>
        // has to be told whether it's selected instead.
        return this.mergeMultiReviewMasterNames.map((m) => ({ ...m, isSelected: m.key === this.mergeMultiTargetId }));
    }
    get isNoMultiTargetSelected() {
        return !this.mergeMultiTargetId;
    }
    get isMultiMergeDisabled() {
        return !this.mergeMultiTargetId || this.isMergingMulti;
    }
    get multiMergeButtonTitle() {
        return this.mergeMultiTargetId ? '' : 'Please choose a candidate to merge into';
    }

    handleConfirmMultiMerge() {
        if (!this.mergeMultiTargetId || !this.selectedAlumniId || this.isMergingMulti) return;
        const fieldChoices = {};
        this.mergeMultiReviewRows.forEach((row) => {
            const picked = row.sources.find((s) => s.key === row.selectedKey);
            fieldChoices[row.fieldKey] = picked ? picked.raw : '';
        });
        const otherCandidateIds = this._mergeMultiReviewMasterRoleIds.filter((id) => id !== this.mergeMultiTargetId);
        this.isMergingMulti = true;
        mergeCandidatesIntoOne({
            leadId: this.selectedAlumniId,
            targetMasterRoleId: this.mergeMultiTargetId,
            fieldChoicesJson: JSON.stringify(fieldChoices),
            otherCandidateIds
        })
            .then((res) => {
                this.isMergingMulti = false;
                const msg = res && res.message ? res.message : '';
                if (res && res.success) {
                    this.showConvertSuccess(msg || 'Lead merged into the selected candidate.');
                    if (this._wiredListResult)   refreshApex(this._wiredListResult);
                    if (this._wiredCountsResult) refreshApex(this._wiredCountsResult);
                    this.handleClose();
                } else if (msg) {
                    this.showConvertSuccess(msg, 'error');
                }
            })
            .catch((err) => {
                this.isMergingMulti = false;
                this.showConvertSuccess((err && err.body && err.body.message) || 'Merge failed.', 'error');
            });
    }

    // Builds the display view-model for one comparison row: which side is
    // selected (defaults to the same side the backend's gap-fill rule would
    // pick), and whether that selection differs from the default — that's the
    // "this was changed" highlight in the UI.
    _toReviewRow(r) {
        // When neither side has a value, leave selectedSide as 'none' too — forcing
        // it to 'existing' made an empty field look "selected" (blue pill) while
        // simultaneously tripping the changed-row highlight (selected != default).
        // Pills stay clickable even when a side is blank — explicitly picking a
        // blank value (to clear a field on merge) is a valid, deliberate choice.
        const selectedSide = r.defaultSide;
        const existingValue = r.existingValue || '—';
        const incomingValue = r.incomingValue || '—';
        return {
            fieldKey: r.fieldKey,
            label: r.label,
            existingValue,
            incomingValue,
            existingRaw: r.existingRaw,
            incomingRaw: r.incomingRaw,
            defaultSide: r.defaultSide,
            selectedSide,
            mergedValue: this._mergedValueFor(existingValue, incomingValue, selectedSide),
            rowClass: this._reviewRowClass(selectedSide, r.defaultSide),
            existingPillClass: this._reviewPillClass(selectedSide === 'existing'),
            incomingPillClass: this._reviewPillClass(selectedSide === 'incoming')
        };
    }
    _mergedValueFor(existingValue, incomingValue, side) {
        return side === 'incoming' ? incomingValue : existingValue;
    }
    _reviewRowClass(selectedSide, defaultSide) {
        return 'compare-row' + (selectedSide !== defaultSide ? ' changed' : '');
    }
    _reviewPillClass(isSelected) {
        return 'side-pill' + (isSelected ? ' selected' : '');
    }
    _rowWithSide(row, side) {
        return {
            ...row,
            selectedSide: side,
            mergedValue: this._mergedValueFor(row.existingValue, row.incomingValue, side),
            rowClass: this._reviewRowClass(side, row.defaultSide),
            existingPillClass: this._reviewPillClass(side === 'existing'),
            incomingPillClass: this._reviewPillClass(side === 'incoming')
        };
    }

    handlePickSide(e) {
        const fieldKey = e.currentTarget.dataset.field;
        const side = e.currentTarget.dataset.side;
        this.mergeReviewRows = this.mergeReviewRows.map((row) =>
            row.fieldKey === fieldKey ? this._rowWithSide(row, side) : row
        );
    }

    // Bulk actions — flip every field to one side at once instead of clicking
    // each pill individually.
    handleUseAllExisting() {
        this.mergeReviewRows = this.mergeReviewRows.map((row) =>
            this._rowWithSide(row, 'existing')
        );
    }
    handleUseAllIncoming() {
        this.mergeReviewRows = this.mergeReviewRows.map((row) =>
            this._rowWithSide(row, 'incoming')
        );
    }

    handleBackToMergeCandidates() {
        this.mergeReviewActive = false;
        this.mergeReviewRows = [];
        this._mergeReviewMasterRoleId = null;
    }

    handleConfirmMerge() {
        if (!this._mergeReviewMasterRoleId || !this.selectedAlumniId || this.isMerging) return;
        const fieldChoices = {};
        this.mergeReviewRows.forEach((row) => { fieldChoices[row.fieldKey] = row.selectedSide; });
        this.isMerging = true;
        mergeLeadIntoMaster({
            leadId: this.selectedAlumniId,
            masterRoleId: this._mergeReviewMasterRoleId,
            fieldChoicesJson: JSON.stringify(fieldChoices)
        })
            .then((res) => {
                this.isMerging = false;
                const msg = res && res.message ? res.message : '';
                if (res && res.success) {
                    this.showConvertSuccess(msg || 'Lead merged with the master record.');
                    if (this._wiredListResult)   refreshApex(this._wiredListResult);
                    if (this._wiredCountsResult) refreshApex(this._wiredCountsResult);
                    this.handleClose();
                } else if (msg) {
                    this.showConvertSuccess(msg, 'error');
                }
            })
            .catch((err) => {
                this.isMerging = false;
                this.showConvertSuccess((err && err.body && err.body.message) || 'Merge failed.', 'error');
            });
    }

    // All merge/convert/owner-change outcomes surface as platform toasts —
    // the modal usually closes right after, so an inline message would vanish
    // with it.
    showConvertSuccess(message, variant = 'success') {
        this.dispatchEvent(new ShowToastEvent({
            title: variant === 'error' ? 'Error' : 'Success',
            message,
            variant
        }));
    }
    handleChip(e) {
        this.activeIssueChip = e.currentTarget.dataset.chip;
        this.currentPage = 1;
        this._syncUrl();
    }
    handleInnerTab(e) {
        this.activeInnerTab = e.currentTarget.dataset.mt;
    }
    handleSearch(e) {
        const value = e.target.value || '';
        if (this._searchDebounce) clearTimeout(this._searchDebounce);
        this._searchDebounce = setTimeout(() => {
            this.searchTerm = value;
            this.currentPage = 1;
        }, 300);
    }
    handlePortalStatusChange(e) {
        this.activePortalStatus = e.target.value || '';
        this.currentPage = 1;
    }
    handlePortalStatusToggle() {
        this.portalStatusOpen = !this.portalStatusOpen;
    }
    handlePortalStatusSelect(e) {
        this.activePortalStatus = e.currentTarget.dataset.value || '';
        this.portalStatusOpen = false;
        this.currentPage = 1;
    }
    /**
     * When a dashboard tile filter is active, hide the portal-status dropdown so
     * only ONE filter indicator is on screen (the dashboard-filter banner above).
     */
    get showPortalDropdown() {
        // Only the cross-status tabs (All master records / Recently joined) expose
        // the Portal Status dropdown. The status-specific tabs (Registered /
        // Unregistered / Old Portal) already pin a portal status, and Leads /
        // Referrals have no portal status — so the dropdown is hidden there.
        // Also hidden while a dashboard tile filter is active (single indicator).
        return !this.activeDashboardFilter
            && (this.activeTab === 'all' || this.activeTab === 'recent');
    }

    get portalStatusLabel() {
        switch (this.activePortalStatus) {
            case 'active':     return 'Active on New Portal';
            case 'registered': return 'Registered on New Portal';
            case 'not':        return 'Not on Portal';
            case 'old':        return 'Old Portal Record';
            default:           return 'All Portal Statuses';
        }
    }
    _ddItemClass(value) {
        return 'ken-dd-item' + (this.activePortalStatus === value ? ' selected' : '');
    }
    get portalStatusItemAll()    { return this._ddItemClass(''); }
    get portalStatusItemActive() { return this._ddItemClass('active'); }
    get portalStatusItemReg()    { return this._ddItemClass('registered'); }
    get portalStatusItemNot()    { return this._ddItemClass('not'); }
    get portalStatusItemOld()    { return this._ddItemClass('old'); }
    /* ---- Advanced multi-filter ---- */
    _toOptions(list) {
        return (list || []).map(v => ({ label: v, value: v }));
    }
    // Prefer the *Pairs (label "X (n)" / value "X") so the dropdown shows alumni
    // counts; fall back to the plain string list when Apex omits the pair.
    _pairOptions(pairs, fallback) {
        if (Array.isArray(pairs) && pairs.length) {
            return pairs.map(p => ({ label: p.label || p.value, value: p.value }));
        }
        return this._toOptions(fallback);
    }
    get programOptions()        { return this._pairOptions(this.filterOptionsRaw.programPairs,        this.filterOptionsRaw.programs); }
    get graduationYearOptions() { return this._pairOptions(this.filterOptionsRaw.graduationYearPairs, this.filterOptionsRaw.graduationYears); }
    get sourceOptions()         { return this._pairOptions(this.filterOptionsRaw.sourcePairs,         this.filterOptionsRaw.sources); }
    get companyOptions()        { return this._pairOptions(this.filterOptionsRaw.companyPairs,        this.filterOptionsRaw.companies); }
    get locationOptions()       { return this._pairOptions(this.filterOptionsRaw.locationPairs,       this.filterOptionsRaw.locations); }
    get countryOptions()        { return this._pairOptions(this.filterOptionsRaw.countryPairs,        this.filterOptionsRaw.countries); }
    // New Master-records filter set
    get instituteOptions()      { return this._pairOptions(this.filterOptionsRaw.institutePairs,     this.filterOptionsRaw.institutes); }
    get roleOptions()           { return this._pairOptions(this.filterOptionsRaw.rolePairs,          this.filterOptionsRaw.roles); }
    get intakeOptions()         { return this._pairOptions(this.filterOptionsRaw.intakePairs,        this.filterOptionsRaw.intakes); }
    get statusOptions()         { return this._pairOptions(this.filterOptionsRaw.statusPairs,        this.filterOptionsRaw.statuses); }
    get preferenceOptions()     { return this._pairOptions(this.filterOptionsRaw.preferencePairs,    this.filterOptionsRaw.preferences); }
    get employmentTypeOptions() { return this._pairOptions(this.filterOptionsRaw.employmentTypePairs, this.filterOptionsRaw.employmentTypes); }
    get genderFilterOptions()   { return this._pairOptions(this.filterOptionsRaw.genderPairs,         this.filterOptionsRaw.genders); }
    get languageOptions()       { return this._pairOptions(this.filterOptionsRaw.languagePairs,       null); }

    get filterProgram()        { return this.selectedFilters.program; }
    get filterGraduationYear() { return this.selectedFilters.graduationYear; }
    get filterSource()         { return this.selectedFilters.source; }
    get filterCompany()        { return this.selectedFilters.company; }
    get filterLocation()       { return this.selectedFilters.location; }
    get filterCountry()        { return this.selectedFilters.country; }
    // New Master-records filter set
    get filterInstitute()      { return this.selectedFilters.institute; }
    get filterRole()           { return this.selectedFilters.role; }
    get filterIntake()         { return this.selectedFilters.intake; }
    get filterStatus()         { return this.selectedFilters.status; }
    get filterPreference()     { return this.selectedFilters.preference; }
    get filterEmploymentType() { return this.selectedFilters.employmentType; }
    get filterGender()         { return this.selectedFilters.gender; }
    get filterLanguage()       { return this.selectedFilters.language; }

    // Badge count for each filter — the option's alumni count surfaces as a
    // small dot next to the dropdown once a value is picked.
    _countFor(pairs, value) {
        if (!value || !Array.isArray(pairs)) return '';
        const hit = pairs.find(p => p && p.value === value);
        return (hit && hit.count != null) ? String(hit.count) : '';
    }
    get instituteCount()      { return this._countFor(this.filterOptionsRaw.institutePairs,      this.selectedFilters.institute); }
    get programCount()        { return this._countFor(this.filterOptionsRaw.programPairs,        this.selectedFilters.program); }
    get intakeCount()         { return this._countFor(this.filterOptionsRaw.intakePairs,         this.selectedFilters.intake); }
    get graduationYearCount() { return this._countFor(this.filterOptionsRaw.graduationYearPairs, this.selectedFilters.graduationYear); }
    get companyCount()        { return this._countFor(this.filterOptionsRaw.companyPairs,        this.selectedFilters.company); }
    get roleCount()           { return this._countFor(this.filterOptionsRaw.rolePairs,           this.selectedFilters.role); }
    get locationCount()       { return this._countFor(this.filterOptionsRaw.locationPairs,       this.selectedFilters.location); }
    get countryCount()        { return this._countFor(this.filterOptionsRaw.countryPairs,        this.selectedFilters.country); }
    get sourceCount()         { return this._countFor(this.filterOptionsRaw.sourcePairs,         this.selectedFilters.source); }
    get statusCount()         { return this._countFor(this.filterOptionsRaw.statusPairs,         this.selectedFilters.status); }
    get preferenceCount()     { return this._countFor(this.filterOptionsRaw.preferencePairs,     this.selectedFilters.preference); }
    get employmentTypeCount() { return this._countFor(this.filterOptionsRaw.employmentTypePairs, this.selectedFilters.employmentType); }
    get genderCount()         { return this._countFor(this.filterOptionsRaw.genderPairs,         this.selectedFilters.gender); }

    get activeFilterCount() {
        if (!this.appliedFiltersJson) return 0;
        try {
            const f = JSON.parse(this.appliedFiltersJson);
            return Object.keys(f).filter(k => f[k]).length;
        } catch (e) {
            return 0;
        }
    }

    handleFiltersClick() {
        this.showFiltersPopup = true;
    }
    handleMapViewOpen() {
        // Full-page modal — only the map's own header (~80px) eats into the
        // viewport, same calc as the network/landing page map views.
        this.mapModalHeight = Math.max(420, window.innerHeight - 90);
        this.showMapModal = true;
        this._syncUrl();
    }
    handleMapModalClose() {
        this.showMapModal = false;
        this._syncUrl();
    }
    handleMapProfileSelect(event) {
        const detail = event.detail || {};
        // The Alumni 360 resolves cleanest from the ConstituentRole; fall back to
        // the Person Account Id.
        const alumniId = detail.constituentRoleId || detail.personId;
        if (!alumniId) {
            return;
        }
        this.personName = detail.name || '';
        this.personInitials = this._initials(detail.name || '');
        this.selectedAlumniId = alumniId;
        this.activeInnerTab = 'overview';
        this.alumni360Tab = 'overview';
        this.activeModal = null;
        this.showMapModal = false;
        this.showAlumni360 = true;
        this._syncUrl();
    }
    handleMapModalClick(e) {
        e.stopPropagation();
    }
    handleFiltersOverlayClick(e) {
        if (e.target.classList.contains('filters-overlay')) this.showFiltersPopup = false;
    }
    handleFiltersPopupClick(e) {
        e.stopPropagation();
    }
    handleFilterValueChange(e) {
        const field = e.target.dataset.field;
        if (!field) return;
        this.selectedFilters = { ...this.selectedFilters, [field]: (e.detail && e.detail.value) || '' };
    }
    handleApplyFilters() {
        const active = {};
        Object.keys(this.selectedFilters).forEach(k => {
            const v = this.selectedFilters[k];
            // Array-valued filters (language) are truthy even when empty ([] is
            // truthy in JS) — check .length so an empty selection isn't sent.
            const isSet = Array.isArray(v) ? v.length > 0 : Boolean(v);
            if (isSet) active[k] = v;
        });
        this.appliedFiltersJson = Object.keys(active).length ? JSON.stringify(active) : '';
        this.currentPage = 1;
        this.showFiltersPopup = false;
    }
    handleResetFilters() {
        this.selectedFilters = { ...EMPTY_FILTERS };
        this.appliedFiltersJson = '';
        this.currentPage = 1;
        this.showFiltersPopup = false;
    }

    handlePrevPage() {
        if (this.currentPage > 1) this.currentPage = this.currentPage - 1;
    }
    handleNextPage() {
        if (this.currentPage < this.totalPages) this.currentPage = this.currentPage + 1;
    }
    handleRow(e) {
        const row = e.currentTarget;
        const kind = row.dataset.modal;
        const name = row.dataset.name || '';
        const alumniId = row.dataset.alumniId || null;
        const gradYear = row.dataset.batch || '';
        const regNum = row.dataset.reg || '';
        const source = row.dataset.source || '';
        this.personName = name;
        this.personInitials = this._initials(name);
        this.selectedAlumniId = alumniId;
        if (kind === 'alumni') {
            // Skip the intermediate Overview modal — clicking an alumni row goes
            // straight to the Alumni 360 full-screen view. A Back button on the
            // 360 returns to the Master Records list.
            this.activeInnerTab = 'overview';
            this.alumni360Tab = 'overview';
            this.activeModal = null;
            this.showAlumni360 = true;
            this._syncUrl();
            return;
        }
        if (kind === 'issues') {
            this._userEditedEmail = false;
            this._userEditedPhone = false;
            this.issueEmailError = null;
            this.issuePhoneError = null;
            this.contactIssue = null;
        } else {
            // Suggestions are computed server-side from the lead's own captured
            // fields (reg number, name, email, phone) — see _loadMergeSuggestions
            // — so the search box no longer needs to be auto-seeded with a guess.
            this.mergeSearchTerm = '';
            this.mergeAppliedTerm = '';
            this.mergeGradYear = gradYear;
            this.selectedCandidateIds = [];
            this.capturedGradYear = gradYear || '—';
            this.capturedRegNumber = regNum;
            this.capturedSource = source;
            this.capturedDateLabel = '';
            this.capturedReferredBy = row.dataset.referredBy || '';
            this.capturedExistingAccountId = row.dataset.existingAccount || '';
            this.capturedExistingAccountName = row.dataset.existingAccountName || '';
            this.capturedIsNewRole = row.dataset.isNewRole === 'true';
            if (!this.capturedIsNewRole) this._loadMergeSuggestions(alumniId);
        }
        this.activeModal = kind;
        this._syncUrl();
    }

    _loadMergeSuggestions(leadId) {
        if (!leadId) return;
        this.mergeCandidatesLoading = true;
        getMergeSuggestions({ leadId })
            .then((data) => {
                this.mergeCandidates = data || [];
                this.mergeCandidatesLoading = false;
            })
            .catch(() => {
                this.mergeCandidates = [];
                this.mergeCandidatesLoading = false;
            });
    }

    handleIssueEmailInput(e) {
        this.issueEmailValue = (e.target.value || '').trim();
        this._userEditedEmail = true;
        this.issueEmailError = null;
    }
    handleIssuePhoneInput(e) {
        this.issuePhoneValue = (e.target.value || '').trim();
        this._userEditedPhone = true;
        this.issuePhoneError = null;
    }
    handleSaveEmail() {
        if (!this.selectedAlumniId) return;
        this.isSavingEmail = true;
        this.issueEmailError = null;
        saveContactEmail({ alumniId: this.selectedAlumniId, emailValue: this.issueEmailValue })
            .then((result) => {
                this.isSavingEmail = false;
                if (result && result.success) {
                    this._userEditedEmail = false;
                    if (this._wiredListResult) refreshApex(this._wiredListResult);
                    this.handleClose();
                } else if (result) {
                    this.issueEmailError = result.message || 'Save failed.';
                }
            })
            .catch((err) => {
                this.isSavingEmail = false;
                this.issueEmailError = (err && err.body && err.body.message) || 'Save failed.';
            });
    }
    handleSavePhone() {
        if (!this.selectedAlumniId) return;
        this.isSavingPhone = true;
        this.issuePhoneError = null;
        saveContactPhone({ alumniId: this.selectedAlumniId, phoneValue: this.issuePhoneValue })
            .then((result) => {
                this.isSavingPhone = false;
                if (result && result.success) {
                    this._userEditedPhone = false;
                    if (this._wiredListResult) refreshApex(this._wiredListResult);
                    this.handleClose();
                } else if (result) {
                    this.issuePhoneError = result.message || 'Save failed.';
                }
            })
            .catch((err) => {
                this.isSavingPhone = false;
                this.issuePhoneError = (err && err.body && err.body.message) || 'Save failed.';
            });
    }
    handleOpenFullProfile() {
        // From the Data Issues panel, jump straight to the full Alumni 360 view
        // instead of the intermediate overview modal.
        this.activeInnerTab = 'overview';
        this.alumni360Tab = 'overview';
        this.activeModal = null;
        this.showAlumni360 = true;
        this._syncUrl();
    }
    // Keeps its own debounce timer: sharing _searchDebounce with the background
    // list search meant typing in one box cancelled the other's pending update.
    handleMergeSearch(e) {
        const value = e.target.value || '';
        this.mergeSearchTerm = value;
        if (this._mergeSearchDebounce) clearTimeout(this._mergeSearchDebounce);
        this._mergeSearchDebounce = setTimeout(() => {
            this.mergeAppliedTerm = value;
            // Clearing the box back out doesn't revert to suggestions on its own
            // (the wire just skips and leaves the last search results in place) —
            // reload them explicitly so the list doesn't look stuck.
            if (!value.trim() && this.selectedAlumniId) this._loadMergeSuggestions(this.selectedAlumniId);
        }, 300);
    }
    handleView360() {
        // Keep selectedAlumniId so the child receives it; show the overlay.
        this.showAlumni360 = true;
        this._syncUrl();
    }
    handleClose360() {
        this.showAlumni360 = false;
        this._syncUrl();
    }
    stopBubble(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.activeModal = null;
        this.selectedAlumniId = null;
        this.alumniDetail = null;
        this.mergeSearchTerm = '';
        this.mergeAppliedTerm = '';
        this.mergeGradYear = '';
        this.mergeCandidates = [];
        this.selectedCandidateIds = [];
        this.mergeReviewActive = false;
        this.mergeReviewRows = [];
        this._mergeReviewMasterRoleId = null;
        this.mergeMultiReviewActive = false;
        this.mergeMultiReviewRows = [];
        this.mergeMultiReviewMasterNames = [];
        this._mergeMultiReviewMasterRoleIds = [];
        this.mergeMultiTargetId = '';
        this.isMergingMulti = false;
        this.contactIssue = null;
        this.issueEmailValue = '';
        this.issuePhoneValue = '';
        this.issueEmailError = null;
        this.issuePhoneError = null;
        this._userEditedEmail = false;
        this._userEditedPhone = false;
        this.timelineRowsRaw = [];
        this.historyRowsRaw = [];
        this.activeLeadTab = 'merge';
        this.commChannel = 'email';
        this.commSubject = '';
        this.commBody = '';
        this.commLogRaw = [];
        this.ownerSearchTerm = '';
        this.ownerOptions = [];
        this.selectedNewOwnerId = '';
        this.ownerReason = '';
        this._syncUrl();
    }
    handleOverlayClick(e) {
        if (e.target.classList.contains('modal-overlay')) this.handleClose();
    }
    handleEsc(e) {
        if (e.key === 'Escape') this.handleClose();
    }
    connectedCallback() {
        this._escBound = this.handleEsc.bind(this);
        document.addEventListener('keydown', this._escBound);
        this._navListener = (evt) => {
            const d = (evt && evt.detail) || {};
            if (d.tabKey) this.activeTab = d.tabKey;
            if (d.portalStatus !== undefined) this.activePortalStatus = d.portalStatus || '';
            if (d.dashboardFilter !== undefined) this.activeDashboardFilter = d.dashboardFilter || '';
            this.currentPage = 1;
            this._syncUrl();
        };
        window.addEventListener('kendash:navigate', this._navListener);
        // A dashboard tile click is a deliberate new destination, so it beats
        // whatever the address bar still describes. Otherwise restore the URL:
        // this runs when the Master Records sub-tab is activated (that is when
        // the component gets created), so after a refresh the dashboard
        // reopens this tab and the screen underneath comes back with it.
        this._popListener = this._handlePopState.bind(this);
        window.addEventListener('popstate', this._popListener);
        if (this._applyDashboardNavIntent()) {
            this._syncUrl();
        } else {
            const incoming = this._readUrlState();
            this._lastUrlSignature = this._urlSignature(incoming);
            this._lastUrlState = incoming;
            this._applyUrlState(incoming);
        }
    }

    // Returns true when a fresh dashboard tile intent was consumed — that intent
    // is newer than whatever the address bar still says, so it wins.
    _applyDashboardNavIntent() {
        try {
            const raw = sessionStorage.getItem('ken_dashboard_nav');
            if (!raw) return false;
            const intent = JSON.parse(raw);
            sessionStorage.removeItem('ken_dashboard_nav');
            if (!intent) return false;
            if (Date.now() - (intent.ts || 0) > 60000) return false;
            if (intent.tabKey) this.activeTab = intent.tabKey;
            if (intent.portalStatus !== undefined) this.activePortalStatus = intent.portalStatus;
            if (intent.dashboardFilter !== undefined) this.activeDashboardFilter = intent.dashboardFilter || '';
            this.currentPage = 1;
            return true;
        } catch (e) { /* ignore */ }
        return false;
    }

    get hasDashboardFilter() { return !!this.activeDashboardFilter; }
    get dashboardFilterLabel() {
        const m = {
            'upload-uploaded':       'All Data Upload · Records Uploaded',
            'upload-available':      'All Data Upload · Data Available',
            'upload-registered':     'All Data Upload · Registered',
            'upload-active':         'All Data Upload · Active',
            'transition-cohort':     'Student-to-Alumni · Graduating Cohort',
            'transition-invited':    'Student-to-Alumni · Invited to Portal',
            'transition-registered': 'Student-to-Alumni · Registered',
            'transition-active':     'Student-to-Alumni · Active',
            'leads-leads':           'Leads & Referrals · Leads',
            'leads-verified':        'Leads & Referrals · Verified',
            'leads-registered':      'Leads & Referrals · Registered',
            'leads-active':          'Leads & Referrals · Active',
            'kpi-total':             'Total Alumni',
            'kpi-verified':          'Institution Verified',
            'kpi-registered':        'Registered Alumni',
            'kpi-pending':           'Pending Activation',
            'kpi-unverified':        'Unverified Leads',
            'kpi-active':            'Active Alumni',
            'life-lead':                  'Lead Lifecycle · Lead',
            'life-unverified':            'Lead Lifecycle · Unverified',
            'life-leads':                 'Lead Lifecycle · Leads',
            'life-registered':            'Lead Lifecycle · Registered',
            
            'life-onboarding-inprogress': 'Lead Lifecycle · Onboarding In Progress',
            'life-onboarding':            'Lead Lifecycle · Onboarding',
            'life-active':                'Lead Lifecycle · Active'
        };
        return m[this.activeDashboardFilter] || this.activeDashboardFilter;
    }
    handleClearDashboardFilter() {
        this.activeDashboardFilter = '';
        this.currentPage = 1;
    }
    disconnectedCallback() {
        if (this._escBound) document.removeEventListener('keydown', this._escBound);
        if (this._navListener) window.removeEventListener('kendash:navigate', this._navListener);
        if (this._popListener) window.removeEventListener('popstate', this._popListener);
    }

    /* ---- Helpers ---- */
    _initials(name) {
        if (!name) return '';
        return name.trim().split(/\s+/).map(w => w[0]).slice(0, 2).join('').toUpperCase();
    }
    _statusPill(s) {
        if (s === 'Complete') return 'success';
        if (s === 'Invalid Contact') return 'danger';
        if (s === 'Review Required') return 'warn';
        if (s === 'Data Missing') return 'warn';
        if (s === 'Valid Details') return 'info';
        return 'neutral';
    }
    _portalPill(s) {
        if (s === 'Active') return 'success';
        if (s === 'Registered') return 'info';
        if (s === 'Unregistered') return 'neutral';
        return 'neutral';
    }
    _sourcePill(s) {
        if (!s) return 'neutral';
        if (s === 'Alumni Referral') return 'teal';
        if (s === 'Self-Declared Lead' || s === 'Campaign Lead') return 'teal';
        if (s === 'Old Portal Record' || s === 'Old Portal Migration') return 'violet';
        if (s === 'Historical Upload') return 'violet';
        if (s === 'Student-to-Alumni Transition') return 'info';
        return 'info';
    }
    _sourceLabel(s) {
        if (!s) return '';
        if (s === 'Self-Declared Lead' || s === 'Campaign Lead') return 'Self Registered';
        if (s === 'Alumni Referral') return 'Referral';
        if (s === 'Student-to-Alumni Transition') return 'Student-to-Alumni';
        if (s === 'Old Portal Record' || s === 'Old Portal Migration') return 'Old Portal Migration';
        return s;
    }
    _matchPill(s) {
        if (!s) return 'neutral';
        if (s === 'Exact Match' || s === 'Strong Match') return 'success';
        if (s === 'Merged') return 'success';
        if (s === 'Duplicate Suspected') return 'violet';
        if (s === 'No Match Found') return 'danger';
        if (s === 'Review Pending') return 'warn';
        return 'info';
    }
    _completenessTier(pct) {
        if (pct >= 75) return 'success';
        if (pct >= 50) return 'warn';
        return 'danger';
    }
    _formatDate(v) {
        if (!v) return '';
        try {
            const d = new Date(v);
            return d.toLocaleDateString();
        } catch (e) {
            return String(v);
        }
    }
}