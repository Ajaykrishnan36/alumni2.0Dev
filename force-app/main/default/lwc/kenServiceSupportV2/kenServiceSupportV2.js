import { LightningElement, track } from 'lwc';
/* ------------------------------------------------------------------ *
 *  PORT of the reference "Product-Kenverse-Service-Support-2.0" logic
 *  into the portal's single kenServiceSupportV2 LWC. All Apex calls,
 *  payloads, data shapes, search scoring, file-to-base64 and the
 *  ConstituentRoleId-from-localStorage pattern are reused verbatim
 *  from KenServiceSupportController. UI is rebuilt to the Figma.
 * ------------------------------------------------------------------ */
import getFAQs from '@salesforce/apex/KenServiceSupportController.getFAQs';
import getUserHistory from '@salesforce/apex/KenServiceSupportController.getUserHistory';
import getCurrentUserFullName from '@salesforce/apex/KenServiceSupportController.getCurrentUserFullName';
import getServiceOfferings from '@salesforce/apex/KenServiceSupportController.getServiceOfferings';
import createNeedHelpCase from '@salesforce/apex/KenServiceSupportController.createNeedHelpCase';
import getCaseDetail from '@salesforce/apex/KenServiceSupportController.getCaseDetail';
import closeCase from '@salesforce/apex/KenServiceSupportController.closeCase';
import submitCaseFeedback from '@salesforce/apex/KenServiceSupportController.submitCaseFeedback';

// Distinct icon (stroke-path set) + accent colour per category. Path-only SVGs so
// they render inline (no lightning-icon base component → no LWR Shadow-DOM bleed).
const ICON_MAP = {
    'Academic Administration':            { color: '#3B5BFF', paths: ['M22 10L12 5 2 10l10 5 10-5z', 'M6 12v5c0 1.2 2.7 3 6 3s6-1.8 6-3v-5'] },
    'Examination & Evaluation Cell':      { color: '#7A5AF8', paths: ['M9 4H7a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2h-2', 'M9 4a1.5 1.5 0 0 1 1.5-1.5h3A1.5 1.5 0 0 1 15 4v.5H9V4z', 'M9 13l2 2 4-4'] },
    'Infrastructure & Facilities':        { color: '#0D9488', paths: ['M3 21h18', 'M5 21V8l7-4v17', 'M19 21V11l-7-3', 'M9 12h0M9 16h0'] },
    'Fees, Scholarships & Financial Aid': { color: '#E0A107', paths: ['M12 2v20', 'M17 6H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6'] },
    'IT Helpdesk':                        { color: '#2563EB', paths: ['M3 4h18v12H3z', 'M8 20h8', 'M12 16v4'] },
    'HR & Payroll':                       { color: '#DB2777', paths: ['M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2', 'M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8', 'M22 21v-2a4 4 0 0 0-3-3.87', 'M16 3.13a4 4 0 0 1 0 7.75'] },
    'Safety, Security & Wellbeing':       { color: '#DC2626', paths: ['M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z', 'M9 12l2 2 4-4'] },
    'Career Services':                    { color: '#0EA5E9', paths: ['M20 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2z', 'M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16', 'M2 13h20'] }
};
const ICON_DEFAULT = { color: '#3B5BFF', paths: ['M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z'] };

export default class KenServiceSupportV2 extends LightningElement {
    @track view = 'dashboard';      // dashboard | catalog | form | detail
    @track activeTab = 'service';   // service | support
    @track isLoading = true;
    userName = '';
    roleId = null;

    @track searchQuery = '';
    @track faqData = [];             // FAQCategoryWrapper[]
    @track expandedFaqId = null;     // open question (answer visible)
    @track expandedCategory = null;  // open category (questions visible)

    @track serviceHistoryData = [];  // HistoryItem[]
    @track supportHistoryData = [];

    @track serviceOfferingsData = []; // mapped offerings
    @track catalog = [];              // categories grouped from offerings
    @track selectedCategory = null;
    @track selectedOffering = null;
    @track formRequirement = '';
    @track formFileName = '';
    formFile = null;
    @track formError = '';
    @track submitting = false;
    MAX_BYTES = 5 * 1024 * 1024;

    @track detail = null;
    @track detailLoading = false;

    @track showSuccessModal = false;
    @track showErrorModal = false;
    @track errorText = '';
    @track successTitle = 'Request Raised';
    @track successSub = 'Your request was raised successfully';
    @track showCancelConfirm = false;
    cancelTargetId = null;

    @track showFeedbackModal = false;
    @track feedbackRating = 0;
    @track feedbackComment = '';
    feedbackTargetId = null;

    /* ===================== lifecycle ===================== */
    connectedCallback() {
        this.roleId = (() => { try { return window.localStorage.getItem('ConstituentRoleId'); } catch (e) { return null; } })();
        this.loadData();
        getCurrentUserFullName()
            .then(name => { this.userName = name || ''; })
            .catch(() => {})
            .finally(() => { this.isLoading = false; });
    }

    loadData() {
        getFAQs()
            .then(res => {
                this.faqData = res || [];
                // First category expanded by default (matches Figma).
                this.expandedCategory = (this.faqData.length) ? 'cat-0' : null;
            })
            .catch(() => { this.faqData = []; });

        getUserHistory({ constituentRoleId: this.roleId })
            .then(res => {
                this.serviceHistoryData = (res && res.serviceHistory) || [];
                this.supportHistoryData = (res && res.supportHistory) || [];
            })
            .catch(() => { this.serviceHistoryData = []; this.supportHistoryData = []; });

        getServiceOfferings({ constituentRoleId: this.roleId })
            .then(services => {
                this.serviceOfferingsData = (services || []).map(s => ({
                    id: s.Id,
                    serviceId: s.Service__c || s.Id,
                    title: s.Service__r ? s.Service__r.Name : s.Name,
                    description: s.Service__r ? s.Service__r.Description__c : '',
                    name: s.Name
                }));
                this._buildCatalog();
            })
            .catch(() => { this.serviceOfferingsData = []; this.catalog = []; });
    }

    // Group offerings by their parent Service → category cards with sub-categories.
    _buildCatalog() {
        const byService = new Map();
        this.serviceOfferingsData.forEach(o => {
            if (!byService.has(o.serviceId)) {
                byService.set(o.serviceId, { id: o.serviceId, name: o.title || o.name, description: o.description || '', offerings: [] });
            }
            byService.get(o.serviceId).offerings.push({ id: o.id, name: o.name, description: o.description });
        });
        this.catalog = Array.from(byService.values());
    }

    /* ===================== view flags ===================== */
    get isDashboard() { return this.view === 'dashboard'; }
    get isCatalog() { return this.view === 'catalog'; }
    get isForm() { return this.view === 'form'; }
    get isDetail() { return this.view === 'detail'; }
    get greeting() { return `Hi, ${this.userName || 'there'}! What Can We Help You With?`; }

    /* ===================== FAQ ===================== */
    get faqGroups() {
        return (this.faqData || []).map((cat, ci) => {
            const key = 'cat-' + ci;
            const catOpen = (this.expandedCategory === '__all__') || (key === this.expandedCategory);
            return {
                key,
                category: cat.category,
                catOpen,
                sectionClass: 'slds-accordion__section faq-section' + (catOpen ? ' slds-is-open' : ''),
                catIconClass: catOpen ? 'faq-cat__chevron faq-cat__chevron--open' : 'faq-cat__chevron',
                questions: (cat.questions || []).map(q => {
                    const id = 'faq-' + q.id;
                    const open = id === this.expandedFaqId;
                    return {
                        id, q: q.question, a: this.stripHtml(q.answer), expanded: open,
                        iconClass: open ? 'faq-q__icon faq-q__icon--open' : 'faq-q__icon'
                    };
                })
            };
        });
    }
    toggleCategory(e) {
        const key = e.currentTarget.dataset.key;
        this.expandedCategory = (this.expandedCategory === key) ? null : key;
    }
    handleFaqViewMore() {
        // Expand all categories (reveals every FAQ); a no-data-loss "see more" affordance.
        this.expandedCategory = '__all__';
    }
    handleViewAllTickets() {
        // Placeholder for a future full ticket-history route; keeps Figma layout parity.
    }
    get noFaqs() { return !this.faqData || this.faqData.length === 0; }
    toggleFaq(e) { const id = e.currentTarget.dataset.id; this.expandedFaqId = (this.expandedFaqId === id) ? null : id; }

    /* ===================== history list ===================== */
    _decorate(item) {
        const st = (item.status || '').toLowerCase();
        let pillClass = 'pill pill--blue';
        if (st.includes('review') || st.includes('progress') || st.includes('new') || st.includes('open')) pillClass = 'pill pill--amber';
        else if (st.includes('reject')) pillClass = 'pill pill--red';
        else if (st.includes('closed') || st.includes('cancel') || st.includes('resolved') || st.includes('solved')) pillClass = 'pill pill--grey';
        const closed = item.closedDate || item.canceledDate || item.rejectedDate;
        return {
            ...item,
            rowId: item.caseId || item.Id,
            pillClass,
            statusLabel: item.status || 'Open',
            titleLine: item.serviceOfferingName || item.title || item.subject || '—',
            subLine: item.subject || item.title || '',
            closedDateStr: this.fmtDate(closed),
            showClosedDate: !!closed,
            canFeedback: st.includes('closed') && !item.hasFeedbackSubmitted
        };
    }
    get serviceRequests() { return (this.serviceHistoryData || []).map(i => this._decorate(i)); }
    get supportTickets() { return (this.supportHistoryData || []).map(i => this._decorate(i)); }
    get serviceTabClass() { return 'tab' + (this.activeTab === 'service' ? ' tab--active' : ''); }
    get supportTabClass() { return 'tab' + (this.activeTab === 'support' ? ' tab--active' : ''); }
    get activeRows() { return this.activeTab === 'service' ? this.serviceRequests : this.supportTickets; }
    get hasRows() { return this.activeRows && this.activeRows.length > 0; }
    selectServiceTab() { this.activeTab = 'service'; }
    selectSupportTab() { this.activeTab = 'support'; }

    /* ===================== catalog cards ===================== */
    get catalogCards() {
        return this.catalog.map(c => {
            const meta = ICON_MAP[c.name] || ICON_DEFAULT;
            const count = c.offerings.length;
            return {
                ...c,
                iconStyle: `background:${meta.color}1A;color:${meta.color};`,
                iconPaths: meta.paths.map((d, i) => ({ key: c.id + '-p' + i, d })),
                countLabel: count + (count === 1 ? ' service' : ' services')
            };
        });
    }
    get catalogEmpty() { return this.isCatalog && this.catalog.length === 0; }

    /* ===================== search (ported scoring) ===================== */
    handleSearchInput(e) { this.searchQuery = e.target.value; }
    clearSearch() { this.searchQuery = ''; }
    get hasSearchQuery() { return this.searchQuery && this.searchQuery.trim().length > 0; }
    get searchActive() { return this.hasSearchQuery; }
    get noSearchResults() { return this.searchActive && this.searchResults.length === 0; }

    get searchResults() {
        if (!this.hasSearchQuery) return [];
        const query = this.normalize(this.searchQuery);
        const terms = query.split(' ').filter(Boolean);
        const out = [];
        (this.faqData || []).forEach(cat => (cat.questions || []).forEach(q => {
            const score = this.score(query, terms, [q.question, q.answer, cat.category]);
            if (score > 0) out.push({ key: 'faq-' + q.id, type: 'FAQ', typeClass: 'rpill rpill--faq', title: q.question, sub: this.stripHtml(q.answer), recordId: null, score });
        }));
        (this.serviceOfferingsData || []).forEach(s => {
            const score = this.score(query, terms, [s.title, s.description, s.name]);
            if (score > 0) out.push({ key: 'svc-' + s.id, type: 'Service', typeClass: 'rpill rpill--service', title: s.name || s.title, sub: s.title || '', recordId: null, score });
        });
        (this.supportHistoryData || []).forEach(t => {
            const cid = t.caseId || t.Id;
            const score = this.score(query, terms, [t.id, cid, t.title, t.subject, t.description, t.status]);
            if (score > 0) out.push({ key: 'sup-' + (cid || t.id), type: 'Support Ticket', typeClass: 'rpill rpill--tik', title: t.id || ('#' + cid), sub: t.title || t.subject || '', recordId: cid, score });
        });
        (this.serviceHistoryData || []).forEach(r => {
            const cid = r.caseId || r.Id;
            const score = this.score(query, terms, [r.id, cid, r.title, r.subject, r.description, r.status]);
            if (score > 0) out.push({ key: 'req-' + (cid || r.id), type: 'Service Request', typeClass: 'rpill rpill--req', title: r.id || ('#' + cid), sub: r.title || r.subject || '', recordId: cid, score });
        });
        return out
            .filter((r, i, list) => list.findIndex(x => x.key === r.key) === i)
            .sort((a, b) => b.score - a.score || String(a.title || '').localeCompare(String(b.title || '')));
    }
    handleSearchResult(e) { const id = e.currentTarget.dataset.id; if (id) { this.clearSearch(); this._openDetail(id); } }

    normalize(v) {
        return String(v || '').replace(/<[^>]*>/g, ' ').toLowerCase().normalize('NFD')
            .replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9#]+/g, ' ').trim();
    }
    score(query, terms, fields) {
        const hay = this.normalize(fields.filter(Boolean).join(' '));
        if (!hay || !terms.length) return 0;
        if (hay.includes(query)) return query.length + 20;
        if (terms.every(t => hay.includes(t))) return terms.reduce((s, t) => s + (hay.includes(t) ? t.length : 0), 0);
        return 0;
    }
    stripHtml(v) { return String(v || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim(); }
    fmtDate(dt) {
        if (!dt) return '';
        try {
            const d = new Date(dt);
            if (isNaN(d.getTime())) return '';
            const dd = String(d.getDate()).padStart(2, '0');
            const mm = String(d.getMonth() + 1).padStart(2, '0');
            return `${dd}-${mm}-${String(d.getFullYear()).slice(-2)}`;
        } catch (e) { return ''; }
    }

    /* ===================== catalog → form ===================== */
    openCatalog() { this.view = 'catalog'; }
    openNeedHelp() { this.view = 'catalog'; }
    selectCategory(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedCategory = this.catalog.find(c => c.id === id) || null;
        this.selectedOffering = (this.selectedCategory && this.selectedCategory.offerings.length) ? this.selectedCategory.offerings[0] : null;
        this.formRequirement = ''; this.formFile = null; this.formFileName = ''; this.formError = '';
        this.view = 'form';
    }
    selectOffering(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedOffering = (this.selectedCategory.offerings || []).find(o => o.id === id) || null;
        this.formError = '';
    }
    get categoryOfferings() {
        if (!this.selectedCategory) return [];
        return this.selectedCategory.offerings.map(o => {
            const active = this.selectedOffering && o.id === this.selectedOffering.id;
            return { ...o, navClass: 'subnav-item' + (active ? ' subnav-item--active' : ''), showChevron: !active };
        });
    }
    get formTitle() { return this.selectedOffering ? this.selectedOffering.name : (this.selectedCategory ? this.selectedCategory.name : ''); }
    get hasFile() { return !!this.formFileName; }
    get fileLabel() { return this.formFileName ? this.formFileName : 'Choose a file…'; }
    get submitDisabled() { return this.submitting || !this.selectedOffering || (this.formRequirement || '').trim() === ''; }

    handleRequirementInput(e) { this.formRequirement = e.target.value; if (this.formError) this.formError = ''; }
    handleFileChange(e) {
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        if (file.size > this.MAX_BYTES) { this.formError = 'File too large (max 5 MB).'; e.target.value = ''; return; }
        this.formFile = file; this.formFileName = file.name;
    }
    removeFile() { this.formFile = null; this.formFileName = ''; }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve({ fileData: String(reader.result).split(',')[1], fileName: file.name });
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    async submitRequest() {
        if (this.submitDisabled) {
            if ((this.formRequirement || '').trim() === '') this.formError = 'Please detail your requirement.';
            return;
        }
        this.submitting = true;
        try {
            let fileData, fileName;
            if (this.formFile) ({ fileData, fileName } = await this.readFileAsBase64(this.formFile));
            await createNeedHelpCase({
                serviceOfferingId: this.selectedOffering.id,
                subject: this.selectedOffering.name,
                description: this.formRequirement,
                fileName,
                fileData,
                constituentRoleId: this.roleId
            });
            this.submitting = false;
            this.successTitle = 'Request Raised';
            this.successSub = 'Your request was raised successfully';
            this.showSuccessModal = true;
            this.loadData();
        } catch (err) {
            this.submitting = false;
            this.errorText = (err && err.body && err.body.message) || 'Please try again later.';
            this.showErrorModal = true;
        }
    }
    closeError() { this.showErrorModal = false; }
    _resetForm() { this.selectedCategory = null; this.selectedOffering = null; this.formRequirement = ''; this.formFile = null; this.formFileName = ''; this.formError = ''; }

    /* ===================== detail ===================== */
    handleRowClick(e) { const id = e.currentTarget.dataset.id; if (id) this._openDetail(id); }
    _openDetail(caseId) {
        this.detailLoading = true; this.view = 'detail'; this.detail = null;
        getCaseDetail({ caseId })
            .then(d => { this.detail = this._mapDetail(d); this.detailLoading = false; })
            .catch(err => {
                this.detailLoading = false;
                this.errorText = (err && err.body && err.body.message) || 'Could not load this request.';
                this.showErrorModal = true; this.view = 'dashboard';
            });
    }
    _mapDetail(d) {
        if (!d) return null;
        const st = (d.status || '').toLowerCase();
        const adminComments = (d.comments || []).filter(c => !c.isCurrentUser).map(c => c.body);
        const docs = [];
        if (d.attachmentUrl) docs.push({ id: d.caseId, name: d.attachmentName || 'Attachment', url: d.attachmentUrl });
        return {
            recordId: d.caseId,
            id: d.caseNumber ? ('#' + d.caseNumber) : ('#' + d.caseId),
            subject: d.subject,
            category: d.serviceOfferingName || d.recordType || '',
            status: d.status,
            requirement: d.description,
            dateStr: this.fmtDateTime(d.createdDate),
            adminReply: adminComments.length ? adminComments.join('\n\n') : null,
            documents: docs,
            canCancel: !(st.includes('closed') || st.includes('cancel') || st.includes('reject')),
            canFeedback: st.includes('closed') && !d.hasFeedbackSubmitted
        };
    }
    fmtDateTime(dt) {
        if (!dt) return '';
        try {
            const d = new Date(dt);
            if (isNaN(d.getTime())) return '';
            return d.toLocaleString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
        } catch (e) { return ''; }
    }
    get detailStatusClass() {
        const st = ((this.detail && this.detail.status) || '').toLowerCase();
        if (st.includes('review') || st.includes('progress') || st.includes('new') || st.includes('open')) return 'badge badge--amber';
        if (st.includes('reject')) return 'badge badge--red';
        if (st.includes('closed') || st.includes('cancel')) return 'badge badge--grey';
        return 'badge badge--blue';
    }
    get hasDocuments() { return this.detail && this.detail.documents && this.detail.documents.length > 0; }
    get hasAdminReply() { return this.detail && this.detail.adminReply; }

    /* ===================== cancel (closeCase) ===================== */
    askCancel() { if (this.detail) { this.cancelTargetId = this.detail.recordId; this.showCancelConfirm = true; } }
    dismissCancel() { this.showCancelConfirm = false; this.cancelTargetId = null; }
    confirmCancel() {
        const id = this.cancelTargetId; this.showCancelConfirm = false;
        if (!id) return;
        closeCase({ caseId: id })
            .then(() => {
                this.successTitle = 'Request Canceled';
                this.successSub = 'Your request has been canceled';
                this.showSuccessModal = true;
                this.loadData();
            })
            .catch(err => { this.errorText = (err && err.body && err.body.message) || 'Could not cancel the request.'; this.showErrorModal = true; });
    }

    /* ===================== feedback ===================== */
    handleLeaveFeedback(e) { e.stopPropagation(); const id = e.currentTarget.dataset.id; if (id) { this.feedbackTargetId = id; this.feedbackRating = 0; this.feedbackComment = ''; this.showFeedbackModal = true; } }
    openFeedback() { if (this.detail) { this.feedbackTargetId = this.detail.recordId; this.feedbackRating = 0; this.feedbackComment = ''; this.showFeedbackModal = true; } }
    get stars() { return [1, 2, 3, 4, 5].map(n => ({ n, cls: n <= this.feedbackRating ? 'star star--on' : 'star' })); }
    setStar(e) { this.feedbackRating = parseInt(e.currentTarget.dataset.n, 10) || 0; }
    handleFeedbackComment(e) { this.feedbackComment = e.target.value; }
    dismissFeedback() { this.showFeedbackModal = false; }
    submitFeedback() {
        // submitCaseFeedback(caseId, rating String, feedback) — reference signature.
        submitCaseFeedback({ caseId: this.feedbackTargetId, rating: String(this.feedbackRating || ''), feedback: this.feedbackComment || '' })
            .then(() => {
                this.showFeedbackModal = false;
                this.successTitle = 'Feedback Submitted';
                this.successSub = 'Thank you for your feedback';
                this.showSuccessModal = true;
                this.loadData();
            })
            .catch(err => { this.errorText = (err && err.body && err.body.message) || 'Could not submit feedback.'; this.showErrorModal = true; });
    }

    /* ===================== modals / nav ===================== */
    closeSuccessAny() { this.showSuccessModal = false; this._resetForm(); this.view = 'dashboard'; }
    backToDashboard() { this.view = 'dashboard'; this._resetForm(); }
    backToCatalog() { this.view = 'catalog'; }
    stop(e) { e.stopPropagation(); }
}