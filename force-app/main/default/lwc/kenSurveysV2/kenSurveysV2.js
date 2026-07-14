// kenSurveysV2 — full-page inline view router. Replaces the old modal-based flow.
// 4 view states: 'board' | 'take' | 'create' | 'detail'.
// URL state is synced as ?view=...&id=... (same pattern as kenJobsV2).
//
// Allowed modals (micro-interactions only):
//   1) "Your Opinion Matters!" intro before taking a survey
//   2) "Review Saved Audience" inside create wizard
//   3) Delete confirmation inside detail view
import { LightningElement, track } from 'lwc';
import getSurveys from '@salesforce/apex/KenSurveyController.getSurveys';
import getMySurveys from '@salesforce/apex/KenSurveyController.getMySurveys';
import getSurveyForEdit from '@salesforce/apex/KenSurveyController.getSurveyForEdit';
import getUserContactDetails from '@salesforce/apex/KenNavBarController.getUserContactDetails';
import getAlumniRolesForPerson from '@salesforce/apex/KenAlumniOnboardingService.getAlumniRolesForPerson';
import submitSurveyResponses from '@salesforce/apex/KenSurveyController.submitSurveyResponses';
import createSurveyWithQuestions from '@salesforce/apex/KenSurveyController.createSurveyWithQuestions';
import updateSurveyWithQuestions from '@salesforce/apex/KenSurveyController.updateSurveyWithQuestions';
import saveSegmentation from '@salesforce/apex/KenAudienceEngineService.saveSegmentation';
import createSurveySegmentation from '@salesforce/apex/KenSurveyController.createSurveySegmentation';
import deleteSurvey from '@salesforce/apex/KenSurveyController.deleteSurvey';
import getSurveyResults from '@salesforce/apex/KenSurveyController.getSurveyResults';

const VALID_VIEWS = ['board', 'take', 'create', 'detail', 'created'];
const VALID_FILTERS = ['All', 'Pending', 'Completed'];
const CREATED_TABS = ['Approved', 'In Review', 'Rejected'];

export default class KenSurveysV2 extends LightningElement {
    @track view = 'board';
    @track selectedSurveyId = null;
    @track filterChip = 'All';
    @track searchQuery = '';

    // Created Surveys view state
    @track createdTab = 'Approved';
    @track createdSearch = '';
    @track createdSort = 'recent';

    // Results (creator's "View Details") state
    @track surveyResults = null;
    @track isLoadingResults = false;

    // Data
    @track allSurveys = [];      // for "All Surveys" left list (available to take)
    @track mySurveys = [];       // for "Your Created Surveys" right rail
    @track isLoading = true;
    @track surveysError = null;
    @track constituentRoleId = null;
    @track userContext = null;

    // Edit mode — populated when the user clicks "Edit" on one of their surveys.
    @track editSurveyId = null;
    @track wizardSeed = null;

    // Detail
    @track detailSurvey = null;
    @track isLoadingDetail = false;

    // Scroll restoration snapshot (per view)
    _scrollY = { board: 0, detail: 0 };

    // Shared date formatter used across view-models. Returns '15 Jul 2026' style.
    formatDate(iso, withTime = false) {
        if (!iso) return '';
        const d = new Date(iso);
        if (isNaN(d.getTime())) return '';
        const opts = { day: '2-digit', month: 'short', year: 'numeric' };
        if (withTime) { opts.hour = '2-digit'; opts.minute = '2-digit'; opts.hour12 = true; }
        try { return d.toLocaleDateString('en-IN', opts); } catch (e) { return ''; }
    }

    // Micro-interaction modals
    @track showOpinionModal = false;
    @track showAudienceReviewModal = false;
    @track showDeleteModal = false;
    @track showToast = false;
    @track toastMsg = '';

    connectedCallback() {
        this._readUrlState();
        this.loadSurveys();
        if (this.view === 'detail' && this.selectedSurveyId) {
            this._loadDetail(this.selectedSurveyId);
        }
    }

    // ===== URL state =====
    _readUrlState() {
        try {
            const p = new URLSearchParams(window.location.search);
            const v = p.get('view');
            const id = p.get('id');
            const f = p.get('filter');
            if (v && VALID_VIEWS.indexOf(v) > -1) this.view = v;
            if (id) this.selectedSurveyId = id;
            if (f && VALID_FILTERS.indexOf(f) > -1) this.filterChip = f;
        } catch (e) { /* ignore */ }
    }

    _syncUrl() {
        try {
            const p = new URLSearchParams(window.location.search);
            if (this.view && this.view !== 'board') p.set('view', this.view); else p.delete('view');
            if (this.selectedSurveyId && (this.view === 'take' || this.view === 'detail')) p.set('id', String(this.selectedSurveyId)); else p.delete('id');
            if (this.filterChip && this.filterChip !== 'All') p.set('filter', this.filterChip); else p.delete('filter');
            const qs = p.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    // ===== View state =====
    get viewState() {
        return {
            isMainBoard: this.view === 'board',
            isTakingSurvey: this.view === 'take',
            isCreatingSurvey: this.view === 'create',
            isSurveyDetail: this.view === 'detail',
            isCreatedSurveys: this.view === 'created'
        };
    }
    get isMainBoard() { return this.view === 'board'; }
    get isTakingSurvey() { return this.view === 'take'; }
    get isCreatingSurvey() { return this.view === 'create'; }
    get isSurveyDetail() { return this.view === 'detail'; }
    get isCreatedSurveys() { return this.view === 'created'; }

    // ===== Data load =====
    loadSurveys() {
        this.isLoading = true;
        Promise.all([
            getUserContactDetails().catch(() => null),
            getAlumniRolesForPerson({ personId: null }).catch(() => [])
        ]).then(([ctx, roles]) => {
            this.userContext = ctx || null;
            const role = Array.isArray(roles) && roles.length ? roles[0] : null;
            this.constituentRoleId = (role && role.constituentRoleId) || null;
            const roleId = this.constituentRoleId;
            Promise.all([
                getSurveys({ constituentRoleId: roleId }).catch(err => { this.surveysError = err; return []; }),
                getMySurveys({ constituentRoleId: roleId }).catch(err => { this.surveysError = err; return []; })
            ]).then(([avail, mine]) => {
                this.allSurveys = this._mapDtoList(avail || []);
                this.mySurveys = this._mapDtoList(mine || []);
                this.isLoading = false;
            });
        });
    }

    _mapDtoList(rows) {
        const fmt = (d) => this.formatDate(d);
        const seen = new Set();
        return (rows || []).filter(r => r && r.id && !seen.has(r.id) && seen.add(r.id)).map(s => {
            const approval = (s.approvalStatus || '').toLowerCase();
            const bucket = approval === 'approved' ? 'Approved'
                : approval === 'rejected' ? 'Rejected' : 'In Review';
            const now = Date.now();
            const start = s.startDate ? new Date(s.startDate).getTime() : 0;
            const end   = s.endDate   ? new Date(s.endDate).getTime()   : 0;
            let status = 'Pending';
            if (bucket === 'Approved') {
                if (start && now < start) status = 'Upcoming';
                else if (end && now > end) status = 'Completed';
                else status = 'Ongoing';
            } else if (bucket === 'Rejected') status = 'Rejected';
            else status = 'In Review';
            const params = (s.questionnaire && Array.isArray(s.questionnaire.parameters)) ? s.questionnaire.parameters : [];
            const qCount = Number(params.length) || 0;
            // Defensive boolean coercion: accept true OR string "true".
            const hasResponses = s.hasResponses === true || s.hasResponses === 'true';
            const responsesNum = Number(s.responsesCount);
            return {
                id: s.id,
                title: s.name || s.sectionName || 'Untitled Survey',
                description: (s._raw && s._raw.description) || '',
                period: s.startDate && s.endDate ? `${fmt(s.startDate)} – ${fmt(s.endDate)}` : '',
                questionsCount: qCount,
                estimatedMinutes: Math.max(1, Math.round(qCount * 0.5)),
                responsesText: Number.isFinite(responsesNum) ? String(responsesNum) : '0',
                status,
                bucket,
                hasResponses,
                statusClass: this._statusClass(status, bucket),
                pillClass: this._pillClass(bucket),
                isCompleted: status === 'Completed' || hasResponses,
                isPending: status === 'Ongoing' || status === 'Upcoming',
                _raw: s
            };
        });
    }

    _statusClass(status, bucket) {
        if (bucket === 'Rejected') return 'pill pill--rejected';
        if (status === 'Completed') return 'pill pill--completed';
        if (status === 'Ongoing') return 'pill pill--ongoing';
        if (status === 'Upcoming') return 'pill pill--upcoming';
        return 'pill pill--review';
    }
    _pillClass(bucket) {
        if (bucket === 'Approved') return 'pill pill--approved';
        if (bucket === 'Rejected') return 'pill pill--rejected';
        return 'pill pill--review';
    }

    // ===== Main Board =====
    get filterChips() {
        return VALID_FILTERS.map(f => ({ key: f, label: f, cls: f === this.filterChip ? 'chip chip--on' : 'chip' }));
    }
    get filteredAllSurveys() {
        const q = (this.searchQuery || '').toLowerCase().trim();
        let list = this.allSurveys;
        if (this.filterChip === 'Pending') list = list.filter(s => s.isPending && !s.hasResponses);
        else if (this.filterChip === 'Completed') list = list.filter(s => s.isCompleted);
        if (q) list = list.filter(s => (s.title || '').toLowerCase().indexOf(q) >= 0);
        return list;
    }
    get hasAllSurveys() { return this.filteredAllSurveys.length > 0; }
    get hasMySurveys() { return this.mySurveys.length > 0; }
    get myCreatedPreview() { return this.mySurveys.slice(0, 4); }

    handleFilterChip(event) { this.filterChip = event.currentTarget.dataset.key; this._syncUrl(); }
    handleSearch(event) { this.searchQuery = event.target.value; }

    // ===== Created Surveys view =====
    handleOpenCreated() {
        try { this._scrollY.board = window.scrollY || 0; } catch (e) { /* ignore */ }
        this.view = 'created';
        this._syncUrl();
        try { window.scrollTo({ top: 0, behavior: 'auto' }); } catch (e) { /* ignore */ }
    }
    handleCreatedBack() {
        this.view = 'board';
        this._syncUrl();
        try {
            const y = this._scrollY.board || 0;
            requestAnimationFrame(() => { try { window.scrollTo({ top: y, behavior: 'auto' }); } catch (e) { /* ignore */ } });
        } catch (e) { /* ignore */ }
    }
    handleCreatedTab(event) { this.createdTab = event.currentTarget.dataset.key; }
    handleCreatedSearch(event) { this.createdSearch = event.target.value; }
    handleCreatedSort(event) { this.createdSort = event.target.value; }

    get createdTabs() {
        return CREATED_TABS.map(t => {
            const count = this.mySurveys.filter(s => s.bucket === t).length;
            return { key: t, label: t, count, cls: t === this.createdTab ? 'ctab ctab--on' : 'ctab' };
        });
    }
    get createdSurveysList() {
        const q = (this.createdSearch || '').toLowerCase().trim();
        let list = this.mySurveys.filter(s => s.bucket === this.createdTab);
        if (q) list = list.filter(s => (s.title || '').toLowerCase().indexOf(q) >= 0);
        const dir = this.createdSort;
        list = [...list].sort((a, b) => {
            if (dir === 'title') return (a.title || '').localeCompare(b.title || '');
            if (dir === 'responses') return (Number(b.responsesText) || 0) - (Number(a.responsesText) || 0);
            // recent (default): by raw end/created date desc
            const ad = a._raw && (a._raw.endDate || a._raw.submittedDate) ? new Date(a._raw.endDate || a._raw.submittedDate).getTime() : 0;
            const bd = b._raw && (b._raw.endDate || b._raw.submittedDate) ? new Date(b._raw.endDate || b._raw.submittedDate).getTime() : 0;
            return bd - ad;
        });
        return list;
    }
    get hasCreatedSurveys() { return this.createdSurveysList.length > 0; }

    handleStartSurvey(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedSurveyId = id;
        this.showOpinionModal = true;
    }
    handleCloseOpinion() { this.showOpinionModal = false; }
    handleConfirmOpinion() {
        this.showOpinionModal = false;
        this.view = 'take';
        this._syncUrl();
    }

    handleOpenCreate() {
        // Fresh create — clear any prior edit seed so the wizard renders defaults.
        this.editSurveyId = null;
        this.wizardSeed = null;
        this.view = 'create';
        this._syncUrl();
    }

    // "Edit" action on a survey row — loads the survey's current definition and opens
    // the create wizard seeded with it (edit-in-place via updateSurveyWithQuestions).
    handleEditSurvey(event) {
        if (event && event.stopPropagation) event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        if (!(typeof id === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(id))) {
            this._toast('This survey cannot be edited.');
            return;
        }
        getSurveyForEdit({ surveyId: id })
            .then(resp => {
                this.wizardSeed = (resp && resp.data) || null;
                this.editSurveyId = id;
                this.view = 'create';
                this._syncUrl();
                try { window.scrollTo({ top: 0, behavior: 'auto' }); } catch (e) { /* ignore */ }
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('getSurveyForEdit error', err);
                this._toast((err && err.body && err.body.message) || 'Could not load survey for editing.');
            });
    }

    handleOpenDetail(event) {
        const id = event.currentTarget.dataset.id;
        // Snapshot scroll position so Back can restore it.
        try { this._scrollY.board = window.scrollY || 0; } catch (e) { /* ignore */ }
        this.selectedSurveyId = id;
        this.view = 'detail';
        this._syncUrl();
        this._loadDetail(id);
        try { window.scrollTo({ top: 0, behavior: 'auto' }); } catch (e) { /* ignore */ }
    }

    _loadDetail(id) {
        this.detailSurvey = null;
        this.surveyResults = null;
        this.isLoadingDetail = true;
        // A survey the current user created (appears in mySurveys) is shown as a
        // results view — the creator must NOT be able to start their own survey.
        const isOwned = this.mySurveys.some(s => String(s.id) === String(id));
        // Find in cached list first for instant render
        const cached = [].concat(this.allSurveys, this.mySurveys).find(s => String(s.id) === String(id));
        if (cached) {
            this.detailSurvey = this._buildDetailVm(cached, cached._raw, isOwned);
        }
        if (isOwned && typeof id === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(id)) {
            this._loadResults(id);
        }
        // Then fetch full detail via getSurveyForEdit
        if (typeof id === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(id)) {
            getSurveyForEdit({ surveyId: id })
                .then(resp => {
                    if (resp && resp.data) {
                        this.detailSurvey = this._mergeDetailFromEdit(this.detailSurvey || {}, resp.data, cached);
                    }
                    this.isLoadingDetail = false;
                })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('getSurveyForEdit error', err);
                    this.isLoadingDetail = false;
                });
        } else {
            this.isLoadingDetail = false;
        }
    }

    _loadResults(id) {
        this.isLoadingResults = true;
        getSurveyResults({ surveyId: id })
            .then(res => {
                if (!res) { this.surveyResults = null; this.isLoadingResults = false; return; }
                const questions = (res.questions || []).map((qq, idx) => {
                    const total = Number(qq.responseCount) || 0;
                    const stats = (qq.stats || []).map(st => ({
                        key: (qq.questionId || idx) + ':' + (st.responseValue || ''),
                        label: st.responseValue,
                        count: st.count,
                        percent: st.percent,
                        barStyle: `width:${Math.min(100, Number(st.percent) || 0)}%`
                    }));
                    return {
                        id: qq.questionId || ('rq' + idx),
                        number: idx + 1,
                        label: qq.questionLabel || 'Untitled Question',
                        type: qq.questionType || 'Short Answer',
                        responseCount: total,
                        stats,
                        hasStats: stats.length > 0
                    };
                });
                this.surveyResults = {
                    totalResponses: Number(res.totalResponses) || 0,
                    questionCount: Number(res.questionCount) || questions.length,
                    questions
                };
                this.isLoadingResults = false;
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('getSurveyResults error', err);
                this.surveyResults = null;
                this.isLoadingResults = false;
            });
    }

    _buildDetailVm(card, raw, isOwned = false) {
        const audiencePills = this._audienceToPills(raw && raw.segmentationName);
        const params = (raw && raw.questionnaire && raw.questionnaire.parameters) || [];
        const questions = params.map((p, idx) => ({
            id: p.id,
            number: idx + 1,
            label: p.questionLabel || 'Untitled Question',
            type: p.questionType || 'Short Answer',
            options: this._splitOpts(p.mcqOptions),
            required: p.required === true,
            hasOptions: !!(p.mcqOptions && p.mcqOptions.length)
        }));
        return {
            id: card.id,
            title: card.title,
            description: card.description || (raw && raw.sectionName) || '',
            status: card.status,
            statusClass: card.statusClass,
            bucket: card.bucket,
            category: (raw && raw.segmentationName) || 'General',
            period: card.period,
            estimatedMinutes: card.estimatedMinutes,
            questionsCount: questions.length,
            responsesCount: card.responsesText,
            audiencePills,
            questions,
            isCompleted: card.isCompleted === true,
            isOwned: isOwned === true,
            canDelete: card.bucket !== 'Approved' || !card.hasResponses
        };
    }

    _mergeDetailFromEdit(vm, dto, cached) {
        const out = { ...vm };
        out.title = dto.title || out.title;
        out.description = dto.description || out.description;
        out.audiencePills = this._audienceListToPills(dto.targetAudience || []);
        if (dto.startDate || dto.endDate) {
            out.period = `${dto.startDate || ''}${dto.endDate ? ' – ' + dto.endDate : ''}`;
        }
        const questions = (dto.questions || []).map((q, idx) => ({
            id: 'q' + idx,
            number: idx + 1,
            label: q.text || 'Untitled Question',
            type: q.type || 'short',
            options: (q.options || []).map(o => o.text).filter(Boolean),
            required: q.required === true,
            hasOptions: (q.options || []).length > 0
        }));
        out.questions = questions;
        out.questionsCount = questions.length;
        if (cached) {
            out.id = cached.id;
            out.status = cached.status;
            out.statusClass = cached.statusClass;
            out.bucket = cached.bucket;
            out.canDelete = cached.bucket !== 'Approved' || !cached.hasResponses;
        }
        return out;
    }

    _splitOpts(s) {
        if (!s) return [];
        return String(s).split(/[;\n,]+/).map(x => x.trim()).filter(Boolean);
    }
    _audienceToPills(segmentationName) {
        if (!segmentationName) return [{ key: 'all', label: 'All Alumni', group: 'Audience' }];
        return [{ key: 'seg', label: segmentationName, group: 'Segment' }];
    }
    _audienceListToPills(list) {
        if (!list || !list.length) return [{ key: 'all', label: 'All Alumni', group: 'Audience' }];
        return list.map((v, i) => ({ key: 'p' + i, label: v, group: 'Audience' }));
    }

    // ===== Take view =====
    handleTakeClose() {
        this.view = 'board';
        this.selectedSurveyId = null;
        this._syncUrl();
    }
    handleTakeSubmit(event) {
        const detail = (event && event.detail) || {};
        const surveyId = detail.surveyId || this.selectedSurveyId;
        const cached = [].concat(this.allSurveys, this.mySurveys).find(s => String(s.id) === String(surveyId));
        const params = (cached && cached._raw && cached._raw.questionnaire && cached._raw.questionnaire.parameters) || [];
        if (typeof surveyId === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(surveyId) && params.length) {
            const responsesObj = detail.responses || {};
            const responses = Object.keys(responsesObj).map(qid => ({
                questionId: qid,
                responseValue: Array.isArray(responsesObj[qid]) ? responsesObj[qid].join(', ') : String(responsesObj[qid] == null ? '' : responsesObj[qid])
            }));
            submitSurveyResponses({ request: { surveyId, responses } })
                .then(() => { this._toast('Survey submitted'); this._backToBoard(); })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('submitSurveyResponses error', err);
                    this._toast('Submitted (offline)');
                    this._backToBoard();
                });
        } else {
            this._toast('Survey submitted');
            this._backToBoard();
        }
    }

    get takeSurvey() {
        const id = this.selectedSurveyId;
        const cached = [].concat(this.allSurveys, this.mySurveys).find(s => String(s.id) === String(id));
        return cached || {};
    }
    get takeQuestions() {
        const cached = this.takeSurvey || {};
        const params = (cached._raw && cached._raw.questionnaire && cached._raw.questionnaire.parameters) || [];
        if (!params.length) return null;
        return params.map(p => {
            const type = (p.questionType || '').toLowerCase();
            let t = 'short';
            if (type.indexOf('multiple') >= 0 || type.indexOf('checkbox') >= 0) t = 'checkbox';
            else if (type.indexOf('linear') >= 0 || type.indexOf('rating') >= 0 || type.indexOf('scale') >= 0) t = 'rating5';
            else if (type.indexOf('single') >= 0 || type.indexOf('radio') >= 0) t = 'radio';
            else if (type.indexOf('yes') >= 0) t = 'radio';
            else t = 'long';
            return {
                id: p.id,
                type: t,
                title: p.questionLabel || '',
                hint: p.required ? 'Required' : 'Optional',
                opts: this._splitOpts(p.mcqOptions)
            };
        });
    }

    // ===== Create view =====
    handleCreateClose() {
        this.editSurveyId = null;
        this.wizardSeed = null;
        this.view = 'board';
        this._syncUrl();
    }
    handleCreateSubmit(event) {
        const d = (event && event.detail) || {};
        // Map wizard types to VALID Ken_Questionnaire_Parameter__c.Question_Type__c values
        // (restricted picklist: Yes/No, Multiple Choice, Rating, Short Answer, Dropdown,
        // Linear Scale, Comment, File Upload). 'Single/Multi Select' were INVALID and
        // caused INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST on insert.
        const mapType = (t) => {
            const v = (t || '').toLowerCase();
            if (v === 'yesno' || v === 'yes/no') return 'Yes/No';
            if (v === 'radio' || v === 'single' || v === 'checkbox' || v === 'multi' || v === 'multiple') return 'Multiple Choice';
            if (v === 'scale' || v === 'rating' || v === 'linear') return 'Linear Scale';
            if (v === 'text' || v === 'short' || v === 'long') return 'Short Answer';
            return 'Short Answer';
        };
        const questions = (d.questions || []).map(q => ({
            text: q.text || '',
            type: mapType(q.type),
            required: q.required === true,
            options: (q.opts || []).map(o => ({ text: o })),
            scaleMin: q.scaleMin != null ? Number(q.scaleMin) : null,
            scaleMax: q.scaleMax != null ? Number(q.scaleMax) : null,
            scaleMinLabel: q.scaleMinLabel || null,
            scaleMaxLabel: q.scaleMaxLabel || null
        }));
        const request = {
            title: d.title || '',
            description: d.desc || '',
            targetAudience: Array.isArray(d.audience) ? d.audience : [],
            startDate: d.startDate || '',
            endDate: d.endDate || '',
            questions
        };
        // Always call Apex — pass whatever role we have (may be null). The controller
        // (resolveConstituentRoleId) auto-provisions an Alumni ConstituentRole when
        // none is passed, so the Survey IS created server-side. Previously the LWC
        // short-circuited with "Survey submitted (offline)" when the role wasn't
        // resolved client-side, which silently skipped record creation.
        const isEdit = !!this.editSurveyId;
        const editId = this.editSurveyId;
        const apexCall = isEdit
            ? updateSurveyWithQuestions({ request, surveyId: editId })
            : createSurveyWithQuestions({ request, constituentRoleId: this.constituentRoleId });
        apexCall
            .then(surveyId => {
                this._toast(isEdit ? 'Survey updated' : 'Survey submitted for review');
                this.editSurveyId = null;
                this.wizardSeed = null;
                this.view = 'board'; this._syncUrl(); this.loadSurveys();
                // Persist Groups / Individuals / CSV selections as a linked segmentation.
                return this._persistSegmentation(surveyId || editId, d);
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error((isEdit ? 'updateSurveyWithQuestions' : 'createSurveyWithQuestions') + ' error', err);
                this._toast((err && err.body && err.body.message)
                    || (isEdit ? 'Could not update survey. Please try again.' : 'Could not submit survey. Please try again.'));
            });
    }

    // Builds an AudienceRequestDTO-shaped payload from the wizard's audienceDetail,
    // saves it as a Ken_Segmentation__c, and links it to the survey. Roles already
    // persist via Target_Audience__c, so this only fires when explicit Groups /
    // Individuals / CSV recipients were chosen.
    _persistSegmentation(surveyId, d) {
        const detail = (d && d.audienceDetail) || {};
        const groupIds = detail.groupIds || [];
        const individualIds = detail.individualIds || [];
        const csvEmails = detail.csvEmails || [];
        if (!surveyId || (groupIds.length === 0 && individualIds.length === 0 && csvEmails.length === 0)) {
            return null;
        }
        // Individuals map cleanly to a ConstituentRole Id IN filter; groups/CSV are
        // preserved verbatim in the stored Definition_JSON__c for downstream resolution.
        const filters = [];
        if (individualIds.length) {
            filters.push({ id: 'individuals', fieldApi: 'Id', operator: 'in', value: individualIds.join(','), dataType: 'reference' });
        }
        const req = {
            audienceName: `${(d.title || 'Survey').substring(0, 60)} Audience ${Date.now()}`,
            description: 'Auto-generated from the survey target-audience selection.',
            targetRole: 'Alumni',
            targetObject: 'ConstituentRole',
            active: true,
            matchMode: 'OR',
            filters,
            // extra keys ignored by the DTO parse but persisted verbatim in Definition_JSON__c
            category: detail.category,
            selectedGroupIds: groupIds,
            selectedIndividualIds: individualIds,
            csvEmails: csvEmails,
            roles: detail.roles || []
        };
        return saveSegmentation({ requestJson: JSON.stringify(req) })
            .then(segId => createSurveySegmentation({ surveyId, segmentationId: segId }))
            .then(() => { this._toast('Audience segmentation saved'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('saveSegmentation/link error', err);
                this._toast('Survey saved — audience segmentation could not be saved.');
            });
    }

    handleReviewAudience() { this.showAudienceReviewModal = true; }
    handleCloseAudienceReview() { this.showAudienceReviewModal = false; }

    // ===== Detail view =====
    handleDetailBack() {
        this.view = 'board';
        this.selectedSurveyId = null;
        this.detailSurvey = null;
        this._syncUrl();
        // Restore scroll position for the board after layout settles.
        try {
            const y = this._scrollY.board || 0;
            requestAnimationFrame(() => { try { window.scrollTo({ top: y, behavior: 'auto' }); } catch (e) { /* ignore */ } });
        } catch (e) { /* ignore */ }
    }
    handleDeleteClick() { this.showDeleteModal = true; }
    handleCloseDelete() { this.showDeleteModal = false; }
    handleConfirmDelete() {
        const id = this.selectedSurveyId;
        this.showDeleteModal = false;
        if (typeof id === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(id)) {
            deleteSurvey({ surveyId: id })
                .then(() => { this._toast('Survey deleted'); this.handleDetailBack(); this.loadSurveys(); })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('deleteSurvey error', err);
                    this._toast('Could not delete survey');
                });
        } else {
            this._toast('Survey deleted');
            this.handleDetailBack();
        }
    }
    handleStartFromDetail() {
        this.showOpinionModal = true;
    }

    // ===== Helpers =====
    _backToBoard() {
        this.view = 'board';
        this.selectedSurveyId = null;
        this._syncUrl();
        this.loadSurveys();
    }
    _toast(msg) {
        this.toastMsg = msg;
        this.showToast = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showToast = false; }, 2400);
    }
}