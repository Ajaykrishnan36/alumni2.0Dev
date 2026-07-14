import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getPortalConfigs from '@salesforce/apex/KenThemeConfigController.getPortalConfigs';
import getAlumniRecords from '@salesforce/apex/KenAdminAlumniController.getAlumniRecords';
import getAlumniDetail from '@salesforce/apex/KenAdminAlumniController.getAlumniDetail';
import getMergeCandidates from '@salesforce/apex/KenAdminAlumniController.getMergeCandidates';
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
import getFilterOptions from '@salesforce/apex/KenAdminAlumniController.getFilterOptions';

const PAGE_SIZE = 25;

const EMPTY_FILTERS = {
    // Legacy keys kept so any other consumer of `selectedFilters` keeps working.
    program: '', graduationYear: '', source: '',
    company: '', industry: '', location: '', country: '',
    // New Master-records filter set
    institute: '', role: '', domain: '', intake: '', skill: '', status: '', preference: ''
};

export default class KenAdminAlumni extends NavigationMixin(LightningElement) {
    @track activeTab = 'all';
    @track activeModal = null;
    @track activeInnerTab = 'overview';
    @track activeIssueChip = 'all';
    @track personName = '';
    @track personInitials = '';

    @track searchTerm = '';
    @track activePortalStatus = '';
    @track activeDashboardFilter = '';
    @track portalStatusOpen = false;

    @track showFiltersPopup = false;
    @track selectedFilters = { ...EMPTY_FILTERS };
    @track appliedFiltersJson = '';
    @track filterOptionsRaw = {};
    @track currentPage = 1;
    @track selectedAlumniId = null;
    @track showAlumni360 = false;

    @track mergeSearchTerm = '';
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

    @track alumniList;
    @track alumniListLoading = true;
    @track alumniDetail;
    @track alumniDetailLoading = false;
    @track mergeCandidates = [];
    @track mergeCandidatesLoading = false;
    @track isRejecting = false;
    @track isMerging = false;

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
    @track convertSuccessMessage = '';
    _convertSuccessTimer;
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
    wiredFilterOptions({ data }) {
        if (data) this.filterOptionsRaw = data;
    }

    @wire(getActivityTimeline, { alumniId: '$detailWireId' })
    wiredTimeline({ data }) {
        if (data) this.timelineRowsRaw = data;
    }

    @wire(getFieldUpdateHistory, { alumniId: '$detailWireId' })
    wiredHistory({ data }) {
        if (data) this.historyRowsRaw = data;
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
    wiredDetail({ data, error }) {
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

    @wire(getMergeCandidates, { searchTerm: '$mergeWireSearch', gradYear: '$mergeWireYear' })
    wiredMerge({ data, error }) {
        if (data) {
            this.mergeCandidates = data;
            this.mergeCandidatesLoading = false;
        } else if (error) {
            this.mergeCandidates = [];
            this.mergeCandidatesLoading = false;
        } else if (this.mergeSearchTerm) {
            this.mergeCandidatesLoading = true;
        }
    }

    // Reactive wire params: returning `undefined` (not null) tells LWC to skip
    // the Apex call entirely. Returning null still invokes Apex with alumniId=null,
    // which throws "List has no rows for assignment to SObject" server-side.
    get detailWireId() {
        return (this.activeModal === 'alumni' && this.selectedAlumniId) ? this.selectedAlumniId : undefined;
    }

    get issueWireId() {
        return (this.activeModal === 'issues' && this.selectedAlumniId) ? this.selectedAlumniId : undefined;
    }

    get mergeWireSearch() {
        return (this.activeModal === 'lead' || this.activeModal === 'referral') ? this.mergeSearchTerm : undefined;
    }

    get mergeWireYear() {
        return (this.activeModal === 'lead' || this.activeModal === 'referral') ? this.mergeGradYear : undefined;
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
            dateLabel: this._formatDate(t.occurredAt)
        }));
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
            detail: 'Batch \'' + (c.batch || '—') + ' · ' + (c.registrationNumber || '—') + ' · ' + (c.source || '—')
        }));
    }
    get hasMergeRows() { return !this.mergeCandidatesLoading && this.mergeRows.length > 0; }
    get isMergeEmpty() { return !this.mergeCandidatesLoading && this.mergeRows.length === 0; }
    get isMergeLoading() { return this.mergeCandidatesLoading; }

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
                    this.showConvertSuccess(msg);
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
        this.showAlumni360 = true;
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

    handleMergeCandidate(e) {
        const masterRoleId = e.currentTarget.dataset.id;
        if (!masterRoleId || !this.selectedAlumniId || this.isMerging) return;
        this.isMerging = true;
        mergeLeadIntoMaster({ leadId: this.selectedAlumniId, masterRoleId })
            .then((res) => {
                this.isMerging = false;
                const msg = res && res.message ? res.message : '';
                if (res && res.success) {
                    this.showConvertSuccess(msg || 'Lead merged with the master record.');
                    if (this._wiredListResult)   refreshApex(this._wiredListResult);
                    if (this._wiredCountsResult) refreshApex(this._wiredCountsResult);
                    this.handleClose();
                } else if (msg) {
                    this.showConvertSuccess(msg);
                }
            })
            .catch((err) => {
                this.isMerging = false;
                this.showConvertSuccess((err && err.body && err.body.message) || 'Merge failed.');
            });
    }

    showConvertSuccess(message) {
        this.convertSuccessMessage = message;
        if (this._convertSuccessTimer) {
            clearTimeout(this._convertSuccessTimer);
        }
        this._convertSuccessTimer = setTimeout(() => {
            this.convertSuccessMessage = '';
            this._convertSuccessTimer = null;
        }, 3000);
    }
    handleChip(e) {
        this.activeIssueChip = e.currentTarget.dataset.chip;
        this.currentPage = 1;
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
    get industryOptions()       { return this._pairOptions(this.filterOptionsRaw.industryPairs,       this.filterOptionsRaw.industries); }
    get locationOptions()       { return this._pairOptions(this.filterOptionsRaw.locationPairs,       this.filterOptionsRaw.locations); }
    get countryOptions()        { return this._pairOptions(this.filterOptionsRaw.countryPairs,        this.filterOptionsRaw.countries); }
    // New Master-records filter set
    get instituteOptions()      { return this._pairOptions(this.filterOptionsRaw.institutePairs,     this.filterOptionsRaw.institutes); }
    get roleOptions()           { return this._pairOptions(this.filterOptionsRaw.rolePairs,          this.filterOptionsRaw.roles); }
    get domainOptions()         { return this._pairOptions(this.filterOptionsRaw.domainPairs,        this.filterOptionsRaw.domains); }
    get intakeOptions()         { return this._pairOptions(this.filterOptionsRaw.intakePairs,        this.filterOptionsRaw.intakes); }
    get skillOptions()          { return this._pairOptions(this.filterOptionsRaw.skillPairs,         this.filterOptionsRaw.skills); }
    get statusOptions()         { return this._pairOptions(this.filterOptionsRaw.statusPairs,        this.filterOptionsRaw.statuses); }
    get preferenceOptions()     { return this._pairOptions(this.filterOptionsRaw.preferencePairs,    this.filterOptionsRaw.preferences); }

    get filterProgram()        { return this.selectedFilters.program; }
    get filterGraduationYear() { return this.selectedFilters.graduationYear; }
    get filterSource()         { return this.selectedFilters.source; }
    get filterCompany()        { return this.selectedFilters.company; }
    get filterIndustry()       { return this.selectedFilters.industry; }
    get filterLocation()       { return this.selectedFilters.location; }
    get filterCountry()        { return this.selectedFilters.country; }
    // New Master-records filter set
    get filterInstitute()      { return this.selectedFilters.institute; }
    get filterRole()           { return this.selectedFilters.role; }
    get filterDomain()         { return this.selectedFilters.domain; }
    get filterIntake()         { return this.selectedFilters.intake; }
    get filterSkill()          { return this.selectedFilters.skill; }
    get filterStatus()         { return this.selectedFilters.status; }
    get filterPreference()     { return this.selectedFilters.preference; }

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
    get domainCount()         { return this._countFor(this.filterOptionsRaw.domainPairs,         this.selectedFilters.domain); }
    get industryCount()       { return this._countFor(this.filterOptionsRaw.industryPairs,       this.selectedFilters.industry); }
    get skillCount()          { return this._countFor(this.filterOptionsRaw.skillPairs,          this.selectedFilters.skill); }
    get locationCount()       { return this._countFor(this.filterOptionsRaw.locationPairs,       this.selectedFilters.location); }
    get countryCount()        { return this._countFor(this.filterOptionsRaw.countryPairs,        this.selectedFilters.country); }
    get sourceCount()         { return this._countFor(this.filterOptionsRaw.sourcePairs,         this.selectedFilters.source); }
    get statusCount()         { return this._countFor(this.filterOptionsRaw.statusPairs,         this.selectedFilters.status); }
    get preferenceCount()     { return this._countFor(this.filterOptionsRaw.preferencePairs,     this.selectedFilters.preference); }

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
            if (this.selectedFilters[k]) active[k] = this.selectedFilters[k];
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
        const email = row.dataset.email || '';
        const source = row.dataset.source || '';
        this.personName = name;
        this.personInitials = this._initials(name);
        this.selectedAlumniId = alumniId;
        if (kind === 'alumni') {
            // Skip the intermediate Overview modal — clicking an alumni row goes
            // straight to the Alumni 360 full-screen view. A Back button on the
            // 360 returns to the Master Records list.
            this.activeInnerTab = 'overview';
            this.activeModal = null;
            this.showAlumni360 = true;
            return;
        }
        if (kind === 'issues') {
            this._userEditedEmail = false;
            this._userEditedPhone = false;
            this.issueEmailError = null;
            this.issuePhoneError = null;
            this.contactIssue = null;
        } else {
            // Seed the merge search with the most precise identifier the lead has
            // (registration number, then email, then name) so the candidate that
            // produced the "Exact Match" badge actually surfaces — the badge keys
            // off reg/email, not the name.
            this.mergeSearchTerm = regNum || email || name;
            this.mergeGradYear = gradYear;
            this.capturedGradYear = gradYear || '—';
            this.capturedRegNumber = regNum;
            this.capturedSource = source;
            this.capturedDateLabel = '';
            this.capturedReferredBy = row.dataset.referredBy || '';
            this.capturedExistingAccountId = row.dataset.existingAccount || '';
            this.capturedExistingAccountName = row.dataset.existingAccountName || '';
            this.capturedIsNewRole = row.dataset.isNewRole === 'true';
        }
        this.activeModal = kind;
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
        this.activeModal = null;
        this.showAlumni360 = true;
    }
    handleMergeSearch(e) {
        const value = e.target.value || '';
        if (this._searchDebounce) clearTimeout(this._searchDebounce);
        this._searchDebounce = setTimeout(() => {
            this.mergeSearchTerm = value;
        }, 300);
    }
    handleView360() {
        // Keep selectedAlumniId so the child receives it; show the overlay.
        this.showAlumni360 = true;
    }
    handleClose360() {
        this.showAlumni360 = false;
    }
    stopBubble(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.activeModal = null;
        this.selectedAlumniId = null;
        this.alumniDetail = null;
        this.mergeSearchTerm = '';
        this.mergeGradYear = '';
        this.mergeCandidates = [];
        this.contactIssue = null;
        this.issueEmailValue = '';
        this.issuePhoneValue = '';
        this.issueEmailError = null;
        this.issuePhoneError = null;
        this._userEditedEmail = false;
        this._userEditedPhone = false;
        this.timelineRowsRaw = [];
        this.historyRowsRaw = [];
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
        };
        window.addEventListener('kendash:navigate', this._navListener);
        this._applyDashboardNavIntent();
    }

    _applyDashboardNavIntent() {
        try {
            const raw = sessionStorage.getItem('ken_dashboard_nav');
            if (!raw) return;
            const intent = JSON.parse(raw);
            sessionStorage.removeItem('ken_dashboard_nav');
            if (!intent) return;
            if (Date.now() - (intent.ts || 0) > 60000) return;
            if (intent.tabKey) this.activeTab = intent.tabKey;
            if (intent.portalStatus !== undefined) this.activePortalStatus = intent.portalStatus;
            if (intent.dashboardFilter !== undefined) this.activeDashboardFilter = intent.dashboardFilter || '';
            this.currentPage = 1;
        } catch (e) { /* ignore */ }
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
            'kpi-registered':        'Portal Registered',
            'kpi-pending':           'Pending Activation'
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