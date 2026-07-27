import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import defaultAvatar from '@salesforce/resourceUrl/AlumniAlt';

import getNotifications from '@salesforce/apex/KenNotificationController.getNotifications';
import getUnreadCount from '@salesforce/apex/KenNotificationController.getUnreadCount';
import fetchNotifications from '@salesforce/apex/KenNotificationController.fetchNotifications';
import markAsRead from '@salesforce/apex/KenNotificationController.markAsRead';
import getNetworkData from '@salesforce/apex/KenNetworkController.getNetworkData';
import respondToConnectionRequests from '@salesforce/apex/KenNetworkController.respondToConnectionRequests';
import respondToMentorshipRequest from '@salesforce/apex/KenMentorshipController.respondToMentorshipRequest';
import respondToCallRequest from '@salesforce/apex/KenMentorshipController.respondToCallRequest';

const PAGE_SIZE  = 10;
const MAX_FEED   = 10;
const TOAST_MS   = 5000;
const DEFAULT_INTERVAL_MS = 60 * 1000;

// ──────────────────────────────────────────────────────────────────────────────
// Module-level heartbeat singleton.
//
// kenPageHeader.html renders <c-ken-notification> twice (once in the mobile
// layout, once in the desktop layout) — CSS hides one based on viewport but
// BOTH LWC instances mount, so a per-instance setInterval would poll twice.
// Hoist the timer to module scope: first instance to mount starts it, all
// instances subscribe for count updates, last one to unmount tears it down.
// ──────────────────────────────────────────────────────────────────────────────
let _hbTimer = null;
let _hbIntervalMs = DEFAULT_INTERVAL_MS;
let _hbInFlight = false;
const _hbSubscribers = new Set();

async function _runHeartbeatTick() {
    if (document.hidden || _hbInFlight) return;
    _hbInFlight = true;
    try {
        const result = await fetchNotifications();
        if (!result) return;
        _hbSubscribers.forEach((cb) => {
            try { cb(result); } catch (e) { /* don't let one instance break another */ }
        });
        const configured = (result.pollIntervalSeconds || 60) * 1000;
        if (configured !== _hbIntervalMs && _hbTimer) {
            _hbIntervalMs = configured;
            window.clearInterval(_hbTimer);
            _hbTimer = window.setInterval(_runHeartbeatTick, _hbIntervalMs);
        }
    } catch (e) {
        console.warn('[KenNotif] heartbeat failed', e);
    } finally {
        _hbInFlight = false;
    }
}

function _ensureHeartbeat(subscriber) {
    _hbSubscribers.add(subscriber);
    if (_hbTimer) return; // Another instance already owns the timer.
    _runHeartbeatTick(); // First tick fires immediately.
    _hbTimer = window.setInterval(_runHeartbeatTick, _hbIntervalMs);
}

function _releaseHeartbeat(subscriber) {
    _hbSubscribers.delete(subscriber);
    if (_hbSubscribers.size === 0 && _hbTimer) {
        window.clearInterval(_hbTimer);
        _hbTimer = null;
    }
}

export default class KenNotification extends NavigationMixin(LightningElement) {
    @track isOpen = false;
    @track activeTab = 'notifications';

    @track _notifications = [];
    @track _unreadCount = 0;
    @track _connectionRequests = [];
    @track _pendingIds = {};
    // rowId -> 'accept' | 'reject', set optimistically on click so the row shows
    // "Accepted"/"Declined" immediately instead of being removed — removing it
    // outright could flicker back if a background fetchFeed() lands mid-flight.
    @track _resolvedActions = {};
    @track toast = null;

    _boundOnWindowClick;
    _boundOnKeydown;
    _boundOnVisibilityChange;
    _toastTimer;
    _audioCtx;
    _previousTopId = null;
    _feedFetchInFlight = false;
    _heartbeatSubscriber = null;

    loadNetworkData() {
        return getNetworkData()
            .then((result) => {
                this._connectionRequests = (result && result.connectionRequests) || [];
            })
            .catch(() => {
                this._connectionRequests = [];
            });
    }

    connectedCallback() {
        this._boundOnWindowClick = this.handleWindowClick.bind(this);
        this._boundOnKeydown = this.handleKeydown.bind(this);
        this._boundOnVisibilityChange = this.handleVisibilityChange.bind(this);
        window.addEventListener('click', this._boundOnWindowClick);
        window.addEventListener('keydown', this._boundOnKeydown);
        document.addEventListener('visibilitychange', this._boundOnVisibilityChange);
        // Subscribe to the shared module heartbeat. First instance to subscribe
        // starts the singleton timer; the rest just attach a callback.
        this._heartbeatSubscriber = (result) => this.applyHeartbeat(result);
        _ensureHeartbeat(this._heartbeatSubscriber);
    }

    disconnectedCallback() {
        window.removeEventListener('click', this._boundOnWindowClick);
        window.removeEventListener('keydown', this._boundOnKeydown);
        document.removeEventListener('visibilitychange', this._boundOnVisibilityChange);
        if (this._heartbeatSubscriber) {
            _releaseHeartbeat(this._heartbeatSubscriber);
            this._heartbeatSubscriber = null;
        }
        this.clearToastTimer();
    }

    handleVisibilityChange() {
        // Returning to the tab → force an immediate tick of the shared timer.
        if (!document.hidden) {
            _runHeartbeatTick();
        }
    }

    /**
     * Called by the module-level singleton on every successful heartbeat. The
     * Apex method returns { unreadCount, hasNew, pollIntervalSeconds } — we
     * only consume the count here. Interval reconfig is handled inside the
     * singleton itself.
     */
    applyHeartbeat(result) {
        if (!result) return;
        const newCount = result.unreadCount || 0;
        const grew = newCount > (this._unreadCount || 0);
        this._unreadCount = newCount;
        if (grew && this.isOpen) {
            this.fetchFeed();
        }
    }

    /**
     * Lazy fetch of the visible feed. Fires only when the user actually opens the
     * bell, or when the heartbeat reports growth while the panel is already open.
     * Coalesces concurrent calls so a quick double-click doesn't spawn two fetches.
     */
    fetchFeed() {
        if (this._feedFetchInFlight) return Promise.resolve();
        this._feedFetchInFlight = true;
        return Promise.all([
            getNotifications({ pageSize: PAGE_SIZE, offsetCount: 0 }),
            getUnreadCount(),
            this.loadNetworkData()
        ]).then(([rows, count]) => {
            this._notifications = rows || [];
            // User-initiated fetch refreshes the badge too — without this the badge
            // would stay stale after accept/reject or mark-read until the next heartbeat.
            this._unreadCount = count || 0;
            const newTopId = this._notifications.length ? this._notifications[0].id : null;
            this._previousTopId = newTopId;
        }).catch((e) => {
            console.warn('[KenNotif] feed fetch failed', e);
        }).finally(() => {
            this._feedFetchInFlight = false;
        });
    }

    // ─── Toast popup ──────────────────────────────────────────────────────

    showToastForLatest(dto) {
        if (!dto) return;
        this.toast = {
            id: dto.id,
            title: dto.title,
            body: dto.body,
            imageUrl: dto.imageUrl || defaultAvatar
        };
        this.clearToastTimer();
        this.toastTimer = setTimeout(() => {
            this.toast = null;
        }, TOAST_MS);
    }

    clearToastTimer() {
        if (this.toastTimer) {
            clearTimeout(this.toastTimer);
            this.toastTimer = null;
        }
    }

    handleToastClick() {
        this.toast = null;
        this.clearToastTimer();
        this.isOpen = true;
        this.activeTab = 'notifications';
        this.fetchFeed();
    }

    handleToastClose(event) {
        event?.stopPropagation();
        this.toast = null;
        this.clearToastTimer();
    }

    // ─── Sound ────────────────────────────────────────────────────────────

    playSound() {
        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            if (!Ctx) return;
            if (!this._audioCtx) this._audioCtx = new Ctx();
            const ctx = this._audioCtx;
            const o = ctx.createOscillator();
            const g = ctx.createGain();
            o.connect(g);
            g.connect(ctx.destination);
            o.type = 'sine';
            o.frequency.setValueAtTime(880, ctx.currentTime);
            o.frequency.exponentialRampToValueAtTime(660, ctx.currentTime + 0.18);
            g.gain.setValueAtTime(0.18, ctx.currentTime);
            g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.32);
            o.start();
            o.stop(ctx.currentTime + 0.32);
        } catch (e) {
            // Auto-play policy / unsupported context — silently skip
        }
    }

    // ─── Tab data ─────────────────────────────────────────────────────────

    get notifications() {
        // Notifications tab is sourced ONLY from Ken_Notification__c. A connection
        // request already has its own "sent you a connection request" notification
        // row (created by the trigger), so we must NOT also merge the raw
        // Ken_Network_Connection__c request here — that produced two rows for one
        // request. The raw pending requests still drive the Connection Requests tab.
        return (this._notifications || [])
            .map((n) => this.decorateNotification(n))
            .sort((a, b) => this.timestamp(b.createdDate) - this.timestamp(a.createdDate))
            .slice(0, MAX_FEED);
    }

    get connectionRequests() {
        // Dedicated Connection Requests tab: Ken_Network_Connection__c rows only.
        const rows = (this._connectionRequests || []).map((r) => ({
            id: 'cn-' + r.id,
            kind: 'network_connection',
            sourceId: r.id,
            personAccountId: r.personAccountId,
            name: r.name,
            subtitle: 'has requested to connect.',
            time: this.timeAgo(r.requestDateTime),
            avatarUrl: r.profileImage || defaultAvatar,
            createdDate: r.requestDateTime,
            groupLabel: this.groupLabel(r.requestDateTime),
            isPending: !!this._pendingIds['cn-' + r.id]
        }));
        return rows.sort((a, b) => this.timestamp(b.createdDate) - this.timestamp(a.createdDate));
    }

    get groupedConnectionRequests() {
        const groups = new Map();
        this.connectionRequests.forEach((r) => {
            const label = r.groupLabel || 'Today';
            if (!groups.has(label)) groups.set(label, []);
            groups.get(label).push(r);
        });
        const order = ['Today', 'Yesterday'];
        const result = [];
        order.forEach((label) => {
            const items = groups.get(label);
            if (items && items.length) result.push({ label, items });
        });
        groups.forEach((items, label) => {
            if (order.includes(label)) return;
            if (items?.length) result.push({ label, items });
        });
        return result;
    }

    decorateNotification(n) {
        const id = 'nf-' + n.id;
        // Most notifications are click-to-navigate. Mentorship + Network connection
        // request rows get inline Accept/Reject — same UX as the Connection Requests
        // tab rows. Each kind routes to a different Apex method via dispatchAction.
        const titleLower = (n.title || '').toLowerCase();
        const isMentorshipRequest = n.category === 'Mentorship' && titleLower.includes('requested mentorship');
        const isMentorshipCallRequest = n.category === 'Mentorship' && titleLower.includes('mentorship call');
        const isNetworkConnectionRequest = n.category === 'Network' && titleLower.includes('sent you a connection request');
        let actionKind = null;
        let extractedId = null;
        // Mentorship request/call rows are actionable only while UNREAD. Accepting or
        // rejecting marks the notification read (server markRelatedAsRead + client
        // markAsRead), so on the next fetch the row renders as a plain notification
        // instead of coming back with Accept/Reject buttons.
        if (isMentorshipCallRequest && !n.isRead) {
            actionKind = 'mentorship_call_request';
            extractedId = this.extractMentorshipIdFromUrl(n.targetUrl);
        } else if (isMentorshipRequest && !n.isRead) {
            actionKind = 'mentorship_request';
            extractedId = this.extractMentorshipIdFromUrl(n.targetUrl);
        } else if (isNetworkConnectionRequest) {
            // Only actionable while the connection is still pending. Once accepted or
            // rejected the connection leaves _connectionRequests, so the row renders as
            // a plain (read) notification instead of coming back with Accept/Decline.
            const connId = this.extractProfileIdFromUrl(n.targetUrl);
            const pendingConnIds = new Set((this._connectionRequests || []).map((r) => String(r.id)));
            if (connId && pendingConnIds.has(String(connId))) {
                actionKind = 'network_connection';
                extractedId = connId;
            }
        }
        const hasInlineAction = !!(actionKind && extractedId);
        const resolvedAction = this._resolvedActions[id];
        const respondedLabel = resolvedAction === 'accept' ? 'Accepted'
            : resolvedAction === 'reject' ? 'Declined'
            : null;
        return {
            id,
            kind: hasInlineAction ? actionKind : 'notification',
            sourceId: hasInlineAction ? extractedId : n.id,
            notificationId: n.id,
            category: n.category,
            title: n.title,
            subtitle: n.body,
            time: this.timeAgo(n.createdDate),
            unread: !n.isRead,
            imageUrl: n.imageUrl || defaultAvatar,
            showActions: hasInlineAction && !resolvedAction,
            respondedLabel,
            targetUrl: n.targetUrl,
            createdDate: n.createdDate,
            rowClass: 'row row--notif' + (n.isRead ? '' : ' row--unread'),
            isPending: hasInlineAction ? !!this._pendingIds[id] : false,
            isInformational: !hasInlineAction,
            _isRead: n.isRead
        };
    }

    // Mentorship templates emit /mentorship?recordId=<Ken_Mentorship__c.Id>
    extractMentorshipIdFromUrl(url) {
        if (!url) return null;
        const match = String(url).match(/recordId=([a-zA-Z0-9]{15,18})/);
        return match ? match[1] : null;
    }

    // Network templates emit /network?profileId=<Ken_Connections__c.Id>
    extractProfileIdFromUrl(url) {
        if (!url) return null;
        const match = String(url).match(/profileId=([a-zA-Z0-9]{15,18})/);
        return match ? match[1] : null;
    }

    // ─── Misc UI getters ──────────────────────────────────────────────────

    get hasUnread() {
        return this._unreadCount > 0 || (this.connectionRequests?.length || 0) > 0;
    }

    get unreadBadge() {
        const count = (this._unreadCount || 0) + (this._connectionRequests?.length || 0);
        if (count <= 0) return '';
        return count > 99 ? '99+' : String(count);
    }

    get hasNotifications() {
        return this.notifications.length > 0;
    }

    get hasConnectionRequests() {
        return this.connectionRequests.length > 0;
    }

    get triggerClass() {
        return this.isOpen ? 'trigger trigger--open' : 'trigger';
    }

    get isNotificationsTab() {
        return this.activeTab === 'notifications';
    }

    get isRequestsTab() {
        return this.activeTab === 'requests';
    }

    get notificationsTabClass() {
        return this.isNotificationsTab ? 'tab tab--active' : 'tab';
    }

    get requestsTabClass() {
        return this.isRequestsTab ? 'tab tab--active' : 'tab';
    }

    get hasToast() {
        return !!this.toast;
    }

    get toastImageUrl() {
        return this.toast ? this.toast.imageUrl : null;
    }

    get toastTitle() {
        return this.toast ? this.toast.title : '';
    }

    get toastBody() {
        return this.toast ? this.toast.body : '';
    }

    // ─── Toggle / outside-click / escape ──────────────────────────────────

    toggleOpen(event) {
        event?.stopPropagation();
        this.isOpen = !this.isOpen;
        if (this.isOpen) {
            this.fetchFeed();
        }
    }

    openNotificationsTab(event) {
        event?.stopPropagation();
        this.activeTab = 'notifications';
    }

    openRequestsTab(event) {
        event?.stopPropagation();
        this.activeTab = 'requests';
        // Lazy-refresh network data when the user actually views this tab.
        this.loadNetworkData();
    }

    handleWindowClick(event) {
        if (!this.isOpen) return;
        const root = this.template.querySelector('[data-root]');
        if (!root) return;
        if (!root.contains(event.target)) {
            this.isOpen = false;
        }
    }

    handleKeydown(event) {
        if (!this.isOpen) return;
        if (event.key === 'Escape') {
            this.isOpen = false;
        }
    }

    // ─── Accept / Reject (works in both tabs) ─────────────────────────────

    async handleAccept(event) {
        event?.stopPropagation();
        const target = event?.currentTarget;
        if (!target) return;
        await this.dispatchAction(
            target.dataset.id,
            target.dataset.kind,
            target.dataset.sourceId,
            'accept'
        );
    }

    async handleDecline(event) {
        event?.stopPropagation();
        const target = event?.currentTarget;
        if (!target) return;
        await this.dispatchAction(
            target.dataset.id,
            target.dataset.kind,
            target.dataset.sourceId,
            'reject'
        );
    }

    async dispatchAction(rowId, kind, sourceId, action) {
        if (!rowId || !kind || !sourceId) return;
        if (this._pendingIds[rowId]) return;
        if (
            kind !== 'network_connection' &&
            kind !== 'mentorship_request' &&
            kind !== 'mentorship_call_request'
        ) return;

        // Find the row up front so we know which notification (if any) to clear.
        const row = (this.notifications || []).find((r) => r.id === rowId) ||
                    (this.connectionRequests || []).find((r) => r.id === rowId);
        const notificationId = row ? row.notificationId : null;

        // Snapshot so we can restore the pending connection request if the
        // Apex call turns out to fail.
        const previousConnectionRequests = this._connectionRequests;

        this._pendingIds = { ...this._pendingIds, [rowId]: true };

        // Show "Accepted"/"Declined" on the row right away, before the server
        // round-trip. This is deliberately NOT a removal from _notifications —
        // removing the row outright meant a background fetchFeed() landing
        // moments later (from the heartbeat, or this same flow) could overwrite
        // it with server data and make the row flicker back with active
        // buttons. Labeling the row instead means even a full refresh is safe:
        // once the server confirms the notification is read, decorateNotification
        // hides the buttons anyway — this label is just the instant version of
        // that same outcome.
        this._resolvedActions = { ...this._resolvedActions, [rowId]: action };

        // The Connection Requests tab is pending-only by design, so that row
        // can safely disappear immediately rather than needing a label.
        if (kind === 'network_connection') {
            this._connectionRequests = (this._connectionRequests || []).filter(
                (r) => r.id !== sourceId
            );
        }

        try {
            if (kind === 'network_connection') {
                await respondToConnectionRequests({ requestIds: [sourceId], action });
            } else if (kind === 'mentorship_request') {
                await respondToMentorshipRequest({ mentorshipId: sourceId, action });
            } else if (kind === 'mentorship_call_request') {
                await respondToCallRequest({ callRequestId: sourceId, action });
            }
            if (notificationId) {
                try { await markAsRead({ notificationIds: [notificationId] }); } catch (e) { /* swallow */ }
            }
            await this.fetchFeed();
        } catch (e) {
            // The request didn't actually go through — undo the optimistic
            // label and restore the pending connection request row.
            const nextResolved = { ...this._resolvedActions };
            delete nextResolved[rowId];
            this._resolvedActions = nextResolved;
            this._connectionRequests = previousConnectionRequests;
            // eslint-disable-next-line no-console
            console.error('Action dispatch failed', e);
        } finally {
            const next = { ...this._pendingIds };
            delete next[rowId];
            this._pendingIds = next;
        }
    }

    // ─── Notification row click (mark read + navigate) ────────────────────

    async handleNotificationClick(event) {
        const id = event?.currentTarget?.dataset?.id;
        const row = this.notifications.find((n) => n.id === id);
        if (!row) return;
        // Don't navigate / mark-read when click happened on an action button.
        if (event.target.closest('.actions')) return;

        if (row.kind === 'notification' && !row._isRead) {
            try {
                await markAsRead({ notificationIds: [row.notificationId] });
                await this.fetchFeed();
            // Heartbeat will refresh the badge on its next tick; nudge it sooner
            // via a direct fetch so the user sees the count update immediately.
            } catch (e) {
                // ignore
            }
        }
        this.navigateForRow(row);
    }

    /**
     * Generic navigation driven entirely by the notification's targetUrl:
     *   - http(s):// → external link, opens in new tab
     *   - leading '/'  → community-relative path, prepended with community basePath
     *   - empty       → informational notification, no navigation
     */
    navigateForRow(row) {
        if (!row.targetUrl) return;
        const url = row.targetUrl;
        this.isOpen = false;
        if (/^https?:\/\//i.test(url)) {
            window.open(url, '_blank');
            return;
        }
        const basePath = this.getCommunityBasePath();
        const path = url.startsWith('/') ? url : '/' + url;
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: basePath + path }
        });
    }

    // Mirrors the helper in kenPageHeader — derives /alumni/s style base path.
    getCommunityBasePath() {
        const pathname = (typeof window !== 'undefined' && window.location)
            ? window.location.pathname : '/';
        const parts = pathname.split('/').filter(Boolean);
        if (!parts.length) return '/';
        const sIndex = parts.indexOf('s');
        if (sIndex > 0) return `/${parts.slice(0, sIndex + 1).join('/')}`;
        return `/${parts[0]}`;
    }

    // ─── Time + grouping helpers ──────────────────────────────────────────

    timestamp(value) {
        if (!value) return 0;
        const n = new Date(value).getTime();
        return isNaN(n) ? 0 : n;
    }

    timeAgo(value) {
        if (!value) return '';
        const ms = Date.now() - new Date(value).getTime();
        if (ms < 0) return 'just now';
        const m = Math.floor(ms / 60000);
        if (m < 1) return 'just now';
        if (m < 60) return `${m} mins ago`;
        const h = Math.floor(m / 60);
        if (h < 24) return `${h} hr ago`;
        const d = Math.floor(h / 24);
        if (d < 7) return `${d} day${d === 1 ? '' : 's'} ago`;
        try {
            return new Date(value).toLocaleDateString(undefined, { day: '2-digit', month: 'short' });
        } catch (e) {
            return '';
        }
    }

    groupLabel(value) {
        if (!value) return 'Today';
        const d = new Date(value);
        if (isNaN(d.getTime())) return 'Today';
        const today = new Date();
        const yesterday = new Date();
        yesterday.setDate(today.getDate() - 1);
        const ymd = (x) => `${x.getFullYear()}-${x.getMonth()}-${x.getDate()}`;
        if (ymd(d) === ymd(today)) return 'Today';
        if (ymd(d) === ymd(yesterday)) return 'Yesterday';
        try {
            return d.toLocaleDateString(undefined, { day: '2-digit', month: 'short' });
        } catch (e) {
            return 'Earlier';
        }
    }

}