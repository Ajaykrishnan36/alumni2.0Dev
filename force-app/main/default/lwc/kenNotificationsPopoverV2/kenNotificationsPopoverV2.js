import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getNotifications from '@salesforce/apex/KenNotificationController.getNotifications';
import getPendingRequests from '@salesforce/apex/KenNotificationController.getPendingRequests';
import processRequest from '@salesforce/apex/KenNotificationController.processRequest';

const PALETTE = ['#2563EB', '#7C3AED', '#DB2777', '#059669', '#D97706', '#0891B2'];

export default class KenNotificationsPopoverV2 extends LightningElement {
    activeTab = 'notifications';
    notifications = [];
    requests = [];
    processingId = null;

    _wiredNotifs;
    _wiredRequests;

    // Tab 1 — informational notifications (cacheable Apex → safe for @wire in LWR).
    @wire(getNotifications, { pageSize: 50, offsetCount: 0 })
    wiredNotifs(result) {
        this._wiredNotifs = result;
        if (result.data) this.notifications = result.data;
    }

    // Tab 2 — pending approvals across network / mentorship / group.
    @wire(getPendingRequests)
    wiredRequests(result) {
        this._wiredRequests = result;
        if (result.data) this.requests = result.data;
    }

    /* ----- tab state ----- */
    get isNotifTab() { return this.activeTab === 'notifications'; }
    get isReqTab() { return this.activeTab === 'requests'; }
    get notifTabClass() { return this.isNotifTab ? 'np-tab np-tab--active' : 'np-tab'; }
    get reqTabClass() { return this.isReqTab ? 'np-tab np-tab--active' : 'np-tab'; }
    showNotifTab() { this.activeTab = 'notifications'; }
    showReqTab() { this.activeTab = 'requests'; }

    // Tab 1 is strictly informational. Network / Mentorship / Group notifications
    // are actionable approvals — those belong to Tab 2 (getPendingRequests), so we
    // exclude those categories here to keep the two tabs cleanly separated.
    get tab1Notifications() {
        const EXCLUDE = new Set(['Network', 'Mentorship', 'Group']);
        return (this.notifications || []).filter(n => !EXCLUDE.has(n.category));
    }

    get hasNotifications() { return this.tab1Notifications.length > 0; }
    get hasRequests() { return this.requests && this.requests.length > 0; }

    /* ----- grouped + decorated lists ----- */
    get notifGroups() {
        return this._groupByDay(this.tab1Notifications).map(g => ({
            key: g.key, label: g.label,
            items: g.items.map(n => this._decorateNotif(n))
        }));
    }
    get requestGroups() {
        return this._groupByDay(this.requests).map(g => ({
            key: g.key, label: g.label,
            items: g.items.map(r => this._decorateRequest(r))
        }));
    }

    _decorateNotif(n) {
        const name = n.title || 'Notification';
        return {
            key: n.id,
            title: n.title,
            body: n.body,
            initial: (name.charAt(0) || '?').toUpperCase(),
            avatarStyle: `background:${this._color(name)}`,
            timeLabel: this._timeAgo(n.createdDate)
        };
    }
    _decorateRequest(r) {
        return {
            id: r.id,
            requesterName: r.requesterName,
            requesterInitial: r.requesterInitial || '?',
            avatarStyle: `background:${r.avatarColor || '#94A3B8'}`,
            fullMessage: r.context ? `${r.message} ${r.context}` : r.message,
            timeLabel: this._timeAgo(r.createdDate),
            busy: this.processingId === r.id
        };
    }

    /* ----- accept / decline ----- */
    handleAccept(event) { this._process(event.currentTarget.dataset.id, 'Accept'); }
    handleDecline(event) { this._process(event.currentTarget.dataset.id, 'Decline'); }

    _process(requestId, actionType) {
        if (!requestId || this.processingId) return;
        this.processingId = requestId;
        processRequest({ requestId, actionType })
            .then(() => refreshApex(this._wiredRequests))
            .then(() => {
                // Tell the shell to refresh the bell badge count.
                this.dispatchEvent(new CustomEvent('processed', { bubbles: true, composed: true }));
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenNotificationController.processRequest error', err);
            })
            .finally(() => { this.processingId = null; });
    }

    handleStop(event) { event.stopPropagation(); }

    /* ----- helpers ----- */
    _groupByDay(items) {
        const today = new Date(); today.setHours(0, 0, 0, 0);
        const yest = new Date(today); yest.setDate(yest.getDate() - 1);
        const buckets = { Today: [], Yesterday: [], Earlier: [] };
        (items || []).forEach(it => {
            let key = 'Earlier';
            if (it.createdDate) {
                const d = new Date(it.createdDate); d.setHours(0, 0, 0, 0);
                if (d.getTime() === today.getTime()) key = 'Today';
                else if (d.getTime() === yest.getTime()) key = 'Yesterday';
            }
            buckets[key].push(it);
        });
        return ['Today', 'Yesterday', 'Earlier']
            .filter(k => buckets[k].length)
            .map(k => ({ key: k, label: k, items: buckets[k] }));
    }

    _timeAgo(dt) {
        if (!dt) return '';
        const mins = Math.floor((Date.now() - new Date(dt).getTime()) / 60000);
        if (mins < 1) return 'just now';
        if (mins < 60) return `${mins} min${mins > 1 ? 's' : ''} ago`;
        const hrs = Math.floor(mins / 60);
        if (hrs < 24) return `${hrs} hr${hrs > 1 ? 's' : ''} ago`;
        const days = Math.floor(hrs / 24);
        if (days < 7) return `${days} day${days > 1 ? 's' : ''} ago`;
        try { return new Date(dt).toLocaleDateString(); } catch (e) { return ''; }
    }

    _color(seed) {
        let h = 0;
        const s = seed || '';
        for (let i = 0; i < s.length; i++) { h += s.charCodeAt(i); }
        return PALETTE[h % PALETTE.length];
    }
}