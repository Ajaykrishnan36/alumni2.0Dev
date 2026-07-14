// V2 wiring — calls OLD KenNotificationController. Do not modify the OLD controller.
// Imperative (not @wire) so the same pattern works whether the OLD method is
// cacheable=true (getNotifications) or not (markAsRead/markAllAsRead).
// Mock RAW data is preserved as the rendering fallback if Apex returns nothing.
import { LightningElement, track } from 'lwc';
import getNotifications from '@salesforce/apex/KenNotificationController.getNotifications';
import markAsRead from '@salesforce/apex/KenNotificationController.markAsRead';
import markAllAsRead from '@salesforce/apex/KenNotificationController.markAllAsRead';

// Mock notification list removed — page shows empty state until Apex returns real data.

const INITIALS_BY_TAG = {
    REUNION: 'R', EVENT: 'E', STORY: 'S', CAMPUS: 'C', MENTOR: 'M', NEWS: 'N',
    AWARD: 'A', MOVE: 'M', COHORT: 'C', RECAP: 'R', ACTION: 'A', FEE: 'F'
};

// Pick a tone for a category — falls back to a rotating palette so colors stay varied.
const TONE_BY_CATEGORY = {
    'Event': 'amber',
    'Network': 'violet',
    'Mentorship': 'emerald',
    'Story': 'rose',
    'Campus': 'emerald',
    'News': 'sky',
    'Award': 'violet',
    'System': 'sky'
};
const TONE_ROTATION = ['violet', 'amber', 'rose', 'emerald', 'sky'];

export default class KenNotificationsV2 extends LightningElement {
    @track activeTab = 'all';

    @track notifications = []; // mapped DTOs from OLD Apex
    @track useLiveData = true; // becomes false only if Apex errors
    @track isLoading = true;
    @track loadError = null;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const VALID_TABS = ['all', 'unread', 'mentions', 'system'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.activeTab = tab;
        } catch (e) { /* ignore */ }
        this.loadNotifications();
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeTab && this.activeTab !== 'all') params.set('tab', this.activeTab); else params.delete('tab');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    handleTabChange(event) {
        const key = event && event.currentTarget && event.currentTarget.dataset
            ? event.currentTarget.dataset.key
            : null;
        if (!key) return;
        this.activeTab = key;
        this.syncUrl();
    }

    loadNotifications() {
        this.isLoading = true;
        getNotifications({ pageSize: 50, offsetCount: 0 })
            .then(rows => {
                this.notifications = Array.isArray(rows) ? rows.map((n, i) => this.mapDto(n, i)) : [];
                this.useLiveData = true;
                this.loadError = null;
                this.isLoading = false;
            })
            .catch(err => {
                // Apex genuinely failed — fall back to mock RAW so the page is usable.
                this.loadError = err;
                this.useLiveData = false;
                this.isLoading = false;
                // eslint-disable-next-line no-console
                console.error('KenNotificationController.getNotifications error, using mock fallback', err);
            });
    }

    get hasNotifications() { return (this._sourceRows || []).length > 0; }
    get showEmptyState() { return !this.isLoading && !this.hasNotifications && !this.loadError; }

    // Translate OLD NotificationDTO → row shape rendered by the template.
    mapDto(n, i) {
        const cat = (n.category || '').trim();
        const tone = TONE_BY_CATEGORY[cat] || TONE_ROTATION[i % TONE_ROTATION.length];
        const tag = (cat || 'NOTIF').toUpperCase();
        return {
            id: n.id,
            tag,
            tone,
            time: this.formatTime(n.createdDate),
            headline: n.title || n.body || '',
            unread: n.isRead === false,
            cta: 'View',
            targetUrl: n.targetUrl
        };
    }

    formatTime(createdDate) {
        if (!createdDate) return '';
        const d = new Date(createdDate);
        if (isNaN(d.getTime())) return '';
        const now = Date.now();
        const diffMs = now - d.getTime();
        const day = 24 * 60 * 60 * 1000;
        if (diffMs < day) return 'Today';
        const days = Math.floor(diffMs / day);
        if (days < 7) return `${days}d`;
        if (days < 30) return `${Math.floor(days / 7)}w`;
        if (days < 365) return `${Math.floor(days / 30)}mo`;
        return `${Math.floor(days / 365)}y`;
    }

    get tabs() {
        return [
            { key: 'all',      label: 'All',      cls: this._tabClass('all') },
            { key: 'unread',   label: 'Unread',   cls: this._tabClass('unread') },
            { key: 'mentions', label: 'Mentions', cls: this._tabClass('mentions') },
            { key: 'system',   label: 'System',   cls: this._tabClass('system') }
        ];
    }

    _tabClass(key) {
        return key === this.activeTab ? 'notif-tab notif-tab--active' : 'notif-tab';
    }

    // Source: live notifications only — no mock fallback.
    get _sourceRows() {
        return this.notifications || [];
    }

    get rows() {
        return this._sourceRows.map((n, i) => {
            const rowClass = n.unread ? 'notif-row notif-row--unread' : 'notif-row';
            const pillClass = `notif-pill notif-pill--${n.tone}`;
            const thumbClass = `notif-thumb notif-thumb--${n.tone}`;
            return {
                key: n.id ? `n-${n.id}` : `n-${i}`,
                id: n.id,
                rowClass,
                pillClass,
                thumbClass,
                initial: INITIALS_BY_TAG[n.tag] || (n.tag || 'N').charAt(0),
                tag: n.tag,
                time: n.time,
                headline: n.headline,
                cta: n.cta,
                isUnread: n.unread
            };
        });
    }

    handleMarkAll() {
        markAllAsRead()
            .then(() => { this.loadNotifications(); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenNotificationController.markAllAsRead error', err);
            });
    }

    handleRowClick(event) {
        const id = event.currentTarget && event.currentTarget.dataset
            ? event.currentTarget.dataset.id
            : null;
        if (!id || String(id).startsWith('mock-')) return;
        markAsRead({ notificationIds: [id] })
            .then(() => { this.loadNotifications(); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenNotificationController.markAsRead error', err);
            });
    }
}