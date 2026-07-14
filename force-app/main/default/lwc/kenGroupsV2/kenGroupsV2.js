// V2 wiring — calls OLD KenGroupsController. Do not modify the OLD controller.
// If a DTO shape mismatch breaks rendering, fix it in this file's mapDto(), not in the controller.
// Imperative (not @wire) because OLD methods aren't consistently cacheable=true and LWR rejects
// non-cacheable methods in @wire. Mock data below stays as fallback so the page never blanks.
import { LightningElement, track } from 'lwc';
import getGroupsData from '@salesforce/apex/KenGroupsController.getGroupsData';
import getGroupDetail from '@salesforce/apex/KenGroupsController.getGroupDetail';
import joinGroup from '@salesforce/apex/KenGroupsController.joinGroup';
import leaveGroup from '@salesforce/apex/KenGroupsController.leaveGroup';
import createGroup from '@salesforce/apex/KenGroupsController.createGroup';
import approveJoinRequest from '@salesforce/apex/KenGroupsController.approveJoinRequest';
import rejectJoinRequest from '@salesforce/apex/KenGroupsController.rejectJoinRequest';
import sendInvite from '@salesforce/apex/KenGroupsController.sendInvite';
import getGroupUpdates from '@salesforce/apex/KenGroupsController.getGroupUpdates';
import getGroupEvents from '@salesforce/apex/KenGroupsController.getGroupEvents';
import getGroupMembersDecorated from '@salesforce/apex/KenGroupsController.getGroupMembersDecorated';

const SF_ID_RE = /^[a-zA-Z0-9]{15,18}$/;

// Shared helpers (mirrored from kenNetworkPageV2 — identical signature so child decorate paths stay uniform).
function formatDate(iso, withTime = false) {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const opts = { day: '2-digit', month: 'short', year: 'numeric' };
    if (withTime) { opts.hour = '2-digit'; opts.minute = '2-digit'; opts.hour12 = true; }
    return d.toLocaleDateString('en-IN', opts);
}
function safeImg(url) {
    if (!url || typeof url !== 'string') return null;
    if (/^https?:\/\//i.test(url) || url.charAt(0) === '/') return url;
    return null;
}
const asBoolG = (v) => v === true || v === 'true';

/* Mock arrays kept as empty placeholders. Real data comes from KenGroupsController.
   UPDATES/EVENTS/MEMBERS are now sourced per-group via the imperative loaders below;
   the top-of-page "Latest Updates" feed (filteredUpdates) currently has no aggregator,
   so it falls back to empty until a multi-group updates query is added. */
const MOCK_GROUPS = [];
const CREATED_IDS = [];

export default class KenGroupsV2 extends LightningElement {
    // Default to 'discover' so the user lands on the real groups grid.
    @track activeTopTab = 'discover';
    @track activeCategory = 'All';
    @track selectedGroupId = null;
    @track view = 'main'; // 'main' | 'detail'
    @track showCreate = false;
    @track joinedIds = [];
    @track searchQuery = '';
    @track toastVisible = false;
    @track toastMessage = '';
    @track toastVariant = 'success';
    @track showInviteModal = false;
    @track inviteGroupId = null;
    @track inviteGroupName = '';
    _toastTimer;

    /* ===== OLD Apex wiring (KenGroupsController.getGroupsData) =====
       Start empty + loading so no mock flash; mock only used in catch fallback. */
    @track groupsState = [];
    @track isLoading = true;
    @track groupsError = null;
    @track detailGroupOverride = null; // populated by getGroupDetail when a SF id is clicked

    /* Per-group sub-tab data, refreshed every time a different group is opened. */
    @track groupUpdates = [];
    @track groupEvents = [];
    @track groupMembers = [];
    @track groupTabLoading = true;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const view = params.get('view');
            const id = params.get('id');
            const VALID_TABS = ['discover', 'joined', 'created'];
            const VALID_VIEWS = ['main', 'detail'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.activeTopTab = tab;
            if (view && VALID_VIEWS.indexOf(view) > -1) this.view = view;
            if (id) this.selectedGroupId = id;
        } catch (e) { /* ignore */ }
        this.loadGroups();
        // Deep-link case: ?view=detail&id=<sfId> — fire sub-tab loaders so the page isn't blank.
        if (this.view === 'detail' && this.selectedGroupId) {
            this.loadGroupSubTabs(this.selectedGroupId);
        }
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeTopTab) params.set('tab', this.activeTopTab); else params.delete('tab');
            if (this.view && this.view !== 'main') params.set('view', this.view); else params.delete('view');
            if (this.selectedGroupId) params.set('id', String(this.selectedGroupId)); else params.delete('id');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    loadGroups() {
        this.isLoading = true;
        getGroupsData()
            .then(data => {
                const mapped = this.mapDto(data) || [];
                this.groupsState = mapped;
                this.joinedIds = mapped.filter(g => g.joined).map(g => g.id);
                this.groupsError = null;
                this.isLoading = false;
            })
            .catch(err => {
                // Apex failed — empty state, no mock flash.
                this.groupsError = err;
                this.groupsState = [];
                this.joinedIds = [];
                this.isLoading = false;
                // eslint-disable-next-line no-console
                console.error('KenGroupsController.getGroupsData error', err);
            });
    }

    get hasGroups() { return (this.groupsState || []).length > 0; }
    get showEmptyState() { return !this.isLoading && !this.hasGroups && !this.groupsError; }

    // Translate OLD GroupDataResponse → existing GROUPS shape used by templates.
    mapDto(dto) {
        if (!dto) return [];
        const seen = new Set();
        const out = [];
        const pushRow = (row) => {
            if (!row || !row.id || seen.has(row.id)) return;
            seen.add(row.id);
            out.push({
                id: row.id,
                name: row.name || '',
                category: row.category || '',
                visibility: row.isPublic ? 'Public' : (row.groupType || 'Private'),
                members: Number(row.memberCount) || 0,
                posts: Number(row.postCount) || 0,
                description: row.description || '',
                rules: (row.rules || '').split(/\r?\n/).filter(Boolean),
                created: formatDate(row.createdDate, false),
                cover: 'linear-gradient(135deg,#3061FF,#9747FF)',
                image: safeImg(row.bannerImage),
                joined: asBoolG(row.isJoined),
                isCreated: asBoolG(row.isCreated),
                isPending: asBoolG(row.isPending),
                memberRecordId: row.memberRecordId || null,
                createdByName: row.createdByName || ''
            });
        };
        (dto.joinedGroups   || []).forEach(pushRow);
        (dto.createdGroups  || []).forEach(pushRow);
        (dto.discoverGroups || []).forEach(pushRow);
        (dto.suggestedGroups|| []).forEach(pushRow);
        return out;
    }

    disconnectedCallback() { if (this._toastTimer) clearTimeout(this._toastTimer); }

    /* Lists */
    get filteredGroups() {
        const q = (this.searchQuery || '').toLowerCase().trim();
        let list = this.groupsState;
        if (this.activeCategory !== 'All') list = list.filter(g => g.category === this.activeCategory);
        if (q) list = list.filter(g => ((g.name || '') + (g.description || '')).toLowerCase().indexOf(q) >= 0);
        return list.map(g => ({ ...g, joined: this.joinedIds.indexOf(g.id) !== -1 }));
    }
    get filteredUpdates() {
        // No cross-group aggregator yet — the top-of-page feed stays empty until one is added.
        let list = [];
        if (this.activeTopTab === 'joined') list = list.filter(u => u.origin === 'joined');
        else if (this.activeTopTab === 'created') list = list.filter(u => u.origin === 'created');
        return list;
    }
    get feedTitle() {
        if (this.activeTopTab === 'joined') return 'Updates from Joined Groups';
        if (this.activeTopTab === 'created') return 'Updates from Created Groups';
        return 'Latest Updates from your Groups';
    }
    get joinedGroups() {
        return this.groupsState.filter(g => this.joinedIds.indexOf(g.id) !== -1);
    }
    get createdGroups() {
        // Prefer server-tagged isCreated when present; fall back to mock CREATED_IDS for legacy data.
        const hasServerFlag = this.groupsState.some(g => g && g.isCreated === true);
        if (hasServerFlag) return this.groupsState.filter(g => g.isCreated === true);
        return this.groupsState.filter(g => CREATED_IDS.indexOf(g.id) !== -1);
    }

    // Router state — purely about which view is rendered. Mutually exclusive.
    get viewState() {
        return {
            isMainDashboard: this.view === 'main',
            isGroupDetail:   this.view === 'detail'
        };
    }
    // Tab state lives separately so getters don't conflate "which tab" with "which route".
    get tabState() {
        return {
            isDiscover: this.activeTopTab === 'discover',
            isJoined:   this.activeTopTab === 'joined',
            isCreated:  this.activeTopTab === 'created'
        };
    }
    get showRail() { return this.view === 'main'; }

    get isDiscoverTab() { return this.activeTopTab === 'discover'; }
    get hasUpdates() { return this.filteredUpdates.length > 0; }
    get emptyFeedMessage() {
        if (this.activeTopTab === 'created') return 'No updates from your created groups yet';
        if (this.activeTopTab === 'joined') return 'No updates from your joined groups yet';
        return 'No updates to show';
    }
    get detailGroup() {
        const base = this.groupsState.find(g => g.id === this.selectedGroupId) || null;
        if (!base) return null;
        // Merge the rich getGroupDetail() payload over the summary row when available.
        return this.detailGroupOverride ? { ...base, ...this.detailGroupOverride } : base;
    }
    get isDetailJoined() {
        return !!(this.detailGroup && this.joinedIds.indexOf(this.detailGroup.id) !== -1);
    }
    get detailEvents() { return this.groupEvents; }
    get detailMembers() { return this.groupMembers; }
    get detailFeed() { return this.groupUpdates; }

    get toastClass() { return `pp-toast pp-toast--${this.toastVariant}`; }

    _toast(message, variant = 'success') {
        this.toastMessage = message;
        this.toastVariant = variant;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }

    /* Handlers from children */
    handleTabChange(event) { this.activeTopTab = event.detail.id; this.syncUrl(); }
    handleCategoryChange(event) { this.activeCategory = event.detail.id; }
    handleSearch(event) { this.searchQuery = event.detail.value; }

    loadGroupSubTabs(groupId) {
        // Resets and fires the three detail-tab loaders in parallel. Each guards against
        // a stale response by checking the request id matches the currently selected group.
        if (!groupId || !SF_ID_RE.test(String(groupId))) {
            this.groupUpdates = [];
            this.groupEvents = [];
            this.groupMembers = [];
            this.groupTabLoading = false;
            return;
        }
        this.groupTabLoading = true;
        this.groupUpdates = [];
        this.groupEvents = [];
        this.groupMembers = [];
        const reqId = groupId;
        Promise.all([
            getGroupUpdates({ groupId }).catch(err => { console.error('getGroupUpdates error', err); return []; }),
            getGroupEvents({ groupId }).catch(err => { console.error('getGroupEvents error', err); return []; }),
            getGroupMembersDecorated({ groupId }).catch(err => { console.error('getGroupMembersDecorated error', err); return []; })
        ]).then(([updates, events, members]) => {
            if (this.selectedGroupId !== reqId) return; // user navigated away — drop stale results
            // `date` and `time` are reserved identifiers in Apex; the controller exposes them as
            // dateLabel / timeLabel. Remap here so the existing detail templates (which read
            // .date and .time) stay unchanged.
            const upd = Array.isArray(updates) ? updates : [];
            const evs = Array.isArray(events)  ? events  : [];
            this.groupUpdates = upd.map(u => ({ ...u, time: u.timeLabel || u.createdLabel || '' }));
            this.groupEvents  = evs.map(e => ({ ...e, date: e.dateLabel || '', time: e.timeLabel || '' }));
            this.groupMembers = Array.isArray(members) ? members : [];
            this.groupTabLoading = false;
        });
    }

    handleOpenGroup(event) {
        const id = event.detail && event.detail.id ? event.detail.id : event.detail;
        const found = this.groupsState.find(g => g.id === id);
        if (!found) return;
        this.selectedGroupId = id;
        this.detailGroupOverride = null;
        this.loadGroupSubTabs(id);
        // If id looks like a Salesforce Id, imperatively fetch the rich detail and merge it.
        if (typeof id === 'string' && SF_ID_RE.test(id)) {
            getGroupDetail({ groupId: id })
                .then(detail => {
                    if (detail) {
                        this.detailGroupOverride = {
                            id: detail.id,
                            name: detail.name || found.name,
                            description: detail.description || found.description,
                            rules: (detail.rules || '').split(/\r?\n/).filter(Boolean),
                            category: detail.category || found.category,
                            visibility: detail.isPublic ? 'Public' : (detail.groupType || found.visibility),
                            members: Number(detail.memberCount) || Number(found.members) || 0,
                            image: safeImg(detail.bannerImage) || found.image,
                            created: formatDate(detail.createdDate, false) || found.created,
                            joined: asBoolG(detail.isJoined),
                            isPending: asBoolG(detail.isPending),
                            isCreated: asBoolG(detail.isCreated),
                            memberRecordId: detail.memberRecordId || null,
                            createdByName: detail.createdByName || found.createdByName
                        };
                    }
                })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenGroupsController.getGroupDetail error', err);
                });
        }
        this._scrollY = (typeof window !== 'undefined' && window.scrollY) || 0;
        this.view = 'detail';
        this.syncUrl();
        try { window.scrollTo({ top: 0, behavior: 'instant' }); } catch (e) { window.scrollTo(0, 0); }
    }
    _restoreScroll() {
        const y = this._scrollY || 0;
        try { requestAnimationFrame(() => { try { window.scrollTo(0, y); } catch (e) { /* ignore */ } }); }
        catch (e) { try { window.scrollTo(0, y); } catch (_) { /* ignore */ } }
    }
    handleCloseDetail() {
        this.selectedGroupId = null;
        this.view = 'main';
        this.syncUrl();
        this._restoreScroll();
    }
    handleBackToMain() {
        this.view = 'main';
        this.selectedGroupId = null;
        this.syncUrl();
        this._restoreScroll();
    }

    handleJoin(event) {
        const id = event.detail.id;
        const prev = this.joinedIds;
        if (this.joinedIds.indexOf(id) === -1) {
            this.joinedIds = [...this.joinedIds, id];
        }
        if (!SF_ID_RE.test(String(id))) {
            this._toast('Joined group successfully', 'success');
            return;
        }
        joinGroup({ groupId: id })
            .then(() => { this._toast('Joined group successfully', 'success'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGroupsController.joinGroup error', err);
                this.joinedIds = prev;
                this._toast((err && err.body && err.body.message) || 'Could not join. Please try again.', 'error');
            });
    }
    handleLeave(event) {
        const id = event.detail.id;
        const prev = this.joinedIds;
        this.joinedIds = this.joinedIds.filter(x => x !== id);
        if (!SF_ID_RE.test(String(id))) {
            this._toast('You left the group', 'info');
            return;
        }
        // leaveGroup wants the memberRecordId, not the groupId. Look it up from server-side data.
        const group = this.groupsState.find(g => g.id === id);
        const memberRecordId = group && group.memberRecordId;
        if (!memberRecordId) {
            // Couldn't resolve member record — keep optimistic update + warn (TODO: surface from getGroupsData).
            this._toast('You left the group (offline)', 'info');
            return;
        }
        leaveGroup({ memberRecordId })
            .then(() => { this._toast('You left the group', 'info'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGroupsController.leaveGroup error', err);
                this.joinedIds = prev;
                this._toast((err && err.body && err.body.message) || 'Could not leave. Please try again.', 'error');
            });
    }

    handleOpenCreate() { this.showCreate = true; }
    handleCloseCreate() { this.showCreate = false; }
    handleSubmitCreate(event) {
        const d = (event && event.detail) || {};
        const name = (d.name || '').trim();
        if (!name) {
            this._toast('Please enter a group name', 'error');
            return;
        }
        const groupType = d.visibility === 'private' ? 'Private' : 'Public';
        const description = d.desc || '';
        const category = ''; // free-form audience not part of OLD category enum — leave empty
        const bannerUrl = d.bannerUrl || '';
        // Audience selection now comes from the shared audience builder as a JSON string.
        // Captured here for the create flow; server-side persistence is a follow-up (the
        // current createGroup Apex signature does not yet accept an audience field, so we
        // do NOT pass it as a named arg — that would break the Apex call).
        const audienceData = d.audienceData || null;
        // eslint-disable-next-line no-console
        console.log('[Groups] create — captured audience:', audienceData);
        createGroup({ name, description, groupType, category, bannerUrl, batchesCsv: '' })
            .then(() => {
                this.showCreate = false;
                this._toast('Group submitted for review', 'success');
                // Refresh groups so the newly created group lands in createdGroups.
                this.loadGroups();
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGroupsController.createGroup error', err);
                this.showCreate = false;
                this._toast((err && err.body && err.body.message) || 'Could not create group. Please try again.', 'error');
            });
    }
    handleApproveJoin(event) {
        const memberRecordId = event && event.detail && event.detail.memberRecordId;
        if (!memberRecordId || !SF_ID_RE.test(String(memberRecordId))) {
            this._toast('Member approved', 'success');
            return;
        }
        approveJoinRequest({ memberRecordId })
            .then(() => { this._toast('Member approved', 'success'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGroupsController.approveJoinRequest error', err);
                this._toast((err && err.body && err.body.message) || 'Could not approve.', 'error');
            });
    }
    handleSendInvite(event) {
        const d = (event && event.detail) || {};
        const groupId = d.groupId || this.selectedGroupId;
        const accountId = d.accountId;
        if (!SF_ID_RE.test(String(groupId)) || !SF_ID_RE.test(String(accountId))) {
            this._toast('Invite sent', 'success');
            return;
        }
        sendInvite({ groupId, accountId })
            .then(() => { this._toast('Invite sent', 'success'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGroupsController.sendInvite error', err);
                this._toast((err && err.body && err.body.message) || 'Could not send invite.', 'error');
            });
    }
    handleRejectJoin(event) {
        const memberRecordId = event && event.detail && event.detail.memberRecordId;
        if (!memberRecordId || !SF_ID_RE.test(String(memberRecordId))) {
            this._toast('Request rejected', 'info');
            return;
        }
        rejectJoinRequest({ memberRecordId })
            .then(() => { this._toast('Request rejected', 'info'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGroupsController.rejectJoinRequest error', err);
                this._toast((err && err.body && err.body.message) || 'Could not reject.', 'error');
            });
    }
    handleOpenInvite(event) {
        const groupId = (event && event.detail && event.detail.groupId) || this.selectedGroupId;
        const group = this.groupsState.find(g => g.id === groupId) || {};
        this.inviteGroupId = groupId;
        this.inviteGroupName = group.name || '';
        this.showInviteModal = true;
    }
    handleCloseInvite() {
        this.showInviteModal = false;
        this.inviteGroupId = null;
        this.inviteGroupName = '';
    }
    handleInviteSend(event) {
        const tokens = (event && event.detail && event.detail.tokens) || [];
        const groupId = this.inviteGroupId;
        const sfTokens = tokens.filter(t => SF_ID_RE.test(String(t)));
        const otherCount = tokens.length - sfTokens.length;
        this.showInviteModal = false;
        if (!SF_ID_RE.test(String(groupId)) || sfTokens.length === 0) {
            // No real SF context — keep mock behaviour, ack the user.
            this._toast(`Invites queued (${tokens.length})`, 'success');
            this.inviteGroupId = null;
            this.inviteGroupName = '';
            return;
        }
        // sendInvite is per-account; loop through valid SF Ids.
        const calls = sfTokens.map(accountId =>
            sendInvite({ groupId, accountId }).then(() => true).catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenGroupsController.sendInvite error', err);
                return false;
            })
        );
        Promise.all(calls).then(results => {
            const ok = results.filter(Boolean).length;
            const failed = results.length - ok;
            let msg = `${ok} invite${ok === 1 ? '' : 's'} sent`;
            if (failed) msg += `, ${failed} failed`;
            if (otherCount) msg += ` · ${otherCount} skipped (not a valid alumni Id)`;
            this._toast(msg, failed ? 'error' : 'success');
            this.inviteGroupId = null;
            this.inviteGroupName = '';
        });
    }
    handleValidationError(event) { this._toast(event.detail.message, 'error'); }

    handleViewAll() { this.activeTopTab = 'joined'; this.syncUrl(); }
    handleDiscover() { this.activeTopTab = 'discover'; this.syncUrl(); }
}