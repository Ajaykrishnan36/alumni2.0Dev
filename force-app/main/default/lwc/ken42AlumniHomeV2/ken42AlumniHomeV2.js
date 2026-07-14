import basePath from '@salesforce/community/basePath';
import { LightningElement, api, track } from 'lwc';
import getUserDashboardState from '@salesforce/apex/KenHomeController.getUserDashboardState';
import getActionItems        from '@salesforce/apex/KenHomeController.getActionItems';
import getQuickActions       from '@salesforce/apex/KenHomeController.getQuickActions';
import getHomeFeed           from '@salesforce/apex/KenHomeController.getHomeFeed';
import getSpotlight          from '@salesforce/apex/KenHomeController.getSpotlight';

/* Tone rotation used to colour Apex-driven items (kept consistent with prior visual language). */
const ROW_TONES   = ['violet', 'sky', 'emerald', 'amber', 'rose', 'indigo'];
const QA_TONES    = ['violet', 'sky', 'indigo', 'emerald', 'amber', 'rose'];
const FEED_TONES  = ['violet', 'amber', 'rose', 'emerald', 'sky'];
const PILL_TONES  = ['em', 'am', 'vi', 'sk'];

const SEVERITY_TO_TONE = { high: 'rose', medium: 'amber', low: 'sky' };

export default class Ken42AlumniHomeV2 extends LightningElement {
    @api userFirstName = '';
    @api userLastName  = '';
    @api viewMode; // optional override; if blank, use Apex-resolved phase

    @track state;
    @track _actionItems  = [];
    @track _quickActions = [];
    @track _feedItems    = [];
    @track _spotlight    = {};
    @track isLoading     = true;
    @track loadError;

    connectedCallback() {
        this.loadAll();
    }

    async loadAll() {
        this.isLoading = true;
        try {
            const state = await getUserDashboardState();
            this.state = state || { phase: 'Verify', insights: [], profileCompleteness: 0 };

            const phase = (this.viewMode === 'connect') ? 'Connect'
                        : (this.viewMode === 'verify')  ? 'Verify'
                        : (this.state.phase || 'Verify');
            this.state.phase = phase;

            if (this.state.userFirstName && !this.userFirstName) this.userFirstName = this.state.userFirstName;
            if (this.state.userLastName  && !this.userLastName)  this.userLastName  = this.state.userLastName;

            const [items, actions, feed, spotlight] = await Promise.all([
                getActionItems({ phase }),
                getQuickActions({ phase }),
                getHomeFeed(),
                getSpotlight()
            ]);
            this._actionItems  = Array.isArray(items)   ? items   : [];
            this._quickActions = Array.isArray(actions) ? actions : [];
            this._feedItems    = Array.isArray(feed)    ? feed    : [];
            this._spotlight    = spotlight || {};
        } catch (err) {
            // Never blank the home — log and render with safe defaults.
            // eslint-disable-next-line no-console
            console.error('ken42AlumniHomeV2.loadAll error', err);
            this.loadError = (err && err.body && err.body.message) || (err && err.message) || 'Unable to load dashboard';
            if (!this.state) this.state = { phase: 'Verify', insights: [], profileCompleteness: 0 };
        } finally {
            this.isLoading = false;
        }
    }

    // ──────────────── Phase getters ────────────────
    get phase() { return (this.state && this.state.phase) || 'Verify'; }
    get isVerifyPhase()  { return this.phase === 'Verify'; }
    get isConnectPhase() { return this.phase === 'Connect'; }

    // Back-compat aliases used by template
    get isVerifyState()  { return this.isVerifyPhase; }
    get isConnectState() { return this.isConnectPhase; }

    get profileCompleteness() {
        return (this.state && Number.isFinite(this.state.profileCompleteness))
            ? this.state.profileCompleteness : 0;
    }
    get progressStyle() {
        return `width: ${this.profileCompleteness}%;`;
    }

    // ──────────────── For-You bar (chips) ────────────────
    get forYouSub() {
        if (this.isVerifyPhase && this.state && this.state.batchLabel) {
            return `Match found · ${this.state.batchLabel}`;
        }
        return this.isVerifyPhase ? 'Welcome back — finish setup' : 'Highlights from your network and KU';
    }
    get forYouCta() { return this.isVerifyPhase ? 'Continue setup →' : '✈ Share an update'; }
    get chips() {
        const insights = (this.state && Array.isArray(this.state.insights)) ? this.state.insights : [];
        return insights.map((p, idx) => {
            const tone = PILL_TONES[idx % PILL_TONES.length];
            return {
                key: p.id || `c${idx}`,
                tone,
                icon: p.icon || '·',
                label: p.label || '',
                chipClass: `fyr-chip fyr-chip--${tone}`
            };
        });
    }

    // ──────────────── Middle card (Checklist OR Attention) ────────────────
    get middleLeftTitle()  { return this.isVerifyPhase ? 'Finish setup' : 'Needs attention'; }
    get middleLeftSub() {
        const items = this._actionItems || [];
        if (this.isVerifyPhase) {
            const done = items.filter(i => i.completed).length;
            return `${done} of ${items.length} done`;
        }
        return `${items.length} need${items.length === 1 ? 's' : ''} action`;
    }
    get middleLeftHeadSymbol() { return this.isVerifyPhase ? '✓' : '⚠'; }
    get middleLeftHeadTone()   { return this.isVerifyPhase ? 'em' : 'am'; }

    /** Mapped to kenHomeChecklistCardV2's row shape (id/icon/title/desc/toneLabel/stTone/action/primary/iconClass/statusClass/btnClass). */
    get middleLeftRows() {
        const items = this._actionItems || [];
        return items.map((i, idx) => {
            const tone = SEVERITY_TO_TONE[(i.severity || 'low').toLowerCase()] || ROW_TONES[idx % ROW_TONES.length];
            const stTone = i.completed ? 'emerald' : tone;
            return {
                key: i.id || `r${idx}`,
                icon: i.completed ? '✓' : '•',
                title: i.title || '',
                desc: i.description || '',
                toneLabel: i.completed ? 'Done' : (i.ctaLabel || 'Action'),
                action: i.completed ? 'View' : (i.ctaLabel || 'Open'),
                primary: !i.completed,
                iconClass: `row-ico ico-${tone}`,
                statusClass: `row-status st-${stTone}`,
                btnClass: i.completed ? 'row-btn row-btn--ghost' : 'row-btn'
            };
        });
    }

    /** Items consumed directly by kenHomeAttentionCardV2 (uses its own severity decoration). */
    get attentionItems() { return this._actionItems || []; }

    // ──────────────── Quick actions ────────────────
    get quickTitle() { return 'Quick actions'; }
    get quickSub()   { return this.isVerifyPhase ? 'Most-used while activating' : 'Most-used by alumni'; }
    get quickActions() {
        const list = this._quickActions || [];
        return list.map((q, idx) => {
            const tone = QA_TONES[idx % QA_TONES.length];
            return {
                key: q.id || `q${idx}`,
                icon: q.icon || '•',
                label: q.label || '',
                desc: '',
                iconClass: `qa-tile__ico qa-ic-${tone}`,
                targetUrl: q.targetUrl
            };
        });
    }

    // ──────────────── Feed ────────────────
    get feedItems() {
        const list = this._feedItems || [];
        const ICON = { EVENT: '📅', GROUP: '👥', JOB: '💼', MENTORSHIP: '🎓', NEWS: '📰', SYSTEM: '🔔' };
        const TONE_BG = {
            violet: '#6d28d9', amber: '#d97706', rose: '#be123c',
            emerald: '#047857', sky: '#0369a1', indigo: '#4f46e5'
        };
        return list.map((f, idx) => {
            const tone = FEED_TONES[idx % FEED_TONES.length];
            const src = (f.source || 'NEWS').toUpperCase();
            return {
                key: f.id || `f${idx}`,
                img: f.imageUrl || '',
                hasImg: !!f.imageUrl,
                iconChar: ICON[src] || '📰',
                iconStyle: `background:${TONE_BG[tone] || '#6b7280'}`,
                tag: src.charAt(0).toUpperCase() + src.slice(1).toLowerCase(),
                tone,
                time: f.displayTime || '',
                title: f.title || '',
                tagClass: `feed-tag feed-tag--${tone}`,
                targetUrl: f.targetUrl
            };
        });
    }

    // ──────────────── Top "Upcoming event" card (Connect rail) ────────────────
    get topEvent() {
        const feed = this._feedItems || [];
        const first = feed.find(f => f.source === 'EVENT');
        if (!first) return null;
        return {
            title: first.title,
            date: first.displayTime,
            location: first.subtitle || '',
            targetUrl: first.targetUrl
        };
    }
    get hasTopEvent() { return !!this.topEvent; }

    // ──────────────── Spotlight + video (admin-swappable via Ken_Home_Spotlight__mdt) ────────────────
    get spotEyebrow()       { return this._spotlight.eyebrow || 'SPOTLIGHT'; }
    get spotName()          { return this._spotlight.personName || ''; }
    get spotMeta()          { return this._spotlight.meta || ''; }
    get spotlightQuote()    { return this._spotlight.quote || ''; }
    get spotCtaLabel()      { return this._spotlight.ctaLabel || 'Read full story'; }
    get spotSecondaryCta()  { return this._spotlight.secondaryCtaLabel || 'Nominate next month'; }
    get videoChipLabel()    { return this._spotlight.videoChip || '▶ WATCH'; }
    get videoTitle()        { return this._spotlight.videoTitle || ''; }
    get videoMeta()         { return this._spotlight.videoMeta || ''; }

    // ──────────────── Event handlers ────────────────
    _emit(label) {
        this.dispatchEvent(new CustomEvent('homeaction', {
            detail: { label, mode: this.phase },
            bubbles: true,
            composed: true
        }));
    }
    handleForYouCta()     { this._emit('for-you-cta'); }
    handleSpotlightRead() { this._emit('read-spotlight'); }
    handleNominate()      { this._emit('nominate'); }
    handlePlayVideo()     { this._emit('play-video'); }
    handleAllChecklist()  { this._emit('all-checklist'); }
    handleChecklistRow(e) {
        const key = (e && e.detail && e.detail.key) || '';
        const it = (this._actionItems || []).find(i => (i.id || '') === key);
        if (it && it.targetUrl) this._navigate(it.targetUrl);
        this._emit(`checklist:${key}`);
    }
    handleAttentionRow(e) {
        const url = e && e.detail && e.detail.url;
        if (url) this._navigate(url);
        this._emit(`attention:${(e && e.detail && e.detail.id) || ''}`);
    }
    handleQuickAction(e) {
        const key = e && e.detail && e.detail.key;
        const it = (this._quickActions || []).find(i => (i.id || '') === key);
        if (it && it.targetUrl) this._navigate(it.targetUrl);
        this._emit(`quick:${key || ''}`);
    }
    handleAllFeed() { this._emit('all-feed'); }
    handleFeedItem(e) {
        const key = e && e.detail && e.detail.key;
        const it = (this._feedItems || []).find(i => (i.id || '') === key);
        if (it && it.targetUrl) this._navigate(it.targetUrl);
        this._emit(`feed:${key || ''}`);
    }
    handleVerifyCta()  { this._navigate('/my-profile'); this._emit('continue-setup'); }
    handleConnectCta() {
        const t = this.topEvent;
        if (t && t.targetUrl) this._navigate(t.targetUrl);
        this._emit('rsvp');
    }

    _navigate(url) {
        if (!url) return;
        try {
            const base = (window.location && window.location.pathname) || '';
            // Strip trailing slash, append relative path; works inside LWR sites.
            const target = url.startsWith('http') ? url : url;
            window.location.assign(target.startsWith('/') ? basePath + target : target);
            // eslint-disable-next-line no-unused-vars
            const _ = base;
        } catch (_e) { /* no-op */ }
    }
}