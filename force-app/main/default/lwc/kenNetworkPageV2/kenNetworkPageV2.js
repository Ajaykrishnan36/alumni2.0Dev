// V2 wiring — calls OLD KenNetworkController.getNetworkData. Do not modify the OLD controller.
// If a DTO shape mismatch breaks rendering, fix it in this file's mapDto(), not in the controller.
// Imperative (not @wire) because OLD methods aren't consistently cacheable=true and LWR rejects
// non-cacheable methods in @wire. Mock data below stays as fallback so the page never blanks.
import { LightningElement, track } from 'lwc';
import getNetworkData from '@salesforce/apex/KenNetworkController.getNetworkData';
import getAlumniProfile from '@salesforce/apex/KenNetworkController.getAlumniProfile';
import requestConnection from '@salesforce/apex/KenNetworkController.requestConnection';
import respondToConnectionRequests from '@salesforce/apex/KenNetworkController.respondToConnectionRequests';
import removeConnection from '@salesforce/apex/KenNetworkController.removeConnection';
import requestMentorship from '@salesforce/apex/KenNetworkController.requestMentorship';

const SF_ID_RE = /^[a-zA-Z0-9]{15,18}$/;
const isSfId = (v) => typeof v === 'string' && SF_ID_RE.test(v);

// Shared helpers — reused by Network main + child decorate paths.
// formatDate normalises Salesforce ISO date strings to "15 Jul 2026" (and optionally "..., 04:00 PM").
export function formatDate(iso, withTime = false) {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const opts = { day: '2-digit', month: 'short', year: 'numeric' };
    if (withTime) { opts.hour = '2-digit'; opts.minute = '2-digit'; opts.hour12 = true; }
    return d.toLocaleDateString('en-IN', opts);
}
// safeImg: only allow http(s) or relative URLs; null-out anything else (data:, javascript:, etc.).
export function safeImg(url) {
    if (!url || typeof url !== 'string') return null;
    if (/^https?:\/\//i.test(url) || url.charAt(0) === '/') return url;
    return null;
}
// fallbackAvatar: deterministic background colour from a name string for letter-disc fallbacks.
const _AV_COLORS = ['#FFE0CC','#FFE9D9','#E8E4FF','#FFD9D9','#D9F0E2','#FFE5F0','#E8B4D6','#67A1C8'];
export function fallbackAvatar(name) {
    const s = (name || '').toString();
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
    return _AV_COLORS[h % _AV_COLORS.length];
}
// Defensive boolean — booleans crossing Apex→LWC can arrive as strings.
export function asBool(v) { return v === true || v === 'true'; }

const EXPERTISE_COLORS = [
    'background:#EAEFFF;color:#3061FF;',
    'background:#F3E8FF;color:#8A38F5;',
    'background:#FFE8F0;color:#C026D3;',
    'background:#E0F2FE;color:#0284C7;',
    'background:#DCFCE7;color:#16A34A;',
    'background:#FEF3C7;color:#B45309;'
];
const COLORS = ['#FFE0CC', '#FFE9D9', '#E8E4FF', '#FFD9D9', '#D9F0E2', '#FFE5F0'];

function makeExpertise(arr) {
    return arr.map((s, i) => ({ label: s, style: EXPERTISE_COLORS[i % EXPERTISE_COLORS.length] }));
}

const MC_COLORS = ['#3061FF', '#8A38F5', '#3F4A60', '#F59E0B', '#16A34A', '#C026D3'];
function mc(name, role, initial, i) {
    return { name, role, initial, style: `background:${MC_COLORS[i % MC_COLORS.length]};color:#fff;` };
}

// Mock profile detail map — left empty; details now come from getAlumniProfile() (selectedProfileOverride).
const PROFILE_DETAILS = {};
// Legacy mock map disabled to avoid any chance of flashing fake bios.
const _LEGACY_PROFILE_DETAILS_UNUSED = {
    1: { // Tanya Singh — Executive at TatvaOne
        work: [
            { title: 'Executive', sub: 'TatvaOne · Full-time', date: 'Mar 2021 — Present · 4 yrs', logo: 'T' },
            { title: 'VP, Strategy', sub: 'Sankalp Co. · Full-time', date: 'Jun 2017 — Feb 2021 · 3.8 yrs', logo: 'S' },
            { title: 'Senior Manager', sub: 'Deloitte · Full-time', date: 'Aug 2014 — May 2017 · 2.8 yrs', logo: 'D' }
        ],
        education: [
            { title: 'MBA, Strategy & Leadership', sub: 'IIM Ahmedabad', date: '2012 — 2014', logo: 'I' },
            { title: 'B.Com (Hons)', sub: 'St. Xavier’s College, Mumbai', date: '2008 — 2011', logo: 'X' }
        ],
        recentActivity: [
            { text: 'Shared notes from our Q1 leadership offsite — what made the cut and why.', when: '3d', icon: '📝' },
            { text: 'Attended Pune Alumni Meetup at The Lalit · 42 attendees', when: '1w', icon: '📅' },
            { text: 'Open to mentoring early-career PMs through 1:1 chats.', when: '2w', icon: '🤝' }
        ],
        mutualConnections: [
            mc('Rahul Mehta', 'Founder · Vortex', 'R', 0),
            mc('Karthik Rao', 'PM · Razorpay', 'K', 1),
            mc('Sandra R', 'Executive · TCS', 'S', 2),
            mc('Anya K', 'Lawyer', 'A', 3)
        ]
    },
    2: { // Ritika Patel — TPM at Nexora
        work: [
            { title: 'Technical Program Manager', sub: 'Nexora · Full-time', date: 'Apr 2022 — Present · 3 yrs', logo: 'N' },
            { title: 'Senior Program Manager', sub: 'Flipkart · Full-time', date: 'Jul 2018 — Mar 2022 · 3.8 yrs', logo: 'F' },
            { title: 'Software Engineer', sub: 'Infosys · Full-time', date: 'Jun 2016 — Jun 2018 · 2 yrs', logo: 'I' }
        ],
        education: [
            { title: 'M.Tech, Computer Science', sub: 'IIT Bombay', date: '2014 — 2016', logo: 'I' },
            { title: 'B.E, Information Technology', sub: 'COEP Pune', date: '2010 — 2014', logo: 'C' }
        ],
        recentActivity: [
            { text: 'Wrote a thread on running blameless retros across distributed teams.', when: '5d', icon: '📝' },
            { text: 'Hosted "Scaling Agile" webinar · 180 attendees', when: '2w', icon: '📅' },
            { text: 'Mentoring 8 engineers this quarter on career growth.', when: '3w', icon: '🤝' }
        ],
        mutualConnections: [
            mc('Karthik Rao', 'PM · Razorpay', 'K', 0),
            mc('Drishti A', 'TPM · Crafted Labs', 'D', 1),
            mc('Anya K', 'Lawyer', 'A', 2),
            mc('Sandra R', 'Executive · TCS', 'S', 3)
        ]
    },
    3: { // Drishti A — TPM at Crafted Labs
        work: [
            { title: 'Technical Program Manager', sub: 'Crafted Labs · Full-time', date: 'Sep 2021 — Present · 3.7 yrs', logo: 'C' },
            { title: 'Program Manager', sub: 'Zomato · Full-time', date: 'Mar 2018 — Aug 2021 · 3.5 yrs', logo: 'Z' },
            { title: 'Associate PM', sub: 'Paytm · Full-time', date: 'Jul 2015 — Feb 2018 · 2.6 yrs', logo: 'P' }
        ],
        education: [
            { title: 'MBA, Product Management', sub: 'ISB Hyderabad', date: '2013 — 2015', logo: 'I' },
            { title: 'B.Tech, Electronics', sub: 'NIT Trichy', date: '2009 — 2013', logo: 'N' }
        ],
        recentActivity: [
            { text: 'Open to coffee chats with anyone hiring TPMs in Pune/Bangalore.', when: '2d', icon: '☕' },
            { text: 'Spoke at WomenInTech Pune chapter · 90 attendees', when: '10d', icon: '📅' },
            { text: 'Posted a guide on writing PRDs that engineering actually reads.', when: '3w', icon: '📝' }
        ],
        mutualConnections: [
            mc('Ritika Patel', 'TPM · Nexora', 'R', 0),
            mc('Rahul Mehta', 'Founder · Vortex', 'R', 1),
            mc('Jakob Siphron', 'Designer · Nexora', 'J', 2),
            mc('Sandra R', 'Executive · TCS', 'S', 3)
        ]
    },
    6: { // Jakob Siphron — Product Designer at Nexora
        work: [
            { title: 'Product Designer', sub: 'Nexora · Full-time', date: 'Feb 2022 — Present · 3.3 yrs', logo: 'N' },
            { title: 'Senior UX Designer', sub: 'Swiggy · Full-time', date: 'Aug 2018 — Jan 2022 · 3.4 yrs', logo: 'S' },
            { title: 'UI Designer', sub: 'IDEO · Full-time', date: 'Jun 2015 — Jul 2018 · 3.1 yrs', logo: 'I' }
        ],
        education: [
            { title: 'M.Des, Interaction Design', sub: 'NID Bengaluru', date: '2013 — 2015', logo: 'N' },
            { title: 'B.Des, Communication Design', sub: 'Srishti Institute', date: '2009 — 2013', logo: 'S' }
        ],
        recentActivity: [
            { text: 'Reviewing 5 portfolios this week — DM me if you want feedback.', when: '1d', icon: '🎨' },
            { text: 'Shipped a redesign of the Nexora checkout flow · +14% conversion', when: '2w', icon: '🚀' },
            { text: 'Attended Config 2026 in San Francisco · met 30+ designers', when: '1mo', icon: '📅' }
        ],
        mutualConnections: [
            mc('Vidushi Rastogi', 'Designer · ArthaWorks', 'V', 0),
            mc('Desirae Press', 'Designer · Nexora', 'D', 1),
            mc('Ritika Patel', 'TPM · Nexora', 'R', 2),
            mc('Anya K', 'Lawyer', 'A', 3)
        ]
    }
};

// Mock alumni list removed — Network page renders empty state until Apex returns real data.

export default class KenNetworkPageV2 extends LightningElement {
    @track activeTopTab = 'all';
    @track view = 'grid'; // 'grid' | 'profile'
    @track selectedAlumniId = 0;
    @track searchQuery = '';
    @track sortBy = '';
    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer = null;

    // Live alumni list — starts empty + loading so no mock flash; mock only on Apex error.
    @track alumni = [];
    @track connectionRequests = [];
    @track networkError = null;
    @track isLoading = true;
    @track selectedProfileOverride = null; // populated by getAlumniProfile() when SF id clicked

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const view = params.get('view');
            const id = params.get('id');
            const q = params.get('q');
            const VALID_TABS = ['all', 'connections'];
            const VALID_VIEWS = ['grid', 'profile'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.activeTopTab = tab;
            if (view && VALID_VIEWS.indexOf(view) > -1) this.view = view;
            if (id) this.selectedAlumniId = /^\d+$/.test(id) ? Number(id) : id;
            // Global topbar search lands here with ?q=... — pre-apply it so results show immediately.
            if (q) this.searchQuery = q;
        } catch (e) { /* ignore */ }
        this.loadNetwork();
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeTopTab) params.set('tab', this.activeTopTab); else params.delete('tab');
            if (this.view && this.view !== 'grid') params.set('view', this.view); else params.delete('view');
            if (this.selectedAlumniId) params.set('id', String(this.selectedAlumniId)); else params.delete('id');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    loadNetwork() {
        this.isLoading = true;
        getNetworkData()
            .then(data => {
                const mapped = this.mapDto(data);
                this.alumni = (mapped && Array.isArray(mapped.alumni)) ? mapped.alumni : [];
                this.connectionRequests = (mapped && Array.isArray(mapped.connectionRequests)) ? mapped.connectionRequests : [];
                this.networkError = null;
                this.isLoading = false;
            })
            .catch(err => {
                // Apex failed — show empty state (no mock data flash).
                this.networkError = err;
                this.alumni = [];
                this.isLoading = false;
                // eslint-disable-next-line no-console
                console.error('KenNetworkController.getNetworkData error, using mock fallback', err);
            });
    }

    get hasAlumni() { return (this.alumni || []).length > 0; }
    get showEmptyState() { return !this.isLoading && !this.hasAlumni && !this.networkError; }

    // Translate OLD NetworkDataResponse → existing ALUMNI shape used by the template.
    mapDto(dto) {
        if (!dto) return null;
        const acceptedIds = new Set();
        const list = [];

        const mapRow = (row, connected) => {
            if (!row) return null;
            // Generate a per-row palette index so colors stay varied even from server data.
            const idxColor = list.length;
            return {
                id: row.id,
                name: row.name || '',
                role: row.title || row.jobFunction || '',
                company: row.company || '',
                city: row.location || row.currentCity || '',
                willing: asBool(row.willingToHelp),
                online: asBool(row.isOnline),
                color: COLORS[idxColor % COLORS.length],
                initial: (row.name || ' ').charAt(0).toUpperCase(),
                batch: row.batch || (row.graduationYear ? 'Batch of ' + row.graduationYear : ''),
                connected: asBool(connected),
                bio1: '',
                bio2: '',
                expertise: makeExpertise([row.industry, row.specialisation, row.programLastAttended].filter(Boolean)),
                profileImage: safeImg(row.profileImage),
                avatarFallback: fallbackAvatar(row.name),
                isMentor: asBool(row.isMentor),
                // Detail-only fields kept blank — inline profile view falls back to PROFILE_DETAILS map.
                education: [],
                work: [],
                recentActivity: [],
                mutualConnections: []
            };
        };

        // QA Bug #126 — global dedupe by id. The previous code only deduped allAlumni
        // against acceptedIds; if either bucket itself contained the same alum twice
        // (e.g. matched on multiple constituent roles), the card rendered twice and the
        // Connect/Message buttons appeared duplicated.
        const seen = new Set();
        (dto.yourConnections || []).forEach(r => {
            if (!r || !r.id || seen.has(r.id)) return;
            acceptedIds.add(r.id);
            seen.add(r.id);
            const m = mapRow(r, true);
            if (m) list.push(m);
        });
        (dto.allAlumni || []).forEach(r => {
            if (!r || !r.id || seen.has(r.id)) return;
            seen.add(r.id);
            const m = mapRow(r, false);
            if (m) list.push(m);
        });

        return {
            alumni: list,
            connectionRequests: dto.connectionRequests || []
        };
    }

    disconnectedCallback() { if (this._toastTimer) clearTimeout(this._toastTimer); }

    get viewState() {
        return { isGrid: this.view === 'grid', isProfile: this.view === 'profile' };
    }
    get showRail() { return this.view === 'grid'; }

    get filteredAlumni() {
        const q = (this.searchQuery || '').toLowerCase().trim();
        let list = [...(this.alumni || [])];
        if (this.activeTopTab === 'connections') list = list.filter(a => a.connected);
        if (q) {
            list = list.filter(a =>
                `${a.name || ''} ${a.role || ''} ${a.title || ''} ${a.company || ''} ${a.city || ''} ${a.location || ''} ${a.batch || ''}`
                    .toLowerCase().indexOf(q) >= 0);
        }
        return this._applySort(list);
    }

    _applySort(list) {
        const by = this.sortBy;
        if (!by) return list;
        const arr = [...list];
        if (by === 'name') {
            arr.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
        } else if (by === 'batch') {
            arr.sort((a, b) => String(b.graduationYear || '').localeCompare(String(a.graduationYear || '')));
        } else if (by === 'company') {
            arr.sort((a, b) => (a.company || '').localeCompare(b.company || ''));
        } else if (by === 'recent') {
            arr.sort((a, b) => (b.lastActiveMs || 0) - (a.lastActiveMs || 0));
        }
        return arr;
    }
    get selectedAlumni() {
        const found = (this.alumni || []).find(a => a.id === this.selectedAlumniId);
        if (!found) return null;
        if (this.selectedProfileOverride) return { ...found, ...this.selectedProfileOverride };
        const details = PROFILE_DETAILS[found.id];
        return details ? { ...found, ...details } : found;
    }
    get isSelectedConnected() {
        const a = this.selectedAlumni;
        if (!a) return false;
        // Prefer the authoritative status fetched by getAlumniProfile (carried on the
        // override as connectionStatus). This makes the chat button unlock the moment the
        // fresh profile load reports 'Accepted' — no hard refresh needed. Falls back to
        // the base-list connected flag when no fresh status is available.
        if (a.connectionStatus) {
            return String(a.connectionStatus).toLowerCase() === 'accepted';
        }
        return !!a.connected;
    }

    handleTabChange(event) { this.activeTopTab = event.detail.id; this.syncUrl(); }
    handleSearch(event) { this.searchQuery = event.detail ? event.detail.value : ''; }
    handleSort(event) { this.sortBy = (event.detail && event.detail.value) || ''; }
    handleFilter() { /* noop */ }

    handleAlumniClick(event) {
        // OLD ids are Salesforce IDs (strings); mock ids are numbers — accept both.
        const raw = event.detail && event.detail.id !== undefined ? event.detail.id : event.detail;
        const id = typeof raw === 'string' ? raw : Number(raw);
        if (!id && id !== 0) return;
        const found = (this.alumni || []).find(a => a.id === id);
        if (!found) return;
        this.selectedAlumniId = id;
        this.selectedProfileOverride = null;
        // If id looks like a Salesforce Id, fetch rich profile data and merge.
        if (typeof id === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(id)) {
            getAlumniProfile({ accountId: id })
                .then(dto => {
                    if (dto) this.selectedProfileOverride = this.mapProfileDto(dto);
                })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenNetworkController.getAlumniProfile error', err);
                });
        }
        // Save scroll position so we can restore it when the user backs out of the profile.
        this._scrollY = (typeof window !== 'undefined' && window.scrollY) || 0;
        this.view = 'profile';
        this.syncUrl();
        try { window.scrollTo({ top: 0, behavior: 'instant' }); } catch (e) { window.scrollTo(0, 0); }
    }

    // Translate OLD AlumniProfileDTO → the rich fields kenAlumniProfilePageV2 reads.
    mapProfileDto(dto) {
        if (!dto) return null;
        const work = (dto.experience || []).map(x => ({
            title: x.position || '',
            sub: [x.company, x.employmentType].filter(Boolean).join(' · '),
            date: x.duration || '',
            logo: (x.company || ' ').charAt(0).toUpperCase()
        }));
        const education = (dto.education || []).map(e => ({
            title: e.degree || '',
            sub: e.institution || '',
            date: e.duration || '',
            logo: (e.institution || ' ').charAt(0).toUpperCase()
        }));
        const achievements = (dto.achievements || []).map(a => ({
            title: a.title || '',
            sub: a.meta || a.type || '',
            text: a.description || ''
        }));
        return {
            about: dto.about || '',
            email: dto.email || '',
            phone: dto.phone || '',
            linkedin: dto.linkedin || '',
            connectionId: dto.connectionId || null,
            connectionStatus: dto.connectionStatus || '',
            mentorshipId: dto.mentorshipId || null,
            mentorshipStatus: dto.mentorshipStatus || '',
            work,
            education,
            achievements,
            recentActivity: [],
            mutualConnections: []
        };
    }

    handleBackToGrid() {
        this.view = 'grid';
        this.selectedAlumniId = 0;
        this.selectedProfileOverride = null;
        this.syncUrl();
        // Restore scroll after the grid re-renders.
        const y = this._scrollY || 0;
        try {
            requestAnimationFrame(() => { try { window.scrollTo(0, y); } catch (e) { /* ignore */ } });
        } catch (e) { try { window.scrollTo(0, y); } catch (_) { /* ignore */ } }
    }
    handleConnect(event) {
        const d = (event && event.detail) || {};
        const id = d.id;
        const wasConnected = d.connected === true;
        if (!isSfId(id)) {
            // Mock id — optimistic local toggle only.
            this._toast(wasConnected ? 'Disconnected' : 'Connection request sent');
            return;
        }
        if (wasConnected) {
            // Disconnect path requires a connectionId. The selectedProfileOverride may carry it
            // via getAlumniProfile (dto.connectionId). If not, we surface a TODO toast.
            const connId = this.selectedProfileOverride && this.selectedProfileOverride.connectionId;
            if (!connId) {
                this._toast('Disconnect unavailable (connection id missing)');
                return;
            }
            removeConnection({ connectionId: connId })
                .then(() => {
                    this.alumni = (this.alumni || []).map(a => a.id === id ? { ...a, connected: false } : a);
                    this._toast('Disconnected');
                })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenNetworkController.removeConnection error', err);
                    this._toast((err && err.body && err.body.message) || 'Could not disconnect.');
                });
            return;
        }
        // Connect path — request a new connection.
        requestConnection({ targetAccountId: id })
            .then(() => { this._toast('Connection request sent'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenNetworkController.requestConnection error', err);
                this._toast((err && err.body && err.body.message) || 'Could not send request.');
            });
    }
    handleAcceptRequest(event) {
        const requestId = event && event.detail && event.detail.id;
        if (!isSfId(requestId)) { this._toast('Request accepted'); return; }
        respondToConnectionRequests({ requestIds: [requestId], action: 'Accept' })
            .then(() => {
                this.connectionRequests = (this.connectionRequests || []).filter(r => r.id !== requestId);
                this._toast('Request accepted');
                this.loadNetwork();
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenNetworkController.respondToConnectionRequests(accept) error', err);
                this._toast((err && err.body && err.body.message) || 'Could not accept.');
            });
    }
    handleRejectRequest(event) {
        const requestId = event && event.detail && event.detail.id;
        if (!isSfId(requestId)) { this._toast('Request rejected'); return; }
        respondToConnectionRequests({ requestIds: [requestId], action: 'Reject' })
            .then(() => {
                this.connectionRequests = (this.connectionRequests || []).filter(r => r.id !== requestId);
                this._toast('Request rejected');
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenNetworkController.respondToConnectionRequests(reject) error', err);
                this._toast((err && err.body && err.body.message) || 'Could not reject.');
            });
    }
    handleRequestMentorship(event) {
        const d = (event && event.detail) || {};
        const connectionId = d.connectionId || (this.selectedProfileOverride && this.selectedProfileOverride.connectionId);
        // Don't fake success when there's no real connection — that silently skipped the
        // Apex insert so no Ken_Mentorship__c record was ever created. Mentorship requires
        // an accepted connection first.
        if (!isSfId(connectionId)) {
            this._toast('Please connect with this alum first, then request mentorship.');
            return;
        }
        requestMentorship({ connectionId })
            .then(() => { this._toast('Mentorship request sent'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenNetworkController.requestMentorship error', err);
                this._toast((err && err.body && err.body.message) || 'Could not send request.');
            });
    }
    handleMessage() { /* Child performs sessionStorage handoff + navigation to /chat. */ }
    handleCopyInvite() { this._toast('Invite link copied'); }
    handleSpotlightClick() { /* noop */ }

    _toast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }
}