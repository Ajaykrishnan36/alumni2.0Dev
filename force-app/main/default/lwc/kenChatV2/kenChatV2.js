import basePath from '@salesforce/community/basePath';
import { LightningElement, track } from 'lwc';
import getThreads from '@salesforce/apex/KenChatV2Controller.getThreads';
import getMessages from '@salesforce/apex/KenChatV2Controller.getMessages';
import sendMessage from '@salesforce/apex/KenChatV2Controller.sendMessage';
import markRead from '@salesforce/apex/KenChatV2Controller.markRead';
import getOrCreateThreadWithContact from '@salesforce/apex/KenChatV2Controller.getOrCreateThreadWithContact';

const CHAT_HANDOFF_KEY = 'a2-chat-target';
const CHAT_HANDOFF_TTL_MS = 60000;

// Mock threads/messages removed — Chat renders empty state until Apex returns real data.

export default class KenChatV2 extends LightningElement {
    // Empty initial state so no mock flash; populated by connectedCallback.
    @track threadsState = [];
    @track messagesState = {};
    @track activeId = null;
    @track draft = '';
    @track searchQ = '';
    @track isLoading = true;
    @track toastMessage = '';
    @track toastVisible = false;
    _toastTimer = null;
    _pendingChatTarget = null;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const id = params.get('id');
            if (id) this.activeId = id;
        } catch (e) { /* ignore */ }
        // Handoff from Network / Business Directory "Message" buttons.
        try {
            const raw = sessionStorage.getItem(CHAT_HANDOFF_KEY);
            if (raw) {
                sessionStorage.removeItem(CHAT_HANDOFF_KEY);
                const target = JSON.parse(raw);
                if (target && target.contactId && (Date.now() - (target.ts || 0)) < CHAT_HANDOFF_TTL_MS) {
                    this._pendingChatTarget = target;
                }
            }
        } catch (e) { /* sandboxed or bad JSON — ignore */ }
        this.loadThreads();
    }

    /** Resolve a handoff target → thread Id, then auto-select it. */
    _resolvePendingTarget() {
        const target = this._pendingChatTarget;
        if (!target || !target.contactId) return;
        this._pendingChatTarget = null;
        this.isLoading = true;
        getOrCreateThreadWithContact({ targetId: target.contactId })
            .then(threadId => {
                if (!threadId) { this.isLoading = false; return; }
                // If thread isn't in current list (newly created), refresh threads first.
                const exists = this.threadsState.some(t => t.id === threadId);
                if (!exists) {
                    return getThreads().then(data => {
                        const list = Array.isArray(data) ? data.map(this._mapThread) : [];
                        this.threadsState = list;
                        this.activeId = threadId;
                        this.syncUrl();
                        this.loadMessages(threadId);
                        this._focusComposer();
                    });
                }
                this.activeId = threadId;
                this.syncUrl();
                this.threadsState = this.threadsState.map(t => t.id === threadId ? { ...t, unread: 0 } : t);
                this.loadMessages(threadId);
                this._focusComposer();
                return null;
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('getOrCreateThreadWithContact error', err);
                this.isLoading = false;
                // Apex now emits descriptive errors (Account id ending …xyz / Invalid prefix / etc.) — surface them.
                // Only swallow when there's no message body at all (network blip / unknown).
                const msg = err && err.body && err.body.message;
                if (msg) {
                    this._showToast(msg);
                }
            });
    }

    _focusComposer() {
        // Defer to next tick so the input is in the DOM.
        Promise.resolve().then(() => {
            try {
                const el = this.template.querySelector('lightning-input[data-role="composer"], input[data-role="composer"], textarea[data-role="composer"]');
                if (el && el.focus) el.focus();
            } catch (e) { /* ignore */ }
        });
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeId) params.set('id', String(this.activeId)); else params.delete('id');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    loadThreads() {
        this.isLoading = true;
        getThreads()
            .then(data => {
                const list = Array.isArray(data) ? data.map(this._mapThread) : [];
                this.threadsState = list;
                // Handoff takes precedence over URL / first-thread default.
                if (this._pendingChatTarget) {
                    this._resolvePendingTarget();
                    return;
                }
                // If URL specified an activeId that's actually in the list, keep it; otherwise default to first.
                if (list.length) {
                    const exists = this.activeId && list.some(t => t.id === this.activeId);
                    if (!exists) this.activeId = list[0].id;
                    this.syncUrl();
                    this.loadMessages(this.activeId);
                } else {
                    this.isLoading = false;
                }
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenChatV2Controller.getThreads error', err);
                this.threadsState = [];
                this.messagesState = {};
                this.activeId = null;
                this.syncUrl();
                this.isLoading = false;
            });
    }

    loadMessages(threadId) {
        if (!threadId) { this.isLoading = false; return; }
        this.isLoading = true;
        getMessages({ threadId, pageSize: 200 })
            .then(data => {
                const list = Array.isArray(data) ? data.map(m => ({
                    id: m.id,
                    fromMe: !!m.fromMe,
                    text: m.text || '',
                    time: m.timeLabel || ''
                })) : [];
                this.messagesState = { ...this.messagesState, [threadId]: list };
                this.isLoading = false;
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenChatV2Controller.getMessages error', err);
                if (!this.messagesState[threadId]) {
                    this.messagesState = { ...this.messagesState, [threadId]: [] };
                }
                this.isLoading = false;
            });
    }

    // Map server DTO -> the shape the existing template expects.
    _mapThread(t) {
        return {
            id: t.id,
            name: t.name || '',
            lastMsg: t.lastMsg || '',
            time: t.timeLabel || '',
            unread: t.unread || 0,
            initial: t.initial || (t.name || ' ').charAt(0).toUpperCase(),
            color: t.color || '#3061FF',
            online: !!t.online,
            group: !!t.isGroup
        };
    }

    get filteredThreads() {
        const q = (this.searchQ || '').trim().toLowerCase();
        if (!q) return this.threadsState;
        return this.threadsState.filter(t => (t.name || '').toLowerCase().includes(q) || (t.lastMsg || '').toLowerCase().includes(q));
    }

    get threads() {
        return this.filteredThreads.map(t => ({
            ...t,
            threadClass: t.id === this.activeId ? 'thread thread--active' : 'thread',
            avatarStyle: `background:${t.color};color:#fff;`,
            // Defensive: accept truthy numeric counts; treat strings sanely.
            showUnread: Number(t.unread) > 0
        }));
    }
    get hasThreads() { return this.filteredThreads.length > 0; }
    get hasMessages() { return ((this.messagesState && this.messagesState[this.activeId]) || []).length > 0; }

    get activeThread() {
        return this.threadsState.find(t => t.id === this.activeId) || this.threadsState[0] || { name: '', color: '#3061FF', initial: '', online: false };
    }
    get activeName() { return this.activeThread.name; }
    get activeStatus() { return this.activeThread.online ? 'Online' : 'Offline'; }
    get activeAvatarStyle() { return `background:${this.activeThread.color};color:#fff;`; }
    get activeInitial() { return this.activeThread.initial; }

    get messages() {
        const list = this.messagesState[this.activeId] || [];
        return list.map(m => ({ ...m, msgClass: m.fromMe ? 'msg msg--out' : 'msg msg--in' }));
    }

    handleSearch(event) { this.searchQ = event.detail.value; }

    handleSelect(event) {
        const id = event.detail.id;
        if (!id || id === this.activeId) return;
        this.activeId = id;
        this.syncUrl();
        this.threadsState = this.threadsState.map(t => t.id === id ? { ...t, unread: 0 } : t);
        // Fetch (or refresh) messages for this thread, then mark read server-side.
        this.loadMessages(id);
        markRead({ threadId: id }).catch(err => {
            // eslint-disable-next-line no-console
            console.error('KenChatV2Controller.markRead error', err);
        });
    }

    handleDraft(event) { this.draft = event.detail.value; }

    handleSend() {
        const text = (this.draft || '').trim();
        if (!text || !this.activeId) return;
        const threadId = this.activeId;
        const tempId = 'tmp-' + Date.now();
        const list = this.messagesState[threadId] || [];
        const optimistic = { id: tempId, fromMe: true, text, time: 'Just now' };
        this.messagesState = { ...this.messagesState, [threadId]: [...list, optimistic] };
        this.threadsState = this.threadsState.map(t => t.id === threadId ? { ...t, lastMsg: `You: ${text}`, time: 'Just now' } : t);
        this.draft = '';
        sendMessage({ threadId, body: text })
            .then(newId => {
                const cur = this.messagesState[threadId] || [];
                this.messagesState = {
                    ...this.messagesState,
                    [threadId]: cur.map(m => m.id === tempId ? { ...m, id: newId } : m)
                };
                this._showToast('Message sent');
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenChatV2Controller.sendMessage error', err);
                this._showToast((err && err.body && err.body.message) || 'Could not send message');
            });
    }

    handleNewChat() {
        // Send the user to the Alumni Network where they can pick a contact;
        // the network page seeds the chat handoff in sessionStorage and returns to /chat.
        try { window.location.assign(basePath + '/network'); } catch (e) { /* ignore */ }
    }
    handleCall()    { this._showToast(`Calling ${this.activeName}...`); }
    handleVideo()   { this._showToast(`Starting video with ${this.activeName}...`); }
    handleMore()    { this._showToast('Chat options'); }
    handleAttach()  { this._showToast('Attach a file'); }

    _showToast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }

    disconnectedCallback() {
        if (this._toastTimer) clearTimeout(this._toastTimer);
    }
}