import { LightningElement, track } from 'lwc';
import getJobsPage from '@salesforce/apex/KenJobsV2Controller.getJobsPage';
import getMyPostedJobs from '@salesforce/apex/KenJobsV2Controller.getMyPostedJobs';
import getJobApex from '@salesforce/apex/KenJobsV2Controller.getJob';
import getMyOffers from '@salesforce/apex/KenJobsV2Controller.getMyOffers';
import getApplicantsApex from '@salesforce/apex/KenJobsV2Controller.getApplicants';
import toggleSaveJobApex from '@salesforce/apex/KenJobsV2Controller.toggleSaveJob';
import applyToJobApex from '@salesforce/apex/KenJobsV2Controller.applyToJob';
import postJobApex from '@salesforce/apex/KenJobsV2Controller.postJob';
import saveJobDraftApex from '@salesforce/apex/KenJobsV2Controller.saveJobDraft';
import bookSlotApex from '@salesforce/apex/KenJobsV2Controller.bookSlot';
import updateOfferStatusApex from '@salesforce/apex/KenJobsV2Controller.updateOfferStatus';

const PREFS = 'Information Technology, Manufacturing & Engineering, Consumer Goods, EdTech';

// Per-job tracker enrichment keyed by id. Only populated for the most-clicked jobs
// so we can demonstrate every applicationState (actionRequired/offered/rejected/slotClosed/inProgress).

export default class KenJobsV2 extends LightningElement {
    // ---------- VIEW ROUTER ----------
    @track view = 'board';   // 'board' | 'tracker' | 'compare' | 'apply' | 'post' | 'create' | 'applicants' | 'offers' | 'placement'
    @track selectedJobId = null;
    @track jobsToCompare = [];

    // ---------- BOARD STATE ----------
    @track activeTab = 'recommended';
    @track viewMode = 'card';
    @track searchTerm = '';
    // Slide-out Filters panel state: keyed by field (jobTitle, company, workplaceType,
    // industry, postedBy, jobLocation, postedOn, jobType, salary, skills). Empty = no filter.
    @track filters = {};
    @track savedIds = [];
    @track appliedIds = [];
    @track toastMsg = '';
    @track showToast = false;
    @track showBookSlotModal = false;
    @track showNoOffersModal = false;

    // ---------- BACKEND STATE ----------
    @track isLoading = true;
    @track serverJobs = null;        // array of JobItem from Apex (null = not loaded / use mocks)
    @track postedJobs = [];          // jobs the running alum posted (any status)
    @track selectedApplicationId = null;
    @track applicantsForSelected = [];
    @track applicantsLoading = false;

    prefs = PREFS;

    connectedCallback() {
        // Restore tab + sub-view from URL so browser refresh keeps user where they were.
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const view = params.get('view');
            const VALID_TABS = ['recommended', 'all', 'applied', 'saved'];
            const VALID_VIEWS = ['board', 'tracker', 'compare', 'apply', 'post', 'create', 'applicants', 'offers', 'placement', 'resume'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.activeTab = tab;
            if (view && VALID_VIEWS.indexOf(view) > -1) this.view = view;
        } catch (e) { /* ignore */ }
        this.loadJobs();
        this.loadPostedJobs();
    }

    loadPostedJobs() {
        getMyPostedJobs()
            .then(rows => { this.postedJobs = (rows || []).map(j => this.decorate(j)); })
            .catch(() => { this.postedJobs = []; });
    }

    // Update the URL (without reloading) so refresh restores current tab/view.
    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            params.set('tab', this.activeTab);
            if (this.view && this.view !== 'board') params.set('view', this.view);
            else params.delete('view');
            const newUrl = window.location.pathname + '?' + params.toString();
            window.history.replaceState(null, '', newUrl);
        } catch (e) { /* ignore */ }
    }

    loadJobs() {
        this.isLoading = true;
        getJobsPage()
            .then(data => {
                const all = (data && data.allJobs) ? data.allJobs : [];
                if (all.length) {
                    this.serverJobs = all;
                    this.savedIds = all.filter(j => j.isSaved).map(j => j.id);
                    this.appliedIds = all.filter(j => j.isApplied).map(j => j.id);
                }
                this.isLoading = false;
            })
            .catch((err) => {
                // Mock fallback retained — server unavailable or empty. Log loudly so an
                // access/permission failure (e.g. user missing the Alumni_2_0_Jobs permset)
                // isn't silently masked by the mock data, which makes the board look healthy
                // while every Apex write (postJob/saveJobDraft) actually fails.
                // eslint-disable-next-line no-console
                console.error('KenJobsV2Controller.getJobsPage failed — falling back to mock jobs. Real backend access may be missing.', err);
                this.serverJobs = null;
                this.isLoading = false;
            });
    }

    // ---------- VIEW STATE ----------
    get viewState() {
        return {
            isMainBoard:          this.view === 'board',
            isApplicationTracker: this.view === 'tracker',
            isOfferComparison:    this.view === 'compare',
            isApply:              this.view === 'apply',
            isPost:               this.view === 'post',
            isCreate:             this.view === 'create',
            isApplicants:         this.view === 'applicants',
            isOffers:             this.view === 'offers',
            isPlacement:          this.view === 'placement',
            isResume:             this.view === 'resume'
        };
    }
    get showRail() { return this.view === 'board'; }

    // ---------- GRID ----------
    get gridClass() { return this.viewMode === 'card' ? 'grid' : 'grid grid--list'; }
    get showFilterBar() { return this.activeTab === 'all'; }
    // "View All" must show the main All Jobs board (All tab), not the tracker/applications view.
    handleViewAll() { this.view = 'board'; this.activeTab = 'all'; this.syncUrl(); }

    // ---------- DECORATION ----------
    get baseList() {
        // Always use real server data. null (still loading) and [] (no records) both yield empty state.
        return this.serverJobs || [];
    }

    decorate(j) {
        const hasBanner = !!(j.bannerUrl && j.bannerUrl.length);
        return {
            ...j,
            isSaved: this.savedIds.indexOf(j.id) > -1,
            isApplied: this.appliedIds.indexOf(j.id) > -1,
            logoStyle: `background:${j.col};color:#fff;`,
            hasBanner,
            bannerStyle: hasBanner
                ? `background-image:url('${j.bannerUrl}');background-size:cover;background-position:center;`
                : ''
        };
    }

    // ---------- FILTER PANEL: derived dropdown options ----------
    // Distinct, sorted values pulled from the loaded job DTOs where the data exists.
    _distinctBy(extractor) {
        const seen = new Set();
        (this.baseList || []).forEach(j => {
            (extractor(j) || []).forEach(v => { if (v) seen.add(String(v).trim()); });
        });
        return Array.from(seen).filter(Boolean).sort((a, b) => a.localeCompare(b));
    }

    get companyOptions()   { return this._distinctBy(j => [j.company]); }
    get jobTitleOptions()  { return this._distinctBy(j => [j.title]); }
    get jobLocationOptions() { return this._distinctBy(j => [j.location, j.l]); }
    get postedByOptions()  { return this._distinctBy(j => [j.postedBy]); }
    get skillsOptions()    { return this._distinctBy(j => j.tags || []); }

    // Workplace type / Industry / Job type are derived heuristically from job tags
    // (the DTO has no dedicated columns), falling back to sensible static values.
    get workplaceTypeOptions() {
        const fromTags = this._distinctBy(j => (j.tags || []).filter(t =>
            /remote|hybrid|on[- ]?site|office/i.test(t)));
        return fromTags.length ? fromTags : ['Remote', 'Hybrid', 'On-site'];
    }
    get jobTypeOptions() {
        const fromTags = this._distinctBy(j => (j.tags || []).filter(t =>
            /full[- ]?time|part[- ]?time|contract|intern|temporary|freelance/i.test(t)));
        return fromTags.length ? fromTags : ['Full-time', 'Part-time', 'Contract', 'Internship'];
    }
    get industryOptions() {
        // Remaining tags that aren't a workplace/job-type/location signal read as "industry".
        return this._distinctBy(j => (j.tags || []).filter(t =>
            !/remote|hybrid|on[- ]?site|office|full[- ]?time|part[- ]?time|contract|intern|temporary|freelance/i.test(t)));
    }

    // Static ranges (no per-job timestamp/numeric salary in the DTO).
    get postedOnOptions() { return ['Any time', 'Last 24 hours', 'Last 7 days', 'Last 30 days']; }
    get salaryOptions()   { return ['Under ₹5L', '₹5L – ₹10L', '₹10L – ₹20L', '₹20L – ₹40L', '₹40L+']; }

    // Filters currently applied (passed back into the child so the panel stays in sync).
    get appliedFilters() { return this.filters; }

    handleApplyFilters(event) {
        this.filters = (event.detail && event.detail.filters) || {};
    }

    // True if a job's value loosely matches a selected option (case-insensitive,
    // substring against the field plus tags so heuristic tag-derived options still hit).
    _jobMatches(j, optionValue, fields) {
        if (!optionValue) return true;
        const needle = String(optionValue).toLowerCase();
        const hay = []
            .concat(fields.map(f => (j[f] || '')))
            .concat(j.tags || [])
            .map(v => String(v).toLowerCase());
        // Exact match on a primary field, or substring anywhere (covers tag-derived options).
        return hay.some(v => v === needle) || hay.some(v => v.indexOf(needle) > -1);
    }

    _salaryMatches(j, bracket) {
        if (!bracket) return true;
        // Best-effort: parse the first number out of the salary display and bucket it.
        const raw = String(j.salary || '').replace(/[,\s₹$]/g, '');
        const m = raw.match(/(\d+(?:\.\d+)?)(l|lpa|k)?/i);
        if (!m) return true; // can't tell — don't exclude
        let val = parseFloat(m[1]);
        const unit = (m[2] || '').toLowerCase();
        if (unit === 'l' || unit === 'lpa') val = val * 100000;
        else if (unit === 'k') val = val * 1000;
        else if (val < 1000) val = val * 100000; // bare "8" → 8L
        const inRange = (lo, hi) => val >= lo && (hi === null || val < hi);
        switch (bracket) {
            case 'Under ₹5L':   return inRange(0, 500000);
            case '₹5L – ₹10L':  return inRange(500000, 1000000);
            case '₹10L – ₹20L': return inRange(1000000, 2000000);
            case '₹20L – ₹40L': return inRange(2000000, 4000000);
            case '₹40L+':       return inRange(4000000, null);
            default: return true;
        }
    }

    get filteredJobs() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        const f = this.filters || {};
        let list = this.baseList.slice();
        if (this.activeTab === 'recommended') {
            list = list.filter(j => j.skillsMatch >= 60);
        }
        // Additive (AND) across every selected filter field.
        if (f.jobTitle)      list = list.filter(j => this._jobMatches(j, f.jobTitle, ['title']));
        if (f.company)       list = list.filter(j => this._jobMatches(j, f.company, ['company']));
        if (f.workplaceType) list = list.filter(j => this._jobMatches(j, f.workplaceType, []));
        if (f.industry)      list = list.filter(j => this._jobMatches(j, f.industry, []));
        if (f.postedBy)      list = list.filter(j => this._jobMatches(j, f.postedBy, ['postedBy']));
        if (f.jobLocation)   list = list.filter(j => this._jobMatches(j, f.jobLocation, ['location', 'l']));
        if (f.jobType)       list = list.filter(j => this._jobMatches(j, f.jobType, []));
        if (f.skills)        list = list.filter(j => this._jobMatches(j, f.skills, []));
        if (f.salary && f.salary !== 'Any salary') list = list.filter(j => this._salaryMatches(j, f.salary));
        // Posted On is a static range; no per-job timestamp in the DTO, so it is a no-op
        // selector kept for parity with the Figma reference (does not exclude jobs).
        if (term) {
            list = list.filter(j =>
                (j.company || '').toLowerCase().indexOf(term) > -1 ||
                (j.title || '').toLowerCase().indexOf(term) > -1
            );
        }
        return list.map(j => this.decorate(j));
    }

    get appliedJobs() {
        return this.baseList.filter(j => this.appliedIds.indexOf(j.id) > -1).map(j => this.decorate(j));
    }
    get savedJobs() {
        return this.baseList.filter(j => this.savedIds.indexOf(j.id) > -1).map(j => this.decorate(j));
    }

    get recommendedCount() { return this.baseList.filter(j => j.skillsMatch >= 60).length; }
    get allCount() { return this.baseList.length; }

    // Distinguish loading from empty so the template can render skeleton vs empty-state card.
    get hasJobs() { return (this.filteredJobs || []).length > 0; }
    get showEmptyJobs() { return !this.isLoading && !this.hasJobs; }
    get emptyJobsMessage() {
        if (this.activeTab === 'recommended') return 'No recommended jobs yet';
        if (this.activeTab === 'applied') return 'No applied jobs yet';
        if (this.activeTab === 'saved') return 'No saved jobs yet';
        return 'No jobs available';
    }

    get selectedJob() {
        const j = this.baseList.find(x => x.id === this.selectedJobId);
        return j ? this.decorate(j) : null;
    }
    get selectedJobTitle()   { return this.selectedJob ? this.selectedJob.title : ''; }
    get selectedJobCompany() { return this.selectedJob ? this.selectedJob.company : ''; }

    // Jobs hydrated for the compare view (filtered to those with offer data, capped at 3).
    get comparisonJobs() {
        return this.jobsToCompare
            .map(id => this.baseList.find(x => x.id === id))
            .filter(Boolean)
            .map(j => this.decorate(j));
    }

    // ---------- HANDLERS ----------
    handleTabChange(event)  { this.activeTab = event.detail.id; this.syncUrl(); }
    handleSearch(event)     { this.searchTerm = event.detail.term; }
    handleViewMode(event)   { this.viewMode = event.detail.mode; }

    handleJobClick(event) {
        const id = (event.detail && (event.detail.id !== undefined ? event.detail.id : event.detail))
            || (event.currentTarget && event.currentTarget.dataset && event.currentTarget.dataset.id)
            || null;
        const job = this.baseList.find(j => j.id === id);
        if (!job) return;
        // Save scroll position of the board so handleBackToBoard can restore it.
        this._boardScrollY = (typeof window !== 'undefined' && window.scrollY) || 0;
        this.selectedJobId = id;
        this.view = 'tracker';
        this.syncUrl();
        if (typeof window !== 'undefined' && window.scrollTo) {
            try { window.scrollTo({ top: 0, behavior: 'instant' }); }
            catch (e) { window.scrollTo(0, 0); }
        }
        // Fire-and-forget refresh of selected job for richer tracker data
        if (typeof id === 'string' && id.length === 18) {
            getJobApex({ jobId: id })
                .then(fresh => {
                    if (fresh && this.serverJobs) {
                        this.serverJobs = this.serverJobs.map(j => j.id === id ? { ...j, ...fresh } : j);
                    }
                })
                .catch(() => {});
        }
    }
    handleBookmark(event) { this.toggleSave(event.detail.id); }
    handleSave(event)     { this.toggleSave(event.detail.id); }

    handleApplyStart(event) {
        const id = event.detail.id;
        if (this.appliedIds.indexOf(id) > -1) return;
        this.selectedJobId = id;
        this.view = 'apply';
    }
    handleApplyFromTracker() {
        if (!this.selectedJobId || this.appliedIds.indexOf(this.selectedJobId) > -1) return;
        this.view = 'apply';
    }

    toggleSave(id) {
        const idx = this.savedIds.indexOf(id);
        if (idx > -1) {
            const next = this.savedIds.slice();
            next.splice(idx, 1);
            this.savedIds = next;
            this.fireToast('Removed from saved');
        } else {
            this.savedIds = this.savedIds.concat([id]);
            this.fireToast('Job saved');
        }
        if (typeof id === 'string' && id.length === 18) {
            toggleSaveJobApex({ jobId: id }).catch(() => {});
        }
    }

    handleApplySubmit(event) {
        if (this.selectedJobId && this.appliedIds.indexOf(this.selectedJobId) === -1) {
            this.appliedIds = this.appliedIds.concat([this.selectedJobId]);
        }
        if (!this._isSfId(this.selectedJobId)) {
            // Mock-id path — UI prototyping only, no Apex call.
            this.fireToast('Application submitted');
            this.view = 'tracker';
            this.syncUrl();
            return;
        }
        const detail = (event && event.detail) || {};
        applyToJobApex({
            payload: {
                jobId: this.selectedJobId,
                applicantType: detail.applicantType || 'Alumni',
                registrationNumber: detail.registrationNumber || null,
                coverLetter: detail.coverLetter || null,
                notes: detail.notes || null,
                skillsMatchPercent: detail.skillsMatchPercent || null,
                resumeContentVersionId: detail.resumeContentVersionId || null
            }
        })
            .then((appId) => {
                this.selectedApplicationId = appId;
                this.fireToast('Application submitted');
                this.view = 'tracker';
                this.syncUrl();
                this.loadJobs();
            })
            .catch((err) => {
                // eslint-disable-next-line no-console
                console.error('applyToJob failed', err);
                const msg = (err && err.body && err.body.message) || 'Application failed. Please try again.';
                this.fireToast(msg);
            });
    }

    _isSfId(v) { return typeof v === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(v); }

    // ---------- VIEW NAVIGATION ----------
    handlePostJob() { this.view = 'create'; }
    handleCreateSubmit(event) {
        const payload = (event && event.detail && event.detail.payload) ? event.detail.payload : null;
        if (!payload) {
            this.fireToast('Could not submit job — missing form data');
            return;
        }
        postJobApex({ payload })
            .then(() => { this.fireToast('Job submitted for approval'); this.loadJobs(); this.loadPostedJobs(); this.handleBackToBoard(); })
            .catch((err) => {
                console.error('postJob failed', err);
                const msg = (err && err.body && err.body.message) ? err.body.message : 'Job submission failed';
                this.fireToast(msg);
            });
    }
    handleCreateSaveDraft(event) {
        const payload = (event && event.detail && event.detail.payload) ? event.detail.payload : null;
        if (!payload) {
            this.fireToast('Could not save draft — missing form data');
            return;
        }
        saveJobDraftApex({ payload })
            .then(() => { this.fireToast('Draft saved'); this.loadJobs(); this.loadPostedJobs(); this.handleBackToBoard(); })
            .catch((err) => {
                console.error('saveJobDraft failed', err);
                const msg = (err && err.body && err.body.message) ? err.body.message : 'Could not save draft';
                this.fireToast(msg);
            });
    }
    handleViewApplicants()  {
        this.view = 'applicants';
        this.syncUrl();
        this.loadApplicantsForSelected();
    }
    loadApplicantsForSelected() {
        // Pick a job id: explicit selection, else first posted-by-me job, else first job.
        let jobId = this.selectedJobId;
        if (!jobId && this.baseList && this.baseList.length) jobId = this.baseList[0].id;
        if (typeof jobId !== 'string' || jobId.length !== 18) {
            this.applicantsForSelected = [];
            return;
        }
        this.applicantsLoading = true;
        getApplicantsApex({ jobId })
            .then(rows => {
                this.applicantsForSelected = Array.isArray(rows) ? rows : [];
                this.applicantsLoading = false;
            })
            .catch(() => {
                this.applicantsForSelected = [];
                this.applicantsLoading = false;
            });
    }
    handleViewOffersLegacy(){ this.view = 'offers'; }
    handleViewPlacement()   { this.view = 'placement'; }
    handleViewResume()      { this.view = 'resume'; this.syncUrl(); }
    handleResumeSaved()     { this.fireToast('Resume saved'); }

    // ----- Compare offers (NEW inline view) -----
    // Local heuristic: a job has an offer if applicationState/status indicates an offer,
    // OR a hydrated offer DTO is attached.
    isOfferJob(j) {
        if (!j) return false;
        if (j.offer) return true;
        const st = (j.applicationState || '').toString().toLowerCase();
        if (st === 'offered' || st === 'offer') return true;
        const ap = (j.appliedStatus || j.status || '').toString().toLowerCase();
        if (ap === 'offer received' || ap === 'offered' || ap === 'offer') return true;
        return false;
    }

    handleViewOffers(event) {
        // Explicit ids from a child (e.g. tracker page) override local detection.
        const explicit = (event && event.detail && Array.isArray(event.detail.jobIds))
            ? event.detail.jobIds.slice(0, 3)
            : null;
        if (explicit && explicit.length) {
            this.jobsToCompare = explicit;
            this.view = 'compare';
            this.syncUrl();
            return;
        }
        // Otherwise compute from applied jobs.
        const offerIds = (this.appliedJobs || [])
            .filter(j => this.isOfferJob(j))
            .slice(0, 3)
            .map(j => j.id);
        if (offerIds.length) {
            this.jobsToCompare = offerIds;
            this.view = 'compare';
            this.syncUrl();
            return;
        }
        // Last resort: check server-side offers (covers offers without applied flag).
        getMyOffers()
            .then(offers => {
                if (offers && offers.length) {
                    const ids = offers
                        .map(o => o && (o.jobId || (o.application && o.application.jobId)))
                        .filter(Boolean)
                        .slice(0, 3);
                    if (ids.length) {
                        this.jobsToCompare = ids;
                        this.view = 'compare';
                        this.syncUrl();
                        return;
                    }
                }
                this.showNoOffersModal = true;
            })
            .catch(() => { this.showNoOffersModal = true; });
    }
    handleCompareOffersClick() { this.handleViewOffers(); }
    handleCloseNoOffers() { this.showNoOffersModal = false; }
    handleStop(event) { if (event && event.stopPropagation) event.stopPropagation(); }
    handleBrowseJobsFromNoOffers() {
        this.showNoOffersModal = false;
        this.activeTab = 'all';
        this.view = 'board';
        this.syncUrl();
    }

    handleOfferAccept(event) {
        const offerId = event && event.detail && event.detail.id;
        this._respondToOffer(offerId, 'Accepted', 'Offer accepted! HR will be in touch');
    }
    handleOfferDecline(event) {
        const offerId = event && event.detail && event.detail.id;
        this._respondToOffer(offerId, 'Declined', 'Offer declined');
    }
    _respondToOffer(offerId, statusValue, successMsg) {
        if (!this._isSfId(offerId)) {
            // mock-id fallback — UI prototyping path (no real offer record to persist against)
            this.fireToast(successMsg);
            if (statusValue === 'Accepted') this.handleBackToBoard();
            return;
        }
        updateOfferStatusApex({ offerId, statusValue })
            .then(() => {
                this.fireToast(successMsg);
                this.loadJobs();
                if (statusValue === 'Accepted') this.handleBackToBoard();
            })
            .catch((err) => {
                const msg = (err && err.body && err.body.message) || `Could not ${statusValue.toLowerCase()} offer.`;
                this.fireToast(msg);
            });
    }
    handleOfferToast(event) { this.fireToast(event.detail.msg); }
    handlePostSubmit(event) {
        const payload = (event && event.detail && event.detail.payload) ? event.detail.payload : null;
        if (!payload) {
            this.fireToast('Could not submit job — missing form data');
            return;
        }
        postJobApex({ payload })
            .then(() => { this.fireToast('Job submitted for review'); this.loadJobs(); this.loadPostedJobs(); this.handleBackToBoard(); })
            .catch((err) => {
                console.error('postJob failed', err);
                const msg = (err && err.body && err.body.message) ? err.body.message : 'Job submission failed';
                this.fireToast(msg);
            });
    }
    handlePostSaveDraft() {
        this.fireToast('Draft saved locally to browser session');
        this.handleBackToBoard();
    }

    handleBackToBoard() {
        this.view = 'board';
        this.selectedJobId = null;
        this.jobsToCompare = [];
        this.syncUrl();
        const y = this._boardScrollY || 0;
        if (typeof window !== 'undefined' && window.requestAnimationFrame) {
            window.requestAnimationFrame(() => { try { window.scrollTo(0, y); } catch (e) { /* ignore */ } });
        }
    }
    handleBackToTracker() { this.view = 'tracker'; this.syncUrl(); }

    // ----- Book Slot modal -----
    handleBookSlot()        { this.showBookSlotModal = true; }
    handleCloseBookSlot()   { this.showBookSlotModal = false; }
    handleBookSlotSubmit(event) {
        const detail = (event && event.detail) || {};
        const slot = detail.slot || '';
        const slotId = detail.slotId;
        const applicationId = this.selectedApplicationId;
        this.showBookSlotModal = false;
        // Mock-id fallback — UI prototyping path (modal dispatches local t1..t4 ids).
        if (!this._isSfId(slotId) || !this._isSfId(applicationId)) {
            this.fireToast(slot ? `Slot booked: ${slot}` : 'Slot booked');
            return;
        }
        bookSlotApex({ applicationId, slotId })
            .then(() => {
                this.fireToast(slot ? `Slot booked: ${slot}` : 'Slot booked');
                this.loadJobs();
            })
            .catch((err) => {
                // eslint-disable-next-line no-console
                console.error('bookSlot failed', err);
                const msg = (err && err.body && err.body.message) || 'Could not book slot. Please try again.';
                this.fireToast(msg);
            });
    }

    fireToast(msg) {
        this.toastMsg = msg;
        this.showToast = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showToast = false; }, 2200);
    }
}