import { LightningElement, api, track } from 'lwc';
import getOpportunitiesPage from '@salesforce/apex/KenGivingV2Controller.getOpportunitiesPage';
import getOpportunityDetail from '@salesforce/apex/KenGivingV2Controller.getOpportunityDetail';
import getMyGiving from '@salesforce/apex/KenGivingV2Controller.getMyGiving';
import getImpactUpdates from '@salesforce/apex/KenGivingV2Controller.getImpactUpdates';
import submitInitiative from '@salesforce/apex/KenGivingV2Controller.submitInitiative';
import submitContribution from '@salesforce/apex/KenGivingV2Controller.submitContribution';

// Mock arrays removed — Giving page renders empty state until Apex returns real data.

const TYPE_META = {
    'donation':   { label: 'Donations',     icon: '♡', single: 'Donation' },
    'pledge':     { label: 'Pledges',       icon: '🗓', single: 'Pledge' },
    'in-kind':    { label: 'In-kind',       icon: '🎁', single: 'In-kind' },
    'csr':        { label: 'CSR referrals', icon: '🏢', single: 'CSR referral' },
    'initiative': { label: 'Initiatives',   icon: '✦', single: 'Initiative' }
};

const STATUS_TONES = {
    'Completed':            'st--ok',
    'Receipt available':    'st--ok',
    'Acknowledged':         'st--ok',
    'Live':                 'st--ok',
    'Pledged':              'st--info',
    'Pending payment':      'st--warn',
    'Under review':         'st--warn',
    'Submitted for Review': 'st--warn',
    'Closed':               'st--muted'
};

const INITIATIVE_STEPS = [
    { number: 1, title: 'Share the idea', body: 'Goal, beneficiaries, why it matters.' },
    { number: 2, title: 'Institution review', body: 'A reviewer checks fit, feasibility, and compliance.' },
    { number: 3, title: 'Go live', body: 'Approved initiatives are visible to all alumni for contribution.' }
];

const CAT_KEY = {
    'Scholarships':       'cat-Scholarships',
    'Infrastructure':     'cat-Infrastructure',
    'Campus Development': 'cat-CampusDevelopment',
    'Batch Fund':         'cat-BatchFund',
    'Student Support':    'cat-StudentSupport'
};

const CATEGORY_FILTERS = ['All', 'Scholarships', 'Infrastructure', 'Campus Development', 'Batch Fund', 'Student Support'];

function formatINR(raw) {
    // Coerce defensively — backend can return string "12345" or null.
    const n = Number(raw);
    if (!Number.isFinite(n)) return '';
    if (n >= 10000000) return '₹' + (n / 10000000).toFixed(n % 10000000 === 0 ? 0 : 2) + ' Cr';
    if (n >= 100000)   return '₹' + (n / 100000).toFixed(n % 100000 === 0 ? 0 : 2) + ' L';
    if (n >= 1000)     return '₹' + (n / 1000).toFixed(n % 1000 === 0 ? 0 : 1) + 'K';
    return '₹' + n;
}

// Only allow http(s) or root-relative URLs.
const SAFE_URL_RE_G = /^(https?:|\/)/i;
function safeImgUrl(u) {
    if (!u || typeof u !== 'string') return '';
    return SAFE_URL_RE_G.test(u.trim()) ? u : '';
}

function decorate(o) {
    if (!o) return null;
    const raised = Number(o.raised) || 0;
    const target = Number(o.target) || 0;
    const daysLeftNum = (o.daysLeft == null || o.daysLeft === '') ? null : Number(o.daysLeft);
    const ongoing = (o.ongoing === true || o.ongoing === 'true');
    const pct = target ? Math.min(100, Math.round((raised / target) * 100)) : 0;
    const catKey = CAT_KEY[o.category] || '';
    const safeImg = safeImgUrl(o.image);
    const useGradient = !safeImg;
    return {
        ...o,
        raised,
        target,
        daysLeft: daysLeftNum,
        ongoing,
        raisedFormatted: formatINR(raised),
        targetText: target ? `of ${formatINR(target)} goal` : 'Ongoing fund',
        ctxText: ongoing ? 'Ongoing fund' : (daysLeftNum != null ? `${daysLeftNum} days left` : ''),
        daysText: ongoing ? 'Ongoing' : `${daysLeftNum || 0} days left`,
        hasProgress: pct > 0,
        pctValue: pct,
        imgStyle: useGradient ? '' : `background-image:url('${safeImg}')`,
        catKey: catKey,
        useGradient: useGradient,
        allocation: (o.allocation || []),
        updates: o.updates || [],
        hasUpdates: (o.updates || []).length > 0
    };
}

export default class Ken42AlumniGivingV2 extends LightningElement {
    @api defaultTab = 'opportunities';
    @api userFirstName = '';

    @track activeTab = 'dashboard';
    @track activeCategory = 'All';
    @track searchTerm = ''; // QA Bug #129 — free-text search across opportunities
    @track modalState = null;
    @track detailId = null;
    @track isLoading = true;

    // Scroll position snapshot for back from detail/give/initiative modals.
    _scrollY = { board: 0 };

    // Shared date formatter (15 Jul 2026 style).
    formatDate(iso, withTime = false) {
        if (!iso) return '';
        const d = new Date(iso);
        if (isNaN(d.getTime())) return '';
        const opts = { day: '2-digit', month: 'short', year: 'numeric' };
        if (withTime) { opts.hour = '2-digit'; opts.minute = '2-digit'; opts.hour12 = true; }
        try { return d.toLocaleDateString('en-IN', opts); } catch (e) { return ''; }
    }

    @track opportunitiesData = [];
    @track contributorsData = [];
    @track topBatchesData = [];
    @track corporateSupportersData = [];
    @track myGivingData = [];
    @track impactUpdatesData = [];
    @track detailRecord = null;

    connectedCallback() {
        if (this.defaultTab) this.activeTab = this.defaultTab;
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const view = params.get('view');
            const id = params.get('id');
            const VALID_TABS = ['dashboard', 'opportunities', 'my-giving', 'start-initiative', 'impact-updates'];
            const VALID_VIEWS = ['details', 'give', 'initiative', 'campaign'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.activeTab = tab;
            if (view && VALID_VIEWS.indexOf(view) > -1) this.modalState = view;
            if (id) this.detailId = id;
        } catch (e) { /* ignore */ }
        this._loadAll();
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeTab) params.set('tab', this.activeTab); else params.delete('tab');
            if (this.modalState) params.set('view', this.modalState); else params.delete('view');
            if (this.detailId) params.set('id', String(this.detailId)); else params.delete('id');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    async _loadAll() {
        this.isLoading = true;
        try {
            const [page, mine, impacts] = await Promise.all([
                getOpportunitiesPage(),
                getMyGiving().catch(() => []),
                getImpactUpdates().catch(() => [])
            ]);
            this.opportunitiesData = (page && page.opportunities) || [];
            this.contributorsData = (page && page.contributors) || [];
            this.topBatchesData = (page && page.topBatches) || [];
            this.corporateSupportersData = (page && page.corporateSupporters) || [];
            this.myGivingData = (mine || []).map(m => ({ ...m, date: m.dateLabel || m.date }));
            this.impactUpdatesData = (impacts || []).map(u => ({ ...u, date: u.dateLabel || u.date }));
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Giving load error', e);
            this.opportunitiesData = [];
            this.contributorsData = [];
            this.topBatchesData = [];
            this.corporateSupportersData = [];
            this.myGivingData = [];
            this.impactUpdatesData = [];
        }
        this.isLoading = false;
    }

    get isDashboard() { return this.activeTab === 'dashboard'; }
    get isOpportunities() { return this.activeTab === 'opportunities'; }
    get isMyGiving() { return this.activeTab === 'my-giving'; }
    get isStartInitiative() { return this.activeTab === 'start-initiative'; }
    get isImpact() { return this.activeTab === 'impact-updates'; }

    get filteredOpps() {
        let list = this.activeCategory === 'All'
            ? this.opportunitiesData
            : this.opportunitiesData.filter(o => o.category === this.activeCategory);
        // QA Bug #129 — apply free-text search across title / cause / department / story.
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (term) {
            list = list.filter(o => {
                const hay = [o.title, o.category, o.cause, o.department, o.story, o.description]
                    .map(x => (x == null ? '' : String(x)).toLowerCase()).join(' ');
                return hay.indexOf(term) > -1;
            });
        }
        return list.map(decorate);
    }
    handleOppsSearch(event) {
        this.searchTerm = (event && event.target && event.target.value) || '';
    }
    get featuredOpp() {
        const list = this.filteredOpps;
        return list[0] || null;
    }
    get hasFeatured() { return !!this.featuredOpp; }
    get nonFeaturedOpps() { return this.filteredOpps.slice(1); }
    get hasMore() { return this.nonFeaturedOpps.length > 0; }
    get topBatches() {
        return this.topBatchesData.map((b, i) => ({ ...b, rank: i + 1 }));
    }
    get contributors() {
        return (this.contributorsData || []).filter(Boolean).map(c => {
            // Defensive boolean — accept true OR 'true'.
            const anon = (c.anon === true || c.anon === 'true' || c.isAnonymous === true || c.isAnonymous === 'true');
            const hideAmount = (c.hideAmount === true || c.hideAmount === 'true');
            const batch = c.batch || '';
            const campaign = c.campaign || '';
            const metaParts = [batch, campaign].filter(Boolean);
            return {
                ...c,
                anon,
                hideAmount,
                avatarChar: anon ? '👁' : ((c.name || '?').charAt(0)),
                avatarCls: anon ? 'rc-avatar rc-avatar--anon' : 'rc-avatar',
                hasAmount: !hideAmount,
                metaLine: metaParts.length ? metaParts.join(' · ') : '—'
            };
        });
    }
    get corporateSupporters() { return this.corporateSupportersData; }
    get anonymousCount() { return 47; }
    get anonText() { return `👁 ${this.anonymousCount} private not shown`; }

    get myGivingEntries() {
        return this.myGivingData.map(g => {
            const meta = TYPE_META[g.type] || { label: g.type, icon: '·', single: g.type };
            const tone = STATUS_TONES[g.status] || 'st--muted';
            return {
                ...g,
                typeLabel: meta.single,
                typeIcon: meta.icon,
                statusCls: `mg-status ${tone}`,
                showComplete: g.status === 'Pledged',
                showReceipt: !!g.receipt,
                showUpdates: !!g.updatesAvailable
            };
        });
    }
    get myGivingTotals() {
        const data = this.myGivingData;
        const count = (t) => data.filter(g => g.type === t).length;
        return [
            { key: 'donation',   label: 'Donations',     value: count('donation'),   icon: '♡', tone: 'sc--violet' },
            { key: 'pledge',     label: 'Pledges',       value: count('pledge'),     icon: '🗓', tone: 'sc--sky' },
            { key: 'in-kind',    label: 'In-kind',       value: count('in-kind'),    icon: '🎁', tone: 'sc--emerald' },
            { key: 'csr',        label: 'CSR referrals', value: count('csr'),        icon: '🏢', tone: 'sc--amber' },
            { key: 'initiative', label: 'Initiatives',   value: count('initiative'), icon: '✦', tone: 'sc--rose' }
        ];
    }
    get visibilityOptions() {
        return [
            { key: 'Public name',  label: 'Public name',  cls: 'vis-opt' },
            { key: 'Name + batch', label: 'Name + batch', cls: 'vis-opt vis-opt--active' },
            { key: 'Anonymous',    label: 'Anonymous',    cls: 'vis-opt' }
        ];
    }

    get initiativeSteps() { return INITIATIVE_STEPS; }
    get myInitiatives() {
        return this.myGivingData.filter(g => g.type === 'initiative').map(g => ({
            ...g,
            statusCls: `mg-status ${STATUS_TONES[g.status] || 'st--muted'}`
        }));
    }
    get hasInitiatives() { return this.myGivingData.some(g => g.type === 'initiative'); }
    get hasNoInitiatives() { return !this.hasInitiatives; }

    get impactUpdates() {
        return (this.impactUpdatesData || []).filter(Boolean).map(u => {
            const safe = safeImgUrl(u.image);
            const dateLabel = u.dateLabel || this.formatDate(u.date || u.createdDate) || u.date || '';
            return {
                ...u,
                dateLabel,
                hasImage: !!safe,
                hasMetric: !!u.metric,
                imgStyle: safe ? `background-image:url('${safe}')` : ''
            };
        });
    }
    get hasImpactUpdates() { return this.impactUpdates.length > 0; }
    get hasContributors() { return (this.contributorsData || []).length > 0; }
    get hasTopBatches() { return (this.topBatchesData || []).length > 0; }
    get hasOpportunities() { return this.filteredOpps.length > 0; }
    get showOpportunitiesEmpty() { return !this.isLoading && !this.hasOpportunities; }

    get categoryFilters() {
        return CATEGORY_FILTERS.map(c => ({
            label: c,
            key: c,
            cls: c === this.activeCategory ? 'g-fpill g-fpill--active' : 'g-fpill'
        }));
    }

    get showDetailsModal() { return this.modalState === 'details'; }
    get showGiveModal() { return this.modalState === 'give'; }
    get showInitiativeModal() { return this.modalState === 'initiative'; }
    get showCampaignModal() { return this.modalState === 'campaign'; }
    get detailView() {
        if (!this.detailId) return null;
        if (this.detailRecord && (this.detailRecord.id === this.detailId)) return decorate(this.detailRecord);
        const rec = this.opportunitiesData.find(o => o.id === this.detailId);
        return rec ? decorate(rec) : null;
    }

    handleTabChange(event) { this.activeTab = event.detail.key; this.syncUrl(); }
    handleCatClick(event) { this.activeCategory = event.currentTarget.dataset.cat; }
    // "Create a campaign" now opens the staging-pattern campaign wizard (Ken_Gift_Campaign_Request__c
    // → admin materializes a real Campaign), which was previously built but never wired into the UI.
    handleNewInitiative() { this.modalState = 'campaign'; this.syncUrl(); }
    handleExplore() { this.activeTab = 'opportunities'; this.syncUrl(); }
    handleStartInitiative() { this.modalState = 'campaign'; this.syncUrl(); }
    handleCsrConnect() { /* placeholder */ }

    handleDetails(event) {
        try { this._scrollY.board = window.scrollY || 0; } catch (e) { /* ignore */ }
        this.detailId = event.detail.id;
        this.modalState = 'details';
        this.syncUrl();
        this._loadDetail(this.detailId);
    }
    handleGive(event) {
        if (event && event.detail && event.detail.id) {
            this.detailId = event.detail.id;
            this._loadDetail(this.detailId);
        }
        this.modalState = 'give';
        this.syncUrl();
    }

    async _loadDetail(id) {
        // id may be an external key from card; pull SF Id by matching opportunitiesData
        const rec = this.opportunitiesData.find(o => o.id === id);
        if (!rec) return;
        try {
            // detailId from server expects an Id. We don't have it directly in the card DTO,
            // but the controller accepts the SF Id. If `rec` carries it, use it; otherwise skip.
            const sfId = rec.sfId || rec.recordId || null;
            if (!sfId) return;
            const detail = await getOpportunityDetail({ opportunityId: sfId });
            if (detail && detail.opportunity) this.detailRecord = detail.opportunity;
        } catch (e) {
            // silent
        }
    }

    stopPropagation(event) { event.stopPropagation(); }

    handleClose() {
        this.modalState = null;
        this.detailId = null;
        this.detailRecord = null;
        this.syncUrl();
        try {
            const y = this._scrollY.board || 0;
            requestAnimationFrame(() => { try { window.scrollTo({ top: y, behavior: 'auto' }); } catch (e) { /* ignore */ } });
        } catch (e) { /* ignore */ }
    }

    async handleGiveSubmit(event) {
        const payload = (event && event.detail && event.detail.payload) || {};
        if (!payload.opportunityId && this.detailId) payload.opportunityId = this.detailId;
        try {
            await submitContribution({ payload });
            this._loadAll();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('submitContribution failed', e);
        }
        this.handleClose();
    }

    async handleNewInitiativeSubmit(event) {
        const payload = (event && event.detail && event.detail.payload) || (event && event.detail) || {};
        try {
            await submitInitiative({ payload });
            this._loadAll();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('submitInitiative failed', e);
        }
        this.handleClose();
    }

    handleInitiativeSubmit(event) { this.handleNewInitiativeSubmit(event); }

    // ---- New single-form initiative modal (kenGivingInitiativeModalV2) ----
    // Toggle to render the legacy multi-step wizard in place of the new modal (kept for
    // emergencies; defaults to false so the new design is live).
    legacyWizardEnabled = false;
    handleInitiativeSubmitted(event) {
        // The new modal already inserted Ken_Gift_Campaign_Request__c server-side and
        // dispatched close right after. Surface a confirmation toast for the alum.
        const d = (event && event.detail) || {};
        // eslint-disable-next-line no-console
        console.info('Initiative submitted', d.requestId, 'alreadyExisted=', d.alreadyExisted);
    }
}