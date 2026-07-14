// V2 wiring — calls OLD KenBusinessController. Do not modify the OLD controller signature.
// Full-page inline view router (no .slds-modal anywhere).
import { LightningElement, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import getAllBusinesses from '@salesforce/apex/KenBusinessController.getAllBusinesses';
import getBusinessById from '@salesforce/apex/KenBusinessController.getBusinessById';
import getMyBusinesses from '@salesforce/apex/KenBusinessController.getMyBusinesses';
import getSimilarBusinesses from '@salesforce/apex/KenBusinessController.getSimilarBusinesses';
import updateBusiness from '@salesforce/apex/KenBusinessController.updateBusiness';
import expressInterest from '@salesforce/apex/KenBusinessController.expressInterest';
import createBusinessListing from '@salesforce/apex/KenBusinessDirectoryV2Controller.createBusinessListing';

const MAX_COVER_BYTES = 2 * 1024 * 1024; // ~2MB

const CHAT_HANDOFF_KEY = 'a2-chat-target';

const SF_ID_RE_B = /^[a-zA-Z0-9]{15,18}$/;
const isSfIdB = (v) => typeof v === 'string' && SF_ID_RE_B.test(v);

const BIZ_PALETTE = ['#3061FF','#B033C8','#19A974','#F59E0B','#E8B4D6','#67A1C8','#8B5CF6','#EF4444'];
const CATEGORIES = ['All','Technology','Art & Design','Education','Retail','Food & Beverage','Hotels & Accommodation','Financial Services','Health & Wellness','Legal Services','Consumer Goods'];

const STATUS_TO_KEY = (s) => {
    const v = (s || '').toLowerCase();
    if (v === 'approved' || v === 'live' || v === 'active') return 'live';
    if (v === 'rejected' || v === 'denied') return 'rejected';
    return 'review';
};
const STATUS_TO_LABEL = (s) => {
    const v = (s || '').toLowerCase();
    if (v === 'approved' || v === 'live' || v === 'active') return 'Live';
    if (v === 'rejected' || v === 'denied') return 'Rejected';
    return 'In Review';
};

const SETUP_STEPS = ['Basics','Details','Offer','Review'];

const FALLBACK_COVER = 'https://images.unsplash.com/photo-1497366216548-37526070297c?w=1600&q=80';

// Only allow http(s) absolute or root-relative URLs (no data:, no javascript:).
const SAFE_URL_RE = /^(https?:|\/)/i;
const safeImageUrl = (u, fallback = '') => {
    if (!u || typeof u !== 'string') return fallback;
    return SAFE_URL_RE.test(u.trim()) ? u : fallback;
};

export default class KenPortalBusinessDirectoryV2 extends LightningElement {
    // View state — MUTUALLY EXCLUSIVE: 'board' | 'detail' | 'setup'
    @track view = 'board';
    @track selectedBusinessId = null;
    @track activeCat = 'All';

    // Scroll restoration snapshots (per view)
    _scrollY = { board: 0, detail: 0 };

    // Reusable date formatter: returns '15 Jul 2026' style.
    formatDate(iso, withTime = false) {
        if (!iso) return '';
        const d = new Date(iso);
        if (isNaN(d.getTime())) return '';
        const opts = { day: '2-digit', month: 'short', year: 'numeric' };
        if (withTime) { opts.hour = '2-digit'; opts.minute = '2-digit'; opts.hour12 = true; }
        try { return d.toLocaleDateString('en-IN', opts); } catch (e) { return ''; }
    }

    // Data
    @track businessesState = [];
    @track myBusinessesState = [];
    @track similarState = [];
    @track isLoading = true;
    @track businessesError = null;

    // Setup wizard
    @track setupStep = 0;
    @track setupMode = 'create';
    @track editingBusinessId = null;
    @track setupForm = { name:'', category:'Technology', city:'', tagline:'', about:'', products:'', contact:'', offer:'' };

    // Cover photo (Basics step)
    @track coverPreviewUrl = '';
    coverFileName = '';
    coverBase64 = '';
    @track submitting = false;

    // Express Interest modal
    @track showInterestModal = false;
    @track interestSubject = '';
    @track interestMessage = '';
    @track interestSubmitting = false;

    // Toast
    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer = null;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const view = params.get('view');
            const id = params.get('id');
            const VALID = ['board', 'detail', 'setup', 'landing'];
            if (view && VALID.indexOf(view) > -1) this.view = (view === 'landing') ? 'board' : view;
            if (id) this.selectedBusinessId = /^\d+$/.test(id) ? Number(id) : id;
        } catch (e) { /* ignore */ }
        this.loadAll();
    }

    loadAll() {
        this.isLoading = true;
        let hadError = false;
        Promise.all([
            getAllBusinesses().catch(err => { hadError = true; this.businessesError = err; return null; }),
            getMyBusinesses().catch(err => { hadError = true; this.businessesError = err; return null; })
        ]).then(([all, mine]) => {
            if (hadError && all == null && mine == null) {
                this.businessesState = [];
                this.myBusinessesState = [];
                // eslint-disable-next-line no-console
                console.error('KenBusinessController error', this.businessesError);
            } else {
                this.businessesState = this.mapAllDto(all);
                this.myBusinessesState = this.mapMineDto(mine);
                this.businessesError = null;
            }
            this.isLoading = false;
            // If we landed on detail via URL, fetch similar businesses.
            if (this.view === 'detail' && this.selectedBusinessId) {
                this.loadSimilar();
            }
        });
    }

    loadSimilar() {
        const cur = this.selectedBusiness;
        if (!cur || !cur.category) { this.similarState = []; return; }
        getSimilarBusinesses({ currentBusinessId: this.selectedBusinessId, category: cur.category, maxRows: 3 })
            .then(rows => { this.similarState = this.mapAllDto(rows); })
            .catch(() => { this.similarState = []; });
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.view && this.view !== 'board') params.set('view', this.view); else params.delete('view');
            if (this.selectedBusinessId) params.set('id', String(this.selectedBusinessId)); else params.delete('id');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    get viewState() {
        return {
            isMainBoard: this.view === 'board',
            isBusinessDetail: this.view === 'detail',
            isSetup: this.view === 'setup'
        };
    }
    get isMainBoard() { return this.view === 'board'; }
    get isBusinessDetail() { return this.view === 'detail'; }
    get isSetup() { return this.view === 'setup'; }

    get hasBusinesses() { return (this.businessesState || []).length > 0; }
    get showEmptyState() { return !this.isLoading && !this.hasBusinesses && !this.businessesError; }
    get hasSimilar() { return (this.similarState || []).length > 0; }
    get hasSelectedBusiness() {
        const sb = this.selectedBusiness;
        return !!(sb && sb.id && sb.name);
    }

    mapAllDto(rows) {
        return (rows || []).filter(Boolean).map((b, i) => {
            const initial = (b.name || ' ').charAt(0).toUpperCase();
            const col = BIZ_PALETTE[i % BIZ_PALETTE.length];
            const cover = safeImageUrl(b.featuredImage, FALLBACK_COVER);
            const address = b.address || b.location || '';
            const aboutText = b.description || '';
            const paragraphs = (aboutText ? aboutText.split(/\n\s*\n/) : []).filter(p => p && p.trim().length > 0);
            // If only one paragraph, try to break by sentences into 2-3 chunks for visual variety.
            let finalParagraphs = paragraphs;
            if (paragraphs.length <= 1 && aboutText) {
                const sentences = aboutText.split(/(?<=\.)\s+/).filter(Boolean);
                if (sentences.length >= 3) {
                    const third = Math.ceil(sentences.length / 3);
                    finalParagraphs = [
                        sentences.slice(0, third).join(' '),
                        sentences.slice(third, third * 2).join(' '),
                        sentences.slice(third * 2).join(' ')
                    ].filter(Boolean);
                } else {
                    finalParagraphs = paragraphs.length ? paragraphs : [aboutText];
                }
            }
            const founder = b.ownerName || '';
            const founderAvatarRaw = b.ownerImage ? this.resolvePhotoUrl(b.ownerImage) : '';
            const founderAvatar = safeImageUrl(founderAvatarRaw, '');
            const safeLogo = safeImageUrl(b.logo, '');
            return {
                id: b.id,
                ownerAccountId: b.ownerAccountId || null,
                name: b.name || '',
                owner: founder,
                founderName: founder,
                ownerAccountId: b.ownerAccountId || null,
                founderAvatarUrl: founderAvatar,
                hasFounderAvatar: !!founderAvatar,
                hasOwner: !!founder,
                category: b.category || '',
                city: address,
                address: address,
                tagline: (aboutText ? aboutText.split(/[\.\n]/)[0].slice(0, 120) : ''),
                initial,
                col,
                logoStyle: `background:${col};color:#fff;`,
                discount: '',
                about: aboutText,
                aboutParagraphs: finalParagraphs.map((p, idx) => ({ id: idx, text: p })),
                products: '',
                contact: [b.email, b.phone].filter(Boolean).join(' · '),
                email: b.email || '',
                phone: b.phone || '',
                website: b.website || '',
                logoUrl: safeLogo,
                hasLogo: !!safeLogo,
                coverImageUrl: cover,
                coverStyle: `background-image:linear-gradient(rgba(0,0,0,0.45),rgba(0,0,0,0.10)),url('${cover}');`,
                cardCoverStyle: `background-image:url('${cover}');`,
                mapUrl: b.mapUrl || (address ? `https://maps.google.com/?q=${encodeURIComponent(address)}` : ''),
                // Defensive boolean — accept true OR 'true' string.
                isFeatured: (b.isFeatured === true || b.isFeatured === 'true'),
                status: b.status || '',
                chatLabel: founder ? `Chat with ${founder.split(' ')[0]}` : 'Chat with owner'
            };
        });
    }

    resolvePhotoUrl(url) {
        if (!url) return '';
        if (url.startsWith('http')) return url;
        // Relative /services/images/photo/... — prepend portal origin.
        try { return window.location.origin + url; } catch (e) { return url; }
    }

    mapMineDto(rows) {
        return (rows || []).filter(Boolean).map(b => {
            const safeLogo = safeImageUrl(b.logo, '');
            return {
                id: b.id,
                name: b.name || '',
                category: b.category || '',
                status: STATUS_TO_LABEL(b.status),
                statusKey: STATUS_TO_KEY(b.status),
                logoUrl: safeLogo,
                hasLogo: !!safeLogo
            };
        });
    }

    get categories() {
        return CATEGORIES.map(c => ({ id:c, label:c, chipClass: c === this.activeCat ? 'chip chip--active' : 'chip' }));
    }

    get featured() {
        // Prefer a record marked isFeatured; fall back to the first business.
        const explicit = this.businessesState.find(b => b.isFeatured);
        return explicit || this.businessesState[0] || null;
    }

    get hasFeatured() { return !!this.featured; }

    get businesses() {
        const list = this.activeCat === 'All' ? this.businessesState : this.businessesState.filter(b => b.category === this.activeCat);
        // Show all businesses (including the featured one) in the grid too.
        return list;
    }

    get myBusinesses() {
        return this.myBusinessesState.map(b => ({ ...b, statusClass: `mb__status mb__status--${b.statusKey}` }));
    }

    get hasMyBusinesses() { return (this.myBusinessesState || []).length > 0; }

    get selectedBusiness() {
        const id = this.selectedBusinessId;
        if (!id) return this.emptyBusiness();
        const b = this.businessesState.find(x => x.id === id || String(x.id) === String(id));
        if (!b) return this.emptyBusiness();
        return b;
    }

    emptyBusiness() {
        return {
            id:null, name:'', owner:'', founderName:'', ownerAccountId:null, founderAvatarUrl:'',
            hasFounderAvatar:false, hasOwner:false, category:'', city:'', address:'',
            tagline:'', initial:'', col:'#3061FF', logoStyle:'', discount:'',
            about:'', aboutParagraphs:[], products:'', contact:'', email:'', phone:'',
            website:'', logoUrl:'', hasLogo:false, coverImageUrl:'', coverStyle:'',
            cardCoverStyle:'', mapUrl:'', isFeatured:false, status:'', chatLabel:'Chat'
        };
    }

    get similarBusinesses() {
        return (this.similarState || []).slice(0, 3);
    }

    get setupSteps() {
        return SETUP_STEPS.map((label, idx) => ({
            id: idx, label,
            stepClass: idx === this.setupStep ? 'step step--active' : (idx < this.setupStep ? 'step step--done' : 'step')
        }));
    }
    get isStep0() { return this.setupStep === 0; }
    get isStep1() { return this.setupStep === 1; }
    get isStep2() { return this.setupStep === 2; }
    get isStep3() { return this.setupStep === 3; }
    get setupProgressLabel() { return `Step ${this.setupStep + 1} of ${SETUP_STEPS.length}`; }
    get setupCanBack() { return this.setupStep > 0; }
    get isLastSetupStep() { return this.setupStep === SETUP_STEPS.length - 1; }
    get isEditMode() { return this.setupMode === 'edit'; }
    get setupHeading() { return this.setupMode === 'edit' ? 'Edit Your Business' : 'List Your Business'; }
    get setupSubmitLabel() { return this.setupMode === 'edit' ? 'Update Business' : 'Submit for Review'; }

    handleCat(event) { this.activeCat = event.currentTarget.dataset.id; }

    // ── Navigation ────────────────────────────────────────────────────────────
    handleOpenBusiness(event) {
        const raw = event.currentTarget.dataset.id;
        try { this._scrollY.board = window.scrollY || 0; } catch (e) { /* ignore */ }
        this.selectedBusinessId = typeof raw === 'string' && !/^\d+$/.test(raw) ? raw : Number(raw);
        this.view = 'detail';
        this.syncUrl();
        this.loadSimilar();
        try { window.scrollTo({ top: 0, behavior: 'auto' }); } catch (e) { /* ignore */ }
    }
    handleBackToDirectory() {
        this.view = 'board';
        this.selectedBusinessId = null;
        this.similarState = [];
        this.syncUrl();
        // Restore scroll after layout settles.
        try {
            const y = this._scrollY.board || 0;
            requestAnimationFrame(() => { try { window.scrollTo({ top: y, behavior: 'auto' }); } catch (e) { /* ignore */ } });
        } catch (e) { /* ignore */ }
    }

    // ── External actions ──────────────────────────────────────────────────────
    handleGetDirections() {
        const url = this.selectedBusiness.mapUrl;
        if (url) { try { window.open(url, '_blank', 'noopener'); } catch (e) { /* ignore */ } }
    }
    handleVisitWebsite() {
        const url = this.selectedBusiness.website;
        if (url) {
            const full = url.startsWith('http') ? url : 'https://' + url;
            try { window.open(full, '_blank', 'noopener'); } catch (e) { /* ignore */ }
        }
    }
    handleEmail() {
        const e = this.selectedBusiness.email;
        if (e) { try { window.location.href = 'mailto:' + e; } catch (err) { /* ignore */ } }
    }
    handlePhone() {
        const p = this.selectedBusiness.phone;
        if (p) { try { window.location.href = 'tel:' + p.replace(/\s+/g,''); } catch (err) { /* ignore */ } }
    }
    handleChat() {
        const sb = this.selectedBusiness || {};
        const targetId = sb.ownerAccountId; // Person Account Id — Apex resolves to PersonContactId
        if (!targetId) {
            this._showToast('Cannot start chat — owner unknown');
            return;
        }
        try {
            sessionStorage.setItem('a2-chat-target', JSON.stringify({
                contactId: targetId,
                name: sb.founderName || sb.name || '',
                ts: Date.now()
            }));
        } catch (e) { /* sandboxed — ignore */ }
        try { window.location.assign(basePath + '/chat'); } catch (e) { /* ignore */ }
    }
    // ── Express Interest modal ────────────────────────────────────────────────
    handleExpressInterest() {
        const sb = this.selectedBusiness || {};
        this.interestSubject = sb.name ? `Interested in ${sb.name}` : 'Interested in your business';
        this.interestMessage = '';
        this.showInterestModal = true;
    }
    handleCloseInterest() {
        this.showInterestModal = false;
        this.interestSubject = '';
        this.interestMessage = '';
        this.interestSubmitting = false;
    }
    stopBubble(event) { if (event && event.stopPropagation) event.stopPropagation(); }
    handleInterestField(event) {
        const f = event.target.dataset.field;
        if (f) this[f] = event.target.value;
    }
    get interestSubmitDisabled() {
        return this.interestSubmitting
            || !(this.interestSubject || '').trim()
            || !(this.interestMessage || '').trim();
    }
    handleSubmitInterest() {
        const businessId = this.selectedBusiness && this.selectedBusiness.id;
        if (!businessId) { this._showToast('No business selected'); return; }
        const subject = (this.interestSubject || '').trim();
        const message = (this.interestMessage || '').trim();
        if (!subject || !message) return;
        this.interestSubmitting = true;
        expressInterest({ req: { businessId, subject, message } })
            .then(() => {
                this.handleCloseInterest();
                this._showToast('Interest sent');
            })
            .catch(err => {
                this.interestSubmitting = false;
                const msg = (err && err.body && err.body.message) || 'Could not send interest. Please try again.';
                this._showToast(msg);
            });
    }

    handleListBusiness() { this.handleOpenSetup(); }

    // ── Setup wizard (preserved from prior version) ───────────────────────────
    handleOpenSetup() {
        this.setupStep = 0;
        this.setupMode = 'create';
        this.editingBusinessId = null;
        this.setupForm = { name:'', category:'Technology', city:'', tagline:'', about:'', products:'', contact:'', offer:'' };
        this._resetCover();
        this.view = 'setup';
        this.syncUrl();
    }

    _resetCover() {
        this.coverPreviewUrl = '';
        this.coverFileName = '';
        this.coverBase64 = '';
    }

    get hasCoverPreview() { return !!this.coverPreviewUrl; }

    handleCoverPhoto(event) {
        const file = event.target && event.target.files && event.target.files[0];
        if (!file) return;
        if (!/^image\/(png|jpeg)$/.test(file.type)) {
            this._showToast('Please choose a PNG or JPEG image');
            return;
        }
        if (file.size > MAX_COVER_BYTES) {
            this._showToast('Cover photo must be under 2MB');
            return;
        }
        const reader = new FileReader();
        reader.onload = () => {
            const result = reader.result || '';
            this.coverPreviewUrl = result;                 // data: URL for preview only
            this.coverBase64 = String(result).split(',')[1] || ''; // strip data: prefix
            this.coverFileName = file.name;
        };
        reader.onerror = () => { this._showToast('Could not read the image'); };
        reader.readAsDataURL(file);
    }

    handleEditBusiness(event) {
        if (event && event.stopPropagation) event.stopPropagation();
        const raw = event.currentTarget.dataset.id;
        const id = isSfIdB(raw) ? raw : (Number.isNaN(Number(raw)) ? raw : Number(raw));
        let source = this.businessesState.find(x => x.id === id || String(x.id) === String(id));
        const summary = this.myBusinessesState.find(x => x.id === id || String(x.id) === String(id));
        if (!source) source = summary || null;
        this.setupStep = 0;
        this.setupMode = 'edit';
        this.editingBusinessId = id;
        this.setupForm = {
            name: (source && source.name) || '',
            category: (source && source.category) || 'Technology',
            city: (source && (source.city || source.address)) || '',
            tagline: (source && source.tagline) || '',
            about: (source && source.about) || '',
            products: (source && source.products) || '',
            contact: (source && source.contact) || '',
            offer: (source && source.discount) || ''
        };
        this.view = 'setup';
        this.syncUrl();
    }
    handleCancelSetup() { this.view = 'board'; this.syncUrl(); }
    handleSetupField(event) {
        const f = event.target.dataset.field;
        if (f) this.setupForm = { ...this.setupForm, [f]: event.target.value };
    }
    handleSetupNext() {
        if (this.setupStep === 0 && !(this.setupForm.name || '').trim()) { this._showToast('Please enter a business name'); return; }
        if (this.setupStep < SETUP_STEPS.length - 1) this.setupStep += 1;
    }
    handleSetupPrev() { if (this.setupStep > 0) this.setupStep -= 1; }
    handleSetupSubmit() {
        const form = this.setupForm || {};
        const baseReq = {
            businessName: (form.name || '').trim() || 'New Business',
            businessType: form.category || '',
            address: form.city || '',
            description: form.about || form.tagline || '',
            email: '', phone: '', website: ''
        };
        if (this.setupMode === 'edit' && isSfIdB(this.editingBusinessId)) {
            const req = { ...baseReq, id: this.editingBusinessId };
            updateBusiness({ req })
                .then(() => {
                    this.businessesState = this.businessesState.map(b => (b.id === this.editingBusinessId)
                        ? { ...b, name: req.businessName, category: req.businessType, city: req.address, address: req.address, about: req.description, tagline: req.description }
                        : b);
                    this.view = 'board';
                    this.syncUrl();
                    this._showToast('Business updated');
                    this.loadAll();
                })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('updateBusiness error', err);
                    this.view = 'board';
                    this.syncUrl();
                    this._showToast((err && err.body && err.body.message) || 'Could not update. Please try again.');
                });
            return;
        }
        if (this.submitting) return;
        this.submitting = true;
        const payload = {
            name: baseReq.businessName,
            category: form.category || '',
            website: '',
            about: form.about || '',
            tagline: form.tagline || '',
            city: form.city || '',
            contact: form.contact || '',
            owner: '',
            offer: form.offer || '',
            products: form.products || '',
            coverFileName: this.coverFileName || '',
            coverBase64: this.coverBase64 || ''
        };
        createBusinessListing({ payload })
            .then(accountId => {
                this.submitting = false;
                const next = { id: accountId, name: payload.name, category: payload.category, status: 'In Review', statusKey: 'review', hasLogo:false, logoUrl:'' };
                this.myBusinessesState = [next, ...this.myBusinessesState];
                // Close the submission wizard and refresh the directory so the new listing shows.
                this.view = 'board';
                this.syncUrl();
                this._resetCover();
                this.loadAll();
                this._showToast('Business Listed Successfully!');
            })
            .catch(err => {
                this.submitting = false;
                // eslint-disable-next-line no-console
                console.error('createBusinessListing error', err);
                const msg = (err && err.body && err.body.message) || 'Could not list your business. Please try again.';
                this._showToast(msg);
            });
    }

    handleMyBusinessClick(event) {
        const raw = event.currentTarget.dataset.id;
        const id = typeof raw === 'string' && !/^\d+$/.test(raw) ? raw : Number(raw);
        // Open detail view if it's an SF record we already have details for.
        if (this.businessesState.find(x => x.id === id || String(x.id) === String(id))) {
            this.selectedBusinessId = id;
            this.view = 'detail';
            this.syncUrl();
            this.loadSimilar();
            return;
        }
        const b = this.myBusinessesState.find(x => x.id === id || String(x.id) === String(id));
        if (b) this._showToast(`${b.name}: ${b.status}`);
    }

    _showToast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }
    disconnectedCallback() { if (this._toastTimer) clearTimeout(this._toastTimer); }
}