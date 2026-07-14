import { LightningElement, api, track } from 'lwc';

const TABS = [
    { id: 'about', label: 'About' },
    { id: 'feed', label: 'Feed' },
    { id: 'events', label: 'Events' },
    { id: 'members', label: 'Members' }
];

export default class KenGroupDetailPageV2 extends LightningElement {
    @api group;
    @api joined = false;
    @api feed = [];
    @api updates = [];
    @api events = [];
    @api members = [];
    @api isLoadingSubTabs = false;

    @track activeTab = 'about';

    get tabs() {
        return TABS.map(t => ({ ...t, cssClass: t.id === this.activeTab ? 'tab tab--active' : 'tab' }));
    }
    get isAbout() { return this.activeTab === 'about'; }
    get isFeed() { return this.activeTab === 'feed'; }
    get isEvents() { return this.activeTab === 'events'; }
    get isMembers() { return this.activeTab === 'members'; }

    get decoratedGroup() {
        if (!this.group) return null;
        // Coerce members defensively — Apex sometimes returns string counts, and undefined .toLocaleString() throws.
        const members = Number(this.group.members) || 0;
        const cover = this.group.cover || 'linear-gradient(135deg,#3061FF,#9747FF)';
        return {
            ...this.group,
            coverStyle: `background:${cover}`,
            initial: (this.group.name || '?').charAt(0).toUpperCase(),
            membersLabel: `${members.toLocaleString()} members`,
            joinLabel: this.joined ? 'Leave Group' : 'Join Group',
            joinClass: this.joined ? 'btn btn--outline' : 'btn btn--primary',
            metaLine: `${this.group.category || ''} · ${this.group.visibility || ''} · ${members.toLocaleString()} members`,
            rulesList: (this.group.rules || []).map((r, i) => ({ id: i, text: r }))
        };
    }

    get canInvite() {
        // Group creator/admin can invite. We accept either an `isCreated` server flag or an explicit `isAdmin` flag.
        const g = this.group || {};
        return g.isCreated === true || g.isAdmin === true;
    }
    get pendingMembers() {
        return (this.members || []).filter(m => {
            const s = (m && m.status ? String(m.status) : '').toLowerCase();
            return s === 'pending' || s === 'requested' || s === 'awaiting approval';
        }).map(m => ({ ...m, avatarStyle: `background:${m.color || 'linear-gradient(135deg,#3061FF,#67A1C8)'}` }));
    }
    get approvedMembers() {
        return (this.members || []).filter(m => {
            const s = (m && m.status ? String(m.status) : '').toLowerCase();
            return !s || s === 'approved' || s === 'active' || s === 'joined';
        });
    }
    get hasPendingMembers() { return this.pendingMembers.length > 0; }

    // Prefer the new `updates` @api input (server-driven). Fall back to legacy `feed` so
    // older callers that still pass `feed=...` keep rendering until they migrate.
    get _activeUpdates() {
        if (Array.isArray(this.updates) && this.updates.length > 0) return this.updates;
        if (Array.isArray(this.feed) && this.feed.length > 0) return this.feed;
        return [];
    }
    get feedDecorated() {
        return (this._activeUpdates || []).map(u => ({
            ...u,
            // u.author can be null — guard charAt() to avoid blowing up the whole feed render.
            initial: (u && u.author ? String(u.author).charAt(0) : '?').toUpperCase(),
            tagsJoined: u && u.tags ? u.tags.join(' ') : '',
            commentsLabel: `${Number(u && u.comments) || 0} comments`
        }));
    }
    get hasUpdates() { return this.feedDecorated.length > 0; }
    get hasEvents() { return (this.events || []).length > 0; }
    get hasMembers() { return this.membersDecorated.length > 0; }
    get showFeedEmpty() { return !this.isLoadingSubTabs && !this.hasUpdates; }
    get showEventsEmpty() { return !this.isLoadingSubTabs && !this.hasEvents; }
    get showMembersEmpty() { return !this.isLoadingSubTabs && !this.hasMembers; }
    get eventsDecorated() {
        return (this.events || []).map(e => ({ ...e, coverStyle: `background:${(e && e.cover) || 'linear-gradient(135deg,#3061FF,#9747FF)'}` }));
    }
    get membersDecorated() {
        // m.color may be undefined — fall back to a deterministic default instead of "background:undefined".
        return this.approvedMembers.map(m => ({ ...m, avatarStyle: `background:${(m && m.color) || 'linear-gradient(135deg,#3061FF,#67A1C8)'}` }));
    }

    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.id;
    }
    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }
    handleJoin() {
        const name = this.joined ? 'leave' : 'join';
        this.dispatchEvent(new CustomEvent(name, { detail: { id: this.group ? this.group.id : null } }));
    }
    handleOpenInvite() {
        this.dispatchEvent(new CustomEvent('openinvite', { detail: { groupId: this.group ? this.group.id : null } }));
    }
    handleApprovePending(event) {
        const memberRecordId = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('approvejoin', { detail: { memberRecordId } }));
    }
    handleRejectPending(event) {
        const memberRecordId = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('rejectjoin', { detail: { memberRecordId } }));
    }
}